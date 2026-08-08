#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    Apps are what turn "who exists" into "who has access to what", so the assignments are the
    part worth pinning rather than the apps themselves.

    The teardown separation gets its own tests because it is a genuine trap: -Keep ServiceApp
    means "keep the credential I authenticate with", and if that also kept eight lab apps the
    user asked to be rid of, teardown would silently under-deliver and the tenant would fill up
    with apps nobody meant to keep.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestApp' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl              = 'https://trial-1.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                    SeedMarker          = '[seed:OKTALAB]'
                }
            }

            # Every seeded group, named the way New-OktaTestGroup would have named it.
            Mock Get-OktaTestSeededGroup {
                $groupRows = Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaGroups.csv') -Encoding UTF8
                @($groupRows | ForEach-Object {
                    [PSCustomObject]@{
                        id      = "00g$($_.Name)"
                        type    = 'OKTA_GROUP'
                        profile = [PSCustomObject]@{
                            name        = "OKTALAB-$($_.DisplayName)"
                            description = "x [seed:OKTALAB]"
                        }
                    }
                })
            }

            Mock Get-OktaTestSeededUser {
                $userRows = Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaUsers.csv') -Encoding UTF8
                @($userRows | ForEach-Object {
                    [PSCustomObject]@{
                        id      = "00u$($_.LoginPrefix)"
                        profile = [PSCustomObject]@{
                            login      = "$($_.LoginPrefix)@oktalab.example.com"
                            labSeedTag = 'OKTALAB'
                        }
                    }
                })
            }

            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/api/v1/apps') {
                    return [PSCustomObject]@{ id = "0oa$($Body.label)"; label = $Body.label }
                }
                return $null
            }
        }
    }

    It 'creates every seeded app' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestApp -PassThru -Confirm:$false
            $r.CreatedApps | Should-Be 8
        }
    }

    It 'stamps each app with the seed tag, for the app types that keep it' {
        # Apps have no description field, so unlike groups the marker goes in the app profile.
        # Okta only honours that for OIDC apps and silently drops it everywhere else, which is
        # why Get-OktaTestSeededApp also falls back to the app URL. Sending it is still correct.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestApp -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 8 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/apps' -and
                $Body.profile.labSeedTag -eq 'OKTALAB'
            }
        }
    }

    It 'uses all three creatable sign-on modes' {
        # Custom SAML apps are absent on purpose: Okta returns 404 for every SAML template name
        # through the API, verified against a live tenant. If that ever changes, this test is
        # where the count should be revisited.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestApp -PassThru -Confirm:$false
            @($r.Apps.SignOnMode | Sort-Object -Unique) |
                Should-BeCollection @('BOOKMARK', 'BROWSER_PLUGIN', 'OPENID_CONNECT')
        }
    }

    It 'assigns a direct user who is not in any of the app`s groups' {
        # The most valuable row in the CSV. Marcus is in Sales, the Wiki is assigned to
        # Engineering, and he is assigned directly - so a group-only access report misses him.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestApp -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -like '*/users' -and
                $Body.id -eq '00umbell' -and $Body.scope -eq 'USER'
            }
        }
    }

    It 'leaves the orphan app with no assignments at all' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestApp -AppName Legacy -PassThru -Confirm:$false

            @($r.Apps[0].Groups).Count | Should-Be 0
            @($r.Apps[0].DirectUsers).Count | Should-Be 0
            $r.GroupsAssigned | Should-Be 0
        }
    }

    It 'assigns groups with PUT, which is idempotent on a re-run' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestApp -AppName Intranet -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Path -like '/api/v1/apps/*/groups/*'
            }
        }
    }

    It 'assigns nothing when -SkipAssignment is passed' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestApp -SkipAssignment -PassThru -Confirm:$false

            $r.CreatedApps | Should-Be 8
            $r.GroupsAssigned | Should-Be 0
            $r.UsersAssigned | Should-Be 0
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestApp -WhatIf

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/apps'
            }
        }
    }

    It 'reuses an existing app rather than creating a duplicate' {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/apps') {
                    return @([PSCustomObject]@{ id = '0oaEXISTING'; label = 'OKTALAB-Intranet Portal' })
                }
                if ($Method -eq 'GET' -and $Path -like '*/users') { return @() }
                return $null
            }

            $r = New-OktaTestApp -AppName Intranet -PassThru -Confirm:$false

            $r.CreatedApps | Should-Be 0
            $r.ExistingApps | Should-Be 1
        }
    }

    It 'sends a redirect URI for the OIDC app' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestApp -AppName Analytics -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/apps' -and
                $Body.settings.oauthClient.redirect_uris -contains
                    'https://analytics.oktalab.example.com/authorization-code/callback'
            }
        }
    }
}

