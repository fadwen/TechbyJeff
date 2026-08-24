#Requires -Version 7.6

<#
.SYNOPSIS
    Generates the synthetic Kerberos audit event XML fixtures used by the unit tests

.DESCRIPTION
    Writes one .xml file per scenario into this folder. The fixtures exist because the
    interesting cases cannot be obtained from a real domain:

    - A domain healthy enough to run this tooling on does not issue RC4 tickets, does not
      hold DES-only accounts that authenticate, and does not have clients advertising no AES.
      Those are exactly the cases the risk engine is written to detect.
    - Version 0 and version 1 audit schemas come from domain controllers predating the
      November 2022 update. Once an estate is patched, no machine can produce them again -
      but the module still has to decode archived logs that contain them, and has to degrade
      its confidence rather than silently reporting nulls as negatives.
    - Failure events carrying KDC_ERR_ETYPE_NOTSUPP require actually breaking authentication
      to produce, which is not something a test suite should arrange.

    The fixture XML is byte-for-byte the shape EventLogRecord.ToXml() emits, including the
    default namespace, the tab-indented ClientAdvertizedEncryptionTypes block and the
    '0x1F (DES, RC4, ...)' rendering Windows appends to the supported-types fields. It was
    derived from real events captured on a Windows Server 2022 domain controller, then edited
    to produce each scenario. Anything less faithful would test the fixture format rather
    than the decoder.

    Re-run this script after editing a scenario. It is deliberately committed alongside the
    fixtures it produces, so a reviewer can see how each one differs from a real event
    instead of having to diff twenty XML files by eye.

.EXAMPLE
    PS> .\New-KrbFixture.ps1

    DESCRIPTION: Regenerates every fixture in place
    OUTPUT: One .xml file per scenario, plus a manifest listing what each one covers
    USE CASE: After adding a scenario or correcting a captured field

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Path = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# Fixed timestamps. Get-Date here would make every regeneration produce a different file and
# turn the fixtures into a permanent source of diff noise, and would make any test that
# asserts on a time window depend on when it was run.
$baseTime = [datetime]::Parse('2026-07-15T09:30:00.0000000Z', [cultureinfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::RoundtripKind)

$domain = 'AD.TECHBYJEFF.NET'
$dc = 'DC01.ad.techbyjeff.net'
$domainSid = 'S-1-5-21-1111111111-2222222222-3333333333'

function New-KrbEventXml {
    <#
    .SYNOPSIS
        Builds one event XML document in the exact shape the event log service emits
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a string. The file writes are guarded by the script-level ShouldProcess.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][int]$EventId,
        [Parameter(Mandatory)][int]$Version,
        [Parameter(Mandatory)][hashtable]$Data,
        [Parameter()][int]$MinutesOffset = 0,
        [Parameter()][long]$RecordId = 1000000
    )

    $task = switch ($EventId) { 4768 { 14339 } 4769 { 14337 } 4771 { 14339 } default { 0 } }
    $stamp = $baseTime.AddMinutes($MinutesOffset).ToString('yyyy-MM-ddTHH:mm:ss.fffffff0Z')

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>")
    [void]$sb.Append('<System>')
    [void]$sb.Append("<Provider Name='Microsoft-Windows-Security-Auditing' " +
        "Guid='{54849625-5478-4994-a5ba-3e3b0328c30d}'/>")
    [void]$sb.Append("<EventID>$EventId</EventID>")

    # Version 0 records genuinely omit the element rather than writing a zero. Emitting
    # <Version>0</Version> would make the fixture easier to build and would stop it testing
    # the missing-element path, which is the one that throws if handled carelessly.
    if ($Version -gt 0) { [void]$sb.Append("<Version>$Version</Version>") }

    [void]$sb.Append("<Level>0</Level><Task>$task</Task><Opcode>0</Opcode>")
    [void]$sb.Append('<Keywords>0x8020000000000000</Keywords>')
    [void]$sb.Append("<TimeCreated SystemTime='$stamp'/>")
    [void]$sb.Append("<EventRecordID>$RecordId</EventRecordID>")
    [void]$sb.Append('<Correlation/><Execution ProcessID="996" ThreadID="1268"/>')
    [void]$sb.Append("<Channel>Security</Channel><Computer>$dc</Computer><Security/>")
    [void]$sb.Append('</System><EventData>')

    foreach ($name in $Data.Keys) {
        $value = [System.Security.SecurityElement]::Escape([string]$Data[$name])
        [void]$sb.Append("<Data Name='$name'>$value</Data>")
    }

    [void]$sb.Append('</EventData></Event>')
    $sb.ToString()
}

