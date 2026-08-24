#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The decode core. Everything else in the module is built on these three parameter sets, so
    an error here propagates into every finding the risk engine produces.

    The tests are organised around the failure modes that actually occur in the wild rather
    than around the function's structure:

    - Conflating the two numbering systems. RC4 is 23 as a ticket encryption type and bit 4
      as a supported-types flag. A script that tests a ticket etype against 4 finds
      DES-CBC-MD4 and reports every RC4 ticket in the estate as clean. The cross-system tests
      pin both readings of the same integer.

    - Treating the 0xffffffff failure sentinel as a cipher, which turns every failed logon
      into a report line claiming an exotic algorithm.

    - Reading the 0x20 bit as AES256 support. It authorises AES only for the session key, so
      an account holding it and nothing else issues AES session keys inside RC4 tickets.
      Counting it as AES support reports that account as already hardened when it is not.

    - Collapsing "attribute unset" into "supports nothing" or into "supports RC4 only". The
      unset case falls through to the domain default, which by default includes bits that
      neither of those readings would predict.

    The final context cross-checks this module's bitmask decoder against Windows' own
    rendering, which version 2 events carry alongside the raw value. Windows writes
    '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'; if the decoder and the operating system
    disagree about which bits are set, one of them is wrong and it is not the operating
    system.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-KrbEtype' -Tag 'Unit', 'Public', 'Decode' {

    Context 'Ticket encryption type numbers (RFC 3961)' {

        It 'decodes <Value> as <Expected>' -ForEach @(
            @{ Value = '0x17';       Expected = 'RC4-HMAC';                   Family = 'RC4' }
            @{ Value = '0x18';       Expected = 'RC4-HMAC-EXP';               Family = 'RC4' }
            @{ Value = '0x12';       Expected = 'AES256-CTS-HMAC-SHA1-96';    Family = 'AES' }
            @{ Value = '0x11';       Expected = 'AES128-CTS-HMAC-SHA1-96';    Family = 'AES' }
            @{ Value = '0x13';       Expected = 'AES128-CTS-HMAC-SHA256-128'; Family = 'AES' }
            @{ Value = '0x14';       Expected = 'AES256-CTS-HMAC-SHA384-192'; Family = 'AES' }
            @{ Value = '0x1';        Expected = 'DES-CBC-CRC';                Family = 'DES' }
            @{ Value = '0x3';        Expected = 'DES-CBC-MD5';                Family = 'DES' }
        ) {
            $result = ConvertFrom-KrbEtype -TicketEtype $Value

            $result.DisplayName | Should-Be $Expected
            $result.Family | Should-Be $Family
            $result.IsRecognized | Should-BeTrue
        }

        It 'accepts the same value as hex, decimal string and integer' {
            $fromHex = ConvertFrom-KrbEtype -TicketEtype '0x17'
            $fromDecimalString = ConvertFrom-KrbEtype -TicketEtype '23'
            $fromInteger = ConvertFrom-KrbEtype -TicketEtype 23

            $fromHex.DisplayName | Should-Be 'RC4-HMAC'
            $fromDecimalString.DisplayName | Should-Be 'RC4-HMAC'
            $fromInteger.DisplayName | Should-Be 'RC4-HMAC'
        }

        It 'marks RC4 and DES as removed by hardening and AES as surviving' {
            (ConvertFrom-KrbEtype -TicketEtype 23).RemovedByHardening | Should-BeTrue
            (ConvertFrom-KrbEtype -TicketEtype 3).RemovedByHardening | Should-BeTrue
            (ConvertFrom-KrbEtype -TicketEtype 18).RemovedByHardening | Should-BeFalse
        }

        It 'decodes Microsoft proprietary negative etypes advertised by old clients' {
            # A client offering only these and RC4 is a client that predates AES entirely.
            # Decoding them as Unknown would leave the report unable to say what it is
            # looking at, on exactly the machines the project needs to identify.
            (ConvertFrom-KrbEtype -TicketEtype -133).DisplayName | Should-Be 'RC4-HMAC-OLD'
            (ConvertFrom-KrbEtype -TicketEtype -128).DisplayName | Should-Be 'RC4-MD4'
            (ConvertFrom-KrbEtype -TicketEtype -135).DisplayName | Should-Be 'RC4-HMAC-OLD-EXP'
        }

        It 'treats 0xffffffff as no ticket issued, not as an encryption type' {
            # The KDC writes this on every failure event. Read as unsigned it is 4294967295;
            # a report claiming an account used encryption type 4294967295 is a report that
            # decoded a failure as a cipher.
            $result = ConvertFrom-KrbEtype -TicketEtype '0xffffffff'

            $result.Value | Should-Be -1
            $result.Family | Should-Be 'None'
            $result.Strength | Should-Be 'NotApplicable'
            $result.RemovedByHardening | Should-BeFalse
        }

        It 'reports an unrecognised etype as unrecognised rather than dropping it' {
            # A future Windows release adding an encryption type must appear in the output as
            # an explicit unknown. Returning nothing would shorten the pipeline and remove
            # the row from every count without saying so.
            $result = ConvertFrom-KrbEtype -TicketEtype 99

            $result | Should-NotBeNull
            $result.IsRecognized | Should-BeFalse
            $result.DisplayName | Should-MatchString 'Unknown'
            $result.Value | Should-Be 99
        }

        It 'returns a described object for an absent value' -ForEach @(
            @{ Value = $null }
            @{ Value = '' }
            @{ Value = 'N/A' }
            @{ Value = '-' }
        ) {
            $result = ConvertFrom-KrbEtype -TicketEtype $Value

            $result | Should-NotBeNull
            $result.Value | Should-BeNull
            $result.IsRecognized | Should-BeFalse
        }

        It 'accepts pipeline input' {
            $results = @('0x17', '0x12' | ConvertFrom-KrbEtype)

            $results | Should-BeCollection -Count 2
            $results[0].DisplayName | Should-Be 'RC4-HMAC'
            $results[1].DisplayName | Should-Be 'AES256-CTS-HMAC-SHA1-96'
        }
    }

    Context 'Supported encryption type bit flags (MS-KILE 2.2.7)' {

        It 'decodes 0x1C as RC4 plus both AES types' {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 28

            $result.SupportsRc4 | Should-BeTrue
            $result.SupportsAes | Should-BeTrue
            $result.SupportsDes | Should-BeFalse
            $result.EffectiveHex | Should-Be '0x1C'
        }

        It 'decodes 0x18 as AES only' {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 24

            $result.SupportsAes | Should-BeTrue
            $result.SupportsRc4 | Should-BeFalse
            $result.SupportsDes | Should-BeFalse
        }

        It 'maps flags to the ticket encryption types they authorise' {
            # The mapping between the two numbering systems is a table, not arithmetic. This
            # is the assertion that keeps it a table.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 24

            $result.TicketEtypes | Should-BeCollection @(17, 18)
        }

        It 'treats bit 0x20 as session key only, not as AES ticket support' {
            # MS-KILE calls this AES256-CTS-HMAC-SHA1-96-SK. An account holding it issues AES
            # session keys inside tickets encrypted with something else. Counting it as AES
            # support declares such an account already hardened when hardening will break it.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x20

            $result.SupportsAes | Should-BeFalse
            $result.SupportsAesSessionKeyOnly | Should-BeTrue
            $result.TicketEtypes | Should-BeCollection @()
            $result.SessionKeyEtypes | Should-BeCollection @(18)
        }

        It 'does not set SupportsAesSessionKeyOnly when real AES bits are present' {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes (0x20 -bor 0x10)

            $result.SupportsAes | Should-BeTrue
            $result.SupportsAesSessionKeyOnly | Should-BeFalse
        }

        It 'distinguishes an unset attribute from a zero one' {
            # Both fall through to the domain default, but they mean different things: unset
            # is an account nobody has touched, zero is an account somebody zeroed. The
            # report should be able to tell them apart even though their effect is identical.
            $unset = ConvertFrom-KrbEtype -SupportedEncryptionTypes $null
            $zero = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0

            $unset.IsUnset | Should-BeTrue
            $zero.IsUnset | Should-BeFalse

            $unset.UsesDomainDefault | Should-BeTrue
            $zero.UsesDomainDefault | Should-BeTrue
        }

        It 'applies the supplied domain default to an unset attribute' {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes $null `
                -DomainDefaultEncryptionTypes 0x18

            $result.EffectiveValue | Should-Be 24
            $result.SupportsAes | Should-BeTrue
        }

        It 'defaults an unset attribute to the documented Windows default of 0x27' {
            # 0x27 is DES + RC4 + the AES256 session key bit. Neither "supports nothing" nor
            # "supports RC4 only" describes it, and both of those wrong readings are common.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes $null

            $result.EffectiveValue | Should-Be 0x27
            $result.SupportsDes | Should-BeTrue
            $result.SupportsRc4 | Should-BeTrue
            $result.SupportsAes | Should-BeFalse
            $result.SupportsAesSessionKeyOnly | Should-BeTrue
        }

        It 'separates capability bits from cipher bits' {
            # FAST, compound identity and claims ride in the same attribute. Counting them as
            # ciphers would make a FAST-capable RC4-only account look like it supports
            # something it does not.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes (0x04 -bor 0x00010000)

            $result.CipherNames | Should-BeCollection @('RC4-HMAC')
            $result.CapabilityNames | Should-BeCollection @('FAST-Supported')
            $result.SupportsFast | Should-BeTrue
            $result.SupportsAes | Should-BeFalse
        }

        It 'preserves bits it does not recognise instead of masking them away' {
            # Microsoft has added bits to this attribute twice. Silently discarding an
            # unrecognised one would let the module report an account as AES-only when a bit
            # it did not understand says otherwise.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes (0x18 -bor 0x0100)

            $result.UnknownBits | Should-Be 0x0100
            $result.UnknownBitsHex | Should-Be '0x100'
        }

        It 'reports no unknown bits for a fully understood value' {
            (ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x1F).UnknownBits | Should-Be 0
        }

        It 'parses the full rendering a version 2 event writes' {
            # Version 2 events append Windows' own decoding to the value. Requiring callers
            # to strip it by hand is how a decoder ends up with a regex at every call site.
            $result = ConvertFrom-KrbEtype `
                -SupportedEncryptionTypes '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'

            $result.Value | Should-Be 31
            $result.SupportsDes | Should-BeTrue
            $result.SupportsRc4 | Should-BeTrue
            $result.SupportsAes | Should-BeTrue
        }
    }

    Context 'Cross-system confusion' {

        It 'reads the integer 23 differently in each numbering system' {
            # The heart of the matter. 23 is RC4-HMAC as a ticket etype and
            # DES+RC4+AES128 as a bitmask. A module that muddles them produces confident,
            # wrong answers rather than errors.
            $asTicket = ConvertFrom-KrbEtype -TicketEtype 23
            $asFlags = ConvertFrom-KrbEtype -SupportedEncryptionTypes 23

            $asTicket.DisplayName | Should-Be 'RC4-HMAC'

            $asFlags.SupportsDes | Should-BeTrue
            $asFlags.SupportsRc4 | Should-BeTrue
            $asFlags.SupportsAes | Should-BeTrue
        }

        It 'reads the integer 4 as DES-CBC-MD4 by ticket and RC4 by flag' {
            # This is the specific mistake that makes an RC4 audit report a clean estate:
            # testing a ticket encryption type against the RC4 FLAG value of 4.
            (ConvertFrom-KrbEtype -TicketEtype 4).Family | Should-Be 'Unknown'
            (ConvertFrom-KrbEtype -SupportedEncryptionTypes 4).SupportsRc4 | Should-BeTrue
        }

        It 'reads the integer 18 as AES256 by ticket and as DES-MD5 plus AES256 by flag' {
            # 18 decimal is 0x12. As a ticket etype that is AES256-CTS-HMAC-SHA1-96. As a
            # bitmask it is 0x10 + 0x02, which is AES256 and DES-CBC-MD5 - the same AES
            # strength arrived at through completely different arithmetic, with a broken
            # cipher silently included. A convincing coincidence, and a good reason never to
            # let one code path serve both meanings.
            (ConvertFrom-KrbEtype -TicketEtype 18).DisplayName | Should-Be 'AES256-CTS-HMAC-SHA1-96'

            $asFlags = ConvertFrom-KrbEtype -SupportedEncryptionTypes 18
            $asFlags.CipherNames | Should-BeCollection @('DES-CBC-MD5', 'AES256-CTS-HMAC-SHA1-96')
            $asFlags.SupportsDes | Should-BeTrue
        }
    }

    Context 'Client advertised encryption type names' {

        It 'parses the tab-indented block Windows writes' {
            $block = "`n`t`tAES256-CTS-HMAC-SHA1-96`n`t`tRC4-HMAC-NT`n`t`tRC4-HMAC-OLD"
            $result = ConvertFrom-KrbEtype -AdvertizedEtype $block

            $result.Names | Should-BeCollection @(
                'AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT', 'RC4-HMAC-OLD')
            $result.Etypes | Should-BeCollection @(-133, 18, 23)
        }

        It 'uses the Windows spelling, not the RFC spelling' {
            # Windows writes RC4-HMAC-NT where RFC 4757 says rc4-hmac. Matching on the RFC
            # name finds nothing, and finding nothing here reads as "this client advertised
            # no RC4", which is the opposite of the truth.
            $result = ConvertFrom-KrbEtype -AdvertizedEtype 'RC4-HMAC-NT'

            $result.Etypes | Should-BeCollection @(23)
            $result.UnrecognizedNames | Should-BeCollection @()
        }

        It 'flags a client that advertised only legacy types' {
            # The single most actionable output of the whole module: this client cannot
            # authenticate against a hardened KDC, and it is direct evidence rather than an
            # inference from what the KDC happened to choose.
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @(
                'RC4-HMAC-NT', 'RC4-HMAC-OLD', 'RC4-MD4', 'RC4-HMAC-NT-EXP')

            $result.SupportsAes | Should-BeFalse
            $result.LegacyOnly | Should-BeTrue
        }

        It 'does not flag a client that advertised AES alongside RC4' {
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @(
                'AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')

            $result.SupportsAes | Should-BeTrue
            $result.LegacyOnly | Should-BeFalse
        }

        It 'does not flag an empty advertisement as legacy-only' {
            # No advertisement is not the same as an advertisement containing no AES. The
            # first is missing data, the second is a finding.
            $result = ConvertFrom-KrbEtype -AdvertizedEtype ''

            $result.LegacyOnly | Should-BeFalse
            $result.Names | Should-BeCollection @()
        }

        It 'reports unrecognised names rather than discarding them' {
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @('AES256-CTS-HMAC-SHA1-96', 'FUTURE-CIPHER-1')

            $result.UnrecognizedNames | Should-BeCollection @('FUTURE-CIPHER-1')
            $result.SupportsAes | Should-BeTrue
        }

        It 'accepts an already-split array as readily as the raw block' {
            $fromBlock = ConvertFrom-KrbEtype -AdvertizedEtype "AES256-CTS-HMAC-SHA1-96`n`tRC4-HMAC-NT"
            $fromArray = ConvertFrom-KrbEtype -AdvertizedEtype @('AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')

            # @() around the expected value. Should-BeCollection given a bare typed array such
            # as [int[]] fails inside Pester with "Cannot find an overload for new and the
            # argument count 1" rather than with an assertion message, which is a confusing
            # ten minutes for anyone who meets it.
            $fromBlock.Etypes | Should-BeCollection @($fromArray.Etypes)
        }
    }

    Context 'Agreement with the operating system' {

        # Version 2 events carry both the raw bitmask and Windows' own decoding of it. That
        # makes the operating system an independent oracle for this module's bitmask
        # decoder, and these are the only tests in the suite whose expected values were not
        # written by the same person who wrote the code under test.
        #
        # The strings below are exact captures from a Windows Server 2022 domain controller
        # and from the KB5021131 documentation.

        It 'agrees with Windows on <Rendering>' -ForEach @(
            @{
                Rendering = '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'
                Expected  = @('DES-CBC-CRC', 'DES-CBC-MD5', 'RC4-HMAC',
                              'AES128-CTS-HMAC-SHA1-96', 'AES256-CTS-HMAC-SHA1-96')
            }
            @{
                Rendering = '0x1C (RC4, AES128-SHA96, AES256-SHA96)'
                Expected  = @('RC4-HMAC', 'AES128-CTS-HMAC-SHA1-96', 'AES256-CTS-HMAC-SHA1-96')
            }
            @{
                Rendering = '0x4 (RC4)'
                Expected  = @('RC4-HMAC')
            }
            @{
                Rendering = '0x3 (DES)'
                Expected  = @('DES-CBC-CRC', 'DES-CBC-MD5')
            }
            @{
                Rendering = '0x24 (RC4, AES256-SHA96-SK)'
                Expected  = @('RC4-HMAC', 'AES256-CTS-HMAC-SHA1-96-SK')
            }
        ) {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes $Rendering

            $result.CipherNames | Should-BeCollection $Expected
        }

        It 'agrees with Windows that the parsed value matches the hex Windows printed' {
            foreach ($rendering in '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)',
                                   '0x1C (RC4, AES128-SHA96, AES256-SHA96)',
                                   '0x4 (RC4)') {

                $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes $rendering
                $windowsHex = ($rendering -split ' ')[0]

                $result.Hex.ToLowerInvariant() | Should-Be $windowsHex.ToLowerInvariant()
            }
        }
    }

    Context 'Parameter validation' {

        It 'refuses to decode a value in two numbering systems at once' {
            { ConvertFrom-KrbEtype -TicketEtype 23 -SupportedEncryptionTypes 23 } | Should-Throw
        }

        It 'returns the declared PSTypeName for each parameter set' {
            (ConvertFrom-KrbEtype -TicketEtype 23).PSTypeNames[0] |
                Should-Be 'KrbEtypeInsight.TicketEtype'
            (ConvertFrom-KrbEtype -SupportedEncryptionTypes 23).PSTypeNames[0] |
                Should-Be 'KrbEtypeInsight.EtypeFlags'
            (ConvertFrom-KrbEtype -AdvertizedEtype 'RC4-HMAC-NT').PSTypeNames[0] |
                Should-Be 'KrbEtypeInsight.AdvertizedEtypeSet'
        }
    }
}
