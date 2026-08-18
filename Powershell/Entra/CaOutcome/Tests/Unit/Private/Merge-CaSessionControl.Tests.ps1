#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Session control merging, and the honesty of its conflict reporting.

    Two policies setting the same session control to different values is common and easy to
    create by accident - the tenant this was built against does it today, with an "always"
    persistent browser from the tenant-wide MFA policy meeting a "never" from the
    unjoined-device policy on the same sign-in.

    The rule these tests hold in place is that a disagreement is always reported, whether or not
    it could be resolved. Resolving quietly would produce an answer that looks authoritative;
    Microsoft documents the aggregate as the most restrictive combination but does not document
    a precedence for every control, so anything outside the two with a defensible ordering has
    to come back marked unresolved rather than guessed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-CaSessionControl' -Tag 'Unit', 'Private' {

    It 'ignores the nulls Graph pads the object with' {
        # A policy that sets one control comes back carrying nine others set to null. Counting
        # those would report every policy as configuring everything.
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p1'; displayName = 'Persistent browser only'
                sessionControls = [PSCustomObject]@{
                    applicationEnforcedRestrictions = $null
                    cloudAppSecurity = $null
                    signInFrequency = $null
                    persistentBrowser = [PSCustomObject]@{ mode = 'never'; isEnabled = $true }
                }
            }

            $contributions = @(Resolve-CaSessionControl -Policy $policy)
            $contributions.Count | Should-Be 1
            $contributions[0].Control | Should-Be 'persistentBrowser'
            $contributions[0].Value | Should-Be 'never'
        }
    }

    It 'drops a control that is present but switched off' {
        # Configured then disabled is not in force, and must not compete with a live setting
        # from another policy
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p2'; displayName = 'Disabled frequency'
                sessionControls = [PSCustomObject]@{
                    signInFrequency = [PSCustomObject]@{
                        value = 1; type = 'hours'; frequencyInterval = 'timeBased'; isEnabled = $false
                    }
                }
            }

            @(Resolve-CaSessionControl -Policy $policy).Count | Should-Be 0
        }
    }

    It 'ranks every time as stricter than any interval' {
        InModuleScope CaOutcome {
            $everyTime = ConvertTo-CaSessionControlValue -Control 'signInFrequency' `
                -Value ([PSCustomObject]@{ frequencyInterval = 'everyTime' })
            $oneHour = ConvertTo-CaSessionControlValue -Control 'signInFrequency' `
                -Value ([PSCustomObject]@{ value = 1; type = 'hours'; frequencyInterval = 'timeBased' })

            $everyTime.RestrictivenessRank | Should-BeLessThan $oneHour.RestrictivenessRank
        }
    }

    It 'converts days and hours to the same scale so they can be compared' {
        InModuleScope CaOutcome {
            $oneDay = ConvertTo-CaSessionControlValue -Control 'signInFrequency' `
                -Value ([PSCustomObject]@{ value = 1; type = 'days'; frequencyInterval = 'timeBased' })
            $twelveHours = ConvertTo-CaSessionControlValue -Control 'signInFrequency' `
                -Value ([PSCustomObject]@{ value = 12; type = 'hours'; frequencyInterval = 'timeBased' })

            $twelveHours.RestrictivenessRank | Should-BeLessThan $oneDay.RestrictivenessRank
        }
    }

    It 'reads a hashtable sessionControls the same as a PSObject one' {
        # Graph returns hashtables under -OutputType Hashtable, and the two are not
        # interchangeable in PowerShell
        InModuleScope CaOutcome {
            $policy = @{
                id = 'p'; displayName = 'From a hashtable'
                sessionControls = @{
                    signInFrequency = $null
                    persistentBrowser = @{ mode = 'never'; isEnabled = $true }
                }
            }

            $contributions = @(Resolve-CaSessionControl -Policy $policy)
            $contributions.Count | Should-Be 1
            $contributions[0].Value | Should-Be 'never'
        }
    }

    It 'ignores the odata annotations Graph mixes in with the controls' {
        InModuleScope CaOutcome {
            $policy = [PSCustomObject]@{
                id = 'p'; displayName = 'Annotated'
                sessionControls = [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.conditionalAccessSessionControls'
                    persistentBrowser = [PSCustomObject]@{ mode = 'always'; isEnabled = $true }
                }
            }

            @(Resolve-CaSessionControl -Policy $policy).Count | Should-Be 1
        }
    }

    It 'returns nothing for a policy with no session controls at all' {
        InModuleScope CaOutcome {
            @(Resolve-CaSessionControl -Policy ([PSCustomObject]@{ id = 'p'; sessionControls = $null })).Count |
                Should-Be 0
        }
    }
}

