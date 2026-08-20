function Export-WmicScanReport {
    <#
    .SYNOPSIS
        Writes scan findings as CSV or SARIF

    .DESCRIPTION
        Core Functionality:
        Takes findings from Invoke-WmicScan and writes them in one of two formats: CSV for
        someone planning the work, SARIF for a pipeline annotating the code.

        Business Value:
        These two readers want opposite things. A migration lead wants every finding in one sheet
        they can sort by tier, filter by team and hand around. A pipeline wants each finding
        pinned to its line with a severity, and wants the same finding recognised next week. One
        format cannot serve both, and the usual compromise - CSV that a script then reshapes -
        just moves the work somewhere it will be done wrong.

        The CSV is flattened deliberately. Arrays become semicolon-joined text and the snippet has
        its newlines collapsed, because a multi-line field turns a CSV into something Excel opens
        wrong and every naive parser reads wrong. The full snippet stays intact in the SARIF,
        where the format can carry it.

        SARIF severity follows the same rule as FailsBuild: error for Mechanical and Wrapped,
        warning for Semantic and Environmental, note for anything in a comment.

        Dependencies:
        None.

        Side Effects:
        Writes the file at Path. Supports -WhatIf.

        Important:
        The SuggestedReplacement column is advisory in every format. Nothing here applies a
        suggestion, and on the Wrapped tier the suggestion says to restructure rather than giving
        a command, because a one-line replacement for a block would be a confident lie.

    .PARAMETER Finding
        [System.Object[]] (Mandatory, Accepts Pipeline Input)

        Findings from Invoke-WmicScan.

    .PARAMETER Path
        [System.String] (Mandatory, No Pipeline Support)

        Where to write the report.

    .PARAMETER Format
        [System.String] (Optional, No Pipeline Support)

        Csv or Sarif. Defaults to Csv.

    .PARAMETER PassThru
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Return the findings as well as writing the file, so the call can sit mid-pipeline.

    .OUTPUTS
        Nothing, unless -PassThru is used.

    .EXAMPLE
        PS> Invoke-WmicScan -Path .\Scripts | Export-WmicScanReport -Path .\wmic.csv

        DESCRIPTION: Writes the inventory as a spreadsheet
        OUTPUT: None; the file is written
        DURATION: Instant
        USE CASE: Handing the inventory to whoever is scheduling the migration

    .EXAMPLE
        PS> Invoke-WmicScan -Path . | Export-WmicScanReport -Path .\wmic.sarif -Format Sarif

        DESCRIPTION: Writes findings for a code scanning service to ingest
        OUTPUT: None; the file is written
        DURATION: Instant
        USE CASE: Annotating the lines in a pull request instead of failing it outright

    .EXAMPLE
        PS> $findings | Export-WmicScanReport -Path .\wmic.csv -WhatIf

        DESCRIPTION: Reports what would be written without writing it
        OUTPUT: The WhatIf message naming the file and the finding count
        DURATION: Instant
        USE CASE: Checking the count before overwriting last week's report

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('WmicTriage.Finding')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Finding,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Csv', 'Sarif')]
        [string]$Format = 'Csv',

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $Finding) {
            if ($null -ne $item) { $collected.Add($item) }
        }
    }

    end {
        $target = "$($collected.Count) finding(s) to $Path"
        if (-not $PSCmdlet.ShouldProcess($target, "Write WMIC triage report as $Format")) {
            if ($PassThru) { return $collected }
            return
        }

        if ($Format -eq 'Sarif') {
            $version = '0.1.0'
            $module = Get-Module -Name 'WmicTriage'
            if ($module) { $version = $module.Version.ToString() }

            $json = ConvertTo-WmicSarif -Finding @($collected) -RuleSet (Get-WmicRuleSet) -Version $version
            Set-Content -LiteralPath $Path -Value $json -Encoding utf8
        }
        else {
            # Flattened on purpose: a newline inside a CSV field is read wrong by Excel and by
            # every hand-rolled parser that will ever be pointed at this file
            $rows = foreach ($item in $collected) {
                [PSCustomObject]@{
                    Tier                 = $item.Tier
                    Kind                 = $item.Kind
                    RelativePath         = $item.RelativePath
                    Line                 = $item.Line
                    StartLine            = $item.StartLine
                    EndLine              = $item.EndLine
                    FileType             = $item.FileType
                    Region               = $item.Region
                    Structure            = $item.Structure
                    RuleId               = $item.RuleId
                    Rule                 = $item.Rule
                    MatchedRules         = (@($item.RuleIds) -join '; ')
                    Command              = ($item.Command -replace '\s*[\r\n]+\s*', ' ')
                    Alias                = $item.Alias
                    TargetClass          = $item.TargetClass
                    Verb                 = $item.Verb
                    Properties           = (@($item.Properties) -join '; ')
                    PropertyGroup        = (@($item.PropertyGroup) -join '; ')
                    Node                 = $item.Node
                    Invocation           = (@($item.Invocation) -join '; ')
                    Capture              = (@($item.Capture) -join '; ')
                    Context              = (@($item.Context) -join '; ')
                    StepName             = $item.StepName
                    ForOptions           = $item.ForOptions
                    FailsBuild           = $item.FailsBuild
                    SuggestedReplacement = $item.SuggestedReplacement
                    Advisory             = $item.Advisory
                    Reason               = ($item.Reason -replace '\s*[\r\n]+\s*', ' ')
                    Snippet              = ($item.Snippet -replace '\s*[\r\n]+\s*', ' | ')
                }
            }

            @($rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
        }

        Write-Verbose "Wrote $($collected.Count) finding(s) to $Path as $Format"

        if ($PassThru) { return $collected }
    }
}
