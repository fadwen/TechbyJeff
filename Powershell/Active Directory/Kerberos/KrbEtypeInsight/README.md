# KrbEtypeInsight

Predicts which accounts, services and clients a Kerberos encryption type hardening change will
break — before the change is made.

## Overview

There is no shortage of scripts that flip `msDS-SupportedEncryptionTypes` from RC4 to AES.
Setting the attribute is a one-line change. The hard part is the question nobody's script
answers: **will this break anything, and if so, whose?**

Answering it means putting three independent sources next to each other:

| Source | Question it answers |
|---|---|
| Events 4768, 4769, 4771 | What the KDC has actually been issuing |
| `msDS-SupportedEncryptionTypes`, `userAccountControl` | What the directory says each principal supports |
| Per-controller `DefaultDomainSupportedEncTypes`, trusts, krbtgt | What the domain permits by default |

The output is not "this account is configured for RC4". It is:

> `svc-payroll` — Critical, score 53. 412 service ticket requests in 30 days, all RC4.
> The account holds no AES key material, so the KDC would return `KDC_ERR_NULL_KEY`.
> 12 distinct clients depend on it, of which **3 advertise no AES encryption type at all**:
> `APPLIANCE-SCAN01$`, `LEGACY-ETL02$`, `KIOSK-114$`.

That last list is the deliverable. It names the machines an application owner has to fix, and
no amount of configuration auditing produces it.

## Why this is harder than it looks

**There are two different Kerberos numbering systems, and they are easy to confuse.**

RC4 is `23` as an RFC 3961 ticket encryption type and bit `0x4` as an MS-KILE supported-types
flag. AES256 is `18` in one and `0x10` in the other. A script that tests a ticket's
`TicketEncryptionType` against `4` is testing for DES-CBC-MD4 and will report every RC4 ticket
in the estate as clean. This module models the two systems as separate types and never
converts between them by arithmetic — the mapping is an explicit table, because it is not a
computable relationship.

**Configuration does not tell you whether the key exists.**

Kerberos keys are derived when the password is set. An account whose password predates the
domain's AES support has no AES key no matter what its attributes claim. Setting it to
AES-only does not harden it — it breaks it, with `KDC_ERR_NULL_KEY`. Version 2 audit events
(post-KB5021131) report the account's *available keys* directly, which is the only reliable
way to see this. It is finding `KRB002`, and it is the single most common cause of a hardening
rollback.

**An unset attribute is not "supports nothing".**

Unset or zero falls through to the domain's `DefaultDomainSupportedEncTypes`, whose unwritten
Windows default of `0x27` includes the AES256 *session-key* bit. That bit (`0x20`) authorises
AES for the session key only, not for the ticket — so an account holding it issues AES session
keys inside RC4 tickets. Counting it as AES support declares the account already hardened when
it is not.

**`DefaultDomainSupportedEncTypes` is a per-controller registry value, not a replicated
attribute.** Controllers can and do disagree, and a domain where they disagree authenticates
differently depending on which controller a client happens to reach — producing intermittent
failures that survive every attempt to reproduce them. The module reads it from every
controller and reports the disagreement.

## Prerequisites

- PowerShell 7.6 (LTS)
- The `Kerberos Authentication Service` and `Kerberos Service Ticket Operations` audit
  subcategories enabled on the domain controllers
- The `ActiveDirectory` module (RSAT) for the directory-reading functions only. The decode and
  correlation core runs offline with no domain present.

Rights differ per function, and an earlier revision of this file got that wrong by stating
Event Log Readers as sufficient for the whole module. It is not:

| Function | Needs |
|---|---|
| `ConvertFrom-KrbEtype` | nothing — pure decode |
| `Get-KrbEvent` | **Event Log Readers** on each controller |
| `Get-KrbPrincipalEtype` | read access to the directory — any authenticated user by default |
| `Get-KrbDomainEtypeContext` | **local administrator on each controller**, or `-SkipRegistry` |
| `Get-KrbEtypeRisk`, `Export-KrbEtypeReport` | whatever the above needed |

