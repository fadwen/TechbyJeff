function Resolve-WmicTier {
    <#
    .SYNOPSIS
        Runs one invocation past every rule and settles which tier it lands in

    .DESCRIPTION
        Builds the subject - everything known about one call - matches it against the whole
        ruleset, and returns the tier along with every rule that fired.

        ESCALATION, NOT FIRST MATCH. A single call routinely trips several rules: a for /f block
        reading a datetime property from a remote node is Wrapped, Semantic and Semantic again.
        The finding takes the highest tier, where highest means hardest, so it is reported as the
        work it actually is. First-match ordering would make the report depend on the order of a
        data file, which is a property nobody could reason about while editing one.

        EVERY RULE IS KEPT. The tier is one value and the reader needs more than one, because
        "Semantic" alone does not say whether the problem is a datetime, an array or an MSI
        consistency check. RuleId names the rule that set the tier and RuleIds names all of them,
        so the reasons survive the reduction.

        SECURITY RULES DO NOT SET THE TIER. A password on a command line is real and separate: it
        is worth fixing whether or not the WMIC call is ever migrated, and folding it into the
        migration tier would let it be closed by a change that does not remove it. Those matches
        come back separately and become their own findings.

    .PARAMETER Region
        [System.Object] (Mandatory, No Pipeline Support)

        The region the call was found in.

    .PARAMETER Invocation
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The invocation from Get-WmicInvocation.

    .PARAMETER Detail
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The parsed command from Get-WmicCommandDetail.

    .PARAMETER Context
        [System.String[]] (Optional, No Pipeline Support)

        File-level contexts. Region-level contexts are merged in from the region's own detail.

    .PARAMETER RuleSet
        [System.Object] (Mandatory, No Pipeline Support)

        The loaded ruleset.

    .OUTPUTS
        A hashtable with Tier, Rule, RuleId, RuleIds, Reason, Suggestion, MatchedRule and
        SecurityRule.

    .EXAMPLE
        $evaluation = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail -RuleSet $ruleSet

        DESCRIPTION: Classifies one call
        OUTPUT: Tier Wrapped, RuleIds WMIC001, WMIC100
        USE CASE: The decision the whole module exists to make

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object]$Region,

        [Parameter(Mandatory)]
        [hashtable]$Invocation,

        [Parameter(Mandatory)]
        [hashtable]$Detail,

        [Parameter()]
        [AllowNull()]
        [string[]]$Context,

        [Parameter(Mandatory)]
        [object]$RuleSet
    )

    $contexts = @()
    if ($Context) { $contexts += $Context }
    if ($Region.Detail -and $Region.Detail.ContainsKey('Context') -and $Region.Detail.Context) {
        $contexts += @($Region.Detail.Context)
    }

    $subject = @{
        Region          = @($Region.Kind)
        Structure       = @($Region.Structure)
        Invocation      = @($Invocation.Invocation)
        Capture         = @($Invocation.Capture)
        Verb            = @($Detail.Verb) | Where-Object { $_ }
        Switch          = @($Detail.SwitchName)
        Alias           = @($Detail.Alias) | Where-Object { $_ }
        PropertyGroup   = @($Detail.PropertyGroup)
        Context         = @($contexts | Select-Object -Unique)
        Text            = [string]$Invocation.CommandText
        Snippet         = [string]$Region.Snippet
        AliasNonObvious = [bool]$Detail.NonObvious
    }

    $matched = [System.Collections.Generic.List[object]]::new()
    $security = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in $RuleSet.Rules) {
        $isMatch = $true

        foreach ($key in $rule.Match.Keys) {
            $expected = $rule.Match[$key]

            if ($key -eq 'Pattern') {
                if ($subject.Text -notmatch $expected) { $isMatch = $false }
            }
            elseif ($key -eq 'Snippet') {
                if ($subject.Snippet -notmatch $expected) { $isMatch = $false }
            }
            elseif ($key -eq 'AliasNonObvious') {
                if ($subject.AliasNonObvious -ne [bool]$expected) { $isMatch = $false }
            }
            else {
                $actual = @($subject[$key])
                $any = $false
                foreach ($candidate in @($expected)) {
                    if ($actual -contains $candidate) { $any = $true; break }
                }
                if (-not $any) { $isMatch = $false }
            }

            if (-not $isMatch) { break }
        }

        if (-not $isMatch) { continue }

        if ($rule.Kind -eq 'Security') { $security.Add($rule) } else { $matched.Add($rule) }
    }

    $tier = $null
    $primary = $null
    $bestRank = -1

    foreach ($rule in $matched) {
        if ($rule.Rank -gt $bestRank) {
            $bestRank = $rule.Rank
            $primary = $rule
            $tier = $rule.Tier
        }
    }

    return @{
        Tier         = $tier
        Rule         = if ($primary) { $primary.Name } else { $null }
        RuleId       = if ($primary) { $primary.Id } else { $null }
        RuleIds      = @(($matched + $security) | ForEach-Object { $_.Id })
        Reason       = if ($primary) { $primary.Reason } else { $null }
        Suggestion   = if ($primary) { $primary.Suggestion } else { $null }
        MatchedRule  = @($matched)
        SecurityRule = @($security)
    }
}
