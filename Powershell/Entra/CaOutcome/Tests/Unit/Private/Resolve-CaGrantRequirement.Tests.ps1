#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The clause reader, which is where a summary of Conditional Access most easily goes wrong.

    Two defects these exist to prevent, both found against a real tenant:

    The first is flattening the operator. "MFA or compliant device" and "MFA and compliant
    device" are different policies and a list of strings cannot tell them apart, so the clause
    has to survive as a clause.

    The second is reading only builtInControls. A policy that requires an authentication
    strength has an empty builtInControls array and its whole requirement in a separate
    property, so a reader that looks only at the array reports the tenant's main MFA policy as
    requiring nothing at all. The tenant this module was built against has exactly that policy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-CaGrantRequirement' -Tag 'Unit', 'Private' {

    It 'keeps an OR clause whole rather than flattening it to a list' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p1'; displayName = 'MFA or compliant'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'
                    builtInControls = @('mfa', 'compliantDevice')
                }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause.Operator | Should-Be 'OR'
            $clause.Controls | Should-BeCollection @('mfa', 'compliantDevice')
            $clause.IsBlock | Should-BeFalse
        }
    }

    It 'reads a requirement expressed only as an authentication strength' {
        # The regression. builtInControls is empty and the requirement lives elsewhere.
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p2'; displayName = 'REQUIRE - MFA for All Users'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'
                    builtInControls = @()
                    authenticationStrength = [PSCustomObject]@{
                        id = '00000000-0000-0000-0000-000000000003'
                        displayName = 'Passwordless MFA'
                    }
                }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause | Should-NotBeNull
            $clause.Controls | Should-BeCollection @('authenticationStrength:Passwordless MFA')
        }
    }

    It 'reports block separately from the controls a user could satisfy' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p3'; displayName = 'BLOCK - Legacy Authentication'
                grantControls = [PSCustomObject]@{ operator = 'OR'; builtInControls = @('block') }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause.IsBlock | Should-BeTrue
            @($clause.Controls).Count | Should-Be 0
        }
    }

    It 'gathers terms of use and custom factors alongside the built-in controls' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p4'; displayName = 'Everything'
                grantControls = [PSCustomObject]@{
                    operator = 'AND'
                    builtInControls = @('mfa')
                    termsOfUse = @('tou-1')
                    customAuthenticationFactors = @('factor-1')
                }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause.Controls | Should-BeCollection @(
                'mfa', 'termsOfUse:tou-1', 'customAuthenticationFactor:factor-1')
        }
    }

    It 'returns nothing for a policy that grants nothing, such as a session-only one' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p5'; displayName = 'Session only'
                grantControls = $null
            }

            Resolve-CaGrantRequirement -Policy $policy | Should-BeNull
        }
    }

    It 'reads a hashtable policy the same as a PSObject one' {
        # Graph hands back hashtables under -OutputType Hashtable, and the two are not
        # interchangeable in PowerShell
        InModuleScope CaOutcome {
            $policy = @{
                id = 'p6'; displayName = 'From a hashtable'
                grantControls = @{ operator = 'AND'; builtInControls = @('mfa', 'compliantDevice') }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause.Operator | Should-Be 'AND'
            $clause.Controls | Should-BeCollection @('mfa', 'compliantDevice')
        }
    }

    It 'carries the allowed combinations of an authentication strength, not just its name' {
        <#
            A custom strength is editable, and editing one changes what every policy
            referencing it requires while every policy document in the tenant stays byte for
            byte identical. The display name is therefore not enough to compare on.
        #>
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p'; displayName = 'Strong'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'; builtInControls = @()
                    authenticationStrength = [PSCustomObject]@{
                        id = 'abc'; displayName = 'Phishing resistant MFA'; policyType = 'builtIn'
                        allowedCombinations = @('fido2', 'windowsHelloForBusiness',
                                                'x509CertificateMultiFactor')
                    }
                }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $detail = $clause.ControlDetail['authenticationStrength:Phishing resistant MFA']

            $detail | Should-NotBeNull
            $detail.DisplayName | Should-Be 'Phishing resistant MFA'
            $detail.PolicyType | Should-Be 'builtIn'
            $detail.AllowedCombinations | Should-BeCollection @(
                'fido2', 'windowsHelloForBusiness', 'x509CertificateMultiFactor')
        }
    }

    It 'sorts the combinations, so Graph reordering them is not read as an edit' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p'; displayName = 'Strong'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'
                    authenticationStrength = [PSCustomObject]@{
                        displayName = 'S'
                        allowedCombinations = @('windowsHelloForBusiness', 'fido2')
                    }
                }
            }

            $clause = Resolve-CaGrantRequirement -Policy $policy
            $clause.ControlDetail['authenticationStrength:S'].AllowedCombinations |
                Should-BeCollection @('fido2', 'windowsHelloForBusiness')
        }
    }

    It 'falls back to the strength id when Graph returns no display name' {
        # A nameless requirement would render as "authenticationStrength:" and collide with
        # every other nameless one, silently merging two different strengths into one
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p'; displayName = 'Nameless strength'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'
                    authenticationStrength = [PSCustomObject]@{
                        id = '00000000-0000-0000-0000-000000000004'
                        allowedCombinations = @('fido2')
                    }
                }
            }

            (Resolve-CaGrantRequirement -Policy $policy).Controls |
                Should-BeCollection @('authenticationStrength:00000000-0000-0000-0000-000000000004')
        }
    }

    It 'counts combination configurations, which also change what satisfies the strength' {
        # FIDO2 AAGUID allowlists and certificate issuer restrictions live here, and adding one
        # tightens the strength without touching any policy
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p'; displayName = 'Strong'
                grantControls = [PSCustomObject]@{
                    operator = 'OR'
                    authenticationStrength = [PSCustomObject]@{
                        displayName = 'S'; allowedCombinations = @('fido2')
                        combinationConfigurations = @(
                            [PSCustomObject]@{ allowedAAGUIDs = @('a') }
                        )
                    }
                }
            }

            $detail = (Resolve-CaGrantRequirement -Policy $policy).ControlDetail['authenticationStrength:S']
            $detail.CombinationConfigurationCount | Should-Be 1
        }
    }

    It 'assumes AND when Graph omits the operator, so nothing is understated' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p7'; displayName = 'No operator'
                grantControls = [PSCustomObject]@{ builtInControls = @('mfa', 'compliantDevice') }
            }

            (Resolve-CaGrantRequirement -Policy $policy).Operator | Should-Be 'AND'
        }
    }
}