`Get-KrbDomainEtypeContext` reads `DefaultDomainSupportedEncTypes` from each controller's
registry over PowerShell remoting. Event Log Readers grants neither WinRM access nor registry
read, so under that group alone every controller comes back `RegistryReachable = $false` and
the baseline silently falls back to the assumed Windows default — which every per-account
finding then inherits.

Run the event collection under a low-privilege account and the domain baseline under an
administrative one, or accept an assumed baseline and check `DomainDefaultSource` says so:

```powershell
$context = Get-KrbDomainEtypeContext -Credential (Get-Credential)
$context.DomainDefaultSource                                   # 'Registry' = measured
$context.DomainControllers | Where-Object { -not $_.RegistryReachable }
```

Domain Admin is not required for anything here, and no function writes to the directory.

Two prerequisites are easy to get wrong, and both were found the hard way in a live two-DC lab:

**Remote Event Log Management must be enabled on every controller you collect from.**
`Get-WinEvent -ComputerName` uses the legacy Event Log RPC protocol, not WinRM, and its
firewall rules are **off by default on a fresh Windows install**. A controller that pings,
resolves, replicates cleanly and answers WinRM perfectly will still fail every event-log call
with *"The RPC server is unavailable"*.

```powershell
Invoke-Command -ComputerName DC02 { Enable-NetFirewallRule -DisplayGroup 'Remote Event Log Management' }
```

**Do not infer the audit schema version from the operating system version.** The rich version 2
fields — available keys and client advertisement, which produce `KRB002` and `KRB005` — arrived
with the November 2022 cumulative update, but a *newer* build does not guarantee them. Measured
in one domain on one day: a Server **2022** controller emitted version **2**, and a Server
**2025** controller emitted version **1** for all 75 of its events. Check rather than assume:

```powershell
Get-KrbEvent -MaxEvents 2000 | Group-Object Source, EventVersion | Select-Object Count, Name
```

Where the fields are absent the module says so on every affected finding rather than presenting
an inference as an observation — see [Event schema
versions](Troubleshooting/Common/Event-Schema-Versions.md).

## Installation

```powershell
Import-Module .\KrbEtypeInsight.psd1
```

## Quick start

```powershell
# The whole assessment, in one line.
Get-KrbEvent -MaxEvents 50000 | Get-KrbEtypeRisk | Sort-Object RiskScore -Descending
```

```text
Level      Score Principal                    Reqs  Clients   NoAES Codes
-----      ----- ---------                    ----  -------   ----- -----
Critical     100 svc-payroll                    412       12       3 KRB002 KRB001 KRB005
Critical      80 MSSQLSvc/legacydb01:1433        89        4       0 KRB002 KRB001
Critical      53 APPLIANCE-SCAN01$               31        0       0 KRB005 KRB008
Medium        10 svc-reporting                 1204       47       0 KRB013
```

The column layout above is the real default table view. The rows are illustrative: the
principal names come from the test fixtures and the request and client counts are invented
to show the shape of a finding at realistic volume. No output in this README was captured
from a production domain.

The named clients behind that `NoAES` column:

```powershell
$risks = Get-KrbEvent | Get-KrbEtypeRisk
$risks | Where-Object RiskLevel -eq 'Critical' |
    Select-Object PrincipalName, RequestCount, ClientCount,
                  @{ n = 'BreaksClients'; e = { $_.ClientsWithoutAesSupport -join ', ' } }
```

A report to attach to the change record:

```powershell
$context = Get-KrbDomainEtypeContext
Get-KrbEvent | Get-KrbEtypeRisk -DomainContext $context |
    Export-KrbEtypeReport -Path .\krb-readiness.html -DomainContext $context `
        -Title 'RC4 removal readiness - Phase 1'
