#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The public command in all three modes. File mode runs against the fixtures under
    Tests/Fixtures; tenant mode against a scripted request handler, so nothing here reaches
    Graph. The one file that does is under Tests/Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'EntraMemberOf.psd1') -Force
    $script:Fixtures = Join-Path $script:ModuleRoot 'Tests\Fixtures'

    function Get-Fixture([string]$Name) { Join-Path $script:Fixtures $Name }
    function Get-ResultOnly($Output) {
        @($Output | Where-Object { $_.PSObject.TypeNames -contains 'EntraMemberOf.Result' })
    }
    function Get-SummaryOnly($Output) {
        @($Output | Where-Object { $_.PSObject.TypeNames -contains 'EntraMemberOf.Summary' })[0]
    }
    $script:G1 = 'a1b2c3d4-0000-4000-8000-000000000001'
}

AfterAll {
    Remove-Module EntraMemberOf -Force -ErrorAction SilentlyContinue
}

Describe 'Test-EntraMemberOfRule rule text mode' -Tag 'Unit', 'Public', 'RuleMode' {

    It 'scans one rule and emits one result and no summary' {
        $out = @(Test-EntraMemberOfRule -Rule "user.memberOf -any (group.objectId -in ['$script:G1'])")
        $out.Count | Should-Be 1
        $out[0].PSObject.TypeNames | Should-ContainCollection 'EntraMemberOf.Result'
        $out[0].ObjectKind | Should-Be 'Rule'
        $out[0].Source | Should-Be 'RuleText'
        $out[0].Level | Should-Be 'Retired'
    }

    It 'takes rules from the pipeline, one result each, in order' {
        $rules = @('user.department -eq "x"', 'user.jobTitle -eq "memberOf"',
            'device.memberOf -any (group.objectId -in [''a''])')
        $out = @($rules | Test-EntraMemberOfRule)
        $out.Level | Should-BeCollection @('Clean', 'Review', 'Retired')
    }

    It 'binds a MembershipRule property from the pipeline' {
        $group = [PSCustomObject]@{ MembershipRule = 'user.memberOf -any (group.objectId -in [''a''])' }
        $out = @($group | Test-EntraMemberOfRule)
        $out[0].Level | Should-Be 'Retired'
    }

    It 'accepts an empty rule and reports it Clean with a note' {
        $out = @(Test-EntraMemberOfRule -Rule '')
        $out[0].Level | Should-Be 'Clean'
        $out[0].Note | Should-Be 'No rule text.'
    }
}

