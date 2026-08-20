function ConvertTo-WmicSarif {
    <#
    .SYNOPSIS
        Renders findings as a SARIF 2.1.0 document

    .DESCRIPTION
        Produces the format GitHub code scanning and Azure DevOps ingest, so the tiers appear as
        annotations on the lines they belong to rather than in a log somebody has to go and read.

        The level mapping is where the tier design has to survive contact with a format that only
        has three severities, and it is deliberate rather than arithmetic:

            Mechanical, Wrapped     error    - a machine can judge these, so a build may insist
            Semantic, Environmental warning  - both end in a judgment call
            anything in a comment   note     - a comment does not run
            a security finding      error    - regardless of its tier

        For the deprecation findings that is the same rule as FailsBuild, expressed in the
        vocabulary of the tools that consume this file. Promoting Semantic to error would look
        more rigorous and would be a mistake: a build that fails on work requiring a human
        decision is a build people learn to bypass, and a bypassed check reports nothing at all.

        Security findings are the one place level and FailsBuild deliberately disagree. A password
        in a checked-in batch file is an error by any reading, so it is surfaced as one - but the
        build gate here is about WMIC deprecation, and letting a credential finding fail that gate
        lets one problem be closed by work aimed at the other. The kind property carries the
        distinction so nothing downstream has to infer it.

        Every finding carries a partial fingerprint over its path, rule and command text, so a
        block moving down a file is recognised as the same finding rather than resurfacing as a
        new one. Without it, any edit above a call site produces a wave of phantom findings and
        the whole report loses its credibility on the second run.

        Line numbers span the region, not the line. For a for /f block that means the annotation
        covers the whole block - which is the unit of work, and the reason the tier exists.

    .PARAMETER Finding
        [System.Object[]] (Mandatory, No Pipeline Support)

        The findings to render.

    .PARAMETER RuleSet
        [System.Object] (Mandatory, No Pipeline Support)

        The loaded ruleset, whose rules become the tool descriptor.

    .PARAMETER Version
        [System.String] (Optional, No Pipeline Support)

        Module version to record as the tool version.

    .OUTPUTS
        System.String - the SARIF document as JSON.

    .EXAMPLE
        $json = ConvertTo-WmicSarif -Finding $findings -RuleSet $ruleSet

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Finding,

        [Parameter(Mandatory)]
        [object]$RuleSet,

        [Parameter()]
        [string]$Version = '0.1.0'
    )

    $levelForTier = @{
        Mechanical    = 'error'
        Wrapped       = 'error'
        Semantic      = 'warning'
        Environmental = 'warning'
    }

    $ruleIndex = @{}
    $descriptors = @()
    $position = 0

    foreach ($rule in $RuleSet.Rules) {
        $ruleIndex[$rule.Id] = $position
        $position++

        $level = 'note'
        $tierTag = 'signal'
        if ($rule.Tier) { $tierTag = $rule.Tier.ToLowerInvariant() }
        if ($rule.Tier -and $levelForTier.ContainsKey($rule.Tier)) { $level = $levelForTier[$rule.Tier] }

        $descriptors += [ordered]@{
            id               = $rule.Id
            name             = $rule.Name
            shortDescription = [ordered]@{ text = $rule.Name }
            fullDescription  = [ordered]@{ text = $rule.Reason }
            help             = [ordered]@{ text = $rule.Suggestion }
            defaultConfiguration = [ordered]@{ level = $level }
            properties       = [ordered]@{
                tags = @('wmic', 'deprecation', $tierTag)
                tier = $rule.Tier
                kind = $rule.Kind
            }
        }
    }

    $results = @()

    foreach ($item in $Finding) {
        $level = 'warning'
        if ($item.Region -eq 'Comment') {
            $level = 'note'
        }
        elseif ($item.Kind -eq 'Security') {
            $level = 'error'
        }
        elseif ($item.Tier -and $levelForTier.ContainsKey($item.Tier)) {
            $level = $levelForTier[$item.Tier]
        }

        # Path, rule and command, but never the line: see Get-WmicFingerprint
        $fingerprintKey = "$($item.RelativePath)|$($item.RuleId)|$($item.Command)"
        $message = "$($item.Tier): $($item.Reason)"
        if ($item.SuggestedReplacement) {
            $message += " Advisory: $($item.SuggestedReplacement)"
        }

        $result = [ordered]@{
            ruleId    = $item.RuleId
            level     = $level
            message   = [ordered]@{ text = $message }
            locations = @(
                [ordered]@{
                    physicalLocation = [ordered]@{
                        artifactLocation = [ordered]@{
                            uri = ConvertTo-WmicSarifUri -Path $item.RelativePath
                        }
                        region           = [ordered]@{
                            startLine = [int]$item.StartLine
                            endLine   = [int][Math]::Max($item.StartLine, $item.EndLine)
                            snippet   = [ordered]@{ text = [string]$item.Snippet }
                        }
                    }
                }
            )
            partialFingerprints = [ordered]@{
                'wmicTriage/v1' = Get-WmicFingerprint -Value $fingerprintKey
            }
            properties = [ordered]@{
                tier                 = $item.Tier
                kind                 = $item.Kind
                structure            = $item.Structure
                fileType             = $item.FileType
                targetClass          = $item.TargetClass
                capture              = @($item.Capture)
                invocation           = @($item.Invocation)
                matchedRules         = @($item.RuleIds)
                stepName             = $item.StepName
                suggestedReplacement = $item.SuggestedReplacement
                advisory             = $true
                failsBuild           = [bool]$item.FailsBuild
            }
        }

        if ($ruleIndex.ContainsKey($item.RuleId)) {
            $result['ruleIndex'] = $ruleIndex[$item.RuleId]
        }

        $results += $result
    }

    $document = [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool    = [ordered]@{
                    driver = [ordered]@{
                        name           = 'WmicTriage'
                        version        = $Version
                        informationUri = 'https://www.techbyjeff.net'
                        rules          = $descriptors
                    }
                }
                results = $results
            }
        )
    }

    return ($document | ConvertTo-Json -Depth 20)
}
