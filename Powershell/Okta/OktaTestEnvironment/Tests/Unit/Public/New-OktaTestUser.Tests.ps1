#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every Okta call is mocked, so this suite touches no tenant and burns none of the ten user
    slots it exists to protect.

    What it pins is the handful of decisions in New-OktaTestUser that are silent when wrong:
    the seed tag that teardown depends on, the activate flag that decides whether Okta emails
    a real address, and the fact that a password is always sent.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestUser' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl              = 'https://trial-123456.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                    ActiveUserLimit     = 10
                    SeedMarker          = '[seed:OKTALAB]'
                }
            }

            Mock Invoke-OktaTestRequest {
                # The seeded contractors belong to a second user type, so the type list has to
                # resolve or their creation fails by design.
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/types/user') {
                    return @(
                        [PSCustomObject]@{ id = 'oty0'; name = 'user'; default = $true }
                        [PSCustomObject]@{ id = 'otyContractor'; name = 'oktalabContractor'; default = $false }
                    )
                }
                # A GET for a specific login is the existence probe. Throwing is "not found",
                # which is the state a first run is in.
                if ($Method -eq 'GET' -and $Path -match '^/api/v1/users/.+') {
                    throw 'Not found'
                }
                if ($Method -eq 'POST' -and $Path -eq '/api/v1/users') {
                    return [PSCustomObject]@{ id = "id-$([Guid]::NewGuid())"; status = 'ACTIVE' }
                }
                return $null
            }
        }
    }

    It 'creates every seeded user' {
        InModuleScope OktaTestEnvironment {
            $result = New-OktaTestUser -PassThru -Confirm:$false
            $result.CreatedUsers | Should-Be 8
        }
    }

    It 'honours -UserCount so the licence ceiling can be respected' {
        InModuleScope OktaTestEnvironment {
            $result = New-OktaTestUser -UserCount 3 -PassThru -Confirm:$false
            $result.CreatedUsers | Should-Be 3
        }
    }

    It 'stamps every user with the seed tag teardown identifies them by' {
        # Without this, Remove-OktaTestEnvironment falls back to the email domain alone, and a
        # user moved to another domain survives teardown silently.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 8 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                $Body.profile.labSeedTag -eq 'OKTALAB'
            }
        }
    }

    It 'always sends a password, so Okta never emails the seeded address' {
        # Creating a user without credentials and activate=true makes Okta send a real
        # activation email. The addresses are under example.com, so nobody receives it, but
        # the tenant still records eight bounced activations.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                -not $Body.credentials.password.value
            }
        }
    }

    It 'creates the staged user with activate=false' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and $Query.activate -eq 'false'
            }
        }
    }

    It 'suspends the user the CSV marks as suspended' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -match '/lifecycle/suspend$'
            }
        }
    }

    It 'creates everyone active when -SkipLifecycleStates is passed' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -SkipLifecycleStates -PassThru -Confirm:$false

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and $Query.activate -eq 'false'
            }
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -match '/lifecycle/suspend$'
            }
        }
    }

    It 'builds logins from the connection email domain rather than the CSV' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -UserCount 1 -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                $Body.profile.login -eq 'awhitfield@oktalab.example.com'
            }
        }
    }

    It 'sends the non-ASCII display name unchanged' {
        # The seeded names carry accents specifically to expose encoding loss. If they are
        # normalised away on the request path, the test data stops testing anything.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -UserCount 2 -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                $Body.profile.displayName -eq ([string][char]0x4A + 'os' + [string][char]0xE9 + ' Ni' +
                    [string][char]0xF1 + 'o')
            }
        }
    }

    It 'puts the contractors on the second user type and nobody else' {
        # profile.userType is a free-text string; the type object is a real reference with its
        # own schema. Okta named them almost identically and they are unrelated, so this pins
        # which one is being set.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                $Body.type.id -eq 'otyContractor'
            }
            Should-Invoke Invoke-OktaTestRequest -Times 6 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and -not $Body.type
            }
        }
    }

    It 'sends the contractor-only attributes only to contractors' {
        # labAgencyName lives on the Contractor schema alone. Sending it to a default user is a
        # 400, so it has to follow the type rather than being set unconditionally.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users' -and
                $Body.profile.labAgencyName
            }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestUser -WhatIf

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/users'
            }
        }
    }

    It 'updates rather than duplicates a user that already exists' {
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -match '^/api/v1/users/.+') {
                    return [PSCustomObject]@{ id = 'existing'; status = 'ACTIVE' }
                }
                return [PSCustomObject]@{ id = 'existing'; status = 'ACTIVE' }
            }

            $result = New-OktaTestUser -UserCount 2 -PassThru -Confirm:$false

            $result.CreatedUsers | Should-Be 0
            $result.UpdatedUsers | Should-Be 2
        }
    }
}
