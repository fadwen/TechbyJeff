#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Baseline writing, and the two properties that make a baseline worth committing.

    Determinism first. A baseline is a file in git, and the only thing that should ever appear in
    its diff is a changed outcome. Graph returns policies in no guaranteed order, so without
    imposed ordering the same tenant would produce a different file on every run, and a diff that
    changes every time is a diff nobody reads. The byte-identical test is the one that keeps that
    honest - it will fail the moment someone adds a timestamp or drops a sort.

    Completeness second. A run with a failed scenario must not quietly become a baseline missing
    that scenario, because the next comparison would report it as removed: a change invented by a
    transient HTTP error, in the one artefact whose entire value rests on its changes being real.
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
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-TestOutcome' -ErrorAction SilentlyContinue
}

Describe 'Export-CaBaseline' -Tag 'Unit', 'Public' {

    BeforeEach {
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:Path = Join-Path $script:Work 'baseline.json'

        $script:Outcomes = @(
            Get-TestOutcome -Fixture 'promotion-adds-satisfiable-requirement' -Name 'b/managed'
            Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'a/managed'
        )
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'determinism' {

        It 'writes a byte identical file for the same outcomes' {
            $second = Join-Path $script:Work 'again.json'
            $script:Outcomes | Export-CaBaseline -Path $script:Path
            $script:Outcomes | Export-CaBaseline -Path $second

            (Get-FileHash $script:Path).Hash | Should-Be (Get-FileHash $second).Hash
        }

        It 'is not sensitive to the order the outcomes arrive in' {
            # Otherwise a matrix that expands in a different order produces a spurious diff
            $second = Join-Path $script:Work 'reversed.json'
            $script:Outcomes | Export-CaBaseline -Path $script:Path
            @($script:Outcomes)[-1..0] | Export-CaBaseline -Path $second

            (Get-FileHash $script:Path).Hash | Should-Be (Get-FileHash $second).Hash
        }

        It 'writes no timestamp, so an unchanged run produces no diff' {
            $script:Outcomes | Export-CaBaseline -Path $script:Path
            $content = Get-Content $script:Path -Raw

            $content | Should-NotMatchString '(?i)generated|timestamp|dateTime'
        }
    }

    Context 'what gets stored' {

        It 'keys scenarios by name and records both worlds' {
            $baseline = $script:Outcomes | Export-CaBaseline

            $baseline.scenarios.Contains('a/managed') | Should-BeTrue
            $baseline.scenarios.Contains('b/managed') | Should-BeTrue
            $baseline.scenarios['b/managed'].current.access | Should-Be 'GrantedWithControls'
            $baseline.scenarios['b/managed'].projected.requiredControls |
                Should-ContainCollection 'compliantDevice'
        }

        It 'records how many report-only policies applied' {
            # Zero means the projection is vacuous, and a baseline that lost it would hide that
            $baseline = $script:Outcomes | Export-CaBaseline
            $baseline.scenarios['a/managed'].reportOnlyApplying | Should-Be 0
            $baseline.scenarios['b/managed'].reportOnlyApplying | Should-Be 1
        }

        It 'stamps a schema version, so a later format change is detectable' {
            ($script:Outcomes | Export-CaBaseline).schemaVersion | Should-Be 1
        }
    }

    Context 'refusing an incomplete baseline' {

        It 'throws when a scenario failed' {
            $withFailure = @($script:Outcomes) + @(Get-TestOutcome -Name 'c/ios' -Failed)

            { $withFailure | Export-CaBaseline -Path $script:Path } |
                Should-Throw -ExceptionMessage '*failed*'
            Test-Path $script:Path | Should-BeFalse
        }

        It 'writes a partial baseline under -Force, and warns about what is missing' {
            $withFailure = @($script:Outcomes) + @(Get-TestOutcome -Name 'c/ios' -Failed)
            $warnings = @()

            $withFailure | Export-CaBaseline -Path $script:Path -Force `
                -WarningVariable warnings -WarningAction SilentlyContinue

            Test-Path $script:Path | Should-BeTrue
            @($warnings).Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'c/ios'
        }

        It 'refuses an outcome with no scenario name, since the baseline is keyed by it' {
            $nameless = Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'x'
            $nameless.Scenario = ''

            { $nameless | Export-CaBaseline } | Should-Throw -ExceptionMessage '*Scenario name*'
        }

        It 'refuses two outcomes sharing a name' {
            $duplicate = @(
                Get-TestOutcome -Fixture 'no-report-only-policy-applies' -Name 'same'
                Get-TestOutcome -Fixture 'session-control-conflict' -Name 'same'
            )

            { $duplicate | Export-CaBaseline } | Should-Throw -ExceptionMessage '*unique*'
        }
    }

    Context 'the file' {

        It 'writes nothing under -WhatIf' {
            $script:Outcomes | Export-CaBaseline -Path $script:Path -WhatIf
            Test-Path $script:Path | Should-BeFalse
        }

        It 'returns the object rather than writing when no path is given' {
            $baseline = $script:Outcomes | Export-CaBaseline
            $baseline | Should-NotBeNull
            @(Get-ChildItem $script:Work).Count | Should-Be 0
        }

        It 'returns nothing when writing, unless PassThru is asked for' {
            ($script:Outcomes | Export-CaBaseline -Path $script:Path) | Should-BeNull
            ($script:Outcomes | Export-CaBaseline -Path $script:Path -PassThru) | Should-NotBeNull
        }

        It 'round trips through JSON' {
            $script:Outcomes | Export-CaBaseline -Path $script:Path
            $read = Get-Content $script:Path -Raw | ConvertFrom-Json

            $read.schemaVersion | Should-Be 1
            $read.scenarios.'a/managed'.current.access | Should-Be 'GrantedWithControls'
        }
    }
}
