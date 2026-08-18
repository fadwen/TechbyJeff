#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    End to end, against What If responses captured from a real tenant.

    The fixtures are genuine responses from a tenant carrying nine enabled and four report-only
    Conditional Access policies, with directory object ids rewritten to synthetic ones. Keeping
    them real matters more here than anywhere else in this module: every shape that caused a
    defect during development came from the API rather than from imagination - grantControls
    with an empty builtInControls array, sessionControls padded with nulls, two policies
    disagreeing about persistent browser on the same sign-in. Hand-written fixtures would have
    had none of those.

    Each fixture carries the signInConditions that produced it alongside the response, so the
    satisfiability check can be exercised on the same data the tenant actually answered for.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force

    $script:FixtureRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures'

    function Get-Fixture {
        param([string]$Name)
        Get-Content (Join-Path $script:FixtureRoot "$Name.json") -Raw | ConvertFrom-Json
    }

    function Get-Outcome {
        param([string]$Name, [switch]$WithoutConditions)
        $fixture = Get-Fixture -Name $Name
        if ($WithoutConditions) {
            return ConvertTo-CaOutcome -WhatIfResult $fixture.whatIf -ScenarioName $Name
        }
        ConvertTo-CaOutcome -WhatIfResult $fixture.whatIf -SignInCondition $fixture.signInConditions `
            -ScenarioName $Name
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-CaOutcome against captured tenant responses' -Tag 'Unit', 'Public' {

    Context 'the headline case: a promotion that locks someone out' {

        BeforeAll {
            $script:LockOut = Get-Outcome -Name 'promotion-locks-out-noncompliant-device'
        }

        It 'lets the sign-in through today' {
            $script:LockOut.Current.IsEffectivelyBlocked | Should-BeFalse
        }

        It 'locks it out once the report-only policies are promoted' {
            $script:LockOut.Projected.IsEffectivelyBlocked | Should-BeTrue
            $script:LockOut.Delta.BecomesEffectivelyBlocked | Should-BeTrue
        }

        It 'names the policy and the control responsible' {
            $blocker = @($script:LockOut.Delta.NewlyUnsatisfiable)[0]
            $blocker.PolicyName | Should-Be 'GRANT - Compliant Windows Devices'
            $blocker.Blockers | Should-BeCollection @('compliantDevice')
        }

        It 'says so in one sentence' {
            $script:LockOut.Delta.Summary | Should-MatchString 'LOCKS OUT'
        }

        It 'reports only an added requirement when no conditions are supplied to judge against' {
            # Without the simulated device state there is no evidence of a lockout, and the
            # module must not invent one
            $blind = Get-Outcome -Name 'promotion-locks-out-noncompliant-device' -WithoutConditions
            $blind.Delta.BecomesEffectivelyBlocked | Should-BeFalse
            $blind.Delta.AddedRequiredControls | Should-BeCollection @('compliantDevice')
        }
    }

    Context 'the same policy against a device that can satisfy it' {

        BeforeAll {
            $script:Satisfiable = Get-Outcome -Name 'promotion-adds-satisfiable-requirement'
        }

        It 'reports the new requirement without calling it a lockout' {
            $script:Satisfiable.Delta.AddedRequiredControls | Should-BeCollection @('compliantDevice')
            $script:Satisfiable.Delta.BecomesEffectivelyBlocked | Should-BeFalse
            $script:Satisfiable.Projected.IsEffectivelyBlocked | Should-BeFalse
        }
    }

    Context 'a sign-in already blocked today' {

        BeforeAll {
            $script:Blocked = Get-Outcome -Name 'blocked-today-additionally-blocked-after'
        }

        It 'is blocked in both worlds' {
            $script:Blocked.Current.Access | Should-Be 'Blocked'
            $script:Blocked.Projected.Access | Should-Be 'Blocked'
            $script:Blocked.Delta.AccessChanged | Should-BeFalse
        }

        It 'still notices a second policy would also block it' {
            $script:Blocked.Delta.HasChange | Should-BeTrue
            @($script:Blocked.Delta.NewlyBlockedBy)[0].PolicyName | Should-Be 'BLOCK - 365 Unless Corp Devices'
        }

        It 'words it as an addition rather than as a fresh denial' {
            $script:Blocked.Delta.Summary | Should-MatchString 'additionally blocked by'
        }
    }

    Context 'two enabled policies disagreeing about a session control' {

        BeforeAll {
            $script:Conflict = Get-Outcome -Name 'session-control-conflict'
            $script:BrowserConflict = @($script:Conflict.Current.SessionConflicts |
                Where-Object Control -eq 'persistentBrowser')
        }

        It 'finds the persistent browser disagreement in the live policy set' {
            @($script:BrowserConflict).Count | Should-Be 1
            @($script:BrowserConflict)[0].Values | Should-BeCollection @('always', 'never')
        }

        It 'resolves it to the stricter value and says it did' {
            $conflict = @($script:BrowserConflict)[0]
            $conflict.Winner | Should-Be 'never'
            $conflict.Resolved | Should-BeTrue
            $script:Conflict.Current.SessionControls.persistentBrowser | Should-Be 'never'
        }

        It 'names both policies that fed the conflict' {
            @(@($script:BrowserConflict)[0].Policies).Count | Should-Be 2
        }
    }

    Context 'a tenant response where nothing report-only applies' {

        BeforeAll {
            $script:Vacuous = Get-Outcome -Name 'no-report-only-policy-applies'
        }

        It 'reports the two worlds as identical' {
            $script:Vacuous.Delta.HasChange | Should-BeFalse
            $script:Vacuous.Delta.Summary | Should-Be 'No change'
        }

        It 'says that no report-only policy applied, so the projection means nothing' {
            # Identical worlds because nothing was piloted is a different fact from identical
            # worlds because the pilot is harmless, and a reader has to be able to tell them apart
            $script:Vacuous.ReportOnlyApplying | Should-Be 0
        }

        It 'still reports what the sign-in has to satisfy today' {
            $script:Vacuous.Current.Access | Should-Be 'GrantedWithControls'
            $script:Vacuous.Current.RequiredControls |
                Should-BeCollection @('authenticationStrength:Passwordless MFA')
        }
    }

    Context 'a blocked, risky sign-in with several policies stacked' {

        BeforeAll {
            $script:Geo = Get-Outcome -Name 'blocked-by-geo-with-risk'
        }

        It 'is blocked by the geo policy' {
            $script:Geo.Current.Access | Should-Be 'Blocked'
            @($script:Geo.Current.BlockedBy)[0].PolicyName | Should-Be 'BLOCK - All Geo IPs Except US'
        }

        It 'still gathers the requirements the other applying policies impose' {
            # Recorded even though block ends the evaluation, because they are what the user
            # would face if the block were lifted
            $script:Geo.Current.RequiredControls | Should-ContainCollection 'passwordChange'
        }

        It 'counts every policy in the tenant, not only the applying ones' {
            $script:Geo.PolicyCount | Should-Be 13
        }
    }

    Context 'shapes the first six fixtures never produced' {
        <#
            These two were captured after building policies in the lab tenant that the first
            six fixtures had no equivalent of. Until then a multi-control OR clause, an
            unresolved session conflict and a custom authentication strength were asserted
            only against objects built by hand in the unit tests - which proves the fold reads
            what this module writes, not what Graph sends.
        #>

        BeforeAll {
            $script:Rich = Get-Outcome -Name 'or-clause-and-custom-strength'
            $script:Legacy = Get-Outcome -Name 'legacy-client-defeats-everything'
        }

        It 'keeps a real multi-control OR clause whole' {
            $choice = @($script:Rich.Projected.OptionalChoices)
            @($choice).Count | Should-Be 1
            $choice[0].PolicyName | Should-Be 'DEMO - MFA or compliant device'
            $choice[0].AnyOf | Should-BeCollection @('mfa', 'compliantDevice')

            # Kept whole rather than flattened, asserted on the clause itself. Absence
            # from RequiredControls cannot be asserted here: compliantDevice legitimately
            # arrives in that list from a different policy that requires it outright,
            # which is the kind of overlap a naive "is it absent" check gets wrong.
            $clause = @($script:Rich.Projected.Requirements |
                Where-Object PolicyName -eq 'DEMO - MFA or compliant device')

            @($clause).Count | Should-Be 1
            $clause[0].Operator | Should-Be 'OR'
            @($clause[0].Controls).Count | Should-Be 2
        }

        It 'reports a real unresolved session conflict without picking a side' {
            $conflict = @($script:Rich.Projected.SessionConflicts |
                Where-Object Control -eq 'cloudAppSecurity')

            @($conflict).Count | Should-Be 1
            $conflict[0].Resolved | Should-BeFalse
            $conflict[0].Values | Should-BeCollection @('blockDownloads', 'monitorOnly')
        }

        It 'reads a real custom authentication strength, combinations and all' {
            $custom = @($script:Rich.Projected.AuthenticationStrengths |
                Where-Object PolicyType -eq 'custom')

            @($custom).Count | Should-Be 1
            $custom[0].DisplayName | Should-Be 'DEMO - Contoso strong'
            $custom[0].AllowedCombinations | Should-BeCollection @(
                'fido2', 'windowsHelloForBusiness', 'x509CertificateMultiFactor')
        }

        It 'tells a device-state failure from an interactive one on the same sign-in' {
            # A legacy client defeats both kinds at once, and the two reasons must stay
            # distinct - one is about the client, the other about device state
            $unsat = @($script:Legacy.Projected.UnsatisfiableRequirements)
            @($unsat).Count | Should-BeGreaterThanOrEqual 3

            $reasons = @($unsat | ForEach-Object { $_.Reasons }) | Select-Object -Unique
            $reasons | Should-ContainCollection `
                'a legacy authentication client cannot perform interactive authentication'
            $reasons | Should-ContainCollection `
                'a legacy authentication client passes no device state'
        }

        It 'folds a device trust mismatch on an otherwise compliant machine' {
            # azureAD joined satisfies compliance and not hybrid join, which is the whole
            # reason the trustType rule is separate from the isCompliant one
            $hybrid = @($script:Rich.Projected.UnsatisfiableRequirements |
                Where-Object PolicyName -like '*hybrid*')

            @($hybrid).Count | Should-Be 1
            $hybrid[0].Reasons | Should-ContainCollection `
                'the simulated device is azureAD joined, not hybrid joined'
        }
    }
}