# Windows writes the advertised list newline-separated and tab-indented. Reproduced exactly,
# because the decoder's splitting logic is one of the things under test.
function Get-AdvertizedBlock {
    param([string[]]$Name)
    "`n`t`t" + ($Name -join "`n`t`t")
}

$v2Common = @{
    DCSupportedEncryptionTypes = '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'
    DCAvailableKeys            = 'AES-SHA1, RC4'
}

$scenarios = @(

    # ------------------------------------------------------------------ healthy baseline
    @{
        File    = '4769-v2-healthy-aes.xml'
        Covers  = 'Version 2 service ticket, AES256 throughout, client advertises AES. The control case.'
        Xml     = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000001 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'svc-payroll'
            ServiceSid       = "$domainSid-2101"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x12'
            IpAddress        = '::ffff:10.20.30.40'
            IpPort           = '52104'
            Status           = '0x0'
            LogonGuid        = '{7a6e6fe3-10b6-3f59-e347-f39a3b393a0e}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x1C (RC4, AES128-SHA96, AES256-SHA96)'
            ServiceAvailableKeys = 'AES-SHA1, RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA1-96', 'AES128-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')
            SessionKeyEncryptionType = '0x12'
        })
    }

    # -------------------------------------------------- service with no AES key material
    # The headline case. msDS-SupportedEncryptionTypes says RC4+AES, the ticket is RC4, and
    # ServiceAvailableKeys proves no AES key was ever derived. Hardening this account without
    # first resetting its password produces KDC_ERR_NULL_KEY.
    @{
        File   = '4769-v2-service-no-aes-key.xml'
        Covers = 'Version 2 service ticket, RC4 ticket, ServiceAvailableKeys shows RC4 only - KRB002.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000002 -MinutesOffset 5 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'MSSQLSvc/legacydb01.ad.techbyjeff.net:1433'
            ServiceSid       = "$domainSid-2102"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.30.40'
            IpPort           = '52110'
            Status           = '0x0'
            LogonGuid        = '{7a6e6fe3-10b6-3f59-e347-f39a3b393a0e}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x1C (RC4, AES128-SHA96, AES256-SHA96)'
            ServiceAvailableKeys = 'RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA1-96', 'AES128-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')
            SessionKeyEncryptionType = '0x17'
        })
    }

    # ------------------------------------------------------- client that cannot do AES
    @{
        File   = '4768-v2-legacy-client.xml'
        Covers = 'Version 2 TGT request from a client advertising only RC4 and proprietary types - KRB005.'
        Xml    = New-KrbEventXml -EventId 4768 -Version 2 -RecordId 1000003 -MinutesOffset 1 -Data ([ordered]@{
            TargetUserName   = 'APPLIANCE-SCAN01$'
            TargetDomainName = $domain
            TargetSid        = "$domainSid-3301"
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x40810010'
            Status           = '0x0'
            TicketEncryptionType = '0x17'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.30.77'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
            AccountSupportedEncryptionTypes = '0x4 (RC4)'
            AccountAvailableKeys = 'RC4'
            ServiceSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            ServiceAvailableKeys = $v2Common.DCAvailableKeys
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'RC4-HMAC-NT', 'RC4-HMAC-OLD', 'RC4-MD4', 'RC4-HMAC-NT-EXP', 'RC4-HMAC-OLD-EXP')
            SessionKeyEncryptionType = '0x17'
            PreAuthEncryptionType = '0x17'
        })
    }

    # The same legacy client requesting the payroll service, so the correlation between a
    # client's advertisement and a service's dependency list has something to join on.
    @{
        File   = '4769-v2-legacy-client-to-service.xml'
        Covers = 'The legacy client above requesting svc-payroll, joining KRB005 to a named service.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000004 -MinutesOffset 2 -Data ([ordered]@{
            TargetUserName   = "APPLIANCE-SCAN01`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'svc-payroll'
            ServiceSid       = "$domainSid-2101"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.30.77'
            IpPort           = '52200'
            Status           = '0x0'
            LogonGuid        = '{1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x1C (RC4, AES128-SHA96, AES256-SHA96)'
            ServiceAvailableKeys = 'AES-SHA1, RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'RC4-HMAC-NT', 'RC4-HMAC-OLD', 'RC4-MD4', 'RC4-HMAC-NT-EXP', 'RC4-HMAC-OLD-EXP')
            SessionKeyEncryptionType = '0x17'
        })
    }

    # ------------------------------------------------------------------------- DES in use
    @{
        File   = '4769-v2-des-ticket.xml'
        Covers = 'Version 2 service ticket issued under DES-CBC-MD5 - KRB007.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000005 -MinutesOffset 10 -Data ([ordered]@{
            TargetUserName   = "OLDHOST-07`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'svc-desonly'
            ServiceSid       = "$domainSid-2103"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x3'
            IpAddress        = '10.20.30.99'
            IpPort           = '49881'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x3 (DES)'
            ServiceAvailableKeys = 'DES'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @('DES-CBC-MD5', 'DES-CBC-CRC')
            SessionKeyEncryptionType = '0x3'
        })
    }

    # ------------------------------------------------ already-failing etype negotiation
    @{
        File   = '4771-etype-notsupp.xml'
        Covers = 'Pre-authentication failure with KDC_ERR_ETYPE_NOTSUPP - KRB011, breakage already happening.'
        Xml    = New-KrbEventXml -EventId 4771 -Version 0 -RecordId 1000006 -MinutesOffset 15 -Data ([ordered]@{
            TargetUserName   = 'APPLIANCE-SCAN01$'
            TargetSid        = "$domainSid-3301"
            ServiceName      = 'krbtgt/AD.TECHBYJEFF.NET'
            TicketOptions    = '0x40810010'
            Status           = '0xE'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.30.77'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
        })
    }

    # -------------------------------------------- KDC_ERR_NULL_KEY, the AES-only mistake
    @{
        File   = '4771-null-key.xml'
        Covers = 'KDC_ERR_NULL_KEY - an account set to AES-only whose password predates the change.'
        Xml    = New-KrbEventXml -EventId 4771 -Version 0 -RecordId 1000007 -MinutesOffset 16 -Data ([ordered]@{
            TargetUserName   = 'svc-batchjob'
            TargetSid        = "$domainSid-2104"
            ServiceName      = 'krbtgt/AD.TECHBYJEFF.NET'
            TicketOptions    = '0x40810010'
            Status           = '0x9'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.31.15'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
        })
    }

    # ------------------------------------------------------------- legacy schema, no detail
    # A version 0 4769 from a controller predating KB5021131. Every field the risk engine
    # prefers is simply absent, and the engine must lower its confidence rather than read the
    # absences as negatives.
    @{
        File   = '4769-v0-legacy-schema.xml'
        Covers = 'Version 0 service ticket - no advertised, supported or available-key fields at all.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 0 -RecordId 1000008 -MinutesOffset 20 -Data ([ordered]@{
            TargetUserName   = "WKS-LEGACY-11`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'svc-fileshare'
            ServiceSid       = "$domainSid-2105"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.32.11'
            IpPort           = '51002'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
        })
    }

    @{
        File   = '4768-v1-legacy-schema.xml'
        Covers = 'Version 1 TGT request - has TicketEncryptionType but none of the KB5021131 additions.'
        Xml    = New-KrbEventXml -EventId 4768 -Version 1 -RecordId 1000009 -MinutesOffset 21 -Data ([ordered]@{
            TargetUserName   = 'WKS-LEGACY-11$'
            TargetDomainName = $domain
            TargetSid        = "$domainSid-3302"
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x40810010'
            Status           = '0x0'
            TicketEncryptionType = '0x17'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.32.11'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
        })
    }

    # ----------------------------------------------------- the no-ticket-issued sentinel
    @{
        File   = '4768-v2-failed-0xffffffff.xml'
        Covers = 'Failed TGT request where TicketEncryptionType is the 0xffffffff sentinel, not a cipher.'
        Xml    = New-KrbEventXml -EventId 4768 -Version 2 -RecordId 1000010 -MinutesOffset 25 -Data ([ordered]@{
            TargetUserName   = 'svc-expired'
            TargetDomainName = $domain
            TargetSid        = "$domainSid-2106"
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x40810010'
            Status           = '0x18'
            TicketEncryptionType = '0xffffffff'
            PreAuthType      = '0'
            IpAddress        = '::ffff:10.20.33.5'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = 'N/A'
            ServiceAvailableKeys = 'N/A'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = 'N/A'
            SessionKeyEncryptionType = '0xffffffff'
        })
    }

    # ------------------------------------------------------ hostile input in a field
    # A service principal name is chosen by whoever makes the request, so it is attacker
    # controlled by construction. This fixture keeps the LDAP escaping and the HTML encoding
    # honest.
    @{
        File   = '4769-v2-hostile-spn.xml'
        Covers = 'Service name containing LDAP filter metacharacters and HTML markup.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000011 -MinutesOffset 30 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'HOST/*)(objectClass=*)<script>alert(1)</script>'
            ServiceSid       = "$domainSid-2107"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.30.40'
            IpPort           = '52999'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x4 (RC4)'
            ServiceAvailableKeys = 'RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')
            SessionKeyEncryptionType = '0x17'
        })
    }

    # ---------------------------------------------------- AES256 session key only (0x20)
    # An account carrying only bit 0x20 gets an AES session key inside a non-AES ticket. A
    # decoder that reads 0x20 as "supports AES256" reports this account as already hardened.
    @{
        File   = '4769-v2-aes-session-key-only.xml'
        Covers = 'RC4 ticket with an AES256 session key, from an account holding only the 0x20 bit.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000012 -MinutesOffset 35 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'svc-sessionkey'
            ServiceSid       = "$domainSid-2108"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.30.40'
            IpPort           = '53001'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x24 (RC4, AES256-SHA96-SK)'
            ServiceAvailableKeys = 'AES-SHA1, RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')
            SessionKeyEncryptionType = '0x12'
        })
    }

    # --------------------------------------------- RFC 8009 SHA-2 AES, newer than the target
    # A client on Windows Server 2025 presenting AES256-CTS-HMAC-SHA384-192. The default
    # target 0x18 does not name etype 20, so an exact-membership comparison classifies the
    # strongest cipher Windows issues as "removed by the change" and raises a Critical against
    # the most modern machine in the estate. Regression fixture for that inversion.
    @{
        File   = '4768-v2-sha2-aes-client.xml'
        Covers = 'Client using RFC 8009 AES-SHA2, stronger than the default target - must not be flagged.'
        Xml    = New-KrbEventXml -EventId 4768 -Version 2 -RecordId 1000013 -MinutesOffset 40 -Data ([ordered]@{
            TargetUserName   = 'WS2025-APP01$'
            TargetDomainName = $domain
            TargetSid        = "$domainSid-3401"
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x40810010'
            Status           = '0x0'
            TicketEncryptionType = '0x14'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.34.10'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
            AccountSupportedEncryptionTypes = '0xC0 (AES128-SHA256, AES256-SHA384)'
            AccountAvailableKeys = 'AES-SHA2'
            ServiceSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            ServiceAvailableKeys = $v2Common.DCAvailableKeys
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA384-192', 'AES128-CTS-HMAC-SHA256-128')
            SessionKeyEncryptionType = '0x14'
            PreAuthEncryptionType = '0x14'
        })
    }

    # ------------------------------------------------- advertisement this catalog cannot name
    # Every advertised name is unrecognised. That is missing knowledge, not evidence of
    # incapability, and must not resolve to "advertises no AES support".
    @{
        File   = '4768-v2-unknown-cipher-client.xml'
        Covers = 'Client advertising only unrecognised ciphers - unknown, not legacy-only.'
        Xml    = New-KrbEventXml -EventId 4768 -Version 2 -RecordId 1000014 -MinutesOffset 45 -Data ([ordered]@{
            TargetUserName   = 'FUTURE-CLIENT01$'
            TargetDomainName = $domain
            TargetSid        = "$domainSid-3402"
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x40810010'
            Status           = '0x0'
            TicketEncryptionType = '0x12'
            PreAuthType      = '2'
            IpAddress        = '::ffff:10.20.34.20'
            IpPort           = '0'
            CertIssuerName   = ''
            CertSerialNumber = ''
            CertThumbprint   = ''
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            ServiceAvailableKeys = $v2Common.DCAvailableKeys
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES512-CTS-HMAC-SHA3-256', 'SOME-FUTURE-CIPHER')
            SessionKeyEncryptionType = '0x12'
            PreAuthEncryptionType = '0x12'
        })
    }

    # ------------------------------------------------------------- cross-realm referral
    # A 4769 whose ServiceName is krbtgt/OTHERREALM. The bare 'krbtgt' form is a local TGT
    # renewal and is excluded from service assessment; this form is a referral over a trust
    # and is the best evidence available that the trust still forces RC4.
    @{
        File   = '4769-v2-crossrealm-referral.xml'
        Covers = 'Cross-realm referral. ServiceName is the BARE REALM, measured on a real forest trust.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000015 -MinutesOffset 50 -Data ([ordered]@{
            TargetUserName   = "USER01@$domain"
            TargetDomainName = $domain
            ServiceName      = 'LAB.CONTOSO.TEST'
            # RID 0. A referral names a realm, not a principal, so the KDC writes the domain
            # SID with a zero RID rather than a real account SID.
            ServiceSid       = "$domainSid-0"
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0x17'
            IpAddress        = '::ffff:10.20.35.5'
            IpPort           = '51500'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = '0x4 (RC4)'
            ServiceAvailableKeys = 'RC4'
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @(
                'AES256-CTS-HMAC-SHA1-96', 'RC4-HMAC-NT')
            SessionKeyEncryptionType = '0x17'
        })
    }

    # ------------------------------------------- local TGT renewal, must NOT become a service
    @{
        File   = '4769-v2-krbtgt-renewal.xml'
        Covers = 'TGT renewal - a 4769 naming bare krbtgt, which must not produce a service row.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000016 -MinutesOffset 55 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'krbtgt'
            ServiceSid       = "$domainSid-502"
            TicketOptions    = '0x60810010'
            TicketEncryptionType = '0x12'
            IpAddress        = '::ffff:10.20.30.40'
            IpPort           = '52400'
            Status           = '0x0'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = 'N/A'
            AccountAvailableKeys = 'N/A'
            ServiceSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            ServiceAvailableKeys = $v2Common.DCAvailableKeys
            DCSupportedEncryptionTypes = $v2Common.DCSupportedEncryptionTypes
            DCAvailableKeys  = $v2Common.DCAvailableKeys
            ClientAdvertizedEncryptionTypes = Get-AdvertizedBlock @('AES256-CTS-HMAC-SHA1-96')
            SessionKeyEncryptionType = '0x12'
        })
    }

    # ------------------------------------------- real KDC failure shape, captured from a DC
    # Transcribed from an actual KDC_ERR_ETYPE_NOTSUPP produced on a Windows Server 2022
    # domain controller by requesting a service ticket for a DES-only account. Names and
    # identifiers are replaced with the fixture set's own; every field SHAPE is exactly what
    # the KDC wrote, and three of them contradicted what this generator had been assuming:
    #
    #   1. Failure events use '-' as the absent marker in the version 2 fields, not 'N/A'.
    #      Only 'N/A' was being handled, so the dash was read as an advertised algorithm name
    #      and ClientAdvertizedSupportsAes came back $false - which means "this client offered
    #      no AES", a Critical finding, on every failure event in a collection.
    #   2. Status is written lower-case ('0xe', not '0xE').
    #   3. SessionKeyEncryptionType carries 0x2d, which is not a valid RFC 3961 encryption
    #      type at all. On a failure the field is not meaningful and must decode as unknown
    #      rather than crash or be believed.
    @{
        File   = '4769-v2-real-etype-notsupp.xml'
        Covers = 'Captured KDC_ERR_ETYPE_NOTSUPP - dash absent-markers, lowercase status, invalid session key.'
        Xml    = New-KrbEventXml -EventId 4769 -Version 2 -RecordId 1000017 -MinutesOffset 60 -Data ([ordered]@{
            TargetUserName   = "WKS-FINANCE-04`$@$domain"
            TargetDomainName = $domain
            ServiceName      = 'KRBTEST/des.ad.techbyjeff.net'
            ServiceSid       = 'S-1-0-0'
            TicketOptions    = '0x40810000'
            TicketEncryptionType = '0xffffffff'
            IpAddress        = '::1'
            IpPort           = '0'
            Status           = '0xe'
            LogonGuid        = '{00000000-0000-0000-0000-000000000000}'
            TransmittedServices = '-'
            AccountSupportedEncryptionTypes = '-'
            AccountAvailableKeys = '-'
            ServiceSupportedEncryptionTypes = '-'
            ServiceAvailableKeys = '-'
            DCSupportedEncryptionTypes = '-'
            DCAvailableKeys  = '-'
            ClientAdvertizedEncryptionTypes = '-'
            SessionKeyEncryptionType = '0x2d'
        })
    }

    # ---------------------------------------------------------------------- malformed
    @{
        File   = 'malformed-truncated.xml'
        Covers = 'Truncated XML - the decoder must warn and skip, not abort the collection.'
        Xml    = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>" +
                 '<System><EventID>4769</EventID>'
    }
)

$manifest = [System.Collections.Generic.List[object]]::new()

foreach ($scenario in $scenarios) {
    $target = Join-Path -Path $Path -ChildPath $scenario.File

    if ($PSCmdlet.ShouldProcess($target, 'Write fixture')) {
        # No BOM. The fixtures are read back with Get-Content -Raw and cast to [xml], and a
        # UTF-8 BOM ahead of the XML declaration makes that cast throw with a message about
        # an unexpected character at position 1 that gives no hint of the real cause.
        [System.IO.File]::WriteAllText($target, $scenario.Xml, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Wrote $($scenario.File)"
    }

    $manifest.Add([PSCustomObject]@{
        File   = $scenario.File
        Covers = $scenario.Covers
    })
}

$manifestPath = Join-Path -Path $Path -ChildPath 'FIXTURES.md'
if ($PSCmdlet.ShouldProcess($manifestPath, 'Write fixture manifest')) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Test fixtures')
    $lines.Add('')
    $lines.Add('Generated by `New-KrbFixture.ps1`. Do not edit the XML by hand - edit the')
    $lines.Add('generator and re-run it, so that the reason each fixture differs from a real')
    $lines.Add('event stays visible in one place.')
    $lines.Add('')
    $lines.Add('| Fixture | Covers |')
    $lines.Add('| --- | --- |')
    foreach ($entry in $manifest) {
        $lines.Add("| ``$($entry.File)`` | $($entry.Covers) |")
    }
    $lines.Add('')
    Set-Content -Path $manifestPath -Value $lines -Encoding utf8
}

Write-Verbose "Generated $($manifest.Count) fixture(s) in $Path"
$manifest
