#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The escalation rule, and the ruleset validation that keeps it honest.

    Escalation is what stops the report depending on the order of a data file. A single call
    routinely trips several rules - a for /f block reading a datetime property from a remote node
    is Wrapped, Semantic and Semantic again - so the finding takes the highest tier any of them
    named, where highest means hardest rather than most severe. First-match ordering would be
    simpler and would make the tier a function of where somebody happened to paste a rule.

    The validation tests matter for a subtler reason. The module's whole extensibility claim is
    that a new detection is a data change, and that is a claim about failure modes: a rule with a
    typo in its Match key does not throw, it just never fires, and the report comes back short by
    however many findings that rule was meant to catch. Nobody notices a report that is quietly
    smaller. So every way of getting the data file wrong has to be an error at load time.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force

    function global:New-TestRegion {
        param(
            [string]$Kind = 'Code',
            [string]$Structure = 'Line',
            [string]$Text = 'wmic os get caption',
            [string[]]$Context = @()
        )
        [PSCustomObject]@{
            Kind      = $Kind
            Structure = $Structure
            Text      = $Text
            Snippet   = $Text
            StartLine = 1
            EndLine   = 1
            Lines     = @(@{ Number = 1; Text = $Text })
            Detail    = @{ Context = $Context }
        }
    }
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-TestRegion' -ErrorAction SilentlyContinue
}

