#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    Encryption at rest for the service app private key, which can mint admin-scoped tokens for
    the tenant.

    The failure mode these guard against is the quiet one: a value that looks encrypted and is
    not. ConvertFrom-SecureString returns a long hex string either way, so "it produced output"
    proves nothing. The tests therefore assert on the two properties that actually matter -
    the plaintext is not recoverable by inspection, and the round trip is exact - rather than
    on the shape of the result.

    The credential file tests cover the storage modes end to end, including reading back a
    schema version 1 file written before this module encrypted anything, because refusing those
    would strand an environment seeded with an earlier build.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "okta-cred-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    # Inside InModuleScope, $script: resolves to the MODULE's scope rather than this file's, so
    # the path has to be pushed across explicitly. Reading $script:Scratch in there without this
    # silently yields $null, which surfaces as "cannot bind argument to parameter 'Path'".
    InModuleScope OktaTestEnvironment -Parameters @{ ScratchPath = $script:Scratch } {
        param($ScratchPath)
        $script:Scratch = $ScratchPath
    }
}

AfterAll {
    Remove-Item -Path $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Protect-OktaTestSecret' -Tag 'Unit', 'Private' {

    It 'does not leave the plaintext recoverable by inspection' {
        InModuleScope OktaTestEnvironment {
            $secret = 'kty-RSA-d-VERYSECRETKEYMATERIAL'
            $protected = Protect-OktaTestSecret -PlainText $secret

            $protected.Value | Should-NotBe $secret
            $protected.Value.Contains('VERYSECRET') | Should-BeFalse
            $protected.Value.Contains($secret) | Should-BeFalse
        }
    }

    It 'round-trips exactly, including JSON punctuation and non-ASCII' {
        InModuleScope OktaTestEnvironment {
            $secret = '{"kty":"RSA","note":"a `$dollar, a ''quote'' and Z' + [string][char]0xFC + 'rich"}'
            $protected = Protect-OktaTestSecret -PlainText $secret

            Unprotect-OktaTestSecret -Method $protected.Method -Value $protected.Value |
                Should-Be $secret
        }
    }

    It 'reports DPAPI on Windows so the caller can record what it wrote' {
        # The Method is written into the credential file and drives how it is read back, so a
        # wrong value here is unrecoverable rather than merely inaccurate.
        InModuleScope OktaTestEnvironment {
            if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
                (Protect-OktaTestSecret -PlainText 'x').Method | Should-Be 'DPAPI'
            }
        }
    }

    It 'never returns a value the plaintext can be read straight back out of' {
        # The regression, found by running on Linux. ConvertFrom-SecureString does not throw
        # off Windows and does not encrypt either - it returns the UTF-16 bytes of the
        # plaintext as hex, so 'SECRETKEYMATERIAL' came back as 5300450043... and decoded
        # straight back. The module recorded Protection = DPAPI and Encrypted = True for a
        # credential sitting in effective plaintext.
        #
        # This asserts the property rather than the platform, so it holds wherever it runs:
        # if the Method says DPAPI, the value must not be a hex encoding of the plaintext.
        InModuleScope OktaTestEnvironment {
            $secret = 'SECRETKEYMATERIAL'
            $protected = Protect-OktaTestSecret -PlainText $secret -WarningAction SilentlyContinue

            if ($protected.Method -eq 'DPAPI') {
                $isHex = $protected.Value -match '^[0-9a-fA-F]+$' -and
                    ($protected.Value.Length % 2) -eq 0
                if ($isHex) {
                    $raw = [byte[]]::new($protected.Value.Length / 2)
                    for ($i = 0; $i -lt $raw.Length; $i++) {
                        $raw[$i] = [Convert]::ToByte($protected.Value.Substring($i * 2, 2), 16)
                    }
                    [System.Text.Encoding]::Unicode.GetString($raw).Contains($secret) |
                        Should-BeFalse
                }
            }
        }
    }

    It 'claims DPAPI only on Windows' {
        InModuleScope OktaTestEnvironment {
            $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
                ($PSVersionTable.PSObject.Properties['Platform'] -and
                    $PSVersionTable.Platform -eq 'Win32NT') -or ($env:OS -eq 'Windows_NT')

            $method = (Protect-OktaTestSecret -PlainText 'x' -WarningAction SilentlyContinue).Method

            if ($onWindows) { $method | Should-Be 'DPAPI' } else { $method | Should-Be 'None' }
        }
    }

    It 'passes an unprotected value straight through when the method says None' {
        InModuleScope OktaTestEnvironment {
            Unprotect-OktaTestSecret -Method 'None' -Value 'plain' | Should-Be 'plain'
        }
    }

    It 'explains what to do when a DPAPI blob will not decrypt' {
        # DPAPI ties the secret to the user and the machine, so this is what a copied profile
        # looks like. The raw CryptographicException names none of that.
        InModuleScope OktaTestEnvironment {
            { Unprotect-OktaTestSecret -Method 'DPAPI' -Value 'deadbeefnotarealblob' } |
                Should-Throw -ExceptionMessage '*machine*'
        }
    }
}

