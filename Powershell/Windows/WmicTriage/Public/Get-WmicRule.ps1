function Get-WmicRule {
    <#
    .SYNOPSIS
        Returns the rules the scanner uses, so a report can be argued with

    .DESCRIPTION
        Core Functionality:
        Lists the loaded ruleset - id, name, tier, what it matches on, why it fires and what it
        suggests.

        Business Value:
        A triage tool's output is only worth as much as the reader's willingness to believe it,
        and the first reasonable question about any classification is why. Being able to answer
        that from the tool rather than from the source is what makes the tiers arguable, and a
        tier nobody can argue with is a tier nobody trusts.

        It is also how you find out what the scanner does not know. The rules are the whole of its
        knowledge; if a shape you care about is not in this list, it is not detected, and reading
        the list is faster than discovering that from an empty result.

        Adding a rule is an edit to Data\WmicRules.psd1 and nothing else. The engine holds no WMIC
        knowledge of its own, so a rule that appears here is live.

        Dependencies:
        None.

        Side Effects:
        None.

    .PARAMETER Id
        [System.String[]] (Optional, No Pipeline Support)

        Return only these rule ids. Wildcards are accepted.

    .PARAMETER Tier
        [System.String[]] (Optional, No Pipeline Support)

        Return only rules that assign one of these tiers. Signal rules assign none, so naming a
        tier excludes them.

    .OUTPUTS
        WmicTriage.Rule objects.

    .EXAMPLE
        PS> Get-WmicRule | Format-Table Id, Tier, Name

        DESCRIPTION: Lists every rule with the tier it assigns
        OUTPUT: A table of all rules, signal rules showing an empty tier
        USE CASE: Seeing at a glance what the scanner does and does not look for

    .EXAMPLE
        PS> Get-WmicRule -Tier Wrapped | Select-Object Id, Name, Reason

        DESCRIPTION: Shows the rules behind the tier that exists for silently wrong output
        OUTPUT: The five ways this module decides output is being consumed
        USE CASE: Checking whether a wrapping idiom in your estate is covered

    .EXAMPLE
        PS> (Get-WmicRule -Id WMIC200).Reason

        DESCRIPTION: Answers why a Win32_Product call was classified as Semantic
        OUTPUT: The explanation of the MSI consistency check that makes it more than a swap
        USE CASE: Justifying a tier to whoever has to schedule the work

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType('WmicTriage.Rule')]
    param(
        [Parameter()]
        [string[]]$Id,

        [Parameter()]
        [ValidateSet('Mechanical', 'Wrapped', 'Semantic', 'Environmental')]
        [string[]]$Tier
    )

    $rules = (Get-WmicRuleSet).Rules

    if ($Id) {
        $rules = @($rules | Where-Object {
                $candidate = $_.Id
                @($Id | Where-Object { $candidate -like $_ }).Count -gt 0
            })
    }

    if ($Tier) {
        $rules = @($rules | Where-Object { $Tier -contains $_.Tier })
    }

    return $rules
}
