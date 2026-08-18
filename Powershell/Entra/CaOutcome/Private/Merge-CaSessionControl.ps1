function Merge-CaSessionControl {
    <#
    .SYNOPSIS
        Merges the session controls of every applying policy into one set, reporting
        disagreements

    .DESCRIPTION
        Session controls from separate policies stack: a sign-in frequency from one and a
        persistent browser setting from another both apply. The interesting case is two policies
        setting the same control to different values, which is common and easy to create by
        accident - the tenant this was built against does it today, with an "always" persistent
        browser from the tenant-wide MFA policy meeting a "never" from the unjoined-device
        policy on the same sign-in.

        Microsoft documents that the aggregate of matching policies is the most restrictive
        combination, and that is applied here for the two controls where restrictiveness has a
        defensible ordering. It is deliberately not guessed at for the rest: Microsoft does not
        document a precedence for every session control, and inventing one would produce an
        outcome that looks authoritative and is not.

        So every disagreement is reported in Conflicts whether or not it could be resolved. A
        resolved conflict still matters, because it means the outcome depends on precedence
        rather than on intent, and that is worth a human deciding about. An unresolved one keeps
        the first value seen and marks Resolved false, so a caller can fail a test on it rather
        than trust a coin toss.

    .PARAMETER Contribution
        The contributions from Resolve-CaSessionControl across all applying policies.

    .OUTPUTS
        PSCustomObject with Controls (one property per control, holding the winning value) and
        Conflicts (one entry per control more than one policy disagreed about).

    .EXAMPLE
        $merged = Merge-CaSessionControl -Contribution $allContributions
        $merged.Conflicts | Where-Object { -not $_.Resolved }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$Contribution
    )

    $controls = [ordered]@{}
    $conflicts = New-Object System.Collections.Generic.List[object]

    $grouped = $Contribution | Where-Object { $null -ne $_ } | Group-Object -Property Control

    foreach ($group in ($grouped | Sort-Object Name)) {
        $items = @($group.Group)
        $distinctValues = @($items | Select-Object -ExpandProperty Value -Unique)

        if ($distinctValues.Count -le 1) {
            $controls[$group.Name] = $items[0].Value
            continue
        }

        # Every contributor can be ranked, so most restrictive wins and the conflict is
        # resolved. Value breaks a tie, so two equally restrictive settings do not pick a
        # winner from whatever order Graph happened to return the policies in.
        $ranked = @($items | Where-Object { $null -ne $_.RestrictivenessRank })
        $resolved = $false

        # Sorted rather than first-seen, and that is not cosmetic. Graph does not guarantee
        # the order of policies in a response, so first-seen makes the winner - and
        # therefore the stored baseline - non-deterministic, and a run against an unchanged
        # tenant reports drift. Found exactly that way: two policies disagreeing about
        # cloudAppSecurity flagged 2 of 24 scenarios as changed when nothing had changed.
        $winner = @($items | Sort-Object -Property Value)[0]

        if ($ranked.Count -eq $items.Count) {
            $winner = @($ranked | Sort-Object -Property RestrictivenessRank, Value)[0]
            $resolved = $true
        }

        $controls[$group.Name] = $winner.Value

        $conflicts.Add([PSCustomObject]@{
            PSTypeName = 'CaOutcome.SessionConflict'
            Control    = $group.Name
            Values     = @($distinctValues | Sort-Object)
            Winner     = $winner.Value
            Resolved   = $resolved
            Policies   = @($items | ForEach-Object {
                [PSCustomObject]@{
                    PolicyId   = $_.PolicyId
                    PolicyName = $_.PolicyName
                    Value      = $_.Value
                }
            })
        })
    }

    return [PSCustomObject]@{
        PSTypeName = 'CaOutcome.SessionControlSet'
        Controls   = [PSCustomObject]$controls
        Conflicts  = $conflicts.ToArray()
    }
}