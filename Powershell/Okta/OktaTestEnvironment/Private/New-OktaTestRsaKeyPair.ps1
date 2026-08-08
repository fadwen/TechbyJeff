function New-OktaTestRsaKeyPair {
    <#
    .SYNOPSIS
        Generates an RSA key pair and returns it as a public and a private JWK

    .DESCRIPTION
        The service app authenticates with private_key_jwt, which means Okta holds the public
        key and this machine holds the private one. Okta wants the public half as a JWK, so
        JWK is also the most convenient shape to store the private half in: it survives a
        round trip through JSON, it is what the Okta admin console shows you, and it avoids
        PEM export entirely.

        PEM is avoided on purpose. ExportRSAPrivateKey does not exist on .NET Framework, so a
        PEM path would mean hand-rolling DER encoding to keep Windows PowerShell 5.1 working.
        A private JWK needs no encoding beyond base64url and imports back into RSAParameters
        directly.

        The key is never written to disk by this function. Export-OktaTestAppCredential owns
        that decision, and the ACL that goes with it.

    .PARAMETER KeySize
        RSA modulus size in bits. Okta accepts 2048 and above.

    .PARAMETER KeyId
        The kid to stamp on both halves. Defaults to a new GUID.

    .OUTPUTS
        PSCustomObject with KeyId, PublicJwk (hashtable, safe to send to Okta) and
        PrivateJwk (hashtable, secret).

    .EXAMPLE
        $keyPair = New-OktaTestRsaKeyPair
        $keyPair.PublicJwk

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Nothing outside this process is changed; the key is returned, never stored.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet(2048, 3072, 4096)]
        [int]$KeySize = 2048,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$KeyId = [Guid]::NewGuid().ToString()
    )

    $rsa = $null
    try {
        # RSA.Create(int) is the portable call on PowerShell 7 and on .NET Framework 4.7.2,
        # but not on every 4.x that Windows PowerShell 5.1 might be sitting on. Fall back to
        # the concrete CSP type, which has taken a key size in its constructor since .NET 1.
        try {
            $rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
        }
        catch {
            Write-Verbose "RSA::Create(int) unavailable ($($_.Exception.Message)); using RSACryptoServiceProvider."
            $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider($KeySize)
        }

        if ($rsa.KeySize -ne $KeySize) {
            throw "Requested a $KeySize-bit key but the provider produced $($rsa.KeySize) bits."
        }

        $parameters = $rsa.ExportParameters($true)

        $publicJwk = [ordered]@{
            kty = 'RSA'
            kid = $KeyId
            use = 'sig'
            alg = 'RS256'
            e   = ConvertTo-OktaTestBase64Url -Bytes $parameters.Exponent
            n   = ConvertTo-OktaTestBase64Url -Bytes $parameters.Modulus
        }

        # The private members are the CRT parameters. Keeping all of them, rather than just
        # d, is what lets ImportParameters reconstruct the key without recomputing anything.
        $privateJwk = [ordered]@{
            kty = 'RSA'
            kid = $KeyId
            use = 'sig'
            alg = 'RS256'
            e   = $publicJwk.e
            n   = $publicJwk.n
            d   = ConvertTo-OktaTestBase64Url -Bytes $parameters.D
            p   = ConvertTo-OktaTestBase64Url -Bytes $parameters.P
            q   = ConvertTo-OktaTestBase64Url -Bytes $parameters.Q
            dp  = ConvertTo-OktaTestBase64Url -Bytes $parameters.DP
            dq  = ConvertTo-OktaTestBase64Url -Bytes $parameters.DQ
            qi  = ConvertTo-OktaTestBase64Url -Bytes $parameters.InverseQ
        }

        return [PSCustomObject]@{
            KeyId      = $KeyId
            KeySize    = $rsa.KeySize
            PublicJwk  = $publicJwk
            PrivateJwk = $privateJwk
        }
    }
    finally {
        if ($rsa -is [System.IDisposable]) { $rsa.Dispose() }
    }
}
