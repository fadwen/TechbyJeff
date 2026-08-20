#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Reading what a WMIC command actually asks the system for.

    The Semantic tier is defined by what is being read rather than by how the call is shaped, so
    everything that tier detects arrives from this function. If it misses a property name, the
    finding silently drops a tier and a datetime that needed a human becomes a swap somebody
    scripts.

    Two parsing decisions carry most of the weight.

    Switches come out first, before anything positional is attempted, because WMIC accepts them
    almost anywhere. wmic /node:PC1 os get caption and wmic os get caption /format:csv are both
    ordinary, and a positional parser that assumed switches came first reads the alias of the
    second as nonsense.

    Where-clauses are removed before the verb search and then mined for property names. Removal
    first because a filter can contain a word that reads as a verb; mining second because a
    filter names properties as surely as a get does - where "DHCPEnabled=TRUE" is the Boolean
    problem exactly, and it never appears after a get.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WmicCommandDetail' -Tag 'Unit', 'Private' {

    Context 'aliases and classes' {

        It 'resolves the alias <Alias> to <Class>' -ForEach @(
            @{ Alias = 'bios'; Class = 'Win32_BIOS'; NonObvious = $false }
            @{ Alias = 'qfe'; Class = 'Win32_QuickFixEngineering'; NonObvious = $true }
            @{ Alias = 'nicconfig'; Class = 'Win32_NetworkAdapterConfiguration'; NonObvious = $true }
            @{ Alias = 'cpu'; Class = 'Win32_Processor'; NonObvious = $true }
        ) {
            InModuleScope WmicTriage -Parameters @{ Alias = $Alias; Class = $Class; NonObvious = $NonObvious } {
                param($Alias, $Class, $NonObvious)
                $detail = Get-WmicCommandDetail -CommandText "wmic $Alias get name" -RuleSet (Get-WmicRuleSet)

                $detail.Alias | Should-Be $Alias
                $detail.Class | Should-Be $Class
                $detail.NonObvious | Should-Be $NonObvious
            }
        }

        It 'reads the class out of a path expression' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic path win32_process get name' `
                    -RuleSet (Get-WmicRuleSet)
                $detail.Class | Should-Be 'win32_process'
            }
        }

        It 'strips the namespace from a fully qualified class' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic path \\.\root\cimv2:Win32_Service get state' `
                    -RuleSet (Get-WmicRuleSet)
                $detail.Class | Should-Be 'Win32_Service'
            }
        }

        It 'leaves the alias null when the command names nothing' {
            # Start-Process 'wmic.exe' with its arguments in a separate string. A wrong class name
            # in the report reads as a fact; a gap reads as a gap.
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic.exe' -RuleSet (Get-WmicRuleSet)
                $detail.Alias | Should-BeNull
                $detail.Class | Should-BeNull
            }
        }

        It 'skips a host-language parameter sitting in the alias position' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic -ArgumentList os get caption' `
                    -RuleSet (Get-WmicRuleSet)
                $detail.Alias | Should-Be 'os'
            }
        }
    }

    Context 'switches' {

        It 'finds a switch written before the alias' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic /node:SRV01 os get caption' `
                    -RuleSet (Get-WmicRuleSet)

                $detail.Node | Should-Be 'SRV01'
                $detail.Alias | Should-Be 'os'
                $detail.Verb | Should-Be 'get'
            }
        }

        It 'finds a switch written after the properties' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic os get caption /format:csv' `
                    -RuleSet (Get-WmicRuleSet)

                $detail.Alias | Should-Be 'os'
                @($detail.SwitchName) | Should-ContainCollection @('format')
            }
        }

        It 'records a valueless switch' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic os get caption /value' `
                    -RuleSet (Get-WmicRuleSet)
                @($detail.SwitchName) | Should-ContainCollection @('value')
            }
        }

        It 'keeps a credential switch so the security rule can fire' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail `
                    -CommandText 'wmic /node:S1 /user:CONTOSO\svc /password:Secret os get caption' `
                    -RuleSet (Get-WmicRuleSet)
                @($detail.SwitchName) | Should-ContainCollection @('password')
            }
        }
    }

    Context 'verbs and properties' {

        It 'splits a comma-separated get list' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic os get caption,version,installdate' `
                    -RuleSet (Get-WmicRuleSet)

                $detail.Verb | Should-Be 'get'
                @($detail.Properties) | Should-BeCollection @('caption', 'version', 'installdate')
            }
        }

        It 'reads the method name from a call' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic path win32_process call terminate' `
                    -RuleSet (Get-WmicRuleSet)

                $detail.Verb | Should-Be 'call'
                $detail.Method | Should-Be 'terminate'
            }
        }

        It 'reads the property name from a set, not its value' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic service set startmode=disabled' `
                    -RuleSet (Get-WmicRuleSet)

                $detail.Verb | Should-Be 'set'
                @($detail.Properties) | Should-BeCollection @('startmode')
            }
        }

        It 'does not mistake a list mode for a property name' {
            # list brief would otherwise put "brief" through the property group lookup
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic qfe list brief' -RuleSet (Get-WmicRuleSet)

                $detail.Verb | Should-Be 'list'
                @($detail.Properties).Count | Should-Be 0
            }
        }
    }

    Context 'where-clauses' {

        It 'captures the filter text' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic service where "name=''spooler''" get state' `
                    -RuleSet (Get-WmicRuleSet)
                $detail.Filter | Should-MatchString 'spooler'
            }
        }

        It 'mines property names out of the filter' {
            InModuleScope WmicTriage {
                $command = 'wmic nicconfig where "IPEnabled=TRUE" get IPAddress'
                $detail = Get-WmicCommandDetail -CommandText $command -RuleSet (Get-WmicRuleSet)

                @($detail.Properties) | Should-ContainCollection @('IPEnabled') -IgnoreOrder
                @($detail.PropertyGroup) | Should-ContainCollection @('Boolean') -IgnoreOrder
            }
        }

        It 'still finds the verb when the filter contains a word that reads as one' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic service where "name like ''%set%''" get state' `
                    -RuleSet (Get-WmicRuleSet)
                $detail.Verb | Should-Be 'get'
            }
        }
    }

    Context 'property groups' {

        It 'classifies <Property> as <Group>' -ForEach @(
            @{ Property = 'lastbootuptime'; Group = 'DateTime' }
            @{ Property = 'installdate'; Group = 'DateTime' }
            @{ Property = 'ipaddress'; Group = 'MultiValue' }
            @{ Property = 'dhcpenabled'; Group = 'Boolean' }
            @{ Property = 'systemuptime'; Group = 'Interval' }
        ) {
            InModuleScope WmicTriage -Parameters @{ Property = $Property; Group = $Group } {
                param($Property, $Group)
                $detail = Get-WmicCommandDetail -CommandText "wmic os get $Property" -RuleSet (Get-WmicRuleSet)
                @($detail.PropertyGroup) | Should-ContainCollection @($Group)
            }
        }

        It 'leaves an ordinary property in no group' {
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic os get caption' -RuleSet (Get-WmicRuleSet)
                @($detail.PropertyGroup).Count | Should-Be 0
            }
        }
    }

    Context 'input it cannot parse' {

        It 'returns a usable object for a bare invocation' {
            # A command that will not parse still deserves its baseline finding
            InModuleScope WmicTriage {
                $detail = Get-WmicCommandDetail -CommandText 'wmic' -RuleSet (Get-WmicRuleSet)
                $detail.Alias | Should-BeNull
                $detail.Verb | Should-BeNull
            }
        }
    }
}
