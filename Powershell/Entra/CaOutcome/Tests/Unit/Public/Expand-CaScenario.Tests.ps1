#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Matrix expansion, and the guards around it.

    The one that matters most is the scenario limit, and specifically that it throws rather than
    truncating. Every axis multiplies, so a matrix is one careless addition away from being ten
    times the size its author had in mind, and each scenario is an API call against an endpoint
    whose throttling limits are not published. A silently shortened run is the worst outcome
    available: it reports a clean result over a fraction of what was asked for, and nothing in
    the output says so.

    The condition translation is a rule rather than a lookup table, which is tested here
    directly, because the alternative fails silently. A table would drop any property Microsoft
    adds to signInConditions, and dropping a condition does not error - it evaluates a different
    sign-in from the one that was asked for and returns a confident answer about it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force

    $script:App = '00000003-0000-0ff1-ce00-000000000000'

    function global:New-TestMatrix {
        param([int]$PersonaCount = 1, [int]$ResourceCount = 1, [int]$ConditionCount = 1)
        @{
            Personas = @(1..$PersonaCount | ForEach-Object {
                @{ Name = "persona$_"; UserId = "1111111$_-1111-1111-1111-111111111111" } })
            Resources = @(1..$ResourceCount | ForEach-Object {
                @{ Name = "resource$_"; ApplicationId = '00000003-0000-0ff1-ce00-000000000000' } })
            Conditions = @(1..$ConditionCount | ForEach-Object {
                @{ Name = "condition$_"; DevicePlatform = 'windows' } })
        }
    }
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-TestMatrix' -ErrorAction SilentlyContinue
}

Describe 'Expand-CaScenario' -Tag 'Unit', 'Public' {

    Context 'the cartesian product' {

        It 'produces every combination of the three axes' {
            @(Expand-CaScenario -Matrix (New-TestMatrix -PersonaCount 2 -ResourceCount 3 `
                -ConditionCount 4)).Count | Should-Be 24
        }

        It 'names a scenario from all three axes so the name identifies it' {
            $scenarios = @(Expand-CaScenario -Matrix (New-TestMatrix -ConditionCount 2))
            $scenarios[0].Name | Should-Be 'persona1/resource1/condition1'
            $scenarios[1].Name | Should-Be 'persona1/resource1/condition2'
        }

        It 'carries the axis values onto each scenario' {
            $scenario = @(Expand-CaScenario -Matrix (New-TestMatrix))[0]
            $scenario.PersonaName | Should-Be 'persona1'
            $scenario.ResourceName | Should-Be 'resource1'
            $scenario.ConditionName | Should-Be 'condition1'
            $scenario.ApplicationId | Should-Be $script:App
        }
    }

    Context 'the scenario limit' {

        It 'throws rather than truncating when the matrix is larger than the limit' {
            # Truncating would report a clean run over a fraction of the matrix
            {
                Expand-CaScenario -Matrix (New-TestMatrix -PersonaCount 5 -ResourceCount 5 `
                    -ConditionCount 5) -MaxScenarioCount 10
            } | Should-Throw -ExceptionMessage '*125 scenarios*'
        }

        It 'allows a matrix that exactly meets the limit' {
            @(Expand-CaScenario -Matrix (New-TestMatrix -PersonaCount 2 -ConditionCount 5) `
                -MaxScenarioCount 10).Count | Should-Be 10
        }

        It 'defaults to a limit that catches a runaway matrix' {
            {
                Expand-CaScenario -Matrix (New-TestMatrix -PersonaCount 10 -ResourceCount 10 `
                    -ConditionCount 10)
            } | Should-Throw
        }
    }

    Context 'malformed matrices' {

        It 'refuses a matrix missing an axis' {
            { Expand-CaScenario -Matrix @{ Personas = @(@{ Name = 'a'; UserId = 'x' }) } } |
                Should-Throw -ExceptionMessage '*Resources*'
        }

        It 'refuses a persona with no UserId' {
            $matrix = New-TestMatrix
            $matrix.Personas = @(@{ Name = 'nameless' })
            { Expand-CaScenario -Matrix $matrix } | Should-Throw -ExceptionMessage '*UserId*'
        }

        It 'refuses a resource that targets nothing' {
            $matrix = New-TestMatrix
            $matrix.Resources = @(@{ Name = 'empty' })
            { Expand-CaScenario -Matrix $matrix } | Should-Throw -ExceptionMessage '*exactly one*'
        }

        It 'refuses a resource that targets two things at once' {
            # applicationContext and userActionContext are different odata types; a resource
            # asking for both describes no request that can be sent
            $matrix = New-TestMatrix
            $matrix.Resources = @(@{ Name = 'both'; ApplicationId = $script:App
                                     UserAction = 'registerSecurityInformation' })
            { Expand-CaScenario -Matrix $matrix } | Should-Throw -ExceptionMessage '*exactly one*'
        }
    }

    Context 'condition translation' {

        It 'lowercases the first letter to match the API' {
            $matrix = New-TestMatrix
            $matrix.Conditions = @(@{
                Name = 'c'; DevicePlatform = 'iOS'; ClientAppType = 'browser'
                SignInRiskLevel = 'high'; Country = 'US'
            })

            $conditions = @(Expand-CaScenario -Matrix $matrix)[0].Conditions
            $conditions['devicePlatform'] | Should-Be 'iOS'
            $conditions['clientAppType'] | Should-Be 'browser'
            $conditions['signInRiskLevel'] | Should-Be 'high'
            $conditions['country'] | Should-Be 'US'
        }

        It 'drops Name, which labels the row and is not part of the sign-in' {
            $conditions = @(Expand-CaScenario -Matrix (New-TestMatrix))[0].Conditions
            $conditions.ContainsKey('name') | Should-BeFalse
            $conditions.ContainsKey('Name') | Should-BeFalse
        }

        It 'passes nested objects through untouched' {
            $matrix = New-TestMatrix
            $matrix.Conditions = @(@{
                Name = 'c'; DeviceInfo = @{ isCompliant = $false; trustType = 'azureAD' }
            })

            $device = @(Expand-CaScenario -Matrix $matrix)[0].Conditions['deviceInfo']
            $device['isCompliant'] | Should-BeFalse
            $device['trustType'] | Should-Be 'azureAD'
        }

        It 'passes through a property this module has never heard of' {
            # The rule beats a lookup table: a signInConditions property Microsoft adds works
            # the day it ships, where a table would silently drop it
            $matrix = New-TestMatrix
            $matrix.Conditions = @(@{ Name = 'c'; SomeFutureCondition = 'value' })

            @(Expand-CaScenario -Matrix $matrix)[0].Conditions['someFutureCondition'] |
                Should-Be 'value'
        }

        It 'reads a matrix given as objects rather than hashtables' {
            $matrix = [PSCustomObject]@{
                Personas = @([PSCustomObject]@{ Name = 'p'; UserId = 'u' })
                Resources = @([PSCustomObject]@{ Name = 'r'; ApplicationId = $script:App })
                Conditions = @([PSCustomObject]@{ Name = 'c'; DevicePlatform = 'windows' })
            }

            @(Expand-CaScenario -Matrix $matrix)[0].Name | Should-Be 'p/r/c'
        }
    }
}
