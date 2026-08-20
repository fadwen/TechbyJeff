function Get-WmicRelativePath {
    <#
    .SYNOPSIS
        Expresses a full path relative to a scan root

    .DESCRIPTION
        Exists because [System.IO.Path]::GetRelativePath is .NET Core only, and this module
        targets Windows PowerShell 5.1 as well. The comparison is case-insensitive because the
        paths are Windows paths; a file outside the root falls back to its own name rather than
        producing a chain of parent traversals nobody wants to read in a report.

    .PARAMETER FullName
        The absolute path to shorten.

    .PARAMETER Root
        The directory to express it relative to.

    .OUTPUTS
        System.String - the relative path, using the platform separator.

    .EXAMPLE
        Get-WmicRelativePath -FullName 'C:\Deploy\Scripts\Set.cmd' -Root 'C:\Deploy'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullName,

        [Parameter()]
        [AllowNull()]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return (Split-Path -Path $FullName -Leaf)
    }

    $normalizedRoot = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if ($FullName.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($normalizedRoot.Length)
    }

    return (Split-Path -Path $FullName -Leaf)
}
