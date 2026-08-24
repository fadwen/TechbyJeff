#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Client address normalisation.

    Small function, but it decides the blast-radius numbers in every report. The KDC writes a
    client address in whichever form the socket presented, so one physical host arrives as
    '::ffff:10.20.30.40' over a v6 socket and '10.20.30.40' over a v4 one. Counting "which
    clients will break" means counting distinct clients, so those have to collapse to one key
    before the group-by - left unnormalised, a single legacy application server reports as two
    or three affected clients and every impact figure in the assessment is inflated.

    The narrowness of the unwrapping rule is the other thing worth pinning. A broader "strip
    everything before the last colon" would turn a genuine IPv6 address into its final hextet,
    which silently merges unrelated hosts instead of splitting one.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-KrbClientAddress' -Tag 'Unit', 'Private' {

    Context 'IPv4-mapped IPv6 unwrapping' {

        It 'unwraps <Value> to <Expected>' -ForEach @(
            @{ Value = '::ffff:10.20.30.40';  Expected = '10.20.30.40' }
            @{ Value = '::ffff:192.168.1.1';  Expected = '192.168.1.1' }
            @{ Value = '::ffff:8.8.8.8';      Expected = '8.8.8.8' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value; Expected = $Expected } {
                ConvertTo-KrbClientAddress -Value $Value | Should-Be $Expected
            }
        }

        It 'collapses both forms of one host to the same key' {
            # The property the blast-radius count depends on.
            InModuleScope KrbEtypeInsight {
                $mapped = ConvertTo-KrbClientAddress -Value '::ffff:10.20.30.40'
                $plain = ConvertTo-KrbClientAddress -Value '10.20.30.40'

                $mapped | Should-Be $plain
            }
        }
    }

    Context 'Addresses that must be left alone' {

        It 'leaves <Value> unchanged' -ForEach @(
            @{ Value = '10.20.30.40' }
            @{ Value = '::1' }
            @{ Value = 'fe80::1c2d:3e4f:5a6b:7c8d' }
            @{ Value = '2001:db8::42' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value } {
                ConvertTo-KrbClientAddress -Value $Value | Should-Be $Value
            }
        }

        It 'does not mangle a real IPv6 address into its last hextet' {
            # A "strip everything before the last colon" rule would return '7c8d' here and
            # merge every host on the subnet into one apparent client.
            InModuleScope KrbEtypeInsight {
                $result = ConvertTo-KrbClientAddress -Value 'fe80::1c2d:3e4f:5a6b:7c8d'

                $result | Should-Be 'fe80::1c2d:3e4f:5a6b:7c8d'
                $result | Should-NotBe '7c8d'
            }
        }

        It 'preserves the loopback marker for requests made on the controller itself' {
            # Worth keeping distinguishable so DC-local traffic can be excluded from a client
            # impact count rather than counted as an affected machine.
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbClientAddress -Value '::1' | Should-Be '::1'
            }
        }
    }

    Context 'Absent values' {

        It 'returns null for <Description>' -ForEach @(
            @{ Value = $null;  Description = 'a null value' }
            @{ Value = '';     Description = 'an empty string' }
            @{ Value = '   ';  Description = 'whitespace' }
            @{ Value = '-';    Description = 'the KDC not-recorded marker' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value } {
                ConvertTo-KrbClientAddress -Value $Value | Should-BeNull
            }
        }

        It 'trims surrounding whitespace rather than treating it as part of the address' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbClientAddress -Value '  10.20.30.40  ' | Should-Be '10.20.30.40'
            }
        }
    }
}
