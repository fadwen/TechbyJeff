#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The event decoder, exercised against the captured fixtures in Tests\Fixtures.

    These tests run with no event log, no domain and no ActiveDirectory module, which is the
    whole point: EventLogRecord has no public constructor, so a decoder that accepted nothing
    else could only ever be tested against whatever events the build machine's own domain
    happened to contain. A healthy domain does not issue RC4 tickets, does not hold DES
    accounts that authenticate, and cannot produce the version 0 and version 1 audit schemas
    at all - and those are precisely the cases the risk engine exists to detect.

    The assertion that recurs throughout is the distinction between null and false. On a
    version 0 event, ClientAdvertizedSupportsAes must be $null - meaning "nobody recorded
    this" - and never $false, which would mean "this client offered no AES". The second is a
    Critical finding. Producing it from missing data would have the module condemn every
    client behind an unpatched domain controller.
#>

BeforeDiscovery {
    $script:FixtureRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'Fixtures'
}

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    $script:FixtureRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'Fixtures'

    function Get-Fixture {
        <#
            Decodes one fixture by name and returns the resulting event object. Kept as a
            helper so each test states which scenario it is about rather than repeating four
            lines of plumbing.
        #>
        param([Parameter(Mandatory)][string]$Name)

        $path = Join-Path -Path $script:FixtureRoot -ChildPath $Name
        if (-not (Test-Path -Path $path)) {
            throw "Fixture '$Name' not found. Run Tests\Fixtures\New-KrbFixture.ps1 to regenerate."
        }

        $raw = Get-Content -Path $path -Raw
        InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw; Name = $Name } {
            ConvertFrom-KrbEventRecord -Xml $Raw -SourceName $Name
        }
    }
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-KrbEventRecord' -Tag 'Unit', 'Private', 'Decode' {

    Context 'Fixture integrity' {

        It 'has every fixture the tests reference' -ForEach @(
            @{ Name = '4769-v2-healthy-aes.xml' }
            @{ Name = '4769-v2-service-no-aes-key.xml' }
            @{ Name = '4768-v2-legacy-client.xml' }
            @{ Name = '4769-v2-legacy-client-to-service.xml' }
            @{ Name = '4769-v2-des-ticket.xml' }
            @{ Name = '4771-etype-notsupp.xml' }
            @{ Name = '4771-null-key.xml' }
            @{ Name = '4769-v0-legacy-schema.xml' }
            @{ Name = '4768-v1-legacy-schema.xml' }
            @{ Name = '4768-v2-failed-0xffffffff.xml' }
            @{ Name = '4769-v2-hostile-spn.xml' }
            @{ Name = '4769-v2-aes-session-key-only.xml' }
            @{ Name = 'malformed-truncated.xml' }
        ) {
            Join-Path -Path $script:FixtureRoot -ChildPath $Name | Should -Exist
        }
    }

    Context 'Version 2 schema' {

        It 'decodes a healthy AES service ticket' {
            $result = Get-Fixture '4769-v2-healthy-aes.xml'

            $result.EventId | Should-Be 4769
            $result.EventVersion | Should-Be 2
            $result.HasEtypeDetail | Should-BeTrue
            $result.TicketEtype | Should-Be 18
            $result.SessionKeyEtype | Should-Be 18
            $result.ServiceName | Should-Be 'svc-payroll'
            $result.IsFailure | Should-BeFalse
            $result.StatusName | Should-Be 'KDC_ERR_NONE'
        }

        It 'strips the realm suffix from a 4769 TargetUserName' {
            # 4769 writes user@REALM; 4768 and 4771 write it bare. Left unsplit, the same
            # machine appears under two different keys and its evidence is divided between
            # them - so a client that advertised no AES in its 4768 is never matched to the
            # 4769 requests that prove which services depend on it.
            $result = Get-Fixture '4769-v2-healthy-aes.xml'

            $result.ClientAccount | Should-Be 'WKS-FINANCE-04$'
            $result.ClientRealm | Should-Be 'AD.TECHBYJEFF.NET'
            $result.IsClientComputer | Should-BeTrue
        }

        It 'reads the available keys that reveal an account has no AES key material' {
            # The decisive field, and the reason the version 2 schema matters. The account is
            # configured for RC4 and AES; the KDC reports it holds an RC4 key only.
            $result = Get-Fixture '4769-v2-service-no-aes-key.xml'

            $result.ServiceAvailableKeys | Should-BeCollection @('RC4')
            $result.ServiceSupportedEtypes | Should-Be 28
            $result.TicketEtype | Should-Be 23
        }

        It 'decodes what a legacy client advertised on the wire' {
            $result = Get-Fixture '4768-v2-legacy-client.xml'

            $result.ClientAdvertizedSupportsAes | Should-BeFalse
            $result.ClientAdvertizedLegacyOnly | Should-BeTrue
            $result.ClientAdvertizedNames | Should-ContainCollection @('RC4-HMAC-NT')
            $result.PreAuthEtype | Should-Be 23
        }

        It 'separates a ticket encryption type from a session key encryption type' {
            # The 0x20 session-key-only case: an RC4 ticket carrying an AES256 session key.
            # A decoder that reported only one of the two would describe this account as
            # either fully hardened or entirely legacy, and both readings are wrong.
            $result = Get-Fixture '4769-v2-aes-session-key-only.xml'

            $result.TicketEtype | Should-Be 23
            $result.SessionKeyEtype | Should-Be 18
        }

        It 'normalises an IPv4-mapped IPv6 client address' {
            # Distinct-client counts are the blast radius numbers in the report. The same
            # host arriving as '::ffff:10.20.30.40' and '10.20.30.40' would be counted twice.
            $mapped = Get-Fixture '4769-v2-healthy-aes.xml'
            $plain = Get-Fixture '4769-v2-des-ticket.xml'

            $mapped.IpAddress | Should-Be '10.20.30.40'
            $mapped.IpAddressRaw | Should-Be '::ffff:10.20.30.40'
            $plain.IpAddress | Should-Be '10.20.30.99'
        }

        It 'decodes ticket options into named flags' {
            $result = Get-Fixture '4768-v2-legacy-client.xml'

            $result.TicketOptionNames | Should-ContainCollection @('Forwardable')
            $result.TicketOptions | Should-Be '0x40810010'
        }
    }

    Context 'Legacy schemas' {

        It 'decodes a version 0 event without the fields it does not have' {
            $result = Get-Fixture '4769-v0-legacy-schema.xml'

            $result.EventVersion | Should-Be 0
            $result.HasEtypeDetail | Should-BeFalse
            $result.TicketEtype | Should-Be 23
        }

        It 'reports missing version 2 fields as null, never as false or empty' {
            # The assertion this whole file is built around. $false here means "this client
            # offered no AES", which is a Critical finding. Producing it from an absent field
            # would condemn every client behind an unpatched controller.
            $result = Get-Fixture '4769-v0-legacy-schema.xml'

            $result.ClientAdvertizedSupportsAes | Should-BeNull
            $result.ClientAdvertizedLegacyOnly | Should-BeNull
            $result.ClientAdvertizedNames | Should-BeNull
            $result.ServiceAvailableKeys | Should-BeNull
            $result.AccountAvailableKeys | Should-BeNull
            $result.ServiceSupportedEtypes | Should-BeNull
            $result.SessionKeyEtype | Should-BeNull
        }

        It 'handles a version 1 event, which has a ticket etype but no KB5021131 additions' {
            $result = Get-Fixture '4768-v1-legacy-schema.xml'

            $result.EventVersion | Should-Be 1
            $result.HasEtypeDetail | Should-BeFalse
            $result.TicketEtype | Should-Be 23
            $result.ClientAdvertizedSupportsAes | Should-BeNull
        }

        It 'treats a missing Version element as version 0 rather than throwing' {
            # The oldest records omit the element entirely. Indexing into it unguarded is a
            # null reference on the first archived log anyone points the module at.
            $result = Get-Fixture '4771-etype-notsupp.xml'

            $result.EventVersion | Should-Be 0
        }
    }

    Context 'Failure events' {

        It 'recognises KDC_ERR_ETYPE_NOTSUPP as encryption-type related' {
            # The direct signature of hardening breakage. Distinguishing it from the constant
            # background of expired passwords is what makes a post-change report readable.
            $result = Get-Fixture '4771-etype-notsupp.xml'

            $result.EventId | Should-Be 4771
            $result.IsFailure | Should-BeTrue
            $result.Status | Should-Be 14
            $result.StatusHex | Should-Be '0xE'
            $result.StatusName | Should-Be 'KDC_ERR_ETYPE_NOTSUPP'
            $result.StatusIsEtypeRelated | Should-BeTrue
        }

        It 'recognises KDC_ERR_NULL_KEY as encryption-type related' {
            # The error an AES-only account returns when its password predates the change and
            # no AES key was ever derived. Not obviously an encryption type problem from its
            # name, which is why it is classified explicitly.
            $result = Get-Fixture '4771-null-key.xml'

            $result.StatusName | Should-Be 'KDC_ERR_NULL_KEY'
            $result.StatusIsEtypeRelated | Should-BeTrue
        }

        It 'does not classify an ordinary bad password as encryption-type related' {
            $result = Get-Fixture '4768-v2-failed-0xffffffff.xml'

            $result.StatusName | Should-Be 'KDC_ERR_PREAUTH_FAILED'
            $result.StatusIsEtypeRelated | Should-BeFalse
            $result.IsFailure | Should-BeTrue
        }

        It 'decodes the no-ticket-issued sentinel rather than a cipher' {
            $result = Get-Fixture '4768-v2-failed-0xffffffff.xml'

            $result.TicketEtype | Should-Be -1
            $result.SessionKeyEtype | Should-Be -1
        }

        It 'treats every 4771 as a failure regardless of its status field' {
            $result = Get-Fixture '4771-etype-notsupp.xml'
            $result.IsFailure | Should-BeTrue
        }
    }

    Context 'Event classification' {

        It 'marks a 4768 as a TGT request so krbtgt is not assessed as a service' {
            # Without this, krbtgt tops every report by request volume and says nothing about
            # any service that matters.
            $tgt = Get-Fixture '4768-v2-legacy-client.xml'
            $service = Get-Fixture '4769-v2-healthy-aes.xml'

            $tgt.IsTgtRequest | Should-BeTrue
            $service.IsTgtRequest | Should-BeFalse
        }

        It 'records the source label it was given' {
            $result = Get-Fixture '4769-v2-healthy-aes.xml'
            $result.Source | Should-Be '4769-v2-healthy-aes.xml'
        }

        It 'emits the declared PSTypeName' {
            $result = Get-Fixture '4769-v2-healthy-aes.xml'
            $result.PSTypeNames[0] | Should-Be 'KrbEtypeInsight.Event'
        }
    }

    Context 'Hostile and malformed input' {

        It 'preserves a service name containing markup verbatim' {
            # Encoding belongs at the report boundary, not here. Mangling it in the decoder
            # would corrupt the value for the LDAP lookup and for the JSON export as well.
            $result = Get-Fixture '4769-v2-hostile-spn.xml'

            $result.ServiceName | Should-Be 'HOST/*)(objectClass=*)<script>alert(1)</script>'
        }

        It 'warns and skips a malformed record instead of throwing' {
            # One corrupt record in a 400,000-event archive must not abandon a collection
            # that has been running for twenty minutes.
            $path = Join-Path -Path $script:FixtureRoot -ChildPath 'malformed-truncated.xml'
            $raw = Get-Content -Path $path -Raw

            $result = InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw -WarningAction SilentlyContinue
            }

            $result | Should-BeNull
        }

        It 'warns and skips XML that parses but has no System element' {
            # Well-formed XML that is not an event record. Reaching for EventID on a missing
            # System element would be a null reference in the middle of a collection.
            $raw = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>" +
                   '<EventData/></Event>'

            $captured = @(InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw 3>&1
            })

            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })
            $records = @($captured | Where-Object {
                $_ -isnot [System.Management.Automation.WarningRecord]
            })

            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-MatchString 'no System element'
            $records | Should-BeCollection -Count 0
        }

        It 'emits a warning naming the problem' {
            $path = Join-Path -Path $script:FixtureRoot -ChildPath 'malformed-truncated.xml'
            $raw = Get-Content -Path $path -Raw

            # 3>&1 redirects the warning stream into the output stream so it can be asserted
            # on. -WarningVariable does not work here: it binds to InModuleScope itself
            # rather than to the command inside the script block, so the warning escapes to
            # the console and the variable stays empty.
            $captured = @(InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw 3>&1
            })

            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-MatchString 'could not be read as XML'
        }
    }

    Context 'Real KDC failure output' {

        # Every assertion here comes from an event captured off a live Windows Server 2022
        # KDC, not from a shape this suite invented. Two of them failed against the
        # implementation that had 377 passing tests.

        It 'treats the dash absent-marker as absent, not as an advertised algorithm' {
            # The defect real data found. A failed 4769 writes '-' into every version 2 field.
            # Handling only 'N/A' let the dash through as an advertised name, so
            # ClientAdvertizedSupportsAes came back $false - and $false there means "offered
            # no AES", a Critical finding, on every failure event collected.
            $result = Get-Fixture '4769-v2-real-etype-notsupp.xml'

            $result.ClientAdvertizedNames | Should-BeNull
            $result.ClientAdvertizedSupportsAes | Should-BeNull
            $result.ClientAdvertizedLegacyOnly | Should-BeNull
            $result.ServiceAvailableKeys | Should-BeNull
            $result.AccountAvailableKeys | Should-BeNull
            $result.ServiceSupportedEtypes | Should-BeNull
        }

        It 'parses a lower-case status value' {
            # The KDC writes '0xe', not '0xE'.
            $result = Get-Fixture '4769-v2-real-etype-notsupp.xml'

            $result.Status | Should-Be 14
            $result.StatusName | Should-Be 'KDC_ERR_ETYPE_NOTSUPP'
            $result.StatusIsEtypeRelated | Should-BeTrue
            $result.IsFailure | Should-BeTrue
        }

        It 'reads the no-ticket-issued sentinel on a real failure' {
            (Get-Fixture '4769-v2-real-etype-notsupp.xml').TicketEtype | Should-Be -1
        }

        It 'does not believe the session key field on a failure event' {
            # A real failure carried 0x2d in SessionKeyEncryptionType, which is not an RFC 3961
            # encryption type at all. It must decode as unrecognised rather than be reported as
            # a cipher or throw.
            $result = Get-Fixture '4769-v2-real-etype-notsupp.xml'
            $decoded = ConvertFrom-KrbEtype -TicketEtype $result.SessionKeyEtype

            $result.SessionKeyEtype | Should-Be 45
            $decoded.IsRecognized | Should-BeFalse
            $decoded.DisplayName | Should-MatchString 'Unknown'
        }
    }

    Context 'Timestamp handling' {

        It 'parses the UTC event timestamp into local time without shifting it' {
            # The XML carries a round-trip UTC string. Parsed without RoundtripKind the
            # DateTime comes back as Unspecified, is then treated as local, and every
            # fixture-derived event moves by the machine's UTC offset - so a time-window
            # assertion passes in one timezone and fails in another.
            $result = Get-Fixture '4769-v2-healthy-aes.xml'
            $expectedUtc = [datetime]::Parse('2026-07-15T09:30:00Z', [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)

            $result.TimeCreated | Should-NotBeNull
            $result.TimeCreated.ToUniversalTime() | Should-Be $expectedUtc.ToUniversalTime()
        }

        It 'reads the record identifier from the XML' {
            $result = Get-Fixture '4769-v2-healthy-aes.xml'
            $result.RecordId | Should-Be 1000001
        }
    }
}
