#Requires -Version 7.6

function ConvertFrom-KrbEtype {
    <#
    .SYNOPSIS
        Decodes Kerberos encryption type values from any of the three forms Windows emits them in

    .DESCRIPTION
        Turns a raw Kerberos encryption-type value into a described object. Which decoding is
        applied depends on which parameter is used, because the three forms are three
        different data types that happen to be written as small integers:

        - -TicketEtype decodes an RFC 3961 encryption type NUMBER, the form found in the
          TicketEncryptionType, SessionKeyEncryptionType and PreAuthEncryptionType fields of
          events 4768 and 4769. In this system RC4-HMAC is 23 (0x17) and
          AES256-CTS-HMAC-SHA1-96 is 18 (0x12).

        - -SupportedEncryptionTypes decodes an MS-KILE 2.2.7 BITMASK, the form found in the
          msDS-SupportedEncryptionTypes attribute, in the DefaultDomainSupportedEncTypes
          registry value, on trustedDomain objects, and in the *SupportedEncryptionTypes
          fields of version 2 events. In this system RC4-HMAC is bit 0x4 and
          AES256-CTS-HMAC-SHA1-96 is bit 0x10.

        - -AdvertizedEtype decodes the newline-separated list of Windows etype NAMES found in
          the ClientAdvertizedEncryptionTypes field of a version 2 event - the list of
          algorithms the client actually offered on the wire.

        The two numeric systems are not interconvertible by arithmetic and this function
        never treats them as if they were. Passing a ticket etype to
        -SupportedEncryptionTypes decodes 23 as DES-CBC-CRC + DES-CBC-MD5 + RC4-HMAC +
        AES128, which is meaningless; the parameter sets exist to make that mistake require
        deliberate effort.

        Business value: this is the decode layer the rest of the module and the risk report
        are built on. It has no dependency on Active Directory or on the event log, so it can
        be exercised in full against captured fixtures with no domain present.

    .PARAMETER TicketEtype
        [System.Object] (Mandatory in the TicketEtype set, Pipeline: ByValue)

        An RFC 3961 encryption type number. Accepts an integer, a hex string such as '0x12',
        or a decimal string. The KDC's no-ticket-issued sentinel - 0xffffffff, written on
        every failure event - decodes to a NotApplicable result rather than to a cipher.

    .PARAMETER SupportedEncryptionTypes
        [System.Object] (Mandatory in the SupportedEncryptionTypes set, Pipeline: ByValue)

        An MS-KILE supported-encryption-types bitmask. Accepts an integer, a hex string, or
        the full rendering a version 2 event uses, such as
        '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'. Pass $null to describe an attribute
        that is not set at all, which is a different state from a value of 0 in every respect
        except its effect.

    .PARAMETER AdvertizedEtype
        [System.String[]] (Mandatory in the AdvertizedEtype set, Pipeline: ByValue)

        The etype names a client advertised. Accepts either the raw multi-line, tab-indented
        block exactly as it appears in ClientAdvertizedEncryptionTypes, or an array of
        individual name strings.

    .PARAMETER DomainDefaultEncryptionTypes
        [System.Int32] (Optional, No Pipeline Support)

        The bitmask the KDC falls back to when msDS-SupportedEncryptionTypes is unset or
        zero - that is, the DefaultDomainSupportedEncTypes registry value on the domain
        controllers. Defaults to 0x27, which is the Windows default when the value has never
        been written.

        Supply the real value from Get-KrbDomainEtypeContext when assessing a live domain.
        Getting this wrong is how an assessment concludes that several hundred accounts with
        an unset attribute support nothing at all, or that they support RC4 only - neither is
        true, because 0x27 also carries the AES256 session-key bit.

    .EXAMPLE
        PS> ConvertFrom-KrbEtype -TicketEtype '0x17'

        DESCRIPTION: Decodes a ticket encryption type taken straight from a 4769 event
        OUTPUT: An object naming RC4-HMAC, family RC4, strength Weak, RemovedByHardening true
        USE CASE: Establishing that a service ticket was issued under RC4

    .EXAMPLE
        PS> ConvertFrom-KrbEtype -SupportedEncryptionTypes 24

        DESCRIPTION: Decodes an AES-only msDS-SupportedEncryptionTypes value
        OUTPUT: AES128 and AES256 flags set, SupportsRc4 false, SupportsAes true
        USE CASE: Confirming an account has already been hardened

    .EXAMPLE
        PS> ConvertFrom-KrbEtype -SupportedEncryptionTypes $null -DomainDefaultEncryptionTypes 0x27

        DESCRIPTION: Describes an account whose attribute has never been set
        OUTPUT: UsesDomainDefault true, and the effective flags the KDC will actually apply
        USE CASE: Assessing the several hundred accounts in a typical domain that inherit the default

    .EXAMPLE
        PS> ConvertFrom-KrbEtype -AdvertizedEtype "AES256-CTS-HMAC-SHA1-96`n`tRC4-HMAC-NT"

        DESCRIPTION: Decodes what a client offered on the wire
        OUTPUT: Both etypes resolved, SupportsAes true - this client survives hardening
        USE CASE: Distinguishing a client that merely received RC4 from one that can only do RC4

    .EXAMPLE
        PS> Get-KrbEvent -MaxEvents 500 | ForEach-Object { ConvertFrom-KrbEtype -TicketEtype $_.TicketEtype } |
                Group-Object DisplayName | Sort-Object Count -Descending

        DESCRIPTION: Profiles which ciphers a domain is actually issuing tickets under
        OUTPUT: A count per encryption type across the sampled events
        USE CASE: The first question to answer before any hardening change is scheduled

    .INPUTS
        System.Object. Accepts etype values by value from the pipeline.

    .OUTPUTS
        KrbEtypeInsight.TicketEtype, KrbEtypeInsight.EtypeFlags, or
        KrbEtypeInsight.AdvertizedEtypeSet, depending on the parameter set used.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Unknown or unexpected etype values: .\Troubleshooting\Common\Unknown-Encryption-Types.md
        - Bitmask versus ticket etype confusion: .\Troubleshooting\Common\Etype-Numbering-Systems.md

    .LINK
        https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-kile/6cfc7b50-11ed-4b4d-846d-6f08f0812919

    .LINK
        https://www.rfc-editor.org/rfc/rfc3961
    #>
    [CmdletBinding(DefaultParameterSetName = 'TicketEtype')]
    [OutputType('KrbEtypeInsight.TicketEtype', ParameterSetName = 'TicketEtype')]
    [OutputType('KrbEtypeInsight.EtypeFlags', ParameterSetName = 'SupportedEncryptionTypes')]
    [OutputType('KrbEtypeInsight.AdvertizedEtypeSet', ParameterSetName = 'AdvertizedEtype')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'TicketEtype')]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$TicketEtype,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'SupportedEncryptionTypes')]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$SupportedEncryptionTypes,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'AdvertizedEtype')]
        [AllowNull()]
        [AllowEmptyString()]
        [string[]]$AdvertizedEtype,

        [Parameter(ParameterSetName = 'SupportedEncryptionTypes')]
        [int]$DomainDefaultEncryptionTypes = 0x27
    )

    begin {
        $catalog = Get-KrbEtypeCatalog
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {

            'TicketEtype' {
                $value = ConvertTo-KrbInt32 -Value $TicketEtype

                if ($null -eq $value) {
                    # An absent field is reported as absent. Returning nothing here would
                    # silently shorten a pipeline and make a 4771 disappear from a count.
                    [PSCustomObject]@{
                        PSTypeName         = 'KrbEtypeInsight.TicketEtype'
                        Value              = $null
                        Hex                = $null
                        DisplayName        = 'Not present'
                        Family             = 'None'
                        Strength           = 'NotApplicable'
                        Rfc                = 'n/a'
                        RemovedByHardening = $false
                        IsRecognized       = $false
                    }
                    return
                }

                $known = $catalog.TicketEtype[$value]

                if ($known) {
                    [PSCustomObject]@{
                        PSTypeName         = 'KrbEtypeInsight.TicketEtype'
                        Value              = $value
                        Hex                = '0x{0:X}' -f $value
                        DisplayName        = $known.DisplayName
                        Family             = $known.Family
                        Strength           = $known.Strength
                        Rfc                = $known.Rfc
                        RemovedByHardening = $known.RemovedByHardening
                        IsRecognized       = $true
                    }
                    return
                }

                # An unrecognised value is surfaced, never swallowed. A new Windows release
                # adding an etype must show up as an explicit unknown in the report rather
                # than as a silently dropped row.
                Write-Verbose "Encryption type $value is not in the catalog"
                [PSCustomObject]@{
                    PSTypeName         = 'KrbEtypeInsight.TicketEtype'
                    Value              = $value
                    Hex                = '0x{0:X}' -f $value
                    DisplayName        = "Unknown ($value)"
                    Family             = 'Unknown'
                    Strength           = 'Unknown'
                    Rfc                = 'Unknown'
                    RemovedByHardening = $false
                    IsRecognized       = $false
                }
            }

            'SupportedEncryptionTypes' {
                $raw = ConvertTo-KrbInt32 -Value $SupportedEncryptionTypes

                # Unset and zero are different states with the same effect, and the
                # distinction is worth keeping: an unset attribute is an account nobody has
                # touched, a zero is an account somebody explicitly zeroed. Both fall through
                # to the domain default, so both get the same effective value.
                $isUnset = $null -eq $raw
                $usesDefault = $isUnset -or $raw -eq 0
                $effective = if ($usesDefault) { $DomainDefaultEncryptionTypes } else { $raw }

                $cipherNames = [System.Collections.Generic.List[string]]::new()
                $capabilityNames = [System.Collections.Generic.List[string]]::new()

                # SortedSet rather than a List piped through Sort-Object -Unique. The result
                # is identical and this decoder runs once per principal and once per event,
                # where a cmdlet pipeline is the difference between an assessment finishing
                # in two minutes and in twenty.
                $ticketEtypes = [System.Collections.Generic.SortedSet[int]]::new()
                $sessionKeyEtypes = [System.Collections.Generic.SortedSet[int]]::new()

                foreach ($bit in $catalog.SortedFlagKeys) {
                    if (($effective -band $bit) -eq 0) { continue }

                    $entry = $catalog.FlagToTicketEtype[$bit]

                    if ($bit -band $catalog.CipherFlagMask) {
                        $cipherNames.Add($entry.Name)
                    }
                    else {
                        $capabilityNames.Add($entry.Name)
                    }

                    foreach ($etype in $entry.TicketEtypes) { [void]$ticketEtypes.Add($etype) }
                    foreach ($etype in $entry.SessionKeyEtypes) { [void]$sessionKeyEtypes.Add($etype) }
                }

                # Bits Microsoft has added since this module was written. Preserved rather
                # than masked away, so an assessment run against a future Windows release
                # reports "I do not understand bit 0x100" instead of quietly under-reporting
                # what an account supports.
                $unknownBits = $effective -band (-bnot $catalog.KnownFlagMask)

                # 0x20 authorises AES256 for the session key only. An account holding 0x20
                # and no other AES bit will issue AES session keys inside RC4 tickets, which
                # looks like AES support in a session-key-only view of the data and like no
                # AES support in a ticket view. Both properties are exposed so the caller
                # cannot accidentally pick the flattering one.
                # SHA1 AES bits only. The RFC 8009 bits 0x40 and 0x80 are excluded because a
                # real Server 2025 KDC was observed refusing to issue a ticket for an account
                # that carried only them - see Get-KrbEtypeCatalog. Counting them as AES
                # support reported an unauthenticatable account as safe.
                $aesTicketBits = 0x08 -bor 0x10
                $sha2Bits = 0x40 -bor 0x80

                [PSCustomObject]@{
                    PSTypeName                = 'KrbEtypeInsight.EtypeFlags'
                    Value                     = $raw
                    Hex                       = if ($isUnset) { $null } else { '0x{0:X}' -f $raw }
                    EffectiveValue            = $effective
                    EffectiveHex              = '0x{0:X}' -f $effective
                    IsUnset                   = $isUnset
                    UsesDomainDefault         = $usesDefault

                    # Masked to known bits before the cast. Casting a value carrying an
                    # undefined bit to a [Flags] enum is a terminating PSInvalidCastException
                    # - "due to enumeration values that are not valid" - not a best-effort
                    # decomposition. Unmasked, the first time Microsoft adds a bit to
                    # msDS-SupportedEncryptionTypes this function would start throwing on any
                    # account that had it, taking the whole assessment down rather than
                    # reporting one unfamiliar bit. UnknownBits below carries what was masked
                    # off, so nothing is lost.
                    Flags                     = [KrbEtypeFlag]($effective -band $catalog.KnownFlagMask)
                    FlagNames                 = @($cipherNames) + @($capabilityNames)
                    CipherNames               = @($cipherNames)
                    CapabilityNames           = @($capabilityNames)
                    TicketEtypes              = [int[]]$ticketEtypes
                    SessionKeyEtypes          = [int[]]$sessionKeyEtypes
                    SupportsDes               = [bool]($effective -band 0x03)
                    SupportsRc4               = [bool]($effective -band 0x04)
                    SupportsAes               = [bool]($effective -band $aesTicketBits)
                    SupportsAesSessionKeyOnly = (($effective -band 0x20) -ne 0) -and
                                                (($effective -band $aesTicketBits) -eq 0)
                    SupportsFast              = [bool]($effective -band 0x00010000)

                    # True when the value carries an RFC 8009 SHA-2 bit. Windows Server 2025
                    # build 26100 was observed NOT honouring these: an account holding only
                    # them received KDC_ERR_ETYPE_NOTSUPP, and one holding 0x80 alongside 0x10
                    # was served etype 0x12 with the 0x80 ignored. The bits are named in
                    # CipherNames so nothing is hidden, but they are excluded from SupportsAes
                    # because on observed Windows they confer no usable ticket encryption.
                    CarriesUnhonouredSha2Bits = [bool]($effective -band $sha2Bits)
                    UnknownBits               = $unknownBits
                    UnknownBitsHex            = if ($unknownBits) { '0x{0:X}' -f $unknownBits } else { $null }
                }
            }

            'AdvertizedEtype' {
                # This branch runs once per collected event, so it is written for throughput
                # rather than for brevity: String.Split against a cached char array instead
                # of a regex, plain loops instead of ForEach-Object and Where-Object, and
                # SortedSet instead of Sort-Object -Unique. Written the idiomatic way it
                # measured at 1.7 ms per call, which is several minutes across a real
                # collection and was the single largest cost in the whole decode path.
                $names = [System.Collections.Generic.List[string]]::new()

                foreach ($chunk in $AdvertizedEtype) {
                    if ([string]::IsNullOrWhiteSpace($chunk)) { continue }

                    foreach ($piece in $chunk.Split($catalog.AdvertizedSeparator,
                            [System.StringSplitOptions]::RemoveEmptyEntries)) {
                        $trimmed = $piece.Trim()
                        if ($trimmed) { $names.Add($trimmed) }
                    }
                }

                $resolved = [System.Collections.Generic.SortedSet[int]]::new()
                $families = [System.Collections.Generic.SortedSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase)
                $unrecognized = [System.Collections.Generic.List[string]]::new()

                foreach ($name in $names) {
                    # PowerShell hashtables are case-insensitive, so no case folding is
                    # needed on the key - and folding it would cost an allocation per name.
                    $etype = $catalog.AdvertizedName[$name]

                    if ($null -ne $etype) {
                        [void]$resolved.Add($etype)
                        $entry = $catalog.TicketEtype[$etype]
                        if ($entry) { [void]$families.Add($entry.Family) }
                    }
                    else {
                        $unrecognized.Add($name)
                    }
                }

                [PSCustomObject]@{
                    PSTypeName        = 'KrbEtypeInsight.AdvertizedEtypeSet'
                    Names             = [string[]]$names
                    Etypes            = [int[]]$resolved
                    Families          = [string[]]$families
                    SupportsAes       = $families.Contains('AES')
                    SupportsRc4       = $families.Contains('RC4')
                    SupportsDes       = $families.Contains('DES')

                    # The whole point of the module in one property. A client that advertised
                    # at least one algorithm, all of them understood, and none of them AES,
                    # cannot authenticate against a hardened KDC. This is direct evidence,
                    # not an inference from what the KDC happened to choose.
                    #
                    # The unrecognised-names clause is what keeps it honest. Without it, a
                    # client advertising only names this catalog has never heard of resolves
                    # to no families at all, which is indistinguishable from "no AES" - so a
                    # client running an algorithm newer than the module would be reported as
                    # legacy-only and raise a Critical saying it advertises no AES support.
                    # That is exactly the unknown-read-as-negative mistake the null handling
                    # everywhere else in this module exists to prevent, and it is worse here
                    # because it fires on the most modern clients in the estate.
                    #
                    # An advertisement containing anything unrecognised therefore yields
                    # $false - meaning "not established", not "capable". Callers that need
                    # the three-way distinction read SupportsAes and UnrecognizedNames.
                    LegacyOnly        = ($names.Count -gt 0) -and
                                        ($unrecognized.Count -eq 0) -and
                                        (-not $families.Contains('AES'))

                    UnrecognizedNames = [string[]]$unrecognized
                }
            }
        }
    }
}
