#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The fold itself: many policy verdicts in, one outcome out.

    Three rules are load bearing and each has a test that fails loudly if it slips.

    Block wins. Entra evaluates every matching policy and enforces the most restrictive
    combination, so one applying block ends it no matter how many grants sit beside it. A fold
    that let a later grant overwrite an earlier block would report a denied sign-in as
    permitted, which is the worst direction to be wrong in.

    A world is a set of policy states. Getting the state filter wrong is invisible in the output
    - both worlds still produce a plausible looking outcome - and it silently destroys the whole
    point of the module, because the projection stops meaning "after promotion".

    Unsatisfiable means the simulated sign-in cannot meet the requirement, and an OR clause is
    only unsatisfiable when every alternative is. Getting that backwards turns "MFA or compliant
    device, on a non-compliant device" into a false lockout report.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-TestPolicy' -ErrorAction SilentlyContinue
}

Describe 'Get-CaEffectiveControl' -Tag 'Unit', 'Private' {

    BeforeAll {
        # Global scope so that InModuleScope can resolve it. A function defined in the test
        # scope is invisible from inside the module's session state.
        function global:New-TestPolicy {
            param(
                [string]$Id, [string]$Name, [string]$State = 'enabled', [bool]$Applies = $true,
                [string]$Operator = 'OR', [string[]]$Controls, $SessionControls
            )
            $grant = $null
            if ($Controls) {
                $grant = [PSCustomObject]@{ operator = $Operator; builtInControls = $Controls }
            }
            [PSCustomObject]@{
                id = $Id; displayName = $Name; state = $State; policyApplies = $Applies
                grantControls = $grant; sessionControls = $SessionControls
            }
        }
    }

    Context 'block precedence' {

        It 'blocks when any applying policy blocks, whatever else grants' {
            InModuleScope CaOutcome {
                $policies = @(
                    New-TestPolicy -Id 'g' -Name 'Grant with MFA' -Controls @('mfa')
                    New-TestPolicy -Id 'b' -Name 'Block legacy' -Controls @('block')
                    New-TestPolicy -Id 'g2' -Name 'Another grant' -Controls @('compliantDevice')
                )

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                $outcome.Access | Should-Be 'Blocked'
                $outcome.IsEffectivelyBlocked | Should-BeTrue
                @($outcome.BlockedBy)[0].PolicyName | Should-Be 'Block legacy'
            }
        }

        It 'grants with no controls when only session policies apply' {
            InModuleScope CaOutcome {
                $policies = @(
                    New-TestPolicy -Id 's' -Name 'Session only' -Controls $null -SessionControls (
                        [PSCustomObject]@{
                            persistentBrowser = [PSCustomObject]@{ mode = 'never'; isEnabled = $true }
                        })
                )

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                $outcome.Access | Should-Be 'Granted'
                $outcome.SessionControls.persistentBrowser | Should-Be 'never'
            }
        }
    }

    Context 'world membership' {

        It 'excludes a policy that does not apply, even in its own state' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'n' -Name 'Does not apply' -Applies $false -Controls @('mfa'))

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                $outcome.Access | Should-Be 'Granted'
                @($outcome.AppliedPolicies).Count | Should-Be 0
            }
        }

        It 'excludes a report-only policy from the current world and includes it in the projected one' {
            InModuleScope CaOutcome {
                $policies = @(
                    New-TestPolicy -Id 'e' -Name 'Enabled MFA' -Controls @('mfa')
                    New-TestPolicy -Id 'r' -Name 'Piloted compliant device' `
                        -State 'enabledForReportingButNotEnforced' -Controls @('compliantDevice')
                )

                $current = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                $projected = Get-CaEffectiveControl -Policy $policies `
                    -State @('enabled', 'enabledForReportingButNotEnforced') -World 'Projected'

                $current.RequiredControls | Should-BeCollection @('mfa')
                $projected.RequiredControls | Should-BeCollection @('compliantDevice', 'mfa')
            }
        }

        It 'leaves a disabled policy out of both worlds' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'd' -Name 'Switched off' -State 'disabled' -Controls @('block'))

                $projected = Get-CaEffectiveControl -Policy $policies `
                    -State @('enabled', 'enabledForReportingButNotEnforced') -World 'Projected'
                $projected.Access | Should-Be 'Granted'
            }
        }
    }

    Context 'requirements and choices' {

        It 'states a single-control OR clause flatly, since there is no choice in it' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'MFA' -Operator 'OR' -Controls @('mfa'))

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                $outcome.RequiredControls | Should-BeCollection @('mfa')
                @($outcome.OptionalChoices).Count | Should-Be 0
            }
        }

        It 'keeps a multi-control OR clause as a choice rather than requiring both' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'MFA or compliant' -Operator 'OR' `
                    -Controls @('mfa', 'compliantDevice'))

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                @($outcome.RequiredControls).Count | Should-Be 0
                @($outcome.OptionalChoices)[0].AnyOf | Should-BeCollection @('mfa', 'compliantDevice')
                $outcome.Access | Should-Be 'GrantedWithControls'
            }
        }

        It 'requires every control of an AND clause' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'MFA and password change' -Operator 'AND' `
                    -Controls @('mfa', 'passwordChange'))

                (Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current').RequiredControls |
                    Should-BeCollection @('mfa', 'passwordChange')
            }
        }

        It 'does not repeat a control two policies both require' {
            InModuleScope CaOutcome {
                $policies = @(
                    New-TestPolicy -Id 'a' -Name 'A' -Controls @('mfa')
                    New-TestPolicy -Id 'b' -Name 'B' -Controls @('mfa')
                )

                (Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current').RequiredControls |
                    Should-BeCollection @('mfa')
            }
        }
    }

    Context 'satisfiability against the simulated conditions' {

        It 'flags a compliant device requirement the simulated device cannot meet' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'Require compliant' -Controls @('compliantDevice'))
                $conditions = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $false } }

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current' `
                    -SignInCondition $conditions

                $outcome.IsEffectivelyBlocked | Should-BeTrue
                @($outcome.UnsatisfiableRequirements)[0].Blockers | Should-BeCollection @('compliantDevice')
            }
        }

        It 'does not flag it when the simulated device is compliant' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'Require compliant' -Controls @('compliantDevice'))
                $conditions = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $true } }

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current' `
                    -SignInCondition $conditions

                $outcome.IsEffectivelyBlocked | Should-BeFalse
                @($outcome.UnsatisfiableRequirements).Count | Should-Be 0
            }
        }

        It 'leaves an OR clause satisfiable while any alternative survives' {
            # MFA or compliant device, on a non-compliant device, is not a lockout - the user
            # can still do MFA
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'MFA or compliant' -Operator 'OR' `
                    -Controls @('mfa', 'compliantDevice'))
                $conditions = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $false } }

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current' `
                    -SignInCondition $conditions

                $outcome.IsEffectivelyBlocked | Should-BeFalse
            }
        }

        It 'fails an AND clause on one impossible control' {
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'MFA and compliant' -Operator 'AND' `
                    -Controls @('mfa', 'compliantDevice'))
                $conditions = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $false } }

                (Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current' `
                    -SignInCondition $conditions).IsEffectivelyBlocked | Should-BeTrue
            }
        }

        It 'says nothing at all when no conditions were supplied' {
            # Silence is the honest answer without evidence. Reporting a lockout from an unknown
            # device state would train the reader to ignore the field.
            InModuleScope CaOutcome {
                $policies = @(New-TestPolicy -Id 'p' -Name 'Require compliant' -Controls @('compliantDevice'))

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                @($outcome.UnsatisfiableRequirements).Count | Should-Be 0
                $outcome.IsEffectivelyBlocked | Should-BeFalse
            }
        }
    }
}

