#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Every numeric field in the module passes through this function, so its edge cases are the
    module's edge cases.

    Three of them are worth stating outright, because each has a plausible-looking wrong
    answer:

    - 0xffffffff must become -1. Read as unsigned it is 4294967295, which overflows Int32; a
      plain [int] cast throws. The KDC writes it on every failure event, so the wrong answer
      here is either a crash on the first failed logon in the collection, or a report line
      claiming an account used encryption type 4294967295.

    - 'N/A' must become $null, not 0. Zero is a real and meaningful value for
      msDS-SupportedEncryptionTypes - it means "use the domain default" - so coercing an
      unpopulated field to zero fabricates a configuration statement the KDC never made.

    - '0x1F (DES, RC4, ...)' must become 31. Version 2 events append Windows' own decoding to
      the value, and the function has to ignore it rather than failing to parse.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-KrbInt32' -Tag 'Unit', 'Private' {

    Context 'Hex parsing' {

        It 'parses <Value> as <Expected>' -ForEach @(
            @{ Value = '0x0';  Expected = 0 }
            @{ Value = '0x4';  Expected = 4 }
            @{ Value = '0x12'; Expected = 18 }
            @{ Value = '0x17'; Expected = 23 }
            @{ Value = '0x1C'; Expected = 28 }
            @{ Value = '0x1F'; Expected = 31 }
            @{ Value = '0x27'; Expected = 39 }
            @{ Value = '0X12'; Expected = 18 }
            @{ Value = '0x1f'; Expected = 31 }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value; Expected = $Expected } {
                ConvertTo-KrbInt32 -Value $Value | Should-Be $Expected
            }
        }

        It 'strips the description Windows appends in version 2 events' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)' |
                    Should-Be 31
            }
        }

        It 'reinterprets 0xffffffff as -1 rather than overflowing' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value '0xffffffff' | Should-Be -1
            }
        }

        It 'reinterprets the decimal spelling of the same sentinel' {
            # The value reaches the module as a string from the event log and as a number
            # from other producers. Both have to land on -1.
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value '4294967295' | Should-Be -1
                ConvertTo-KrbInt32 -Value ([long]4294967295) | Should-Be -1
            }
        }

        It 'rejects a hex value too wide to be a 32-bit encryption type' {
            # Truncating would fabricate a reading. Returning null makes the caller decide.
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value '0x1FFFFFFFF' | Should-BeNull
            }
        }
    }

    Context 'Null-ish input' {

        It 'returns null for <Description>' -ForEach @(
            @{ Value = $null;  Description = 'a null value' }
            @{ Value = '';     Description = 'an empty string' }
            @{ Value = '   ';  Description = 'whitespace' }
            @{ Value = 'N/A';  Description = 'the KDC not-applicable marker' }
            @{ Value = '-';    Description = 'the KDC absent marker' }
            @{ Value = 'Unknown'; Description = 'the unknown marker' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value } {
                ConvertTo-KrbInt32 -Value $Value | Should-BeNull
            }
        }

        It 'does not confuse an absent value with zero' {
            # The distinction the risk engine depends on. Zero means "use the domain
            # default"; absent means the field was never written. Collapsing them makes a
            # legacy-schema event indistinguishable from an explicitly zeroed account.
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value 'N/A' | Should-BeNull
                ConvertTo-KrbInt32 -Value '0' | Should-Be 0
                ConvertTo-KrbInt32 -Value '0x0' | Should-Be 0
            }
        }

        It 'returns null for text that is not a number at all' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value 'not-a-number' | Should-BeNull
            }
        }
    }

    Context 'Native types' {

        It 'passes an integer through unchanged' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value 28 | Should-Be 28
                ConvertTo-KrbInt32 -Value -1 | Should-Be -1
            }
        }

        It 'accepts a value that Get-ADObject widened to [long]' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value ([long]28) | Should-Be 28
            }
        }

        It 'returns an [int]' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbInt32 -Value '0x12' | Should-HaveType ([int])
            }
        }
    }

    Context 'Pipeline' {

        It 'accepts values from the pipeline' {
            InModuleScope KrbEtypeInsight {
                $result = @('0x12', '0x17', 'N/A' | ConvertTo-KrbInt32)

                $result | Should-BeCollection -Count 3
                $result[0] | Should-Be 18
                $result[1] | Should-Be 23
                $result[2] | Should-BeNull
            }
        }
    }
}