```

## Commands

| Command | Purpose |
|---|---|
| `ConvertFrom-KrbEtype` | Decodes all three forms: RFC 3961 ticket etype numbers, MS-KILE bitmasks, and the client advertised-etype name list |
| `Get-KrbEvent` | Collects and decodes 4768/4769/4771 from live controllers or archived `.evtx` |
| `Get-KrbPrincipalEtype` | Reads per-account configuration, including the `userAccountControl` overrides that supersede the encryption type attribute |
| `Get-KrbDomainEtypeContext` | Establishes the baseline: functional level, per-controller policy, krbtgt, trusts |
| `Get-KrbEtypeRisk` | Correlates the above into per-principal risk objects |
| `Export-KrbEtypeReport` | Self-contained HTML, per-finding CSV, or full-fidelity JSON |

## Typical workflows

### Scope an RC4 removal project

```powershell
$context = Get-KrbDomainEtypeContext
$principals = Get-KrbPrincipalEtype -All -DomainDefaultEncryptionTypes $context.DomainDefaultEncryptionTypes

Get-KrbEvent -StartTime (Get-Date).AddDays(-45) |
    Get-KrbEtypeRisk -Principal $principals -DomainContext $context |
    Where-Object WillBreakOnHardening |
    Export-KrbEtypeReport -Path .\phase1-blockers.html -DomainContext $context
```

Use a window of at least 30 days. Shorter, and the monthly batch job — reliably the thing
hardening breaks — falls outside the collection entirely.

### Validate the staged rollout

Model the intermediate step of *adding* AES while leaving RC4 in place. It should produce no
Critical findings; if it does, that step is not as safe as it is usually assumed to be.

```powershell
Get-KrbEvent | Get-KrbEtypeRisk -TargetEncryptionTypes 0x1C |
    Where-Object RiskLevel -in 'Critical', 'High'
```

### Verify during the maintenance window

```powershell
Get-KrbEvent -IncludeFailureOnly -StartTime (Get-Date).AddHours(-4) |
    Group-Object StatusName | Sort-Object Count -Descending
```

`KDC_ERR_ETYPE_NOTSUPP` appearing here is the change breaking something. This is the
roll-back-or-proceed signal.

### Assess a domain from a workstation

Archive the security logs on each controller — `wevtutil` exports in seconds because nothing
leaves the machine — then process the files anywhere:

```powershell
# On each controller
wevtutil epl Security C:\Temp\$env:COMPUTERNAME-krb.evtx `
    "/q:*[System[(EventID=4768 or EventID=4769 or EventID=4771)]]"

# Anywhere, with no domain connectivity
Get-ChildItem \\fileserver\krbaudit\*.evtx | Get-KrbEvent -MaxEvents 0 | Get-KrbEtypeRisk -Offline
```

## Finding codes

| Code | Severity | Meaning |
|---|---|---|
| `KRB001` | Critical | Every observed ticket used an encryption type the change removes |
| `KRB002` | Critical | Principal holds no AES key material — hardening yields `KDC_ERR_NULL_KEY` |
| `KRB003` | High | `msDS-SupportedEncryptionTypes` explicitly set to exclude AES |
| `KRB004` | Critical | `USE_DES_KEY_ONLY` set, overriding the encryption type attribute |
| `KRB005` | Critical | Named clients advertise no AES support |
| `KRB006` | High | No AES ticket observed and key material cannot be confirmed (legacy event schema) |
| `KRB007` | Critical | Single DES observed or configured |
| `KRB008` | High | Pre-authentication has only ever used a removed encryption type |
| `KRB009` | Info | No impact predicted, on adequate evidence |
| `KRB010` | Medium | Mix of surviving and removed encryption types |
| `KRB011` | Critical | Encryption-type failures are already occurring |
| `KRB012` | Medium | Explicitly non-AES and no traffic in the window — unknown, not safe |
| `KRB013` | Medium | Delegation enabled, widening the blast radius |
| `KRB014` | High | Trust does not permit AES for cross-realm authentication |
| `KRB015` | Low | Insufficient evidence to assess |

`KRB009` and `KRB015` are the pair worth understanding. Both mean "nothing was found wrong".
`KRB009` says so on the strength of version 2 events and directory configuration. `KRB015` says
the fields that would have revealed a problem were never written — nothing was found wrong, and
nothing would have been found wrong had it been broken. Reporting the second as the first is how
an assessment gives false assurance about exactly the principals it understood least.

## Risk scoring

Two values, answering different questions:

- **Level** is the highest severity present — does this principal block the change?
- **Score** is the capped weighted sum — how should the backlog be ordered when a hundred
  principals all come back Critical?

