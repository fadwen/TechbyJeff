# The two Kerberos encryption type numbering systems

The single most common error in RC4-hardening scripts, and the reason this module models the
two systems as separate types.

## The problem

Kerberos encryption types are described by two different numbering systems that both look like
small integers. They are not interchangeable, and nothing in the field names warns you.

### RFC 3961 encryption type numbers

Ordinals, not bits. These appear in:

- `TicketEncryptionType`, `SessionKeyEncryptionType` and `PreAuthEncryptionType` on events
  4768 and 4769
- KDC error text
- `klist` output

| Value | Hex | Algorithm |
|---|---|---|
| 1 | `0x1` | DES-CBC-CRC |
| 3 | `0x3` | DES-CBC-MD5 |
| 17 | `0x11` | AES128-CTS-HMAC-SHA1-96 |
| 18 | `0x12` | AES256-CTS-HMAC-SHA1-96 |
| 19 | `0x13` | AES128-CTS-HMAC-SHA256-128 (RFC 8009) |
| 20 | `0x14` | AES256-CTS-HMAC-SHA384-192 (RFC 8009) |
| 23 | `0x17` | RC4-HMAC |
| 24 | `0x18` | RC4-HMAC-EXP |
| -128 | | RC4-MD4 (Microsoft proprietary) |
| -133 | | RC4-HMAC-OLD (Microsoft proprietary) |
| -135 | | RC4-HMAC-OLD-EXP (Microsoft proprietary) |
| -1 | `0xFFFFFFFF` | **Not an algorithm.** No ticket was issued. |

### MS-KILE supported-encryption-type bit flags

A bitmask. These appear in:

- The `msDS-SupportedEncryptionTypes` attribute on users, computers and trusts
- The `DefaultDomainSupportedEncTypes` registry value
- `AccountSupportedEncryptionTypes`, `ServiceSupportedEncryptionTypes` and
  `DCSupportedEncryptionTypes` on version 2 events

| Bit | Meaning |
|---|---|
| `0x01` | DES-CBC-CRC |
| `0x02` | DES-CBC-MD5 |
| `0x04` | RC4-HMAC |
| `0x08` | AES128-CTS-HMAC-SHA1-96 |
| `0x10` | AES256-CTS-HMAC-SHA1-96 |
| `0x20` | AES256-CTS-HMAC-SHA1-96 **session key only** |
| `0x40` | AES128-CTS-HMAC-SHA256-128 |
| `0x80` | AES256-CTS-HMAC-SHA384-192 |
| `0x10000` | FAST supported (capability, not a cipher) |
| `0x20000` | Compound identity supported (capability) |
| `0x40000` | Claims supported (capability) |
| `0x80000` | Resource SID compression disabled (capability) |

## How it goes wrong

**Testing a ticket encryption type against the RC4 flag value.**

```powershell
# WRONG - 4 is DES-CBC-MD4 as a ticket etype, not RC4
$events | Where-Object { $_.TicketEncryptionType -eq 4 }
```

This matches nothing in a normal domain, so the audit reports a clean estate. It is the failure
mode that makes a hardening project look finished when it has not started.

```powershell
# Right
$events | Where-Object { $_.TicketEtype -eq 23 }

# Better - let the module say what it means
Get-KrbEvent | Where-Object { (ConvertFrom-KrbEtype -TicketEtype $_.TicketEtype).Family -eq 'RC4' }
```

**Decoding an attribute value as a ticket etype.**

`msDS-SupportedEncryptionTypes = 24` does not mean RC4-HMAC-EXP. It means `0x18` — AES128 plus
AES256. The two readings of `24` are opposite conclusions: one says the account is on an expired
RC4 variant, the other says it is fully hardened.

**The coincidence that hides the bug.** `18` decodes to AES256-CTS-HMAC-SHA1-96 as a ticket
etype, and to DES-CBC-MD5 + AES256-CTS-HMAC-SHA1-96 as a bitmask. Both readings mention AES256,
so a spot check passes — while the bitmask reading has silently included a broken cipher.

## Verifying

```powershell
# The same integer, both ways
ConvertFrom-KrbEtype -TicketEtype 23                  # RC4-HMAC
ConvertFrom-KrbEtype -SupportedEncryptionTypes 23     # DES-CBC-CRC + DES-CBC-MD5 + RC4 + AES128
```

The parameter sets are mutually exclusive by design, so decoding a value in both systems at once
is a binding error rather than a silent wrong answer.

## The 0x20 trap

Bit `0x20` is not a sixth cipher. MS-KILE defines it as AES256-CTS-HMAC-SHA1-96-**SK** —
permission to use AES256 for the *session key* only, while the ticket itself stays on whatever
else the account supports.

It is part of the Windows default `0x27`, so a great many accounts carry it. Treating it as AES
support overstates readiness; treating it as unknown understates it. The module reports both
readings separately:

```powershell
$e = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x20
$e.SupportsAes                 # False - no AES ticket
$e.SupportsAesSessionKeyOnly   # True
$e.TicketEtypes                # @()
$e.SessionKeyEtypes            # @(18)
```

## Why the risk engine compares families, not exact etypes

A related trap, and the reason `Get-KrbEtypeRisk` does not simply test observed etypes for
membership in the target's etype list.

The default target `0x18` authorises etypes 17 and 18 - the AES-SHA1 pair. It does not name 19
and 20, the RFC 8009 AES-SHA2 types that Windows Server 2025 issues. Under exact membership, a
client presenting AES256-CTS-HMAC-SHA384-192 is classified as using "an encryption type the
change removes", which surfaces as a Critical finding advising someone to confirm their client
supports AES. It already does - more of it than the target names.

What actually happens when such an account is narrowed to `0x18` is that the KDC negotiates down
from AES-SHA2 to AES-SHA1. The principal holds AES keys and keeps working.

So survival is decided by cipher family:

| Observed | Target `0x18` families | Verdict |
|---|---|---|
| 18 AES256-SHA1 | AES | survives |
| 20 AES256-SHA384 | AES | survives, negotiates down |
| 23 RC4-HMAC | AES | lost |
| 3 DES-CBC-MD5 | AES | lost |

An etype the catalog does not recognise is treated as surviving. The module cannot know an
unfamiliar algorithm is weak, and condemning it would be the same unknown-read-as-negative
mistake in a different place.

## Related

- [Unknown encryption types](Unknown-Encryption-Types.md)
- [Event schema versions](Event-Schema-Versions.md)
- [Missing AES keys](Missing-AES-Keys.md)
- [MS-KILE 2.2.7](https://learn.microsoft.com/openspecs/windows_protocols/ms-kile/6cfc7b50-11ed-4b4d-846d-6f08f0812919)
