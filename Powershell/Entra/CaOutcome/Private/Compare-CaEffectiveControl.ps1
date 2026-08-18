function Compare-CaEffectiveControl {
    <#
    .SYNOPSIS
        Diffs two effective outcomes and describes what changed between them

    .DESCRIPTION
        The whole point of holding two worlds is this comparison. Being told that six policies
        apply is not actionable; being told that promoting the three report-only ones turns a
        granted sign-in into a blocked one, for this user on this platform, is.

        The diff is written against effective outcomes rather than against policy lists on
        purpose. Two policies can change while the outcome does not - a second policy requiring
        MFA when MFA is already required changes nothing the user will notice - and an outcome
        can change while the policy set looks stable, which is what happens when a group
        membership moves someone into scope. Diffing outcomes keeps the noise out and catches
        the second case, which is the one config comparison cannot see at all.

        Direction matters and is not symmetric in meaning: From is the baseline, To is the
        candidate. Promoting report-only policies can only add policies to the applying set, so
        Removed collections are normally empty in that direction. They are computed anyway,
        because the same function is what compares a stored baseline against a later run, and
        there requirements genuinely do disappear.

    .PARAMETER From
        The baseline outcome from Get-CaEffectiveControl.

    .PARAMETER To
        The candidate outcome from Get-CaEffectiveControl.

    .OUTPUTS
        PSCustomObject describing the change, with HasChange as the single field a test would
        assert on.

    .EXAMPLE
        $delta = Compare-CaEffectiveControl -From $current -To $projected
        if ($delta.HasChange) { $delta.Summary }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$From,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$To
    )

    $fromRequired = @($From.RequiredControls)
    $toRequired = @($To.RequiredControls)

    $addedRequired = @($toRequired | Where-Object { $fromRequired -notcontains $_ })
    $removedRequired = @($fromRequired | Where-Object { $toRequired -notcontains $_ })

    $fromBlockIds = @($From.BlockedBy | ForEach-Object { $_.PolicyId })
    $newlyBlockedBy = @($To.BlockedBy | Where-Object { $fromBlockIds -notcontains $_.PolicyId })

    # A choice is identified by its policy and its option set, so reordering the options is not
    # mistaken for a different choice
    $choiceKey = { param($Choice) "$($Choice.PolicyId)|$(($Choice.AnyOf | Sort-Object) -join ',')" }
    $fromChoiceKeys = @($From.OptionalChoices | ForEach-Object { & $choiceKey $_ })
    $addedChoices = @($To.OptionalChoices | Where-Object {
        $fromChoiceKeys -notcontains (& $choiceKey $_)
    })

    # Session controls are compared by name so that a control appearing, disappearing or
    # changing value are three distinguishable events rather than one opaque "session differs"
    $fromSession = @{}
    if ($From.SessionControls) {
        foreach ($property in $From.SessionControls.PSObject.Properties) {
            $fromSession[$property.Name] = $property.Value
        }
    }
    $toSession = @{}
    if ($To.SessionControls) {
        foreach ($property in $To.SessionControls.PSObject.Properties) {
            $toSession[$property.Name] = $property.Value
        }
    }

    $addedSession = New-Object System.Collections.Generic.List[object]
    $changedSession = New-Object System.Collections.Generic.List[object]
    $removedSession = New-Object System.Collections.Generic.List[object]

    foreach ($name in ($toSession.Keys | Sort-Object)) {
        if (-not $fromSession.ContainsKey($name)) {
            $addedSession.Add([PSCustomObject]@{ Control = $name; Value = $toSession[$name] })
        } elseif ($fromSession[$name] -ne $toSession[$name]) {
            $changedSession.Add([PSCustomObject]@{
                Control = $name; From = $fromSession[$name]; To = $toSession[$name]
            })
        }
    }
    foreach ($name in ($fromSession.Keys | Sort-Object)) {
        if (-not $toSession.ContainsKey($name)) {
            $removedSession.Add([PSCustomObject]@{ Control = $name; Value = $fromSession[$name] })
        }
    }

    # A custom authentication strength is editable, and editing one changes what every policy
    # referencing it requires while every policy document stays identical. Comparing the
    # strength's name would see nothing, so its combinations are compared instead. Combinations
    # added is a weakening - more ways to get in - and removed is a tightening.
    $fromStrengths = @{}
    foreach ($strength in @($From.AuthenticationStrengths)) {
        if ($strength) { $fromStrengths[[string]$strength.Control] = $strength }
    }

    $weakened = New-Object System.Collections.Generic.List[object]
    $strengthened = New-Object System.Collections.Generic.List[object]

    foreach ($strength in @($To.AuthenticationStrengths)) {
        if (-not $strength) { continue }
        $key = [string]$strength.Control
        if (-not $fromStrengths.ContainsKey($key)) { continue }

        $before = @($fromStrengths[$key].AllowedCombinations)
        $after = @($strength.AllowedCombinations)

        $added = @($after | Where-Object { $before -notcontains $_ })
        $removed = @($before | Where-Object { $after -notcontains $_ })
        $configBefore = [int]$fromStrengths[$key].CombinationConfigurationCount
        $configAfter = [int]$strength.CombinationConfigurationCount

        if ($added.Count -gt 0 -or $configAfter -lt $configBefore) {
            $weakened.Add([PSCustomObject]@{
                Strength                = $strength.DisplayName
                Control                 = $key
                AddedCombinations       = $added
                RemovedConfigurations   = [math]::Max(0, $configBefore - $configAfter)
            })
        }
        if ($removed.Count -gt 0 -or $configAfter -gt $configBefore) {
            $strengthened.Add([PSCustomObject]@{
                Strength                = $strength.DisplayName
                Control                 = $key
                RemovedCombinations     = $removed
                AddedConfigurations     = [math]::Max(0, $configAfter - $configBefore)
            })
        }
    }

    $fromPolicyIds = @($From.AppliedPolicies | ForEach-Object { $_.Id })
    $addedPolicies = @($To.AppliedPolicies | Where-Object { $fromPolicyIds -notcontains $_.Id })
    $toPolicyIds = @($To.AppliedPolicies | ForEach-Object { $_.Id })
    $removedPolicies = @($From.AppliedPolicies | Where-Object { $toPolicyIds -notcontains $_.Id })

    # The headline finding when satisfiability was evaluated: the sign-in gets in today and
    # would not after the promotion. Kept separate from AccessChanged because Access can stay
    # GrantedWithControls in both worlds while the user is locked out in one of them.
    $fromUnsatisfiableIds = @($From.UnsatisfiableRequirements | ForEach-Object { $_.PolicyId })
    $newlyUnsatisfiable = @($To.UnsatisfiableRequirements | Where-Object {
        $fromUnsatisfiableIds -notcontains $_.PolicyId
    })
    $becomesEffectivelyBlocked = ((-not $From.IsEffectivelyBlocked) -and $To.IsEffectivelyBlocked)

    $accessChanged = $From.Access -ne $To.Access

    $hasChange = $accessChanged -or $newlyUnsatisfiable.Count -gt 0 -or
        $weakened.Count -gt 0 -or $strengthened.Count -gt 0 -or
        $addedRequired.Count -gt 0 -or $removedRequired.Count -gt 0 -or
        $addedChoices.Count -gt 0 -or $newlyBlockedBy.Count -gt 0 -or
        $addedSession.Count -gt 0 -or $changedSession.Count -gt 0 -or $removedSession.Count -gt 0

    $parts = New-Object System.Collections.Generic.List[string]
    if ($becomesEffectivelyBlocked) {
        $parts.Add('LOCKS OUT this sign-in')
    }
    if ($accessChanged) { $parts.Add("access $($From.Access) -> $($To.Access)") }
    if ($newlyBlockedBy.Count -gt 0) {
        # A new blocker on an already-blocked sign-in changes nothing the user sees, so it is
        # worded to say so rather than reading like a fresh denial
        $blockWord = 'blocked by'
        if (-not $accessChanged -and $From.Access -eq 'Blocked') {
            $blockWord = 'additionally blocked by'
        }
        $names = ($newlyBlockedBy | ForEach-Object { $_.PolicyName }) -join ', '
        $parts.Add("$blockWord $names")
    }
    if ($newlyUnsatisfiable.Count -gt 0) {
        # The reason is what makes this actionable - "cannot satisfy X (compliantDevice)" says
        # what is required, where "the simulated device is not compliant" says why it fails
        $detail = ($newlyUnsatisfiable | ForEach-Object {
            $why = @($_.Reasons) -join ', '
            if ([string]::IsNullOrWhiteSpace($why)) { $why = @($_.Blockers) -join ', ' }
            "$($_.PolicyName) - $why"
        }) -join '; '
        $parts.Add("cannot satisfy $detail")
    }
    foreach ($change in $weakened) {
        $detail = @($change.AddedCombinations) -join ', '
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "$($change.RemovedConfigurations) restriction(s) removed"
        }
        $parts.Add("WEAKENED authentication strength '$($change.Strength)' now also allows $detail")
    }
    foreach ($change in $strengthened) {
        $detail = @($change.RemovedCombinations) -join ', '
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "$($change.AddedConfigurations) restriction(s) added"
        }
        $parts.Add("authentication strength '$($change.Strength)' no longer allows $detail")
    }
    if ($addedRequired.Count -gt 0) {
        $parts.Add("now requires $($addedRequired -join ', ')")
    }
    if ($removedRequired.Count -gt 0) {
        $parts.Add("no longer requires $($removedRequired -join ', ')")
    }
    if ($addedChoices.Count -gt 0) {
        $detail = ($addedChoices | ForEach-Object { $_.AnyOf -join ' or ' }) -join '; '
        $parts.Add("new choice of $detail")
    }
    if ($addedSession.Count -gt 0) {
        $detail = ($addedSession | ForEach-Object { "$($_.Control)=$($_.Value)" }) -join ', '
        $parts.Add("session adds $detail")
    }
    if ($changedSession.Count -gt 0) {
        $detail = ($changedSession | ForEach-Object {
            "$($_.Control) $($_.From)->$($_.To)"
        }) -join ', '
        $parts.Add("session changes $detail")
    }
    if ($removedSession.Count -gt 0) {
        $detail = ($removedSession | ForEach-Object { $_.Control }) -join ', '
        $parts.Add("session drops $detail")
    }

    $summary = 'No change'
    if ($parts.Count -gt 0) { $summary = $parts -join '; ' }

    return [PSCustomObject]@{
        PSTypeName                = 'CaOutcome.Delta'
        HasChange                 = $hasChange
        AccessChanged             = $accessChanged
        AccessFrom                = $From.Access
        AccessTo                  = $To.Access
        BecomesEffectivelyBlocked = $becomesEffectivelyBlocked
        NewlyUnsatisfiable        = $newlyUnsatisfiable
        WeakenedStrengths         = $weakened.ToArray()
        StrengthenedStrengths     = $strengthened.ToArray()
        NewlyBlockedBy            = $newlyBlockedBy
        AddedRequiredControls     = $addedRequired
        RemovedRequiredControls   = $removedRequired
        AddedChoices              = $addedChoices
        AddedSessionControls      = $addedSession.ToArray()
        ChangedSessionControls    = $changedSession.ToArray()
        RemovedSessionControls    = $removedSession.ToArray()
        AddedPolicies             = $addedPolicies
        RemovedPolicies           = $removedPolicies
        Summary                   = $summary
    }
}
