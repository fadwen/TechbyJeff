#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The one path the unit tests cannot reach: the default request handler, which is this
    module's only contact with Microsoft.Graph.Authentication.

    Everything else here is a pure transform and is tested against captured fixtures with no
    tenant at all. That is deliberate, and it leaves exactly one thing unproven - that when no
    -RequestHandler is supplied, the handler this module builds actually reaches Graph and
    comes back with something the fold can read. Mocking that would only prove the mock works.

    So this suite talks to a real tenant, and skips itself when there is not one. The skip is
    evaluated during Pester's discovery pass and has to survive a host where the Graph SDK is
    not installed at all, which is why the connection check is wrapped rather than assumed:
    CI runs with no tenant and no SDK, and this file must discover cleanly there.

    Scope is checked as well as connection. A session connected for some other purpose would
    otherwise fail here for a reason that says nothing about this module - where a session that
    does hold the right scope and still fails is telling you something real.

    Nothing tenant-specific is asserted. The tenant this was written against has thirteen
    Conditional Access policies; a tenant with none is still a valid answer, so the assertions
    are about the shape of the response and the health of the round trip.

    Read-only: the evaluate endpoint is a POST that changes nothing. It is a read that happens
    to need a request body.
#>

# Discovery-time, and defensive. Get-MgContext may not exist; if it does it may throw.
$script:CanReachGraph = $false
try {
    if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) {
        $context = Get-MgContext
        if ($context) {
            $scopes = @($context.Scopes)
            $script:CanReachGraph = @('Policy.Read.All', 'Policy.Read.ConditionalAccess',
                'Policy.ReadWrite.ConditionalAccess') |
                Where-Object { $scopes -contains $_ } | Select-Object -First 1
            $script:CanReachGraph = [bool]$script:CanReachGraph
        }
    }
} catch {
    $script:CanReachGraph = $false
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force

    $script:Office365 = '00000003-0000-0ff1-ce00-000000000000'
    $script:TestUserId = $null

    # Recomputed rather than inherited: the value above was assigned during discovery, and a
    # discovery-scope variable is not guaranteed to survive into the run pass
    $script:CanReachGraph = $false
    try {
        if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) {
            $script:CanReachGraph = [bool](Get-MgContext)
        }
    } catch {
        $script:CanReachGraph = $false
    }

    if ($script:CanReachGraph) {
        # Discovered rather than hard coded: a user id in a shipped test file is one tenant's
        # and useless in every other
        $users = (Invoke-MgGraphRequest -Method GET -OutputType PSObject `
            -Uri 'https://graph.microsoft.com/v1.0/users?$select=id&$top=1').value
        $script:TestUserId = @($users)[0].id
    }

    # Get- rather than New-, because PSScriptAnalyzer treats New- as state changing and asks
    # for ShouldProcess. This builds an object in memory and changes nothing.
    function Get-LiveScenario {
        [PSCustomObject]@{
            PSTypeName    = 'CaOutcome.Scenario'
            Name          = 'integration/office365/unmanaged'
            PersonaName   = 'integration'
            UserId        = $script:TestUserId
            ResourceName  = 'office365'
            ApplicationId = $script:Office365
            UserAction    = $null
            AuthenticationContext = $null
            ConditionName = 'unmanaged'
            Conditions    = @{
                devicePlatform = 'windows'; clientAppType = 'browser'
                signInRiskLevel = 'low'; userRiskLevel = 'low'; country = 'US'
                deviceInfo = @{ isCompliant = $false }
            }
        }
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'CaOutcome default request handler' `
    -Tag 'Integration', 'RequiresTenant' -Skip:(-not $script:CanReachGraph) {

    # Fetched once for the whole Describe rather than inside a Context. Shuffle mode
    # proved why: a fixture built in one Context's BeforeAll and read from a sibling
    # Context passes or fails on whichever order Pester happens to pick, and over eight
    # shuffled runs it picked both.
    BeforeAll {
        # -Parameters, because InModuleScope runs in the module's session state and cannot
        # see the test file's variables
        $script:Raw = InModuleScope CaOutcome -Parameters @{ UserId = $script:TestUserId } {
            param($UserId)
            $scenario = [PSCustomObject]@{
                Name = 'integration'; UserId = $UserId
                ApplicationId = '00000003-0000-0ff1-ce00-000000000000'
                Conditions = @{
                    devicePlatform = 'windows'; clientAppType = 'browser'
                    deviceInfo = @{ isCompliant = $false }
                }
            }
            # No -RequestHandler: this is the whole point of the file
            Invoke-CaEvaluateRequest -Body (ConvertTo-CaEvaluateBody -Scenario $scenario)
        }
    }

    Context 'the handler this module builds when the caller supplies none' {

        It 'has a user to evaluate' {
            $script:TestUserId | Should-NotBeWhiteSpaceString
        }

        It 'reaches Graph and returns JSON' {
            $script:Raw | Should-NotBeWhiteSpaceString
            $script:Raw | Should-HaveType ([string])
        }

        It 'returns a whatIfAnalysisResult collection the fold can read' {
            $parsed = $script:Raw | ConvertFrom-Json
            $parsed.PSObject.Properties['value'] | Should-NotBeNull

            # Every policy in the tenant, not only the applying ones - appliedPoliciesOnly is
            # pinned to false, and the projection is meaningless without that
            @($parsed.value) | ForEach-Object { $_.PSObject.Properties['state'] | Should-NotBeNull }
        }
    }

    Context 'the whole pipeline with no request handler supplied' {

        It 'folds a live evaluation into an outcome' {
            $outcome = Get-LiveScenario | Invoke-CaScenarioMatrix

            $outcome.Failed | Should-BeFalse
            $outcome.Error | Should-BeNull
            $outcome.Scenario | Should-Be 'integration/office365/unmanaged'
            $outcome.Current | Should-NotBeNull
            $outcome.Projected | Should-NotBeNull
            $outcome.Delta | Should-NotBeNull
            @('Blocked', 'Granted', 'GrantedWithControls') |
                Should-ContainCollection $outcome.Current.Access
        }

        It 'agrees with the response it was folded from' {
            $outcome = Get-LiveScenario | Invoke-CaScenarioMatrix
            $direct = @(($script:Raw | ConvertFrom-Json).value).Count

            $outcome.PolicyCount | Should-Be $direct
        }

        It 'produces an outcome that survives a baseline round trip' {
            $outcome = Get-LiveScenario | Invoke-CaScenarioMatrix
            $baseline = @($outcome) | Export-CaBaseline
            $drift = @(@($outcome) | Compare-CaBaseline -Baseline $baseline)

            @($drift).Count | Should-Be 1
            @($drift)[0].Status | Should-Be 'Unchanged'
        }
    }
}
