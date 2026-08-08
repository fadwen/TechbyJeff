#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    The client assertion is the one piece of this module that cannot fail loudly. If the JWT
    is malformed, Okta answers 401 invalid_client and says nothing about which part was
    wrong, so a signature computed over the wrong bytes, a claim with the wrong name, or a
    key that did not survive the JWK round trip all look identical from the outside.

    These tests verify the signature with the public half of the same key, which is exactly
    what Okta does, and check each claim Okta validates. They generate a real key, so they
    are slower than the rest of the suite and still touch no network.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestClientAssertion' -Tag 'Unit', 'Private' {

    BeforeAll {
        InModuleScope OktaTestEnvironment {
            $script:KeyPair = New-OktaTestRsaKeyPair -KeySize 2048
            $script:Assertion = New-OktaTestClientAssertion -PrivateJwk $script:KeyPair.PrivateJwk `
                -ClientId '0oaTESTCLIENTID' -Audience 'https://trial-123456.okta.com/oauth2/v1/token'
        }
    }

    It 'produces three dot-separated segments' {
        InModuleScope OktaTestEnvironment {
            @($script:Assertion -split '\.').Count | Should-Be 3
        }
    }

    It 'signs with RS256 and names the key' {
        InModuleScope OktaTestEnvironment {
            $header = [System.Text.Encoding]::UTF8.GetString(
                (ConvertFrom-OktaTestBase64Url -Text ($script:Assertion -split '\.')[0])) | ConvertFrom-Json

            $header.alg | Should-Be 'RS256'
            $header.typ | Should-Be 'JWT'
            $header.kid | Should-Be $script:KeyPair.KeyId
        }
    }

    It 'sets both iss and sub to the client id, which is what Okta checks' {
        InModuleScope OktaTestEnvironment {
            $payload = [System.Text.Encoding]::UTF8.GetString(
                (ConvertFrom-OktaTestBase64Url -Text ($script:Assertion -split '\.')[1])) | ConvertFrom-Json

            $payload.iss | Should-Be '0oaTESTCLIENTID'
            $payload.sub | Should-Be '0oaTESTCLIENTID'
        }
    }

    It 'sets aud to the token endpoint rather than the org root' {
        # An assertion aimed at https://org rather than https://org/oauth2/v1/token is
        # rejected, and the error does not say so.
        InModuleScope OktaTestEnvironment {
            $payload = [System.Text.Encoding]::UTF8.GetString(
                (ConvertFrom-OktaTestBase64Url -Text ($script:Assertion -split '\.')[1])) | ConvertFrom-Json

            $payload.aud | Should-Be 'https://trial-123456.okta.com/oauth2/v1/token'
        }
    }

    It 'expires inside the hour Okta allows' {
        InModuleScope OktaTestEnvironment {
            $payload = [System.Text.Encoding]::UTF8.GetString(
                (ConvertFrom-OktaTestBase64Url -Text ($script:Assertion -split '\.')[1])) | ConvertFrom-Json

            $lifetime = $payload.exp - $payload.iat
            $lifetime | Should-BeGreaterThan 0
            $lifetime | Should-BeLessThanOrEqual 3600
        }
    }

    It 'carries a jti so the assertion cannot be replayed' {
        InModuleScope OktaTestEnvironment {
            $payload = [System.Text.Encoding]::UTF8.GetString(
                (ConvertFrom-OktaTestBase64Url -Text ($script:Assertion -split '\.')[1])) | ConvertFrom-Json

            $payload.jti | Should-NotBeNull
        }
    }

    It 'produces a signature that verifies against the public JWK' {
        # The assertion that actually matters. It exercises the whole path: RSAParameters out
        # to base64url, back in through ImportParameters, and a signature over the exact bytes
        # a verifier will hash. If the JWK round trip loses a leading zero anywhere, this is
        # where it shows up.
        InModuleScope OktaTestEnvironment {
            $segments = $script:Assertion -split '\.'
            $signingInput = [System.Text.Encoding]::ASCII.GetBytes("$($segments[0]).$($segments[1])")
            $signature = ConvertFrom-OktaTestBase64Url -Text $segments[2]

            $parameters = New-Object System.Security.Cryptography.RSAParameters
            $parameters.Modulus = ConvertFrom-OktaTestBase64Url -Text $script:KeyPair.PublicJwk.n
            $parameters.Exponent = ConvertFrom-OktaTestBase64Url -Text $script:KeyPair.PublicJwk.e

            $verifier = [System.Security.Cryptography.RSA]::Create()
            $verifier.ImportParameters($parameters)

            $verified = $verifier.VerifyData(
                $signingInput,
                $signature,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $verifier.Dispose()

            $verified | Should-BeTrue
        }
    }

    It 'produces a different assertion each time' {
        InModuleScope OktaTestEnvironment {
            $second = New-OktaTestClientAssertion -PrivateJwk $script:KeyPair.PrivateJwk `
                -ClientId '0oaTESTCLIENTID' -Audience 'https://trial-123456.okta.com/oauth2/v1/token'

            $second | Should-NotBe $script:Assertion
        }
    }

    It 'refuses a public JWK with a message that says why' {
        # Handing the public half to the signer is an easy mistake, and without this guard the
        # symptom is an ImportParameters error about key lengths rather than anything that
        # names the cause.
        InModuleScope OktaTestEnvironment {
            { New-OktaTestClientAssertion -PrivateJwk $script:KeyPair.PublicJwk `
                -ClientId '0oaTESTCLIENTID' -Audience 'https://x/oauth2/v1/token' } |
                Should-Throw -ExceptionMessage '*public key*'
        }
    }
}

Describe 'New-OktaTestRsaKeyPair' -Tag 'Unit', 'Private' {

    It 'keeps the private members out of the public JWK' {
        # The public JWK is sent to Okta. A private member leaking into it would publish the
        # signing key, and the request would still succeed, so nothing else would notice.
        InModuleScope OktaTestEnvironment {
            $keyPair = New-OktaTestRsaKeyPair -KeySize 2048

            foreach ($secret in @('d', 'p', 'q', 'dp', 'dq', 'qi')) {
                $keyPair.PublicJwk.Contains($secret) | Should-BeFalse
            }
        }
    }

    It 'produces a key of the size that was asked for' {
        InModuleScope OktaTestEnvironment {
            (New-OktaTestRsaKeyPair -KeySize 2048).KeySize | Should-Be 2048
        }
    }

    It 'gives both halves the same key id' {
        InModuleScope OktaTestEnvironment {
            $keyPair = New-OktaTestRsaKeyPair -KeySize 2048
            $keyPair.PrivateJwk.kid | Should-Be $keyPair.PublicJwk.kid
        }
    }
}
