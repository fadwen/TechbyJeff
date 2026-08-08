function ConvertTo-OktaTestBase64Url {
    <#
    .SYNOPSIS
        Encodes bytes as base64url

    .DESCRIPTION
        JWK members and JWS segments are base64url, which is standard base64 with the two
        URL-unsafe characters swapped and the padding removed.

        Note what this deliberately does not do: it does not strip leading zero bytes. RFC
        7518 says JWK integer members are the minimal big-endian representation, but .NET's
        RSAParameters requires each component to be an exact fixed length, and stripping a
        leading zero on export leaves a key that will not import again. Since the only keys
        this module encodes are ones it generated itself and will later re-import itself, an
        exact byte-for-byte round trip matters more than minimal encoding, and Okta accepts
        the padded form.

    .PARAMETER Bytes
        The bytes to encode

    .OUTPUTS
        String

    .EXAMPLE
        ConvertTo-OktaTestBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes('{"alg":"RS256"}'))

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
