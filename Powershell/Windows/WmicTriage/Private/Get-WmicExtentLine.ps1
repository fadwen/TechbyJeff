function Get-WmicExtentLine {
    <#
    .SYNOPSIS
        Builds the numbered line records for a span of a file

    .DESCRIPTION
        The PowerShell parser reports positions as line numbers into the file, while the rest of
        this module works on line records carrying both a number and their text. This converts
        one into the other so a finding coming from the tree carries the same shape as one coming
        from the batch reader, and the invocation finder does not need to know which reader
        produced what it was handed.

        Out-of-range numbers are clamped rather than throwing. An extent that runs past the last
        line means the file ended without a trailing newline, which is common and harmless.

    .PARAMETER Line
        [System.String[]] (Mandatory, No Pipeline Support)

        The file split into lines, zero-indexed.

    .PARAMETER Start
        [System.Int32] (Mandatory, No Pipeline Support)

        First line of the span, one-based as the parser reports it.

    .PARAMETER End
        [System.Int32] (Mandatory, No Pipeline Support)

        Last line of the span, one-based and inclusive.

    .OUTPUTS
        System.Object[] - hashtables with Number and Text.

    .EXAMPLE
        $records = Get-WmicExtentLine -Line $lines -Start 12 -End 14

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line,

        [Parameter(Mandatory)]
        [int]$Start,

        [Parameter(Mandatory)]
        [int]$End
    )

    $first = [Math]::Max(1, $Start)
    $last = [Math]::Min($Line.Count, $End)

    $records = @()
    for ($i = $first; $i -le $last; $i++) {
        $records += @{ Number = $i; Text = $Line[$i - 1] }
    }

    return $records
}