Describe 'Test-EntraMemberOfRule file mode' -Tag 'Unit', 'Public', 'FileMode' {

    Context 'the admin center style export' {

        BeforeAll {
            $script:Out = Test-EntraMemberOfRule -Path (Get-Fixture 'dynamic-groups-export.csv')
            $script:Results = Get-ResultOnly $script:Out
            $script:Summary = Get-SummaryOnly $script:Out
        }

        It 'emits one result per row, then one summary' {
            $script:Results.Count | Should-Be 8
            $script:Summary | Should-NotBeNull
            @($script:Out)[-1].PSObject.TypeNames | Should-ContainCollection 'EntraMemberOf.Summary'
        }

        It 'takes every row as a Group and names the file as the source' {
            $script:Results | Should-All { $_.ObjectKind -eq 'Group' }
            $script:Results | Should-All { $_.Source -like '*dynamic-groups-export.csv' }
            $script:Results | Should-All { $_.Note -match 'no object kind' }
        }

        It 'reads objectId, displayName and the processing state columns' {
            $script:Results[2].Id | Should-Be '11111111-0000-4000-8000-000000000003'
            $script:Results[2].DisplayName | Should-Be 'Sales and Marketing'
            $script:Results[4].ProcessingState | Should-Be 'Paused'
        }

        It 'reports exactly the memberOf rows as Retired' {
            @($script:Results | Where-Object Level -eq 'Retired' | ForEach-Object DisplayName) |
                Should-BeCollection @('Sales and Marketing', 'Field Devices', 'Rollup of Rollups')
        }

        It 'reports the quoted-value and broken rows for review, each with its code' {
            ($script:Results | Where-Object DisplayName -eq 'Says memberOf').ReviewCode | Should-Be 'StringLiteral'
            ($script:Results | Where-Object DisplayName -eq 'Broken rule').ReviewCode | Should-Be 'UnparsedRule'
        }

        It 'reports a row with no rule as Clean' {
            ($script:Results | Where-Object DisplayName -eq 'Assigned group').Level | Should-Be 'Clean'
        }

        It 'resolves source group names from the file itself and leaves unknown ids null' {
            $rollup = $script:Results | Where-Object DisplayName -eq 'Sales and Marketing'
            $rollup.SourceGroupNames | Should-BeCollection @('All Sales', 'All Marketing')
            $devices = $script:Results | Where-Object DisplayName -eq 'Field Devices'
            $devices.SourceGroupNames | Should-BeCollection @($null)
        }

        It 'finds the memberOf group that depends on another memberOf group' {
            $nested = $script:Results | Where-Object DisplayName -eq 'Rollup of Rollups'
            $nested.DependsOnMemberOfGroup | Should-BeTrue
            $nested.DependsOn | Should-BeCollection @('11111111-0000-4000-8000-000000000003')
            $nested.Note | Should-MatchString 'Learn lists as unsupported'
            $flat = $script:Results | Where-Object DisplayName -eq 'Sales and Marketing'
            $flat.DependsOnMemberOfGroup | Should-BeFalse
        }

        It 'summarizes the file with per-kind counts and complete coverage' {
            $script:Summary.Mode | Should-Be 'File'
            $script:Summary.Outcome | Should-Be 'Retired'
            $script:Summary.Coverage | Should-Be 'Complete'
            $script:Summary.Groups.Scanned | Should-Be 8
            $script:Summary.Groups.Retired | Should-Be 3
            $script:Summary.Groups.Review | Should-Be 2
            $script:Summary.AdministrativeUnits.Coverage | Should-Be 'NotRequested'
            $script:Summary.MemberOfGroupCount | Should-Be 3
            $script:Summary.MemberOfGroupLimit | Should-Be 500
            $script:Summary.DependencyChainCount | Should-Be 1
            $script:Summary.RetirementDate | Should-Be '2026-11-03'
            $script:Summary.Message | Should-MatchString '^3 object\(s\) use memberOf and stop updating after '
            $script:Summary.Message | Should-MatchString 'November 3, 2026; 2 more need a look\.$'
        }
    }

    Context 'a saved Graph response' {

        It 'reads the value array of a JSON response' {
            $results = Get-ResultOnly (Test-EntraMemberOfRule -Path (Get-Fixture 'graph-groups.json'))
            $results.Count | Should-Be 3
            $results.Level | Should-BeCollection @('Retired', 'Clean', 'Retired')
            $results[2].Note | Should-MatchString 'combined with other expressions'
            $results[2].SourceGroupNames | Should-BeCollection @('All Engineers')
        }
    }

    Context 'a file with an object kind column' {

        BeforeAll {
            $script:Mixed = Get-ResultOnly (Test-EntraMemberOfRule -Path (Get-Fixture 'mixed-kinds.csv'))
            $script:MixedSummary = Get-SummaryOnly (Test-EntraMemberOfRule -Path (Get-Fixture 'mixed-kinds.csv'))
        }

        It 'maps the kind column and the alternative column names' {
            $script:Mixed.ObjectKind |
                Should-BeCollection @('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy', 'Rule', 'Group')
            $script:Mixed[0].DisplayName | Should-Be 'Rollup Group'
            $script:Mixed[2].AccessPackageName | Should-Be 'Contractor Tools'
        }

        It 'falls back to Group for a kind it does not know, and says so' {
            $script:Mixed[4].ObjectKind | Should-Be 'Group'
            $script:Mixed[4].Note | Should-MatchString "Object kind 'Widget' was not recognized"
        }

        It 'picks the remediation for each kind' {
            $script:Mixed[1].Remediation | Should-MatchString 'administrative scope'
            $script:Mixed[2].Remediation | Should-MatchString 'access package'
        }

        It 'marks the unit and policy that depend on the memberOf group, without the group-only clause' {
            $script:Mixed[1].DependsOnMemberOfGroup | Should-BeTrue
            $script:Mixed[1].Note | Should-NotMatchString 'unsupported'
            $script:Mixed[2].DependsOnMemberOfGroup | Should-BeFalse
        }

        It 'counts each kind separately in the summary' {
            $script:MixedSummary.Groups.Scanned | Should-Be 2
            $script:MixedSummary.AdministrativeUnits.Retired | Should-Be 1
            $script:MixedSummary.AutoAssignmentPolicies.Retired | Should-Be 1
            $script:MixedSummary.Rules.Scanned | Should-Be 1
            $script:MixedSummary.RetiredCount | Should-Be 3
        }
    }

    Context 'input handling' {

        It 'errors on a file with no rule column rather than reporting it clean' {
            $noRule = Get-Fixture 'no-rule-column.csv'
            $out = @(Test-EntraMemberOfRule -Path $noRule -ErrorAction SilentlyContinue -ErrorVariable err)
            $written = @($err | Where-Object { "$_" -like 'Could not read *' })
            $written.Count | Should-Be 1
            "$written" | Should-MatchString 'no rule column'
            (Get-ResultOnly $out).Count | Should-Be 0
        }

        It 'errors on a missing path and continues with the next' {
            $paths = @((Join-Path $TestDrive 'missing.csv'), (Get-Fixture 'graph-groups.json'))
            $out = @(Test-EntraMemberOfRule -Path $paths -ErrorAction SilentlyContinue -ErrorVariable err)
            (Get-ResultOnly $out).Count | Should-Be 3
            @($err | Where-Object { "$_" -like 'Path not found*' }).Count | Should-Be 1
        }

        It 'rejects a file that is neither csv nor json' {
            $txt = Join-Path $TestDrive 'rules.txt'
            Set-Content -Path $txt -Value 'user.memberOf -any (group.objectId -in [''a''])'
            Test-EntraMemberOfRule -Path $txt -ErrorAction SilentlyContinue -ErrorVariable err
            "$err" | Should-MatchString 'not a \.csv or \.json'
        }

        It 'takes Get-ChildItem output from the pipeline' {
            $out = @(Get-ChildItem (Join-Path $script:Fixtures '*.json') | Test-EntraMemberOfRule)
            (Get-ResultOnly $out).Count | Should-Be 3
            (Get-SummaryOnly $out).Mode | Should-Be 'File'
        }

        It 'expands a wildcard and scans every matching file into one summary' {
            $paths = @((Join-Path $script:Fixtures 'dynamic-groups-*.csv'), (Get-Fixture 'graph-groups.json'))
            $out = @(Test-EntraMemberOfRule -Path $paths)
            (Get-ResultOnly $out).Count | Should-Be 11
            @($out | Where-Object { $_.PSObject.TypeNames -contains 'EntraMemberOf.Summary' }).Count | Should-Be 1
        }
    }
}

