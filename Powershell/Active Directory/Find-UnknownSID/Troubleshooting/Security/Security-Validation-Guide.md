# Security Validation Guide - Find-UnknownSID

## Overview

This guide describes the security controls built into `Find-UnknownSID.ps1`: how a run is gated
before it changes anything, how each SID is validated before removal, what is backed up, how class
files are loaded, and how the audit trail is protected from log-level filtering. It also shows how
to verify each control and how to customise the lists it relies on.

## Operating Modes and Gates

| Mode | Parameters | Effect on the directory |
|---|---|---|
| Discovery (default) | `-SearchBase` | Read-only: `Get-ADObject`, `Get-Acl`, SID lookups |
| Removal | `-Remove` | Modifies ACLs; writes a backup first |
| Restore | `-Restore -BackupPath` | Rewrites ACLs from backup files |

### -WhatIf

Removal and restore honour `SupportsShouldProcess`. With `-WhatIf` the full discovery runs, every
planned removal is logged as `WhatIf: Would remove orphaned SID: <SID> from <DN>` and recorded in
the results with `SecurityValidation = 'WhatIf - Would Remove'`, and no ACL is written and no
backup is created.

### Confirmation and -Force

A `-Remove` or `-Restore` run without `-WhatIf` requires an explicit go-ahead:

- In an interactive console the script asks once through `ShouldContinue`:
  `This will remove orphaned SIDs from ACLs for: <search bases>` (or
  `restore ACLs from backup for: ...`). Answering No stops the run.
- In a session that cannot prompt (scheduled task, CI, remote host) the run stops with:

  ```text
  Refusing to remove orphaned SIDs from ACLs without confirmation. Re-run with -Force to proceed unattended, or with -WhatIf to preview the changes.
  ```

- `-Force` skips the prompt and is the only way to run destructive modes unattended.

```powershell
# Preview
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Test,DC=contoso,DC=com" -WhatIf

# Interactive, prompted once
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Test,DC=contoso,DC=com"

# Unattended
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Test,DC=contoso,DC=com" -Force -SuppressConsoleOutput
```

## Input Validation

- **SearchBase**: each value is checked by `Test-ValidDistinguishedName`
  (`Private\ActiveDirectory\Test-ValidDistinguishedName.ps1`) before processing. It requires the
  form `(CN|OU|DC)=...,DC=...`, rejects control characters and a set of injection patterns, and
  validates each component. A failing value stops `Invoke-MainProcessingLogic` with a parameter
  validation error.
- **OutputPath**: the parent directory must exist.
- **BackupPath**: for `-Restore` the directory must exist; for `-Remove` its parent must exist.
- **ConfigPath**: the file must exist; `ScriptConfiguration.LoadFromFile` validates every key it
  reads (regex patterns must compile, protected SIDs must match `^S-1-\d+(-\d+)*$`, numeric ranges
  are enforced).
- **LogPath**: the directory is created if missing.
- **MaxRetries** 1-10, **MaxMemoryUsageMB** 100-16384, **LogLevel** from a fixed set.

`Test-PathTraversal` (`Private\Security\Test-PathTraversal.ps1`) exists as a utility for checking
that a path stays under a base directory, but the script does not call it.

## SID Validation Before Removal

Every SID that discovery marks orphaned passes through `Invoke-SecurityValidation`
(`Private\Security\Invoke-SecurityValidation.ps1`) inside `Invoke-RemovalWorkflow` before any ACL
is touched. It calls `Test-SIDSecurity -ValidationLevel Standard` for each SID and produces a
`SecurityValidationResult` with `IsValid`, `RiskLevel`, `AllowedSIDs`, `BlockedSIDs`, `Issues` and
`RequiresElevatedConfirmation`. If any SID is blocked the whole object is skipped with
`SECURITY BLOCK: Security validation failed: <issues>` at Error level, and only `AllowedSIDs` are
ever passed to `Invoke-SIDRemoval`.

### Test-SIDSecurity

`Private\SID\Test-SIDSecurity.ps1` applies these checks in order; the first block wins:

