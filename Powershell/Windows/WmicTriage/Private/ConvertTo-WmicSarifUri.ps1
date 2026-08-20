function ConvertTo-WmicSarifUri {
    <#
    .SYNOPSIS
        Turns a Windows relative path into the URI form SARIF expects

    .DESCRIPTION
        SARIF artifact locations are URIs, not paths. Backslashes are not separators there, and a
        space is not a legal character, so a Windows path handed over unchanged either fails
        validation or - worse - is accepted and then fails to match any file in the repository,
        which shows up as a report full of findings that annotate nothing.

        Each segment is escaped separately so that the separators survive as separators.

    .PARAMETER Path
        [System.String] (Mandatory, No Pipeline Support)

        A relative path.

    .OUTPUTS
        System.String - the escaped, forward-slashed relative URI.

    .EXAMPLE
        ConvertTo-WmicSarifUri -Path 'Deploy Scripts\Set OSD.cmd'

        DESCRIPTION: Escapes a path with spaces in both segments
        OUTPUT: Deploy%20Scripts/Set%20OSD.cmd
        USE CASE: Making a finding line up with a file in a code scanning UI

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    $segments = $Path -split '[\\/]' | Where-Object { $_ -ne '' }
    $escaped = foreach ($segment in $segments) { [uri]::EscapeDataString($segment) }

    return ($escaped -join '/')
}
