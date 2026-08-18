function ConvertFrom-CaBaselineEntry {
    <#
    .SYNOPSIS
        Rehydrates a stored baseline entry into the shape Compare-CaEffectiveControl reads

    .DESCRIPTION
        The reason this exists rather than a second, baseline-specific comparison: drift between
        a stored run and a fresh one is the same question as the difference between two worlds,
        and answering it with the same code means the two can never disagree about what counts
        as a change. Rehydrating a stored entry into an outcome-shaped object is cheaper than
        maintaining a parallel diff, and it is what makes a baseline comparison report the same
        vocabulary - added requirements, changed session controls, newly blocked - as a
        promotion diff.

        A missing property comes back as an empty collection rather than null, because the
        comparison indexes into all of them. That also makes the function tolerant of a baseline
        written by an older version of this module: a field added later reads as empty, and the
        comparison then reports it as an addition, which is exactly what it is.

    .PARAMETER Entry
        A stored entry, as written by ConvertTo-CaBaselineEntry and read back from JSON.

    .OUTPUTS
        PSCustomObject with the properties Compare-CaEffectiveControl expects.

    .EXAMPLE
        $stored = ConvertFrom-CaBaselineEntry -Entry $baseline.scenarios.'standard/office365/managed'.current
        Compare-CaEffectiveControl -From $stored -To $fresh.Current

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.3.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Entry
    )

    $sessionControls = [ordered]@{}
    $stored = Get-CaProperty -InputObject $Entry -Name 'sessionControls'
    if ($null -ne $stored) {
        $names = @()
        if ($stored -is [System.Collections.IDictionary]) {
            $names = @($stored.Keys)
        } elseif ($stored.PSObject) {
            $names = @($stored.PSObject.Properties | Select-Object -ExpandProperty Name)
        }
        foreach ($name in ($names | Sort-Object)) {
            $sessionControls[$name] = Get-CaProperty -InputObject $stored -Name $name
        }
    }

    return [PSCustomObject]@{
        PSTypeName                = 'CaOutcome.EffectiveControl'
        World                     = 'Baseline'
        Access                    = [string](Get-CaProperty -InputObject $Entry -Name 'access')
        IsEffectivelyBlocked      = [bool](Get-CaProperty -InputObject $Entry -Name 'isEffectivelyBlocked')
        RequiredControls          = @(Get-CaProperty -InputObject $Entry -Name 'requiredControls')
        BlockedBy                 = @(@(Get-CaProperty -InputObject $Entry -Name 'blockedBy') |
            Where-Object { $null -ne $_ } | ForEach-Object {
                [PSCustomObject]@{
                    PolicyId   = Get-CaProperty -InputObject $_ -Name 'policyId'
                    PolicyName = Get-CaProperty -InputObject $_ -Name 'policyName'
                }
            })
        OptionalChoices           = @(@(Get-CaProperty -InputObject $Entry -Name 'optionalChoices') |
            Where-Object { $null -ne $_ } | ForEach-Object {
                [PSCustomObject]@{
                    PolicyId   = Get-CaProperty -InputObject $_ -Name 'policyId'
                    PolicyName = Get-CaProperty -InputObject $_ -Name 'policyName'
                    AnyOf      = @(Get-CaProperty -InputObject $_ -Name 'anyOf')
                }
            })
        UnsatisfiableRequirements = @(@(Get-CaProperty -InputObject $Entry -Name 'unsatisfiable') |
            Where-Object { $null -ne $_ } | ForEach-Object {
                [PSCustomObject]@{
                    PolicyId   = Get-CaProperty -InputObject $_ -Name 'policyId'
                    PolicyName = Get-CaProperty -InputObject $_ -Name 'policyName'
                    Operator   = Get-CaProperty -InputObject $_ -Name 'operator'
                    Controls   = @(Get-CaProperty -InputObject $_ -Name 'controls')
                    Blockers   = @(Get-CaProperty -InputObject $_ -Name 'blockers')
                    Reasons    = @(Get-CaProperty -InputObject $_ -Name 'reasons')
                }
            })
        AuthenticationStrengths   = @(@(Get-CaProperty -InputObject $Entry -Name 'strengths') |
            Where-Object { $null -ne $_ } | ForEach-Object {
                [PSCustomObject]@{
                    Control                       = Get-CaProperty -InputObject $_ -Name 'control'
                    Id                            = Get-CaProperty -InputObject $_ -Name 'id'
                    DisplayName                   = Get-CaProperty -InputObject $_ -Name 'displayName'
                    PolicyType                    = Get-CaProperty -InputObject $_ -Name 'policyType'
                    AllowedCombinations           = @(Get-CaProperty -InputObject $_ `
                        -Name 'allowedCombinations')
                    CombinationConfigurationCount = [int](Get-CaProperty -InputObject $_ `
                        -Name 'combinationConfigurationCount')
                }
            })
        SessionControls           = [PSCustomObject]$sessionControls
        SessionConflicts          = @()
        AppliedPolicies           = @(@(Get-CaProperty -InputObject $Entry -Name 'appliedPolicies') |
            Where-Object { $null -ne $_ } | ForEach-Object {
                [PSCustomObject]@{
                    Id          = Get-CaProperty -InputObject $_ -Name 'id'
                    DisplayName = Get-CaProperty -InputObject $_ -Name 'displayName'
                    State       = Get-CaProperty -InputObject $_ -Name 'state'
                }
            })
    }
}
