#Requires -Version 7.6

<#
    Kerberos encryption types are described by TWO different numbering systems, and conflating
    them is the single most common error in RC4-hardening scripts found in the wild.

    1. RFC 3961 encryption type NUMBERS. These are ordinals, not bits. RC4-HMAC is 23 (0x17),
       AES256-CTS-HMAC-SHA1-96 is 18 (0x12). They appear in the 4768/4769 fields
       TicketEncryptionType, SessionKeyEncryptionType and PreAuthEncryptionType, and in
       KDC error text. Modelled below by [KrbTicketEtype].

    2. MS-KILE 2.2.7 supported-encryption-type BIT FLAGS. These are a bitmask. RC4-HMAC is
       bit 0x4, AES256-CTS-HMAC-SHA1-96 is bit 0x10. They appear in the AD attribute
       msDS-SupportedEncryptionTypes, in the DefaultDomainSupportedEncTypes registry value,
       on trustedDomain objects, and in the 4768/4769 fields *SupportedEncryptionTypes.
       Modelled below by [KrbEtypeFlag].

    So RC4 is "23" in one system and "4" in the other, and AES256 is "18" in one and "16" in
    the other. A script that tests a ticket's TicketEncryptionType against the value 4 is
    testing for DES-CBC-MD4, not RC4, and will report every RC4 ticket in the estate as clean.
    Both enums are therefore named for the system they belong to, and nothing in this module
    converts between them by arithmetic - the mapping is an explicit table in
    Get-KrbEtypeCatalog, because it is not a computable relationship.

    These types are dot-sourced into the module scope and are not exported. Public functions
    surface decoded values as strings and typed PSCustomObjects so that callers never need
    'using module' to consume output.
#>

<#
    RFC 3961 section 8 / IANA "Kerberos Encryption Type Numbers" registry, plus the
    Microsoft-proprietary negative values that Windows clients still advertise.

    The negative members exist because Windows really does put them on the wire. A client
    advertising -133 (RC4-MD4) alongside AES is harmless; a client advertising ONLY negative
    values and 23/24 is a client that hardening will break, so the module has to be able to
    name them rather than discarding them as unknown.
#>
enum KrbTicketEtype {
    # RFC 3961 - deprecated single-DES. Present here so the module can name what it finds;
    # any appearance of these in a modern estate is a finding in its own right.
    DesCbcCrc               = 1
    DesCbcMd4               = 2
    DesCbcMd5               = 3
    Des3CbcMd5              = 5
    Des3CbcSha1             = 7
    Des3CbcSha1Kd           = 16

    # RFC 3962 - the AES types Windows has shipped since Server 2008.
    Aes128CtsHmacSha1_96    = 17
    Aes256CtsHmacSha1_96    = 18

    # RFC 8009 - SHA-2 AES. Windows Server 2025 and Windows 11 24H2 KDCs can issue these;
    # earlier KDCs cannot, so seeing them constrains which DC served the request.
    Aes128CtsHmacSha256_128 = 19
    Aes256CtsHmacSha384_192 = 20

    # RFC 4757 - the types this module exists to help you remove.
    Rc4Hmac                 = 23
    Rc4HmacExp              = 24

    # RFC 6803 - Camellia. Not implemented by Windows; named so a cross-realm ticket from a
    # non-Windows KDC does not read as 'Unknown'.
    Camellia128CtsCmac      = 25
    Camellia256CtsCmac      = 26

    # Microsoft-proprietary. Advertised by Windows clients in the AS-REQ etype list.
    Rc4HmacOld              = -133
    Rc4Md4                  = -128
    Rc4HmacOldExp           = -135

    # Not an algorithm. The KDC writes 0xFFFFFFFF into TicketEncryptionType when no ticket
    # was issued - that is, on every failure event. Decoding it as an etype produces the
    # nonsense reading "this account used encryption type 4294967295", which is how audit
    # scripts end up reporting failures as an exotic cipher. It is modelled explicitly so the
    # module can say "no ticket issued" instead.
    NotApplicable           = -1
}

<#
    MS-KILE 2.2.7 "Supported Encryption Types Bit Flags", as carried in
    msDS-SupportedEncryptionTypes.

    [Flags] matters: PowerShell's enum formatter will decompose a combined value into its
    member names, which is exactly the human-readable rendering the report needs. Bits with
    no member here are preserved separately as UnknownBits rather than being dropped, because
    Microsoft has added bits to this attribute twice and will do so again - silently
    discarding an unrecognised bit would let the module report an account as AES-only when it
    is not.
#>
[Flags()]
enum KrbEtypeFlag {
    None                        = 0x00000000

    DesCbcCrc                   = 0x00000001
    DesCbcMd5                   = 0x00000002
    Rc4Hmac                     = 0x00000004
    Aes128CtsHmacSha1_96        = 0x00000008
    Aes256CtsHmacSha1_96        = 0x00000010

    # 0x20 is NOT a sixth cipher. MS-KILE defines it as
    # "AES256-CTS-HMAC-SHA1-96-SK" - permission to use AES256 for the SESSION KEY only,
    # while the ticket itself stays on the account's other supported types. It is set by
    # default domain policy (part of the 0x27 default), which is why so many accounts that
    # look DES+RC4-only in a naive decode are in fact issuing AES session keys. Treating
    # 0x20 as "supports AES256" overstates readiness; treating it as unknown understates it.
    Aes256CtsHmacSha1_96Sk      = 0x00000020

    # RFC 8009 SHA-2 types, added for Windows Server 2025 / Windows 11 24H2.
    Aes128CtsHmacSha256_128     = 0x00000040
    Aes256CtsHmacSha384_192     = 0x00000080

    # Capability bits, not ciphers. They ride in the same attribute and must not be counted
    # when answering "does this account support AES?".
    FastSupported               = 0x00010000
    CompoundIdentitySupported   = 0x00020000
    ClaimsSupported             = 0x00040000
    ResourceSidCompressionDisabled = 0x00080000
}
