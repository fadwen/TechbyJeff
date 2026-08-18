#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The input normaliser, which exists because the same evaluation arrives in four different
    shapes depending on who fetched it.

    These were added after a coverage run showed the function at 52 percent - the envelope and
    JSON paths were exercised end to end through ConvertTo-CaOutcome, and everything else was
    not. The untested branches were not trivia: the hashtable envelope is what
    Invoke-MgGraphRequest returns under -OutputType Hashtable, and a wrong answer there is
    silent. An unrecognised shape does not throw, it folds to an outcome saying no policy
    applies, which reads exactly like a tenant with no Conditional Access.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'CaOutcome.psd1') -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-CaWhatIfResponse' -Tag 'Unit', 'Private' {

    Context 'the shapes Graph and Maester actually return' {

        It 'unwraps a PSObject envelope' {
            InModuleScope CaOutcome {
                $envelope = [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) }

                @(ConvertFrom-CaWhatIfResponse -InputObject $envelope).Count | Should-Be 2
            }
        }

        It 'unwraps a hashtable envelope, as -OutputType Hashtable returns' {
            # A PSObject and a hashtable are not interchangeable in PowerShell, and getting
            # this wrong is silent: the fold reports no policy applying, which reads like a
            # tenant with no Conditional Access at all
            InModuleScope CaOutcome {
                $envelope = @{ value = @(@{ id = 'a' }, @{ id = 'b' }, @{ id = 'c' }) }

                @(ConvertFrom-CaWhatIfResponse -InputObject $envelope).Count | Should-Be 3
            }
        }

        It 'passes through an already-unwrapped collection' {
            InModuleScope CaOutcome {
                $results = @([PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' })

                @(ConvertFrom-CaWhatIfResponse -InputObject $results).Count | Should-Be 2
            }
        }

        It 'parses a JSON string' {
            InModuleScope CaOutcome {
                $json = '{"value":[{"id":"a"},{"id":"b"}]}'

                @(ConvertFrom-CaWhatIfResponse -InputObject $json).Count | Should-Be 2
            }
        }

        It 'unwraps an envelope that arrived wrapped in a single-element array' {
            # What a caller produces by splatting or by piping the envelope into @()
            InModuleScope CaOutcome {
                $wrapped = @([PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) })

                @(ConvertFrom-CaWhatIfResponse -InputObject $wrapped).Count | Should-Be 2
            }
        }

        It 'unwraps a single-element array holding a hashtable envelope' {
            InModuleScope CaOutcome {
                $wrapped = @(@{ value = @(@{ id = 'a' }) })

                @(ConvertFrom-CaWhatIfResponse -InputObject $wrapped).Count | Should-Be 1
            }
        }

        It 'treats a lone policy result as a collection of one' {
            InModuleScope CaOutcome {
                $single = [PSCustomObject]@{ id = 'a'; policyApplies = $true }

                $result = @(ConvertFrom-CaWhatIfResponse -InputObject $single)
                $result.Count | Should-Be 1
                $result[0].id | Should-Be 'a'
            }
        }
    }

    Context 'nothing to fold' {

        It 'returns an empty collection for null' {
            InModuleScope CaOutcome {
                @(ConvertFrom-CaWhatIfResponse -InputObject $null).Count | Should-Be 0
            }
        }

        It 'returns an empty collection for an empty or whitespace string' {
            InModuleScope CaOutcome {
                @(ConvertFrom-CaWhatIfResponse -InputObject '').Count | Should-Be 0
                @(ConvertFrom-CaWhatIfResponse -InputObject "   `t ").Count | Should-Be 0
            }
        }

        It 'returns an empty collection for an envelope with no results' {
            InModuleScope CaOutcome {
                @(ConvertFrom-CaWhatIfResponse -InputObject ([PSCustomObject]@{ value = @() })).Count |
                    Should-Be 0
            }
        }
    }

    Context 'input that cannot be read' {

        It 'throws a message naming the problem when a string is not JSON' {
            # Silence here would be worse than the throw: an unparseable response folds to an
            # outcome that says every policy is inapplicable, and looks entirely plausible
            InModuleScope CaOutcome {
                { ConvertFrom-CaWhatIfResponse -InputObject 'not json at all {' } |
                    Should-Throw -ExceptionMessage '*not valid JSON*'
            }
        }
    }
}
