function ConvertTo-CaBaselineEntry {
    <#
    .SYNOPSIS
        Reduces one effective outcome to the stable shape a baseline stores

    .DESCRIPTION
        A baseline is a file that gets committed, so the only thing that should ever change in
        it is the outcome. Everything here exists to make that true.

        Ordering is imposed rather than inherited. Graph returns policies in no guaranteed
        order, and a baseline that reordered its own arrays run to run would produce a diff on
        every commit, which is the fastest way to teach everybody to ignore the diff. So
        policies sort by id, choices by policy, and controls are already sorted by the fold.

        Only what Compare-CaEffectiveControl reads is stored - access, blockers, requirements,
        choices, unsatisfiable requirements, session controls and applied policies. Storing the
        whole outcome would bloat the file with the full policy conditions of every policy in
        the tenant, and none of it would be compared. Storing less would mean the comparison
        could not run against a stored baseline at all, which is the entire point.

        Session conflicts are deliberately not stored. They are a property of the live policy
        set rather than of this sign-in's outcome, they are reported by the matrix run itself,
        and including them would make a conflict appear as scenario drift in every scenario it
        touches at once.

    .PARAMETER EffectiveControl
        A Current or Projected outcome from Get-CaEffectiveControl.

    .OUTPUTS
        Ordered hashtable, ready to serialise.

    .EXAMPLE
        $entry = ConvertTo-CaBaselineEntry -EffectiveControl $outcome.Current

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.3.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$EffectiveControl
    )

    if ($null -eq $EffectiveControl) {
        return [ordered]@{}
    }

    $sessionControls = [ordered]@{}
    $controls = Get-CaProperty -InputObject $EffectiveControl -Name 'SessionControls'
    if ($null -ne $controls -and $controls.PSObject) {
        foreach ($property in ($controls.PSObject.Properties | Sort-Object Name)) {
            $sessionControls[$property.Name] = $property.Value
        }
    }

    return [ordered]@{
        access               = [string]$EffectiveControl.Access
        isEffectivelyBlocked = [bool]$EffectiveControl.IsEffectivelyBlocked
        requiredControls     = @($EffectiveControl.RequiredControls)
        blockedBy            = @(@($EffectiveControl.BlockedBy) | Sort-Object PolicyId |
            ForEach-Object {
                [ordered]@{ policyId = $_.PolicyId; policyName = $_.PolicyName }
            })
        optionalChoices      = @(@($EffectiveControl.OptionalChoices) | Sort-Object PolicyId |
            ForEach-Object {
                [ordered]@{
                    policyId = $_.PolicyId; policyName = $_.PolicyName
                    anyOf = @($_.AnyOf | Sort-Object)
                }
            })
        unsatisfiable        = @(@($EffectiveControl.UnsatisfiableRequirements) |
            Sort-Object PolicyId | ForEach-Object {
                [ordered]@{
                    policyId = $_.PolicyId; policyName = $_.PolicyName
                    operator = $_.Operator
                    controls = @($_.Controls | Sort-Object)
                    blockers = @($_.Blockers | Sort-Object)
                    reasons  = @($_.Reasons | Sort-Object)
                }
            })
        # Stored because a custom strength is editable and every policy referencing it changes
        # when it is edited, with no policy document changing at all
        strengths            = @(@($EffectiveControl.AuthenticationStrengths) |
            Sort-Object Control | ForEach-Object {
                [ordered]@{
                    control                       = $_.Control
                    id                            = $_.Id
                    displayName                   = $_.DisplayName
                    policyType                    = $_.PolicyType
                    allowedCombinations           = @($_.AllowedCombinations | Sort-Object)
                    combinationConfigurationCount = [int]$_.CombinationConfigurationCount
                }
            })
        sessionControls      = $sessionControls
        appliedPolicies      = @(@($EffectiveControl.AppliedPolicies) | Sort-Object Id |
            ForEach-Object {
                [ordered]@{ id = $_.Id; displayName = $_.DisplayName; state = $_.State }
            })
    }
}
