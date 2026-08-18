#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The diff, tested on hand-built outcomes so each kind of change can be isolated.

    The reason this diffs outcomes rather than policy lists is the case in the last Context: a
    group membership change moves someone into the scope of a policy whose JSON never changed.
    Config drift tooling cannot see it, because there is no config drift. Comparing a stored
    outcome against a fresh one does see it, which is the whole argument for baselining.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-Outcome' -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-Strength' -ErrorAction SilentlyContinue
}

Describe 'Compare-CaEffectiveControl' -Tag 'Unit', 'Private' {

    BeforeAll {
        # Global scope so that InModuleScope can resolve it. A function defined in the test
        # scope is invisible from inside the module's session state.
        function global:New-Outcome {
            param(
                [string]$Access = 'GrantedWithControls',
                [string[]]$Required = @(),
                $BlockedBy = @(),
                $Unsatisfiable = @(),
                [hashtable]$Session = @{},
                $Applied = @(),
                $Choices = @(),
                $Strengths = @()
            )
            [PSCustomObject]@{
                Access                    = $Access
                BlockedBy                 = $BlockedBy
                RequiredControls          = $Required
                OptionalChoices           = $Choices
                UnsatisfiableRequirements = $Unsatisfiable
                AuthenticationStrengths   = $Strengths
                IsEffectivelyBlocked      = ($Access -eq 'Blocked' -or @($Unsatisfiable).Count -gt 0)
                SessionControls           = [PSCustomObject]$Session
                SessionConflicts          = @()
                AppliedPolicies           = $Applied
            }
        }

        function global:New-Strength {
            param([string]$Name = 'Contoso strong', [string[]]$Combinations, [int]$ConfigCount = 0)
            [PSCustomObject]@{
                Control                       = "authenticationStrength:$Name"
                Id                            = 'abc'
                DisplayName                   = $Name
                PolicyType                    = 'custom'
                AllowedCombinations           = $Combinations
                CombinationConfigurationCount = $ConfigCount
            }
        }
    }

    It 'reports no change between identical outcomes' {
        InModuleScope CaOutcome {
            $outcome = New-Outcome -Required @('mfa') -Session @{ persistentBrowser = 'never' }
            $delta = Compare-CaEffectiveControl -From $outcome -To $outcome

            $delta.HasChange | Should-BeFalse
            $delta.Summary | Should-Be 'No change'
        }
    }

    It 'reports a newly required control' {
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Required @('mfa')) `
                -To (New-Outcome -Required @('mfa', 'compliantDevice'))

            $delta.HasChange | Should-BeTrue
            $delta.AddedRequiredControls | Should-BeCollection @('compliantDevice')
            @($delta.RemovedRequiredControls).Count | Should-Be 0
        }
    }

    It 'reports a requirement that has gone away' {
        # Not possible when promoting report-only policies, which can only add. It is possible
        # when comparing a stored baseline against a later run, which is the other caller.
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Required @('mfa', 'compliantDevice')) `
                -To (New-Outcome -Required @('mfa'))

            $delta.RemovedRequiredControls | Should-BeCollection @('compliantDevice')
            $delta.Summary | Should-MatchString 'no longer requires'
        }
    }

    It 'reports access flipping to blocked' {
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Required @('mfa')) `
                -To (New-Outcome -Access 'Blocked' -BlockedBy @([PSCustomObject]@{
                        PolicyId = 'b'; PolicyName = 'BLOCK - Corp devices only' }))

            $delta.AccessChanged | Should-BeTrue
            $delta.BecomesEffectivelyBlocked | Should-BeTrue
            $delta.Summary | Should-MatchString 'access GrantedWithControls -> Blocked'
        }
    }

    It 'distinguishes a lockout from a mere extra requirement' {
        InModuleScope CaOutcome {
            $unsatisfiable = @([PSCustomObject]@{
                PolicyId = 'p'; PolicyName = 'GRANT - Compliant devices'
                Operator = 'OR'; Controls = @('compliantDevice'); Blockers = @('compliantDevice') })

            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Required @('mfa')) `
                -To (New-Outcome -Required @('mfa', 'compliantDevice') -Unsatisfiable $unsatisfiable)

            # Access never changes - both worlds say GrantedWithControls - so a diff that looked
            # only at Access would call this harmless
            $delta.AccessChanged | Should-BeFalse
            $delta.BecomesEffectivelyBlocked | Should-BeTrue
            $delta.Summary | Should-MatchString 'LOCKS OUT'
        }
    }

    It 'tells an added session control from a changed one' {
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Session @{ persistentBrowser = 'always' }) `
                -To (New-Outcome -Session @{ persistentBrowser = 'never'; signInFrequency = '1 hours' })

            @($delta.ChangedSessionControls)[0].Control | Should-Be 'persistentBrowser'
            @($delta.ChangedSessionControls)[0].From | Should-Be 'always'
            @($delta.ChangedSessionControls)[0].To | Should-Be 'never'
            @($delta.AddedSessionControls)[0].Control | Should-Be 'signInFrequency'
        }
    }

    It 'reports a session control that has disappeared' {
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Session @{ persistentBrowser = 'never'; signInFrequency = '1 hours' }) `
                -To (New-Outcome -Session @{ persistentBrowser = 'never' })

            @($delta.RemovedSessionControls)[0].Control | Should-Be 'signInFrequency'
        }
    }

    Context 'a custom authentication strength being edited' {

        <#
            A custom strength is a tenant object, and editing it changes what every policy
            referencing it requires without anyone editing a policy. The requirement string is
            unchanged too, because the strength keeps its name, so this only surfaces by
            comparing the combinations themselves.

            Measured against a real tenant rather than assumed: Graph inlines the strength
            inside each referencing policy, so a policy export is not byte-identical after the
            edit. It moves as N policies with a changed blob, where this reports one strength
            weakened and what was added to it.
        #>

        It 'reports a strength that has been widened as a weakening' {
            InModuleScope CaOutcome {
                $before = New-Outcome -Required @('authenticationStrength:Contoso strong') `
                    -Strengths @(New-Strength -Combinations @('fido2', 'windowsHelloForBusiness'))
                $after = New-Outcome -Required @('authenticationStrength:Contoso strong') `
                    -Strengths @(New-Strength -Combinations @('fido2', 'windowsHelloForBusiness',
                        'password,sms'))

                $delta = Compare-CaEffectiveControl -From $before -To $after

                # Nothing else moved: same access, same required controls, same policies
                $delta.AccessChanged | Should-BeFalse
                @($delta.AddedRequiredControls).Count | Should-Be 0

                $delta.HasChange | Should-BeTrue
                @($delta.WeakenedStrengths)[0].AddedCombinations | Should-BeCollection @('password,sms')
                $delta.Summary | Should-MatchString 'WEAKENED'
            }
        }

        It 'reports a strength that has been narrowed as a tightening' {
            InModuleScope CaOutcome {
                $before = New-Outcome -Strengths @(New-Strength -Combinations @('fido2', 'sms'))
                $after = New-Outcome -Strengths @(New-Strength -Combinations @('fido2'))

                $delta = Compare-CaEffectiveControl -From $before -To $after
                @($delta.StrengthenedStrengths)[0].RemovedCombinations | Should-BeCollection @('sms')
                $delta.Summary | Should-MatchString 'no longer allows'
            }
        }

        It 'reports a dropped combination configuration as a weakening' {
            # Removing a FIDO2 AAGUID allowlist or a certificate issuer restriction widens what
            # satisfies the strength without changing a single combination
            InModuleScope CaOutcome {
                $before = New-Outcome -Strengths @(New-Strength -Combinations @('fido2') -ConfigCount 2)
                $after = New-Outcome -Strengths @(New-Strength -Combinations @('fido2') -ConfigCount 0)

                $delta = Compare-CaEffectiveControl -From $before -To $after
                $delta.HasChange | Should-BeTrue
                @($delta.WeakenedStrengths)[0].RemovedConfigurations | Should-Be 2
            }
        }

        It 'says nothing when the strength is unchanged' {
            InModuleScope CaOutcome {
                $strengths = @(New-Strength -Combinations @('fido2', 'windowsHelloForBusiness'))
                $outcome = New-Outcome -Strengths $strengths

                $delta = Compare-CaEffectiveControl -From $outcome -To $outcome
                $delta.HasChange | Should-BeFalse
                @($delta.WeakenedStrengths).Count | Should-Be 0
            }
        }

        It 'ignores a strength that only appears on one side' {
            # That is a policy coming into or out of scope, already reported as a requirement
            # change; reporting it again as a strength edit would double count it
            InModuleScope CaOutcome {
                $before = New-Outcome
                $after = New-Outcome -Strengths @(New-Strength -Combinations @('fido2'))

                $delta = Compare-CaEffectiveControl -From $before -To $after
                @($delta.WeakenedStrengths).Count | Should-Be 0
                @($delta.StrengthenedStrengths).Count | Should-Be 0
            }
        }
    }

    It 'notices a policy coming into scope even when the requirements are unchanged' {
        # The case that argues for baselining. Someone joins a group, a policy that already
        # required MFA now also applies to them, and no policy JSON changed anywhere.
        InModuleScope CaOutcome {
            $delta = Compare-CaEffectiveControl `
                -From (New-Outcome -Required @('mfa') -Applied @(
                    [PSCustomObject]@{ Id = 'a'; DisplayName = 'A'; State = 'enabled' })) `
                -To (New-Outcome -Required @('mfa') -Applied @(
                    [PSCustomObject]@{ Id = 'a'; DisplayName = 'A'; State = 'enabled' }
                    [PSCustomObject]@{ Id = 'b'; DisplayName = 'B'; State = 'enabled' }))

            @($delta.AddedPolicies).Count | Should-Be 1
            @($delta.AddedPolicies)[0].DisplayName | Should-Be 'B'
        }
    }
}
