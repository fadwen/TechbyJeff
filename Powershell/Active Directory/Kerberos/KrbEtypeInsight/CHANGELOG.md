# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Tests/Stubs` — a generated stand-in for the six RSAT cmdlets the unit suites mock, so
  those suites run on a host without RSAT. The suites already mocked every directory call
  and never reached a domain; what stopped them was that Pester cannot attach a mock to a
  command that does not exist, which failed 91 of 402 unit tests on a workstation. The stub
  path is appended to `PSModulePath`, not prepended, so a controller with real RSAT still
  binds against the real cmdlets. Verified 402 passing in both environments.

## [1.0.0] - 2026-08-19

First public release. The module was developed and validated against a live two-controller
domain with a cross-forest trust before this version was cut, so the notes below record what
that validation changed rather than only what was built.

### Added

- `ConvertFrom-KrbEtype` — decodes both Kerberos numbering systems: RFC 3961 ticket
  encryption type numbers and MS-KILE `msDS-SupportedEncryptionTypes` bit flags, plus the
  client advertised encryption type name list from version 2 events.
- `Get-KrbEvent` — collects 4768, 4769 and 4771 from live domain controllers or archived
  `.evtx` files, handling the version 0, 1 and 2 audit schemas.
- `Get-KrbPrincipalEtype` — per-account configuration, including the `userAccountControl`
  overrides that supersede the encryption type attribute.
- `Get-KrbDomainEtypeContext` — the domain baseline: functional level, per-controller
  `DefaultDomainSupportedEncTypes` including disagreement between controllers, krbtgt, and
  trust encryption types.
- `Get-KrbEtypeRisk` — correlates the above into per-principal risk objects naming the
  specific clients a change will break.
- `Export-KrbEtypeReport` — self-contained HTML, per-finding CSV, or full-fidelity JSON.
- A performance suite (`Tests/Performance`) enforcing decode throughput, catalog reuse and
  sub-linear correlation scaling. It runs offline against fixtures, so it behaves identically
  on a controller and on a CI runner.

### Fixed during pre-release validation

Each of these was found by running against real domains rather than by review, and each has a
regression test that fails without the fix.

- **Boot-time AES advertisement defeated the named-client list.** Client AES capability was
  accumulated as a union, so a single AES advertisement anywhere marked a client capable.
  Every domain-joined Windows machine emits exactly one AES256 `TGS-REQ` for `krbtgt/REALM`
  at boot — confirmed on the wire across seven boots and two unrelated machines — so with a
  30-day window essentially every client was marked AES-capable and `KRB005` could not fire
  for the population it exists to describe. Service ticket requests whose service is `krbtgt`
  are now excluded from capability evidence, and the finding reports the counts behind it.
- **Cross-realm referrals were misidentified.** Referrals log the bare realm as
  `ServiceName`, not `krbtgt/REALM`. A real referral also reports `AvailableKeys = None`,
  which would otherwise have produced a spurious Critical `KRB002` about a realm rather than
  `KRB014` about the trust.
- **Controller disagreement resolution.** An unset controller now votes for the documented
  Windows default rather than abstaining, unreachable controllers abstain rather than
  counting as agreement, and ties resolve toward the Windows default.
- **RFC 8009 SHA-2 bits.** Corrected against measured KDC behaviour: an account carrying only
  `0x40`/`0x80` is rejected with `KDC_ERR_ETYPE_NOTSUPP` rather than being treated as
  AES-capable.
- **NTSTATUS result codes** added to the status catalog; the `Status` field carries both RFC
  4120 codes and NTSTATUS values.
- **Absent-marker handling.** A dash rather than `N/A` in the advertisement field was being
  read as evidence, setting `ClientAdvertizedSupportsAes = $false` on every failure event.

### Known limitations

- `KRB002` is covered by fixtures and unit tests only. The condition is real, but it cannot
  arise in a domain a current Windows build can host — see the README section of the same
  name for the reasoning and the evidence.
- Collection is sequential across controllers. Parallel collection measured roughly 2.7x
  faster, but Pester mocks do not cross the `ForEach-Object -Parallel` boundary, which would
  leave the server-side filtering contract and the fault-tolerance behaviour untested. The
  archive-to-`.evtx` pattern in the Troubleshooting notes is the supported answer for large
  estates.
- Predictions have been validated by outcome, at small scale, in both directions that matter.
  Three hardening dry runs withdrew RC4 at the KDC and compared what actually failed against
  predictions recorded beforehand.

  Service-side: the one service the module named — configured RC4-only, observed using only
  RC4 — was the only thing that failed, and an AES-capable service predicted safe kept working
  and moved silently to AES256.

  Client-side (`KRB005`, the named list of client machines, which is the module's actual
  deliverable): **both** clients it named failed, each at the AS exchange with
  `KDC_ERR_ETYPE_NOTSUPP` — unable to obtain a TGT at all, which is exactly what that finding
  claims. One of the two carried a single AES advertisement that would have exonerated it
  under the pre-release logic, so the hardening also confirmed the capability fix by outcome.

  **No run produced a false negative.** What remains untested is scale, and the
  predicted-to-break principals that have no traffic and so could not be exercised.
- `WillBreakOnHardening` means "predicted to break given observed use", not "cannot work". An
  account configured without AES that produced no traffic in the window is reported as
  `KRB012` rather than as breaking. Absence of traffic is not evidence of safety, and a report
  should not be read as though it were.

[1.0.0]: https://github.com/fadwen/TechbyJeff
