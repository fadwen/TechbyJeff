#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Groups and the rules that populate them. They are tested together because the interesting
    failures are in the seam between them: a rule names its target by the CSV key, Okta knows
    that group by its prefixed display name, and the rule needs the id. Two translations, and
    a mistake in either produces a rule that is created successfully and never populates
    anything - which looks like a working environment until somebody counts members.

    The membership shapes in OktaGroups.csv are deliberate, so the tests assert the shapes
    rather than just the call count: overlapping departments, a single-member group, an empty
    group, and two non-ASCII display names.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestGroup' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl      = 'https://trial-1.okta.com'
                    Prefix      = 'OKTALAB'
                    EmailDomain = 'oktalab.example.com'
                    SeedMarker  = '[OktaTestEnvironment]'
                }
            }

            # All eight seeded users resolve. Tests that need a member to go missing shrink
            # this inside the test rather than here.
            Mock Get-OktaTestSeededUser {
                @('awhitfield', 'jnino', 'zmueller', 'mbell', 'praghunathan', 'talvarez',
                  'hkobayashi', 'ofitzgerald' | ForEach-Object {
                    [PSCustomObject]@{
                        id      = "00u$_"
                        profile = [PSCustomObject]@{ login = "$_@oktalab.example.com" }
                    }
                })
            }

            # GET returns nothing, so every group takes the create path unless a test says
            # otherwise. The id echoes the name so assertions can tell the groups apart.
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                if ($Method -eq 'PUT' -and $Path -match '/users/') { return $null }
                return [PSCustomObject]@{
                    id      = "grp-$($Body.profile.name)"
                    profile = [PSCustomObject]@{ name = $Body.profile.name }
                }
            }
        }
    }

    Context 'Core Functionality' {

        It 'creates every group in the CSV and prefixes the display name' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -SkipMemberAssignment -PassThru -Confirm:$false

                $r.TotalGroups | Should-Be 17
                $r.CreatedGroups | Should-Be 17
                $r.UpdatedGroups | Should-Be 0
                @($r.Groups | Where-Object { $_.Name -notlike 'OKTALAB-*' }) |
                    Should-BeCollection -Count 0
            }
        }

        It 'stamps the seed marker onto every description' {
            # Remove-OktaTestEnvironment finds what it owns by this marker. A group created
            # without it survives a teardown that reports having removed everything.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestGroup -SkipMemberAssignment -PassThru -Confirm:$false

                # EndsWith, not -like: the marker is bracketed, and in a wildcard pattern
                # "[OktaTestEnvironment]" is a character class matching one character from
                # that set, so -like would quietly test something else entirely.
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'POST' -and
                    -not $Body.profile.description.EndsWith('[OktaTestEnvironment]')
                }
            }
        }

        It 'carries the accented display names through unmangled' {
            # The CSV is read with -Encoding UTF8 for these two rows. If that regresses the
            # names arrive as mojibake, which is exactly the defect the rows exist to catch,
            # so asserting on them here is the point rather than incidental.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -GroupName Site-Zurich, Ingenierie-Reseau `
                    -SkipMemberAssignment -PassThru -Confirm:$false

                @($r.Groups.Name) | Should-BeCollection @(
                    'OKTALAB-Zürich Site Access', 'OKTALAB-Ingénierie Réseau')
            }
        }

        It 'updates an existing group rather than creating a second one' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET') {
                        return @([PSCustomObject]@{
                            id      = 'grp-existing'
                            profile = [PSCustomObject]@{ name = 'OKTALAB-Finance' }
                        })
                    }
                    return [PSCustomObject]@{ id = 'grp-existing' }
                }

                $r = New-OktaTestGroup -GroupName Dept-Finance -SkipMemberAssignment `
                    -PassThru -Confirm:$false

                $r.UpdatedGroups | Should-Be 1
                $r.CreatedGroups | Should-Be 0
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'POST' }
            }
        }
    }

    Context 'Membership' {

        It 'assigns every membership named in the CSV' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -PassThru -Confirm:$false

                $r.MembersAdded | Should-Be 36
                @($r.Errors) | Should-BeCollection -Count 0
            }
        }

        It 'puts the overlapping user in both departments' {
            # talvarez is in Engineering and IT on purpose. A script that assumes one
            # department per user is wrong about him, and that is what he is there to expose.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -GroupName Dept-Engineering, Dept-IT -PassThru -Confirm:$false

                $inBoth = @($r.Groups | Where-Object {
                    $_.Members -contains 'talvarez@oktalab.example.com' })
                @($inBoth) | Should-BeCollection -Count 2
            }
        }

        It 'creates the deliberately empty group with no members and no errors' {
            # Empty and failed-to-resolve look identical in most reporting. They must not
            # look identical here.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -GroupName Offboarding-Hold -PassThru -Confirm:$false

                $r.CreatedGroups | Should-Be 1
                $r.MembersAdded | Should-Be 0
                @($r.Errors) | Should-BeCollection -Count 0
                @($r.Groups[0].Members) | Should-BeCollection -Count 0
            }
        }

        It 'skips a member who does not exist but still creates the group' {
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestSeededUser {
                    @([PSCustomObject]@{
                        id      = '00ujnino'
                        profile = [PSCustomObject]@{ login = 'jnino@oktalab.example.com' }
                    })
                }

                $r = New-OktaTestGroup -GroupName Dept-Engineering -PassThru -Confirm:$false `
                    -WarningAction SilentlyContinue

                $r.CreatedGroups | Should-Be 1
                $r.MembersAdded | Should-Be 1
                @($r.Errors) | Should-BeCollection -Count 2
            }
        }

        It 'creates the groups but no memberships with -SkipMemberAssignment' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -SkipMemberAssignment -PassThru -Confirm:$false

                $r.CreatedGroups | Should-Be 17
                $r.MembersAdded | Should-Be 0
                Should-NotInvoke Get-OktaTestSeededUser
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Method -eq 'PUT' -and $Path -match '/users/'
                }
            }
        }
    }

    Context 'Parameter Validation' {

        It 'restricts the run to the named groups' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroup -GroupName Dept-Sales -SkipMemberAssignment `
                    -PassThru -Confirm:$false

                $r.TotalGroups | Should-Be 1
                $r.Groups[0].Name | Should-Be 'OKTALAB-Sales'
            }
        }

        It 'throws on a group name the CSV does not define' {
            # Silently creating nothing would read as success, and the caller would be left
            # wondering why their group never appeared.
            InModuleScope OktaTestEnvironment {
                { New-OktaTestGroup -GroupName Dept-Nonexistent -Confirm:$false } |
                    Should-Throw -ExceptionMessage '*Dept-Nonexistent*'
            }
        }
    }

    Context 'Error Handling' {

        It 'records a failed group and carries on with the rest' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET') { return @() }
                    if ($Body.profile.name -eq 'OKTALAB-Sales') { throw 'HTTP 400 invalid name' }
                    return [PSCustomObject]@{ id = 'grp-ok' }
                }

                $r = New-OktaTestGroup -GroupName Dept-Sales, Dept-Finance `
                    -SkipMemberAssignment -PassThru -Confirm:$false -ErrorAction SilentlyContinue

                $r.CreatedGroups | Should-Be 1
                @($r.Errors) | Should-BeCollection -Count 1
                $r.Errors[0] | Should-MatchString 'OKTALAB-Sales'
            }
        }
    }

    Context 'Safety' {

        It 'creates nothing under -WhatIf' {
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestGroup -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'POST' }
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'PUT' }
            }
        }
    }
}

