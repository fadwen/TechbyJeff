#Requires -Version 7.6

function Get-KrbEtypeCatalog {
    <#
    .SYNOPSIS
        Returns the module's reference tables for Kerberos encryption types

    .DESCRIPTION
        Builds - once per session - the lookup tables that every decode path in the module
        depends on:

        - TicketEtype: RFC 3961 etype number to metadata (display name, algorithm family,
          cryptographic strength band, defining RFC, and whether hardening removes it).
        - AdvertizedName: the literal strings Windows writes into the
          ClientAdvertizedEncryptionTypes field of a version 2 4768/4769 event, mapped back
          to their RFC 3961 numbers.
        - AvailableKeyName: the short key-family strings Windows writes into
          AccountAvailableKeys / ServiceAvailableKeys / DCAvailableKeys.
        - FlagToTicketEtype: the explicit, non-arithmetic mapping from an
          msDS-SupportedEncryptionTypes bit to the ticket etype it authorises.

        The tables are cached in a script-scoped variable. They are pure data with no AD or
        event-log dependency, which is what allows the whole decode layer to be tested
        offline against captured fixtures.

        Why this is a function and not a module-level hashtable literal: a $script: hashtable
        assigned at import time is mutable by any caller who can reach module scope, and a
        single accidental write corrupts every subsequent decode in the session. Building
        through a function lets the tables be constructed once and handed out as a read-only
        wrapper.

    .EXAMPLE
        PS> $catalog = Get-KrbEtypeCatalog
        PS> $catalog.TicketEtype[23].DisplayName

        DESCRIPTION: Resolves the RFC 3961 number 23 to its display name
        OUTPUT: RC4-HMAC
        USE CASE: Decoding a TicketEncryptionType field read from an event

    .EXAMPLE
        PS> (Get-KrbEtypeCatalog).AdvertizedName['RC4-HMAC-NT']

        DESCRIPTION: Maps a Windows advertised-etype string back to its RFC number
        OUTPUT: 23
        USE CASE: Parsing ClientAdvertizedEncryptionTypes from a version 2 event

    .OUTPUTS
        System.Collections.Hashtable

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Unknown etype values: .\Troubleshooting\Common\Unknown-Encryption-Types.md
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:KrbEtypeCatalog) {
        return $script:KrbEtypeCatalog
    }

    Write-Verbose 'Building Kerberos encryption type catalog (first call this session)'

    # A row builder, so each catalog entry below stays one readable line inside the
    # 115-character limit. Written out as full hashtable literals the table is correct and
    # 150 characters wide, which the repository's quality gate rejects and which nobody can
    # read in a side-by-side diff anyway.
    $etype = {
        param([string]$Name, [string]$Family, [string]$Strength, [string]$Rfc, [bool]$Removed)

        @{
            DisplayName        = $Name
            Family             = $Family
            Strength           = $Strength
            Rfc                = $Rfc
            RemovedByHardening = $Removed
        }
    }

    # Strength bands drive the risk engine, not just the display. 'Broken' means the
    # algorithm is cryptanalytically dead and Windows will refuse it once hardened;
    # 'Weak' means it still works but is what the hardening removes; 'Strong' means it
    # survives hardening. The distinction between Broken and Weak matters because a DES
    # finding needs a different remediation from an RC4 finding - DES requires clearing
    # UseDESKeyOnly and a password reset, RC4 usually just needs the attribute widened.
    #
    # Columns:            display name                 family     strength   RFC          removed
    $ticketEtype = @{
        1  = & $etype 'DES-CBC-CRC'                'DES'      'Broken' 'RFC 3961' $true
        2  = & $etype 'DES-CBC-MD4'                'DES'      'Broken' 'RFC 3961' $true
        3  = & $etype 'DES-CBC-MD5'                'DES'      'Broken' 'RFC 3961' $true
        5  = & $etype 'DES3-CBC-MD5'               'DES3'     'Broken' 'RFC 3961' $true
        7  = & $etype 'DES3-CBC-SHA1'              'DES3'     'Broken' 'RFC 3961' $true
        16 = & $etype 'DES3-CBC-SHA1-KD'           'DES3'     'Broken' 'RFC 3961' $true
        17 = & $etype 'AES128-CTS-HMAC-SHA1-96'    'AES'      'Strong' 'RFC 3962' $false
        18 = & $etype 'AES256-CTS-HMAC-SHA1-96'    'AES'      'Strong' 'RFC 3962' $false
        19 = & $etype 'AES128-CTS-HMAC-SHA256-128' 'AES'      'Strong' 'RFC 8009' $false
        20 = & $etype 'AES256-CTS-HMAC-SHA384-192' 'AES'      'Strong' 'RFC 8009' $false
        23 = & $etype 'RC4-HMAC'                   'RC4'      'Weak'   'RFC 4757' $true
        24 = & $etype 'RC4-HMAC-EXP'               'RC4'      'Weak'   'RFC 4757' $true
        25 = & $etype 'CAMELLIA128-CTS-CMAC'       'Camellia' 'Strong' 'RFC 6803' $false
        26 = & $etype 'CAMELLIA256-CTS-CMAC'       'Camellia' 'Strong' 'RFC 6803' $false

        # Microsoft-proprietary negatives. A client that advertises these and nothing else
        # is a client that predates AES support entirely.
        -128 = & $etype 'RC4-MD4'          'RC4' 'Broken' 'Microsoft proprietary' $true
        -133 = & $etype 'RC4-HMAC-OLD'     'RC4' 'Broken' 'Microsoft proprietary' $true
        -135 = & $etype 'RC4-HMAC-OLD-EXP' 'RC4' 'Broken' 'Microsoft proprietary' $true

        # The failure sentinel. See KrbEtypeEnum.ps1 for why this is modelled rather than
        # decoded as a number.
        -1 = & $etype 'None (no ticket issued)' 'None' 'NotApplicable' 'n/a' $false
    }

    # The exact literals Windows writes, one per line and tab-indented, into
    # ClientAdvertizedEncryptionTypes. Note that Windows says 'RC4-HMAC-NT' where the RFC
    # says 'rc4-hmac' - matching on the RFC spelling finds nothing.
    $advertizedName = @{
        'DES-CBC-CRC'                = 1
        'DES-CBC-MD4'                = 2
        'DES-CBC-MD5'                = 3
        'DES3-CBC-SHA1'              = 16
        'AES128-CTS-HMAC-SHA1-96'    = 17
        'AES256-CTS-HMAC-SHA1-96'    = 18
        'AES128-CTS-HMAC-SHA256-128' = 19
        'AES256-CTS-HMAC-SHA384-192' = 20
        'RC4-HMAC-NT'                = 23
        'RC4-HMAC-NT-EXP'            = 24
        'RC4-MD4'                    = -128
        'RC4-HMAC-OLD'               = -133
        'RC4-HMAC-OLD-EXP'           = -135
    }

    # AccountAvailableKeys / ServiceAvailableKeys report which key MATERIAL exists on the
    # account in AD, derived from the password at the time it was last set. This is a
    # different question from what the account is configured to support, and it is the
    # question that actually predicts breakage: an account whose msDS-SupportedEncryptionTypes
    # says AES but whose available keys are RC4-only has no AES key to issue a ticket with.
    $availableKeyName = @{
        'DES'      = @{ Family = 'DES'; TicketEtypes = @(1, 3) }
        'RC4'      = @{ Family = 'RC4'; TicketEtypes = @(23, 24) }
        'AES-SHA1' = @{ Family = 'AES'; TicketEtypes = @(17, 18) }
        'AES-SHA2' = @{ Family = 'AES'; TicketEtypes = @(19, 20) }
    }

    # The mapping the module refuses to compute. Note 0x20: it authorises AES256 for the
    # session key only, so it maps to etype 18 for session-key purposes and to nothing for
    # ticket purposes. TicketEtypes and SessionKeyEtypes are therefore separate lists.
    $flagToTicketEtype = @{
        0x00000001 = @{ Name = 'DES-CBC-CRC';                TicketEtypes = @(1);  SessionKeyEtypes = @(1)  }
        0x00000002 = @{ Name = 'DES-CBC-MD5';                TicketEtypes = @(3);  SessionKeyEtypes = @(3)  }
        0x00000004 = @{ Name = 'RC4-HMAC';                   TicketEtypes = @(23); SessionKeyEtypes = @(23) }
        0x00000008 = @{ Name = 'AES128-CTS-HMAC-SHA1-96';    TicketEtypes = @(17); SessionKeyEtypes = @(17) }
        0x00000010 = @{ Name = 'AES256-CTS-HMAC-SHA1-96';    TicketEtypes = @(18); SessionKeyEtypes = @(18) }
        0x00000020 = @{ Name = 'AES256-CTS-HMAC-SHA1-96-SK'; TicketEtypes = @();   SessionKeyEtypes = @(18) }
        # TicketEtypes deliberately EMPTY, on observed evidence rather than on the spec.
        #
        # MS-KILE documents these as the RFC 8009 SHA-2 types, and this module originally
        # mapped them to etypes 19 and 20 accordingly. A Windows Server 2025 KDC (build 26100)
        # tested directly does not honour them: an account carrying only 0x80 could not obtain
        # a service ticket at all - KDC_ERR_ETYPE_NOTSUPP - and an account carrying 0x80|0x10
        # was issued a ticket under etype 0x12, the SHA1 type, with the 0x80 bit contributing
        # nothing.
        #
        # Claiming a ticket etype here is therefore not a harmless overstatement: it made
        # SupportsAes true for an account that cannot authenticate, so the risk engine reported
        # a dead account as safe. An empty list is the honest reading of what Windows does. The
        # names are retained so the bits are still identified in a report, and
        # CarriesUnhonouredSha2Bits below surfaces the discrepancy explicitly.
        0x00000040 = @{ Name = 'AES128-CTS-HMAC-SHA256-128'; TicketEtypes = @(); SessionKeyEtypes = @() }
        0x00000080 = @{ Name = 'AES256-CTS-HMAC-SHA384-192'; TicketEtypes = @(); SessionKeyEtypes = @() }

        # Capability bits. Deliberately carry empty etype lists so that any code summing
        # TicketEtypes across set bits cannot mistake a FAST-capable account for a
        # cipher-capable one.
        0x00010000 = @{ Name = 'FAST-Supported';                    TicketEtypes = @(); SessionKeyEtypes = @() }
        0x00020000 = @{ Name = 'Compound-Identity-Supported';       TicketEtypes = @(); SessionKeyEtypes = @() }
        0x00040000 = @{ Name = 'Claims-Supported';                  TicketEtypes = @(); SessionKeyEtypes = @() }
        0x00080000 = @{ Name = 'Resource-SID-Compression-Disabled'; TicketEtypes = @(); SessionKeyEtypes = @() }
    }

    $script:KrbEtypeCatalog = @{
        TicketEtype       = $ticketEtype
        AdvertizedName    = $advertizedName
        AvailableKeyName  = $availableKeyName
        FlagToTicketEtype = $flagToTicketEtype

        # Precomputed once, because the alternative is a Sort-Object pipeline inside the
        # bitmask decoder, which then runs once per event. At the volumes this module is
        # built for that single sort was measured at roughly a third of total decode time -
        # a cmdlet invocation is expensive relative to a loop over thirteen integers, and
        # the answer never changes.
        SortedFlagKeys    = [int[]]@($flagToTicketEtype.Keys | Sort-Object)

        # Separator set for the ClientAdvertizedEncryptionTypes block, which Windows writes
        # as newline-and-tab indented text. String.Split with a char array avoids compiling
        # a regex per event.
        AdvertizedSeparator = [char[]]@("`r", "`n", "`t", ',')

        # Every bit this module knows about, for detecting the ones it does not. Cast to
        # [int] because Measure-Object returns a [double], and -bnot on a double is a
        # parameter binding error rather than a bitwise complement.
        KnownFlagMask     = [int](($flagToTicketEtype.Keys | Measure-Object -Sum).Sum)

        # Bits that represent a cipher rather than a capability. Used wherever the question
        # is "what can this principal actually encrypt with".
        CipherFlagMask    = 0x000000FF

        # MS-KILE: when msDS-SupportedEncryptionTypes is absent or zero, the KDC falls back
        # to the DefaultDomainSupportedEncTypes registry value on the DC, whose own default
        # is 0x27. Anything that reads a null attribute as "supports nothing" is wrong, and
        # anything that reads it as "supports RC4 only" is also wrong - 0x27 includes the
        # AES256 session-key bit.
        DefaultDomainSupportedEncTypes = 0x27
    }

    return $script:KrbEtypeCatalog
}
