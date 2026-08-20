function Find-WmicTextLine {
    <#
    .SYNOPSIS
        Locates a fragment of text back in the raw file to recover a line number

    .DESCRIPTION
        XmlDocument discards line information, so a task sequence finding would otherwise have no
        line at all. Searching the raw text for the command recovers one.

        The search narrows in two steps. The whole value is tried first, then its first line
        alone, because a CommandLine variable in a task sequence export is frequently one long
        entity-encoded string that never appears verbatim on any single line of the file. Failing
        both, line 1 is returned rather than nothing, so a finding always points somewhere a
        person can open.

        This is approximate by construction and only ever used for task sequences, where the
        authoritative location is the step name rather than the offset. Nothing that fails a
        build depends on it.

    .PARAMETER Line
        [System.String[]] (Mandatory, No Pipeline Support)

        The file split into lines.

    .PARAMETER Needle
        [System.String] (Mandatory, No Pipeline Support)

        The text to find.

    .OUTPUTS
        System.Int32 - a one-based line number, or 1 when the text cannot be located.

    .EXAMPLE
        $line = Find-WmicTextLine -Line $lines -Needle 'wmic csproduct get vendor'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Needle
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) { return 1 }

    $candidates = @($Needle.Trim())

    $firstLine = ($Needle -split "`r?`n")[0].Trim()
    if ($firstLine -and $firstLine -ne $candidates[0]) { $candidates += $firstLine }

    foreach ($candidate in $candidates) {
        if ($candidate.Length -lt 4) { continue }
        for ($i = 0; $i -lt $Line.Count; $i++) {
            if ($Line[$i].IndexOf($candidate, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $i + 1
            }
        }
    }

    return 1
}