Describe 'Resolve-WmicTier' -Tag 'Unit', 'Private' {

    Context 'escalation' {

        It 'gives an unremarkable call the baseline tier' {
            InModuleScope WmicTriage {
                $region = New-TestRegion
                $call = @{
                    CommandText = 'wmic os get caption'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -RuleSet (Get-WmicRuleSet)

                $result.Tier | Should-Be 'Mechanical'
                $result.RuleId | Should-Be 'WMIC001'
            }
        }

        It 'takes the hardest tier when several rules match' {
            # A for /f block reading a datetime is both Wrapped and Semantic. Semantic wins,
            # because a judgment call outranks a restructure.
            InModuleScope WmicTriage {
                $region = New-TestRegion -Structure 'ForBlock'
                $call = @{
                    CommandText = 'wmic os get lastbootuptime'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -RuleSet (Get-WmicRuleSet)

                $result.Tier | Should-Be 'Semantic'
                @($result.RuleIds) | Should-ContainCollection @('WMIC100') -IgnoreOrder
                @($result.RuleIds) | Should-ContainCollection @('WMIC201') -IgnoreOrder
            }
        }

        It 'lets the environment outrank everything else' {
            InModuleScope WmicTriage {
                $region = New-TestRegion -Structure 'ForBlock'
                $call = @{
                    CommandText = 'wmic product get name'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -Context @('WinPE') -RuleSet (Get-WmicRuleSet)

                $result.Tier | Should-Be 'Environmental'
            }
        }

        It 'merges a region context with the file context' {
            # A task sequence spans both phases, so the WinPE marking is per step
            InModuleScope WmicTriage {
                $region = New-TestRegion -Structure 'TaskSequenceStep' -Context @('TaskSequenceWinPE')
                $call = @{
                    CommandText = 'wmic os get caption'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -Context @('TaskSequence') -RuleSet (Get-WmicRuleSet)

                $result.Tier | Should-Be 'Environmental'
            }
        }

        It 'keeps every rule that fired, not only the one that set the tier' {
            # "Semantic" alone does not say whether the problem is a datetime, an array or an MSI
            # consistency check
            InModuleScope WmicTriage {
                $region = New-TestRegion
                $call = @{
                    CommandText = 'wmic nicconfig where "IPEnabled=TRUE" get IPAddress'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -RuleSet (Get-WmicRuleSet)

                @($result.RuleIds).Count | Should-BeGreaterThan 2
            }
        }
    }

    Context 'security rules' {

        It 'returns a credential match separately from the tier' {
            # It has to survive a change that moves the WMIC call but leaves the password
            InModuleScope WmicTriage {
                $region = New-TestRegion
                $call = @{
                    CommandText = 'wmic /node:S1 /user:CONTOSO\svc /password:Secret os get caption'
                    Line = 1; Invocation = @('Literal'); Capture = @()
                }
                $detail = Get-WmicCommandDetail -CommandText $call.CommandText -RuleSet (Get-WmicRuleSet)

                $result = Resolve-WmicTier -Region $region -Invocation $call -Detail $detail `
                    -RuleSet (Get-WmicRuleSet)

                @($result.SecurityRule).Count | Should-Be 1
                $result.SecurityRule[0].Id | Should-Be 'WMIC900'
                $result.RuleId | Should-NotBe 'WMIC900'
            }
        }
    }

    Context 'ruleset validation' {

        BeforeEach {
            $script:Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $script:Work | Out-Null
        }

        AfterEach {
            Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'refuses a rule matching on a key the engine does not implement' {
            # It would never fire, and a report that is quietly short is worse than one that
            # will not start
            InModuleScope WmicTriage -Parameters @{ Work = $script:Work } {
                param($Work)
                $originalRoot = $script:ModuleRoot
                try {
                    New-Item -ItemType Directory -Path (Join-Path $Work 'Data') | Out-Null
                    Copy-Item (Join-Path $originalRoot 'Data\WmicAliases.psd1') (Join-Path $Work 'Data')
                    Copy-Item (Join-Path $originalRoot 'Data\WmicProperties.psd1') (Join-Path $Work 'Data')
                    $rules = @'
@{
    SchemaVersion = 1
    Rules = @(
        @{
            Id = 'TEST001'; Name = 'Typo'; Tier = 'Mechanical'
            Match = @{ Struckture = @('Line') }
            Reason = 'x'; Suggestion = 'y'
        }
    )
}
'@
                    Set-Content -Path (Join-Path $Work 'Data\WmicRules.psd1') -Value $rules
                    $script:ModuleRoot = $Work
                    { Get-WmicRuleSet -Force } | Should-Throw -ExceptionMessage '*Struckture*'
                }
                finally {
                    $script:ModuleRoot = $originalRoot
                    $null = Get-WmicRuleSet -Force
                }
            }
        }

        It 'refuses a rule naming a tier that does not exist' {
            InModuleScope WmicTriage -Parameters @{ Work = $script:Work } {
                param($Work)
                $originalRoot = $script:ModuleRoot
                try {
                    New-Item -ItemType Directory -Path (Join-Path $Work 'Data') | Out-Null
                    Copy-Item (Join-Path $originalRoot 'Data\WmicAliases.psd1') (Join-Path $Work 'Data')
                    Copy-Item (Join-Path $originalRoot 'Data\WmicProperties.psd1') (Join-Path $Work 'Data')
                    $rules = @'
@{
    SchemaVersion = 1
    Rules = @(
        @{
            Id = 'TEST001'; Name = 'Bad tier'; Tier = 'Catastrophic'
            Match = @{}
            Reason = 'x'; Suggestion = 'y'
        }
    )
}
'@
                    Set-Content -Path (Join-Path $Work 'Data\WmicRules.psd1') -Value $rules
                    $script:ModuleRoot = $Work
                    { Get-WmicRuleSet -Force } | Should-Throw -ExceptionMessage '*Catastrophic*'
                }
                finally {
                    $script:ModuleRoot = $originalRoot
                    $null = Get-WmicRuleSet -Force
                }
            }
        }

        It 'refuses two rules sharing an id' {
            # Ids appear in SARIF, where a duplicate makes two findings indistinguishable
            InModuleScope WmicTriage -Parameters @{ Work = $script:Work } {
                param($Work)
                $originalRoot = $script:ModuleRoot
                try {
                    New-Item -ItemType Directory -Path (Join-Path $Work 'Data') | Out-Null
                    Copy-Item (Join-Path $originalRoot 'Data\WmicAliases.psd1') (Join-Path $Work 'Data')
                    Copy-Item (Join-Path $originalRoot 'Data\WmicProperties.psd1') (Join-Path $Work 'Data')
                    $rules = @'
@{
    SchemaVersion = 1
    Rules = @(
        @{ Id = 'TEST001'; Name = 'One'; Match = @{}; Reason = 'x'; Suggestion = 'y' }
        @{ Id = 'TEST001'; Name = 'Two'; Match = @{}; Reason = 'x'; Suggestion = 'y' }
    )
}
'@
                    Set-Content -Path (Join-Path $Work 'Data\WmicRules.psd1') -Value $rules
                    $script:ModuleRoot = $Work
                    { Get-WmicRuleSet -Force } | Should-Throw -ExceptionMessage '*twice*'
                }
                finally {
                    $script:ModuleRoot = $originalRoot
                    $null = Get-WmicRuleSet -Force
                }
            }
        }

        It 'refuses a rule referencing a property group that does not exist' {
            InModuleScope WmicTriage -Parameters @{ Work = $script:Work } {
                param($Work)
                $originalRoot = $script:ModuleRoot
                try {
                    New-Item -ItemType Directory -Path (Join-Path $Work 'Data') | Out-Null
                    Copy-Item (Join-Path $originalRoot 'Data\WmicAliases.psd1') (Join-Path $Work 'Data')
                    Copy-Item (Join-Path $originalRoot 'Data\WmicProperties.psd1') (Join-Path $Work 'Data')
                    $rules = @'
@{
    SchemaVersion = 1
    Rules = @(
        @{
            Id = 'TEST001'; Name = 'Ghost group'; Tier = 'Semantic'
            Match = @{ PropertyGroup = @('Imaginary') }
            Reason = 'x'; Suggestion = 'y'
        }
    )
}
'@
                    Set-Content -Path (Join-Path $Work 'Data\WmicRules.psd1') -Value $rules
                    $script:ModuleRoot = $Work
                    { Get-WmicRuleSet -Force } | Should-Throw -ExceptionMessage '*Imaginary*'
                }
                finally {
                    $script:ModuleRoot = $originalRoot
                    $null = Get-WmicRuleSet -Force
                }
            }
        }
    }
}
