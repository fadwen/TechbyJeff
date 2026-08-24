#Requires -Version 7.6

function ConvertFrom-KrbEventRecord {
    <#
    .SYNOPSIS
        Normalises a raw Kerberos audit event into a single flat schema

    .DESCRIPTION
        Events 4768, 4769 and 4771 carry overlapping but non-identical field sets, and each
        has been revised over time. This function flattens all of them into one shape so that
        the correlation layer never has to branch on event ID or schema version.

        The three complications this function exists to absorb:

        1. Schema versions. The November 2022 hardening update (KB5021131) introduced
           version 2 of 4768 and 4769, adding ClientAdvertizedEncryptionTypes,
           AccountSupportedEncryptionTypes, AccountAvailableKeys, ServiceSupportedEncryptionTypes,
           ServiceAvailableKeys, DCSupportedEncryptionTypes, DCAvailableKeys and
           SessionKeyEncryptionType. Those fields are the difference between inferring what a
           client can do and reading it directly. A domain still running version 0 or 1
           events yields nulls in those positions, and the risk engine has to be able to tell
           "this client offered no AES" from "nobody recorded what this client offered" - so
           they are null, not false.

        2. Positional field access is unusable across versions. EventLogRecord.Properties is
           an ordered list whose indices shift between schema versions, so the field at index
           7 is TicketEncryptionType in one version and something else in another. This
           function reads the XML by Data element NAME instead. That costs an XML parse per
           record and is the module's dominant per-event expense; it is paid deliberately,
           because a positional decoder silently mislabels data rather than failing.

        3. Principal names are not written consistently. 4769 writes TargetUserName as
           user@REALM while 4768 writes it bare; ServiceName may be a bare account name, a
           machine account with a trailing dollar, or a full SPN with a class and port. All
           three are decomposed here rather than at every call site.

        The -Xml parameter set exists so the decoder can be exercised without an event log.
        EventLogRecord cannot be constructed - it has no public constructor and is produced
        only by the event log service - so a decoder that accepted nothing else would be
        testable only against whatever events the test machine's own domain happened to
        contain. Since the interesting cases are precisely the ones a healthy domain does not
        produce - RC4-only services, DES tickets, clients advertising no AES, version 0 and 1
        schemas from controllers that no longer exist - the fixture path is not a convenience.
        It is the only way to test the code that matters.

    .PARAMETER Record
        [System.Diagnostics.Eventing.Reader.EventLogRecord] (Mandatory in the Record set, Pipeline: ByValue)

        The event record to normalise, as returned by Get-WinEvent.

    .PARAMETER Xml
        [System.String] (Mandatory in the Xml set, Pipeline: ByValue)

        Raw event XML, in the form EventLogRecord.ToXml returns. Timestamp and record
        identifier are read from the XML itself in this mode.

    .PARAMETER SourceName
        [System.String] (Optional, No Pipeline Support)

        Label recorded on the output as the origin of the event - a domain controller name
        for a live collection, or a file name for an archived log. Defaults to the Computer
        value carried inside the record itself.

    .EXAMPLE
        PS> Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4769 } -MaxEvents 1 |
                ConvertFrom-KrbEventRecord

        DESCRIPTION: Normalises a single service ticket request event
        OUTPUT: A KrbEtypeInsight.Event object with decoded etype, principal and client fields
        USE CASE: Inspecting the decoder's output directly while developing a filter

    .EXAMPLE
        PS> Get-Content .\Tests\Fixtures\4769-rc4-only.xml -Raw |
                ConvertFrom-KrbEventRecord -SourceName 'fixture'

        DESCRIPTION: Decodes a captured event with no event log present
        OUTPUT: The same KrbEtypeInsight.Event schema as the live path
        USE CASE: How the unit tests reach the cases a healthy domain never produces

    .OUTPUTS
        KrbEtypeInsight.Event

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Missing version 2 fields: .\Troubleshooting\Common\Event-Schema-Versions.md
        - Collection performance: .\Troubleshooting\Performance\Event-Volume.md
    #>
    [CmdletBinding(DefaultParameterSetName = 'Record')]
    [OutputType('KrbEtypeInsight.Event')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Record')]
        [ValidateNotNull()]
        [System.Diagnostics.Eventing.Reader.EventLogRecord]$Record,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Xml')]
        [ValidateNotNullOrEmpty()]
        [string]$Xml,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SourceName
    )

    begin {
        $protocol = Get-KrbProtocolCatalog
    }

    process {
        $rawXml = if ($PSCmdlet.ParameterSetName -eq 'Record') { $Record.ToXml() } else { $Xml }

        try {
            $document = [xml]$rawXml
        }
        catch {
            # A record that will not render as XML is corrupt or truncated. Report it and
            # continue: a single bad record in a 400,000-event log must not abort a
            # collection that has been running for twenty minutes.
            $identifier = if ($PSCmdlet.ParameterSetName -eq 'Record') {
                "record $($Record.RecordId) on $($Record.MachineName)"
            }
            else { 'supplied XML' }

            Write-Warning ("Kerberos event $identifier could not be read as XML and was " +
                "skipped: $($_.Exception.Message)")
            return
        }

        # One pass over the Data elements builds the name-keyed lookup. Doing this once and
        # indexing it beats calling SelectSingleNode per field, which reparses the XPath for
        # every one of the twenty-odd fields on a version 2 record.
        #
        # GetElementsByTagName and GetAttribute rather than $xml.Event.EventData.Data and
        # $element.Name: the dotted form goes through PowerShell's XML type adapter, which
        # builds an adapted property set for every node it touches. On a record with twenty
        # Data elements that is twenty adapter passes, and it measured about 40 percent
        # slower across a collection than the underlying XmlNode API for identical results.
        $data = @{}
        foreach ($element in $document.DocumentElement.GetElementsByTagName('Data')) {
            $data[$element.GetAttribute('Name')] = $element.InnerText
        }

        $system = $document.DocumentElement['System']
        if (-not $system) {
            Write-Warning 'Kerberos event XML has no System element and was skipped'
            return
        }

        $eventId = [int]$system['EventID'].InnerText

        # Version is absent from the oldest records rather than being written as zero, so a
        # missing element has to read as version 0 and not throw.
        $versionNode = $system['Version']
        $version = if ($versionNode) { [int]$versionNode.InnerText } else { 0 }

        $computerNode = $system['Computer']
        $computer = if ($computerNode) { $computerNode.InnerText } else { $null }

        if ($PSCmdlet.ParameterSetName -eq 'Record') {
            $timeCreated = $Record.TimeCreated
            $recordId = $Record.RecordId
            if (-not $computer) { $computer = $Record.MachineName }
        }
        else {
            # The XML carries the timestamp as a UTC round-trip string. Parsing without
            # RoundtripKind produces a DateTime whose Kind is Unspecified, which then gets
            # treated as local time - shifting every fixture-derived event by the machine's
            # UTC offset and making time-window assertions fail in one timezone and pass in
            # another.
            $timeCreated = $null
            $timeNode = $system['TimeCreated']
            if ($timeNode) {
                $stamp = $timeNode.GetAttribute('SystemTime')
                if ($stamp) {
                    $timeCreated = [datetime]::Parse($stamp, [cultureinfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
                }
            }

            $recordId = $null
            $recordNode = $system['EventRecordID']
            if ($recordNode) { $recordId = [long]$recordNode.InnerText }
        }

        # TargetUserName is written as user@REALM on 4769 and bare on 4768/4771. Splitting
        # unconditionally on the first @ handles both, and leaves a UPN-shaped account name
        # intact because the realm suffix is the only thing after an @ in this field.
        $rawClient = $data['TargetUserName']
        $clientAccount = $rawClient
        $clientRealm = $data['TargetDomainName']
        if ($rawClient -and $rawClient.Contains('@')) {
            $parts = $rawClient -split '@', 2
            $clientAccount = $parts[0]
            if (-not $clientRealm) { $clientRealm = $parts[1] }
        }

        $status = ConvertTo-KrbInt32 -Value $data['Status']
        $statusInfo = if ($null -ne $status) { $protocol.KdcStatus[$status] } else { $null }

        $preAuth = ConvertTo-KrbInt32 -Value $data['PreAuthType']
        $preAuthInfo = if ($null -ne $preAuth) { $protocol.PreAuthType[$preAuth] } else { $null }

        # Version 2 fields. Absent on older schemas, and absent must stay distinguishable
        # from empty - see the note in the description.
        #
        # Windows uses TWO different absent markers depending on the event, which was only
        # discovered by capturing a real failure from a live KDC. A successful 4769 writes
        # 'N/A' into the fields it did not populate; a FAILED one writes a single dash into
        # every version 2 field. Testing only for 'N/A' let the dash through as though it were
        # an advertised algorithm name, so ClientAdvertizedNames came back as @('-') and
        # ClientAdvertizedSupportsAes as $false - and $false on that property means "this
        # client offered no AES", which is a Critical finding. Every failure event in a
        # collection would have carried it.
        $advertized = $data['ClientAdvertizedEncryptionTypes']
        $advertizedSet = if (-not [string]::IsNullOrWhiteSpace($advertized) -and
                             $advertized.Trim() -notin 'N/A', '-') {
            ConvertFrom-KrbEtype -AdvertizedEtype $advertized
        }
        else { $null }

        [PSCustomObject]@{
            PSTypeName  = 'KrbEtypeInsight.Event'

            TimeCreated = $timeCreated
            EventId     = $eventId
            EventVersion = $version
            RecordId    = $recordId
            Source      = if ($SourceName) { $SourceName } else { $computer }

            # True only for the schema that carries the fields the risk engine prefers. The
            # engine reads this rather than testing individual fields for null, so that
            # "collected from a legacy DC" is a single stated fact in the output.
            HasEtypeDetail = ($version -ge 2 -and $eventId -in 4768, 4769)

            ClientAccount   = $clientAccount
            ClientRealm     = $clientRealm
            ClientSid       = $data['TargetSid']
            IsClientComputer = [bool]($clientAccount -and $clientAccount.EndsWith('$'))

            ServiceName     = $data['ServiceName']
            ServiceSid      = $data['ServiceSid']

            # A 4768 is always against krbtgt, so treating its ServiceName as a service under
            # assessment would put krbtgt at the top of every report and say nothing about
            # the services that matter. The event still counts - it is where
            # ClientAdvertizedEncryptionTypes and PreAuthEncryptionType live - but it is
            # evidence about the CLIENT, not about a service.
            IsTgtRequest    = ($eventId -eq 4768)

            # Cross-realm referral. This module originally looked for a 'krbtgt/REALM' prefix
            # here, on the reasonable assumption that the referral ticket's own principal name
            # would be logged. It is not. Measured on a real bidirectional forest trust, the
            # 4769 ServiceName carries the BARE TARGET REALM and nothing else:
            #
            #   logged on the LAB forest  ServiceName = AD.TECHBYJEFF.NET   etype 0x17
            #   logged on the TBJ forest  ServiceName = LAB.CONTOSO.TEST    0xC000019B
            #
            # while the literal string 'krbtgt' is what LOCAL TGT renewals carry. So a rule
            # keyed on a 'krbtgt/' prefix matches neither, and every cross-realm referral -
            # the single best evidence that a trust is still forcing RC4 - was being filed as
            # an ordinary unresolved service.
            #
            # Detected here by shape, because the decoder has no trust list: a realm name has
            # no SPN class separator, no trailing dollar, at least one dot, and is upper case.
            # Get-KrbEtypeRisk refines this against the real trust names when a domain context
            # is available, which is authoritative where this is only indicative.
            IsProbableRealmName = [bool](
                $data['ServiceName'] -and
                $data['ServiceName'] -notmatch '[/\\]' -and
                $data['ServiceName'] -notmatch '\$$' -and
                $data['ServiceName'].Contains('.') -and
                $data['ServiceName'] -ceq $data['ServiceName'].ToUpperInvariant()
            )

            # RFC 3961 etype numbers.
            TicketEtype     = ConvertTo-KrbInt32 -Value $data['TicketEncryptionType']
            SessionKeyEtype = ConvertTo-KrbInt32 -Value $data['SessionKeyEncryptionType']
            PreAuthEtype    = ConvertTo-KrbInt32 -Value $data['PreAuthEncryptionType']

            # MS-KILE bitmasks, version 2 only. These are the KDC's COMPUTED effective value
            # for the principal, which is not always the raw msDS-SupportedEncryptionTypes
            # attribute - an account attributed 0x1C has been observed reported here as 0x1F.
            # Both are surfaced, by this field and by the directory reader, and the module
            # deliberately does not reconcile them into one number.
            AccountSupportedEtypes = ConvertTo-KrbInt32 -Value $data['AccountSupportedEncryptionTypes']
            ServiceSupportedEtypes = ConvertTo-KrbInt32 -Value $data['ServiceSupportedEncryptionTypes']
            DcSupportedEtypes      = ConvertTo-KrbInt32 -Value $data['DCSupportedEncryptionTypes']

            # Which key material actually exists on the principal, version 2 only. This is
            # the field that answers "will hardening this account leave it with no usable
            # key", which msDS-SupportedEncryptionTypes on its own cannot answer.
            AccountAvailableKeys = ConvertTo-KrbKeyNameList -Value $data['AccountAvailableKeys']
            ServiceAvailableKeys = ConvertTo-KrbKeyNameList -Value $data['ServiceAvailableKeys']
            DcAvailableKeys      = ConvertTo-KrbKeyNameList -Value $data['DCAvailableKeys']

            ClientAdvertizedEtypes      = if ($advertizedSet) { $advertizedSet.Etypes } else { $null }
            ClientAdvertizedNames       = if ($advertizedSet) { $advertizedSet.Names } else { $null }
            ClientAdvertizedSupportsAes = if ($advertizedSet) { $advertizedSet.SupportsAes } else { $null }
            ClientAdvertizedLegacyOnly  = if ($advertizedSet) { $advertizedSet.LegacyOnly } else { $null }

            IpAddress   = ConvertTo-KrbClientAddress -Value $data['IpAddress']
            IpAddressRaw = $data['IpAddress']
            IpPort      = $data['IpPort']

            Status         = $status
            StatusHex      = if ($null -ne $status) { '0x{0:X}' -f $status } else { $null }
            StatusName     = if ($statusInfo) { $statusInfo.Name } else { $null }
            StatusIsEtypeRelated = if ($statusInfo) { $statusInfo.IsEtypeRelated } else { $false }

            # 4771 is a failure event by definition. 4768 and 4769 carry a status field and
            # are failures only when it is non-zero.
            IsFailure   = ($eventId -eq 4771) -or ($null -ne $status -and $status -ne 0)

            PreAuthType     = $preAuth
            PreAuthTypeName = if ($preAuthInfo) { $preAuthInfo.Name } else { $null }

            TicketOptions     = $data['TicketOptions']
            TicketOptionNames = ConvertTo-KrbTicketOptionName -Value $data['TicketOptions']

            CertIssuerName    = $data['CertIssuerName']
            CertThumbprint    = $data['CertThumbprint']
            LogonGuid         = $data['LogonGuid']
        }
    }
}