1. **Malicious input patterns.** The SID string is compared with `-like` against
   `|`, `&`, `;`, `net user`, `cmd`, `powershell`, `invoke-`, `start-process`, `<script`, `<`, `>`,
   `$(` and `` `$( ``. A match sets `RiskLevel = Critical`, blocks the SID and writes a
   `SecurityViolation` audit entry.
2. **Protected SID list.** An exact match against `ProtectedSIDs` blocks with `RiskLevel = Critical`
   and the issue `SID is in protected SIDs list - removal blocked by security policy`. Defaults:

   | SID | Principal |
   |---|---|
   | S-1-5-32-544 | Administrators |
   | S-1-5-32-545 | Users |
   | S-1-5-32-546 | Guests |
   | S-1-5-18 | Local System |
   | S-1-5-19 | Local Service |
   | S-1-5-20 | Network Service |

3. **Well-known SIDs.** `Test-WellKnownSID` (`Private\SID\Test-SIDFormat.ps1`) returns true for:
   configuration `WellKnownSIDPatterns` (defaults cover Everyone, Authenticated Users, built-in
   groups `S-1-5-32-*`, Creator Owner/Group, Local System/Service, Network Service, Service,
   integrity levels, app packages, and the `S-1-5-80/90/96/84` service prefixes), the protected
   list, every `S-1-5-32-*`, a fixed list of universal and NT Authority SIDs, and domain RIDs 512,
   518 and 519 (Domain, Schema and Enterprise Admins). At `Standard` or `Strict` level a well-known
   SID is blocked with `RiskLevel = High`. Other domain RIDs, including 500 (Administrator) and 513
   (Domain Users), are not well-known and are not blocked by this check.
4. **Risk from Get-SIDAnalysis.** `Private\SID\Get-SIDAnalysis.ps1` categorises the SID:

   | Situation | RiskLevel |
   |---|---|
   | Invalid format | High |
   | Well-known | Low |
   | Local domain, RID 502 (KRBTGT) or 100000 and above | High |
   | Local domain, RID 500, 503-999, 5000-99999 | Medium |
   | Local domain, RID 501 or 1000-4999 | Low |
   | Foreign domain (`CurrentDomainSID` given, no match) | High |
   | Unknown domain (`CurrentDomainSID` not given) | High |

   `High` sets `RequiresElevatedConfirmation` and adds the issue
   `High-risk SID requires elevated confirmation for removal`; at `Strict` level it also blocks.
   `Medium` sets `RequiresElevatedConfirmation` only at `Strict`. `Invoke-MainProcessingLogic`
   reads the domain SID once with `Get-ADDomain` and passes it down through
   `Invoke-SecurityValidation` and `Test-SIDSecurity`, so SIDs from the current domain are rated
   `Medium` and foreign ones `High`. If that lookup fails the log carries
   `Could not determine the current domain SID` and every domain SID is analysed as
   `Unknown Domain` with `RiskLevel = High`; removal still proceeds at `Standard` level, but the
   issue text appears in the result.
5. **Critical object context.** If `ObjectDN` matches a `CriticalObjectPatterns` wildcard
   (`*CN=Domain Admins*`, `*CN=Enterprise Admins*`, `*CN=Schema Admins*`, `*CN=BUILTIN*`,
   `*CN=Users,DC=*`, `*CN=Computers,DC=*`), `RequiresElevatedConfirmation` is set and
   `RiskLevel = High` with the issue `SID is on critical object: <DN>`. This never blocks on its
   own.

Every decision writes a `DataValidation` security audit entry (see
[Security-Logging-Issues.md](./Security-Logging-Issues.md)).

### Get-SIDRiskAssessment

`Get-SIDRiskAssessment -SIDList <sids>` runs `Get-SIDAnalysis` and `Test-SIDSecurity` over a list
and returns `OverallRisk`, `RiskBreakdown`, `BlockedSIDs`, `AllowedSIDs`, `RequiresApproval`,
`Recommendations` and `SafeForAutomation` (true only when nothing is blocked and nothing requires
approval). It is a reporting helper and is not called by the main script.

### Verifying the validation

The functions are private. Load them, then test representative SIDs:

```powershell
Set-Location "<path to Find-UnknownSID>"
. .\Private\Core\Import-LoggingSystem.ps1
. .\Classes\ScriptConfiguration.ps1
. .\Classes\SecurityValidationResult.ps1
. .\Classes\SIDAnalysisResult.ps1
. .\Private\SID\Test-SIDFormat.ps1
. .\Private\SID\Get-SIDAnalysis.ps1
. .\Private\SID\Test-SIDSecurity.ps1
. .\Private\Security\Invoke-SecurityValidation.ps1
Initialize-LoggingSystem -LogLevel Information
$script:Config = [ScriptConfiguration]::new()

