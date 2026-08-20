function Invoke-WmicScan {
    <#
    .SYNOPSIS
        Scans a codebase for deprecated WMIC usage and sorts each hit by how hard it is to replace

    .DESCRIPTION
        Core Functionality:
        Walks the files under Path, finds every WMIC call site, and returns one object per finding
        carrying the tier it belongs to, the rules that put it there, and an advisory replacement.

        Business Value:
        The inventory is the expensive part of retiring WMIC, and a flat list of four hundred grep
        hits does not help anyone plan. PSScriptAnalyzer already answers the yes-or-no question
        for PowerShell files. What nobody answers is which of those hits is a two-second swap and
        which is a day, and that is the number a migration is actually scheduled against.

        The tiers, in increasing order of effort:

        MECHANICAL - swap the command and stop. Nothing reads the output.
        WRAPPED    - the output is captured and parsed, so the wrapper has to be rewritten too.
        SEMANTIC   - the correct translation is a judgment call rather than a substitution.
        ENVIRONMENTAL - PowerShell may not exist where this runs, so the environment comes first.

        Wrapped is the tier this tool exists for. No other tool detects it, and it is the case
        that produces silently wrong output instead of a clean failure: a for /f block parsing a
        padded WMIC table by token position keeps running perfectly against Get-CimInstance and
        starts setting variables to the wrong thing. Nothing errors, and the report it feeds looks
        exactly as plausible as it did last week.

        Escalation is by effort rather than severity, so when several rules match one call the
        finding takes the hardest of them. A mechanical one-liner in a WinPE script is reported as
        Environmental: the swap really is trivial, but whether the boot image has PowerShell at
        all is not, and that question has to be answered before the easy part matters.

        Comments are included by default. A WMIC command in a rem line is documentation that will
        mislead somebody long after the code beside it was fixed. It never fails a build - a
        comment does not run - and -ExcludeComment drops it entirely.

        Dependencies:
        None. Everything is text and XML parsing over files on disk, so this runs anywhere,
        including a Linux build agent scanning a mounted deployment share.

        Side Effects:
        None. This function only reads.

        Important:
        Variables holding the path to wmic.exe are reported where they are assigned but their
        call sites are NOT resolved, in batch or anywhere else. Chasing them is an AST problem in
        PowerShell and unsolvable in batch, so the assignment carries a Semantic finding saying in
        as many words that the count is an undercount until someone greps for that variable. That
        is the one place this tool knows it is incomplete, and it says so in the report rather
        than in the documentation.

    .PARAMETER Path
        [System.String[]] (Mandatory, Accepts Pipeline Input by Value and by Property Name)

        Files, directories, or wildcards to scan. Directories are walked in full including
        subdirectories - there is no -Recurse switch, because an inventory that silently covered
        only the top level of a deployment share is worse than none, since it will be believed.

        Accepts FullName from the pipeline, so Get-ChildItem piped straight in works.

    .PARAMETER Exclude
        [System.String[]] (Optional, No Pipeline Support)

        Wildcard patterns matched against each file's full path and its path relative to the scan
        root. Use it for vendor trees, build output and anything else you did not write.

    .PARAMETER Extension
        [System.String[]] (Optional, No Pipeline Support)

        Restrict the scan to these extensions. Omit to read every type the module has a reader
        for: .bat .cmd .ps1 .psm1 .vbs .vbe .wsf .js .py .xml

    .PARAMETER Tier
        [System.String[]] (Optional, No Pipeline Support)

        Return only findings in these tiers. Filtering happens after classification, so a call
        escalated out of the tier you asked for will not appear - which is the intended behaviour,
        since it is no longer that kind of work.

    .PARAMETER ExcludeComment
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Drop findings that sit in comments.

    .PARAMETER Summary
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Return a single summary object with the counts per tier and a FailsBuild verdict, instead
        of the findings. This module never calls exit, so a CI step reads FailsBuild and decides
        for itself.

    .OUTPUTS
        WmicTriage.Finding objects, or one WmicTriage.Summary object with -Summary.

    .EXAMPLE
        PS> Invoke-WmicScan -Path '\\dp01\Deploy$'

        DESCRIPTION: Scans a whole deployment share
        OUTPUT: One finding per call site, worst tier first in the default table view
        DURATION: A few seconds per thousand files
        USE CASE: Building the inventory that a WMIC migration gets scheduled against

    .EXAMPLE
        PS> Invoke-WmicScan -Path .\Scripts -Tier Wrapped | Format-List Command, ForOptions, Reason

        DESCRIPTION: Isolates the calls whose output is parsed by something downstream
        OUTPUT: The wrapped findings with the for /f token spec that has to be rewritten
        DURATION: Instant on a normal repository
        USE CASE: Finding the work that will silently produce wrong answers if it is swapped
                  rather than restructured

    .EXAMPLE
        PS> $summary = Invoke-WmicScan -Path . -Summary
        PS> if ($summary.FailsBuild) { exit 1 }

        DESCRIPTION: Uses the scan as a build gate
        OUTPUT: The summary object, then a non-zero exit when Mechanical or Wrapped code was found
        DURATION: Instant
        USE CASE: Failing CI on the tiers a machine can judge, while letting Semantic and
                  Environmental through for a human to read

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType('WmicTriage.Finding')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [string[]]$Extension,

        [Parameter()]
        [ValidateSet('Mechanical', 'Wrapped', 'Semantic', 'Environmental')]
        [string[]]$Tier,

        [Parameter()]
        [switch]$ExcludeComment,

        [Parameter()]
        [switch]$Summary
    )

    begin {
        $ruleSet = Get-WmicRuleSet
        $collected = [System.Collections.Generic.List[object]]::new()
        $paths = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Path) { $paths.Add($item) }
    }

    end {
        $files = @(Resolve-WmicScanFile -Path $paths -Exclude $Exclude -Extension $Extension)
        Write-Verbose "Scanning $($files.Count) file(s)"

        $index = 0
        foreach ($file in $files) {
            $index++
            if ($files.Count -gt 50) {
                Write-Progress -Activity 'Scanning for WMIC usage' -Status $file.RelativePath `
                    -PercentComplete (($index / $files.Count) * 100)
            }

            $content = $null
            try {
                $content = Get-Content -LiteralPath $file.Path -Raw -ErrorAction Stop
            }
            catch {
                # One locked or unreadable file must not end a scan of ten thousand
                Write-Warning "Could not read $($file.Path): $($_.Exception.Message)"
                continue
            }

            if ([string]::IsNullOrEmpty($content)) { continue }
            if ($content -notmatch '(?i)wmic') { continue }

            $context = @(Get-WmicFileContext -Path $file.Path -Content $content -FileType $file.FileType)

            $regions = switch ($file.FileType) {
                'Batch' { Read-WmicBatchRegion -Content $content }
                'PowerShell' { Read-WmicPowerShellRegion -Content $content }
                'TaskSequence' { Read-WmicTaskSequenceRegion -Content $content }
                default { Read-WmicScriptRegion -Content $content -FileType $file.FileType }
            }

            foreach ($region in $regions) {
                if ($ExcludeComment -and $region.Kind -eq 'Comment') { continue }

                $calls = @(Get-WmicInvocation -Region $region -FileType $file.FileType -RuleSet $ruleSet)
                foreach ($call in $calls) {
                    $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet $ruleSet
                    $evaluation = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                        -Context $context -RuleSet $ruleSet

                    $collected.Add((New-WmicFinding -File $file -Region $region -Invocation $call `
                                -Detail $detail -Evaluation $evaluation -Context $context))

                    # Raised separately rather than folded into the tier, so a credential on a
                    # command line cannot be closed by a change that only moves the WMIC call
                    foreach ($rule in $evaluation.SecurityRule) {
                        $collected.Add((New-WmicFinding -File $file -Region $region -Invocation $call `
                                    -Detail $detail -Evaluation $evaluation -Rule $rule `
                                    -Kind 'Security' -Context $context))
                    }
                }
            }
        }

        if ($files.Count -gt 50) {
            Write-Progress -Activity 'Scanning for WMIC usage' -Completed
        }

        $findings = @($collected)
        if ($Tier) {
            $findings = @($findings | Where-Object { $Tier -contains $_.Tier })
        }

        if (-not $Summary) {
            return $findings
        }

        $byTier = [ordered]@{}
        foreach ($name in $script:TierRank.Keys) {
            $byTier[$name] = @($findings | Where-Object { $_.Tier -eq $name -and $_.Kind -eq 'Deprecation' }).Count
        }

        return [PSCustomObject]@{
            PSTypeName    = 'WmicTriage.Summary'
            FilesScanned  = $files.Count
            FindingCount  = @($findings | Where-Object { $_.Kind -eq 'Deprecation' }).Count
            SecurityCount = @($findings | Where-Object { $_.Kind -eq 'Security' }).Count
            CommentCount  = @($findings | Where-Object { $_.Region -eq 'Comment' }).Count
            ByTier        = $byTier
            FailsBuild    = [bool](@($findings | Where-Object { $_.FailsBuild }).Count)
        }
    }
}
