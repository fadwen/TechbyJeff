# Metadata Population Issues - Troubleshooting Guide

## Overview

Every orphaned SID the script finds becomes one `OrphanedSIDResult` object
(`Classes\OrphanedSIDResult.ps1`). `New-OrphanedSIDResult` (`Private\SID\New-SIDResult.ps1`) fills
it in three steps:

1. Core identification: `ObjectDN`, `ObjectClass`, `OrphanedSID`, `LikelySource`, `Confidence`,
   `AnalysisNotes`.
2. `Add-ProcessingMetadata`: `ProcessingMethod`, `ActionTaken` (always `Detected`),
   `CorrelationId`, `Timestamp`, plus a `ProcessingContext` note property.
3. `Set-ACLMetadata`: `AccessControlType`, `ActiveDirectoryRights`, `InheritanceType`,
   `ObjectType`, `InheritedObjectType`, `IsInherited`, read from the access rule.

`Find-OrphanedSIDsInObject` then attaches a `ProcessingStatistics` note property to each result for
the object it came from. This guide covers the metadata that can look wrong and why.

## Common Issues

### 1. Timestamps

#### Issue: Timestamps are local time, not UTC

`Timestamp` is set with `Get-Date` in the class constructor and again in `Add-ProcessingMetadata`,
so it carries the local time of the machine running the script with `Kind = Local`. The CSV written
by `-OutputPath` serialises it in the local culture's format. This is by design; convert on the way
out when a downstream system needs UTC:

```powershell
Import-Csv -Path .\Reports\orphaned-sids.csv | ForEach-Object {
    $_.Timestamp = ([datetime]$_.Timestamp).ToUniversalTime().ToString('o')
    $_
} | Export-Csv -Path .\Reports\orphaned-sids-utc.csv -NoTypeInformation
```

Backup files use a different field: `BackupDate` is written as `yyyy-MM-ddTHH:mm:ss.fffZ` text
(local time with a literal `Z`). Treat it as local when comparing with `Timestamp`.

#### Issue: Timestamps appear out of order or far apart in one run

Results are created when each access rule is evaluated, so the `Timestamp` spread equals the
run's duration. A gap of minutes between consecutive objects usually reflects SID lookups being
retried (`Retry attempt N of M for object <DN>` in the log). Check the system clock only when
timestamps are in the future relative to the log file's own timestamps.

### 2. Processing Metrics

#### Issue: Per-object duration looks wrong

There is no per-result `ProcessingTime` property. Timing lives in the `ProcessingStatistics` note
property that `Find-OrphanedSIDsInObject` attaches to every result from one object:

| Key | Meaning |
| --- | --- |
| `ObjectDN` | Object the statistics belong to |
| `StartTime`, `EndTime` | `Get-Date` at start and end of that object |
| `Duration` | Milliseconds between them |
| `AccessRulesRetrieved` | Rules returned by `Get-ObjectAccessRule` |
| `ProcessedSIDs` | Rules evaluated |
| `SkippedSIDs` | Rules skipped (no identity, well-known, or error) |
| `OrphanedSIDsFound` | Results created |
| `ErrorsEncountered` | Exceptions caught for that object |
| `ProcessingMethod` | `Orchestrated-Workflow` |

`Duration` is a `Get-Date` difference, so sub-millisecond work shows as `0`. It is not written to
the CSV (only class members are exported). To see it, run the per-object function directly in a
diagnostic session:

```powershell
Set-Location 'C:\Scripts\Find-UnknownSID'
Import-Module ActiveDirectory
. .\Private\Core\Import-LoggingSystem.ps1
Get-ChildItem .\Classes\*.ps1 | ForEach-Object { . $_.FullName }
'SID\Test-SIDFormat', 'SID\Get-SIDAnalysis', 'ActiveDirectory\Invoke-ADOperationWithRetry',
'Operations\Invoke-OperationWithRetry', 'Logging\Write-ADOperationSecurityLog', 'SID\Test-OrphanedSID',
'Security\Get-SecurityDescriptor', 'SID\Resolve-SIDIdentity', 'SID\New-SIDResult', 'SID\Invoke-SIDProcessing' |
    ForEach-Object { . ".\Private\$_.ps1" }

$object = Get-ADObject -Identity 'CN=User1,OU=Test,DC=contoso,DC=com' -Properties nTSecurityDescriptor, ObjectClass
$results = Find-OrphanedSIDsInObject -ADObject $object -IncludeInherited
$results | Select-Object -First 1 -ExpandProperty ProcessingStatistics
```