$domainSID = (Get-ADDomain).DomainSID.Value
foreach ($sid in 'S-1-5-32-544', 'S-1-5-18', "$domainSID-512", "$domainSID-500", "$domainSID-1001", 'S-1-5-21-1-2-3-1001;cmd') {
    $v = Test-SIDSecurity -SIDString $sid -ObjectDN 'CN=Test,OU=Users,DC=contoso,DC=com'
    "{0,-45} Valid={1,-5} Risk={2,-8} Elevated={3,-5} {4}" -f $sid, $v.IsValid, $v.RiskLevel, $v.RequiresElevatedConfirmation, ($v.Issues -join '; ')
}
```

Expected: the first three are blocked (protected or well-known), `-500` and `-1001` are valid with
`RiskLevel = High` (unknown domain context) and `RequiresElevatedConfirmation = True`, and the
last is blocked as a malicious pattern.

```powershell
$result = Invoke-SecurityValidation -OrphanedSIDs @("$domainSID-1001", 'S-1-5-32-544') -ObjectDN 'CN=Test,OU=Users,DC=contoso,DC=com'
$result.IsValid        # False: one SID blocked blocks the object
$result.BlockedSIDs    # S-1-5-32-544
$result.AllowedSIDs    # <domain>-1001
```

## Backup Before Change

In `Invoke-RemovalWorkflow`, after security validation passes and before any ACE is removed,
`New-ACLBackup` writes the object's current ACL to
`<BackupPath>\<safe object name>_<yyyyMMdd_HHmmss>.xml` with metadata and a SHA256 hash of the SDDL
for integrity checking. If the backup fails the removal is aborted
(`Failed to create ACL backup - aborting removal operation`). The main script defaults
`-BackupPath` to `.\Backup\<yyyyMMdd_HHmmss>\` under the script directory when `-Remove` is used
without it. Under `-WhatIf` no backup is written because no change is made.

`-Restore -BackupPath <folder>` validates each backup file (`Test-BackupValidation`, including the
hash) before `Restore-ACLOperation` rewrites the ACL. See
[Backup-Restore-Issues.md](../Common/Backup-Restore-Issues.md).

## Class Loading

Classes are loaded through `Import-SecureClasses` (`Private\ClassManagement\Import-SecureClasses.ps1`):

- Only class names on the list returned by `Get-ApprovedClassList` are accepted; a request for an
  unknown class fails the import.
- `Resolve-ClassPath` resolves each name to `Classes\<Name>.ps1` under the script root.
- `Test-ClassIntegrity -Class <name>` (`Private\Security\Test-ClassIntegrity.ps1`) checks the
  class name only. No file hash is computed or compared at load time; the `ExpectedHash` values in
  `Get-ApprovedClassList` are reference data for `Tools\Generate-ClassHashes.ps1`, not a runtime
  gate.

Protect the `Classes\` and `Private\` folders with file-system ACLs; the script trusts their
contents.

## Audit Trail

Security events bypass `-LogLevel` filtering and are always written to the log file as JSON lines
with `Component = SecurityAudit`. Events written during a run:

| SecurityEventType | OperationName or source | When |
|---|---|---|
| ObjectAccess | `AD-ObjectDiscovery` | Attempt/Success/Failure per search base |
| ObjectAccess | `OrphanedSID-Detection` | Success per object with findings, listing the SIDs |
| ObjectAccess | `OrphanedSID-Removal` | Attempt/Success/Failure per SID; WhatIf attempts carry `WhatIfMode = true` |
| DataValidation | `Test-SIDSecurity` | Attempt, then Success or Failure (blocked) per SID |
| SecurityViolation | `Test-SIDSecurity` | Malicious pattern detected |
| PrivilegeUse | `Invoke-RemovalWorkflow` | ACL modification initiated |

How to read them, and what to do when they land in emergency files, is in
[Security-Logging-Issues.md](./Security-Logging-Issues.md).

## Customising the Lists

Supply a JSON file with `-ConfigPath`. Only these keys are read:

```json
{
  "ProtectedSIDs": [
    "S-1-5-32-544", "S-1-5-32-545", "S-1-5-32-546",
    "S-1-5-18", "S-1-5-19", "S-1-5-20",
    "S-1-5-21-1234567890-1234567890-1234567890-500",
    "S-1-5-21-1234567890-1234567890-1234567890-513"
  ],
  "WellKnownSIDPatterns": [
    "^S-1-1-0$", "^S-1-5-11$", "^S-1-5-32-", "^S-1-3-[0-4]$",
    "^S-1-5-18$", "^S-1-5-19$", "^S-1-5-20$", "^S-1-5-6$",
    "^S-1-16-", "^S-1-15-2-\\d+$", "^S-1-5-80-\\d+$", "^S-1-5-90-\\d+$",
    "^S-1-5-96-\\d+$", "^S-1-5-84-\\d+$",
    "^S-1-5-21-1234567890-1234567890-1234567890-(500|501|513|515|516|517|520)$"
  ],
  "MemoryCheckInterval": 50,
  "LogLevel": "Information"
}
```

- `ProtectedSIDs` must each match `^S-1-\d+(-\d+)*$`; a match blocks removal outright.
- `WellKnownSIDPatterns` must compile as .NET regular expressions; a match excludes the SID from
  discovery as well as from removal.
- Supplying either key replaces the default list for that key; include the defaults you want to
  keep.
- `CriticalObjectPatterns` is not read from the file; the defaults listed above always apply.

## Security Checklist Before a Removal Run

- [ ] A `-WhatIf` run has been reviewed and the CSV examined for false positives.
- [ ] `-ConfigPath` lists any domain-specific principals that must never be removed.
- [ ] `-BackupPath` points at storage that is itself backed up; the default `.\Backup\` is on the
      script host.
- [ ] The run is interactive, or `-Force` is deliberate and the job is monitored.
- [ ] The log file location is writable so security entries do not fall back to `$env:TEMP`.
- [ ] `Classes\` and `Private\` are write-protected on the host.

## Related Documentation

- [Security Logging Issues](./Security-Logging-Issues.md)
- [Orphaned SID Issues](./Orphaned-SID-Issues.md)
- [SID Format Issues](./SID-Format-Issues.md)
- [SID Analysis Issues](./SID-Analysis-Issues.md)
- [Backup and Restore Issues](../Common/Backup-Restore-Issues.md)
- [Find-UnknownSID Issues](../Common/Find-UnknownSID-Issues.md)
