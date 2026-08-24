# Trust encryption types

Finding `KRB014` (High), or `TrustsWithRc4Only` is non-empty on the domain context.

## The problem

A `trustedDomain` object carries its own `msDS-SupportedEncryptionTypes`. If it omits AES, every
cross-realm ticket over that trust is pinned to RC4 **regardless of what the accounts on either
side support**.

This is the most common reason a domain that has "finished" removing RC4 keeps issuing it. Every
per-account attribute is correct, every service holds AES keys, and RC4 tickets keep appearing
in the log - because the trust, which nobody thought to look at, does not permit anything else.

## Finding it

```powershell
$context = Get-KrbDomainEtypeContext

$context.Trusts | Select-Object Name, Direction, TrustType, IsIntraForest,
    @{ n = 'Etypes'; e = { $_.EncryptionTypes.EffectiveHex } },
    @{ n = 'AES';    e = { $_.EncryptionTypes.SupportsAes } },
    IsCrossRealmRc4Risk
```

Or directly:

```powershell
Get-ADTrust -Filter * -Properties msDS-SupportedEncryptionTypes |
    Select-Object Name, Direction, msDS-SupportedEncryptionTypes
```

An unset value on a trust means the same thing it means anywhere else: the domain default
applies, which by default includes no AES ticket bit.

## Fixing it

```powershell
Set-ADObject -Identity 'CN=contoso.net,CN=System,DC=ad,DC=fabrikam,DC=net' `
    -Replace @{ 'msDS-SupportedEncryptionTypes' = 0x1C }
```

Two things make this the longest-lead item in most hardening projects:

**It has to be set on both sides.** The trusted domain object exists in each domain, and both
must permit AES or the intersection is still RC4.

**The other side may not be yours.** An external or forest trust to a partner organisation
requires their cooperation, their change process, and their maintenance window. Start this
conversation at the beginning of the project, not when the rest of the work is done.

Intra-forest trusts inherit the forest's behaviour and are rarely the problem; the module marks
them `IsIntraForest` and does not flag them as cross-realm risks.

## Verifying afterwards

Cross-realm tickets show up as service names in another realm:

```powershell
Get-KrbEvent -EventId 4769 -MaxEvents 20000 |
    Where-Object { $_.ServiceName -like 'krbtgt/*' } |
    Group-Object ServiceName, TicketEtype |
    Select-Object Count, Name
```

A `krbtgt/OTHERREALM` entry with `TicketEtype 23` is a cross-realm referral still on RC4.

## Related

- [Controller policy drift](Controller-Policy-Drift.md)
- [SPN resolution](SPN-Resolution.md)

## How a referral actually appears in the log

Measured on a real bidirectional forest trust, in both directions. This contradicts the
obvious assumption and it is worth knowing before writing any query of your own.

A cross-realm referral is a 4769 whose `ServiceName` is the **bare target realm**:

| Logged on | `ServiceName` | Status | Ticket etype |
|---|---|---|---|
| the trusting forest | `LAB.CONTOSO.TEST` | `0xC000019B` | none issued |
| the trusted forest | `AD.TECHBYJEFF.NET` | `0x0` | **`0x17` RC4** |

There is **no `krbtgt/` prefix**. The ticket itself is `krbtgt/AD.TECHBYJEFF.NET` and `klist`
shows it plainly, but the event field carries only the realm. Meanwhile the literal string
`krbtgt` is what *local TGT renewals* record — 116 of them in a single capture — so a filter
written for `krbtgt/` matches the wrong thing entirely.

`ServiceSid` on a referral carries the domain SID with a **RID of 0**, because a realm is not
a principal. That is suggestive but not sufficient on its own: a failed SPN lookup also
resolves to RID 0.

The module identifies referrals by matching `ServiceName` against the real trust names from
`Get-KrbDomainEtypeContext`, falling back to a name-shape test — no separator, no trailing
dollar, contains a dot, upper case — when running offline with no trust list available.

Finding them yourself:

```powershell
$context = Get-KrbDomainEtypeContext
$realms = @($context.Trusts.Name)

Get-KrbEvent -EventId 4769 -MaxEvents 20000 |
    Where-Object { $_.ServiceName -in $realms } |
    Group-Object ServiceName, TicketEtype |
    Select-Object Count, Name
```

An entry with `TicketEtype 23` is a cross-realm referral still on RC4 — the condition
`KRB014` warns about, observed rather than inferred. The module attaches these counts and
etypes to the `KRB014` evidence as `ObservedReferrals` and `ObservedReferralEtypes`.

## The status code a broken trust produces

`0xC000019B`, `STATUS_TRUSTED_DOMAIN_FAILURE`. Note that this is an **NTSTATUS**, not an
RFC 4120 Kerberos result code — the `Status` field carries both, and they do not collide
because Kerberos codes are small positive integers while NTSTATUS failures all begin
`0xC0000000`. The module classifies it as encryption-type related, because a trust whose
supported types do not intersect with the requesting realm fails exactly here.
