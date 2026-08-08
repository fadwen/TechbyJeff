#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    The orchestrator's only real job is ordering, and the order is not arbitrary: each step
    depends on the one before it. Users cannot carry an attribute the schema does not define,
    group rules cannot target groups that do not exist, and the service app goes last because
    it is the handover from the SSWS token everything above ran on.

    Getting that wrong produces a run that half works and reports success, so it is worth
    pinning rather than trusting to the order the steps happen to be written in.

    The step bodies are also scriptblocks stored in a hashtable and invoked with &, which only
    works because they close over the function's parameters. That is easy to break by moving
    them, so it is asserted here too.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestEnvironment' -Tag 'Unit', 'Public' {

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
            Mock Test-OktaTestPrerequisite { $true }

            # Recorded in a module-scoped list so the ordering can be asserted afterwards.
            $script:StepOrder = [System.Collections.Generic.List[string]]::new()

            Mock New-OktaTestProfileAttribute {
                $script:StepOrder.Add('Schema')
                [PSCustomObject]@{ Applied = @('labSeedTag'); Removed = @(); Errors = @() }
            }
            Mock New-OktaTestUser {
                $script:StepOrder.Add('Users')
                [PSCustomObject]@{ CreatedUsers = 8; UpdatedUsers = 0; Errors = @() }
            }
            Mock New-OktaTestGroup {
                $script:StepOrder.Add('Groups')
                [PSCustomObject]@{ CreatedGroups = 17; MembersAdded = 30; Errors = @() }
            }
            Mock New-OktaTestGroupRule {
                $script:StepOrder.Add('GroupRules')
                [PSCustomObject]@{ CreatedRules = 3; ActivatedRules = 3; Errors = @() }
            }
            Mock New-OktaTestApp {
                $script:StepOrder.Add('Apps')
                [PSCustomObject]@{ CreatedApps = 8; GroupsAssigned = 11; UsersAssigned = 2; Errors = @() }
            }
            Mock New-OktaTestUserType {
                $script:StepOrder.Add('UserTypes')
                [PSCustomObject]@{ CreatedTypes = 1; ExistingTypes = 0; Types = @(); Errors = @() }
            }
            Mock New-OktaTestLinkedObject {
                $script:StepOrder.Add('LinkedObjects')
                [PSCustomObject]@{ LinksCreated = 3; Definitions = @(); Errors = @() }
            }
            Mock New-OktaTestNetworkZone {
                $script:StepOrder.Add('NetworkZones')
                [PSCustomObject]@{ CreatedZones = 2; Zones = @(); Errors = @() }
            }
            Mock New-OktaTestPolicy {
                $script:StepOrder.Add('Policies')
                [PSCustomObject]@{ CreatedPolicies = 3; RulesCreated = 2; Policies = @(); Errors = @() }
            }
            Mock New-OktaTestTrustedOrigin {
                $script:StepOrder.Add('TrustedOrigins')
                [PSCustomObject]@{ CreatedOrigins = 2; Origins = @(); Errors = @() }
            }
            Mock New-OktaTestEventHook {
                $script:StepOrder.Add('EventHooks')
                [PSCustomObject]@{ CreatedHooks = 2; Hooks = @(); Errors = @() }
            }
            Mock New-OktaTestServiceApp {
                $script:StepOrder.Add('ServiceApp')
                [PSCustomObject]@{ ClientId = '0oaTEST'; Protection = 'DPAPI'; Warnings = @() }
            }

            # The backstop. A step function added later and not mocked here would otherwise fall
            # through to the real REST engine and hit whatever tenant the developer happens to
            # be pointed at - which is exactly what happened when the Apps step was introduced.
            # Failing loudly beats a suite that silently makes live calls.
            Mock Invoke-OktaTestRequest {
                throw "A network call escaped the mocks: $Method $Path"
            }
        }
    }

    It 'runs the steps in dependency order' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestEnvironment -Confirm:$false

            $script:StepOrder |
                Should-BeCollection @('UserTypes', 'Schema', 'Users', 'Groups', 'GroupRules', 'Apps',
                    'LinkedObjects', 'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks',
                    'ServiceApp')
        }
    }

    It 'runs every step by default' {
        InModuleScope OktaTestEnvironment {
            $result = New-OktaTestEnvironment -Confirm:$false -PassThru
            $result.Summary.SuccessfulOperations | Should-Be 12
        }
    }

    It 'skips only what -Skip names' {
        InModuleScope OktaTestEnvironment {
            $skip = @('ServiceApp', 'Schema', 'Apps', 'UserTypes', 'LinkedObjects',
                'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks')
            $null = New-OktaTestEnvironment -Skip $skip -Confirm:$false

            $script:StepOrder | Should-BeCollection @('Users', 'Groups', 'GroupRules')
        }
    }

    It 'passes -UserCount through to the user step' {
        # The step bodies are scriptblocks in a hashtable, invoked with &. They only see
        # $UserCount because they close over the function's scope, which is easy to break by
        # moving the definitions somewhere that does not.
        InModuleScope OktaTestEnvironment {
            $skip = @('UserTypes', 'Groups', 'GroupRules', 'Apps', 'LinkedObjects',
                'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks', 'ServiceApp')
            $null = New-OktaTestEnvironment -UserCount 3 -Skip $skip -Confirm:$false

            Should-Invoke New-OktaTestUser -Times 1 -Exactly -ParameterFilter { $UserCount -eq 3 }
        }
    }

    It 'does not ask for user headroom when users are skipped' {
        # A groups-only rebuild against a full tenant is a legitimate thing to want, and
        # demanding eight free slots for it would fail for no reason.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestEnvironment -Skip Users -Confirm:$false

            Should-Invoke Test-OktaTestPrerequisite -Times 1 -Exactly -ParameterFilter {
                $RequiredUserSlots -eq 0
            }
        }
    }

    It 'still runs the step functions under -WhatIf, so the preview names real objects' {
        # The orchestrator deliberately has no ShouldProcess gate of its own. Gating here made
        # -WhatIf print "would perform step 2" instead of the eight users it would create,
        # which is not a preview of anything. Each step function owns the decision, and each
        # has its own -WhatIf test proving it creates nothing.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestEnvironment -WhatIf

            Should-Invoke New-OktaTestUser -Times 1 -Exactly
            Should-Invoke New-OktaTestGroup -Times 1 -Exactly
            Should-Invoke New-OktaTestServiceApp -Times 1 -Exactly
        }
    }

    It 'propagates -WhatIf into the step functions' {
        # The propagation is what makes the delegation safe. $WhatIfPreference is inherited by
        # child scopes, so a step function called from here sees it without being passed it.
        InModuleScope OktaTestEnvironment {
            Mock New-OktaTestUser {
                $script:StepOrder.Add("Users:WhatIf=$WhatIfPreference")
                [PSCustomObject]@{ CreatedUsers = 0; UpdatedUsers = 0; Errors = @() }
            }

            $skip = @('UserTypes', 'Groups', 'GroupRules', 'Apps', 'LinkedObjects',
                'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks', 'ServiceApp')
            $null = New-OktaTestEnvironment -Skip $skip -WhatIf

            $script:StepOrder | Should-ContainCollection 'Users:WhatIf=True'
        }
    }

    It 'carries on after a failing step rather than losing the others' {
        InModuleScope OktaTestEnvironment {
            Mock New-OktaTestGroup { throw 'Okta POST /api/v1/groups failed with HTTP 403' }

            $result = New-OktaTestEnvironment -Confirm:$false -PassThru -ErrorAction SilentlyContinue

            $result.Summary.FailedOperations | Should-Be 1
            $result.Summary.SuccessfulOperations | Should-Be 11
            $result.Operations.Groups.Success | Should-BeFalse
            $result.Operations.ServiceApp.Success | Should-BeTrue
        }
    }

    It 'refuses to start when prerequisites are not met' {
        InModuleScope OktaTestEnvironment {
            Mock Test-OktaTestPrerequisite { $false }

            { New-OktaTestEnvironment -Confirm:$false } | Should-Throw -ExceptionMessage '*Prerequisites not met*'
            Should-NotInvoke New-OktaTestUser
        }
    }
}