Describe 'Get-CaControlSatisfiability' -Tag 'Unit', 'Private' {

    <#
        Every rule below rests on a documented Microsoft constraint, and the asymmetry is the
        reason for the last Context. A missed lockout is a finding this module fails to make.
        An invented one sends somebody to investigate a policy that is fine, and two of those
        teach the reader to ignore the field entirely.
    #>

    Context 'device state' {

        It 'decides compliant device from the simulated device state' {
            InModuleScope CaOutcome {
                $no = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $false } }
                $yes = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $true } }

                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $no).Verdict |
                    Should-Be 'Unsatisfiable'
                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $yes).Verdict |
                    Should-Be 'Satisfiable'
            }
        }

        It 'treats an Entra joined device as not satisfying a hybrid join requirement' {
            InModuleScope CaOutcome {
                $entraJoined = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ trustType = 'azureAD' } }
                $hybrid = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ trustType = 'serverAD' } }

                (Get-CaControlSatisfiability -Control 'domainJoinedDevice' `
                    -SignInCondition $entraJoined).Verdict | Should-Be 'Unsatisfiable'
                (Get-CaControlSatisfiability -Control 'domainJoinedDevice' `
                    -SignInCondition $hybrid).Verdict | Should-Be 'Satisfiable'
            }
        }

        It 'explains why, not just that' {
            InModuleScope CaOutcome {
                $no = [PSCustomObject]@{ deviceInfo = [PSCustomObject]@{ isCompliant = $false } }
                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $no).Reason |
                    Should-Be 'the simulated device is not compliant'
            }
        }
    }

    Context 'legacy authentication clients' {

        <#
            "Sign-ins from legacy authentication clients don't support multifactor
            authentication (MFA) and don't pass device state information, so they're blocked by
            Conditional Access grant controls, like requiring MFA or compliant devices."

            This one condition decides most of the interesting controls at once, and it is the
            rule that fires most often against a real tenant.
        #>

        It 'rules out every interactive control for Other clients' {
            InModuleScope CaOutcome {
                $legacy = [PSCustomObject]@{ clientAppType = 'other' }

                foreach ($control in @('mfa', 'passwordChange', 'authenticationStrength:Phishing resistant',
                        'termsOfUse:abc', 'customAuthenticationFactor:xyz')) {
                    (Get-CaControlSatisfiability -Control $control -SignInCondition $legacy).Verdict |
                        Should-Be 'Unsatisfiable'
                }
            }
        }

        It 'rules out device state controls, which legacy clients do not pass' {
            InModuleScope CaOutcome {
                $legacy = [PSCustomObject]@{
                    clientAppType = 'exchangeActiveSync'
                    deviceInfo = [PSCustomObject]@{ isCompliant = $true; trustType = 'serverAD' }
                }

                # Note the device is compliant AND hybrid joined. The client type overrides it,
                # so a blocking rule has to beat a satisfying one.
                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $legacy).Verdict |
                    Should-Be 'Unsatisfiable'
                (Get-CaControlSatisfiability -Control 'domainJoinedDevice' -SignInCondition $legacy).Verdict |
                    Should-Be 'Unsatisfiable'
            }
        }

        It 'does not treat easSupported as legacy' {
            # easSupported names the EAS clients that DO support modern authentication, which is
            # the entire point of Microsoft keeping it as a separate client app type
            InModuleScope CaOutcome {
                $modern = [PSCustomObject]@{ clientAppType = 'easSupported' }
                (Get-CaControlSatisfiability -Control 'mfa' -SignInCondition $modern).Verdict |
                    Should-Be 'Unknown'
            }
        }

        It 'does not treat a browser or a desktop client as legacy' {
            InModuleScope CaOutcome {
                foreach ($clientApp in @('browser', 'mobileAppsAndDesktopClients', 'all')) {
                    $conditions = [PSCustomObject]@{ clientAppType = $clientApp }
                    (Get-CaControlSatisfiability -Control 'mfa' -SignInCondition $conditions).Verdict |
                        Should-Be 'Unknown'
                }
            }
        }
    }

    Context 'device code flow' {

        <#
            "the required grant control for the managed device or a device state condition isn't
            supported. This is because the device that is performing authentication can't
            provide its device state to the device that is providing a code."
        #>

        It 'rules out device state controls even on a compliant hybrid joined device' {
            InModuleScope CaOutcome {
                $deviceCode = [PSCustomObject]@{
                    devicePlatform = 'windows'
                    authenticationFlow = [PSCustomObject]@{ transferMethod = 'deviceCodeFlow' }
                    deviceInfo = [PSCustomObject]@{ isCompliant = $true; trustType = 'serverAD' }
                }

                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $deviceCode).Verdict |
                    Should-Be 'Unsatisfiable'
                (Get-CaControlSatisfiability -Control 'domainJoinedDevice' -SignInCondition $deviceCode).Verdict |
                    Should-Be 'Unsatisfiable'
            }
        }

        It 'leaves MFA alone, which is what Microsoft recommends using instead' {
            InModuleScope CaOutcome {
                $deviceCode = [PSCustomObject]@{
                    authenticationFlow = [PSCustomObject]@{ transferMethod = 'deviceCodeFlow' }
                }
                (Get-CaControlSatisfiability -Control 'mfa' -SignInCondition $deviceCode).Verdict |
                    Should-Be 'Unknown'
            }
        }

        It 'does not fire on a different transfer method' {
            InModuleScope CaOutcome {
                $transfer = [PSCustomObject]@{
                    authenticationFlow = [PSCustomObject]@{ transferMethod = 'authenticationTransfer' }
                    deviceInfo = [PSCustomObject]@{ isCompliant = $true }
                }
                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $transfer).Verdict |
                    Should-Be 'Satisfiable'
            }
        }
    }

    Context 'platform-limited controls' {

        It 'rules out approved client app anywhere but iOS and Android' {
            # "Only supports the iOS and Android for device platform condition."
            InModuleScope CaOutcome {
                foreach ($platform in @('windows', 'macOS', 'linux', 'windowsPhone')) {
                    (Get-CaControlSatisfiability -Control 'approvedApplication' `
                        -SignInCondition ([PSCustomObject]@{ devicePlatform = $platform })).Verdict |
                        Should-Be 'Unsatisfiable'
                }

                foreach ($platform in @('iOS', 'android')) {
                    (Get-CaControlSatisfiability -Control 'approvedApplication' `
                        -SignInCondition ([PSCustomObject]@{ devicePlatform = $platform })).Verdict |
                        Should-Be 'Unknown'
                }
            }
        }

        It 'rules out hybrid join anywhere but Windows' {
            InModuleScope CaOutcome {
                foreach ($platform in @('iOS', 'android', 'macOS', 'linux')) {
                    (Get-CaControlSatisfiability -Control 'domainJoinedDevice' `
                        -SignInCondition ([PSCustomObject]@{ devicePlatform = $platform })).Verdict |
                        Should-Be 'Unsatisfiable'
                }
            }
        }

        It 'rules out app protection policy on macOS and Linux' {
            InModuleScope CaOutcome {
                foreach ($platform in @('macOS', 'linux')) {
                    (Get-CaControlSatisfiability -Control 'compliantApplication' `
                        -SignInCondition ([PSCustomObject]@{ devicePlatform = $platform })).Verdict |
                        Should-Be 'Unsatisfiable'
                }
            }
        }

        It 'leaves app protection policy on Windows unknown, because it is in preview there' {
            # Preview for Microsoft Edge on Windows, and nothing in the request names the
            # browser. Calling this a lockout would be the invented finding.
            InModuleScope CaOutcome {
                (Get-CaControlSatisfiability -Control 'compliantApplication' `
                    -SignInCondition ([PSCustomObject]@{ devicePlatform = 'windows' })).Verdict |
                    Should-Be 'Unknown'
            }
        }

        It 'rules out device compliance on a platform Intune does not support' {
            InModuleScope CaOutcome {
                $conditions = [PSCustomObject]@{
                    devicePlatform = 'windowsPhone'
                    deviceInfo = [PSCustomObject]@{ isCompliant = $true }
                }

                (Get-CaControlSatisfiability -Control 'compliantDevice' `
                    -SignInCondition $conditions).Verdict | Should-Be 'Unsatisfiable'
            }
        }
    }

    Context 'authentication strengths' {

        It 'rules out a strength that allows no combination at all' {
            InModuleScope CaOutcome {
                $detail = [PSCustomObject]@{ DisplayName = 'Empty'; AllowedCombinations = @() }

                (Get-CaControlSatisfiability -Control 'authenticationStrength:Empty' `
                    -SignInCondition ([PSCustomObject]@{ devicePlatform = 'windows' }) `
                    -ControlDetail $detail).Verdict | Should-Be 'Unsatisfiable'
            }
        }

        It 'does NOT infer a platform from a combination name' {
            <#
                The tempting inference is that a strength allowing only windowsHelloForBusiness
                cannot be satisfied on iOS. It is wrong: the combination is documented as
                "Windows Hello for Business or platform credential" and now covers macOS
                Platform SSO, so the name does not name a platform. No allowedCombinations
                value carries a documented platform restriction, and asserting one here would
                manufacture exactly the invented lockout this module refuses to produce.
            #>
            InModuleScope CaOutcome {
                $detail = [PSCustomObject]@{
                    DisplayName = 'WHfB only'
                    AllowedCombinations = @('windowsHelloForBusiness')
                }

                foreach ($platform in @('iOS', 'android', 'macOS', 'linux')) {
                    (Get-CaControlSatisfiability -Control 'authenticationStrength:WHfB only' `
                        -SignInCondition ([PSCustomObject]@{ devicePlatform = $platform }) `
                        -ControlDetail $detail).Verdict | Should-Be 'Unknown'
                }
            }
        }

        It 'still rules a strength out on a legacy client, which cannot authenticate at all' {
            InModuleScope CaOutcome {
                $detail = [PSCustomObject]@{ DisplayName = 'S'; AllowedCombinations = @('fido2') }

                (Get-CaControlSatisfiability -Control 'authenticationStrength:S' `
                    -SignInCondition ([PSCustomObject]@{ clientAppType = 'other' }) `
                    -ControlDetail $detail).Verdict | Should-Be 'Unsatisfiable'
            }
        }

        It 'surfaces each applying strength once, however many policies name it' {
            # The strength is a tenant object, not a property of the policy
            InModuleScope CaOutcome {
                $strength = [PSCustomObject]@{
                    displayName = 'Passwordless MFA'; id = 'abc'
                    allowedCombinations = @('fido2', 'windowsHelloForBusiness')
                }
                $policies = @(
                    [PSCustomObject]@{
                        id = 'a'; displayName = 'A'; state = 'enabled'; policyApplies = $true
                        grantControls = [PSCustomObject]@{ operator = 'OR'
                                                           authenticationStrength = $strength }
                    }
                    [PSCustomObject]@{
                        id = 'b'; displayName = 'B'; state = 'enabled'; policyApplies = $true
                        grantControls = [PSCustomObject]@{ operator = 'OR'
                                                           authenticationStrength = $strength }
                    }
                )

                $outcome = Get-CaEffectiveControl -Policy $policies -State 'enabled' -World 'Current'
                @($outcome.AuthenticationStrengths).Count | Should-Be 1
                @($outcome.AuthenticationStrengths)[0].AllowedCombinations |
                    Should-BeCollection @('fido2', 'windowsHelloForBusiness')
            }
        }
    }

    Context 'refusing to guess' {

        It 'treats an unconstrained platform as no evidence' {
            # 'all' and an absent value both mean unconstrained, so no platform rule may fire
            InModuleScope CaOutcome {
                foreach ($conditions in @(
                    [PSCustomObject]@{ devicePlatform = 'all' }
                    [PSCustomObject]@{ clientAppType = 'browser' }
                )) {
                    (Get-CaControlSatisfiability -Control 'approvedApplication' `
                        -SignInCondition $conditions).Verdict | Should-Be 'Unknown'
                    (Get-CaControlSatisfiability -Control 'domainJoinedDevice' `
                        -SignInCondition $conditions).Verdict | Should-Be 'Unknown'
                }
            }
        }

        It 'never judges whether a user could complete MFA on a modern client' {
            InModuleScope CaOutcome {
                $modern = [PSCustomObject]@{
                    devicePlatform = 'windows'; clientAppType = 'browser'
                    deviceInfo = [PSCustomObject]@{ isCompliant = $false }
                }

                foreach ($control in @('mfa', 'passwordChange', 'authenticationStrength:X',
                        'termsOfUse:abc', 'customAuthenticationFactor:xyz')) {
                    (Get-CaControlSatisfiability -Control $control -SignInCondition $modern).Verdict |
                        Should-Be 'Unknown'
                }
            }
        }

        It 'returns Unknown rather than throwing when there are no conditions at all' {
            InModuleScope CaOutcome {
                (Get-CaControlSatisfiability -Control 'compliantDevice' -SignInCondition $null).Verdict |
                    Should-Be 'Unknown'
                (Get-CaControlSatisfiability -Control 'compliantDevice' `
                    -SignInCondition ([PSCustomObject]@{ devicePlatform = 'windows' })).Verdict |
                    Should-Be 'Unknown'
            }
        }

        It 'says nothing about a control it has never heard of' {
            InModuleScope CaOutcome {
                (Get-CaControlSatisfiability -Control 'someFutureControl' `
                    -SignInCondition ([PSCustomObject]@{ clientAppType = 'other' })).Verdict |
                    Should-Be 'Unknown'
            }
        }
    }
}