Blast radius (distinct dependent clients) scales the Score logarithmically but never the Level.
A widely used healthy service must not outrank a broken obscure one, and a principal with no
findings stays at zero however many clients depend on it.

## What counts as "broken"

Survival is judged by cipher **family**, not by exact membership in the target's etype list.

The default target `0x18` names etypes 17 and 18 — AES-SHA1. It does not name 19 and 20, the
RFC 8009 AES-SHA2 types Windows Server 2025 issues. Testing exact membership would classify the
strongest cipher Windows produces as "removed by the change" and raise Criticals against the most
modern machines in the estate. What actually happens is that the KDC negotiates down from AES-SHA2
to AES-SHA1, and the principal keeps working.

Equally, anything the catalog does not recognise is treated as surviving, and a client advertising
only unrecognised algorithms is reported as *unknown* rather than as legacy. Unknown is not
incapable. The module is built so that missing information produces a lower-confidence finding,
never a higher-severity one — see [KRB015](Troubleshooting/Common/Finding-Codes.md) and
[unknown encryption types](Troubleshooting/Common/Unknown-Encryption-Types.md).

## Testing

427 tests, 98.4% command coverage. The decode and correlation core is exercised entirely offline
against captured fixtures in [`Tests/Fixtures`](Tests/Fixtures/), because the interesting cases
cannot be obtained from a working domain — a healthy estate does not issue RC4 tickets, does not
hold DES accounts that authenticate, and cannot produce the version 0 and 1 audit schemas at all.

```powershell
Invoke-Pester -Path .\Tests

# Unit only - no domain, no event log, no ActiveDirectory module required
Invoke-Pester -Path .\Tests\Unit

# Performance only - also fully offline, roughly 28 seconds
Invoke-Pester -Path .\Tests\Performance
```

### How "no ActiveDirectory module required" is held up

That claim is enforced, not aspirational. The unit suites mock every directory call they
make — 129 of them — so they never reach a domain. What they cannot do without help is
*attach* those mocks: Pester resolves `Mock -ModuleName KrbEtypeInsight Get-ADDomain`
against a real command, and where RSAT is absent that throws `CommandNotFoundException`
inside `BeforeAll`, which fails the entire `Describe` block. Before the stubs existed, 91
of the 402 unit tests failed on a workstation, and not one of them was testing Active
Directory.

[`Tests/Stubs`](Tests/Stubs/) supplies the six cmdlet names the suites mock, with the real
parameter surface and empty bodies, and each affected suite appends it to `PSModulePath`
in `BeforeAll`. **Appending rather than prepending is the whole design:** a domain
controller with real RSAT keeps binding against the real cmdlets, so the suite still
exercises the true surface there, while a workstation falls back to the stub.

Both directions are verified — 402 pass on a controller where `Get-ADTrust` resolves to
`C:\Windows\system32\...\ActiveDirectory.psd1`, and 402 pass on a workstation with no RSAT
installed at all.

The stub weakens nothing. Every command a test relies on is still mocked; the stub only
makes the name exist so the mock can be attached. It is generated from the real cmdlets by
[`Update-KrbTestStub.ps1`](Tests/Stubs/Update-KrbTestStub.ps1) — never edited by hand — and
the cmdlet list is explicit rather than a wildcard over RSAT, so it stays a statement about
what this module actually depends on.

One test is worth calling out: every `-Code 'KRBnnn'` literal in the risk engine must appear
somewhere in the suite. Four finding codes had no test at all in the first version, and two
defects lived in exactly those paths.

### Order independence

The suite passes clean under Pester 6's two experimental isolation options, which is worth
knowing before trusting a green run:

```powershell
# Randomises file, block and test order
$c = New-PesterConfiguration
$c.Run.Path = '.\Tests'; $c.Run.Shuffle = $true; $c.Run.ShuffleSeed = 20260818
Invoke-Pester -Configuration $c

# One test file per runspace
$c = New-PesterConfiguration
$c.Run.Path = '.\Tests'; $c.Run.Parallel = $true; $c.Run.ParallelThrottleLimit = 4
Invoke-Pester -Configuration $c
```

