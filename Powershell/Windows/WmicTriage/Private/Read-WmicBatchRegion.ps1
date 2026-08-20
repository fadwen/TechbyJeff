function Read-WmicBatchRegion {
    <#
    .SYNOPSIS
        Splits a batch file into the regions the rule engine evaluates

    .DESCRIPTION
        Turns a .bat or .cmd file into regions - a comment, an ordinary line, a for /f block, or
        a variable assignment holding the path to wmic.exe - so the matcher can reason about the
        structure a call sits in rather than only the text of the call.

        Batch is the priority reader in this module because it is the gap. PSScriptAnalyzer never
        opens a .cmd file, so the estate's oldest and least reviewed automation is exactly the
        part no existing tool reports on.

        Three things happen here that a line-oriented grep cannot do:

        CONTINUATIONS ARE JOINED. A trailing caret escapes the newline, so a WMIC call can be
        split across lines with the alias on one and the property on the next. Each logical line
        keeps the physical lines it came from, so the report still points at a real line number.

        FOR /F BLOCKS ARE CAPTURED WHOLE. The finding spans the entire block, because the block
        is the unit of work: the tokens= and delims= spec is what has to be rewritten, and it is
        not on the same line as the command often enough to matter.

        ONLY THE IN-CLAUSE IS TREATED AS WRAPPED. A second WMIC call sitting in the do-body of
        the same block is not parsed by that block - it just runs there - so it is emitted as an
        ordinary line and stays Mechanical. Marking the whole block as Wrapped would be the
        easier implementation and would inflate the tier that the tool exists to report
        accurately.

        Comments are regions rather than being discarded, because a WMIC command in a rem line is
        the example somebody copies two years after the code around it was fixed.

    .PARAMETER Content
        [System.String] (Mandatory, No Pipeline Support)

        The full text of the batch file.

    .OUTPUTS
        Region hashtables carrying Kind, Structure, Text, Snippet, StartLine, EndLine, Lines and
        Detail.

    .EXAMPLE
        $regions = Read-WmicBatchRegion -Content (Get-Content .\Inventory.cmd -Raw)

        DESCRIPTION: Splits a batch inventory script into evaluable regions
        OUTPUT: One region per comment, line, for /f block and wmic path assignment
        USE CASE: The first stage of scanning a batch file

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $physical = $Content -split "`r?`n"
    if ($physical.Count -eq 0) { return }

    # Join caret continuations into logical lines, remembering which physical lines each came
    # from so a finding still reports a line number somebody can go and look at
    $logical = [System.Collections.Generic.List[object]]::new()
    $pending = $null

    for ($i = 0; $i -lt $physical.Count; $i++) {
        $text = $physical[$i]
        $lineRecord = @{ Number = $i + 1; Text = $text }

        if ($null -eq $pending) {
            $pending = @{
                Text  = $text
                Lines = [System.Collections.Generic.List[object]]::new()
            }
        }
        else {
            # The caret and the newline are both consumed; whatever preceded the caret stands
            $pending.Text = $pending.Text + $text
        }
        $pending.Lines.Add($lineRecord)

        # An odd number of trailing carets escapes the newline. An even number is escaped carets
        # that happen to sit at the end of the line and continue nothing.
        $trailing = 0
        for ($c = $pending.Text.Length - 1; $c -ge 0 -and $pending.Text[$c] -eq '^'; $c--) {
            $trailing++
        }

        if ($trailing % 2 -eq 1 -and $i -lt $physical.Count - 1) {
            $pending.Text = $pending.Text.Substring(0, $pending.Text.Length - 1)
            continue
        }

        $logical.Add([PSCustomObject]@{
            Text  = $pending.Text
            Lines = @($pending.Lines)
            Start = $pending.Lines[0].Number
            End   = $pending.Lines[$pending.Lines.Count - 1].Number
        })
        $pending = $null
    }

    # for /f, with its optional quoted option string, its loop variable, and the in-clause that
    # holds the command whose output the block parses
    $forPattern = '(?i)\bfor\s+/f\s*(?:"(?<options>[^"]*)"\s*)?%%?~?[a-zA-Z]\s+in\s*(?=\()'
    $commentPattern = '^\s*(?:@\s*)?(?:rem\b|::)'
    $assignmentPattern = '(?i)^\s*(?:@\s*)?set\s+(?:/a\s+)?"?(?<name>[A-Za-z_][\w]*)=(?<value>[^"]*)"?\s*$'

    $index = 0
    while ($index -lt $logical.Count) {
        $line = $logical[$index]
        $text = $line.Text

        if ([string]::IsNullOrWhiteSpace($text)) {
            $index++
            continue
        }

        if ($text -match $commentPattern) {
            [PSCustomObject]@{
                Kind      = 'Comment'
                Structure = 'Line'
                Text      = $text
                Snippet   = $text
                StartLine = $line.Start
                EndLine   = $line.End
                Lines     = $line.Lines
                Detail    = @{}
            }
            $index++
            continue
        }

        $forMatch = [regex]::Match($text, $forPattern)
        if ($forMatch.Success) {
            $openIndex = $text.IndexOf('(', $forMatch.Index + $forMatch.Length - 1)
            if ($openIndex -ge 0) {
                # Apostrophes and backticks quote the command inside an in-clause, so
                # parentheses within them are data rather than structure
                $inClose = Find-WmicBalancedClose -Line $logical -LineIndex $index `
                    -CharIndex $openIndex -QuoteCharacter "'", '`', '"'

                if ($null -ne $inClose) {
                    $blockEndIndex = $inClose.LineIndex
                    $afterIn = $logical[$inClose.LineIndex].Text.Substring($inClose.CharIndex + 1)

                    # If the do-body is parenthesised the block continues; an apostrophe in the
                    # body is an apostrophe, not a quote, so it must not be treated as one here
                    $doOpen = [regex]::Match($afterIn, '(?i)^\s*do\s*\(')
                    if ($doOpen.Success) {
                        $bodyOpenChar = $inClose.CharIndex + 1 + $afterIn.IndexOf('(')
                        $bodyClose = Find-WmicBalancedClose -Line $logical `
                            -LineIndex $inClose.LineIndex -CharIndex $bodyOpenChar `
                            -QuoteCharacter '"'
                        if ($null -ne $bodyClose) { $blockEndIndex = $bodyClose.LineIndex }
                    }

                    $blockLines = @()
                    for ($b = $index; $b -le $blockEndIndex; $b++) {
                        $blockLines += $logical[$b].Lines
                    }
                    $snippet = (($logical[$index..$blockEndIndex]) | ForEach-Object { $_.Text }) -join "`n"

                    # The region covers the in-clause only: that is the text whose output the
                    # block parses. StartLine and EndLine still span the whole block, because
                    # the block is what a person has to rewrite.
                    $inClauseLines = @()
                    for ($b = $index; $b -le $inClose.LineIndex; $b++) {
                        $inClauseLines += $logical[$b].Lines
                    }

                    [PSCustomObject]@{
                        Kind      = 'Code'
                        Structure = 'ForBlock'
                        Text      = $text
                        Snippet   = $snippet
                        StartLine = $logical[$index].Start
                        EndLine   = $logical[$blockEndIndex].End
                        Lines     = $inClauseLines
                        Detail    = @{
                            ForOptions = $forMatch.Groups['options'].Value
                            BlockLines = $blockLines.Count
                        }
                    }

                    # The do-body is scanned normally, so a WMIC call that merely runs inside the
                    # block is not misreported as one the block parses
                    $index = $inClose.LineIndex + 1
                    continue
                }
            }
        }

        $assignment = [regex]::Match($text, $assignmentPattern)
        $holdsWmic = $assignment.Success -and
            $assignment.Groups['value'].Value -match '(?i)(?<![\w.])wmic(\.exe)?(?![\w])'
        if ($holdsWmic) {
            [PSCustomObject]@{
                Kind      = 'Code'
                Structure = 'Assignment'
                Text      = $text
                Snippet   = $text
                StartLine = $line.Start
                EndLine   = $line.End
                Lines     = $line.Lines
                Detail    = @{ VariableName = $assignment.Groups['name'].Value }
            }
            $index++
            continue
        }

        [PSCustomObject]@{
            Kind      = 'Code'
            Structure = 'Line'
            Text      = $text
            Snippet   = $text
            StartLine = $line.Start
            EndLine   = $line.End
            Lines     = $line.Lines
            Detail    = @{}
        }
        $index++
    }
}
