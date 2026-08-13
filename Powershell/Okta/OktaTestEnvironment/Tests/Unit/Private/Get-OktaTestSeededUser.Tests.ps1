#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    This function decides which users teardown is allowed to delete, so a false positive here
    deletes somebody's real account and there is no recycle bin in Okta to get it back from.

    The tests are therefore mostly about what it must NOT return: a real employee whose login
    happens to start the same way, a user in another lab's prefix, a user with no seed tag
    under a different domain.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OktaTestSeededUser' -Tag 'Unit', 'Private', 'Destructive' {

    BeforeEach {
        InModuleScope OktaTestEnvironment {
            # Built literally rather than through a helper. A function defined inside an
            # InModuleScope block does not survive into the block the mock body runs in, so a
            # helper here fails at call time rather than at definition time.
            Mock Invoke-OktaTestRequest {
                if ($Query -and $Query.filter) { return @() }

                @(
                    # Tagged and under the lab domain: unambiguously ours.
                    [PSCustomObject]@{ id = 'u1'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'awhitfield@oktalab.example.com'; labSeedTag = 'OKTALAB' } }
                    # Under the lab domain but the tag was removed by a half-finished teardown.
                    [PSCustomObject]@{ id = 'u2'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'jnino@oktalab.example.com' } }
                    # Tagged but somebody moved it to another domain.
                    [PSCustomObject]@{ id = 'u3'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'moved@contoso.com'; labSeedTag = 'OKTALAB' } }
                    # A real admin. Neither marker.
                    [PSCustomObject]@{ id = 'u4'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'admin@contoso.com' } }
                    # Another lab sharing the tenant under a different prefix.
                    [PSCustomObject]@{ id = 'u5'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'someone@otherlab.example.com'; labSeedTag = 'CONTOSO' } }
                    # The nastiest one: the seed domain appears as a substring of another.
                    [PSCustomObject]@{ id = 'u6'; status = 'ACTIVE'; profile = [PSCustomObject]@{
                        login = 'trap@notoktalab.example.com.evil.test' } }
                )
            }
        }
    }

    It 'returns the users carrying the seed tag' {
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-ContainCollection 'u1'
        }
    }

    It 'returns users under the seed domain even without the tag' {
        # This is the fallback that makes an interrupted teardown recoverable: if the schema
        # attribute went first, the domain is all that is left to go on.
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-ContainCollection 'u2'
        }
    }

    It 'returns a tagged user that moved off the seed domain' {
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-ContainCollection 'u3'
        }
    }

    It 'leaves a real account with neither marker alone' {
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-NotContainCollection 'u4'
        }
    }

    It 'leaves another lab sharing the tenant alone' {
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-NotContainCollection 'u5'
        }
    }

    It 'matches the domain as a suffix rather than as a substring' {
        # notoktalab.example.com.evil.test contains the seed domain. A -like or -match check
        # would delete it.
        InModuleScope OktaTestEnvironment {
            $found = Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'
            @($found.id) | Should-NotContainCollection 'u6'
        }
    }

    It 'returns each user once even when the two listings overlap' {
        InModuleScope OktaTestEnvironment {
            # Both the default listing and the deprovisioned listing return the same user, as
            # happens when a status changes between the two calls.
            Mock Invoke-OktaTestRequest {
                @([PSCustomObject]@{
                    id      = 'dupe'
                    status  = 'ACTIVE'
                    profile = [PSCustomObject]@{ login = 'x@oktalab.example.com'; labSeedTag = 'OKTALAB' }
                })
            }

            $found = @(Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com')
            $found.Count | Should-Be 1
        }
    }
}
