#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Revoking an Okta API token is permanent. There is no restore, and no way to recreate a token
    with the same value - a replacement is a new token made by hand in the admin console. So the
    resolve step has exactly two acceptable outcomes: one match, or an error.

    The danger is concrete rather than theoretical. The tenant this module was developed against
    held two tokens, one for this work and one named "postman testing". Anything that picked the
    first match, or matched on a prefix, would eventually revoke somebody's working credential.

    The design constraint behind all of it: the module cannot identify the token it is itself
    using. /api/v1/api-tokens/current returns 404 on a standard org, and the list endpoint
    returns ids and names but never token values, so an SSWS string cannot be matched to a row.
    That is why the caller has to name one.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-OktaTestApiToken' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                @(
                    [PSCustomObject]@{ id = '00T4cxwlhd2fCSwol697'; name = 'claude' }
                    [PSCustomObject]@{ id = '00T4cjt31qn3RQ0tr697'; name = 'postman testing' }
                    [PSCustomObject]@{ id = '00T4dupe1'; name = 'duplicate' }
                    [PSCustomObject]@{ id = '00T4dupe2'; name = 'duplicate' }
                )
            }
        }
    }

    It 'resolves an exact name' {
        InModuleScope OktaTestEnvironment {
            (Resolve-OktaTestApiToken -NameOrId 'claude').id | Should-Be '00T4cxwlhd2fCSwol697'
        }
    }

    It 'resolves an exact id' {
        InModuleScope OktaTestEnvironment {
            (Resolve-OktaTestApiToken -NameOrId '00T4cjt31qn3RQ0tr697').name | Should-Be 'postman testing'
        }
    }

    It 'matches a name case-insensitively' {
        InModuleScope OktaTestEnvironment {
            (Resolve-OktaTestApiToken -NameOrId 'CLAUDE').id | Should-Be '00T4cxwlhd2fCSwol697'
        }
    }

    It 'refuses a name that matches more than one token' {
        # Never "pick the first". Two tokens can share a name, and the wrong one is unrecoverable.
        InModuleScope OktaTestEnvironment {
            { Resolve-OktaTestApiToken -NameOrId 'duplicate' } | Should-Throw -ExceptionMessage '*matches 2*'
        }
    }

    It 'refuses a name that matches nothing, and says what does exist' {
        InModuleScope OktaTestEnvironment {
            { Resolve-OktaTestApiToken -NameOrId 'nosuchtoken' } |
                Should-Throw -ExceptionMessage '*postman testing*'
        }
    }

    It 'does not match on a prefix' {
        # 'claud' must not resolve to 'claude'. A near miss here deletes a credential.
        InModuleScope OktaTestEnvironment {
            { Resolve-OktaTestApiToken -NameOrId 'claud' } | Should-Throw
        }
    }

    It 'does not treat a wildcard as a wildcard' {
        InModuleScope OktaTestEnvironment {
            { Resolve-OktaTestApiToken -NameOrId '*' } | Should-Throw
        }
    }

    It 'reports plainly when the org has no tokens at all' {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest { @() }
            { Resolve-OktaTestApiToken -NameOrId 'anything' } | Should-Throw -ExceptionMessage '*no API tokens*'
        }
    }
}

Describe 'Revoke-OktaTestApiToken' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest { $null }
        }
    }

    It 'deletes the token it was given' {
        InModuleScope OktaTestEnvironment {
            $revoked = Revoke-OktaTestApiToken -TokenId '00T4abc' -TokenName 'bootstrap' -Confirm:$false

            $revoked | Should-BeTrue
            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Path -eq '/api/v1/api-tokens/00T4abc'
            }
        }
    }

    It 'revokes nothing under -WhatIf' {
        InModuleScope OktaTestEnvironment {
            $revoked = Revoke-OktaTestApiToken -TokenId '00T4abc' -TokenName 'bootstrap' -WhatIf

            $revoked | Should-BeFalse
            Should-NotInvoke Invoke-OktaTestRequest
        }
    }
}

Describe 'New-OktaTestServiceApp revoke interlock' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl              = 'https://trial-1.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                }
            }
            Mock Write-OktaTestProgress { }
            Mock New-OktaTestRsaKeyPair {
                [PSCustomObject]@{
                    KeyId = 'k'; KeySize = 2048
                    PublicJwk = @{ kid = 'k' }; PrivateJwk = @{ kid = 'k' }
                }
            }
            Mock Export-OktaTestAppCredential {
                [PSCustomObject]@{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $true }
            }
            Mock Get-OktaTestCredentialPath { 'C:\temp\fake.serviceapp.json' }
            Mock Resolve-OktaTestApiToken { [PSCustomObject]@{ id = '00T4abc'; name = 'bootstrap' } }
            Mock Revoke-OktaTestApiToken { $true }

            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/oauth2/v1/clients') {
                    return [PSCustomObject]@{ client_id = '0oaNEW' }
                }
                if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                    return [PSCustomObject]@{ id = '0oaNEW' }
                }
                return $null
            }
        }
    }

    It 'revokes the named token once the app has proven itself' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }

            $r = New-OktaTestServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false

            $r.ApiTokenRevoked | Should-Be 'bootstrap'
            Should-Invoke Revoke-OktaTestApiToken -Times 1 -Exactly
        }
    }

    It 'refuses to revoke when the new app cannot issue a token' {
        # The interlock that matters most. Rotating this app's key later needs an SSWS token,
        # so discarding the bootstrap credential before the replacement works would leave no
        # way back except the admin console.
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestAccessToken { throw 'invalid_client' }

            $r = New-OktaTestServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            $r.ApiTokenRevoked | Should-BeNull
            Should-NotInvoke Revoke-OktaTestApiToken
        }
    }

    It 'says why it declined to revoke' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestAccessToken { throw 'invalid_client' }

            $r = New-OktaTestServiceApp -RevokeApiToken 'bootstrap' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            (@($r.Warnings) -join ' ') | Should-MatchString 'Not revoking'
        }
    }

    It 'revokes nothing when no token is named' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }

            $null = New-OktaTestServiceApp -PassThru -Confirm:$false

            Should-NotInvoke Resolve-OktaTestApiToken
            Should-NotInvoke Revoke-OktaTestApiToken
        }
    }

    It 'carries on when the token cannot be resolved, rather than failing the app creation' {
        # The app exists and works at this point. An unresolvable token name is a reason to warn,
        # not to make the caller think the whole operation failed.
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestAccessToken { [PSCustomObject]@{ Scopes = @('okta.users.manage') } }
            Mock Resolve-OktaTestApiToken { throw "matches 2 API tokens" }

            $r = New-OktaTestServiceApp -RevokeApiToken 'duplicate' -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            $r.ClientId | Should-Be '0oaNEW'
            $r.ApiTokenRevoked | Should-BeNull
            (@($r.Warnings) -join ' ') | Should-MatchString 'Could not revoke'
        }
    }
}
