#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The scanner's three levels and the notes it attaches, against inline rules. The public
    command's tests cover whole files and tenants; these pin what one rule produces.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'EntraMemberOf.psd1') -Force
    $script:G1 = 'a1b2c3d4-0000-4000-8000-000000000001'
    $script:G2 = 'a1b2c3d4-0000-4000-8000-000000000002'
}

AfterAll {
    Remove-Module EntraMemberOf -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-MemberOfRuleScan' -Tag 'Unit', 'Private' {

    Context 'Retired' {

        It 'reports the documented user rule with its kind, quantifier, operator and ids' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1; G2 = $script:G2 } {
                param($G1, $G2)
                $r = Invoke-MemberOfRuleScan -Rule "user.memberof -any (group.objectId -in ['$G1', '$G2'])" `
                    -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.RuleKind | Should-Be 'user'
                $r.Quantifier | Should-Be 'any'
                $r.Operator | Should-Be 'in'
                $r.SourceGroupIds | Should-BeCollection @($G1, $G2)
                $r.Note | Should-BeNull
                $r.Remediation | Should-MatchString 'assigned membership'
            }
        }

        It 'reports the documented device rule, written in any case' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -Rule "DEVICE.MemberOf -ANY (Group.ObjectId -IN ['$G1'])" `
                    -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.RuleKind | Should-Be 'device'
                $r.SourceGroupIds | Should-BeCollection @($G1)
            }
        }

        It 'reads double-quoted ids as well as single-quoted' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -any (group.objectId -in [`"$G1`"])" `
                    -ObjectKind Group -Source RuleText
                $r.SourceGroupIds | Should-BeCollection @($G1)
            }
        }

        It 'notes a quantifier or operator that is not the documented one, and still reports Retired' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -all (group.objectId -eq '$G1')" `
                    -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.Quantifier | Should-Be 'all'
                $r.Operator | Should-Be 'eq'
                $r.Note | Should-MatchString 'Quantifier -all is not the documented -any'
                $r.Note | Should-MatchString 'Operator -eq is not the documented -in'
            }
        }

        It 'notes a source value that is not an object id' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -any (group.objectId -in ['Sales'])" `
                    -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.Note | Should-MatchString 'Not every source value is an object id: Sales'
            }
        }

        It 'notes memberOf combined with other expressions' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -ObjectKind Group -Source RuleText `
                    -Rule "(user.country -eq `"US`") -and (user.memberOf -any (group.objectId -in ['$G1']))"
                $r.Level | Should-Be 'Retired'
                $r.SourceGroupIds | Should-BeCollection @($G1)
                $r.Note | Should-MatchString 'combined with other expressions'
            }
        }

        It 'does not count the -in inside the memberOf expression as a combination' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -any (group.objectId -in ['$G1'])" `
                    -ObjectKind Group -Source RuleText
                $r.Note | Should-BeNull
            }
        }

        It 'notes more source groups than the documented limit' {
            InModuleScope EntraMemberOf {
                $ids = @(1..51 | ForEach-Object { "'a1b2c3d4-0000-4000-8000-{0:d12}'" -f $_ }) -join ', '
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -any (group.objectId -in [$ids])" `
                    -ObjectKind Group -Source RuleText
                $r.SourceGroupIds.Count | Should-Be 51
                $r.Note | Should-MatchString '51 source groups, over the documented limit of 50'
            }
        }

        It 'notes a rule with no quantifier and no objectId comparison' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule 'user.memberOf' -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.Note | Should-MatchString 'No quantifier follows memberOf'
                $r.Note | Should-MatchString 'No group.objectid comparison'
                $r.Note | Should-MatchString 'No source group id'
            }
        }

        It 'picks the remediation sentence for the object kind' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $rule = "user.memberOf -any (group.objectId -in ['$G1'])"
                (Invoke-MemberOfRuleScan -Rule $rule -ObjectKind AdministrativeUnit -Source RuleText).Remediation |
                    Should-MatchString 'administrative scope'
                $policy = Invoke-MemberOfRuleScan -Rule $rule -ObjectKind AutoAssignmentPolicy -Source RuleText
                $policy.Remediation | Should-MatchString 'access package'
            }
        }
    }

    Context 'Review' {

        It 'reports memberOf inside a quoted value as StringLiteral' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule 'user.jobTitle -eq "memberOf coordinator"' -ObjectKind Group `
                    -Source RuleText
                $r.Level | Should-Be 'Review'
                $r.ReviewCode | Should-Be 'StringLiteral'
                $r.Remediation | Should-BeNull
            }
        }

        It 'reports a rule it could not read to the end as UnparsedRule' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule 'user.department -eq "Sales' -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Review'
                $r.ReviewCode | Should-Be 'UnparsedRule'
                $r.Note | Should-MatchString 'at index 20'
            }
        }

        It 'reports an identifier that only contains memberOf as UnqualifiedMemberOf' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule 'user.memberOfSomething -eq 1' -ObjectKind Group `
                    -Source RuleText
                $r.ReviewCode | Should-Be 'UnqualifiedMemberOf'
                $g = Invoke-MemberOfRuleScan -Rule 'group.memberOf -eq 1' -ObjectKind Group -Source RuleText
                $g.ReviewCode | Should-Be 'UnqualifiedMemberOf'
            }
        }

        It 'reports -memberOf written as an operator as MemberOfAsOperator' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule 'user.department -memberOf "x"' -ObjectKind Group `
                    -Source RuleText
                $r.ReviewCode | Should-Be 'MemberOfAsOperator'
            }
        }

        It 'still reports Retired, with a note, when a memberOf rule also has unreadable text' {
            InModuleScope EntraMemberOf -Parameters @{ G1 = $script:G1 } {
                param($G1)
                $r = Invoke-MemberOfRuleScan -Rule "user.memberOf -any (group.objectId -in ['$G1']) #" `
                    -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Retired'
                $r.Note | Should-MatchString 'could not read'
            }
        }
    }

    Context 'Clean' {

        It 'reports a rule without memberOf as Clean with no note' {
            InModuleScope EntraMemberOf {
                $rule = '(user.department -eq "Sales") -and (user.accountEnabled -eq true)'
                $r = Invoke-MemberOfRuleScan -Rule $rule -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Clean'
                $r.ReviewCode | Should-BeNull
                $r.Note | Should-BeNull
                $r.SourceGroupIds | Should-BeCollection @()
            }
        }

        It 'reports empty rule text as Clean with a note' {
            InModuleScope EntraMemberOf {
                $r = Invoke-MemberOfRuleScan -Rule $null -ObjectKind Group -Source RuleText
                $r.Level | Should-Be 'Clean'
                $r.Note | Should-Be 'No rule text.'
            }
        }
    }

    It 'carries the object identity and typed name through' {
        InModuleScope EntraMemberOf {
            $r = Invoke-MemberOfRuleScan -Rule 'user.x -eq 1' -ObjectKind AutoAssignmentPolicy -Id 'p1' `
                -DisplayName 'Policy' -AccessPackageName 'Pkg' -ProcessingState $null -Source 'Tenant'
            $r.PSObject.TypeNames | Should-ContainCollection 'EntraMemberOf.Result'
            $r.Id | Should-Be 'p1'
            $r.DisplayName | Should-Be 'Policy'
            $r.AccessPackageName | Should-Be 'Pkg'
            $r.Source | Should-Be 'Tenant'
            $r.DependsOnMemberOfGroup | Should-BeFalse
        }
    }
}
