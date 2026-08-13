#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Registering the OAuth service app that replaces the bootstrap SSWS token.

    Most of this is ordinary seeding, but three behaviours are irreversible or close to it, and
    those are what most of the file is about:

    - Refusing to create a second app with the same label. Re-registering does not replace the
      first app, it produces a second, and the credential file for the old one stops working -
      so the private key of a still-existing app is gone.
    - Revoking the bootstrap API token ONLY after the new app has proven it can issue a token.
      Okta cannot restore a revoked token or recreate one with the same value, and rotating this
      app's key later needs an SSWS token, so revoking an unproven replacement leaves no way
      back except the admin console.
    - Saying out loud when the private key ended up unencrypted.

    A test that passes because a mock was never reached would hide exactly these, so the
    interlock tests assert on the revoke call not happening rather than on the warning text.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestServiceApp' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl   = 'https://trial-1.okta.com'
                    Prefix   = 'OKTALAB'
                    AuthType = 'ApiToken'
                }
            }

            Mock Get-OktaTestCredentialPath { 'TestDrive:/okta-app.json' }
            Mock New-OktaTestRsaKeyPair {
                @{
                    PublicJwk  = @{ kty = 'RSA'; kid = 'kid-1'; n = 'nnn'; e = 'AQAB' }
                    PrivateJwk = @{ kty = 'RSA'; kid = 'kid-1'; d = 'ddd' }
                }
            }

            # Protected and encrypted by default, so the warning paths only fire where a test
            # deliberately puts them in a worse state.
            Mock Export-OktaTestAppCredential {
                @{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $true }
            }

            Mock Get-OktaTestAccessToken { @{ Scopes = @('okta.users.manage') } }
            Mock Write-OktaTestProgress { }
            Mock Resolve-OktaTestApiToken { @{ id = 'tok1'; name = 'bootstrap' } }
            Mock Revoke-OktaTestApiToken { $true }

            # No app exists yet; registration returns a client id.
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                if ($Path -eq '/oauth2/v1/clients') { return [PSCustomObject]@{ client_id = 'cid1' } }
                if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                    return [PSCustomObject]@{ id = 'app1' }
                }
                return $null
            }
        }
    }

    Context 'Core Functionality' {

        It 'registers a service app that authenticates with a key rather than a secret' {
            # private_key_jwt with an inline JWKS is what makes the app usable without storing
            # a shared secret anywhere. A client secret would defeat the point of the exercise.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestServiceApp -PassThru -Confirm:$false

                $r.ClientId | Should-Be 'cid1'
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients' -and
                    $Body.token_endpoint_auth_method -eq 'private_key_jwt' -and
                    $Body.application_type -eq 'service' -and
                    $Body.grant_types -contains 'client_credentials' -and
                    @($Body.jwks.keys).Count -eq 1
                }
            }
        }

        It 'reads the app instance back rather than assuming the id matches the client id' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestServiceApp -PassThru -Confirm:$false
                $r.AppId | Should-Be 'app1'
            }
        }

        It 'falls back to the client id when the app instance cannot be read' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') { throw 'HTTP 404' }
                    return $null
                }

                $r = New-OktaTestServiceApp -PassThru -Confirm:$false
                $r.AppId | Should-Be 'cid1'
            }
        }

        It 'grants every requested scope and assigns every requested role' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestServiceApp -Scope okta.users.read, okta.groups.read `
                    -AdminRole READ_ONLY_ADMIN -PassThru -Confirm:$false

                @($r.Scopes) | Should-BeCollection @('okta.users.read', 'okta.groups.read')
                @($r.AdminRoles) | Should-BeCollection @('READ_ONLY_ADMIN')
                @($r.Warnings) | Should-BeCollection -Count 0
            }
        }

        It 'warns when connected as something other than an API token' {
            # The seeded app is deliberately not granted okta.clients.manage, so it cannot
            # register another app. Failing later with a bare 403 explains nothing.
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestConnection {
                    @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'; AuthType = 'ServiceApp' }
                }

                $null = New-OktaTestServiceApp -PassThru -Confirm:$false -WarningVariable warned `
                    -WarningAction SilentlyContinue

                @($warned) | Should-BeCollection -Count 1
                "$warned" | Should-MatchString 'okta\.clients\.manage'
            }
        }
    }

    Context 'Replacing An Existing App' -Tag 'Security' {

        It 'refuses to create a second app with the same label' {
            # Re-registering produces a second app rather than replacing the first, and the
            # credential file for the old one is overwritten - so its key is gone while the app
            # itself still exists and still has SUPER_ADMIN.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') {
                        return @([PSCustomObject]@{
                            id = 'existing1'; label = 'OKTALAB Test Environment Automation' })
                    }
                    return $null
                }

                { New-OktaTestServiceApp -Confirm:$false } |
                    Should-Throw -ExceptionMessage '*already exists*'

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients'
                }
            }
        }

        It 'deactivates before deleting when replacing with -Force' {
            # Okta refuses to delete an active app, so a missing deactivate turns -Force into
            # a failure that leaves the old app in place.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') {
                        return @([PSCustomObject]@{
                            id = 'existing1'; label = 'OKTALAB Test Environment Automation' })
                    }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    return $null
                }

                $null = New-OktaTestServiceApp -Force -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/apps/existing1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/apps/existing1'
                }
            }
        }
    }

    Context 'Credential Protection' -Tag 'Security' {

        It 'passes the vault through when asked for SecretStore' {
            InModuleScope OktaTestEnvironment {
                Mock Export-OktaTestAppCredential {
                    @{ Protection = 'SecretStore'; VaultName = 'MyVault'; FileProtected = $true }
                }

                $r = New-OktaTestServiceApp -UseSecretStore -VaultName MyVault `
                    -PassThru -Confirm:$false

                $r.Protection | Should-Be 'SecretStore'
                Should-Invoke Export-OktaTestAppCredential -Times 1 -Exactly -ParameterFilter {
                    $UseSecretStore -and $VaultName -eq 'MyVault'
                }
            }
        }

        It 'says so when the private key ends up unencrypted' {
            # An unprotected key is a state the user can fix, but only if they are told they
            # are in it. Recording it only in the file would not reach anyone.
            InModuleScope OktaTestEnvironment {
                Mock Export-OktaTestAppCredential {
                    @{ Protection = 'None'; VaultName = $null; FileProtected = $true }
                }

                $r = New-OktaTestServiceApp -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                @($r.Warnings | Where-Object { $_ -match 'UNENCRYPTED' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'says so when the file could not be locked down' {
            InModuleScope OktaTestEnvironment {
                Mock Export-OktaTestAppCredential {
                    @{ Protection = 'DPAPI'; VaultName = $null; FileProtected = $false }
                }

                $r = New-OktaTestServiceApp -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                @($r.Warnings | Where-Object { $_ -match 'could not be' }) |
                    Should-BeCollection -Count 1
            }
        }
    }

    Context 'API Token Revocation' -Tag 'Security' {

        It 'revokes the named token once the new app has issued one' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false

                $r.ApiTokenRevoked | Should-Be 'bootstrap'
                Should-Invoke Revoke-OktaTestApiToken -Times 1 -Exactly -ParameterFilter {
                    $TokenId -eq 'tok1'
                }
            }
        }

        It 'does not revoke when the new app could not issue a token' {
            # The interlock that matters most. Revocation is irreversible, and rotating this
            # app's key later needs an SSWS token - so throwing the bootstrap credential away
            # before its replacement works leaves no route back except the admin console.
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestAccessToken { throw 'HTTP 403 grant not yet propagated' }

                $r = New-OktaTestServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                Should-NotInvoke Revoke-OktaTestApiToken
                Should-NotInvoke Resolve-OktaTestApiToken
                $r.ApiTokenRevoked | Should-BeNull
                @($r.Warnings | Where-Object { $_ -match 'unproven' }) | Should-BeCollection -Count 1
            }
        }

        It 'revokes nothing when the token name cannot be resolved' {
            # An ambiguous or unknown name is refused rather than guessed at. An org routinely
            # holds several tokens, and guessing would eventually revoke somebody's CI.
            InModuleScope OktaTestEnvironment {
                Mock Resolve-OktaTestApiToken { throw "More than one token matches 'bootstrap'" }

                $r = New-OktaTestServiceApp -RevokeApiToken bootstrap -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                Should-NotInvoke Revoke-OktaTestApiToken
                $r.ApiTokenRevoked | Should-BeNull
                @($r.Warnings | Where-Object { $_ -match 'Could not revoke' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'leaves the token alone when no revocation was asked for' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestServiceApp -PassThru -Confirm:$false

                Should-NotInvoke Revoke-OktaTestApiToken
                $r.ApiTokenRevoked | Should-BeNull
            }
        }
    }

    Context 'Error Handling' {

        It 'keeps going when a single scope grant fails, and reports which' {
            # A partially granted app is recoverable by hand; a failed run that created the app
            # anyway and said nothing is not.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    if ($Path -like '*/grants' -and $Body.scopeId -eq 'okta.groups.read') {
                        throw 'HTTP 403 scope not available'
                    }
                    return $null
                }

                $r = New-OktaTestServiceApp -Scope okta.users.read, okta.groups.read `
                    -PassThru -Confirm:$false -WarningAction SilentlyContinue

                @($r.Scopes) | Should-BeCollection @('okta.users.read')
                @($r.Warnings | Where-Object { $_ -match 'okta\.groups\.read' }) |
                    Should-BeCollection -Count 1
            }
        }

        It 'explains the consequence when the admin role cannot be assigned' {
            # Scopes without a role produce an app that authenticates and then 403s on every
            # call, which is a confusing state to debug from the symptom.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                    if ($Path -eq '/oauth2/v1/clients') {
                        return [PSCustomObject]@{ client_id = 'cid1' }
                    }
                    if ($Method -eq 'GET' -and $Path -like '/api/v1/apps/*') {
                        return [PSCustomObject]@{ id = 'app1' }
                    }
                    if ($Path -like '*/roles') { throw 'HTTP 403 requires super admin' }
                    return $null
                }

                $r = New-OktaTestServiceApp -PassThru -Confirm:$false -WarningAction SilentlyContinue

                @($r.AdminRoles) | Should-BeCollection -Count 0
                @($r.Warnings | Where-Object { $_ -match '403' }) | Should-BeCollection -Count 1
            }
        }
    }

    Context 'Safety' {

        It 'registers nothing under -WhatIf' {
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestServiceApp -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Path -eq '/oauth2/v1/clients'
                }
                Should-NotInvoke New-OktaTestRsaKeyPair
                Should-NotInvoke Export-OktaTestAppCredential
            }
        }

        It 'revokes nothing under -WhatIf, even when a token is named' {
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestServiceApp -RevokeApiToken bootstrap -WhatIf

                Should-NotInvoke Revoke-OktaTestApiToken
            }
        }
    }
}
