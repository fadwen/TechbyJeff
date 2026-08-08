#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
    The report is the module's own account of what it built, so the defect that matters is not
    a crash - it is the report confidently omitting something that exists. That happened: six
    object types were added and the report kept reporting the original five, which reads as
    authoritative and is worse than not mentioning them.

    So the tests here are mostly completeness assertions, driven off the module's own data files
    rather than a hardcoded list, so that adding a seventh object type without reporting it
    fails here instead of misleading somebody later.

    Also covered: the credential and token accessors, which had no suite of their own.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "okta-report-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    # Inside InModuleScope, $script: is the MODULE's scope, not this file's, so the path has to
    # be pushed across explicitly or it reads as $null.
    InModuleScope OktaTestEnvironment -Parameters @{ ScratchPath = $script:Scratch } {
        param($ScratchPath)
        $script:Scratch = $ScratchPath
    }
}

AfterAll {
    Remove-Item -Path $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OktaTestEnvironmentReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Write-OktaTestProgress { }
            Mock Get-OktaTestConnection {
                @{
                    OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                    EmailDomain = 'oktalab.example.com'; SeedMarker = '[seed:OKTALAB]'
                    ActiveUserLimit = 10; AuthType = 'ApiToken'
                }
            }
            Mock Get-OktaTestUserHeadroom {
                [PSCustomObject]@{ Limit = 10; InUse = 10; Available = 0; SeededInUse = 8
                                   AvailableForSeed = 8; ExistingLogins = @() }
            }
            Mock Get-OktaTestSeededUser {
                @([PSCustomObject]@{
                    id = 'u1'; status = 'ACTIVE'
                    profile = [PSCustomObject]@{ login = 'a@oktalab.example.com'; displayName = 'A' }
                })
            }
            Mock Get-OktaTestSeededGroup {
                @([PSCustomObject]@{
                    id = 'g1'; profile = [PSCustomObject]@{ name = 'OKTALAB-All Employees'; description = 'x' }
                })
            }
            Mock Get-OktaTestSeededApp {
                @([PSCustomObject]@{ id = 'a1'; label = 'OKTALAB-Intranet Portal'
                                     status = 'ACTIVE'; signOnMode = 'BOOKMARK' })
            }

            Mock Invoke-OktaTestRequest {
                switch -Regex ($Path) {
                    '/api/v1/groups/rules$'  { return @([PSCustomObject]@{
                        id = 'r1'; name = 'OKTALAB-Rule-Contractors'; status = 'ACTIVE'
                        conditions = @{ expression = @{ value = 'x' } }
                        actions = @{ assignUserToGroups = @{ groupIds = @('g1') } } }) }
                    '/api/v1/meta/types/user$' { return @(
                        [PSCustomObject]@{ id = 't0'; name = 'user'; displayName = 'User'; default = $true }
                        [PSCustomObject]@{ id = 't1'; name = 'oktalabContractor'
                            displayName = 'OKTALAB-Lab Contractor'; default = $false
                            _links = @{ schema = @{
                                href = 'https://trial-1.okta.com/api/v1/meta/schemas/user/osc1' } } }
                    ) }
                    '/api/v1/meta/schemas/user/linkedObjects$' { return @([PSCustomObject]@{
                        primary = @{ name = 'labMentor' }; associated = @{ name = 'labMentee' } }) }
                    '/api/v1/meta/schemas/user/' {
                        return [PSCustomObject]@{ definitions = @{ custom = @{
                            properties = [PSCustomObject]@{
                                labSeedTag = [PSCustomObject]@{ title = 'Lab Seed Tag'; type = 'string' } } } } }
                    }
                    '/api/v1/zones$'          { return @([PSCustomObject]@{
                        id = 'z1'; name = 'OKTALAB-Corporate-Egress'; usage = 'POLICY'; status = 'ACTIVE'
                        gateways = @(@{ value = '198.51.100.0/24' }) }) }
                    '/api/v1/policies$'       { return @([PSCustomObject]@{
                        id = 'p1'; name = 'OKTALAB-Admin-Session'; type = $Query.type
                        status = 'ACTIVE'; priority = 1 }) }
                    '/api/v1/trustedOrigins$' { return @([PSCustomObject]@{
                        id = 'o1'; name = 'OKTALAB-Lab-Portal'; origin = 'https://portal.example.com'
                        scopes = @(@{ type = 'CORS' }) }) }
                    '/api/v1/eventHooks$'     { return @([PSCustomObject]@{
                        id = 'h1'; name = 'OKTALAB-Lifecycle-Watcher'; status = 'ACTIVE'
                        events = @{ items = @('user.lifecycle.create') }
                        channel = @{ config = @{ uri = 'https://example.com/x' } } }) }
                    '/groups$'                { return @() }
                    '/users$'                 { return @() }
                }
                return @()
            }
        }
    }

    It 'reports every object type the module creates' {
        # Driven off the Data folder rather than a hardcoded list, so a seventh CSV added
        # without a matching report section fails here.
        InModuleScope OktaTestEnvironment {
            $r = Get-OktaTestEnvironmentReport -PassThru

            $expected = @{
                'OktaUsers.csv'             = 'Users'
                'OktaGroups.csv'            = 'Groups'
                'OktaGroupRules.csv'        = 'GroupRules'
                'OktaApps.csv'              = 'Apps'
                'OktaProfileAttributes.csv' = 'CustomAttributes'
                'OktaUserTypes.csv'         = 'UserTypes'
                'OktaNetworkZones.csv'      = 'NetworkZones'
                'OktaPolicies.csv'          = 'Policies'
                'OktaTrustedOrigins.csv'    = 'TrustedOrigins'
                'OktaEventHooks.csv'        = 'EventHooks'
                'OktaLinkedObjects.csv'     = 'LinkedObjects'
            }

            $csvs = @(Get-ChildItem -Path (Get-OktaTestDataPath) -Filter *.csv | ForEach-Object { $_.Name })
            $unmapped = @($csvs | Where-Object { -not $expected.ContainsKey($_) })
            @($unmapped).Count | Should-Be 0

            $missing = @($expected.Values | Where-Object { -not $r.PSObject.Properties[$_] })
            @($missing).Count | Should-Be 0
        }
    }

    It 'reads every user type schema, not only the default' {
        # Reading only the default schema is the exact mistake the second user type exists to
        # expose, so the report itself must not make it.
        InModuleScope OktaTestEnvironment {
            $r = Get-OktaTestEnvironmentReport -PassThru

            @($r.CustomAttributes.UserType | Sort-Object -Unique) |
                Should-BeCollection @('oktalabContractor', 'user')
        }
    }

    It 'queries policies per type, since there is no all-policies listing' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestEnvironmentReport -PassThru

            foreach ($policyType in @('OKTA_SIGN_ON', 'PASSWORD')) {
                Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                    $Path -eq '/api/v1/policies' -and $Query.type -eq $policyType
                }
            }
        }
    }

    It 'includes the service app in the app listing' {
        InModuleScope OktaTestEnvironment {
            $null = Get-OktaTestEnvironmentReport -PassThru
            Should-Invoke Get-OktaTestSeededApp -Times 1 -Exactly -ParameterFilter { $IncludeServiceApp }
        }
    }

    It 'requires an output path for every format except Console' {
        InModuleScope OktaTestEnvironment {
            foreach ($format in @('JSON', 'HTML', 'CSV')) {
                { Get-OktaTestEnvironmentReport -OutputFormat $format } |
                    Should-Throw -ExceptionMessage '*OutputPath is required*'
            }
        }
    }

    It 'writes JSON that parses back with every section' {
        InModuleScope OktaTestEnvironment {
            $path = Join-Path $script:Scratch 'r.json'
            $null = Get-OktaTestEnvironmentReport -OutputFormat JSON -OutputPath $path

            $parsed = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $parsed.Licence.ActiveUserLimit | Should-Be 10
            @($parsed.NetworkZones).Count | Should-Be 1
            @($parsed.EventHooks).Count | Should-Be 1
        }
    }

    It 'survives an app or group whose members cannot be read' {
        # A 403 or a rate limit on one object's membership should cost you that object's counts,
        # not the entire report. The group read originally had no handler at all, so a single
        # 403 there took the whole thing down.
        InModuleScope OktaTestEnvironment {
            Mock Invoke-OktaTestRequest {
                if ($Path -like '*/users' -or $Path -like '*/groups') { throw 'HTTP 403' }
                return @()
            }

            $r = Get-OktaTestEnvironmentReport -PassThru -WarningAction SilentlyContinue

            @($r.Apps).Count | Should-Be 1
            @($r.Groups).Count | Should-Be 1
            $r.Groups[0].MemberCount | Should-Be 0
        }
    }
}

