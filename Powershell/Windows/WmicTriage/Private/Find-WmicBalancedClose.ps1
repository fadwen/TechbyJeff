function Find-WmicBalancedClose {
    <#
    .SYNOPSIS
        Finds the parenthesis that closes an opening one, across lines, ignoring quoted text

    .DESCRIPTION
        Walks forward from an opening parenthesis and returns where its match sits, counting
        nesting and skipping anything inside quotes.

        A regex cannot do this, which is the whole reason this function exists. A for /f block is
        the single most valuable thing this module detects, and its extent is defined by balanced
        parentheses spread over however many lines the author felt like using. Matching the line
        instead of the block is exactly the failure that makes existing tooling useless here: the
        line tells you a WMIC call exists, and the block tells you the tokens= spec that has to be
        rewritten with it.

        Which characters quote is caller's choice, and it has to be, because batch does not agree
        with itself. Inside a for /f in-clause an apostrophe opens a quoted command, so a
        parenthesis within it is data. Inside the do-body an apostrophe is just an apostrophe, and
        treating it as a quote there would swallow the rest of the file the first time somebody
        wrote "don't" in an echo.

    .PARAMETER Line
        [System.Object[]] (Mandatory, No Pipeline Support)

        The logical lines to walk, each carrying a Text property.

    .PARAMETER LineIndex
        [System.Int32] (Mandatory, No Pipeline Support)

        Index into Line of the line holding the opening parenthesis.

    .PARAMETER CharIndex
        [System.Int32] (Mandatory, No Pipeline Support)

        Position of the opening parenthesis within that line.

    .PARAMETER QuoteCharacter
        [System.Char[]] (Optional, No Pipeline Support)

        Characters that open and close a quoted span. Defaults to the double quote alone.

    .OUTPUTS
        A hashtable with LineIndex and CharIndex of the closing parenthesis, or null when the
        parentheses never balance - which means malformed batch, and the caller should fall back
        to treating the single line as the region rather than swallowing the file.

    .EXAMPLE
        $close = Find-WmicBalancedClose -Line $logical -LineIndex 4 -CharIndex 22 -QuoteCharacter "'", '"'

        DESCRIPTION: Finds the end of a for /f in-clause whose command is in apostrophes
        OUTPUT: @{ LineIndex = 4; CharIndex = 58 }
        USE CASE: Establishing the span of text that holds the wrapped WMIC call

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Line,

        [Parameter(Mandatory)]
        [int]$LineIndex,

        [Parameter(Mandatory)]
        [int]$CharIndex,

        [Parameter()]
        [char[]]$QuoteCharacter = @('"')
    )

    $depth = 0
    $openQuote = $null

    for ($i = $LineIndex; $i -lt $Line.Count; $i++) {
        $text = [string]$Line[$i].Text
        $start = 0
        if ($i -eq $LineIndex) { $start = $CharIndex }

        for ($c = $start; $c -lt $text.Length; $c++) {
            $character = $text[$c]

            if ($null -ne $openQuote) {
                # Inside a quoted span nothing counts except the quote that ends it
                if ($character -eq $openQuote) { $openQuote = $null }
                continue
            }

            if ($QuoteCharacter -contains $character) {
                $openQuote = $character
                continue
            }

            if ($character -eq '(') {
                $depth++
            }
            elseif ($character -eq ')') {
                $depth--
                if ($depth -le 0) {
                    return @{ LineIndex = $i; CharIndex = $c }
                }
            }
        }
    }

    return $null
}