Describe 'Test-EntraMemberOfRule tenant mode' -Tag 'Unit', 'Public', 'TenantMode' {

    BeforeAll {
        $script:V1 = 'https://graph.microsoft.com/v1.0'
        $script:SourceId = '22222222-0000-4000-8000-000000000009'
        $script:DynA = '22222222-0000-4000-8000-000000000001'
        $script:DynB = '22222222-0000-4000-8000-000000000002'
        $script:Gone = '22222222-0000-4000-8000-000000000008'

        # A scripted tenant: two dynamic groups (one memberOf group whose sources are a plain
        # group and the other memberOf group), one dynamic and one assigned administrative unit,
        # one auto-assignment policy with a memberOf rule, one manual policy, and group paging.
        # Everything the handler reads is a local captured by GetNewClosure; $script: inside a
        # closure would refer to the closure's own module and read as null.
        function Get-TenantHandler {
            param([switch]$AdministrativeUnitsForbidden, [switch]$AsHashtable)

            $calls = [System.Collections.Generic.List[object]]::new()
            $script:Calls = $calls
            $sourceId = $script:SourceId; $dynA = $script:DynA; $dynB = $script:DynB; $gone = $script:Gone
            $forbidUnits = $AdministrativeUnitsForbidden.IsPresent
            $asHashtable = $AsHashtable.IsPresent
            $forbidden = 'Response status code does not indicate success: Forbidden (Forbidden).'
            $toObject = { param($Hashtable) if ($asHashtable) { $Hashtable } else { [PSCustomObject]$Hashtable } }

            return {
                param($Uri, $Headers)
                $calls.Add([PSCustomObject]@{ Uri = $Uri; Headers = $Headers })

                switch -Regex ($Uri) {
                    '/groups\?.*DynamicMembership.*(?<!skiptoken=page2)$' {
                        return & $toObject @{
                            '@odata.nextLink' = "$Uri&`$skiptoken=page2"
                            value = @((& $toObject @{
                                id = $dynA; displayName = 'Dyn A'; groupTypes = @('DynamicMembership')
                                membershipRule = "user.memberOf -any (group.objectId -in ['$sourceId', '$dynB'])"
                                membershipRuleProcessingState = 'On'
                            }))
                        }
                    }
                    '/groups\?.*DynamicMembership.*skiptoken=page2$' {
                        return & $toObject @{ value = @((& $toObject @{
                            id = $dynB; displayName = 'Dyn B'; groupTypes = @('DynamicMembership')
                            membershipRule = "device.memberOf -any (group.objectId -in ['$gone'])"
                            membershipRuleProcessingState = 'Paused'
                        })) }
                    }
                    '/groups\?.*id%20in' {
                        return & $toObject @{ value = @(
                            (& $toObject @{ id = $sourceId; displayName = 'Source Group' })
                            (& $toObject @{ id = $dynB; displayName = 'Dyn B' })
                        ) }
                    }
                    '/directory/administrativeUnits' {
                        if ($forbidUnits) { throw $forbidden }
                        return & $toObject @{ value = @(
                            (& $toObject @{ id = 'au1'; displayName = 'Dynamic AU'; membershipType = 'dynamic'
                                membershipRule = "user.memberOf -any (group.objectId -in ['$dynA'])"
                                membershipRuleProcessingState = 'On' })
                            (& $toObject @{ id = 'au2'; displayName = 'Assigned AU'; membershipType = 'assigned'
                                membershipRule = $null; membershipRuleProcessingState = $null })
                        ) }
                    }
                    '/assignmentPolicies' {
                        return & $toObject @{ value = @(
                            (& $toObject @{
                                id = 'p1'; displayName = 'Auto policy'
                                automaticRequestSettings = (& $toObject @{ requestAccessForAllowedTargets = $true
                                })
                                accessPackage = (& $toObject @{ displayName = 'Contractor Tools' })
                                specificAllowedTargets = @((& $toObject @{
                                    '@odata.type' = '#microsoft.graph.attributeRuleMembers'
                                    membershipRule = "user.memberof -any (group.objectId -in ['$sourceId'])"
                                }))
                            })
                            (& $toObject @{
                                id = 'p2'; displayName = 'Manual policy'
                                accessPackage = (& $toObject @{ displayName = 'Contractor Tools' })
                                specificAllowedTargets = @()
                            })
                        ) }
                    }
                }
                throw "Unexpected request in test handler: $Uri"
            }.GetNewClosure()
        }
    }

    Context 'a full scan' {

        BeforeEach {
            $script:Out = @(Test-EntraMemberOfRule -Tenant -RequestHandler (Get-TenantHandler))
            $script:Results = Get-ResultOnly $script:Out
            $script:Summary = Get-SummaryOnly $script:Out
        }

        It 'returns one result per rule-bearing object across the three kinds, then a summary' {
            @($script:Results | ForEach-Object DisplayName) |
                Should-BeCollection @('Dyn A', 'Dyn B', 'Dynamic AU', 'Auto policy')
            $script:Results.ObjectKind |
                Should-BeCollection @('Group', 'Group', 'AdministrativeUnit', 'AutoAssignmentPolicy')
            $script:Summary.Mode | Should-Be 'Tenant'
        }

        It 'skips the assigned administrative unit and the manual policy' {
            $script:Results.DisplayName | Should-NotContainCollection 'Assigned AU'
            $script:Results.DisplayName | Should-NotContainCollection 'Manual policy'
        }

        It 'follows the groups paging link' {
            $script:Results[1].DisplayName | Should-Be 'Dyn B'
            @($script:Calls | Where-Object { $_.Uri -like '*skiptoken=page2*' }).Count | Should-Be 1
        }

        It 'sends ConsistencyLevel eventual with the dynamic group filter on every page' {
            $groupCalls = @($script:Calls | Where-Object { $_.Uri -like '*DynamicMembership*' })
            $groupCalls.Count | Should-Be 2
            $groupCalls | Should-All { $_.Headers['ConsistencyLevel'] -eq 'eventual' }
            $groupCalls[0].Uri | Should-MatchString '\$count=true'
        }

        It 'resolves source group names in one batched lookup' {
            $lookups = @($script:Calls | Where-Object { $_.Uri -like '*id%20in*' })
            $lookups.Count | Should-Be 1
            $script:Results[0].SourceGroupNames | Should-BeCollection @('Source Group', 'Dyn B')
        }

        It 'names a deleted source group as not found' {
            $script:Results[1].SourceGroupNames | Should-BeCollection @($null)
            $script:Results[1].Note | Should-MatchString "not found in the tenant: $script:Gone"
        }

        It 'marks the memberOf group and the unit that depend on another memberOf group' {
            $script:Results[0].DependsOn | Should-BeCollection @($script:DynB)
            $script:Results[2].DependsOn | Should-BeCollection @($script:DynA)
            $script:Results[2].SourceGroupNames | Should-BeCollection @('Dyn A')
            $script:Results[3].DependsOnMemberOfGroup | Should-BeFalse
        }

        It 'carries the processing state and the access package name' {
            $script:Results[1].ProcessingState | Should-Be 'Paused'
            $script:Results[3].AccessPackageName | Should-Be 'Contractor Tools'
            $script:Results[3].Source | Should-Be 'Tenant'
        }

        It 'summarizes complete coverage with per-kind counts' {
            $script:Summary.Outcome | Should-Be 'Retired'
            $script:Summary.Coverage | Should-Be 'Complete'
            $script:Summary.Groups.Scanned | Should-Be 2
            $script:Summary.AdministrativeUnits.Scanned | Should-Be 1
            $script:Summary.AutoAssignmentPolicies.Scanned | Should-Be 1
            $script:Summary.RetiredCount | Should-Be 4
            $script:Summary.DependencyChainCount | Should-Be 2
            $script:Summary.IncompleteKinds | Should-BeCollection @()
        }

        It 'only ever sends GET requests under v1.0' {
            $script:Calls | Should-All { $_.Uri -like 'https://graph.microsoft.com/v1.0/*' }
        }
    }

    Context 'coverage and options' {

        It 'reports a kind that cannot be read as incomplete and still scans the others' {
            $handler = Get-TenantHandler -AdministrativeUnitsForbidden
            $out = @(Test-EntraMemberOfRule -Tenant -RequestHandler $handler -ErrorAction SilentlyContinue `
                -ErrorVariable err)
            $summary = Get-SummaryOnly $out
            $summary.Coverage | Should-Be 'Incomplete'
            $summary.AdministrativeUnits.Coverage | Should-Be 'Incomplete'
            $summary.IncompleteKinds | Should-BeCollection @('AdministrativeUnit')
            $summary.Message | Should-MatchString 'Not every kind was read: AdministrativeUnit'
            (Get-ResultOnly $out).Count | Should-Be 3
            @($err | Where-Object { "$_" -like 'Could not read AdministrativeUnit*' }).Count | Should-Be 1
        }

        It 'reads only the kinds asked for' {
            $out = @(Test-EntraMemberOfRule -Tenant -ObjectKind Group -RequestHandler (Get-TenantHandler))
            (Get-ResultOnly $out) | Should-All { $_.ObjectKind -eq 'Group' }
            $script:Calls | Should-All {
                $_.Uri -notlike '*administrativeUnits*' -and $_.Uri -notlike '*assignmentPolicies*'
            }
            (Get-SummaryOnly $out).AutoAssignmentPolicies.Coverage | Should-Be 'NotRequested'
        }

        It 'skips the name lookup when asked, and still finds chains from the scan itself' {
            $handler = Get-TenantHandler
            $out = @(Test-EntraMemberOfRule -Tenant -ObjectKind Group -SkipGroupNameLookup `
                -RequestHandler $handler)
            @($script:Calls | Where-Object { $_.Uri -like '*id%20in*' }).Count | Should-Be 0
            $results = Get-ResultOnly $out
            $results[0].SourceGroupNames | Should-BeCollection @($null, 'Dyn B')
            $results[0].DependsOn | Should-BeCollection @($script:DynB)
        }

        It 'reports an all-clean tenant as Clean with every kind complete' {
            $handler = { [PSCustomObject]@{ value = @() } }
            $out = @(Test-EntraMemberOfRule -Tenant -RequestHandler $handler)
            $out.Count | Should-Be 1
            $out[0].Outcome | Should-Be 'Clean'
            $out[0].Coverage | Should-Be 'Complete'
            $out[0].Message | Should-Be 'No memberOf rules in 0 object(s) scanned.'
        }

        It 'reports nothing found with a failed kind as Incomplete, not Clean' {
            $handler = {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    throw 'Response status code does not indicate success: Forbidden (Forbidden).'
                }
                [PSCustomObject]@{ value = @() }
            }
            $out = @(Test-EntraMemberOfRule -Tenant -RequestHandler $handler -ErrorAction SilentlyContinue)
            (Get-SummaryOnly $out).Outcome | Should-Be 'Incomplete'
            (Get-SummaryOnly $out).Message | Should-MatchString 'not an all-clear'
        }

        It 'reads hashtable responses as well as objects' {
            $out = @(Test-EntraMemberOfRule -Tenant -RequestHandler (Get-TenantHandler -AsHashtable))
            (Get-ResultOnly $out).Count | Should-Be 4
            (Get-ResultOnly $out)[3].AccessPackageName | Should-Be 'Contractor Tools'
        }

        It 'explains what to install when no handler is given and the Graph SDK is absent' {
            InModuleScope EntraMemberOf {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Invoke-MgGraphRequest' }
                { Invoke-EntraMemberOfRequest -Uri 'https://graph.microsoft.com/v1.0/groups' } |
                    Should-Throw -ExceptionMessage '*Microsoft.Graph.Authentication*'
            }
        }

        It 'refuses a URI outside graph.microsoft.com' {
            InModuleScope EntraMemberOf {
                { Invoke-EntraMemberOfRequest -Uri 'https://example.com/groups' -RequestHandler { 'x' } } |
                    Should-Throw
            }
        }
    }
}
