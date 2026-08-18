#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The matrix run, driven through the request handler seam so no tenant is involved.

    That seam is the reason this suite can exist at all, and it is worth being explicit about
    what it buys: the module ships no Graph dependency, its tests run on a bare host, and the
    same parameter that makes the tests possible is what lets a caller replay recorded responses
    or route through their own transport.

    The behaviour under test that is easiest to get wrong is what happens to a scenario that
    fails. Dropping it would be the natural implementation and is quietly destructive: a
    baseline written from that run records the scenario as absent, and the next comparison
    reports it as removed - a real-looking change manufactured by a transient HTTP error. So a
    failure comes back as an object with Failed set, and the run carries on.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
    $script:FixtureRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures'

    function global:Get-FixtureJson {
        param([string]$Name)
        $fixture = Get-Content (Join-Path $script:FixtureRoot "$Name.json") -Raw | ConvertFrom-Json
        $fixture.whatIf | ConvertTo-Json -Depth 20
    }

    function global:New-TestScenario {
        param([string]$Name, [hashtable]$Conditions = @{ devicePlatform = 'windows' })
        [PSCustomObject]@{
            PSTypeName = 'CaOutcome.Scenario'
            Name = $Name; PersonaName = 'p'; UserId = 'u1'
            ResourceName = 'r'; ApplicationId = '00000003-0000-0ff1-ce00-000000000000'
            UserAction = $null; AuthenticationContext = $null
            ConditionName = 'c'; Conditions = $Conditions
        }
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-FixtureJson' -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-TestScenario' -ErrorAction SilentlyContinue
}

Describe 'Invoke-CaScenarioMatrix' -Tag 'Unit', 'Public' {

    It 'folds each scenario into an outcome carrying its name' {
        $handler = { Get-FixtureJson -Name 'no-report-only-policy-applies' }

        $outcomes = @(New-TestScenario -Name 'a'), (New-TestScenario -Name 'b') |
            Invoke-CaScenarioMatrix -RequestHandler $handler

        @($outcomes).Count | Should-Be 2
        @($outcomes)[0].Scenario | Should-Be 'a'
        @($outcomes)[1].Scenario | Should-Be 'b'
        @($outcomes)[0].Current.Access | Should-Be 'GrantedWithControls'
    }

    It 'passes the scenario conditions through, so satisfiability is judged' {
        # Without this the run reports "now requires compliantDevice" for a device the scenario
        # itself declared non-compliant, understating a lockout as a mild extra requirement
        # The handler is called as & $handler $body $uri, so a block with no param() simply
        # ignores both arguments
        $handler = { Get-FixtureJson -Name 'promotion-locks-out-noncompliant-device' }

        $scenario = New-TestScenario -Name 'unmanaged' -Conditions @{
            devicePlatform = 'windows'; deviceInfo = @{ isCompliant = $false }
        }

        ($scenario | Invoke-CaScenarioMatrix -RequestHandler $handler).Delta.BecomesEffectivelyBlocked |
            Should-BeTrue
    }

    It 'marks a failed scenario rather than dropping it, and keeps going' {
        $handler = {
            param($Body)
            if ($Body.signInIdentity.userId -eq 'boom') { throw 'The property is invalid' }
            Get-FixtureJson -Name 'no-report-only-policy-applies'
        }

        $bad = New-TestScenario -Name 'bad'
        $bad.UserId = 'boom'

        $outcomes = @((New-TestScenario -Name 'good'), $bad, (New-TestScenario -Name 'good2') |
            Invoke-CaScenarioMatrix -RequestHandler $handler -ErrorAction SilentlyContinue)

        @($outcomes).Count | Should-Be 3
        @($outcomes | Where-Object Failed).Count | Should-Be 1
        @($outcomes | Where-Object Failed)[0].Scenario | Should-Be 'bad'
        @($outcomes | Where-Object Failed)[0].Error | Should-MatchString 'invalid'
    }

    It 'marks a successful scenario as not failed, so the property is always there' {
        $handler = { Get-FixtureJson -Name 'no-report-only-policy-applies' }
        $outcome = New-TestScenario -Name 'a' | Invoke-CaScenarioMatrix -RequestHandler $handler

        $outcome.Failed | Should-BeFalse
        $outcome.Error | Should-BeNull
    }

    It 'writes an error as well, so an interactive run is not silently short' {
        $handler = { throw 'The property is invalid' }
        $errors = @()

        $null = New-TestScenario -Name 'bad' |
            Invoke-CaScenarioMatrix -RequestHandler $handler -ErrorVariable errors `
                -ErrorAction SilentlyContinue

        @($errors).Count | Should-BeGreaterThan 0
    }

    It 'paces the run when asked to' {
        # The endpoint publishes no throttling limits, so -DelayMillisecond is how a large
        # matrix avoids discovering one. It must not pause before the first scenario.
        $handler = { Get-FixtureJson -Name 'no-report-only-policy-applies' }
        $scenarios = @(1..3 | ForEach-Object { New-TestScenario -Name "s$_" })

        $elapsed = Measure-Command {
            $null = $scenarios | Invoke-CaScenarioMatrix -RequestHandler $handler -DelayMillisecond 300
        }

        # Two gaps between three scenarios, not three
        $elapsed.TotalMilliseconds | Should-BeGreaterThan 500
        $elapsed.TotalMilliseconds | Should-BeLessThan 2500
    }

    It 'sends one request per scenario' {
        $script:sent = 0
        $handler = {
            $script:sent++
            Get-FixtureJson -Name 'no-report-only-policy-applies'
        }

        $null = 1..4 | ForEach-Object { New-TestScenario -Name "s$_" } |
            Invoke-CaScenarioMatrix -RequestHandler $handler

        $script:sent | Should-Be 4
    }
}
