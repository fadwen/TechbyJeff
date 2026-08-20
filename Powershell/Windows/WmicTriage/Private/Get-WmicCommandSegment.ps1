function Get-WmicCommandSegment {
    <#
    .SYNOPSIS
        Cuts one command out of a line at the first unquoted shell terminator

    .DESCRIPTION
        Walks forward from a WMIC token and stops at the first pipe, redirect, separator or
        closing parenthesis that is not inside quotes, returning the command text and what the
        terminator says about where the output went.

        QUOTE TRACKING IS THE POINT. A WMIC where-clause is quoted text that regularly contains
        the exact characters a shell uses as terminators:

            wmic process where "workingsetsize > 100000000" get name

        Splitting that on the first > yields a command that reads as a redirect into a file called
        100000000, which is both a truncated command in the report and an invented Wrapped
        finding. Tracking the quote state costs a single pass and removes the whole class.

        THE WALK STARTS MID-STRING MORE OFTEN THAN NOT. objShell.Exec("wmic ...") and
        Start-Process 'wmic.exe' both put the command inside a quoted argument, and the WMIC token
        sits after the opening quote. So the state is seeded by reading the text behind the start
        first. Without that, the closing quote reads as an opening one, every terminator after it
        looks quoted, and the command swallows the rest of the host language - which is how
        wmic bios get serialnumber", 0, True ends up in a report.

        When the walk did begin inside a quote, the quote that closes it ends the command, because
        that quoted string is the command. Nothing after it belongs to WMIC.

        TERMINATORS ARE ALSO EVIDENCE. A pipe means something downstream reads the WMIC table
        layout, and a redirect means something reads it later out of a file; both put the finding
        in the Wrapped tier, where the honest advice is to restructure rather than substitute. A
        plain separator or a closing parenthesis ends the command without consuming its output, so
        neither is recorded as capture.

    .PARAMETER Text
        [System.String] (Mandatory, No Pipeline Support)

        The line to read.

    .PARAMETER StartIndex
        [System.Int32] (Mandatory, No Pipeline Support)

        Where the WMIC token begins.

    .PARAMETER QuoteCharacter
        [System.Char[]] (Optional, No Pipeline Support)

        Which characters delimit a string in the host language. Defaults to the double quote
        alone, which is the right answer for batch - an apostrophe there is an apostrophe, and
        treating it as a quote would run every echoed "don't" into the following command.

    .OUTPUTS
        A hashtable with Text - the command, trimmed of the quoting that wrapped it - and Capture,
        holding Pipe, Redirect, or nothing.

    .EXAMPLE
        $segment = Get-WmicCommandSegment -Text $line -StartIndex 21

        DESCRIPTION: Isolates the command inside a for /f in-clause
        OUTPUT: @{ Text = "wmic os get caption"; Capture = @() }
        USE CASE: Getting a clean command to parse and to print in the report

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
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$StartIndex,

        [Parameter()]
        [char[]]$QuoteCharacter = @('"')
    )

    $capture = @()
    $end = $Text.Length

    # Seed the quote state from the text behind the start: see the description
    $openQuote = $null
    for ($i = 0; $i -lt $StartIndex -and $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        if ($null -ne $openQuote) {
            if ($character -eq $openQuote) { $openQuote = $null }
        }
        elseif ($QuoteCharacter -contains $character) {
            $openQuote = $character
        }
    }
    $startedQuoted = $null -ne $openQuote

    for ($i = $StartIndex; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]

        if ($null -ne $openQuote) {
            if ($character -eq $openQuote) {
                $openQuote = $null
                # The string that held the command has ended, so the command has too
                if ($startedQuoted) {
                    $end = $i
                    break
                }
            }
            continue
        }

        if ($QuoteCharacter -contains $character) {
            $openQuote = $character
            continue
        }

        if ($character -eq '|') {
            # || is a logical or, not a pipe: nothing reads the output, it only decides whether
            # the next command runs
            if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '|') {
                $end = $i
                break
            }
            $capture += 'Pipe'
            $end = $i
            break
        }

        if ($character -eq '>' -or $character -eq '<') {
            $capture += 'Redirect'
            $end = $i
            break
        }

        if ($character -eq '&' -or $character -eq ')') {
            $end = $i
            break
        }
    }

    $segment = $Text.Substring($StartIndex, $end - $StartIndex)

    # A command lifted out of a for /f in-clause or a quoted argument keeps the quote that closed
    # it, and a stray trailing quote in the report looks like a parsing bug rather than a source
    # artefact
    $segment = $segment.Trim().TrimEnd("'", '`', '"').Trim()

    return @{
        Text    = $segment
        Capture = $capture
    }
}