Describe 'Get-OktaTestAppCredential' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Import-OktaTestAppCredential {
                [PSCustomObject]@{
                    orgUrl = 'https://trial-1.okta.com'; clientId = '0oaX'; appId = '0oaX'
                    label = 'Lab'; scopes = @('okta.users.manage'); protection = 'DPAPI'
                    vaultName = $null; secretName = $null; createdUtc = '2026-08-07T00:00:00Z'
                    privateJwk = [PSCustomObject]@{ kid = 'k'; d = 'SECRET' }
                }
            }
        }
    }

    It 'does not return the private key by default' {
        # Nothing in normal use needs the key in a variable, and a function that returns one by
        # default puts one in transcripts.
        InModuleScope OktaTestEnvironment {
            $c = Get-OktaTestAppCredential -CredentialPath 'x'
            $c.PSObject.Properties.Name | Should-NotContainCollection 'PrivateJwk'
        }
    }

    It 'returns the key only when asked, and reports it as encrypted' {
        InModuleScope OktaTestEnvironment {
            $c = Get-OktaTestAppCredential -CredentialPath 'x' -IncludePrivateKey -Confirm:$false
            $c.PrivateJwk.d | Should-Be 'SECRET'
            $c.Encrypted | Should-BeTrue
        }
    }

    It 'warns when the stored key is unprotected' {
        InModuleScope OktaTestEnvironment {
            Mock Import-OktaTestAppCredential {
                [PSCustomObject]@{
                    orgUrl = 'https://trial-1.okta.com'; clientId = '0oaX'; appId = '0oaX'
                    label = 'Lab'; scopes = @(); protection = 'None'
                    vaultName = $null; secretName = $null; createdUtc = $null
                    privateJwk = [PSCustomObject]@{ kid = 'k' }
                }
            }

            $warnings = @()
            $c = Get-OktaTestAppCredential -CredentialPath 'x' -WarningVariable warnings `
                -WarningAction SilentlyContinue

            $c.Encrypted | Should-BeFalse
            (@($warnings) -join ' ') | Should-MatchString 'UNENCRYPTED'
        }
    }
}
