function Unprotect-OktaTestSecret {
    <#
    .SYNOPSIS
        Reverses Protect-OktaTestSecret

    .DESCRIPTION
        Reads the protection method recorded beside the value rather than guessing from the
        value's shape, so a DPAPI string and an unprotected one cannot be confused.

        The failure worth naming is a DPAPI blob that will not decrypt. That means the file was
        written by a different user or on a different machine, because DPAPI keys the secret to
        both. It is a common thing to hit after copying a profile or moving a lab between
        machines, and the raw CryptographicException says nothing about the cause, so it is
        translated here into the actual remedy.

    .PARAMETER Method
        The protection method recorded with the value: 'DPAPI' or 'None'

    .PARAMETER Value
        The protected value

    .OUTPUTS
        String containing the original secret

    .EXAMPLE
        $json = Unprotect-OktaTestSecret -Method 'DPAPI' -Value $credential.privateJwkProtected

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DPAPI', 'None')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    if ($Method -eq 'None') { return $Value }

    try {
        $secure = ConvertTo-SecureString -String $Value -ErrorAction Stop
        return ConvertFrom-OktaTestSecureString -SecureString $secure
    }
    catch {
        throw ('The stored credential could not be decrypted. DPAPI ties it to the user ' +
            'account and machine that created it, so this usually means the file was copied ' +
            'from elsewhere. Re-run New-OktaTestServiceApp -Force with an SSWS token to mint ' +
            "a new key on this machine. Underlying error: $($_.Exception.Message)")
    }
}