Describe 'ConvertTo-CaSessionControlValue' -Tag 'Unit', 'Private' {

    <#
        The per-control rendering, tested directly because it is where a control Microsoft adds
        later will land. The contract that matters is the last one: an unrecognised control is
        surfaced with whatever detail it carries rather than dropped, so a new session control
        appears in the outcome the day it ships - without a restrictiveness rank, which is what
        makes Merge-CaSessionControl report a disagreement about it as unresolved.
    #>

    Context 'controls this module knows' {

        It 'renders a sign-in frequency with its authentication type' {
            InModuleScope CaOutcome {
                $rendered = ConvertTo-CaSessionControlValue -Control 'signInFrequency' -Value (
                    [PSCustomObject]@{
                        value = 4; type = 'hours'; frequencyInterval = 'timeBased'
                        authenticationType = 'primaryAndSecondaryAuthentication'
                    })

                $rendered.Value | Should-Be '4 hours (primaryAndSecondaryAuthentication)'
                $rendered.RestrictivenessRank | Should-Be 240
            }
        }

        It 'gives no rank to a sign-in frequency measured in a unit it cannot convert' {
            # No rank means Merge-CaSessionControl reports a disagreement rather than resolving
            # it, which is the honest outcome for a unit this module does not understand
            InModuleScope CaOutcome {
                $rendered = ConvertTo-CaSessionControlValue -Control 'signInFrequency' -Value (
                    [PSCustomObject]@{ value = 3; type = 'fortnights'; frequencyInterval = 'timeBased' })

                $rendered.Value | Should-Be '3 fortnights'
                $rendered.RestrictivenessRank | Should-BeNull
            }
        }

        It 'returns nothing for a sign-in frequency that says neither how often nor every time' {
            InModuleScope CaOutcome {
                ConvertTo-CaSessionControlValue -Control 'signInFrequency' `
                    -Value ([PSCustomObject]@{ isEnabled = $true }) | Should-BeNull
            }
        }

        It 'returns nothing for a persistent browser with no mode' {
            InModuleScope CaOutcome {
                ConvertTo-CaSessionControlValue -Control 'persistentBrowser' `
                    -Value ([PSCustomObject]@{ isEnabled = $true }) | Should-BeNull
            }
        }

        It 'renders cloud app security by its type' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'cloudAppSecurity' -Value (
                    [PSCustomObject]@{ cloudAppSecurityType = 'blockDownloads'; isEnabled = $true })).Value |
                    Should-Be 'blockDownloads'
            }
        }

        It 'falls back to enabled for a cloud app security with no type' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'cloudAppSecurity' `
                    -Value ([PSCustomObject]@{ isEnabled = $true })).Value | Should-Be 'enabled'
            }
        }

        It 'renders continuous access evaluation by its mode, and nothing without one' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'continuousAccessEvaluation' `
                    -Value ([PSCustomObject]@{ mode = 'strictLocation' })).Value | Should-Be 'strictLocation'

                ConvertTo-CaSessionControlValue -Control 'continuousAccessEvaluation' `
                    -Value ([PSCustomObject]@{ isEnabled = $true }) | Should-BeNull
            }
        }
    }

    Context 'bare scalars' {

        It 'renders a true boolean control such as disableResilienceDefaults' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'disableResilienceDefaults' -Value $true).Value |
                    Should-Be 'True'
            }
        }

        It 'drops a false boolean, which asserts nothing' {
            InModuleScope CaOutcome {
                ConvertTo-CaSessionControlValue -Control 'disableResilienceDefaults' -Value $false |
                    Should-BeNull
            }
        }

        It 'renders a string or a number' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'someControl' -Value 'value').Value |
                    Should-Be 'value'
                (ConvertTo-CaSessionControlValue -Control 'someControl' -Value 42).Value |
                    Should-Be '42'
            }
        }

        It 'returns nothing for a null value' {
            InModuleScope CaOutcome {
                ConvertTo-CaSessionControlValue -Control 'anything' -Value $null | Should-BeNull
            }
        }
    }

    Context 'a control this module has never heard of' {

        It 'reports it as enabled when isEnabled is all it carries' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'someFutureControl' `
                    -Value ([PSCustomObject]@{ isEnabled = $true })).Value | Should-Be 'enabled'
            }
        }

        It 'renders its detail, sorted, rather than dropping it' {
            # A new control has to be visible the day Microsoft ships it. Sorted so that Graph
            # reordering the properties is not read as the control changing.
            InModuleScope CaOutcome {
                $rendered = ConvertTo-CaSessionControlValue -Control 'someFutureControl' -Value (
                    [PSCustomObject]@{
                        isEnabled = $true; zebra = 'last'; alpha = 'first'; '@odata.type' = 'ignored'
                    })

                $rendered.Value | Should-Be 'alpha=first;zebra=last'
                $rendered.RestrictivenessRank | Should-BeNull
            }
        }

        It 'renders the detail of a hashtable control too' {
            InModuleScope CaOutcome {
                (ConvertTo-CaSessionControlValue -Control 'someFutureControl' `
                    -Value @{ isEnabled = $true; mode = 'strict' }).Value | Should-Be 'mode=strict'
            }
        }
    }
}

Describe 'Merge-CaSessionControl' -Tag 'Unit', 'Private' {

    It 'reports no conflict when two policies agree' {
        InModuleScope CaOutcome {
            $contributions = @(
                [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'never'; RestrictivenessRank = 0
                                   PolicyId = 'a'; PolicyName = 'A' }
                [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'never'; RestrictivenessRank = 0
                                   PolicyId = 'b'; PolicyName = 'B' }
            )

            $merged = Merge-CaSessionControl -Contribution $contributions
            $merged.Controls.persistentBrowser | Should-Be 'never'
            @($merged.Conflicts).Count | Should-Be 0
        }
    }

    It 'resolves always against never in favour of the stricter value, and still reports it' {
        # The conflict that exists in the real tenant. Resolving it is right; hiding it is not,
        # because the outcome now depends on precedence rather than on anyone's intent.
        InModuleScope CaOutcome {
            $contributions = @(
                [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'always'; RestrictivenessRank = 1
                                   PolicyId = 'a'; PolicyName = 'REQUIRE - MFA for All Users' }
                [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'never'; RestrictivenessRank = 0
                                   PolicyId = 'b'; PolicyName = 'REQUIRE - No Persistent Browser Session' }
            )

            $merged = Merge-CaSessionControl -Contribution $contributions
            $merged.Controls.persistentBrowser | Should-Be 'never'

            $conflict = @($merged.Conflicts)[0]
            $conflict.Control | Should-Be 'persistentBrowser'
            $conflict.Resolved | Should-BeTrue
            $conflict.Winner | Should-Be 'never'
            @($conflict.Policies).Count | Should-Be 2
        }
    }

    It 'picks the same winner however Graph ordered the policies' {
        <#
            The regression. An unresolved conflict still has to put SOMETHING in
            SessionControls, and that value used to be whichever contribution arrived
            first - which is the order Graph returned the policies in, and Graph
            guarantees no order. The baseline then stored a different winner run to run,
            and a comparison against an unchanged tenant reported drift.

            Found against a real tenant: two policies disagreeing about cloudAppSecurity
            flagged 2 of 24 scenarios as changed when nothing had changed at all.
        #>
        InModuleScope CaOutcome {
            $a = [PSCustomObject]@{ Control = 'cloudAppSecurity'; Value = 'monitorOnly'
                                    RestrictivenessRank = $null; PolicyId = 'a'; PolicyName = 'A' }
            $b = [PSCustomObject]@{ Control = 'cloudAppSecurity'; Value = 'blockDownloads'
                                    RestrictivenessRank = $null; PolicyId = 'b'; PolicyName = 'B' }

            $oneWay = Merge-CaSessionControl -Contribution @($a, $b)
            $theOther = Merge-CaSessionControl -Contribution @($b, $a)

            $oneWay.Controls.cloudAppSecurity | Should-Be $theOther.Controls.cloudAppSecurity
            # And it is still reported as unresolved - determinism is not a decision
            @($oneWay.Conflicts)[0].Resolved | Should-BeFalse
            @($theOther.Conflicts)[0].Resolved | Should-BeFalse
        }
    }

    It 'breaks a restrictiveness tie deterministically too' {
        InModuleScope CaOutcome {
            $a = [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'alpha'
                                    RestrictivenessRank = 5; PolicyId = 'a'; PolicyName = 'A' }
            $b = [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'beta'
                                    RestrictivenessRank = 5; PolicyId = 'b'; PolicyName = 'B' }

            (Merge-CaSessionControl -Contribution @($a, $b)).Controls.persistentBrowser |
                Should-Be (Merge-CaSessionControl -Contribution @($b, $a)).Controls.persistentBrowser
        }
    }

    It 'refuses to resolve a control it has no defensible ordering for' {
        InModuleScope CaOutcome {
            $contributions = @(
                [PSCustomObject]@{ Control = 'cloudAppSecurity'; Value = 'monitorOnly'
                                   RestrictivenessRank = $null; PolicyId = 'a'; PolicyName = 'A' }
                [PSCustomObject]@{ Control = 'cloudAppSecurity'; Value = 'blockDownloads'
                                   RestrictivenessRank = $null; PolicyId = 'b'; PolicyName = 'B' }
            )

            $conflict = @((Merge-CaSessionControl -Contribution $contributions).Conflicts)[0]
            $conflict.Resolved | Should-BeFalse
            $conflict.Values | Should-BeCollection @('blockDownloads', 'monitorOnly')
        }
    }

    It 'stacks controls from different policies rather than letting one win' {
        InModuleScope CaOutcome {
            $contributions = @(
                [PSCustomObject]@{ Control = 'persistentBrowser'; Value = 'never'; RestrictivenessRank = 0
                                   PolicyId = 'a'; PolicyName = 'A' }
                [PSCustomObject]@{ Control = 'signInFrequency'; Value = '1 hours'; RestrictivenessRank = 60
                                   PolicyId = 'b'; PolicyName = 'B' }
            )

            $merged = Merge-CaSessionControl -Contribution $contributions
            $merged.Controls.persistentBrowser | Should-Be 'never'
            $merged.Controls.signInFrequency | Should-Be '1 hours'
        }
    }

    It 'copes with no contributions at all' {
        InModuleScope CaOutcome {
            $merged = Merge-CaSessionControl -Contribution @()
            @($merged.Conflicts).Count | Should-Be 0
            @($merged.Controls.PSObject.Properties).Count | Should-Be 0
        }
    }
}