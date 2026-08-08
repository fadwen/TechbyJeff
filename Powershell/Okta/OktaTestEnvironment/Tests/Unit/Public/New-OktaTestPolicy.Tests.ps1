#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    Policies are the only seeded object that changes how people sign in, so the tests here are
    weighted towards what happens when something does not resolve rather than towards the happy
    path.

    The one that matters most: an Okta policy with no group condition applies to the WHOLE ORG.
    So a group lookup that quietly fails must not fall through to creating an unscoped policy -
    that is how a lab seeding script locks real people out of a shared tenant.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestPolicy' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl      = 'https://trial-1.okta.com'
                    AuthorizationHeader = 'SSWS test'
                    Prefix      = 'OKTALAB'
                    EmailDomain = 'oktalab.example.com'
                    SeedMarker  = '[seed:OKTALAB]'
                }
            }

            Mock Get-OktaTestSeededGroup {
                $groupRows = Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaGroups.csv') -Encoding UTF8
                @($groupRows | ForEach-Object {
                    [PSCustomObject]@{
                        id      = "00g$($_.Name)"
                        type    = 'OKTA_GROUP'
                        profile = [PSCustomObject]@{
                            name        = "OKTALAB-$($_.DisplayName)"
                            description = 'x [seed:OKTALAB]'
                        }
                    }
                })
            }

            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') {
                    return @([PSCustomObject]@{ id = 'nzo1'; name = 'OKTALAB-Corporate-Egress' })
                }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') { return @() }
                if ($Method -eq 'GET' -and $Path -like '*/rules') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/api/v1/policies') {
                    return [PSCustomObject]@{ id = "00p$($Body.name)"; name = $Body.name; priority = 1 }
                }
                return $null
            }
        }
    }

    It 'creates every seeded policy' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestPolicy -PassThru -Confirm:$false
            $r.CreatedPolicies | Should-Be 3
        }
    }

    It 'scopes every policy to at least one group' {
        # The safety property. An Okta policy without a group condition applies org-wide.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestPolicy -PassThru -Confirm:$false

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/policies' -and
                @($Body.conditions.people.groups.include).Count -eq 0
            }
        }
    }

    It 'refuses to create a policy when its groups do not resolve' {
        # Rather than creating an unscoped one that applies to everybody.
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestSeededGroup { @() }

            $r = New-OktaTestPolicy -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedPolicies | Should-Be 0
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/policies'
            }
            (@($r.Errors) -join ' ') | Should-MatchString 'whole org'
        }
    }

    It 'attaches the network zone to the rule that names one' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestPolicy -PolicyName Admin-Session -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -like '*/rules' -and
                $Body.conditions.network.connection -eq 'ZONE' -and
                $Body.conditions.network.include -contains 'nzo1'
            }
        }
    }

    It 'falls back to ANYWHERE for a rule that names no zone' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestPolicy -PolicyName Standard-Session -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -like '*/rules' -and
                $Body.conditions.network.connection -eq 'ANYWHERE'
            }
        }
    }

    It 'still creates the rule when the named zone is missing, and says so' {
        # A missing zone should not cost you the policy; it should cost you the restriction,
        # loudly. Silently creating an ALLOW-from-anywhere rule that was meant to be
        # zone-restricted is the dangerous version of this.
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/zones') { return @() }
                if ($Method -eq 'GET' -and $Path -eq '/api/v1/policies') { return @() }
                if ($Method -eq 'GET' -and $Path -like '*/rules') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/api/v1/policies') {
                    return [PSCustomObject]@{ id = '00pX'; name = $Body.name; priority = 1 }
                }
                return $null
            }

            $r = New-OktaTestPolicy -PolicyName Admin-Session -PassThru -Confirm:$false `
                -WarningAction SilentlyContinue

            $r.RulesCreated | Should-Be 1
            (@($r.Errors) -join ' ') | Should-MatchString 'does not exist'
        }
    }

    It 'sends password settings only for the password policy' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestPolicy -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/policies' -and
                $Body.type -eq 'PASSWORD' -and $Body.settings.password.complexity.minLength -eq 14
            }
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/policies' -and
                $Body.type -eq 'OKTA_SIGN_ON' -and $Body.settings
            }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestPolicy -WhatIf

            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/policies'
            }
        }
    }
}