427 passing under three shuffle seeds and under four parallel runspaces. Neither is enabled by
default — they are experimental, and `Run.Parallel` forces code coverage onto slower breakpoint
mode — but both being clean means no test depends on another having run first, and no two files
contend for shared state.

Worth confirming the shuffle is actually shuffling before believing it, since a silent no-op
looks identical to a clean pass. Comparing executed order across seeds shows three genuinely
different orderings.

### What is still not covered

The remaining 33 uncovered commands are, in the main, error paths for dependencies that are
present on any machine able to run the module at all:

- The `Import-Module ActiveDirectory` failure branch in two functions — needs RSAT to be absent.
- The malformed-record warning on the `-Record` parameter set. `EventLogRecord` has no public
  constructor, so a corrupt one cannot be synthesised.
- The **local** registry read in `Get-KrbDomainEtypeContext`. Unit tests drive mock controllers,
  which take the remote branch; the local branch runs only when the module executes on a DC.
- Parameter default expressions, which only evaluate when the parameter is omitted.

### KRB002 cannot be reproduced in a modern lab, and that is not a gap in the tests

Fourteen of the fifteen finding codes have now been observed firing against a real domain.
`KRB002` is the exception, and the reason is structural rather than a missing test.

The finding requires an event that reports `AvailableKeys` **containing no AES entry**. Three
facts close every route to that in a lab a modern Windows build can host:

- The KDC only writes `AvailableKeys` on a **successful** issuance. A request rejected with
  `KDC_ERR_ETYPE_NOTSUPP` omits the field entirely - verified by giving a `UseDESKeyOnly`
  account an SPN and requesting a ticket for it. The failure logged `ServiceAvailableKeys` as
  absent and `ServiceSupportedEncryptionTypes` as empty, because the KDC rejected the request
  before evaluating the service's key material.
- A successful issuance means the KDC found a usable key, and on any domain at functional
  level 2008 or above AES keys are derived at every password set. Windows Server 2016 and
  later cannot join a domain below that level, so the pre-AES vintage that produces this
  state cannot be created.
- The one real observation of `AvailableKeys = None` in the lab came from a **cross-realm
  referral**, not a principal. The module correctly excludes it from per-principal assessment,
  so it produces `KRB014` about the trust rather than a spurious `KRB002` about a realm.

The condition is real - it is why accounts whose passwords predate AES fail with
`KDC_ERR_NULL_KEY` the moment RC4 is withdrawn, and it is the most common cause of a hardening
rollback in genuinely old estates. It simply cannot arise in a directory young enough to be
built today. Producing it artificially would mean writing key material directly into the
database with a tool such as DSInternals, which is a statement about that tool rather than
about this module.

`KRB002` is therefore covered by fixtures and unit tests only, deliberately.

Previously uncovered and now closed by the validation lab: a genuine multi-controller estate, a real
cross-forest trust, and a Server 2025 controller. See the SHA-2 section above and
the lab results directory. The disagreement, trust and SHA-2 behaviours are now pinned by
regression tests written from measured KDC output rather than from documentation.

### Fixtures

The fixtures are synthetic and generated by
[`New-KrbFixture.ps1`](Tests/Fixtures/New-KrbFixture.ps1), which is committed alongside them so
that the reason each one differs from a real event stays visible in one place. **No real event
data is stored in this repository** — a genuine `.evtx` export carries real account names, SIDs
and client addresses, and the integration suite generates its own at run time instead.

One group of tests is worth singling out. Version 2 events carry Windows' own rendering of each
bitmask alongside the raw value (`0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)`). Comparing the
module's decoding against that string makes the operating system an independent oracle — the
only assertions in the suite whose expected values were not written by the same person who wrote
the code.

## Performance

A full collection costs about **2.8 ms per event warm**, and **5.9 ms on the first run of a
session**. Of the warm figure, roughly 57% is `Get-WinEvent` itself, and decode alone — the
part that runs offline — settles at about 0.82 ms per event, or 1,200 events per second. All
filtering that can be pushed to the event log service is: event ID and time window go into the
`FilterHashtable`, evaluated on the remote controller before a record crosses the network.

