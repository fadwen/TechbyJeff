function Get-WmicPropertyGroup {
    <#
    .SYNOPSIS
        Maps property names onto the shape-change groups they belong to

    .DESCRIPTION
        Looks each property up in the index built from WmicProperties.psd1 and returns the groups
        that matched. A property in no group returns nothing, which is the common case and not a
        problem: most properties are strings on both sides of the migration and genuinely do only
        need the command swapped.

        The lookup is case-insensitive because nothing in WMIC ever was, and the scripts in scope
        were written by people who knew that.

    .PARAMETER Property
        [System.String[]] (Mandatory, No Pipeline Support)

        Property names read out of the command.

    .PARAMETER RuleSet
        [System.Object] (Mandatory, No Pipeline Support)

        The loaded ruleset, for its property index.

    .OUTPUTS
        System.String[] - group names, deduplicated. Empty when nothing matched.

    .EXAMPLE
        Get-WmicPropertyGroup -Property 'IPAddress', 'DHCPEnabled' -RuleSet $ruleSet

        DESCRIPTION: Classifies two properties that change shape in different ways
        OUTPUT: MultiValue, Boolean
        USE CASE: Deciding whether a call belongs in the Semantic tier, and saying why

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Property,

        [Parameter(Mandatory)]
        [object]$RuleSet
    )

    $groups = @()

    foreach ($name in $Property) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $key = $name.Trim().ToLowerInvariant()
        if ($RuleSet.PropertyIndex.ContainsKey($key)) {
            $groups += $RuleSet.PropertyIndex[$key]
        }
    }

    return @($groups | Select-Object -Unique)
}