Describe 'Get-OktaTestSeededApp' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                @(
                    # An OIDC app, where Okta actually persists the profile marker.
                    [PSCustomObject]@{ id = 'a1'; label = 'OKTALAB-Analytics Console'
                        profile  = [PSCustomObject]@{ labSeedTag = 'OKTALAB' }
                        settings = [PSCustomObject]@{ oauthClient = [PSCustomObject]@{
                            redirect_uris = @('https://analytics.oktalab.example.com/cb') } } }
                    # The service app: space delimiter, no markers at all.
                    [PSCustomObject]@{ id = 'a2'; label = 'OKTALAB Test Environment Automation'
                        profile = $null; settings = $null }
                    # A real app that happens to share the prefix. No marker of any kind.
                    [PSCustomObject]@{ id = 'a3'; label = 'OKTALAB-Real Production App'
                        profile  = $null
                        settings = [PSCustomObject]@{ app = [PSCustomObject]@{
                            url = 'https://real.contoso.com/' } } }
                    # Somebody else's app entirely.
                    [PSCustomObject]@{ id = 'a4'; label = 'Google Workspace'
                        profile = $null; settings = $null }
                    # A bookmark app of ours. Okta DISCARDS the profile on these, so the URL is
                    # the only marker it carries - this is the case that broke teardown.
                    [PSCustomObject]@{ id = 'a5'; label = 'OKTALAB-Intranet Portal'
                        profile  = $null
                        settings = [PSCustomObject]@{ app = [PSCustomObject]@{
                            url = 'https://intranet.oktalab.example.com/' } } }
                    # The substring trap, the same one the user lookup guards against.
                    [PSCustomObject]@{ id = 'a6'; label = 'OKTALAB-Impostor'
                        profile  = $null
                        settings = [PSCustomObject]@{ app = [PSCustomObject]@{
                            url = 'https://notoktalab.example.com.evil.test/' } } }
                )
            }
        }
    }

    It 'returns an OIDC lab app by its profile marker' {
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com').id) |
                Should-ContainCollection 'a1'
        }
    }

    It 'returns a bookmark lab app by its URL, since Okta discards the profile on those' {
        # The regression. Okta ACCEPTS a profile on a bookmark or SWA app and then silently
        # drops it - the POST succeeds, the response omits it, and a follow-up PUT does not
        # help either. Keying teardown on the profile alone found one app out of eight and
        # quietly abandoned the other seven.
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com').id) |
                Should-ContainCollection 'a5'
        }
    }

    It 'matches the app URL domain as a suffix rather than as a substring' {
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com').id) |
                Should-NotContainCollection 'a6'
        }
    }

    It 'leaves a prefixed app alone when it has no seed marker' {
        # The trap: the tenant this was built against already held apps named after real
        # things. A label-prefix match alone would eventually delete one.
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com').id) |
                Should-NotContainCollection 'a3'
        }
    }

    It 'excludes the service app by default' {
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com').id) |
                Should-NotContainCollection 'a2'
        }
    }

    It 'includes the service app on request' {
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com' -IncludeServiceApp).id) |
                Should-ContainCollection 'a2'
        }
    }

    It 'never returns an unrelated app' {
        InModuleScope OktaTestEnvironment {
            @((Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com' -IncludeServiceApp).id) |
                Should-NotContainCollection 'a4'
        }
    }
}
