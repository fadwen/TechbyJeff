#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The remaining public functions: connection handling, the group and rule seeders, and the
    report.

    Connect-OktaTestEnvironment is worth pinning because it is the only place a live credential
    is turned into module state, and because it has two failure modes that are silent rather
    than loud: storing a credential that was never validated, and returning the Authorization
    header in the -PassThru object where it lands in transcripts.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Fake tokens in a suite that never reaches a tenant. There is no real secret to protect.')]
param()

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-OktaTestEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Write-OktaTestProgress { }
            Mock Invoke-OktaTestRequest { @() }
            $script:OktaConnection = $null
        }
    }

    It 'validates the credential before storing it' {
        # A bad token accepted here and rejected on the first real call produces an error about
        # users when the problem is the credential.
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest { throw 'Okta GET /api/v1/users failed with HTTP 401' }

            $token = ConvertTo-SecureString 'bad' -AsPlainText -Force
            { Connect-OktaTestEnvironment -OrgUrl 'https://trial-1.okta.com' -ApiToken $token } |
                Should-Throw -ExceptionMessage '*Could not authenticate*'

            Get-OktaTestConnection -AllowNone | Should-BeNull
        }
    }

    It 'never returns the Authorization header' {
        # The PassThru object ends up in transcripts and in PassThru result bundles.
        InModuleScope OktaTestEnvironment {
            $token = ConvertTo-SecureString 'good' -AsPlainText -Force
            $c = Connect-OktaTestEnvironment -OrgUrl 'https://trial-1.okta.com' -ApiToken $token -PassThru

            $c.PSObject.Properties.Name | Should-NotContainCollection 'AuthorizationHeader'
        }
    }

    It 'rewrites the admin host to the API host' {
        # Pasting the admin console address is the most common way to get this wrong, and every
        # call then 404s without naming the cause.
        InModuleScope OktaTestEnvironment {
            $token = ConvertTo-SecureString 'good' -AsPlainText -Force
            $c = Connect-OktaTestEnvironment -OrgUrl 'https://trial-1-admin.okta.com' `
                -ApiToken $token -PassThru -WarningAction SilentlyContinue

            $c.OrgUrl | Should-Be 'https://trial-1.okta.com'
        }
    }

    It 'records the prefix upper-cased and the seed marker derived from it' {
        InModuleScope OktaTestEnvironment {
            $token = ConvertTo-SecureString 'good' -AsPlainText -Force
            $null = Connect-OktaTestEnvironment -OrgUrl 'https://trial-1.okta.com' `
                -ApiToken $token -Prefix 'contoso'

            $conn = Get-OktaTestConnection
            $conn.Prefix | Should-Be 'CONTOSO'
            $conn.SeedMarker | Should-Be '[seed:CONTOSO]'
        }
    }

    It 'clears the stored credential on disconnect' {
        InModuleScope OktaTestEnvironment {
            $token = ConvertTo-SecureString 'good' -AsPlainText -Force
            $null = Connect-OktaTestEnvironment -OrgUrl 'https://trial-1.okta.com' -ApiToken $token

            Disconnect-OktaTestEnvironment -Confirm:$false

            Get-OktaTestConnection -AllowNone | Should-BeNull
        }
    }
}

Describe 'New-OktaTestGroup' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                   EmailDomain = 'oktalab.example.com'; SeedMarker = '[seed:OKTALAB]' }
            }
            Mock Get-OktaTestSeededUser {
                $rows = Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaUsers.csv') -Encoding UTF8
                @($rows | ForEach-Object {
                    [PSCustomObject]@{
                        id = "00u$($_.LoginPrefix)"
                        profile = [PSCustomObject]@{ login = "$($_.LoginPrefix)@oktalab.example.com" }
                    }
                })
            }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                if ($Method -eq 'POST') { return [PSCustomObject]@{ id = "00g$($Body.profile.name)" } }
                return $null
            }
        }
    }

    It 'creates every group and stamps the seed marker into the description' {
        # Teardown requires the marker as well as the prefix, so a group created without it
        # would survive teardown silently.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestGroup -PassThru -Confirm:$false

            $r.CreatedGroups | Should-Be 17
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter {
                $Method -eq 'POST' -and $Path -eq '/api/v1/groups' -and
                -not $Body.profile.description.EndsWith('[seed:OKTALAB]')
            }
        }
    }

    It 'sends the accented display name to Okta rather than the ASCII key' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestGroup -GroupName Site-Zurich -PassThru -Confirm:$false

            $expected = 'OKTALAB-Z' + [string][char]0xFC + 'rich Site Access'
            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.profile.name -eq $expected
            }
        }
    }

    It 'leaves the deliberately empty group empty' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestGroup -GroupName Offboarding-Hold -PassThru -Confirm:$false
            $r.MembersAdded | Should-Be 0
        }
    }

    It 'adds no members to the rule-driven groups' {
        # A rule group with manual members cannot tell you whether the rule works.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestGroup -PassThru -Confirm:$false
            $auto = @($r.Groups | Where-Object { $_.Assignment -eq 'Rule' })

            @($auto).Count | Should-Be 3
            @($auto | Where-Object { @($_.Members).Count -gt 0 }).Count | Should-Be 0
        }
    }
}

Describe 'New-OktaTestGroupRule' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                   EmailDomain = 'oktalab.example.com'; SeedMarker = '[seed:OKTALAB]' }
            }
            Mock Get-OktaTestSeededGroup {
                $rows = Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaGroups.csv') -Encoding UTF8
                @($rows | ForEach-Object {
                    [PSCustomObject]@{
                        id = "00g$($_.Name)"
                        profile = [PSCustomObject]@{ name = "OKTALAB-$($_.DisplayName)" }
                    }
                })
            }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                if ($Method -eq 'POST' -and $Path -eq '/api/v1/groups/rules') {
                    return [PSCustomObject]@{ id = "0pr$($Body.name)" }
                }
                return $null
            }
        }
    }

    It 'creates and activates all three rules' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestGroupRule -PassThru -Confirm:$false
            $r.CreatedRules | Should-Be 3
            $r.ActivatedRules | Should-Be 3
        }
    }

    It 'leaves the rules inactive with -SkipActivation' {
        # An inactive rule assigns nobody, which is a useful state to test a report against.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestGroupRule -SkipActivation -PassThru -Confirm:$false

            $r.CreatedRules | Should-Be 3
            $r.ActivatedRules | Should-Be 0
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Path -like '*/lifecycle/activate' }
        }
    }

    It 'skips a rule whose target group is missing rather than pointing it elsewhere' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestSeededGroup { @() }

            $r = New-OktaTestGroupRule -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.CreatedRules | Should-Be 0
            @($r.Errors).Count | Should-Be 3
        }
    }
}
