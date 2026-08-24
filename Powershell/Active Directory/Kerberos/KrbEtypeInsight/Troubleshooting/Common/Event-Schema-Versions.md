# Event schema versions

Findings carry a note saying available-key or client-advertisement evidence was unavailable, or
`EventSchemaVersion2` is `$false`.

Note which object each of those properties lives on, because they are not the same one and the
mistake is silent:

| Object | Property | Meaning |
|---|---|---|
| Event (`Get-KrbEvent`) | `EventVersion` | the raw schema version, `0`, `1` or `2` |
| Event (`Get-KrbEvent`) | `HasEtypeDetail` | `$true` when the event is a version 2 4768 or 4769, so the rich fields are present |
| Risk (`Get-KrbEtypeRisk`) | `EventSchemaVersion2` | `$true` when *any* event behind this principal carried version 2 detail |

Grouping events by `EventSchemaVersion2` returns a single group and looks like a confident
answer. It is not — events have no such property, and `Group-Object` does not error on one that
is missing, it silently groups everything together. Earlier revisions of this page and of the
README both made exactly that mistake, and it survived a full documentation audit because the
property name is genuinely real; only the object it was used on was wrong. A contract test now
checks every documented `Get-KrbEvent` grouping against the event object's actual shape.

## What changed

The November 2022 cumulative update (KB5021131, for CVE-2022-37966) introduced **version 2** of
events 4768 and 4769. Version 2 added the fields that make this module's best findings possible:

| Field | What it answers |
|---|---|
| `ClientAdvertizedEncryptionTypes` | What the client actually offered on the wire |
| `AccountAvailableKeys` / `ServiceAvailableKeys` | Which key material exists on the principal |
| `AccountSupportedEncryptionTypes` / `ServiceSupportedEncryptionTypes` | The KDC's computed effective types |
| `DCSupportedEncryptionTypes` / `DCAvailableKeys` | The controller's own position |
| `SessionKeyEncryptionType` | Session key etype, separately from the ticket |

Without them the module falls back to inferring from `TicketEncryptionType` alone, which tells
you what the KDC *chose* but not what either party was *capable of*.

## What degrades

| Finding | Version 2 | Version 0 or 1 |
|---|---|---|
| `KRB002` no AES key material | Direct, from `AvailableKeys` | Not possible - becomes `KRB006` inference |
| `KRB005` named legacy clients | Direct, from advertisement | Not possible |
| `KRB001` all tickets removed | Available | Available |
| `KRB015` insufficient evidence | Rare | Common |

The module never treats a missing field as a negative. `ClientAdvertizedSupportsAes` is `$null`
on a legacy event, not `$false` - because `$false` means "this client offered no AES", which is
a Critical finding, and producing it from an absent field would condemn every client behind an
unpatched controller.

## Checking what your controllers emit

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4768, 4769 } -MaxEvents 500 |
    Group-Object Version
```

Or per controller, through the module:

```powershell
Get-KrbEvent -MaxEvents 1000 | Group-Object Source, EventVersion |
    Select-Object Count, Name
```

A mixed result means some controllers are patched and some are not. The module records that on
each affected finding as a partial-coverage note, because a principal assessed mostly through
legacy events has weaker evidence than its finding count suggests.

## The fix

Install the November 2022 or later cumulative update on every domain controller. There is no
way to obtain the version 2 fields otherwise, and no way to reconstruct them after the fact -
an event that was never written cannot be recovered.

If patching is not imminent, run the assessment anyway and read the `ConfidenceNotes` on every
object. A partial assessment reported honestly is more useful than none; a partial assessment
presented as complete is worse than none.

## A note on the supported-types fields

`ServiceSupportedEncryptionTypes` in a version 2 event is the KDC's **computed effective value**
for the principal, and it is not always the raw `msDS-SupportedEncryptionTypes` attribute. An
account attributed `0x1C` has been observed reported as `0x1F`.

The module surfaces both - the event value on `KrbEtypeInsight.Event`, the directory value on
`KrbEtypeInsight.Principal` - and deliberately does not reconcile them into one number. When
they differ, the event value is what the KDC acted on.

## Related

- [The two numbering systems](Etype-Numbering-Systems.md)
- [Missing AES keys](Missing-AES-Keys.md)
- [KB5021131](https://support.microsoft.com/help/5021131)

## A newer controller can emit an OLDER schema

Measured in a two-controller domain, both patched, same forest, same day:

| Controller | Operating system | Schema emitted |
|---|---|---|
| `WS22-EV-01` | Windows Server **2022** | **version 2** — all events |
| `WS25-EV-02` | Windows Server **2025** (build 26100) | **version 1** — all 75 events |

The newer controller emitted the older schema. This inverts the natural assumption, and it
matters because the version 2 fields are where the module's strongest findings come from.

A version 1 event on Server 2025 does carry `RequestTicketHash` and `ResponseTicketHash`, so
it is not the ancient shape — but it has **none** of the encryption-type detail:

```text
TargetUserName        = Administrator@AD.TECHBYJEFF.NET
ServiceName           = krbtgt
TicketEncryptionType  = 0x12
RequestTicketHash     = ajzU/qHDqjEpF77T+Z6fkkzdCfsFla6zzTjkHIsWMRg=
ResponseTicketHash    = 6FqImAWN6zqi6DvhOPJsCgmyv4MJjE5pUXkV/aop63c=
```

No `AccountSupportedEncryptionTypes`, no `ServiceAvailableKeys`, no
`ClientAdvertizedEncryptionTypes`, no `SessionKeyEncryptionType`. So on that controller
`KRB002` and `KRB005` — the two findings that make this module worth running — cannot be
produced at all, and the engine correctly falls back to `KRB006` and `KRB015`.

**Do not infer schema version from operating system version.** Measure it:

```powershell
Get-KrbEvent -MaxEvents 2000 |
    Group-Object Source, EventVersion |
    Select-Object Count, Name
```

A domain of mixed schema is normal, and the module records it per principal — a finding built
partly from version 1 events carries a confidence note saying so. Read those notes before
treating a quiet controller as a clean one.

The practical consequence for an assessment: **collect from every controller**, and check the
schema spread before believing a low finding count. A domain whose busiest controller emits
version 1 will look far healthier than it is.