Describe 'ConvertTo-CaOutcome input handling' -Tag 'Unit', 'Public' {

    BeforeAll {
        $script:Fixture = Get-Fixture -Name 'no-report-only-policy-applies'
        $script:Expected = (ConvertTo-CaOutcome -WhatIfResult $script:Fixture.whatIf).Current.RequiredControls
    }

    It 'accepts the OData envelope' {
        (ConvertTo-CaOutcome -WhatIfResult $script:Fixture.whatIf).Current.RequiredControls |
            Should-BeCollection $script:Expected
    }

    It 'accepts the already-unwrapped collection, as Maester hands it back' {
        (ConvertTo-CaOutcome -WhatIfResult $script:Fixture.whatIf.value).Current.RequiredControls |
            Should-BeCollection $script:Expected
    }

    It 'accepts a raw JSON string, as Invoke-MgGraphRequest -OutputType Json hands it back' {
        $json = $script:Fixture.whatIf | ConvertTo-Json -Depth 20
        (ConvertTo-CaOutcome -WhatIfResult $json).Current.RequiredControls |
            Should-BeCollection $script:Expected
    }

    It 'accepts input from the pipeline' {
        ($script:Fixture.whatIf | ConvertTo-CaOutcome).Current.RequiredControls |
            Should-BeCollection $script:Expected
    }

    It 'warns rather than throwing on an empty response' {
        $warnings = @()
        $outcome = ConvertTo-CaOutcome -WhatIfResult @() -WarningVariable warnings -WarningAction SilentlyContinue
        $outcome.PolicyCount | Should-Be 0
        $outcome.Current.Access | Should-Be 'Granted'
        @($warnings).Count | Should-BeGreaterThan 0
    }

    It 'collapses the delta when both worlds are given the same states' {
        # The escape hatch for a tenant with no report-only policies, where a projection would
        # be meaningless rather than merely empty
        $outcome = ConvertTo-CaOutcome -WhatIfResult $script:Fixture.whatIf `
            -BaselineState 'enabled' -CandidateState 'enabled'
        $outcome.Delta.HasChange | Should-BeFalse
    }
}