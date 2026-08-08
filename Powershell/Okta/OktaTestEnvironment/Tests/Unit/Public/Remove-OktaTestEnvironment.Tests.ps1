#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    Teardown regression tests for the classic -Force-defeats--WhatIf bug. It happens when the
    guards are written as "if ($Force -or $PSCmdlet.ShouldProcess(...))": -or short-circuits, so
    "Remove-... -Force -WhatIf" really deletes everything. Nothing warns you about that; the
    only way to catch it is a test asserting that nothing was deleted.

    The stakes are as high as they get here, because a deleted Okta user cannot be restored at
    all - there is no recycle bin.

    Every call is mocked. This suite must never reach a tenant.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Remove-OktaTestEnvironment' -Tag 'Unit', 'Public', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl              = 'https://dev-123456.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    AuthType            = 'ApiToken'
                    Prefix              = 'OKTALAB'
                    EmailDomain         = 'oktalab.example.com'
                    ActiveUserLimit     = 10
                    SeedMarker          = '[seed:OKTALAB]'
                }
            }
            Mock Write-OktaTestProgress { }
            Mock New-OktaTestProfileAttribute { [PSCustomObject]@{ Removed = @('labSeedTag'); Errors = @() } }

            Mock Get-OktaTestSeededUser {
                @([PSCustomObject]@{
                    id      = 'u1'
                    status  = 'ACTIVE'
                    profile = [PSCustomObject]@{ login = 'awhitfield@oktalab.example.com' }
                })
            }
            Mock Get-OktaTestSeededGroup {
                @([PSCustomObject]@{
                    id      = 'g1'
                    type    = 'OKTA_GROUP'
                    profile = [PSCustomObject]@{
                        name        = 'OKTALAB-All Employees'
                        description = 'Everyone [seed:OKTALAB]'
                    }
                })
            }

            # Must honour -IncludeServiceApp. Returning the service app to the lab-app sweep as
            # well is what -Keep ServiceApp exists to prevent, so a mock that ignores the switch
            # tests the opposite of the intended behaviour.
            Mock Get-OktaTestSeededApp {
                if ($IncludeServiceApp) {
                    return @([PSCustomObject]@{
                        id = 'a1'; label = 'OKTALAB Test Environment Automation'; status = 'ACTIVE'
                    })
                }
                return @()
            }

            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/groups/rules') {
                    return @([PSCustomObject]@{ id = 'r1'; name = 'OKTALAB-Rule-Contractors'; status = 'ACTIVE' })
                }
                # Each of these returns one object of ours and one belonging to somebody else,
                # so every sweep is asserted on what it leaves behind as well as what it takes.
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/eventHooks') {
                    return @(
                        [PSCustomObject]@{ id = 'h1'; name = 'OKTALAB-Lifecycle-Watcher' }
                        [PSCustomObject]@{ id = 'h2'; name = 'Production SIEM Feed' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/trustedOrigins') {
                    return @(
                        [PSCustomObject]@{ id = 'o1'; name = 'OKTALAB-Lab-Portal' }
                        [PSCustomObject]@{ id = 'o2'; name = 'Corporate SPA' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') {
                    if ($Query.type -eq 'OKTA_SIGN_ON') {
                        return @(
                            [PSCustomObject]@{ id = 'p1'; name = 'OKTALAB-Admin-Session' }
                            [PSCustomObject]@{ id = 'p2'; name = 'Default Policy' }
                        )
                    }
                    return @([PSCustomObject]@{ id = 'p3'; name = 'OKTALAB-Contractor-Password' })
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') {
                    return @(
                        [PSCustomObject]@{ id = 'z1'; name = 'OKTALAB-Corporate-Egress' }
                        [PSCustomObject]@{ id = 'z2'; name = 'LegacyVPN' }
                    )
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/schemas/user/linkedObjects') {
                    return @([PSCustomObject]@{ primary = @{ name = 'labMentor' } })
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/meta/types/user') {
                    return @(
                        [PSCustomObject]@{ id = 't0'; name = 'user'; default = $true }
                        [PSCustomObject]@{ id = 't1'; name = 'oktalabContractor'; default = $false }
                    )
                }
                return $null
            }
        }
    }

    Context 'WhatIf must win over Force' {

        It 'deletes no users' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/users/'
                }
            }
        }

        It 'does not even deactivate a user' {
            # The quieter half of the same bug. A deactivation that -WhatIf was meant to skip
            # locks eight people out and reports that it did nothing.
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'POST' -and $Path -match '/lifecycle/deactivate$'
                }
            }
        }

        It 'deletes no groups' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/groups/'
                }
            }
        }

        It 'deletes no group rules' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/groups/rules/'
                }
            }
        }

        It 'deletes no apps' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/apps/'
                }
            }
        }

        It 'reports nothing removed' {
            InModuleScope OktaTestEnvironment {
                $result = Remove-OktaTestEnvironment -Force -WhatIf -PassThru
                @($result.Users.Removed).Count | Should-Be 0
                @($result.Groups.Removed).Count | Should-Be 0
            }
        }

        It 'does not delete the credential file' {
            InModuleScope OktaTestEnvironment {
                Mock Remove-Item { }
                Mock Test-Path { $true }

                $null = Remove-OktaTestEnvironment -Force -WhatIf -RemoveCredentialFile

                Should-NotInvoke Remove-Item
            }
        }
    }

    Context 'Force actually removes' {

        # The counterpart to the tests above: proving -WhatIf is honoured is worthless if the
        # real path stopped working too.

        It 'deactivates and then deletes each user' {
            # Okta needs both. A single DELETE against an active user only deactivates it, so
            # a teardown that skips the deactivate leaves the user behind still holding a
            # licence slot, and reports success.
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/api/v1/users/u1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/users/u1'
                }
            }
        }

        It 'deletes the groups' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/groups/g1'
                }
            }
        }

        It 'deactivates a group rule before deleting it' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/api/v1/groups/rules/r1/lifecycle/deactivate'
                }
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/groups/rules/r1'
                }
            }
        }

        It 'removes the custom schema attributes last' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force
                Should-Invoke New-OktaTestProfileAttribute -Times 1 -Exactly
            }
        }

        It 'keeps the credential file unless asked to delete it' {
            InModuleScope OktaTestEnvironment {
                Mock Remove-Item { }
                Mock Test-Path { $true }

                $null = Remove-OktaTestEnvironment -Force

                Should-NotInvoke Remove-Item
            }
        }
    }

    Context 'The sweeps added for policies, zones, hooks, origins, types and links' {

        # These went in without tests, in the one function where deleting the wrong thing is
        # unrecoverable. Each case asserts both halves: ours goes, theirs stays.

        It 'deletes our event hook and leaves the production one' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/eventHooks/h1'
                }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/eventHooks/h2'
                }
            }
        }

        It 'deletes our trusted origin and leaves the corporate one' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/trustedOrigins/o1'
                }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/trustedOrigins/o2'
                }
            }
        }

        It 'deletes both our policies and leaves the org default' {
            # The policy sweep queries per type, because there is no "all policies" listing.
            # A sweep that forgot PASSWORD would leave that one behind and still report success.
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p1'
                }
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p3'
                }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/policies/p2'
                }
            }
        }

        It 'deletes our network zone and leaves the unrelated one' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/zones/z1'
                }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/zones/z2'
                }
            }
        }

        It 'deletes the linked object definition' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and
                    $Path -eq '/api/v1/meta/schemas/user/linkedObjects/labMentor'
                }
            }
        }

        It 'deletes our user type and never the default one' {
            # Deleting the default user type would take every user in the org with it.
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/meta/types/user/t1'
                }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/meta/types/user/t0'
                }
            }
        }

        It 'removes zones only after the policies that reference them' {
            # Okta refuses to delete a zone a policy rule still points at, so the order is a
            # correctness requirement rather than a preference.
            InModuleScope OktaTestEnvironment {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'DELETE' -and $Path -like '/api/v1/policies/*') {
                        $script:Order.Add('policy')
                    }
                    if ($Method -eq 'DELETE' -and $Path -like '/api/v1/zones/*') {
                        $script:Order.Add('zone')
                    }
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') {
                        return @([PSCustomObject]@{ id = 'p1'; name = 'OKTALAB-Admin-Session' })
                    }
                    if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') {
                        return @([PSCustomObject]@{ id = 'z1'; name = 'OKTALAB-Corporate-Egress' })
                    }
                    return $null
                }

                $null = Remove-OktaTestEnvironment -Force

                $script:Order.IndexOf('policy') | Should-BeLessThan $script:Order.IndexOf('zone')
            }
        }

        It 'removes nothing new under -Force -WhatIf either' {
            # The -WhatIf guarantee has to hold for the sweeps added later, not just the
            # original four.
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -WhatIf

                # Not $path: inside a ParameterFilter that name is the bound parameter, so the
                # comparison would be against itself.
                foreach ($expectedPath in @('/api/v1/eventHooks/h1', '/api/v1/trustedOrigins/o1',
                        '/api/v1/policies/p1', '/api/v1/zones/z1',
                        '/api/v1/meta/types/user/t1',
                        '/api/v1/meta/schemas/user/linkedObjects/labMentor')) {
                    Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                        $Method -eq 'DELETE' -and $Path -eq $expectedPath
                    }
                }
            }
        }

        It 'honours -Keep for each of them individually' {
            InModuleScope OktaTestEnvironment {
                $keep = @('EventHooks', 'TrustedOrigins', 'Policies', 'NetworkZones',
                    'LinkedObjects', 'UserTypes')
                $null = Remove-OktaTestEnvironment -Force -Keep $keep

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'DELETE' -and
                    ($Path -like '/api/v1/eventHooks/*' -or $Path -like '/api/v1/trustedOrigins/*' -or
                     $Path -like '/api/v1/policies/*' -or $Path -like '/api/v1/zones/*' -or
                     $Path -like '/api/v1/meta/types/user/*' -or $Path -like '*linkedObjects/*') }
            }
        }
    }

    Context 'Keep' {

        It 'leaves the service app alone when kept, so the next seed can still authenticate' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -Keep ServiceApp

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -match '^/api/v1/apps/'
                }
            }
        }

        It 'leaves the schema alone when kept' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -Keep Schema
                Should-NotInvoke New-OktaTestProfileAttribute
            }
        }

        It 'still removes users when only the app is kept' {
            InModuleScope OktaTestEnvironment {
                $null = Remove-OktaTestEnvironment -Force -Keep ServiceApp

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Path -eq '/api/v1/users/u1'
                }
            }
        }
    }
}
