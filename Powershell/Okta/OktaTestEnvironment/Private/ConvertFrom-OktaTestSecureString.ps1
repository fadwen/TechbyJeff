function ConvertFrom-OktaTestSecureString {
    <#
    .SYNOPSIS
        Converts a SecureString to plain text without depending on edition-specific cmdlets

    .DESCRIPTION
        ConvertFrom-SecureString -AsPlainText only exists on PowerShell 7, and the
        PSCredential trick mangles nothing but reads badly at the call site. This uses the
        marshalling API directly and, importantly, frees the unmanaged buffer in a finally
        block so the plain text does not sit in unmanaged memory after an exception.

    .PARAMETER SecureString
        The SecureString to convert

    .OUTPUTS
        String

    .EXAMPLE
        $plain = ConvertFrom-OktaTestSecureString -SecureString $token

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [System.IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
