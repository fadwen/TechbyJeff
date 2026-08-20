function Split-WmicCommandToken {
    <#
    .SYNOPSIS
        Splits command text into tokens, keeping quoted spans whole

    .DESCRIPTION
        A whitespace split would be enough if WMIC arguments never contained spaces, and they do:
        a get list can be written as get "Name, Version" and a set value is frequently a quoted
        path. Splitting those apart turns one property name into two and a path into several
        tokens that parse as nothing.

        The quotes themselves are dropped from the returned tokens, since every caller wants the
        value rather than its punctuation.

    .PARAMETER Text
        [System.String] (Mandatory, No Pipeline Support)

        The text to tokenize.

    .OUTPUTS
        System.String[] - the tokens, with empty entries removed.

    .EXAMPLE
        $tokens = Split-WmicCommandToken -Text 'service where "name=''spooler''" get startmode'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuote = $false

    foreach ($character in $Text.ToCharArray()) {
        if ($character -eq '"') {
            $inQuote = -not $inQuote
            continue
        }

        if (-not $inQuote -and [char]::IsWhiteSpace($character)) {
            if ($current.Length -gt 0) {
                $tokens.Add($current.ToString())
                $null = $current.Clear()
            }
            continue
        }

        $null = $current.Append($character)
    }

    if ($current.Length -gt 0) { $tokens.Add($current.ToString()) }

    # Apostrophes and backticks survive from the shell that wrapped the command - a for /f
    # in-clause, a PowerShell argument list - and are punctuation rather than part of any value
    return @($tokens |
        ForEach-Object { $_.Trim("'", '`', ',') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