Earlier revisions of this file claimed 3.6 ms per event and a 35% `Get-WinEvent` share. Both
were wrong, and building the performance suite is what exposed them: the old figures came from
a single half-warmed run. `Get-WinEvent` is I/O bound and costs the same on the first pass as
the eighth, while the decode path is JIT-sensitive and gets about four times faster as it
warms — so the I/O share *rises* from 28% cold to 57% warm. The old pairing described a moment
rather than a steady state. [Event volume](Troubleshooting/Performance/Event-Volume.md) has the
full breakdown and the run-by-run numbers.

Both figures are enforced by [`Tests/Performance`](Tests/Performance/), which runs offline
against the fixtures and needs no domain, so it behaves the same on a controller as on a CI
runner. It asserts decode throughput, that the two catalogs are built once and reused, that
correlation scales sub-linearly with event volume, and that repeated decoding does not retain
allocations.

Two notes on reading a failure there, both of which cost time to learn:

- **Warm up before believing any measurement.** Tiered JIT compilation makes early iterations
  useless. Twelve consecutive runs of 500 decodes with only a token warmup gave 1088, 897, 650,
  564, 494, 453, 458, 400 ms — a 2.7x spread still trending downward at the eighth run, with a
  coefficient of variation of 36.6%. After a 3000-decode warmup the same measurement settles at
  409 ms and 6.1%. The suite therefore warms up hard, and that warmup is load-bearing.
- **Prefer ratios and identities to wall-clock.** The scaling and cache tests compare two
  measurements taken back to back on the same machine, so they detect a complexity change
  regardless of how fast that machine is. The absolute thresholds sit at five to eight times
  the measured cost, so a failure there usually means the machine was busy, not that the module
  regressed.

The suite was verified by mutation rather than by passing: disabling the catalog cache and
injecting a quadratic scan into the correlation loop each produced a failure in the expected
test — the quadratic mutation made 8x the events cost 37.2x the time. An earlier version of the
cache test, which compared the first call against later ones, passed *with the cache disabled*
and was replaced; the reasoning is recorded in the test file.

For a large estate, archive to `.evtx` per controller and process the files — see
[Event volume](Troubleshooting/Performance/Event-Volume.md).

## Safety

Read-only throughout. No function in this module writes to Active Directory, and the integration
suite asserts that every principal's `msDS-SupportedEncryptionTypes` is byte-identical before and
after a full assessment run.

Reports name accounts, service principal names and client addresses. Handle them as internal
documents.

## Troubleshooting

| Topic | Guide |
|---|---|
| No events collected | [Common/No-Events-Collected.md](Troubleshooting/Common/No-Events-Collected.md) |
| The two numbering systems | [Common/Etype-Numbering-Systems.md](Troubleshooting/Common/Etype-Numbering-Systems.md) |
| Event schema versions | [Common/Event-Schema-Versions.md](Troubleshooting/Common/Event-Schema-Versions.md) |
| Accounts with no AES key | [Common/Missing-AES-Keys.md](Troubleshooting/Common/Missing-AES-Keys.md) |
| KDC result codes | [Common/KDC-Status-Codes.md](Troubleshooting/Common/KDC-Status-Codes.md) |
| Controller policy drift | [Common/Controller-Policy-Drift.md](Troubleshooting/Common/Controller-Policy-Drift.md) |
| Event log permissions | [Security/Event-Log-Permissions.md](Troubleshooting/Security/Event-Log-Permissions.md) |
| Event volume and archiving | [Performance/Event-Volume.md](Troubleshooting/Performance/Event-Volume.md) |
| Remote registry access | [Integration/Remote-Registry-Access.md](Troubleshooting/Integration/Remote-Registry-Access.md) |

## The RFC 8009 SHA-2 bits are not honoured by Windows

Worth stating plainly, because this module used to get it wrong and the error pointed the
dangerous way.

MS-KILE documents bits `0x40` and `0x80` as the RFC 8009 SHA-2 encryption types, and this
module mapped them to etypes 19 and 20 accordingly. **A Windows Server 2025 KDC, build 26100,
does not honour them.** Measured directly:

