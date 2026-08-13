#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Base64url is where JWT implementations written by hand go wrong, and the failure is
    always the same shape: it works for most inputs and produces an invalid signature for
    some, because whether padding or a '+' turns up depends on the byte length and content of
    the particular key you generated.

    These tests therefore care about the awkward lengths and about inputs that are guaranteed
    to produce the two URL-unsafe characters, rather than about a single happy path.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-OktaTestBase64Url' -Tag 'Unit', 'Private' {

    It 'produces no padding characters' {
        InModuleScope OktaTestEnvironment {
            # Every remainder class in one test: 1, 2 and 3 bytes over a multiple of 3 are the
            # three cases standard base64 pads differently.
            foreach ($length in 1..12) {
                $bytes = [byte[]]@(1..$length)
                $encoded = ConvertTo-OktaTestBase64Url -Bytes $bytes
                $encoded | Should-NotMatchString '='
            }
        }
    }

    It 'produces no URL-unsafe characters' {
        InModuleScope OktaTestEnvironment {
            # 0xFB 0xFF encodes to '+/' in standard base64, so this input is guaranteed to
            # produce both of the characters that must be swapped.
            $bytes = [byte[]]@(0xFB, 0xFF, 0xBF, 0xFF, 0xEF, 0xFF)
            $encoded = ConvertTo-OktaTestBase64Url -Bytes $bytes

            $encoded | Should-NotMatchString '\+'
            $encoded | Should-NotMatchString '/'
        }
    }

    It 'round-trips arbitrary bytes exactly' {
        InModuleScope OktaTestEnvironment {
            $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            foreach ($length in @(1, 2, 3, 16, 31, 32, 255, 256)) {
                $bytes = [byte[]]::new($length)
                $random.GetBytes($bytes)

                $decoded = ConvertFrom-OktaTestBase64Url -Text (ConvertTo-OktaTestBase64Url -Bytes $bytes)

                [Convert]::ToBase64String($decoded) | Should-Be ([Convert]::ToBase64String($bytes))
            }
            $random.Dispose()
        }
    }

    It 'preserves leading zero bytes' {
        InModuleScope OktaTestEnvironment {
            # This is the one that matters for JWK. RFC 7518 says integer members are minimal
            # big-endian, but .NET's RSAParameters requires exact fixed lengths, so a decoder
            # that strips a leading zero produces a key that will not import. The round trip
            # has to be byte-exact, not numerically equal.
            $bytes = [byte[]]@(0x00, 0x00, 0x01, 0x02)
            $decoded = ConvertFrom-OktaTestBase64Url -Text (ConvertTo-OktaTestBase64Url -Bytes $bytes)

            $decoded.Length | Should-Be 4
            $decoded[0] | Should-Be 0
        }
    }

    It 'rejects a string whose length cannot be valid base64url' {
        InModuleScope OktaTestEnvironment {
            { ConvertFrom-OktaTestBase64Url -Text 'AAAAA' } | Should-Throw
        }
    }

    It 'returns an empty array for an empty string' {
        InModuleScope OktaTestEnvironment {
            @(ConvertFrom-OktaTestBase64Url -Text '').Count | Should-Be 0
        }
    }
}
