function ConvertFrom-OktaTestBase64Url {
    <#
    .SYNOPSIS
        Decodes a base64url string back to bytes

    .DESCRIPTION
        Reverses ConvertTo-OktaTestBase64Url: restores the URL-unsafe characters and puts
        back the padding that base64url strips, which [Convert]::FromBase64String requires.

    .PARAMETER Text
        The base64url text to decode

    .OUTPUTS
        Byte array

    .EXAMPLE
        $bytes = ConvertFrom-OktaTestBase64Url -Text $jwk.n

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return [byte[]]@() }

    $standard = $Text.Replace('-', '+').Replace('_', '/')
    switch ($standard.Length % 4) {
        2 { $standard += '==' }
        3 { $standard += '=' }
        1 { throw "'$Text' is not valid base64url: its length leaves one character over." }
    }

    return [Convert]::FromBase64String($standard)
}