| `msDS-SupportedEncryptionTypes` | Result | Etype issued |
|---|---|---|
| `0x80` | `KDC_ERR_ETYPE_NOTSUPP` | none |
| `0xC0` | `KDC_ERR_ETYPE_NOTSUPP` | none |
| `0x90` (`0x80` + `0x10`) | ticket issued | `0x12` — the SHA1 type; `0x80` ignored |
| `0x10` (control) | ticket issued | `0x12` |

An account carrying only those bits **cannot obtain a service ticket at all**. Because the
module counted them toward `SupportsAes`, it reported such an account as AES-capable and safe —
a false negative on an account that could not authenticate.

The bits are still decoded and named, so nothing is hidden from a report, but they no longer
confer ticket capability and `CarriesUnhonouredSha2Bits` surfaces the discrepancy. See
[Etype-Numbering-Systems.md](Troubleshooting/Common/Etype-Numbering-Systems.md).

> This is one build of one platform. If a future Windows release honours these bits, the
> catalog entry in `Get-KrbEtypeCatalog` is where to change it back — and it should be changed
> back only against a measurement, never against a document.

## Validation lab

The behaviours a single-controller lab cannot produce — schema-version differences between
controllers, controller disagreement, and cross-forest trust encryption types — were exercised
against a purpose-built multi-VM lab. Its build guide is kept privately rather than published,
because it necessarily carries the addressing of the estate it was written for.

The lab has been executed. Results are in `..\KrbEtypeLab-Results\`, and they closed all three gaps —
one of them, above, *against* the assumption. The lab surfaced five defects that the 377-test
suite had not, all now fixed and regression-tested:

| Defect | What was wrong |
|---|---|
| SHA-2 bit mapping | `0x40`/`0x80` claimed AES capability the KDC does not grant |
| Controller disagreement | An unset controller was excluded from the vote, so genuine disagreement read as agreement and the *wrong* controller was named as outlier |
| Unreachable controller | Scored as agreeing rather than unknown — a firewalled DC read as consensus |
| NTSTATUS in `Status` | Catalog stopped at `0x3C`; `0xC000019B` and its siblings resolved to no name |
| Referral detection | Keyed on a `krbtgt/` prefix the KDC never writes — see below |

**Cross-realm referrals do not carry a `krbtgt/` prefix.** A 4769 referral records the bare
target realm in `ServiceName` (`LAB.CONTOSO.TEST`), while the literal `krbtgt` is what *local
TGT renewals* carry. Referrals are now matched against the real trust names and attributed to
the trust, which turns `KRB014` from a claim about configuration into an observation —
`ObservedReferralEtypes` on that finding is what the KDC actually issued cross-realm. See
[Trust-Encryption-Types.md](Troubleshooting/Common/Trust-Encryption-Types.md).

## References

- [KB5021131 — managing the Kerberos protocol changes for CVE-2022-37966](https://support.microsoft.com/help/5021131)
- [MS-KILE 2.2.7 — Supported Encryption Types Bit Flags](https://learn.microsoft.com/openspecs/windows_protocols/ms-kile/6cfc7b50-11ed-4b4d-846d-6f08f0812919)
- [RFC 3961 — Encryption and Checksum Specifications for Kerberos 5](https://www.rfc-editor.org/rfc/rfc3961)
- [RFC 4120 — The Kerberos Network Authentication Service (V5)](https://www.rfc-editor.org/rfc/rfc4120)

## Source

[github.com/fadwen/TechbyJeff](https://github.com/fadwen/TechbyJeff) — this module lives under
[`Powershell/Active Directory/Kerberos/KrbEtypeInsight`](https://github.com/fadwen/TechbyJeff/tree/main/Powershell/Active%20Directory/Kerberos/KrbEtypeInsight).

## Author

Jeffrey Stuhr
[techbyjeff.net](https://www.techbyjeff.net) ·
[LinkedIn](https://www.linkedin.com/in/jeffrey-stuhr-034214aa/)

## License

Copyright (C) 2026 EntraVantage LLC.

Released under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for the full
text. In short: you may use, study, modify and redistribute it, and any distributed derivative
must carry the same licence and make its source available. It comes with no warranty, which is
worth reading literally for a tool whose output informs changes to a production directory —
verify its findings before acting on them.
