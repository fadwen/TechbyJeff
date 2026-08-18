#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Drift detection against a recorded baseline.

    The first test is the load bearing one: export a baseline, compare the same outcomes back
    against it, and every scenario must read Unchanged. That is the round trip through
    serialisation, and it is where a baseline quietly rots - a field the writer stores and the
    reader does not rehydrate shows up as drift on the very next run, and a tool that cries wolf
    on an unchanged tenant is a tool that gets switched off in a week.

    The second thing pinned here is that Missing is not Removed. A scenario in the baseline with
    no fresh outcome is almost always a failed evaluation rather than a deliberate change to the
    matrix, and if those two look the same then a transient HTTP error reads as a policy change.

    Both worlds are compared, and the distinction earns its keep: Current drift means what the
    tenant enforces has moved, Projected drift means the pilot's blast radius has moved. The
    second happens without anyone touching the pilot, because the population it would hit is not
    fixed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
    $script:FixtureRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures'

    function global:Get-TestOutcome {
        param([string]$Fixture, [string]$Name, [switch]$Failed)
        if ($Failed) {
            return [PSCustomObject]@{
                PSTypeName = 'CaOutcome.Result'; Scenario = $Name
                Current = $null; Projected = $null; Delta = $null
                PolicyCount = 0; ReportOnlyApplying = 0
                Failed = $true; Error = 'throttled after 4 retries'
            }
        }

        # Not $fixture: the parameter above is [string]$Fixture, PowerShell is case-insensitive,
        # and assigning an object to a string-typed variable silently stringifies it
        $data = Get-Content (Join-Path $script:FixtureRoot "$Fixture.json") -Raw | ConvertFrom-Json
        $outcome = ConvertTo-CaOutcome -WhatIfResult $data.whatIf `
            -SignInCondition $data.signInConditions -ScenarioName $Name
        $outcome | Add-Member -NotePropertyName Failed -NotePropertyValue $false
        $outcome | Add-Member -NotePropertyName Error -NotePropertyValue $null
        $outcome
    }

    # An outcome carrying a blocker and a multi-option choice - the two requirement shapes the
    # captured fixtures happen not to produce
    function global:Get-TestEffectiveControl {
        [PSCustomObject]@{
            PSTypeName = 'CaOutcome.EffectiveControl'
            World = 'Current'; Access = 'Blocked'
            BlockedBy = @([PSCustomObject]@{ PolicyId = 'b1'; PolicyName = 'BLOCK - Legacy' })
            RequiredControls = @('mfa')
            OptionalChoices = @([PSCustomObject]@{
                PolicyId = 'p1'; PolicyName = 'MFA or compliant'
                AnyOf = @('mfa', 'compliantDevice')
            })
            UnsatisfiableRequirements = @()
            AuthenticationStrengths = @()
            IsEffectivelyBlocked = $true
            SessionControls = [PSCustomObject]@{}
            SessionConflicts = @()
            AppliedPolicies = @([PSCustomObject]@{ Id = 'p1'; DisplayName = 'P1'; State = 'enabled' })
        }
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-TestOutcome' -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-TestEffectiveControl' -ErrorAction SilentlyContinue
}

Describe 'Compare-CaBaseline' -Tag 'Unit', 'Public' {

    BeforeEach {
        $script:Approved = @(
            Get-TestOutcome -Fixture 'promotion-adds-satisfiable-requirement' -Name 'support/managed'
            Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'jeff/managed'
            Get-TestOutcome -Fixture 'session-control-conflict' -Name 'support/unmanaged'
        )
        $script:Baseline = $script:Approved | Export-CaBaseline
    }

    Context 'the round trip' {

        It 'reports every scenario unchanged when nothing has moved' {
            # A field stored by the writer and not rehydrated by the reader shows up as drift
            # on the very next run. This is the test that catches it.
            $drift = @($script:Approved | Compare-CaBaseline -Baseline $script:Baseline)

            @($drift).Count | Should-Be 3
            @($drift | Where-Object HasChange).Count | Should-Be 0
            @($drift | Where-Object { $_.Status -ne 'Unchanged' }).Count | Should-Be 0
        }

        It 'carries authentication strength combinations through the round trip' {
            <#
                The regression this exists for: strengths are stored by the writer and have to
                be rehydrated by the reader. If they are not, a run against an unchanged tenant
                reports every scenario using a strength as drifted, and a tool that cries wolf
                on an unchanged tenant is switched off within a week.
            #>
            $strengths = @($script:Baseline.scenarios.Values |
                ForEach-Object { $_.current.strengths } | Where-Object { $_ })

            @($strengths).Count | Should-BeGreaterThan 0
            @($strengths)[0].allowedCombinations.Count | Should-BeGreaterThan 0
        }

        It 'carries a multi-option OR clause through the round trip' {
            <#
                An OptionalChoice is the one requirement shape that cannot be flattened to a
                string, so it is stored and rehydrated by a different path from everything
                else. Untested, a tenant whose policies offer "MFA or a compliant device"
                would report drift on every run against an unchanged tenant.
            #>
            $withChoice = [PSCustomObject]@{
                PSTypeName = 'CaOutcome.Result'; Scenario = 'choice/managed'
                PolicyCount = 1; ReportOnlyApplying = 0; Failed = $false; Error = $null
                Delta = $null
                Current = Get-TestEffectiveControl
                Projected = Get-TestEffectiveControl
            }

            $baseline = @($withChoice) | Export-CaBaseline
            $drift = @(@($withChoice) | Compare-CaBaseline -Baseline $baseline)

            @($drift).Count | Should-Be 1
            @($drift)[0].Status | Should-Be 'Unchanged'
            $baseline.scenarios['choice/managed'].current.optionalChoices[0].anyOf |
                Should-BeCollection @('compliantDevice', 'mfa')
        }

        It 'survives the journey through a file' {
            $path = Join-Path ([IO.Path]::GetTempPath()) "$([guid]::NewGuid().ToString('n')).json"
            try {
                $script:Approved | Export-CaBaseline -Path $path
                $drift = @($script:Approved | Compare-CaBaseline -Path $path)

                @($drift | Where-Object HasChange).Count | Should-Be 0
            } finally {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'real drift' {

        It 'reports a scenario whose outcome has moved' {
            $drifted = @(
                Get-TestOutcome -Fixture 'promotion-locks-out-noncompliant-device' -Name 'support/managed'
                Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'jeff/managed'
                Get-TestOutcome -Fixture 'session-control-conflict' -Name 'support/unmanaged'
            )

            $drift = @($drifted | Compare-CaBaseline -Baseline $script:Baseline)
            $changed = @($drift | Where-Object { $_.Status -eq 'Changed' })

            @($changed).Count | Should-Be 1
            @($changed)[0].Scenario | Should-Be 'support/managed'
            @($changed)[0].HasChange | Should-BeTrue
        }

        It 'separates drift in what is enforced from drift in the pilot blast radius' {
            $drifted = @(
                Get-TestOutcome -Fixture 'promotion-locks-out-noncompliant-device' -Name 'support/managed'
            )

            $entry = @($drifted | Compare-CaBaseline -Baseline $script:Baseline |
                Where-Object Scenario -eq 'support/managed')[0]

            $entry.CurrentDelta | Should-NotBeNull
            $entry.ProjectedDelta | Should-NotBeNull
            $entry.ProjectedDelta.BecomesEffectivelyBlocked | Should-BeTrue
        }

        It 'says which world moved in the summary' {
            $drifted = @(
                Get-TestOutcome -Fixture 'promotion-locks-out-noncompliant-device' -Name 'support/managed'
            )

            $entry = @($drifted | Compare-CaBaseline -Baseline $script:Baseline |
                Where-Object Scenario -eq 'support/managed')[0]

            $entry.Summary | Should-MatchString 'after promotion'
        }
    }

    Context 'scenarios present on only one side' {

        It 'reports a scenario absent from the baseline as added' {
            $extra = @(Get-TestOutcome -Fixture 'blocked-by-geo-with-risk' -Name 'contractor/de')
            $drift = @($extra | Compare-CaBaseline -Baseline $script:Baseline)

            @($drift | Where-Object { $_.Status -eq 'Added' })[0].Scenario | Should-Be 'contractor/de'
        }

        It 'reports a scenario absent from the run as missing, not as removed' {
            # The usual cause is a failed evaluation. If this read as a removal, a transient
            # HTTP error would look like somebody deleting a policy.
            $partial = @($script:Approved | Select-Object -First 1)
            $drift = @($partial | Compare-CaBaseline -Baseline $script:Baseline)

            $missing = @($drift | Where-Object { $_.Status -eq 'Missing' })
            @($missing).Count | Should-Be 2
            @($missing)[0].Summary | Should-MatchString 'failed evaluation'
        }

        It 'reports a failed scenario as failed rather than as changed' {
            $withFailure = @(
                Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'jeff/managed'
                Get-TestOutcome -Name 'support/managed' -Failed
                Get-TestOutcome -Fixture 'session-control-conflict' -Name 'support/unmanaged'
            )

            $drift = @($withFailure | Compare-CaBaseline -Baseline $script:Baseline)
            $failed = @($drift | Where-Object { $_.Status -eq 'Failed' })

            @($failed).Count | Should-Be 1
            @($failed)[0].Scenario | Should-Be 'support/managed'
            @($failed)[0].HasChange | Should-BeFalse
            @($failed)[0].Summary | Should-MatchString 'throttled'
        }
    }

    Context 'bad input' {

        It 'throws on a baseline path that does not exist' {
            { $script:Approved | Compare-CaBaseline -Path 'X:\nope\baseline.json' } |
                Should-Throw -ExceptionMessage '*No baseline*'
        }

        It 'throws on an object that is not a baseline' {
            { $script:Approved | Compare-CaBaseline -Baseline ([PSCustomObject]@{ other = 1 }) } |
                Should-Throw -ExceptionMessage '*scenarios*'
        }
    }
}
