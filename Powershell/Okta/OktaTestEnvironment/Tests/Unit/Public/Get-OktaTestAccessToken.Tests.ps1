#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    The token request is short but every part of it is load-bearing, and every failure it can
    produce looks the same from the outside: Okta answers 401 invalid_client and says nothing
    about which part was wrong.

    Two of these are worth more than the rest:

    - The audience and the endpoint must be the ORG authorisation server. A token from
      /oauth2/default/v1/token is issued perfectly happily and then rejected by every
      management API call, which sends you looking at scopes and roles instead of the URL.
    - The request must carry NO Authorization header. The client assertion in the body is the
      credential; sending both makes Okta reject it.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'A fake vault password in a suite that never reaches a tenant or a vault.')]
param()

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OktaTestAccessToken' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Import-OktaTestAppCredential {
                [PSCustomObject]@{
                    orgUrl     = 'https://trial-1.okta.com'
                    clientId   = '0oaCLIENT'
                    appId      = '0oaCLIENT'
                    label      = 'Lab'
                    scopes     = @('okta.users.manage', 'okta.groups.manage')
                    protection = 'DPAPI'
                    privateJwk = [PSCustomObject]@{ kid = 'k'; d = 'x' }
                }
            }
            Mock New-OktaTestClientAssertion { 'HEADER.PAYLOAD.SIGNATURE' }
            Mock Get-OktaTestCredentialPath { '/tmp/fake.serviceapp.json' }
            Mock Invoke-OktaTestRequest {
                [PSCustomObject]@{
                    access_token = 'eyJACCESS'
                    token_type   = 'Bearer'
                    scope        = 'okta.users.manage okta.groups.manage'
                    expires_in   = 3600
                }
            }
        }
    }

    It 'posts to the org authorisation server, not the default one' {
        # /oauth2/default/v1/token issues a token that every management call then rejects.
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x'

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/oauth2/v1/token'
            }
        }
    }

    It 'signs the assertion for the token endpoint as audience' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x'

            Should-Invoke New-OktaTestClientAssertion -Times 1 -Exactly -ParameterFilter {
                $Audience -eq 'https://trial-1.okta.com/oauth2/v1/token' -and
                $ClientId -eq '0oaCLIENT'
            }
        }
    }

    It 'sends no Authorization header' {
        # The assertion in the body IS the credential. Sending both makes Okta reject it, and
        # passing an explicit connection is also what stops this recursing through
        # Get-OktaTestConnection when that function renews an expiring token.
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x'

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $null -eq $Connection.AuthorizationHeader
            }
        }
    }

    It 'sends a form-encoded client_credentials grant with the assertion' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x'

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $ContentType -eq 'application/x-www-form-urlencoded' -and
                $Body -match 'grant_type=client_credentials' -and
                $Body -match 'client_assertion=HEADER\.PAYLOAD\.SIGNATURE' -and
                $Body -match ('client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3A' +
                    'client-assertion-type%3Ajwt-bearer')
            }
        }
    }

    It 'requests the scopes recorded on the credential, space separated and encoded' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x'

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Body -match 'scope=okta\.users\.manage%20okta\.groups\.manage'
            }
        }
    }

    It 'lets -Scope narrow the request below what the app holds' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestAccessToken -CredentialPath 'x' -Scope 'okta.users.read'

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Body -match 'scope=okta\.users\.read' -and $Body -notmatch 'groups'
            }
        }
    }

    It 'returns a typed result with the expiry computed from expires_in' {
        InModuleScope OktaTestEnvironment {
            $before = [DateTime]::UtcNow
            $t = Get-OktaTestAccessToken -CredentialPath 'x'

            $t.AccessToken | Should-Be 'eyJACCESS'
            $t.TokenType | Should-Be 'Bearer'
            @($t.Scopes) | Should-BeCollection @('okta.users.manage', 'okta.groups.manage')
            $t.ClientId | Should-Be '0oaCLIENT'
            $t.ExpiresUtc | Should-BeGreaterThan $before.AddSeconds(3500)
        }
    }

    It 'returns just the string with -AsPlainText' {
        # Deliberately not the default: the object carries context, the bare string is a live
        # bearer credential and nothing else.
        InModuleScope OktaTestEnvironment {
            $t = Get-OktaTestAccessToken -CredentialPath 'x' -AsPlainText
            $t | Should-Be 'eyJACCESS'
            $t | Should-HaveType ([string])
        }
    }

    It 'passes the vault password through when the key lives in a vault' {
        InModuleScope OktaTestEnvironment {
            $vaultPassword = ConvertTo-SecureString 'vault' -AsPlainText -Force
            $null = Get-OktaTestAccessToken -CredentialPath 'x' -VaultPassword $vaultPassword

            Should-Invoke Import-OktaTestAppCredential -Times 1 -Exactly -ParameterFilter {
                $null -ne $VaultPassword
            }
        }
    }

    It 'throws when the token endpoint returns no access_token' {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest { [PSCustomObject]@{ token_type = 'Bearer' } }

            { Get-OktaTestAccessToken -CredentialPath 'x' } |
                Should-Throw -ExceptionMessage '*no access_token*'
        }
    }

    It 'throws when the credential records no scopes and none were passed' {
        # Asking for nothing yields a token that is authorised for nothing, which fails later
        # and further away.
        InModuleScope OktaTestEnvironment {
            Mock Import-OktaTestAppCredential {
                [PSCustomObject]@{
                    orgUrl = 'https://trial-1.okta.com'; clientId = '0oaX'; appId = '0oaX'
                    scopes = @(); privateJwk = [PSCustomObject]@{ kid = 'k'; d = 'x' }
                }
            }

            { Get-OktaTestAccessToken -CredentialPath 'x' } |
                Should-Throw -ExceptionMessage '*records no scopes*'
        }
    }

    It 'throws with guidance when there is nothing to locate the credential by' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection { $null }

            { Get-OktaTestAccessToken } | Should-Throw -ExceptionMessage '*connect first*'
        }
    }

    It 'falls back to the connected org when only a connection is available' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection { @{ OrgUrl = 'https://trial-9.okta.com' } }

            $null = Get-OktaTestAccessToken

            Should-Invoke Get-OktaTestCredentialPath -Times 1 -Exactly -ParameterFilter {
                $OrgUrl -eq 'https://trial-9.okta.com'
            }
        }
    }
}
