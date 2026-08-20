function Get-WmicFingerprint {
    <#
    .SYNOPSIS
        Produces a stable hash used to recognise a finding across runs

    .DESCRIPTION
        Hashes the file, the rule and the command text - deliberately not the line number.

        Line numbers are the one part of a finding guaranteed to change for reasons that have
        nothing to do with the finding. Somebody adds a comment at the top of a batch file and
        every call site below it moves. If the fingerprint included the line, a code scanning
        service would close two hundred findings and open two hundred identical ones, and the
        second report anyone read would be noise. Fingerprinting what the finding is about rather
        than where it currently sits is what makes the run-to-run diff mean something.

    .PARAMETER Value
        [System.String] (Mandatory, No Pipeline Support)

        The composed key to hash.

    .OUTPUTS
        System.String - a lowercase hex SHA-256 digest.

    .EXAMPLE
        Get-WmicFingerprint -Value 'Scripts\Inv.cmd|WMIC100|wmic os get caption'

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
        [string]$Value
    )

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $digest = $algorithm.ComputeHash($bytes)
        return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $algorithm.Dispose()
    }
}
