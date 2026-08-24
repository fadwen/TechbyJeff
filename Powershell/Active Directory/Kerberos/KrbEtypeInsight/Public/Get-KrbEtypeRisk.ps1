#Requires -Version 7.6

function Get-KrbEtypeRisk {
    <#
    .SYNOPSIS
        Predicts which principals and clients a Kerberos encryption type hardening change will break

    .DESCRIPTION
        Correlates observed authentication behaviour with directory configuration and domain
        baseline, and emits one risk object per affected principal describing what a proposed
        encryption type change would do to it - with the evidence attached.

        This is the question the configuration scripts cannot answer. Setting an account's
        msDS-SupportedEncryptionTypes to AES is a one-line change; knowing whether that
        account has ever successfully used AES, whether it even holds an AES key, and which
        clients will stop working when RC4 goes away, requires putting three independent
        sources next to each other:

        - What the KDC actually issued, from events 4768 and 4769.
        - What the directory says each principal supports, from msDS-SupportedEncryptionTypes
          and userAccountControl.
        - What the domain permits by default, from the controllers' own policy.

        The correlations that produce the useful findings:

        1. Available keys against configured types. Version 2 events report which key material
           a principal actually holds. An account configured for AES that holds no AES key is
           the single most common cause of a hardening rollback: Kerberos keys are derived
           when the password is set, so an account whose password predates the change has
           nothing to encrypt with and the KDC returns KDC_ERR_NULL_KEY. Configuration alone
           cannot see this. It is finding KRB002 and it is why this module exists.

        2. Client advertisement against service dependency. Every 4768 records the full list
           of encryption types the client offered. Indexing that by client account, and then
           looking up each client of a given service, converts "this service only ever gets
           RC4 tickets" into "these twelve named clients advertise no AES at all and will
           fail the moment the KDC stops offering RC4". That named list is what an
           application owner needs in order to act, and no amount of configuration auditing
           produces it.

        3. Existing failures against the proposed change. Events already carrying
           KDC_ERR_ETYPE_NOTSUPP or KDC_ERR_NULL_KEY are not predictions - they are breakage
           that has already happened and is being absorbed by retries somewhere.

        Confidence is reported, not assumed. Where the controllers emit the older version 0
        or version 1 event schema, the available-key and client-advertisement fields do not
        exist, and the engine falls back to weaker inference from ticket encryption types
        alone. It says so on every affected object rather than presenting an inference as an
        observation.

    .PARAMETER KerberosEvent
        [System.Object[]] (Mandatory, Pipeline: ByValue)

        Decoded events from Get-KrbEvent. The assessment is only as good as this window; see
        the StartTime guidance on Get-KrbEvent for why thirty days is the practical minimum.

        Aliased to -Event, which reads better at the console. The parameter itself cannot be
        named Event: $Event is a PowerShell automatic variable, populated inside the action
        block of an event registration, and a parameter of that name shadows it. Nothing in
        this function would notice, but a caller who pipes into it from inside such a block
        would, and the failure would be baffling.

    .PARAMETER Principal
        [System.Object[]] (Optional, No Pipeline Support)

        Directory configuration from Get-KrbPrincipalEtype. When omitted and -Offline is not
        set, the domain is enumerated once and indexed in memory.

        Supplying this explicitly is worthwhile when assessing repeatedly against the same
        directory snapshot, and required when the analysis machine cannot reach the domain.

    .PARAMETER DomainContext
        [System.Object] (Optional, No Pipeline Support)

        Domain baseline from Get-KrbDomainEtypeContext. When omitted and -Offline is not set,
        it is collected automatically. Supplies the true domain default against which
        accounts with an unset attribute are judged, and contributes trust and krbtgt
        findings of its own.

    .PARAMETER TargetEncryptionTypes
        [System.Int32] (Optional, No Pipeline Support)

        The msDS-SupportedEncryptionTypes bitmask the change would move to. Defaults to 0x18
        (24) - AES128 and AES256, with RC4 and DES removed - which is what an RC4 removal
        project is aiming at.

        Set it to 0x1C (28) to model the intermediate step of adding AES while leaving RC4
        in place, which should produce no Critical findings at all; if it does, that step is
        not as safe as it is usually assumed to be.

    .PARAMETER Offline
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Assess purely from the event data, making no directory or registry calls.

        This is the mode for analysing archived logs on a machine with no domain
        connectivity. Version 2 events carry enough of each principal's configuration inline
        that the assessment remains substantially complete; against older event schemas it
        degrades considerably, and the ConfidenceNotes on each object record what was lost.

    .PARAMETER IncludeHealthy
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Also emit principals that the change would not affect. Off by default so that the
        output is a work list rather than an inventory.

        Turn it on when producing evidence that a change is safe, where the principals with
        nothing wrong are the point.

    .EXAMPLE
        PS> Get-KrbEvent -MaxEvents 50000 | Get-KrbEtypeRisk | Sort-Object RiskScore -Descending

        DESCRIPTION: A complete assessment of an RC4 removal against the last 30 days
        OUTPUT: One risk object per affected principal, worst first
        USE CASE: The main entry point; everything else in the module supports this line
        DURATION: 2 to 15 minutes depending on domain and event volume

    .EXAMPLE
        PS> $risks = Get-KrbEvent -EventId 4768,4769 | Get-KrbEtypeRisk
        PS> $risks | Where-Object RiskLevel -eq 'Critical' |
                Select-Object PrincipalName, RequestCount, ClientCount,
                              @{ n = 'BreaksClients'; e = { $_.ClientsWithoutAesSupport -join ', ' } }

        DESCRIPTION: Produces the named list of clients each critical service would take down
        OUTPUT: Service, its request volume, and the specific clients that cannot do AES
        USE CASE: The table to send to each application owner - it names their machines, not yours

    .EXAMPLE
        PS> Get-KrbEvent | Get-KrbEtypeRisk -TargetEncryptionTypes 0x1C |
                Where-Object RiskLevel -in 'Critical', 'High'

        DESCRIPTION: Models the intermediate step of adding AES while keeping RC4
        OUTPUT: Anything that would break even from that supposedly safe change
        USE CASE: Validating the first phase of a staged rollout before scheduling it

    .EXAMPLE
        PS> Get-KrbEvent -Path .\dc01.evtx, .\dc02.evtx -MaxEvents 0 | Get-KrbEtypeRisk -Offline

        DESCRIPTION: Assesses archived logs with no domain connectivity
        OUTPUT: Risk objects built entirely from version 2 event content
        USE CASE: Analysing a customer's collected logs on your own machine

    .INPUTS
        KrbEtypeInsight.Event

    .OUTPUTS
        KrbEtypeInsight.Risk

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        Read-only. This function predicts the effect of a change; it never makes one.

        Events are buffered in memory before correlation, because a per-principal view cannot
        be built from a stream. Peak memory is roughly 2 KB per event. For collections beyond
        a few hundred thousand events, assess one controller's archive at a time and merge
        the resulting risk objects.

        TROUBLESHOOTING:
        - Finding code reference: .\Troubleshooting\Common\Finding-Codes.md
        - Risk scoring: .\Troubleshooting\Common\Risk-Scoring.md
        - Low confidence results: .\Troubleshooting\Common\Event-Schema-Versions.md
        - Memory use on large collections: .\Troubleshooting\Performance\Event-Volume.md
    #>
    [CmdletBinding()]
    [OutputType('KrbEtypeInsight.Risk')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Event')]
        [object[]]$KerberosEvent,

        [Parameter()]
        [object[]]$Principal,

        [Parameter()]
        [object]$DomainContext,

        [Parameter()]
        [int]$TargetEncryptionTypes = 0x18,

        [Parameter()]
        [switch]$Offline,

        [Parameter()]
        [switch]$IncludeHealthy
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        $catalog = Get-KrbEtypeCatalog

        # Validate the RAW target before decoding it. ConvertFrom-KrbEtype treats a zero
        # bitmask as "inherit the domain default", which is the correct reading for an
        # account attribute and the wrong one for a target: a caller asking what breaks if
        # everything moves to 0 is asking about no ciphers, not about 0x27. Checking the
        # cipher bits on the raw value keeps that distinction where it belongs.
        if (($TargetEncryptionTypes -band 0xFF) -eq 0) {
            $message = 'TargetEncryptionTypes 0x{0:X} enables no encryption type at all. Every ' +
                'principal would be reported as broken, which is true and useless.'
            Write-Error ($message -f $TargetEncryptionTypes) -ErrorAction Stop
            return
        }

        $target = ConvertFrom-KrbEtype -SupportedEncryptionTypes $TargetEncryptionTypes

        if (@($target.TicketEtypes).Count -eq 0) {
            # Reachable with a target of 0x20 alone, which authorises AES256 for the session
            # key and nothing for the ticket. It passes the cipher-bit check above and would
            # then mark every principal in the domain as broken.
            $message = 'TargetEncryptionTypes 0x{0:X} authorises no ticket encryption type. ' +
                'Bit 0x20 permits an AES256 session key only and cannot encrypt a ticket.'
            Write-Error ($message -f $TargetEncryptionTypes) -ErrorAction Stop
            return
        }

        # Survival is judged by cipher FAMILY, not by exact etype membership in the target.
        #
        # The obvious implementation - "is the observed etype in $target.TicketEtypes" - is
        # wrong in the one direction that matters. The default target 0x18 authorises etypes
        # 17 and 18, the AES-SHA1 pair. It does not include 19 and 20, the RFC 8009 AES-SHA2
        # types that Windows Server 2025 issues. Under exact-membership a client presenting
        # AES256-CTS-HMAC-SHA384-192 - the strongest thing Windows currently produces - is
        # reported as using "an encryption type the change removes", which reads out as a
        # Critical finding advising someone to confirm their client supports AES. It already
        # does; it supports more AES than the target names.
        #
        # What actually happens when such an account is narrowed to 0x18 is that the KDC
        # negotiates down from AES-SHA2 to AES-SHA1. The principal holds AES keys and keeps
        # working. That is not breakage and must not be reported as breakage - a tool that
        # raises Criticals against the most modern estate in the domain is one nobody
        # believes the second time.
        #
        # Comparing families gets every case right: RC4 and DES are lost when the target
        # drops them, AES survives whichever AES variant was observed.
        $targetFamilies = [System.Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        foreach ($etype in $target.TicketEtypes) {
            $entry = $catalog.TicketEtype[$etype]
            if ($entry) { [void]$targetFamilies.Add($entry.Family) }
        }

        # An etype the catalog does not recognise is treated as SURVIVING. The module cannot
        # know that an unfamiliar algorithm is weak, and condemning it would repeat the
        # mistake this whole comparison exists to avoid. It is surfaced as unrecognised
        # elsewhere, which is the honest place for it.
        $survivesTarget = {
            param([int]$Etype)

            $entry = $catalog.TicketEtype[$Etype]
            if (-not $entry) { return $true }
            return $targetFamilies.Contains($entry.Family)
        }

        Write-Verbose ("Assessing against target $($target.EffectiveHex): " +
            "$($target.CipherNames -join ', ') - surviving families: " +
            "$(@($targetFamilies) -join ', ')")

        if (-not $Offline -and -not $DomainContext) {
            try {
                $DomainContext = Get-KrbDomainEtypeContext -ErrorAction Stop
            }
            catch {
                Write-Warning ("Could not collect the domain baseline, continuing with the Windows " +
                    "default of 0x27. Accounts with an unset encryption type attribute may be " +
                    "misjudged. Error: $($_.Exception.Message)")
            }
        }

        $domainDefault = if ($DomainContext) {
            $DomainContext.DomainDefaultEncryptionTypes
        }
        else {
            $catalog.DefaultDomainSupportedEncTypes
        }

        # Directory index. One enumeration, two lookup tables - by account name and by SPN.
        # Resolving service names one directory query at a time would issue a query per
        # distinct SPN in the log, which in a domain of any size is tens of thousands of
        # round trips for data that fits comfortably in memory.
        $byAccount = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::OrdinalIgnoreCase)
        $bySpn = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        if (-not $Offline) {
            if (-not $Principal) {
                try {
                    Write-Verbose 'Enumerating directory principals for correlation'
                    $Principal = @(Get-KrbPrincipalEtype -All -IncludeDisabled `
                            -DomainDefaultEncryptionTypes $domainDefault -ErrorAction Stop)
                }
                catch {
                    Write-Warning ('Could not enumerate directory principals, continuing with event ' +
                        "evidence only. Error: $($_.Exception.Message)")
                    $Principal = @()
                }
            }

            foreach ($item in $Principal) {
                if ($item.SamAccountName) { $byAccount[$item.SamAccountName] = $item }
                foreach ($spn in @($item.ServicePrincipalNames)) {
                    if ($spn) { $bySpn[$spn] = $item }
                }
            }
            Write-Verbose "Indexed $($byAccount.Count) account(s) and $($bySpn.Count) SPN(s)"
        }

        # Trust names, used to confirm a cross-realm referral authoritatively rather than by
        # name shape. Empty when running offline, in which case the decoder's shape test is
        # the only signal available.
        $trustNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($DomainContext) {
            foreach ($t in @($DomainContext.Trusts)) {
                if ($t.Name) { [void]$trustNames.Add($t.Name) }
                if ($t.Target) { [void]$trustNames.Add($t.Target) }
            }
        }

        # Referral traffic, keyed by remote realm. Feeds the trust findings rather than
        # producing service rows of its own.
        $referralEvidence = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        $buffer = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $KerberosEvent) {
            if ($item) { $buffer.Add($item) }
        }
    }

    end {
        if ($buffer.Count -eq 0) {
            Write-Warning ('No events were supplied, so no assessment was produced. An empty ' +
                'result here means nothing was measured, not that nothing is at risk.')
            return
        }

        Write-Verbose "Correlating $($buffer.Count) event(s) - CorrelationId: $correlationId"

        # Pass 1: index what each CLIENT account advertised. This is the table that turns a
        # service-level finding into a named list of machines, and it has to exist before any
        # service is assessed - which is why the correlation is two passes and not one.
        $clientCapability = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        foreach ($item in $buffer) {
            if (-not $item.ClientAccount) { continue }

            $entry = $null
            if (-not $clientCapability.TryGetValue($item.ClientAccount, [ref]$entry)) {
                $entry = [PSCustomObject]@{
                    Account          = $item.ClientAccount
                    AdvertisedAes    = $null
                    AdvertisedAny    = $false
                    AdvertisedNames  = [System.Collections.Generic.HashSet[string]]::new(
                                            [StringComparer]::OrdinalIgnoreCase)
                    Addresses        = [System.Collections.Generic.HashSet[string]]::new(
                                            [StringComparer]::OrdinalIgnoreCase)
                    LastSeen         = $item.TimeCreated

                    # Evidence counts, so a finding can state what it saw rather than only
                    # asserting a boolean. See the KRB005 emission for why that matters.
                    AesAdvertisements    = 0
                    NoAesAdvertisements  = 0
                    IgnoredTgtRenewals   = 0
                }
                $clientCapability[$item.ClientAccount] = $entry
            }

            if ($item.IpAddress) { [void]$entry.Addresses.Add($item.IpAddress) }
            if ($item.TimeCreated -gt $entry.LastSeen) { $entry.LastSeen = $item.TimeCreated }

            # A service ticket request whose service IS krbtgt is a TGT renewal or a request
            # for a forwarded TGT, not the client asking for a service. Its advertised
            # encryption types are NOT reliable evidence of what the client can do, and
            # trusting them silently disabled KRB005 for every domain-joined Windows machine.
            #
            # Measured, not assumed. Seven instrumented boots across two machines, both with
            # SupportedEncryptionTypes = 0x4 (RC4 only), captured on the wire:
            #
            #   - 0 of 19 AS-REQs advertised AES. The client's own capability is reported
            #     faithfully there, every time.
            #   - Every normal boot emitted EXACTLY ONE AES advertisement, always the same
            #     request: TGS-REQ for krbtgt/REALM, etypes [AES256] alone, kdc-options
            #     0x60810010 (forwardable, forwarded, renewable, canonicalize, renewable-ok).
            #   - The same lone request appeared on a second, unrelated machine, so this is
            #     Windows behaviour rather than one host's misconfiguration.
            #
            # Because the union below treats a single AES advertisement as proof of
            # capability, that one boot-time request marked every rebooted Windows client as
            # AES-capable. With a 30-day default window nearly every client boots at least
            # once, so the named-client list that is this module's whole reason to exist
            # could not be produced for the population it exists to describe.
            #
            # Note it is the krbtgt SERVICE that disqualifies the evidence, not the forwarded
            # flag. Normal boots also emit forwarded krbtgt requests carrying ordinary RC4
            # lists, so filtering on the flag would keep the contaminating request and drop
            # clean ones. The RC4 evidence discarded here is redundant with the AS-REQs.
            $isTgtServiceRequest = $item.EventId -eq 4769 -and
                $item.ServiceName -and
                ($item.ServiceName -eq 'krbtgt' -or $item.ServiceName -like 'krbtgt/*')

            if ($isTgtServiceRequest) {
                if ($null -ne $item.ClientAdvertizedSupportsAes) { $entry.IgnoredTgtRenewals++ }
                continue
            }

            if ($null -ne $item.ClientAdvertizedSupportsAes) {
                $entry.AdvertisedAny = $true
                foreach ($name in @($item.ClientAdvertizedNames)) {
                    if ($name) { [void]$entry.AdvertisedNames.Add($name) }
                }

                if ($item.ClientAdvertizedSupportsAes) { $entry.AesAdvertisements++ }
                elseif ($item.ClientAdvertizedLegacyOnly) { $entry.NoAesAdvertisements++ }

                # Three states, not two. AdvertisedAes stays $null until the evidence settles
                # it either way, because "we could not tell" and "it cannot do AES" lead to
                # opposite findings.
                #
                # A client that has EVER advertised AES can do AES. Taking the union rather
                # than the latest observation matters because a single request made through a
                # constrained path would otherwise mark a healthy client as legacy-only. That
                # reasoning is still right - the filter above removes the evidence that was
                # wrong, rather than weakening the rule that was correct.
                #
                # The negative is taken from LegacyOnly rather than from SupportsAes being
                # false. SupportsAes is false whenever no AES name was RECOGNISED, which
                # includes a client advertising only algorithms newer than this catalog.
                # LegacyOnly is false in that case and true only when every advertised name
                # was understood and none was AES - which is the claim a Critical finding
                # needs behind it.
                if ($item.ClientAdvertizedSupportsAes) {
                    $entry.AdvertisedAes = $true
                }
                elseif ($item.ClientAdvertizedLegacyOnly -and $null -eq $entry.AdvertisedAes) {
                    $entry.AdvertisedAes = $false
                }
            }
        }

        Write-Verbose "Indexed advertisement evidence for $($clientCapability.Count) client account(s)"

        # Pass 2: bucket events by the principal they say something about.
        $observation = [System.Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::OrdinalIgnoreCase)

        $newObservation = {
            param([string]$key, [string]$displayName, [string]$role)

            [PSCustomObject]@{
                Key             = $key
                Name            = $displayName
                Roles           = [System.Collections.Generic.HashSet[string]]::new()
                ServiceNames    = [System.Collections.Generic.HashSet[string]]::new(
                                        [StringComparer]::OrdinalIgnoreCase)
                TicketEtypes    = [System.Collections.Generic.HashSet[int]]::new()
                SessionKeyEtypes = [System.Collections.Generic.HashSet[int]]::new()
                PreAuthEtypes   = [System.Collections.Generic.HashSet[int]]::new()
                AvailableKeys   = [System.Collections.Generic.HashSet[string]]::new(
                                        [StringComparer]::OrdinalIgnoreCase)
                AvailableKeysKnown = $false
                EventSupportedEtypes = [System.Collections.Generic.HashSet[int]]::new()
                Clients         = [System.Collections.Generic.HashSet[string]]::new(
                                        [StringComparer]::OrdinalIgnoreCase)
                ClientAddresses = [System.Collections.Generic.HashSet[string]]::new(
                                        [StringComparer]::OrdinalIgnoreCase)
                RequestCount    = 0
                FailureCount    = 0
                EtypeFailures   = [System.Collections.Generic.List[object]]::new()
                FirstSeen       = $null
                LastSeen        = $null
                SawV2           = $false
                SawLegacySchema = $false
                Sources         = [System.Collections.Generic.HashSet[string]]::new(
                                        [StringComparer]::OrdinalIgnoreCase)
                InitialRole     = $role
            }
        }

        $touch = {
            param($entry, $item)

            $entry.RequestCount++
            if ($item.IsFailure) { $entry.FailureCount++ }
            if ($item.StatusIsEtypeRelated -and $item.IsFailure) { $entry.EtypeFailures.Add($item) }
            if ($item.Source) { [void]$entry.Sources.Add($item.Source) }
            if ($item.HasEtypeDetail) { $entry.SawV2 = $true } else { $entry.SawLegacySchema = $true }

            if ($null -eq $entry.FirstSeen -or $item.TimeCreated -lt $entry.FirstSeen) {
                $entry.FirstSeen = $item.TimeCreated
            }
            if ($null -eq $entry.LastSeen -or $item.TimeCreated -gt $entry.LastSeen) {
                $entry.LastSeen = $item.TimeCreated
            }
        }

        foreach ($item in $buffer) {

            # SERVICE role, from 4769 only. A 4768 is always a request against krbtgt, so
            # treating its ServiceName as a service under assessment would put krbtgt at the
            # top of every report and say nothing about the services that matter.
            #
            # Excluding 4768 is not sufficient on its own, which is what the first version of
            # this got wrong. A TGT renewal is a 4769 whose ServiceName is the bare string
            # 'krbtgt', so krbtgt reappeared as a service anyway - 46 requests on a quiet lab
            # domain, and proportionally more on a real one. krbtgt's encryption types are a
            # domain-wide property reported by Get-KrbDomainEtypeContext, not a per-service
            # finding, so the bare name is skipped here.
            #
            # 'krbtgt/REALM' is deliberately NOT skipped. That form is a cross-realm referral,
            # and its ticket encryption type is the best evidence available that a trust is
            # still forcing RC4 - which is the finding trusts exist in this module for.
            $isLocalKrbtgt = $item.ServiceName -and
                             $item.ServiceName.Trim().Equals('krbtgt', [StringComparison]::OrdinalIgnoreCase)

            # Cross-realm referrals are evidence about a TRUST, not about a service principal.
            # The decoder marks them by shape; here that is confirmed against the real trust
            # names when a domain context is available, which is authoritative. Left as an
            # ordinary service row a referral produces a phantom principal named after the
            # remote realm, duplicating the KRB014 the trust already earns - and the etype on
            # it is the most direct evidence available that the trust is forcing RC4, so it
            # belongs on that finding rather than beside it.
            $isReferral = $false
            if ($item.EventId -eq 4769 -and $item.ServiceName) {
                if ($trustNames.Count -gt 0) {
                    $isReferral = $trustNames.Contains($item.ServiceName.Trim())
                }
                else {
                    $isReferral = [bool]$item.IsProbableRealmName
                }
            }

            if ($isReferral) {
                $realm = $item.ServiceName.Trim()
                $seen = $null
                if (-not $referralEvidence.TryGetValue($realm, [ref]$seen)) {
                    $seen = [PSCustomObject]@{
                        Realm  = $realm
                        Etypes = [System.Collections.Generic.SortedSet[int]]::new()
                        Count  = 0
                        Failures = 0
                    }
                    $referralEvidence[$realm] = $seen
                }
                $seen.Count++
                if ($item.IsFailure) { $seen.Failures++ }
                if ($null -ne $item.TicketEtype -and $item.TicketEtype -ne -1) {
                    [void]$seen.Etypes.Add($item.TicketEtype)
                }
            }

            if ($item.EventId -eq 4769 -and $item.ServiceName -and -not $isLocalKrbtgt -and -not $isReferral) {

                $serviceName = $item.ServiceName
                $resolved = $null

                if (-not $Offline) {
                    if (-not $bySpn.TryGetValue($serviceName, [ref]$resolved)) {
                        # The KDC writes ServiceName as a bare account name as often as a
                        # full SPN, so both lookups are needed before concluding it is
                        # unresolvable.
                        [void]$byAccount.TryGetValue($serviceName, [ref]$resolved)
                    }
                }

                $key = if ($resolved) { $resolved.SamAccountName } else { $serviceName }

                $entry = $null
                if (-not $observation.TryGetValue($key, [ref]$entry)) {
                    $entry = & $newObservation $key $key 'Service'
                    $observation[$key] = $entry
                }

                [void]$entry.Roles.Add('Service')
                [void]$entry.ServiceNames.Add($serviceName)
                & $touch $entry $item

                if ($null -ne $item.TicketEtype -and $item.TicketEtype -ne -1) {
                    [void]$entry.TicketEtypes.Add($item.TicketEtype)
                }
                if ($null -ne $item.SessionKeyEtype -and $item.SessionKeyEtype -ne -1) {
                    [void]$entry.SessionKeyEtypes.Add($item.SessionKeyEtype)
                }
                if ($null -ne $item.ServiceSupportedEtypes) {
                    [void]$entry.EventSupportedEtypes.Add($item.ServiceSupportedEtypes)
                }
                if ($null -ne $item.ServiceAvailableKeys) {
                    $entry.AvailableKeysKnown = $true
                    foreach ($k in $item.ServiceAvailableKeys) { [void]$entry.AvailableKeys.Add($k) }
                }
                if ($item.ClientAccount) { [void]$entry.Clients.Add($item.ClientAccount) }
                if ($item.IpAddress) { [void]$entry.ClientAddresses.Add($item.IpAddress) }
            }

            # CLIENT role, from 4768 and 4771. This is where advertisement and
            # pre-authentication evidence lives.
            if ($item.EventId -in 4768, 4771 -and $item.ClientAccount) {

                $key = $item.ClientAccount

                $entry = $null
                if (-not $observation.TryGetValue($key, [ref]$entry)) {
                    $entry = & $newObservation $key $key 'Client'
                    $observation[$key] = $entry
                }

                [void]$entry.Roles.Add('Client')
                & $touch $entry $item

                if ($null -ne $item.PreAuthEtype -and $item.PreAuthEtype -ne -1) {
                    [void]$entry.PreAuthEtypes.Add($item.PreAuthEtype)
                }
                if ($null -ne $item.SessionKeyEtype -and $item.SessionKeyEtype -ne -1) {
                    [void]$entry.SessionKeyEtypes.Add($item.SessionKeyEtype)
                }
                if ($null -ne $item.AccountSupportedEtypes) {
                    [void]$entry.EventSupportedEtypes.Add($item.AccountSupportedEtypes)
                }
                if ($null -ne $item.AccountAvailableKeys) {
                    $entry.AvailableKeysKnown = $true
                    foreach ($k in $item.AccountAvailableKeys) { [void]$entry.AvailableKeys.Add($k) }
                }
                if ($item.IpAddress) { [void]$entry.ClientAddresses.Add($item.IpAddress) }
            }
        }

        Write-Verbose "Built observations for $($observation.Count) principal(s)"

        $targetSupportsAes = $target.SupportsAes
        $emitted = 0

        foreach ($key in $observation.Keys) {
            $obs = $observation[$key]
            $findings = [System.Collections.Generic.List[object]]::new()
            $confidenceNotes = [System.Collections.Generic.List[string]]::new()

            $adPrincipal = $null
            if (-not $Offline) { [void]$byAccount.TryGetValue($obs.Key, [ref]$adPrincipal) }

            $isService = $obs.Roles.Contains('Service')
            $isClient = $obs.Roles.Contains('Client')

            # Which clients of this service cannot do AES, by name. The correlation the whole
            # module is built to make.
            $clientsWithoutAes = [System.Collections.Generic.List[string]]::new()
            $clientsUnknown = [System.Collections.Generic.List[string]]::new()

            # Every client lands in exactly one of three buckets: confirmed AES-capable (no
            # list), confirmed incapable, or unknown. The earlier shape tested AdvertisedAny
            # first and then AdvertisedAes, which silently dropped clients whose capability
            # was recorded but indeterminate - they appeared in neither list, so the report
            # neither warned about them nor counted them as unmeasured.
            foreach ($clientName in $obs.Clients) {
                $cap = $null
                $known = $clientCapability.TryGetValue($clientName, [ref]$cap)

                if ($known -and $cap.AdvertisedAes -eq $true) { continue }

                if ($known -and $cap.AdvertisedAes -eq $false) {
                    $clientsWithoutAes.Add($clientName)
                }
                else {
                    $clientsUnknown.Add($clientName)
                }
            }

            # ---- Schema confidence -------------------------------------------------------
            if (-not $obs.SawV2) {
                $confidenceNotes.Add('All events for this principal used the pre-KB5021131 schema. ' +
                    'Available-key and client-advertisement evidence was unavailable, so findings ' +
                    'rest on issued ticket encryption types alone.')
            }
            if ($obs.SawV2 -and $obs.SawLegacySchema) {
                $confidenceNotes.Add('Events came from controllers running different audit schema ' +
                    'versions. Coverage of the detailed fields is partial.')
            }
            if ($Offline) {
                $confidenceNotes.Add('Assessed offline. Directory configuration was not consulted; ' +
                    'userAccountControl overrides such as USE_DES_KEY_ONLY cannot be detected.')
            }

            # ---- KRB011: already failing -------------------------------------------------
            if ($obs.EtypeFailures.Count -gt 0) {
                $statusNames = @($obs.EtypeFailures.StatusName | Sort-Object -Unique)
                $findings.Add((New-KrbRiskFinding -Code 'KRB011' -Severity 'Critical' `
                    -Title 'Encryption-type-related authentication failures are already occurring' `
                    -Detail ("$($obs.EtypeFailures.Count) of $($obs.RequestCount) requests failed with " +
                        "$($statusNames -join ', '). This is not a prediction - it is breakage " +
                        'already happening, most likely being absorbed by client retries or a ' +
                        'fallback path. Hardening will remove the fallback.') `
                    -RecommendedAction 'Investigate before making any further encryption type change.' `
                    -Evidence @{
                        FailureCount = $obs.EtypeFailures.Count
                        RequestCount = $obs.RequestCount
                        StatusNames  = $statusNames
                        SampleTimes  = @($obs.EtypeFailures | Select-Object -First 5 -ExpandProperty TimeCreated)
                    }))
            }

            # ---- Service-role findings ---------------------------------------------------
            if ($isService) {
                $observedTickets = @($obs.TicketEtypes)
                $survivingTickets = @($observedTickets | Where-Object { & $survivesTarget $_ })

                # KRB002 - the decisive one. Available keys are ground truth from the KDC, so
                # this outranks anything the configuration says.
                if ($targetSupportsAes -and $obs.AvailableKeysKnown) {
                    $hasAesKey = @($obs.AvailableKeys) -match '^AES'
                    if (-not $hasAesKey) {
                        $findings.Add((New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' `
                            -Title 'Principal holds no AES key material' `
                            -Detail ('The KDC reported this principal''s available keys as ' +
                                "$(@($obs.AvailableKeys) -join ', ') with no AES key present. " +
                                'Kerberos keys are derived when the password is set, so applying an ' +
                                'AES-only configuration gives the KDC nothing to encrypt with and ' +
                                'authentication fails with KDC_ERR_NULL_KEY. Changing the attribute ' +
                                'is not sufficient - the password must be reset first.') `
                            -RecommendedAction ('Reset the account password to derive AES keys, confirm ' +
                                'AES appears in AvailableKeys on subsequent events, and only then ' +
                                'change msDS-SupportedEncryptionTypes.') `
                            -Evidence @{
                                AvailableKeys = @($obs.AvailableKeys)
                                RequestCount  = $obs.RequestCount
                                PasswordAgeDays = if ($adPrincipal) { $adPrincipal.PasswordAgeDays } else { $null }
                            }))
                    }
                }

                # KRB001 - every ticket this service has ever been issued uses an etype the
                # target removes.
                if ($observedTickets.Count -gt 0 -and $survivingTickets.Count -eq 0) {
                    $names = @(foreach ($e in $observedTickets) {
                        (ConvertFrom-KrbEtype -TicketEtype $e).DisplayName
                    })
                    $findings.Add((New-KrbRiskFinding -Code 'KRB001' -Severity 'Critical' `
                        -Title 'Every observed service ticket used an encryption type the change removes' `
                        -Detail ("All $($obs.RequestCount) service ticket requests in the collection " +
                            "window were issued under $($names -join ', '), none of which survive the " +
                            "target of $($target.EffectiveHex). This service has no demonstrated " +
                            'ability to operate under the proposed configuration.') `
                        -RecommendedAction ('Verify AES key material exists, then move the account to ' +
                            'RC4+AES (0x1C) first and confirm AES tickets appear before removing RC4.') `
                        -Evidence @{
                            ObservedEtypes = $names
                            RequestCount   = $obs.RequestCount
                            FirstSeen      = $obs.FirstSeen
                            LastSeen       = $obs.LastSeen
                            TargetEtypes   = $target.CipherNames
                        }))
                }
                elseif ($observedTickets.Count -gt 0 -and $survivingTickets.Count -lt $observedTickets.Count) {
                    $lost = @($observedTickets | Where-Object { -not (& $survivesTarget $_) })
                    $lostNames = @(foreach ($e in $lost) { (ConvertFrom-KrbEtype -TicketEtype $e).DisplayName })
                    $keptNames = @(foreach ($e in $survivingTickets) {
                        (ConvertFrom-KrbEtype -TicketEtype $e).DisplayName
                    })

                    $findings.Add((New-KrbRiskFinding -Code 'KRB010' -Severity 'Medium' `
                        -Title 'Service uses a mix of surviving and removed encryption types' `
                        -Detail ("Tickets were issued under both $($keptNames -join ', '), which " +
                            "survive the change, and $($lostNames -join ', '), which do not. The " +
                            'service can clearly do AES, but something in its client population or ' +
                            'its own negotiation is still selecting the weaker type.') `
                        -RecommendedAction ('Identify which clients drove the removed types before ' +
                            'proceeding; they are listed in ClientsWithoutAesSupport where advertisement ' +
                            'evidence exists.') `
                        -Evidence @{
                            Surviving = $keptNames
                            Removed = $lostNames
                            RequestCount = $obs.RequestCount
                        }))
                }

                # KRB005 - the named client list. Reported on the SERVICE because that is the
                # object whose owner has to be told.
                if ($clientsWithoutAes.Count -gt 0) {
                    # State the evidence rather than only the conclusion. A reader who has to
                    # tell an application owner their appliance is about to break deserves the
                    # count behind the claim, and a count survives a mechanism nobody has
                    # characterised yet - a bare boolean does not.
                    $noAesTotal = 0
                    $ignoredTotal = 0
                    foreach ($name in $clientsWithoutAes) {
                        $capEntry = $null
                        if ($clientCapability.TryGetValue($name, [ref]$capEntry)) {
                            $noAesTotal += $capEntry.NoAesAdvertisements
                            $ignoredTotal += $capEntry.IgnoredTgtRenewals
                        }
                    }

                    $evidenceLine = "$noAesTotal qualifying request(s) across these clients " +
                        'advertised no AES and none advertised any.'
                    if ($ignoredTotal -gt 0) {
                        $evidenceLine += " A further $ignoredTotal TGT renewal or forwarded-TGT " +
                            'request was excluded, because those carry the encryption types their ' +
                            'caller asked for rather than the ones the client supports.'
                    }

                    $findings.Add((New-KrbRiskFinding -Code 'KRB005' -Severity 'Critical' `
                        -Title "$($clientsWithoutAes.Count) client(s) of this service advertise no AES support" `
                        -Detail ('These client accounts were observed requesting tickets for this ' +
                            'service, and their own TGT requests advertised no AES encryption type at ' +
                            'all. They are not merely receiving RC4 - they are incapable of anything ' +
                            "else, and will fail outright once the KDC stops offering it. $evidenceLine") `
                        -RecommendedAction ('Patch or replace the listed clients before hardening. If ' +
                            'any is an appliance or a third-party product, its vendor needs a support ' +
                            'statement, and that is usually the longest lead time in the project.') `
                        -Evidence @{
                            Clients                  = @($clientsWithoutAes)
                            ClientCount              = $clientsWithoutAes.Count
                            TotalClients             = $obs.Clients.Count
                            NoAesAdvertisements      = $noAesTotal
                            ExcludedTgtServiceEvents = $ignoredTotal
                        }))
                }

                if ($clientsUnknown.Count -gt 0 -and $obs.Clients.Count -gt 0) {
                    $confidenceNotes.Add("$($clientsUnknown.Count) of $($obs.Clients.Count) clients had " +
                        'no TGT request in the collection window, so their encryption type capability ' +
                        'is unknown rather than confirmed.')
                }
            }

            # ---- Client-role findings ----------------------------------------------------
            if ($isClient) {
                $cap = $null
                if ($clientCapability.TryGetValue($obs.Key, [ref]$cap) -and
                    $cap.AdvertisedAny -and $cap.AdvertisedAes -eq $false) {

                    $findings.Add((New-KrbRiskFinding -Code 'KRB005' -Severity 'Critical' `
                        -Title 'This client advertises no AES encryption type' `
                        -Detail ('Across every TGT request in the window, this account offered only ' +
                            "$(@($cap.AdvertisedNames) -join ', '). A KDC that no longer offers RC4 " +
                            'has nothing in common with it and authentication fails at the first step.') `
                        -RecommendedAction ('Identify the operating system or Kerberos implementation ' +
                            'behind the listed addresses and update it. This cannot be fixed from the ' +
                            'directory side.') `
                        -Evidence @{
                            AdvertisedNames = @($cap.AdvertisedNames)
                            Addresses       = @($cap.Addresses)
                            LastSeen        = $cap.LastSeen
                        }))
                }

                $preAuth = @($obs.PreAuthEtypes)
                $preAuthLost = @($preAuth | Where-Object { -not (& $survivesTarget $_) })
                if ($preAuth.Count -gt 0 -and $preAuthLost.Count -eq $preAuth.Count) {
                    $names = @(foreach ($e in $preAuth) { (ConvertFrom-KrbEtype -TicketEtype $e).DisplayName })
                    $findings.Add((New-KrbRiskFinding -Code 'KRB008' -Severity 'High' `
                        -Title 'Pre-authentication has only ever used an encryption type the change removes' `
                        -Detail ("Every pre-authentication exchange used $($names -join ', '). " +
                            'Pre-authentication is the first cryptographic step of a logon, so this ' +
                            'account fails before it obtains a TGT, not at some later service.') `
                        -RecommendedAction 'Confirm the client platform supports AES pre-authentication.' `
                        -Evidence @{ PreAuthEtypes = $names; RequestCount = $obs.RequestCount }))
                }
            }

            # ---- Configuration findings, directory-backed --------------------------------
            if ($adPrincipal) {
                if ($adPrincipal.AccountControl.UseDesKeyOnly) {
                    $findings.Add((New-KrbRiskFinding -Code 'KRB004' -Severity 'Critical' `
                        -Title 'USE_DES_KEY_ONLY is set in userAccountControl' `
                        -Detail ('This bit confines the account to single DES and overrides ' +
                            'msDS-SupportedEncryptionTypes entirely, so the encryption type attribute ' +
                            'on this account is not being honoured. DES has been refused by default ' +
                            'since Windows Server 2008 R2.') `
                        -RecommendedAction ('Clear USE_DES_KEY_ONLY and reset the password. Clearing ' +
                            'the bit alone leaves the account with no non-DES key material.') `
                        -Evidence @{ UserAccountControl = $adPrincipal.AccountControl.Value }))
                }

                $configured = $adPrincipal.EncryptionTypes
                if ($configured.SupportsRc4 -and -not $configured.SupportsAes -and
                    -not $configured.IsUnset -and $configured.Value -ne 0) {

                    $findings.Add((New-KrbRiskFinding -Code 'KRB003' -Severity 'High' `
                        -Title 'msDS-SupportedEncryptionTypes is explicitly set to exclude AES' `
                        -Detail ("The attribute is set to $($configured.Hex), which somebody chose " +
                            'deliberately. Whatever compatibility reason produced that value needs to ' +
                            'be understood before it is reversed - it is frequently a note in a ' +
                            'runbook nobody has read since.') `
                        -RecommendedAction 'Find the original justification, then widen to 0x1C and verify.' `
                        -Evidence @{
                            ConfiguredValue = $configured.Hex
                            CipherNames     = $configured.CipherNames
                        }))
                }

                if ($adPrincipal.AccountControl.TrustedForDelegation -or
                    $adPrincipal.AccountControl.TrustedToAuthForDelegation) {

                    $findings.Add((New-KrbRiskFinding -Code 'KRB013' -Severity 'Medium' `
                        -Title 'Delegation is enabled, which widens the blast radius' `
                        -Detail ('This account is trusted for delegation, so an encryption type ' +
                            'failure here does not stop at this service - it propagates to every ' +
                            'backend the service reaches on a user''s behalf. Its true impact is ' +
                            'larger than its own client count suggests.') `
                        -RecommendedAction ("Treat this principal as a higher priority " +
                            'than its score alone implies.') `
                        -Evidence @{
                            TrustedForDelegation       = $adPrincipal.AccountControl.TrustedForDelegation
                            TrustedToAuthForDelegation = $adPrincipal.AccountControl.TrustedToAuthForDelegation
                        }))
                }

                # KRB006 - the inference used when available-key evidence is absent. Kept
                # separate from KRB002 and rated lower precisely because it is an inference.
                if (-not $obs.AvailableKeysKnown -and $targetSupportsAes -and
                    $obs.TicketEtypes.Count -gt 0 -and
                    -not (@($obs.TicketEtypes) | Where-Object { $_ -in 17, 18, 19, 20 })) {

                    $findings.Add((New-KrbRiskFinding -Code 'KRB006' -Severity 'High' `
                        -Title 'No AES ticket has been observed and key material cannot be confirmed' `
                        -Detail ('No AES ticket was issued for this principal in the window, and the ' +
                            'controllers are emitting an event schema too old to report which keys ' +
                            'exist. The account may hold AES keys and simply never have negotiated ' +
                            "them, or may hold none at all. Its password was last set " +
                            "$($adPrincipal.PasswordAgeDays) day(s) ago.") `
                        -RecommendedAction ('Install the November 2022 or later cumulative update on the ' +
                            'domain controllers to obtain version 2 audit events, or reset the ' +
                            'password to guarantee AES keys exist.') `
                        -Evidence @{
                            PasswordAgeDays = $adPrincipal.PasswordAgeDays
                            PasswordLastSet = $adPrincipal.PasswordLastSet
                            ObservedEtypes  = @($obs.TicketEtypes)
                        }))
                }
            }

            # ---- DES anywhere ------------------------------------------------------------
            $desSeen = @(@($obs.TicketEtypes) + @($obs.SessionKeyEtypes) + @($obs.PreAuthEtypes) |
                Where-Object { $_ -in 1, 2, 3, 5, 7, 16 })
            if ($desSeen.Count -gt 0) {
                $findings.Add((New-KrbRiskFinding -Code 'KRB007' -Severity 'Critical' `
                    -Title 'Single DES encryption was observed in use' `
                    -Detail ('DES has been cryptographically broken for two decades and disabled by ' +
                        'default since Windows Server 2008 R2. Its presence here means the domain is ' +
                        'carrying an explicit allowance that any hardening will remove.') `
                    -RecommendedAction 'Treat as an immediate security finding, independent of the RC4 project.' `
                    -Evidence @{ ObservedEtypes = @($desSeen | Sort-Object -Unique) }))
            }

            # ---- Nothing found: healthy, or merely unexamined? ---------------------------
            #
            # These two outcomes look identical in a naive engine and mean opposite things.
            # A principal assessed against version 2 events and directory configuration, with
            # nothing wrong, is evidence of safety. A principal seen only through the legacy
            # schema, with no directory record, is the absence of evidence - the fields that
            # would have revealed a problem were never written. Reporting the second as "no
            # impact predicted" is how an assessment gives false assurance about exactly the
            # principals it understood least.
            if ($findings.Count -eq 0) {

                $hasUsableEvidence = $obs.SawV2 -or $adPrincipal

                if ($hasUsableEvidence) {
                    $findings.Add((New-KrbRiskFinding -Code 'KRB009' -Severity 'Info' `
                        -Title 'No impact predicted from the proposed change' `
                        -Detail ("All $($obs.RequestCount) observed request(s) used encryption types that " +
                            'survive the target configuration, and no configuration override was found.') `
                        -Evidence @{
                            RequestCount   = $obs.RequestCount
                            ObservedEtypes = @($obs.TicketEtypes)
                            AvailableKeys  = if ($obs.AvailableKeysKnown) { @($obs.AvailableKeys) } else { $null }
                        }))
                }
                else {
                    $findings.Add((New-KrbRiskFinding -Code 'KRB015' -Severity 'Low' `
                        -Title 'Insufficient evidence to assess this principal' `
                        -Detail ("This principal was seen $($obs.RequestCount) time(s), but only through " +
                            'the pre-KB5021131 audit schema, and it could not be matched to a directory ' +
                            'object. Neither the keys it holds nor the encryption types it can negotiate ' +
                            'were recorded anywhere. Nothing was found wrong with it, and nothing would ' +
                            'have been found wrong with it had it been broken.') `
                        -RecommendedAction ('Update the domain controllers to obtain version 2 audit ' +
                            'events, or re-run with directory access, before treating this principal as safe.') `
                        -Evidence @{
                            RequestCount   = $obs.RequestCount
                            ObservedEtypes = @($obs.TicketEtypes)
                            Sources        = @($obs.Sources)
                        }))
                }
            }

            $summary = Measure-KrbRiskLevel -Finding $findings.ToArray() -ClientCount $obs.Clients.Count

            if (-not $IncludeHealthy -and $summary.Level -in 'Info', 'None') { continue }

            $emitted++

            New-KrbRiskObject -PrincipalName $obs.Key -Finding $findings.ToArray() `
                -Summary $summary -Role @($obs.Roles) -Observation $obs `
                -Principal $adPrincipal -TargetEncryptionTypes $target `
                -ClientsWithoutAesSupport @($clientsWithoutAes) `
                -ClientsWithUnknownSupport @($clientsUnknown) `
                -ConfidenceNote @($confidenceNotes) -CorrelationId $correlationId
        }

        # ---- Principals with dangerous configuration and no traffic in the window --------
        #
        # The engine above is observational, and an observational engine is blind to an
        # account that simply did not authenticate during the collection. That blindness is
        # dangerous in exactly the wrong direction: a DES-only account used by a quarterly
        # batch job produces no events in a thirty-day window and would be reported as
        # absent rather than as the blocker it is. Only configurations that are unsafe on
        # their face are reported this way, so this pass adds a handful of rows to a domain
        # of thousands rather than an inventory of everything that was quiet.
        if (-not $Offline -and $byAccount.Count -gt 0) {

            foreach ($name in $byAccount.Keys) {
                if ($observation.ContainsKey($name)) { continue }

                $item = $byAccount[$name]
                if ($item.Enabled -eq $false) { continue }

                $configured = $item.EncryptionTypes
                $unobservedFindings = [System.Collections.Generic.List[object]]::new()

                if ($item.AccountControl.UseDesKeyOnly) {
                    $unobservedFindings.Add((New-KrbRiskFinding -Code 'KRB004' -Severity 'Critical' `
                        -Title 'USE_DES_KEY_ONLY is set on an account with no traffic in the window' `
                        -Detail ('The account is confined to single DES by userAccountControl and did ' +
                            'not authenticate during the collection window. Absence of traffic is not ' +
                            'evidence of disuse - a quarterly or annual job produces none in thirty days.') `
                        -RecommendedAction ('Establish what uses this account before hardening. Clear ' +
                            'USE_DES_KEY_ONLY and reset the password.') `
                        -Evidence @{
                            UserAccountControl = $item.AccountControl.Value
                            LastLogonTimestamp = $item.LastLogonTimestamp
                        }))
                }
                elseif ($configured.SupportsDes -and -not $configured.SupportsAes -and
                        -not $configured.SupportsRc4 -and -not $configured.IsUnset) {

                    $unobservedFindings.Add((New-KrbRiskFinding -Code 'KRB007' -Severity 'Critical' `
                        -Title 'Account is configured for DES only and has no traffic in the window' `
                        -Detail ("msDS-SupportedEncryptionTypes is $($configured.Hex), which permits " +
                            'only single DES. DES has been refused by default since Windows Server ' +
                            '2008 R2, so this account is either already failing or is being carried by ' +
                            'an explicit domain-wide DES allowance that hardening removes.') `
                        -RecommendedAction 'Identify the consumer, move to AES, and reset the password.' `
                        -Evidence @{
                            ConfiguredValue    = $configured.Hex
                            CipherNames        = $configured.CipherNames
                            LastLogonTimestamp = $item.LastLogonTimestamp
                        }))
                }
                elseif (-not $configured.IsUnset -and $configured.Value -ne 0 -and
                        @($configured.TicketEtypes).Count -eq 0) {

                    # The account is configured for no usable ticket encryption type at all.
                    # Reached most readily by setting only the RFC 8009 SHA-2 bits, which
                    # Windows does not honour - a Server 2025 KDC returned
                    # KDC_ERR_ETYPE_NOTSUPP for exactly this configuration - but any value
                    # whose bits authorise nothing lands here.
                    #
                    # This branch was missing until a regression test written from that lab
                    # result went looking for it. The three conditions above it test for DES,
                    # for USE_DES_KEY_ONLY and for RC4-without-AES, and an account that
                    # supports nothing matches none of them, so it produced no row at all.
                    $unobservedFindings.Add((New-KrbRiskFinding -Code 'KRB007' -Severity 'Critical' `
                        -Title 'Account is configured for no usable encryption type' `
                        -Detail ("msDS-SupportedEncryptionTypes is $($configured.Hex), which " +
                            'authorises no ticket encryption type the KDC will issue. Bits 0x40 ' +
                            'and 0x80 are the usual cause: MS-KILE documents them as the RFC 8009 ' +
                            'SHA-2 types, but Windows does not honour them, so an account carrying ' +
                            'only those bits cannot obtain a service ticket at all.') `
                        -RecommendedAction ('Add AES128 (0x08) and AES256 (0x10) - the SHA1 types - ' +
                            'which are what Windows actually issues.') `
                        -Evidence @{
                            ConfiguredValue = $configured.Hex
                            CipherNames     = $configured.CipherNames
                            CarriesUnhonouredSha2Bits = $configured.CarriesUnhonouredSha2Bits
                            LastLogonTimestamp = $item.LastLogonTimestamp
                        }))
                }
                elseif ($configured.SupportsRc4 -and -not $configured.SupportsAes -and
                        -not $configured.IsUnset -and $configured.Value -ne 0) {

                    $unobservedFindings.Add((New-KrbRiskFinding -Code 'KRB012' -Severity 'Medium' `
                        -Title 'Account is explicitly configured without AES and has no traffic in the window' `
                        -Detail ("msDS-SupportedEncryptionTypes is $($configured.Hex), set deliberately " +
                            'to exclude AES, and no authentication was observed. There is no evidence ' +
                            'either way about whether hardening breaks it - which is a different ' +
                            'statement from evidence that it is safe.') `
                        -RecommendedAction ('Extend the collection window, or check lastLogonTimestamp ' +
                            'and the owning application''s schedule, before assuming this account is dormant.') `
                        -Evidence @{
                            ConfiguredValue    = $configured.Hex
                            LastLogonTimestamp = $item.LastLogonTimestamp
                            PasswordAgeDays    = $item.PasswordAgeDays
                        }))
                }

                if ($unobservedFindings.Count -eq 0) { continue }

                $unobservedSummary = Measure-KrbRiskLevel -Finding $unobservedFindings.ToArray()
                $emitted++

                New-KrbRiskObject -PrincipalName $item.SamAccountName `
                    -Finding $unobservedFindings.ToArray() -Summary $unobservedSummary `
                    -Role @('Unobserved') -Principal $item `
                    -ConfiguredEncryptionTypes $configured -TargetEncryptionTypes $target `
                    -ConfidenceNote @(
                        'No authentication by this principal was observed in the collection ' +
                        'window. The finding rests entirely on directory configuration.'
                    ) -CorrelationId $correlationId
            }
        }

        # ---- Domain-scope findings, emitted alongside the per-principal ones -------------
        if ($DomainContext) {
            foreach ($trust in @($DomainContext.TrustsWithRc4Only)) {

                # Evidence is assembled before the finding is built rather than inside the
                # -Evidence argument. An inline script block there parses badly enough to
                # break the whole module load, and this reads better anyway.
                $trustEvidence = @{
                    Trust     = $trust.Name
                    Direction = "$($trust.Direction)"
                    TrustType = "$($trust.TrustType)"
                    Value     = $trust.EncryptionTypes.EffectiveHex
                }

                # Observed referral traffic over this trust, where the collection contained
                # any. This is what turns KRB014 from a statement about configuration into an
                # observation: the etypes recorded here are what the KDC actually issued for
                # cross-realm requests, measured rather than inferred from the attribute.
                $observedReferral = $null
                foreach ($key in @($trust.Name, $trust.Target)) {
                    if ($key -and $referralEvidence.TryGetValue($key, [ref]$observedReferral)) {
                        break
                    }
                }

                if ($observedReferral) {
                    $trustEvidence['ObservedReferrals'] = $observedReferral.Count
                    $trustEvidence['ObservedReferralFailures'] = $observedReferral.Failures
                    $trustEvidence['ObservedReferralEtypes'] = @(
                        foreach ($e in $observedReferral.Etypes) {
                            (ConvertFrom-KrbEtype -TicketEtype $e).DisplayName
                        })
                }

                $trustFindings = @(New-KrbRiskFinding -Code 'KRB014' -Severity 'High' `
                    -Title 'Trust does not permit AES for cross-realm authentication' `
                    -Detail ("The trust to $($trust.Target) has msDS-SupportedEncryptionTypes of " +
                        "$($trust.EncryptionTypes.EffectiveHex), which carries no AES bit. Every " +
                        'cross-realm ticket over this trust is pinned to RC4 regardless of what the ' +
                        'accounts on either side support. This is the usual reason a domain that has ' +
                        '"finished" removing RC4 keeps issuing it.') `
                    -RecommendedAction ('Set AES support on the trustedDomain object on both sides. ' +
                        'This requires the other realm''s cooperation and is typically the longest ' +
                        'lead item in a hardening project.') `
                    -Evidence $trustEvidence)

                $trustSummary = Measure-KrbRiskLevel -Finding $trustFindings

                $emitted++

                # KRB014 is added to the breaking set for this row only. A trust that permits
                # no AES does break cross-realm authentication, but the code is not in the
                # default breaking list because on a per-principal row it would be meaningless.
                New-KrbRiskObject -PrincipalName $trust.Name -Finding $trustFindings `
                    -Summary $trustSummary -Role @('Trust') `
                    -ConfiguredEncryptionTypes $trust.EncryptionTypes `
                    -TargetEncryptionTypes $target `
                    -BreakingCode @('KRB014') `
                    -ConfidenceNote @(
                        'Derived from directory configuration; no event evidence applies to trusts.'
                    ) -CorrelationId $correlationId
            }
        }

        Write-Verbose ("Completed $($MyInvocation.MyCommand.Name) - emitted $emitted risk object(s) " +
            "from $($observation.Count) observed principal(s) - CorrelationId: $correlationId")
    }
}