`Get-SIDProcessingStatistics` (same file) aggregates these across results:
`TotalObjectsProcessed`, `TotalSIDsProcessed`, `AverageProcessingTimeMS`, `ProcessingThroughput`
and so on. It returns `$null` with the warning `No processing statistics found in results` when the
results carry no `ProcessingStatistics` property, which happens after a round trip through CSV.

#### Issue: Memory figures missing from the summary

`Peak memory usage: N MB` in the summary comes from `MemoryManager.GetPeakMemoryUsage()`. Current
process figures come from `Get-CurrentMemoryUsage` (`Private\System\Get-MemoryStatistics.ps1`),
which returns `WorkingSetMB`, `PrivateMemoryMB`, `VirtualMemoryMB` and `GCTotalMemoryMB`; a failure
is reported as `Failed to retrieve memory usage: <message>`. These read the current process only;
no WMI query is involved. See `.\Troubleshooting\Performance\Memory-Management-Issues.md`.

### 3. Correlation IDs

#### Issue: Many results share one correlation ID

Expected. `New-OrphanedSIDResult` receives `-CorrelationId` from the calling chain
(`Find-OrphanedSIDsInObject` -> `Test-AccessRuleForOrphanedSID`), so every result from one object
shares that object's ID. A result generates its own GUID in the class constructor only when no ID is
passed. Uniqueness per result is not a goal; traceability from result to log lines is.

The main run's `-CorrelationId` is what appears in the `[Main]`, `[MainProcessing]` and `[Summary]`
log lines. Per-object IDs are generated inside `Invoke-MainProcessingLogic` when it calls
`Find-OrphanedSIDsInObject`, so a result's `CorrelationId` is the per-object GUID, not the run's.
To tie a result back to a run, filter the log file by `ObjectDN` instead:

```powershell
$dn = 'CN=User1,OU=Test,DC=contoso,DC=com'
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern ([regex]::Escape($dn)) | Select-Object -First 10
```

#### Issue: Correlation ID format

All generated IDs are GUID strings (`[System.Guid]::NewGuid().ToString()`). The main script accepts
any string for `-CorrelationId`, but `Test-BackupValidation` in the restore path validates
`-CorrelationId` as a GUID (`CorrelationId must be in valid GUID format`). Use GUIDs throughout:

```powershell
$id = [guid]::NewGuid().ToString()
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -CorrelationId $id
```

### 4. Processing Context

Each result also carries a `ProcessingContext` note property (hashtable) with `MachineName`,
`UserName`, `ProcessId`, `PowerShellVersion` and `ModuleVersion`. Like `ProcessingStatistics` it is
not a class member and is not exported to CSV; it is available on the live objects only.

### 5. ACL Metadata Defaults

When the access rule lacks a property, `Set-ACLMetadata` substitutes a default and logs it at
Debug level:

| Property | Default when absent | Debug message |
| --- | --- | --- |
| `AccessControlType` | `Allow` | `AccessControlType property missing, set to Allow` |
| `ActiveDirectoryRights` | `GenericRead` (after trying a `Rights` property) | `ActiveDirectoryRights property missing, set to GenericRead` |
| `InheritanceType` | `None` | `InheritanceFlags property missing, set to None` |
| `ObjectType`, `InheritedObjectType` | `Guid.Empty` | `GUID property <name> missing or null, set to Empty` |
| `IsInherited` | `$false` | `IsInherited property missing, set to false` |

Defaults appear mainly on deserialized access rules. If many results show `GenericRead` and
`Allow`, run with `-LogLevel Debug` and look for these messages to confirm.

## Validation Commands

```powershell
# After a run with -OutputPath
$rows = Import-Csv -Path .\Reports\orphaned-sids.csv

# Every row has the identifying fields
$rows | Where-Object { -not $_.ObjectDN -or -not $_.OrphanedSID -or -not $_.CorrelationId }

# Timestamps fall inside the run window recorded in the log
$rows | ForEach-Object { [datetime]$_.Timestamp } | Measure-Object -Minimum -Maximum

# SIDs are well formed
$rows | Where-Object { $_.OrphanedSID -notmatch '^S-1-\d+(-\d+)+$' }
```

## Related Documentation

- `.\Troubleshooting\Common\Result-Creation-Issues.md`
- `.\Troubleshooting\Common\Result-Validation-Issues.md`
- `.\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md`
- `.\Troubleshooting\Performance\Memory-Management-Issues.md`

## Support Information

- **Module**: `Private\SID\New-SIDResult.ps1`
- **Functions**: `New-OrphanedSIDResult`, `Add-ProcessingMetadata`, `Set-ACLMetadata`,
  `Get-SafeGuidProperty`, `ConvertTo-ResultSummary`
- **Correlation ID**: include the run's `-CorrelationId` in support requests
