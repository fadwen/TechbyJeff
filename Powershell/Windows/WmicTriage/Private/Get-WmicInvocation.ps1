function Get-WmicInvocation {
    <#
    .SYNOPSIS
        Finds the WMIC calls inside a region and works out how each one was reached

    .DESCRIPTION
        Locates every WMIC token in a region, isolates the command it belongs to, and reports how
        it was invoked and whether its output goes anywhere.

        FINDING THE COMMAND, NOT THE LINE. The command runs from the WMIC token to the first
        unquoted shell terminator - a pipe, a redirect, a separator, a closing parenthesis. The
        quote tracking is what makes this usable: a where-clause routinely contains > and |
        inside quotes, and a naive split on those characters truncates the command exactly where
        the interesting part starts.

        REACHED WITHOUT THE WORD WMIC AT THE FRONT. %COMSPEC% /c, a full path under System32\wbem,
        Start-Process, WScript.Shell - all of these are call sites that an inventory built by
        grepping for a leading wmic silently misses. They do not change the tier, but they change
        whether the count in the report can be trusted, so each is recorded.

        NOT EVERY OCCURRENCE OF FIVE LETTERS. echo Replace wmic with PowerShell is prose, and a
        scanner that reports it teaches people to ignore the report. A match is accepted only if
        it actually looks like a command: the next token is a known alias or a switch, or the
        segment contains a WMIC verb, or the invocation is bare. The verb test is what covers an
        alias missing from the table - an undercount is the failure mode worth engineering
        against here, so there are two ways to pass rather than one.

    .PARAMETER Region
        [System.Object] (Mandatory, No Pipeline Support)

        A region from one of the readers.

    .PARAMETER FileType
        [System.String] (Mandatory, No Pipeline Support)

        Selects the language profile for process launcher detection.

    .PARAMETER RuleSet
        [System.Object] (Mandatory, No Pipeline Support)

        The loaded ruleset, for its alias table.

    .OUTPUTS
        Hashtables carrying CommandText, Line, Invocation and Capture. Nothing when the region
        holds no real invocation.

    .EXAMPLE
        $calls = Get-WmicInvocation -Region $region -FileType Batch -RuleSet $ruleSet

        DESCRIPTION: Extracts the WMIC calls from a for /f block's in-clause
        OUTPUT: One hashtable with the command text and Capture of ForBlock origin
        USE CASE: The stage between reading a file and classifying what was found

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
        [ValidateNotNullOrEmpty()]
        [string]$FileType,

        [Parameter(Mandatory)]
        [object]$RuleSet
    )

    $profileEntry = $script:LanguageProfile[$FileType]
    $launcherPattern = $null
    if ($profileEntry -and $profileEntry.Invocation -and $profileEntry.Invocation.ProcessLauncher) {
        $launcherPattern = $profileEntry.Invocation.ProcessLauncher
    }

    $quoteCharacter = @('"')
    if ($profileEntry -and $profileEntry.QuoteCharacter) { $quoteCharacter = $profileEntry.QuoteCharacter }

    $tokenPattern = '(?i)(?<![\w.])wmic(\.exe)?(?![\w])'

    # The words that may legitimately stand where an alias would, and the words that may follow
    # one. Together these are the grammar the prose test is built on.
    $targetWords = @('path', 'class', 'alias', 'context')
    $followWords = @('get', 'list', 'call', 'set', 'create', 'delete', 'assoc',
        'associators', 'references', 'where')

    $regionCapture = @()
    if ($Region.Detail -and $Region.Detail.ContainsKey('Capture') -and $Region.Detail.Capture) {
        $regionCapture = @($Region.Detail.Capture)
    }

    foreach ($record in $Region.Lines) {
        $text = [string]$record.Text
        if ([string]::IsNullOrEmpty($text)) { continue }

        foreach ($match in [regex]::Matches($text, $tokenPattern)) {
            $segment = Get-WmicCommandSegment -Text $text -StartIndex $match.Index -QuoteCharacter $quoteCharacter
            $commandText = $segment.Text
            $remainder = $commandText.Substring([Math]::Min($match.Length, $commandText.Length)).Trim()

            # Prose rather than a command: see the description. The test follows the actual WMIC
            # grammar rather than looking for a verb anywhere in the text, because prose is full
            # of these words. "the WMIC call ever moves" and "wmic was pulled off PATH" both
            # contain a verb and neither is a command.
            $tokens = @(Split-WmicCommandToken -Text $remainder)
            $looksLikeCommand = $false

            if ($tokens.Count -eq 0) {
                # A bare wmic in code is a real invocation - it opens the interactive shell. The
                # same five letters in a comment are just the word, usually in a sentence about
                # having stopped using it, so a naked mention there is prose.
                $looksLikeCommand = $Region.Kind -ne 'Comment'
            }
            elseif ($tokens[0].StartsWith('/')) {
                $looksLikeCommand = $true
            }
            elseif ($targetWords -contains $tokens[0].ToLowerInvariant() -and $tokens.Count -gt 1) {
                $looksLikeCommand = $true
            }
            elseif ($RuleSet.Aliases.ContainsKey($tokens[0].ToLowerInvariant())) {
                $looksLikeCommand = $true
            }
            elseif ($tokens[0] -match '^[A-Za-z][\w]*$' -and $tokens.Count -gt 1 -and
                $followWords -contains $tokens[1].ToLowerInvariant()) {
                # An alias the table does not carry, followed by something that only ever follows
                # an alias. This is what keeps an unfamiliar alias from being an undercount.
                $looksLikeCommand = $true
            }

            if (-not $looksLikeCommand) {
                Write-Verbose "Skipping prose match at line $($record.Number): $commandText"
                continue
            }

            $prefix = $text.Substring(0, $match.Index)
            $invocation = @()

            if ($prefix -match '[\\/]$') { $invocation += 'Path' }
            if ($prefix -match '(?i)(%COMSPEC%|\bcmd(\.exe)?["'']?\s+/[ck]\b)') { $invocation += 'ComSpec' }
            if ($launcherPattern -and ($prefix -match $launcherPattern -or $Region.Text -match $launcherPattern)) {
                $invocation += 'ProcessLauncher'
            }
            if ($invocation.Count -eq 0) { $invocation += 'Literal' }

            $capture = @($regionCapture + $segment.Capture | Select-Object -Unique)

            @{
                CommandText = $commandText
                Line        = $record.Number
                Invocation  = @($invocation | Select-Object -Unique)
                Capture     = @($capture | Where-Object { $_ })
            }
        }
    }
}
