#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The tokenizer, one behavior per test. The scanner's correctness rests on these: a token
    kind that is wrong here becomes a wrong Level there.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'EntraMemberOf.psd1') -Force
}

AfterAll {
    Remove-Module EntraMemberOf -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-MembershipRuleToken' -Tag 'Unit', 'Private' {

    It 'tokenizes the documented memberOf rule into nine tokens' {
        InModuleScope EntraMemberOf {
            $tokens = @(ConvertTo-MembershipRuleToken -Rule "user.memberof -any (group.objectId -in ['a'])")
            $tokens.Kind | Should-BeCollection @('Word', 'Operator', 'OpenParen', 'Word', 'Operator',
                'OpenBracket', 'String', 'CloseBracket', 'CloseParen')
            $tokens[0].Text | Should-Be 'user.memberof'
            $tokens[1].Text | Should-Be 'any'
            $tokens[4].Text | Should-Be 'in'
            $tokens[6].Text | Should-Be 'a'
        }
    }

    It 'returns nothing for empty text' {
        InModuleScope EntraMemberOf {
            @(ConvertTo-MembershipRuleToken -Rule '').Count | Should-Be 0
            @(ConvertTo-MembershipRuleToken -Rule "   `n ").Count | Should-Be 0
        }
    }

    It 'records the index of every token' {
        InModuleScope EntraMemberOf {
            $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.a -eq "x"')
            $tokens.Index | Should-BeCollection @(0, 7, 11)
        }
    }

    Context 'strings' {

        It 'keeps a double-quoted string as one token with the quotes removed' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.department -eq "Sales and Marketing"')
                $tokens.Count | Should-Be 3
                $tokens[2].Kind | Should-Be 'String'
                $tokens[2].Text | Should-Be 'Sales and Marketing'
                $tokens[2].Raw | Should-Be '"Sales and Marketing"'
            }
        }

        It 'undoes the backtick escape inside a double-quoted string' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.displayName -eq "say `"hi`""')
                $tokens[2].Text | Should-Be 'say "hi"'
            }
        }

        It 'undoes the doubled quote inside a single-quoted string' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule "user.displayName -eq 'O''Brien'")
                $tokens[2].Text | Should-Be "O'Brien"
            }
        }

        It 'does not read operators or brackets inside a string' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x -eq "a -in [b] (c)"')
                $tokens.Count | Should-Be 3
                $tokens[2].Kind | Should-Be 'String'
            }
        }

        It 'marks an unclosed string as Unterminated' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x -eq "open')
                $tokens[2].Kind | Should-Be 'Unterminated'
                $tokens[2].Text | Should-Be 'open'
            }
        }
    }

    Context 'operators' {

        It 'returns a dashed operator by name, lower case, without the dash' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x -NotStartsWith "a"')
                $tokens[1].Kind | Should-Be 'Operator'
                $tokens[1].Text | Should-Be 'notstartswith'
                $tokens[1].Raw | Should-Be '-NotStartsWith'
            }
        }

        It 'accepts the en dash some Learn examples carry' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule ("user.x {0}eq 'a'" -f [char]0x2013))
                $tokens[1].Kind | Should-Be 'Operator'
                $tokens[1].Text | Should-Be 'eq'
            }
        }

        It 'treats a bare operator word without a dash as an operator' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x eq "a" and user.y ne "b"')
                @($tokens | Where-Object Kind -eq 'Operator' | ForEach-Object Text) |
                    Should-BeCollection @('eq', 'and', 'ne')
            }
        }

        It 'returns an unknown dashed word as an Operator so the scanner can flag -memberOf' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x -memberOf "a"')
                $tokens[1].Kind | Should-Be 'Operator'
                $tokens[1].Text | Should-Be 'memberof'
            }
        }
    }

    Context 'words and values' {

        It 'keeps a dotted identifier as one word' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.extension_abc_costCenter -eq 1')
                $tokens[0].Kind | Should-Be 'Word'
                $tokens[0].Text | Should-Be 'user.extension_abc_costCenter'
            }
        }

        It 'does not fuse a dash onto an identifier, so "user.department-eq" splits' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.department-eq "x"')
                $tokens.Kind | Should-BeCollection @('Word', 'Operator', 'String')
            }
        }

        It 'keeps a datetime with dashes and colons as one word' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.createdDateTime -ge 2020-06-10T18:13:20Z')
                $tokens[2].Kind | Should-Be 'Word'
                $tokens[2].Text | Should-Be '2020-06-10T18:13:20Z'
            }
        }

        It 'tokenizes brackets and commas in an array' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule "user.x -in ['a', 'b']")
                $tokens.Kind | Should-BeCollection @('Word', 'Operator', 'OpenBracket', 'String', 'Comma',
                    'String', 'CloseBracket')
            }
        }

        It 'returns a character it cannot read as Unknown, once, and keeps going' {
            InModuleScope EntraMemberOf {
                $tokens = @(ConvertTo-MembershipRuleToken -Rule 'user.x -eq "a" # user.y -eq "b"')
                @($tokens | Where-Object Kind -eq 'Unknown').Count | Should-Be 1
                $tokens.Count | Should-Be 7
            }
        }
    }
}
