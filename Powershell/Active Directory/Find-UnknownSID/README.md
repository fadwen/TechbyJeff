# Find-UnknownSID

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x%20(Windows)-blue)](https://github.com/PowerShell/PowerShell)
[![Active Directory](https://img.shields.io/badge/dependency-RSAT%20ActiveDirectory-orange)](https://learn.microsoft.com/powershell/module/activedirectory/)
[![Tests](https://img.shields.io/badge/tests-Pester%203.4-blue)](./Documentation/Quick-Test-Reference.md)

## Overview

**Business value:** Orphaned Security Identifiers (SIDs) are access control entries that still grant
rights to accounts that no longer exist. They accumulate on every Active Directory object as users,
groups and computers are deleted, and they clutter security reviews. Find-UnknownSID finds them,
removes them with a backup of every ACL it touches, and can put an ACL back from that backup.

**Technical summary:** A single PowerShell script, `Find-UnknownSID.ps1`, that dot-sources its
components from `Private/` and `Classes/`. It walks the objects under one or more search bases,
reads each security descriptor, resolves every identity reference, and records the ones that do not
resolve. Results stream to batch files on disk so memory stays flat on large OUs.

### Key features

- **Three modes.** Discovery (default, read-only), `-Remove` (backup then strip the orphaned ACEs),
  and `-Restore` (apply a backed-up ACL to an object).
- **Backup before change.** Every `-Remove` run writes one Clixml file per modified object into a
  timestamped folder. `-Restore` validates the backup's SHA256 hash before applying it.
- **Protected SID checks.** Well-known SIDs (BUILTIN groups, SYSTEM, LOCAL SERVICE, NETWORK SERVICE,
  Domain Admins, Enterprise Admins, Schema Admins) are never treated as orphaned.
- **Confirmation gate.** `-Remove` and `-Restore` prompt once in an interactive console. In an
  unattended session they stop unless `-Force` is given. `-WhatIf` previews either mode.
- **Correlation tracking.** One correlation ID per run, carried through every log line, backup file
  and result row. Pass your own with `-CorrelationId` to tie a run to a ticket or pipeline job.
- **Audit log that survives log-level filtering.** Security events are written to the log file
  regardless of `-LogLevel`.
- **Memory management.** Results are flushed to disk in batches (`BatchSize`, default 50); memory is
  checked against `-MaxMemoryUsageMB` and garbage collection runs when the threshold is exceeded.

### Target audience

- **Active Directory administrators** cleaning up delegated permissions on OUs.
- **Security teams** auditing which objects carry rights for deleted principals.
- **Compliance teams** who need a CSV and a log with a correlation ID per run.

## Project status

The script and its components are complete for the three modes above. The Pester suite under
`Tests/` targets Pester 3.4 on Windows PowerShell 5.1; see
[Quick Test Reference](./Documentation/Quick-Test-Reference.md) for how to run it and the
current pass counts.

Known gaps:

- Objects are processed sequentially. There is no parallel processing and no thread count to tune.
- The script writes nothing to the pipeline. Automation reads the CSV from `-OutputPath` or the
  summary block in the log.
- Class file hashes are recorded in `Private/ClassManagement/Get-ApprovedClassList.ps1` but are not
  verified at load time; only the class name is checked against the approved list.
- The script runs as the caller. There is no `-Credential` parameter.

## Quick start

```powershell
# Discovery: list orphaned SIDs under an OU, no changes made
.\Find-UnknownSID.ps1 -SearchBase 'OU=Users,DC=contoso,DC=com' -OutputPath '.\Reports\audit.csv' -Verbose

# Preview a removal
.\Find-UnknownSID.ps1 -SearchBase 'OU=Computers,DC=contoso,DC=com' -Remove -WhatIf

# Remove, unattended, with the backup in the default .\Backup\<timestamp>\ folder
.\Find-UnknownSID.ps1 -SearchBase 'OU=Computers,DC=contoso,DC=com' -Remove -Force -OutputPath '.\Reports\cleanup.csv'

# Restore one object from a backup folder
.\Find-UnknownSID.ps1 -Restore -SearchBase 'CN=SRV01,OU=Computers,DC=contoso,DC=com' -BackupPath '.\Backup\20250703_104232' -Force
```

The console shows progress and a summary block. The same lines, with timestamps and the correlation
ID, go to `.\Logs\Find-UnknownSID_<yyyyMMdd_HHmmss>.log`.

## Prerequisites

| Component | Requirement | Notes |
| --- | --- | --- |
| PowerShell | Windows PowerShell 5.1, or PowerShell 7.x on Windows | The ActiveDirectory module is Windows-only |
| ActiveDirectory module | RSAT: Active Directory PowerShell | Not on the PowerShell Gallery; install RSAT (below) |
| Domain | Domain-joined machine with line of sight to a domain controller | |
| Disk | Space for backups and logs | One Clixml file per modified object |

Install the module from RSAT:

```powershell
# Windows 10 / 11
Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'

# Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell

# Verify
Get-Module -ListAvailable ActiveDirectory
```

### Permissions

| Mode | Active Directory right needed |
| --- | --- |
| Discovery | Read on the objects under `-SearchBase` |
| `-Remove` | Write to the security descriptor (Modify Permissions) on the target objects |
| `-Restore` | Same as `-Remove` |

Backups and logs are written as the running user, so the account also needs write access to
`-BackupPath` and `-LogPath`.

## Installation

```powershell
git clone https://github.com/fadwen/TechbyJeff.git
Set-Location 'TechbyJeff\Powershell\Active Directory\Find-UnknownSID'
Get-Help .\Find-UnknownSID.ps1 -Full
```

Keep the folder structure intact. The script dot-sources `Classes/` and `Private/` relative to its
own location.

## Configuration

Most runs need no configuration file. `-ConfigPath` accepts a JSON file whose top-level keys override
the defaults in `Classes/ScriptConfiguration.ps1`. Only these keys are read; anything else is
ignored without a warning:

```json
{
  "WellKnownSIDPatterns": ["^S-1-5-32-", "^S-1-5-18$"],
  "ProtectedSIDs": ["S-1-5-32-544", "S-1-5-32-545", "S-1-5-32-546", "S-1-5-18", "S-1-5-19", "S-1-5-20"],
  "BatchSize": 50,
  "MemoryCheckInterval": 50,
  "EnableDetailedLogging": false,
  "LogLevel": "Information",
  "LogFilePath": null,
  "EnableLogFileRotation": false,
  "MaxLogFileSizeMB": 50
}
```

| Key | Range | Effect |
| --- | --- | --- |
| `WellKnownSIDPatterns` | regex list | Identity references matching any pattern are never reported as orphaned |
| `ProtectedSIDs` | SID list | Never removed, even if unresolvable |
| `BatchSize` | 1-1000 | Results per streaming batch file in `%TEMP%` (default 50) |
| `MemoryCheckInterval` | 1-1000 | Operations between memory checks |
| `LogLevel` | Critical, Error, Warning, Information, Debug, Verbose | Default file log level; `-LogLevel` on the command line wins |

Everything else is a command-line parameter: `-MaxMemoryUsageMB` (100-16384, default 1024),
`-MaxRetries` (1-10, default 3), `-IncludeInherited`, `-LogPath`, `-LogLevel`,
`-SuppressConsoleOutput`, `-PreserveTempFiles`, `-CorrelationId`. There are no environment variables.

## Usage

### Discovery across several OUs

```powershell
'OU=Users,DC=contoso,DC=com', 'OU=Computers,DC=contoso,DC=com' |
    .\Find-UnknownSID.ps1 -IncludeInherited -OutputPath '.\Reports\audit.csv'
```

`-SearchBase` accepts pipeline input and an array. `-IncludeInherited` also reports ACEs inherited
from parent containers; expect more rows and a longer run.

### Removal with a custom backup location

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'OU=Decommissioned,DC=contoso,DC=com' -Remove -Force `
    -BackupPath 'D:\ADBackups' -OutputPath '.\Reports\cleanup.csv' -CorrelationId 'CHG0012345'
```

Backups land in `D:\ADBackups\<yyyyMMdd_HHmmss>\`, one `.xml` per modified object, named from the
object's distinguished name with path-unsafe characters replaced by `_`.

### Restore every object in an OU from a backup set

```powershell
.\Find-UnknownSID.ps1 -Restore -SearchBase 'OU=Decommissioned,DC=contoso,DC=com' `
    -BackupPath 'D:\ADBackups\20250703_104232' -WhatIf
```

When `-SearchBase` is an OU or domain, every backup file under `-BackupPath` whose object sits
under that container is restored. For a single object the most recent matching backup is used.
Drop `-WhatIf` and add `-Force` to apply.

### Scheduled task

```powershell
$report = "C:\Reports\orphaned-sids-$(Get-Date -Format yyyyMMdd).csv"
$correlationId = "SCHED-$(Get-Date -Format yyyyMMddHHmm)"

& 'C:\Scripts\Find-UnknownSID\Find-UnknownSID.ps1' -SearchBase 'DC=contoso,DC=com' `
    -OutputPath $report -SuppressConsoleOutput -CorrelationId $correlationId

# The script emits nothing to the pipeline; read the CSV it wrote
$found = if (Test-Path $report) { @(Import-Csv $report).Count } else { 0 }
if ($found -gt 0) {
    Send-MailMessage -To 'security-alerts@contoso.com' -From 'ad-hygiene@contoso.com' `
        -SmtpServer 'smtp.contoso.com' -Subject "Orphaned SIDs found: $found" `
        -Body "Report: $report`nCorrelationId: $correlationId"
}
```

Exit code is 0 on success and 1 when the end block hits a critical error. There are no other codes.

### CSV columns

One row per orphaned ACE: `ObjectDN`, `ObjectClass`, `OrphanedSID`, `LikelySource`, `Confidence`,
`AnalysisNotes`, `AccessControlType`, `ActiveDirectoryRights`, `InheritanceType`, `ObjectType`,
`InheritedObjectType`, `IsInherited`, `ProcessingMethod`, `ActionTaken`, `CorrelationId`,
`Timestamp`. A `-Restore` run exports one row per object instead.

## Architecture

```text
Find-UnknownSID/
├── Find-UnknownSID.ps1          # Entry point: parameters, confirmation gate, load order, summary
├── Classes/                     # Loaded first, by name from Get-ApprovedClassList
│   ├── ScriptConfiguration.ps1      # Defaults, protected SIDs, JSON override loader
│   ├── MemoryManager.ps1            # Threshold checks and garbage collection
│   ├── StreamingResultsManager.ps1  # Batch files in %TEMP%, CSV export, cleanup
│   ├── ProcessingStatistics.ps1     # Counters and timing for the summary
│   ├── OrphanedSIDResult.ps1        # One row of output
│   ├── SIDAnalysisResult.ps1
│   ├── SecurityValidationResult.ps1
│   ├── RemovalOperationResult.ps1
│   └── RestoreOperationResult.ps1
├── Private/                     # One function per file, grouped by area
│   ├── ACL/                         # Get-ACLForRemoval, Invoke-SIDRemoval, Set-ModifiedACL
│   ├── ActiveDirectory/             # Get-ADObjectFromSearchBase, Get-ADObjectsSequential,
│   │                                #   Invoke-ADOperationWithRetry, Test-ValidDistinguishedName
│   ├── Backup/                      # New-ACLBackup, Find-BackupFile, Get-BackupMetadata,
│   │                                #   Test-BackupValidation, Invoke-RestoreWorkflow, Restore-ACLOperation
│   ├── ClassManagement/             # Get-ApprovedClassList, Resolve-ClassPath, Import-SecureClasses
│   ├── Core/                        # Initialize-ScriptExecution, Start-OrchestrationWorkflow,
│   │                                #   Invoke-MainProcessingLogic, Remove-OrphanedSID, Import-LoggingSystem
│   ├── FileSystem/                  # Get-SafeFileName, Initialize-LogDirectory, Test-DirectoryAccess
│   ├── Logging/                     # Write-StructuredLog, Write-SecurityLog, Test-LogLevel, ...
│   ├── Operations/                  # Invoke-RemovalWorkflow, Invoke-OperationWithRetry
│   ├── Reporting/                   # Write-ProcessingSummary, Get-LogFileSummary, Export-DiagnosticData
│   ├── Security/                    # Get-SecurityDescriptor (Get-ObjectAccessRule), Invoke-SecurityValidation,
│   │                                #   Invoke-RemovalVerification, Test-ClassIntegrity, Test-PathTraversal
│   ├── SID/                         # Test-SIDFormat, Test-OrphanedSID, Resolve-SIDIdentity,
│   │                                #   Get-SIDAnalysis, Test-SIDSecurity, New-SIDResult, Invoke-SIDProcessing
│   ├── System/                      # Initialize-MemoryManager, Invoke-MemoryMonitoring,
│   │                                #   Invoke-GarbageCollection, Invoke-ResourceDisposal, Get-MemoryStatistics
│   └── Utilities/                   # Get-StringHash, Test-BackupIntegrity, Validate-BackupSignature
├── Tests/                       # Pester 3.4 suite: Unit, Integration, Performance
├── Tools/                       # Generate-ClassHashes, Generate-OrphanedSIDs (lab seeding), Invoke-GitWorkflow
├── Documentation/               # Guides listed below, plus Archive/ with development history
├── Troubleshooting/             # Common, Security, Performance, Integration
├── Backup/                      # Created on first -Remove (git-ignored)
└── Logs/                        # Created on first run (git-ignored)
```

### Processing flow

1. `begin`: import the ActiveDirectory module, load the approved classes, dot-source `Private/`,
   initialise logging, configuration and the memory manager.
2. `process`: apply the confirmation gate for `-Remove` and `-Restore`, then either run
   `Invoke-MainProcessingLogic` (discovery and removal) or `Start-OrchestrationWorkflow -OperationType Restore`
   once per `-SearchBase` value.
3. `end`: print the summary, export the CSV, dispose the streaming manager and memory manager.

For each object, `Get-ObjectAccessRule` reads the security descriptor (trying `Get-Acl` on the
`AD:` drive, then the binary `nTSecurityDescriptor`, then a fresh query), `Test-OrphanedSID`
resolves each identity reference with a per-run cache, and `New-OrphanedSIDResult` builds the
output row. In `-Remove` mode `Test-SIDSecurity` and `Invoke-SecurityValidation` run before
`New-ACLBackup` and `Invoke-SIDRemoval`.

## Troubleshooting

Start with the log file. Every line carries the correlation ID, so one run can be isolated with:

```powershell
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern '<correlation id>'
```

| Symptom | Cause | Where to look |
| --- | --- | --- |
| `Active Directory PowerShell module is not available` | RSAT not installed | [Prerequisites](#prerequisites) |
| `Refusing to remove orphaned SIDs from ACLs without confirmation` | Unattended `-Remove` without `-Force` | [Confirmation gate](#key-features) |
| `BackupPath parameter is required when using -Restore` | `-Restore` without `-BackupPath` | [Backup and Restore Guide](./Documentation/Backup-and-Restore-Guide.md) |
| `All security descriptor retrieval methods failed for <DN>` | No read access to the descriptor, or the object vanished mid-run | [Security Descriptor Issues](./Troubleshooting/Security/Security-Descriptor-Issues.md) |
| `Memory usage threshold exceeded` warnings | `-MaxMemoryUsageMB` lower than the working set | [Memory Management](./Troubleshooting/Performance/Memory-Management.md) |
| Restore reports `Backup validation failed` | File edited, truncated or from another object | [Backup-Restore Issues](./Troubleshooting/Common/Backup-Restore-Issues.md) |

Guides by area:

- [Common](./Troubleshooting/Common/): startup, backup and restore, result objects, orchestration
- [Security](./Troubleshooting/Security/): SID format and resolution, security descriptors, security logging
- [Performance](./Troubleshooting/Performance/): memory management, WhatIf behaviour, tuning
- [Integration](./Troubleshooting/Integration/): scheduling and pipeline use

## Performance

Run time is dominated by one LDAP read per object plus one identity lookup per distinct SID. The
SID lookup is cached for the run, so the second object carrying the same orphaned SID costs
nothing extra. Measure in your own environment: the summary block in the log reports objects
processed, duration, objects per second and peak memory.

Levers, in order of effect:

- Narrow `-SearchBase`, or run one OU at a time.
- Leave `-IncludeInherited` off unless the audit needs inherited ACEs.
- Raise `-MaxMemoryUsageMB` if the log shows repeated threshold warnings; lower it on a constrained
  host.
- Set `-LogLevel Warning` to shrink the log file on large runs. Security events are still written.
- Use `-PreserveTempFiles` to keep the batch files in `%TEMP%\Find-UnknownSID-<CorrelationId>\`
  for inspection after a run.

## Security

- `-Remove` and `-Restore` never run without a confirmation prompt, `-Force`, or `-WhatIf`.
- Every modified ACL is backed up first as Clixml with the SDDL, a SHA256 hash of the SDDL, the
  object DN, the correlation ID and the user and computer that made the change.
- `ProtectedSIDs` and `WellKnownSIDPatterns` are checked before any removal. Objects matching
  `CriticalObjectPatterns` (Domain Admins, Enterprise Admins, Schema Admins, BUILTIN, the default
  Users and Computers containers) are flagged high risk in the results.
- Security events are written to the log file at every `-LogLevel`, with a fallback file under
  `%TEMP%` if the main log cannot be written.
- The script runs as the caller; it stores no credentials.

These controls produce evidence an audit can use. They do not by themselves make an environment
compliant with any regulation.

## Documentation

- [Quick Test Reference](./Documentation/Quick-Test-Reference.md): running the Pester suite and current results
- [Backup and Restore Guide](./Documentation/Backup-and-Restore-Guide.md): backup format, restore workflow, validation
- [Automation Guide](./Documentation/Find-UnknownSID-Automation.md): scheduled and pipeline use, exit codes, reading results
- [Memory and Security Notes](./Documentation/Find-UnknownSID-Memory-Security.md): memory behaviour and the security checks
- [Class Loading Security Analysis](./Documentation/Class-Loading-Security-Analysis.md): how classes are loaded and what is and is not verified
- [Security Logging Compliance](./Documentation/Security-Logging-Compliance.md): the always-on security log

[Documentation/Archive](./Documentation/Archive/) holds 74 historical development, refactoring and
testing documents. They describe the project as it was at the time; see
[Archive README](./Documentation/Archive/README.md).

## Testing

The suite targets Pester 3.4 on Windows PowerShell 5.1 and does not need a domain. Tests that
touch AD cmdlets mock them, and stub `Get-ADObject` when RSAT is absent.

```powershell
Import-Module Pester -RequiredVersion 3.4.0 -Force
Invoke-Pester -Path .\Tests\Unit
Invoke-Pester -Path .\Tests\Integration
Invoke-Pester -Path .\Tests\Performance
```

Current results are recorded in [Quick Test Reference](./Documentation/Quick-Test-Reference.md).
