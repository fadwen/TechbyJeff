# KDC result codes

Interpreting the `Status` field on events 4768, 4769 and 4771.

## The codes that mean your change broke something

| Code | Name | What it means here |
|---|---|---|
| `0x0E` | `KDC_ERR_ETYPE_NOTSUPP` | The KDC and the client have no encryption type in common. **The direct signature of etype hardening breakage.** |
| `0x09` | `KDC_ERR_NULL_KEY` | The account has no key of a usable type - typically AES-only with a password that predates the change. |
| `0x0F` | `KDC_ERR_SUMTYPE_NOSUPP` | No checksum type in common. |
| `0x10` | `KDC_ERR_PADATA_TYPE_NOSUPP` | The pre-authentication type offered is unsupported - seen when PKINIT or FAST is unavailable. |
| `0x1F` | `KRB_AP_ERR_BAD_INTEGRITY` | Integrity check failed. Can follow a key mismatch after an etype change. |
| `0x29` | `KRB_AP_ERR_MODIFIED` | Message stream modified. Frequently a key mismatch, including one an etype change caused. |

The module marks exactly these as `StatusIsEtypeRelated`, and raises `KRB011` when it sees them.

## The codes that are background noise

Every domain produces a steady stream of these. Counting them as hardening breakage buries the
signal entirely.

| Code | Name | Usual cause |
|---|---|---|
| `0x18` | `KDC_ERR_PREAUTH_FAILED` | Wrong password |
| `0x19` | `KDC_ERR_PREAUTH_REQUIRED` | Normal first-leg response, **not a failure** |
| `0x17` | `KDC_ERR_KEY_EXPIRED` | Password expired |
| `0x12` | `KDC_ERR_CLIENT_REVOKED` | Account disabled, locked out or expired |
| `0x25` | `KRB_AP_ERR_SKEW` | Clock skew |
| `0x06` | `KDC_ERR_C_PRINCIPAL_UNKNOWN` | Client principal not found |
| `0x07` | `KDC_ERR_S_PRINCIPAL_UNKNOWN` | Missing or duplicate SPN |
| `0x0C` | `KDC_ERR_POLICY` | Logon hours, workstation restriction, authentication policy |

`0x19` deserves special mention: it is a normal part of the pre-authentication exchange and
appears constantly on a healthy domain. Treating it as a failure inflates any failure count by
an order of magnitude.

## Post-change verification

The check to run during the maintenance window:

```powershell
$before = Get-KrbEvent -IncludeFailureOnly -StartTime (Get-Date).AddDays(-7) `
                       -EndTime (Get-Date).AddHours(-1) |
    Group-Object StatusName | Select-Object Name, Count

$after = Get-KrbEvent -IncludeFailureOnly -StartTime (Get-Date).AddHours(-1) |
    Group-Object StatusName | Select-Object Name, Count

$after | Where-Object Name -eq 'KDC_ERR_ETYPE_NOTSUPP'
```

`KDC_ERR_ETYPE_NOTSUPP` appearing where it was not before is the change breaking something.
That is the roll-back signal, and it is worth deciding the threshold before the window opens
rather than during it.

## Finding who is affected

```powershell
Get-KrbEvent -IncludeFailureOnly -StartTime (Get-Date).AddHours(-4) |
    Where-Object StatusIsEtypeRelated |
    Group-Object ClientAccount |
    Sort-Object Count -Descending |
    Select-Object Count, Name, @{ n = 'Addresses'; e = { ($_.Group.IpAddress | Sort-Object -Unique) -join ', ' } }
```

## Ticket options

`TicketOptions` is decoded onto `TicketOptionNames`. It matters mainly for explaining an
unexpectedly large client count: a delegation target generates a service ticket request per hop,
and seeing `Forwardable` and `Forwarded` on those requests explains the volume without a
separate investigation.

## Related

- [Missing AES keys](Missing-AES-Keys.md)
- [RFC 4120 section 7.5.9](https://www.rfc-editor.org/rfc/rfc4120#section-7.5.9)
