function New-OktaTestClientAssertion {
    <#
    .SYNOPSIS
        Builds the signed JWT the service app presents instead of a client secret

    .DESCRIPTION
        Okta's private_key_jwt client authentication wants an RS256-signed JWT whose issuer
        and subject are both the client_id and whose audience is the org token endpoint. This
        assembles that JWT from the private JWK produced by New-OktaTestRsaKeyPair.

        Written by hand rather than pulled from a JWT library because the whole point of this
        module is that it installs nothing. Requiring a gallery module just to get an access
        token would undercut that, and the signing itself is a dozen lines of in-box .NET.

        The lifetime is short on purpose. The assertion is single use in practice, Okta
        rejects anything longer than an hour, and there is no reason for the window to be
        wider than one request.

    .PARAMETER PrivateJwk
        The private JWK, either as a hashtable or as the object parsed out of the saved
        credential file

    .PARAMETER ClientId
        The service app client_id, used as both iss and sub

    .PARAMETER Audience
        The token endpoint URL, which is what Okta checks aud against

    .PARAMETER LifetimeSeconds
        How long the assertion stays valid. Okta's ceiling is one hour.

    .OUTPUTS
        String containing the compact-serialised JWT

    .EXAMPLE
        $assertion = New-OktaTestClientAssertion -PrivateJwk $jwk -ClientId $clientId `
            -Audience 'https://dev-123456.okta.com/oauth2/v1/token'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds and returns a string. Nothing is created, sent or persisted.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PrivateJwk,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Audience,

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int]$LifetimeSeconds = 300
    )

    foreach ($member in @('n', 'e', 'd', 'p', 'q', 'dp', 'dq', 'qi')) {
        if (-not $PrivateJwk.$member) {
            throw ("The private JWK is missing the '$member' member, so it is a public key " +
                'rather than a private one. Re-run New-OktaTestServiceApp to mint a new pair.')
        }
    }

    $rsa = $null
    try {
        $parameters = New-Object System.Security.Cryptography.RSAParameters
        $parameters.Modulus  = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.n
        $parameters.Exponent = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.e
        $parameters.D        = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.d
        $parameters.P        = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.p
        $parameters.Q        = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.q
        $parameters.DP       = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.dp
        $parameters.DQ       = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.dq
        $parameters.InverseQ = ConvertFrom-OktaTestBase64Url -Text $PrivateJwk.qi

        try {
            $rsa = [System.Security.Cryptography.RSA]::Create()
        }
        catch {
            Write-Verbose "RSA::Create() unavailable ($($_.Exception.Message)); using RSACryptoServiceProvider."
            $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        }
        $rsa.ImportParameters($parameters)

        $header = [ordered]@{ alg = 'RS256'; typ = 'JWT' }
        if ($PrivateJwk.kid) { $header.kid = $PrivateJwk.kid }

        $issuedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $payload = [ordered]@{
            iss = $ClientId
            sub = $ClientId
            aud = $Audience
            iat = $issuedAt
            exp = $issuedAt + $LifetimeSeconds
            jti = [Guid]::NewGuid().ToString()
        }

        $encodedHeader = ConvertTo-OktaTestBase64Url -Bytes (
            [System.Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))
        $encodedPayload = ConvertTo-OktaTestBase64Url -Bytes (
            [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress)))

        $signingInput = "$encodedHeader.$encodedPayload"
        $signature = $rsa.SignData(
            [System.Text.Encoding]::ASCII.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        return "$signingInput.$(ConvertTo-OktaTestBase64Url -Bytes $signature)"
    }
    finally {
        if ($rsa -is [System.IDisposable]) { $rsa.Dispose() }
    }
}
