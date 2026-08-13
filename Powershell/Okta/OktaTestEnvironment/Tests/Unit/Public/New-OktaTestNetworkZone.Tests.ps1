#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The three remaining seed functions whose bodies are a CSV row turned into a POST: network
    zones, trusted origins and event hooks, plus linked objects.

    Each has exactly one piece of real logic, and each of those is a place a silent mistake
    would go unnoticed - a wrong gateway type, a scope list that did not split, a link pointing
    the wrong way round. Those are what is tested here rather than the loop around them.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-OktaTestNetworkZone' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection { @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB' } }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                return [PSCustomObject]@{ id = 'nzo1'; name = $Body.name }
            }
        }
    }

    It 'creates both zones with their declared usage' {
        # POLICY and BLOCKLIST zones behave differently in evaluation, so the usage has to
        # survive from the CSV rather than defaulting.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestNetworkZone -PassThru -Confirm:$false

            $r.CreatedZones | Should-Be 2
            @($r.Zones.Usage | Sort-Object -Unique) | Should-BeCollection @('BLOCKLIST', 'POLICY')
        }
    }

    It 'infers CIDR from the value shape rather than being told' {
        # Okta rejects a CIDR sent as a RANGE and vice versa.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestNetworkZone -ZoneName Corporate-Egress -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                @($Body.gateways | Where-Object { $_.type -ne 'CIDR' }).Count -eq 0 -and
                @($Body.gateways).Count -eq 2
            }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestNetworkZone -WhatIf
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'POST' }
        }
    }
}

Describe 'New-OktaTestTrustedOrigin' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection { @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB' } }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                return [PSCustomObject]@{ id = 'tos1'; name = $Body.name }
            }
        }
    }

    It 'splits the scope list into separate scope objects' {
        # One origin has both scopes and one has only CORS, so a split that silently produced
        # one scope for both would still look plausible.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestTrustedOrigin -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and @($Body.scopes).Count -eq 2 -and
                @($Body.scopes | ForEach-Object { $_.type }) -contains 'REDIRECT'
            }
            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and @($Body.scopes).Count -eq 1
            }
        }
    }

    It 'keeps origins under a reserved domain' {
        # A trusted origin naming a domain somebody else controls is a real security finding.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestTrustedOrigin -PassThru -Confirm:$false
            $bad = @($r.Origins | Where-Object { ([uri]$_.Origin).Host -notlike '*example.com' })
            @($bad).Count | Should-Be 0
        }
    }
}

Describe 'New-OktaTestEventHook' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection { @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB' } }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                return [PSCustomObject]@{ id = 'who1'; name = $Body.name; status = 'ACTIVE' }
            }
        }
    }

    It 'splits the event list and sends it as EVENT_TYPE items' {
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestEventHook -HookName Lifecycle-Watcher -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.events.type -eq 'EVENT_TYPE' -and
                @($Body.events.items).Count -eq 3
            }
        }
    }

    It 'points the hooks at a resolvable host, which Okta requires' {
        # Okta validates the hook URL and rejects a hostname that does not resolve, so the lab
        # domain cannot be used here even though everything else uses it.
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestEventHook -PassThru -Confirm:$false
            $bad = @($r.Hooks | Where-Object { ([uri]$_.Uri).Host -ne 'example.com' })
            @($bad).Count | Should-Be 0
        }
    }
}

Describe 'New-OktaTestLinkedObject' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestConnection {
                @{ OrgUrl = 'https://trial-1.okta.com'; Prefix = 'OKTALAB'
                   EmailDomain = 'oktalab.example.com' }
            }
            Mock Get-OktaTestSeededUser {
                @('awhitfield', 'jnino', 'zmueller', 'talvarez', 'praghunathan' | ForEach-Object {
                    [PSCustomObject]@{
                        id      = "00u$_"
                        profile = [PSCustomObject]@{ login = "$_@oktalab.example.com" }
                    }
                })
            }
            Mock Invoke-OktaTestRequest {
                if ($Method -eq 'GET') { return @() }
                return $null
            }
        }
    }

    It 'creates the definition and all three links' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestLinkedObject -PassThru -Confirm:$false
            $r.LinksCreated | Should-Be 3
        }
    }

    It 'sets the link on the associated user, naming the primary relationship' {
        # This reads backwards until you have seen it: the PUT goes to the mentee and names
        # the mentor. Getting it the wrong way round creates a link that exists and points the
        # wrong way, which nothing would flag.
        InModuleScope OktaTestEnvironment {
            $null = New-OktaTestLinkedObject -PassThru -Confirm:$false

            Should-Invoke Invoke-OktaTestRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -eq '/api/v1/users/00uzmueller/linkedObjects/labMentor/00ujnino'
            }
        }
    }

    It 'skips a link naming a user that does not exist, without failing the definition' {
        InModuleScope OktaTestEnvironment {
            Mock Get-OktaTestSeededUser {
                @([PSCustomObject]@{
                    id = '00ujnino'
                    profile = [PSCustomObject]@{ login = 'jnino@oktalab.example.com' }
                })
            }

            $r = New-OktaTestLinkedObject -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.LinksCreated | Should-Be 0
            @($r.Definitions).Count | Should-Be 1
            @($r.Errors).Count | Should-Be 3
        }
    }

    It 'creates the definition but no links with -SkipLinks' {
        InModuleScope OktaTestEnvironment {
            $r = New-OktaTestLinkedObject -SkipLinks -PassThru -Confirm:$false

            $r.LinksCreated | Should-Be 0
            Should-NotInvoke Invoke-OktaTestRequest -ParameterFilter { $Method -eq 'PUT' }
        }
    }
}
