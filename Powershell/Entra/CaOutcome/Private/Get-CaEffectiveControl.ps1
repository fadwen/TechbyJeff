function Get-CaEffectiveControl {
    <#
    .SYNOPSIS
        Folds the policies that apply in one world into the single outcome the sign-in would
        meet

    .DESCRIPTION
        This is the piece the What If API stops short of. Graph reports, policy by policy,
        whether each one applies. It does not say what the user actually experiences when six of
        them apply at once, and that is the only thing an administrator wants to know.

        The fold follows Entra's documented evaluation. Policies are not processed in order;
        every matching policy is evaluated and the aggregate is the most restrictive
        combination. So:

        - Block wins outright. One applying policy carrying the block control ends it, and no
          combination of grants from other policies changes that.
        - Otherwise every applying policy's grant clause must be satisfied. Policies are ANDed
          with each other even though the controls inside one policy may be ORed.

        RequiredControls and OptionalChoices exist because that distinction is what makes the
        result readable. A clause is unambiguously required when its operator is AND, or when it
        offers only one control - in both cases the user has no choice about it, so it can be
        stated flatly. A clause offering several alternatives under OR cannot be flattened
        without lying, so it is kept whole as a choice. Comparing two worlds then means
        comparing a set of flat requirements plus a set of choices, rather than trying to diff
        arbitrary boolean expressions.

        A world is a set of policy states. Passing only 'enabled' gives what the tenant enforces
        today; adding 'enabledForReportingButNotEnforced' gives what it would enforce if the
        report-only policies were promoted. Both come out of one API response, because the
        response carries every policy's state alongside its verdict.

    .PARAMETER Policy
        The whatIfAnalysisResult collection, all policies, applying or not.

    .PARAMETER State
        The policy states that make up this world.

    .PARAMETER World
        A label carried onto the output, for example Current or Projected.

    .PARAMETER SignInCondition
        The signInConditions that were simulated. Optional. When supplied, each clause is
        checked against them and the ones the simulated sign-in could not possibly satisfy are
        reported, which is what separates "this policy adds a requirement" from "this policy
        locks this persona out". See Get-CaControlSatisfiability for the rules and the
        documentation each rests on.

    .OUTPUTS
        PSCustomObject with World, Access, BlockedBy, Requirements, RequiredControls,
        OptionalChoices, UnsatisfiableRequirements, IsEffectivelyBlocked, SessionControls,
        SessionConflicts and AppliedPolicies.

    .EXAMPLE
        $current = Get-CaEffectiveControl -Policy $results -State 'enabled' -World 'Current'
        $current.Access

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Policy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$State,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$World,

        [Parameter()]
        [AllowNull()]
        [object]$SignInCondition
    )

    $applied = @(@($Policy) | Where-Object {
        $null -ne $_ -and
        (Get-CaProperty -InputObject $_ -Name 'policyApplies') -eq $true -and
        $State -contains [string](Get-CaProperty -InputObject $_ -Name 'state')
    })

    $requirements = New-Object System.Collections.Generic.List[object]
    $blockedBy = New-Object System.Collections.Generic.List[object]
    $requiredControls = New-Object System.Collections.Generic.List[string]
    $optionalChoices = New-Object System.Collections.Generic.List[object]
    $sessionContributions = New-Object System.Collections.Generic.List[object]
    $unsatisfiable = New-Object System.Collections.Generic.List[object]
    $strengths = [ordered]@{}

    foreach ($item in $applied) {
        $clause = Resolve-CaGrantRequirement -Policy $item
        if ($null -ne $clause) {
            $requirements.Add($clause)

            # Keyed by control so that two policies naming the same strength collapse to one
            # entry - the strength is a tenant object, not a property of the policy
            if ($clause.ControlDetail) {
                foreach ($key in $clause.ControlDetail.Keys) {
                    if (-not $strengths.Contains($key)) {
                        $strengths[$key] = $clause.ControlDetail[$key]
                    }
                }
            }

            if ($clause.IsBlock) {
                $blockedBy.Add([PSCustomObject]@{
                    PolicyId   = $clause.PolicyId
                    PolicyName = $clause.PolicyName
                })
            } elseif ($clause.Operator -eq 'AND' -or $clause.Controls.Count -eq 1) {
                foreach ($control in $clause.Controls) {
                    if (-not $requiredControls.Contains($control)) {
                        $requiredControls.Add($control)
                    }
                }
            } else {
                $optionalChoices.Add([PSCustomObject]@{
                    PSTypeName = 'CaOutcome.GrantChoice'
                    PolicyId   = $clause.PolicyId
                    PolicyName = $clause.PolicyName
                    AnyOf      = @($clause.Controls)
                })
            }

            if (-not $clause.IsBlock -and $null -ne $SignInCondition) {
                $verdicts = @($clause.Controls | ForEach-Object {
                    Get-CaControlSatisfiability -Control $_ -SignInCondition $SignInCondition `
                        -ControlDetail $clause.ControlDetail[$_]
                })
                $blocked = @($verdicts | Where-Object { $_.Verdict -eq 'Unsatisfiable' })
                $blockers = @($blocked | ForEach-Object { $_.Control })

                # An AND clause dies on one impossible control; an OR clause only dies when
                # every alternative is impossible, which is why the clause is kept whole
                $clauseFails = $false
                if ($blockers.Count -gt 0) {
                    if ($clause.Operator -eq 'AND') {
                        $clauseFails = $true
                    } elseif ($blockers.Count -eq $clause.Controls.Count) {
                        $clauseFails = $true
                    }
                }

                if ($clauseFails) {
                    # Reasons are deduplicated because one condition commonly rules out every
                    # control in a clause at once - a legacy client defeats MFA and device
                    # state together - and repeating the sentence per control reads as several
                    # findings when it is one
                    $unsatisfiable.Add([PSCustomObject]@{
                        PSTypeName = 'CaOutcome.UnsatisfiableRequirement'
                        PolicyId   = $clause.PolicyId
                        PolicyName = $clause.PolicyName
                        Operator   = $clause.Operator
                        Controls   = @($clause.Controls)
                        Blockers   = $blockers
                        Reasons    = @($blocked | ForEach-Object { $_.Reason } |
                            Where-Object { $_ } | Select-Object -Unique)
                    })
                }
            }
        }

        foreach ($contribution in (Resolve-CaSessionControl -Policy $item)) {
            $sessionContributions.Add($contribution)
        }
    }

    $session = Merge-CaSessionControl -Contribution $sessionContributions.ToArray()

    if ($blockedBy.Count -gt 0) {
        $access = 'Blocked'
    } elseif ($requiredControls.Count -gt 0 -or $optionalChoices.Count -gt 0) {
        $access = 'GrantedWithControls'
    } else {
        $access = 'Granted'
    }

    return [PSCustomObject]@{
        PSTypeName                = 'CaOutcome.EffectiveControl'
        World                     = $World
        Access                    = $access
        BlockedBy                 = $blockedBy.ToArray()
        Requirements              = $requirements.ToArray()
        RequiredControls          = @($requiredControls | Sort-Object)
        OptionalChoices           = $optionalChoices.ToArray()
        UnsatisfiableRequirements = $unsatisfiable.ToArray()
        AuthenticationStrengths   = @($strengths.Values)
        # Blocked outright, or granted subject to something this sign-in demonstrably cannot
        # produce. Either way the user does not get in.
        IsEffectivelyBlocked      = ($access -eq 'Blocked' -or $unsatisfiable.Count -gt 0)
        SessionControls           = $session.Controls
        SessionConflicts          = @($session.Conflicts)
        AppliedPolicies           = @($applied | ForEach-Object {
            [PSCustomObject]@{
                Id          = [string](Get-CaProperty -InputObject $_ -Name 'id')
                DisplayName = [string](Get-CaProperty -InputObject $_ -Name 'displayName')
                State       = [string](Get-CaProperty -InputObject $_ -Name 'state')
            }
        })
    }
}
