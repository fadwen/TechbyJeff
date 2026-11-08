# Result Validation Issues - Troubleshooting Guide

## Overview

Result objects are instances of the `OrphanedSIDResult` class and are created only by
`New-OrphanedSIDResult`. The class and its members are documented in
`.\Troubleshooting\Common\Result-Creation-Issues.md`; the metadata attached to each result is
documented in `.\Troubleshooting\Common\Metadata-Population-Issues.md`. This page covers how to
check a set of results after a run.

## What to Validate

The script writes results to the CSV named by `-OutputPath` (always CSV, whatever the extension).
The columns are the class members: `ObjectDN`, `ObjectClass`, `OrphanedSID`, `LikelySource`,
`Confidence`, `AnalysisNotes`, `AccessControlType`, `ActiveDirectoryRights`, `InheritanceType`,
`ObjectType`, `InheritedObjectType`, `IsInherited`, `ProcessingMethod`, `ActionTaken`,
`CorrelationId`, `Timestamp`.

```powershell
$rows = Import-Csv -Path .\Reports\orphaned-sids.csv

# 1. Identifying fields present
$rows | Where-Object { [string]::IsNullOrWhiteSpace($_.ObjectDN) -or [string]::IsNullOrWhiteSpace($_.OrphanedSID) }

# 2. SIDs well formed and not well-known
$rows | Where-Object { $_.OrphanedSID -notmatch '^S-1-\d+(-\d+)+$' }
$rows | Where-Object { $_.OrphanedSID -match '^S-1-5-(18|19|20|32-\d+)$|^S-1-1-0$|^S-1-5-11$' }

# 3. DNs resolvable (objects deleted since the run are expected to fail)
$rows.ObjectDN | Sort-Object -Unique | ForEach-Object {
    try { $null = Get-ADObject -Identity $_ -ErrorAction Stop }
    catch { "Not found: $_" }
}

# 4. Timestamps inside the run window and ActionTaken as expected
$rows | ForEach-Object { [datetime]$_.Timestamp } | Measure-Object -Minimum -Maximum
$rows | Where-Object ActionTaken -ne 'Detected'

# 5. Counts agree with the log summary line "Orphaned SIDs found: N"
$rows.Count
```

A SID in the well-known ranges should never appear: `Test-WellKnownSID` filters them before a
result is created. Finding one means the `WellKnownSIDPatterns` list in a `-ConfigPath` file
removed a default pattern.

## Common Findings and Their Meaning

| Finding | Meaning |
| --- | --- |
| Many rows share one `CorrelationId` | Expected: results from the same object share the ID generated for that object |
| `ActiveDirectoryRights = GenericRead`, `AccessControlType = Allow` on every row | Access rules lacked those properties and defaults were applied; see Result-Creation-Issues.md |
| `LikelySource = Unknown` | `Get-SIDAnalysis` had no domain SID to compare against; see `.\Troubleshooting\Security\SID-Analysis-Issues.md` |
| `Timestamp` is local time | By design; convert on export when UTC is required |
| Row count lower than `ORPHANED ACCOUNT DETECTED` log entries suggest | Name-form identities that fail translation are logged but produce no result; see Result-Creation-Issues.md |
| A SID that does resolve today | `Test-OrphanedSID` marks a SID orphaned when every AD lookup fails, so a run against an unreachable domain controller over-reports; re-run and compare |

## Validating Live Objects

In a diagnostic session (prepared as shown in Result-Creation-Issues.md), type checks replace
property-name checks:

```powershell
$results | Where-Object { $_ -isnot [OrphanedSIDResult] }
$results | Where-Object { -not $_.PSObject.Properties['ProcessingStatistics'] }   # attached by Find-OrphanedSIDsInObject
```

`ConvertTo-ResultSummary` in `Private\SID\New-SIDResult.ps1` produces per-source, per-confidence
and per-class counts from live results and is the quickest way to spot skew:

```powershell
$results | ConvertTo-ResultSummary | Select-Object TotalOrphanedSIDs, UniqueObjects, UniqueOrphanedSIDs, SourceCategories
```

## Related Documentation

- `.\Troubleshooting\Common\Result-Creation-Issues.md`
- `.\Troubleshooting\Common\Metadata-Population-Issues.md`
- `.\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md`
- `.\Troubleshooting\Security\Orphaned-SID-Issues.md`

## Support Information

- **Module**: `Private\SID\New-SIDResult.ps1`
- **Class**: `Classes\OrphanedSIDResult.ps1`
