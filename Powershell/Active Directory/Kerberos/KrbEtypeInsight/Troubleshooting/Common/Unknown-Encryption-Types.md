# Unknown or unexpected encryption types

`ConvertFrom-KrbEtype` returned `IsRecognized = $false`, or a report shows `Unknown (nn)`, or
`UnknownBits` is non-zero.

## The module never silently drops a value

An unrecognised encryption type is surfaced as an explicit unknown, not discarded. Returning
nothing would shorten the pipeline and remove the row from every count without saying so - and a
new Windows release adding an encryption type must show up in a report, not vanish from it.

Likewise, bits the module does not recognise in a supported-types bitmask are preserved as
`UnknownBits` rather than masked away. Microsoft has added bits to
`msDS-SupportedEncryptionTypes` twice.

```powershell
$e = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x118
$e.UnknownBits       # 256
$e.UnknownBitsHex    # 0x100
$e.CipherNames       # the bits it did understand
```

## Unknown never becomes a finding

Two places where this matters most:

**A client advertising only unrecognised names is reported as unknown, not legacy.**
`LegacyOnly` requires that every advertised name was recognised and none was AES. Without that
condition a client running an algorithm newer than this catalog resolves to no families at all,
which is indistinguishable from "no AES" - and raises a Critical saying it advertises no AES
support. Such clients land in `ClientsWithUnknownSupport`, which is the honest answer.

**An unrecognised ticket etype is treated as surviving the target.** The module cannot know that
an unfamiliar algorithm is weak.

```powershell
# Unknown, therefore not condemned
$r = ConvertFrom-KrbEtype -AdvertizedEtype @('AES512-CTS-HMAC-SHA3-256')
$r.SupportsAes   # False - no AES name was recognised
$r.LegacyOnly    # False - and this is the one the risk engine reads
```

## Common causes

**A newer Windows release.** RFC 8009 SHA-2 encryption types (19 and 20) arrived with Windows
Server 2025. If a report shows them from an older controller, something else issued the ticket.

**A non-Windows KDC.** Camellia (25, 26) is defined by RFC 6803 and not implemented by Windows.
Seeing it means an MIT or Heimdal KDC is involved, usually through a cross-realm trust.

**Microsoft-proprietary negative values.** `-128` (RC4-MD4), `-133` (RC4-HMAC-OLD) and `-135`
(RC4-HMAC-OLD-EXP) are advertised by old Windows clients in the AS-REQ etype list. These are
recognised, not unknown - a client advertising only these and RC4 predates AES support entirely
and is exactly what `KRB005` is for.

**A genuinely malformed field.** Rare, but the decoder returns null rather than guessing.

## `0xFFFFFFFF` is not an encryption type

The KDC writes it into `TicketEncryptionType` on every failure event, meaning no ticket was
issued. Read as unsigned it is 4294967295; the module reinterprets the bit pattern as `-1` and
decodes it as "None (no ticket issued)".

A report claiming an account used encryption type 4294967295 is a report that decoded a failure
as a cipher.

```powershell
ConvertFrom-KrbEtype -TicketEtype '0xffffffff'
# Value -1, Family None, Strength NotApplicable
```

## Finding them in a collection

```powershell
Get-KrbEvent -MaxEvents 20000 |
    Where-Object { $null -ne $_.TicketEtype } |
    ForEach-Object { ConvertFrom-KrbEtype -TicketEtype $_.TicketEtype } |
    Where-Object { -not $_.IsRecognized } |
    Group-Object Value
```

An unrecognised etype on a live production domain means the catalog is missing something the
operating system is actively using. That is worth reporting as an issue - include the raw value
and the controller's OS build.

## Related

- [The two numbering systems](Etype-Numbering-Systems.md)
- [Event schema versions](Event-Schema-Versions.md)
