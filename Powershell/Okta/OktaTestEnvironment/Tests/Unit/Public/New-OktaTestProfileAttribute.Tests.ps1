#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Custom profile attributes, which are the module's least obvious piece of logic.

    An Okta user type's schema is independent rather than an extension of the default one, so a
    shared attribute has to be written to EVERY type's schema. Getting that wrong does not fail
    loudly: the seed creates the attribute on the default schema, every contractor rejects it,
    and labSeedTag - which teardown keys off - is missing on exactly the users a partial
    teardown would then leave behind.

    The other half is property construction. Okta returns 400 for a minLength on a boolean or a
    null maxLength on a string, so the constraints have to be omitted rather than sent empty,
    and enum and oneOf have to agree exactly. These are the cases the CSV rows were chosen to
    exercise, so the tests assert per-type rather than counting calls.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestProfileAttribute' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB' }
            }

            # The default schema and the Contractor type's schema are different endpoints,
            # which is the whole point of the fan-out being tested here.
            Mock Get-OktaTestSchemaPath {
                if ($UserTypeKey) { return "/api/v1/meta/schemas/user/osc-$UserTypeKey" }
                return '/api/v1/meta/schemas/user/default'
            }

            Mock Invoke-OktaTestPendingCleanupRequest { $null }
        }
    }

    Context 'Schema Fan-Out' {

        It 'writes a schema update for the default type and for each named type' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestProfileAttribute -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -Times 2 -Exactly
                @($r.Errors) | Should-BeCollection -Count 0
            }
        }

        It 'sends every shared attribute to both schemas' {
            # labSeedTag is the one that matters most: teardown finds what it owns by it, so a
            # contractor whose schema lacks it cannot be marked and cannot be cleaned up.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestProfileAttribute -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/meta/schemas/user/default' -and
                    $Body.definitions.custom.properties.Contains('labSeedTag')
                }
                Should-Invoke Invoke-OktaTestPendingCleanupRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/meta/schemas/user/osc-Contractor' -and
                    $Body.definitions.custom.properties.Contains('labSeedTag')
                }
            }
        }

        It 'keeps a type-specific attribute off the default schema' {
            # labAgencyName being invisible to a default-schema export is the property the
            # Contractor type exists to give the lab. Leaking it onto the default schema would
            # quietly remove the thing under test.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestProfileAttribute -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/meta/schemas/user/osc-Contractor' -and
                    $Body.definitions.custom.properties.Contains('labAgencyName') -and
                    $Body.definitions.custom.properties.Contains('labPurchaseOrder')
                }
                Should-NotInvoke Invoke-OktaTestPendingCleanupRequest -ParameterFilter {
                    $Path -eq '/api/v1/meta/schemas/user/default' -and
                    $Body.definitions.custom.properties.Contains('labAgencyName')
                }
            }
        }
    }

    Context 'Property Construction' {

        It 'generates oneOf from the same list as enum, so the two agree' {
            # Okta rejects the schema if they disagree, and they are easy to let drift apart
            # if oneOf is ever maintained separately.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestProfileAttribute -Attribute labClearanceLevel `
                    -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -ParameterFilter {
                    $p = $Body.definitions.custom.properties['labClearanceLevel']
                    @($p.enum) -join ',' -eq 'Low,Standard,High' -and
                    (@($p.oneOf | ForEach-Object { $_.const }) -join ',') -eq 'Low,Standard,High' -and
                    (@($p.oneOf | ForEach-Object { $_.title }) -join ',') -eq 'Low,Standard,High'
                }
            }
        }

        It 'gives an array attribute an item type and disables union' {
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestProfileAttribute -Attribute labEntitlements `
                    -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -ParameterFilter {
                    $p = $Body.definitions.custom.properties['labEntitlements']
                    $p.type -eq 'array' -and $p.items.type -eq 'string' -and $p.union -eq 'DISABLE'
                }
            }
        }

        It 'sends length constraints only for the attribute that declares them' {
            # A minLength on a boolean is a 400, not a no-op, so "omitted" and "sent empty"
            # are very different outcomes.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestProfileAttribute -Attribute labBadgeId, labIsContractor `
                    -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -ParameterFilter {
                    $badge = $Body.definitions.custom.properties['labBadgeId']
                    $flag = $Body.definitions.custom.properties['labIsContractor']
                    $badge.minLength -eq 4 -and $badge.maxLength -eq 12 -and
                    -not $flag.Contains('minLength') -and -not $flag.Contains('maxLength') -and
                    $flag.type -eq 'boolean'
                }
            }
        }

        It 'reports each applied attribute once per schema it was written to' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestProfileAttribute -PassThru -Confirm:$false

                # Eight shared attributes on the default schema, the same eight plus two
                # contractor-only ones on the Contractor schema.
                @($r.Applied) | Should-BeCollection -Count 18
                @($r.Removed) | Should-BeCollection -Count 0
            }
        }
    }

    Context 'Removal' {

        It 'nulls each property out rather than sending its definition' {
            # Okta deletes a custom property when it is set to null; sending the definition
            # again would recreate exactly what teardown is trying to remove.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestProfileAttribute -Remove -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestPendingCleanupRequest -ParameterFilter {
                    $props = $Body.definitions.custom.properties
                    @($props.Keys).Count -gt 0 -and
                    @($props.Keys | Where-Object { $null -ne $props[$_] }).Count -eq 0
                }
                @($r.Removed) | Should-BeCollection -Count 18
                @($r.Applied) | Should-BeCollection -Count 0
            }
        }

        It 'treats a missing user type as already done when removing' {
            # Teardown runs after the type may already be gone. That is the desired end state,
            # so it must not be reported as a failure.
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestSchemaPath {
                    if ($UserTypeKey) { throw "User type '$UserTypeKey' was not found" }
                    return '/api/v1/meta/schemas/user/default'
                }

                $r = New-OktaTestProfileAttribute -Remove -PassThru -Confirm:$false

                @($r.Errors) | Should-BeCollection -Count 0
                Should-Invoke Invoke-OktaTestPendingCleanupRequest -Times 1 -Exactly
            }
        }

        It 'reports a missing user type as an error when adding' {
            # Adding is the opposite case: the type should be there, and continuing silently
            # would leave contractors without the shared attributes.
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestSchemaPath {
                    if ($UserTypeKey) { throw "User type '$UserTypeKey' was not found" }
                    return '/api/v1/meta/schemas/user/default'
                }

                $r = New-OktaTestProfileAttribute -PassThru -Confirm:$false -ErrorAction SilentlyContinue

                @($r.Errors) | Should-BeCollection -Count 1
                $r.Errors[0] | Should-MatchString 'Contractor'
            }
        }
    }

    Context 'Error Handling' {

        It 'records a schema update that fails and names the schema' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestPendingCleanupRequest { throw 'HTTP 400 invalid property' }

                $r = New-OktaTestProfileAttribute -PassThru -Confirm:$false -ErrorAction SilentlyContinue

                @($r.Errors) | Should-BeCollection -Count 2
                @($r.Applied) | Should-BeCollection -Count 0
                $r.Errors[0] | Should-MatchString 'default user schema'
            }
        }

        It 'throws on an attribute the CSV does not define' {
            InModuleScope OktaTestEnvironment {
                { New-OktaTestProfileAttribute -Attribute labNotReal -Confirm:$false } |
                    Should-Throw -ExceptionMessage '*labNotReal*'
            }
        }
    }

    Context 'Safety' {

        It 'changes no schema under -WhatIf, and reports what it would have done' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestProfileAttribute -WhatIf -PassThru

                Should-NotInvoke Invoke-OktaTestPendingCleanupRequest
                @($r.Skipped) | Should-BeCollection -Count 18
                @($r.Applied) | Should-BeCollection -Count 0
            }
        }
    }
}
