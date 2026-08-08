function Protect-OktaTestSecret {
    <#
    .SYNOPSIS
        Encrypts a secret for storage at rest, using DPAPI where it is available

    .DESCRIPTION
        The service app private key can mint admin-scoped tokens for the tenant, so leaving it
        on disk as readable JSON is not good enough even behind a restrictive ACL. An ACL stops
        other users; it does nothing about a backup agent, a synced folder, or a stolen disk
        image.

        ConvertFrom-SecureString with no -Key produces a DPAPI-protected string bound to the
        current user and machine. That is the right default here: it needs no modules, no
        password to remember, and no key of its own to protect. Copying the file to another
        machine or another account makes it undecryptable, which for a lab credential is a
        feature rather than a limitation.

        DPAPI is Windows-only. On Linux and macOS the underlying ProtectedData API throws, and
        this returns the secret unprotected with a warning rather than pretending otherwise.
        That is deliberate: the dangerous outcome would be a value that looks encrypted and is
        not, and silently downgrading without saying so is how that happens. Callers record the
        returned Method alongside the value so the reader knows what it is holding, and
        -UseSecretStore is the cross-platform answer.

    .PARAMETER PlainText
        The secret to protect

    .OUTPUTS
        PSCustomObject with Method ('DPAPI' or 'None') and Value

    .EXAMPLE
        $protected = Protect-OktaTestSecret -PlainText ($jwk | ConvertTo-Json -Compress)
        $protected.Method

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The plaintext is already in memory; this is the step that encrypts it.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PlainText
    )

    try {
        # Windows only, and checked up front rather than relied on failing. This is the whole
        # correction: on Linux, ConvertFrom-SecureString does NOT throw and does NOT encrypt -
        # it returns the UTF-16 bytes of the plaintext as hex. Verified on PowerShell 7.4 on
        # Debian, where 'SECRETKEYMATERIAL' came back as 5300450043... and decoded straight
        # back. Treating that as DPAPI recorded Protection = DPAPI and Encrypted = True for a
        # credential sitting in effective plaintext, which is worse than storing it plainly and
        # saying so.
        $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
            ($PSVersionTable.PSObject.Properties['Platform'] -and
                $PSVersionTable.Platform -eq 'Win32NT') -or
            ($env:OS -eq 'Windows_NT')

        if (-not $onWindows) {
            throw 'DPAPI is only available on Windows.'
        }

        $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
        $protected = ConvertFrom-SecureString -SecureString $secure -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($protected) -or $protected -eq $PlainText) {
            throw 'ConvertFrom-SecureString did not return a protected value.'
        }

        # And prove it, rather than assuming the platform check was enough. A hex string that
        # decodes back to the plaintext as UTF-16 is exactly what the non-Windows
        # implementation produces, so this is the check that would catch the same regression
        # arriving by a different route.
        if ($protected -match '^[0-9a-fA-F]+$' -and ($protected.Length % 2) -eq 0) {
            try {
                $raw = [byte[]]::new($protected.Length / 2)
                for ($i = 0; $i -lt $raw.Length; $i++) {
                    $raw[$i] = [Convert]::ToByte($protected.Substring($i * 2, 2), 16)
                }
                if ([System.Text.Encoding]::Unicode.GetString($raw).Contains($PlainText)) {
                    throw 'the protected value still contains the plaintext.'
                }
            }
            catch [System.FormatException] {
                Write-Verbose 'Protected value is not a hex encoding, which is the desired outcome.'
            }
        }

        return [PSCustomObject]@{ Method = 'DPAPI'; Value = $protected }
    }
    catch {
        Write-Warning ("This platform cannot encrypt the credential at rest with DPAPI " +
            "($($_.Exception.Message)). The private key will be written UNPROTECTED, guarded " +
            'only by file permissions. Pass -UseSecretStore for encrypted storage here.')

        return [PSCustomObject]@{ Method = 'None'; Value = $PlainText }
    }
}