Describe 'Credential file storage' -Tag 'Unit', 'Private' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            $script:Jwk = [ordered]@{
                kty = 'RSA'; kid = 'test-kid'; alg = 'RS256'
                e = 'AQAB'; n = 'bW9kdWx1cw'; d = 'U0VDUkVUS0VZTUFURVJJQUw'
                p = 'cA'; q = 'cQ'; dp = 'ZHA'; dq = 'ZHE'; qi = 'cWk'
            }
        }
    }

    It 'writes no readable key material to disk by default' {
        # The whole point of the change. Anyone who can read the file must not be able to read
        # the key out of it.
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'default.json'
            $null = Export-OktaTestAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $raw = Get-Content -Path $path -Raw
            $raw.Contains('U0VDUkVUS0VZTUFURVJJQUw') | Should-BeFalse
            $raw.Contains('"d"') | Should-BeFalse
        }
    }

    It 'records the protection method it actually used' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'method.json'
            $result = Export-OktaTestAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $stored = Get-Content -Path $path -Raw | ConvertFrom-Json
            $stored.schemaVersion | Should-Be 2
            $stored.protection | Should-Be $result.Protection
        }
    }

    It 'round-trips the key through the file unchanged' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'roundtrip.json'
            $null = Export-OktaTestAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $script:Jwk -Confirm:$false

            $read = Import-OktaTestAppCredential -Path $path

            $read.privateJwk.d | Should-Be 'U0VDUkVUS0VZTUFURVJJQUw'
            $read.privateJwk.kid | Should-Be 'test-kid'
            $read.clientId | Should-Be '0oaTEST'
            @($read.scopes) | Should-BeCollection @('okta.users.manage')
        }
    }

    It 'produces a key that can still sign an assertion after the round trip' {
        # The end-to-end property. Encryption that corrupts the key by a byte would pass every
        # test above and fail only against Okta, with a 401 that explains nothing.
        InModuleScope OktaTestEnvironment {
            $keyPair = New-OktaTestRsaKeyPair -KeySize 2048
            $path = Join-Path $script:Scratch 'signing.json'

            $null = Export-OktaTestAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                -PrivateJwk $keyPair.PrivateJwk -Confirm:$false

            $read = Import-OktaTestAppCredential -Path $path
            $assertion = New-OktaTestClientAssertion -PrivateJwk $read.privateJwk `
                -ClientId '0oaTEST' -Audience 'https://trial-1.okta.com/oauth2/v1/token'

            @($assertion -split '\.').Count | Should-Be 3
        }
    }

    It 'still reads a schema version 1 file, and says it should be replaced' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'legacy.json'
            $legacy = [ordered]@{
                schemaVersion = 1
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaLEGACY'
                appId         = '0oaLEGACY'
                label         = 'Lab'
                scopes        = @('okta.users.manage')
                privateJwk    = $script:Jwk
            }
            Set-Content -Path $path -Value ($legacy | ConvertTo-Json -Depth 10)

            $warnings = @()
            $read = Import-OktaTestAppCredential -Path $path -WarningVariable warnings `
                -WarningAction SilentlyContinue

            $read.privateJwk.d | Should-Be 'U0VDUkVUS0VZTUFURVJJQUw'
            $read.protection | Should-Be 'None'
            @($warnings).Count | Should-BeGreaterThan 0
        }
    }

    It 'refuses a file whose protection method and payload disagree' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'mismatch.json'
            Set-Content -Path $path -Value (@{
                schemaVersion = 2
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaX'
                appId         = '0oaX'
                protection    = 'DPAPI'
            } | ConvertTo-Json)

            { Import-OktaTestAppCredential -Path $path } | Should-Throw -ExceptionMessage '*no protected key*'
        }
    }

    It 'refuses a SecretStore pointer that names no vault' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'novault.json'
            Set-Content -Path $path -Value (@{
                schemaVersion = 2
                orgUrl        = 'https://trial-1.okta.com'
                clientId      = '0oaX'
                appId         = '0oaX'
                protection    = 'SecretStore'
            } | ConvertTo-Json)

            { Import-OktaTestAppCredential -Path $path } |
                Should-Throw -ExceptionMessage '*does not name the vault*'
        }
    }

    It 'restricts the credential file to the current user' {
        InModuleScope OktaTestEnvironment {
            if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
                $path = Join-Path $script:Scratch 'acl.json'
                $null = Export-OktaTestAppCredential -Path $path -OrgUrl 'https://trial-1.okta.com' `
                    -ClientId '0oaTEST' -AppId '0oaTEST' -Label 'Lab' -Scopes @('okta.users.manage') `
                    -PrivateJwk $script:Jwk -Confirm:$false

                $acl = Get-Acl -Path $path
                $acl.AreAccessRulesProtected | Should-BeTrue
                @($acl.Access).Count | Should-Be 1
            }
        }
    }
}