Describe 'New-OktaTestGroupRule' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl      = 'https://trial-1.okta.com'
                    Prefix      = 'OKTALAB'
                    EmailDomain = 'oktalab.example.com'
                    SeedMarker  = '[OktaTestEnvironment]'
                }
            }

            # The three rule-target groups exist, named the way Okta would know them.
            Mock Get-OktaTestSeededGroup {
                @('Automatic Contractors', 'Automatic High Clearance', 'Automatic Engineering' |
                    ForEach-Object {
                        [PSCustomObject]@{
                            id      = "grp-$($_ -replace ' ', '')"
                            profile = [PSCustomObject]@{ name = "OKTALAB-$_" }
                        }
                    })
            }

            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                return [PSCustomObject]@{ id = "rule-$($Body.name)"; name = $Body.name }
            }
        }
    }

    Context 'Core Functionality' {

        It 'creates every rule and names it consistently' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroupRule -PassThru -Confirm:$false

                $r.TotalRules | Should-Be 3
                $r.CreatedRules | Should-Be 3
                @($r.Errors) | Should-BeCollection -Count 0
                @($r.Rules.Name) | Should-BeCollection @(
                    'OKTALAB-Rule-Contractors',
                    'OKTALAB-Rule-High-Clearance',
                    'OKTALAB-Rule-Engineering')
            }
        }

        It 'resolves the CSV target key through the display name to the group id' {
            # The rule is useless if it targets the wrong group, and a wrong-but-valid id
            # produces a rule Okta accepts. This is the seam worth pinning down.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestGroupRule -RuleName Contractors -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Path -eq '/api/v1/groups/rules' -and
                    $Body.actions.assignUserToGroups.groupIds[0] -eq 'grp-AutomaticContractors'
                }
            }
        }

        It 'sends the expression verbatim, embedded quotes and all' {
            # Two of the three expressions contain doubled quotes in the CSV. Anything that
            # re-quotes or escapes them produces an expression Okta accepts and never matches.
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestGroupRule -RuleName High-Clearance -PassThru -Confirm:$false

                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and
                    $Body.conditions.expression.value -eq 'user.labClearanceLevel == "High"' -and
                    $Body.conditions.expression.type -eq 'urn:okta:expression:1.0'
                }
            }
        }

        It 'deactivates an existing rule before updating it' {
            # Okta refuses to modify an active rule, so a missing deactivate turns every
            # re-run into a failure on exactly the rules that worked last time.
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET') {
                        return @([PSCustomObject]@{
                            id = 'rule-existing'; name = 'OKTALAB-Rule-Contractors' })
                    }
                    return [PSCustomObject]@{ id = 'rule-existing' }
                }

                $r = New-OktaTestGroupRule -RuleName Contractors -PassThru -Confirm:$false

                $r.UpdatedRules | Should-Be 1
                $r.CreatedRules | Should-Be 0
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/groups/rules/rule-existing/lifecycle/deactivate'
                }
            }
        }

        It 'treats an already-inactive rule as fine rather than failing the update' {
            InModuleScope OktaTestEnvironment {
                Mock Invoke-OktaTestRequest {
                    if ($Method -eq 'GET') {
                        return @([PSCustomObject]@{
                            id = 'rule-existing'; name = 'OKTALAB-Rule-Contractors' })
                    }
                    if ($Path -like '*lifecycle/deactivate') { throw 'HTTP 400 already inactive' }
                    return [PSCustomObject]@{ id = 'rule-existing' }
                }

                $r = New-OktaTestGroupRule -RuleName Contractors -PassThru -Confirm:$false

                $r.UpdatedRules | Should-Be 1
                @($r.Errors) | Should-BeCollection -Count 0
            }
        }
    }

    Context 'Activation' {

        It 'activates the rules the CSV marks for activation' {
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroupRule -PassThru -Confirm:$false

                $r.ActivatedRules | Should-Be 3
                @($r.Rules | Where-Object { -not $_.Active }) | Should-BeCollection -Count 0
            }
        }

        It 'creates the rules inactive with -SkipActivation' {
            # An active rule starts moving real membership. Seeding without activating is how
            # you stage an environment before letting the rules loose on it.
            InModuleScope OktaTestEnvironment {
                $r = New-OktaTestGroupRule -SkipActivation -PassThru -Confirm:$false

                $r.CreatedRules | Should-Be 3
                $r.ActivatedRules | Should-Be 0
                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                    $Path -like '*lifecycle/activate'
                }
            }
        }
    }

    Context 'Error Handling' {

        It 'skips a rule whose target group is missing, and says which' {
            # This is the ordering trap: rules before groups leaves rules pointing at nothing.
            # It has to name the group and it must not throw, or a partial seed cannot recover.
            InModuleScope OktaTestEnvironment {
                Mock Get-OktaTestSeededGroup { @() }

                $r = New-OktaTestGroupRule -PassThru -Confirm:$false -WarningAction SilentlyContinue

                $r.CreatedRules | Should-Be 0
                @($r.Errors) | Should-BeCollection -Count 3
                $r.Errors[0] | Should-MatchString 'New-OktaTestGroup'
            }
        }

        It 'throws on a rule name the CSV does not define' {
            InModuleScope OktaTestEnvironment {
                { New-OktaTestGroupRule -RuleName Nonexistent -Confirm:$false } |
                    Should-Throw -ExceptionMessage '*Nonexistent*'
            }
        }
    }

    Context 'Safety' {

        It 'creates nothing under -WhatIf' {
            InModuleScope OktaTestEnvironment {
                $null = New-OktaTestGroupRule -WhatIf

                Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'POST' }
            }
        }
    }
}
