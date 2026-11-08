# SID Processing Orchestration Issues - Troubleshooting Guide

## Overview

`Find-OrphanedSIDsInObject` in `Private\SID\Invoke-SIDProcessing.ps1` is the per-object workflow.
`Invoke-MainProcessingLogic` calls it once for every object returned by `Get-ADObjectsSequential`,
and it returns an array of `OrphanedSIDResult` objects (possibly empty). This guide describes the
components it coordinates, the messages each emits, and the failure modes between them.

## The Workflow

```text
Invoke-MainProcessingLogic                      (Private\Core)
  for each object:
    Find-OrphanedSIDsInObject -ADObject $obj [-IncludeInherited]
      Get-ObjectAccessRule                      (Private\Security\Get-SecurityDescriptor.ps1)
        -> ActiveDirectoryAccessRule[] or $null
      for each rule:
        Test-AccessRuleForOrphanedSID           (Private\SID\Resolve-SIDIdentity.ps1)
          Resolve-IdentityReference             -> SID string, or $null
            Convert-NTAccountToSID              (for NTAccount identities)
          Test-SIDValidityAndType               -> Test-SIDFormat, Test-WellKnownSID
          Test-OrphanedSID                      (Private\SID\Test-OrphanedSID.ps1) -> bool
          Get-SIDAnalysis -SIDString            (Private\SID\Get-SIDAnalysis.ps1)
          New-OrphanedSIDResult                 (Private\SID\New-SIDResult.ps1)
      attach ProcessingStatistics to each result
    StreamingResultsManager.AddResult(...)      (batch files under $env:TEMP\Find-UnknownSID-<CorrelationId>)
    if -Remove: Remove-OrphanedSID per result
```

Objects are processed sequentially; there is no parallel path.

### Component contracts

| Component | Input | Output |
| --- | --- | --- |
| `Get-ObjectAccessRule -ADObject <PSObject> [-IncludeInherited]` | AD object with `DistinguishedName` (and usually `nTSecurityDescriptor`) | `ActiveDirectoryAccessRule[]`; `$null` when every strategy fails |
| `Resolve-IdentityReference -IdentityReference <PSObject>` | `SecurityIdentifier`, `NTAccount`, or a deserialized identity | SID string; `ORPHANED_ACCOUNT:<name>` for an untranslatable `NTAccount`; `$null` otherwise |
| `Test-SIDValidityAndType -SIDString <string>` | SID string | `$true` only for a well-formed, non-well-known SID |
| `Test-OrphanedSID -SID <string>` | SID string | `$true` orphaned, `$false` resolves; cached per SID for the run |
| `Get-SIDAnalysis -SIDString <string> [-CurrentDomainSID <string>]` | SID string | `SIDAnalysisResult` (`LikelySource`, `Confidence`, `Notes`, `RiskLevel`) |
| `New-OrphanedSIDResult` | see Result-Creation-Issues.md | `OrphanedSIDResult` |

## Common Issues

### 1. Objects Skipped Without Results

Each skip is logged at Debug level by `Find-OrphanedSIDsInObject`; run with `-LogLevel Debug` to
see them.

| Debug message | Cause |
| --- | --- |
| `Skipping error object: <message>` | `Get-ADObjectsSequential` emitted an error record (`IsError = $true`) instead of an object |
| `Object missing DistinguishedName property, skipping` | Malformed pipeline input |
| `No security descriptor found for <DN>` | Object arrived without `nTSecurityDescriptor` |
| `No access rules retrieved for <DN>` | `Get-ObjectAccessRule` returned nothing; a Warning `All security descriptor retrieval methods failed for <DN>` usually precedes it (see `.\Troubleshooting\Common\Security-Descriptor-Warnings.md`) |

Skips are not errors. `Processing errors` in the summary counts exceptions caught by the main loop,
not skipped objects.

### 2. Rules Evaluated but No Result Created

Per-rule outcomes are also Debug level in `Test-AccessRuleForOrphanedSID` and its helpers:

| Debug message | Cause |
| --- | --- |
| `Skipping access rule with missing or null IdentityReference for <DN>` | Rule has no identity |
| `Failed to resolve identity reference to SID for <DN>` | `Resolve-IdentityReference` returned `$null` |
| `Extracted string is not a valid SID format: <value> (Type: <type>) for <DN>` | Deserialized identity whose string form is not a SID |
| `Skipping well-known SID: <sid>` | Filtered by `Test-WellKnownSID` (patterns from `ScriptConfiguration.WellKnownSIDPatterns`) |
| `SID validation failed or well-known SID detected: <sid>` | `Test-SIDValidityAndType` returned `$false` |
| `SID <sid> is valid (found in AD)` | `Test-OrphanedSID` resolved the SID |

One case is logged at Information level and is easy to miss:
`ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount '<name>' to SID - likely orphaned: <message>`.
`Convert-NTAccountToSID` returns `ORPHANED_ACCOUNT:<name>`, which `Test-SIDFormat` rejects, so the
rule is skipped and no result is created. Count these when the CSV looks short:

```powershell
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern 'ORPHANED ACCOUNT DETECTED' | Measure-Object
```

### 3. Over-Reporting When the Domain Controller Is Unreachable

`Test-OrphanedSID` tries, in order: `Get-ADObject -Filter "objectSid -eq '<sid>'"`, the same
with `-IncludeDeletedObjects`, `SecurityIdentifier.Translate`, then `Get-ADUser`, `Get-ADGroup`
and `Get-ADComputer`. Each AD call goes through `Invoke-ADOperationWithRetry`, which retries
transient errors up to its own default of 3 attempts (the main script's `-MaxRetries` does not reach
it). When every method fails, the SID is marked orphaned
(`SID could not be resolved - marking as orphaned: <sid>` at Debug) and cached for the rest of the
run. An exception in the function itself also marks the SID orphaned (`Error testing SID for
orphaned status <sid> : <message>` at Error level).

A run against a slow or unreachable domain controller therefore reports valid SIDs as orphaned.
Check before acting on results:

```powershell
# Look for lookup failures in the log
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern 'lookup failed for SID|Error testing SID for orphaned status' | Measure-Object

# Re-test a reported SID directly
$sid = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
Get-ADObject -Filter "objectSid -eq '$sid'" -IncludeDeletedObjects
([System.Security.Principal.SecurityIdentifier]$sid).Translate([System.Security.Principal.NTAccount])
```

Never run `-Remove` on results from a run whose log shows lookup failures.

### 4. Errors Inside the Workflow

| Message | Level | Where | Effect |
| --- | --- | --- | --- |
| `Error processing access rule for <DN> : <message>` | Warning | `Find-OrphanedSIDsInObject` | That rule is skipped; `ErrorsEncountered` incremented; other rules continue |
| `Error testing access rule for orphaned SID on <DN> : <message>` | Warning | `Test-AccessRuleForOrphanedSID` | Rule skipped |
| `Error in orchestrated processing for object <DN> : <message>` | Error | `Find-OrphanedSIDsInObject` | Results collected so far for that object are returned |
| `Unexpected error retrieving access rules for <DN>: <message>` | Error | `Get-ObjectAccessRule` | Object skipped |
| `Error processing object <DN>: <message>` then `Retry attempt N of M for object <DN>` | Error / Warning | `Invoke-MainProcessingLogic` | Object retried up to `-MaxRetries` times with 2s, 4s, 6s... back-off; `Max retries (M) exceeded for object <DN>` when exhausted |

Errors never abort the run; the next object is processed. `Processing errors: N` in the summary is
the count of main-loop exceptions.

### 5. Resource Clean-up

Results are streamed to `$env:TEMP\Find-UnknownSID-<CorrelationId>\batch_<n>.json` by
`StreamingResultsManager` (`BatchSize` results per file, default 50) and the folder is removed when the script's `finally`
block disposes it. Pass `-PreserveTempFiles` to keep the folder for inspection; the log then shows
`Temporary result files preserved as requested`. Every 100 objects the main loop calls
`Invoke-Cleanup`, which logs the freed memory at Verbose level
(`Memory usage at N objects: X MB (Freed: Y MB)`).

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -PreserveTempFiles -CorrelationId ($id = [guid]::NewGuid().ToString())
Get-ChildItem -Path (Join-Path $env:TEMP "Find-UnknownSID-$id")
```

If a run was killed before `finally` ran, delete leftover `Find-UnknownSID-*` folders under
`$env:TEMP` by hand. See `.\Troubleshooting\Performance\Memory-Management-Issues.md` for the
memory manager and `.\Troubleshooting\Performance\Memory-WhatIf-Behavior.md` for `-WhatIf` runs.

### 6. SID Lookup Cache

`Test-OrphanedSID` caches each SID's verdict in `$script:SIDValidationCache` for the session.
`Get-SIDValidationCacheStat` returns `TotalEntries`, `OrphanedSIDs`, `ValidSIDs`, `CacheHitRatio`
(cache hits / lookups * 100) and `LastUpdated`; `Clear-SIDValidationCache` empties the cache and
resets the counters. Both live in `Private\SID\Test-OrphanedSID.ps1` and are reachable only in a
session that dot-sourced that file. In a long diagnostic session, clear the cache after the domain
controller becomes reachable again, otherwise cached `$true` verdicts persist.

## Running the Workflow by Hand

```powershell
Set-Location 'C:\Scripts\Find-UnknownSID'
Import-Module ActiveDirectory
. .\Private\Core\Import-LoggingSystem.ps1
Get-ChildItem .\Classes\*.ps1 | ForEach-Object { . $_.FullName }
'SID\Test-SIDFormat', 'SID\Get-SIDAnalysis', 'Operations\Invoke-OperationWithRetry',
'Logging\Write-ADOperationSecurityLog', 'ActiveDirectory\Invoke-ADOperationWithRetry', 'SID\Test-OrphanedSID',
'Security\Get-SecurityDescriptor', 'SID\Resolve-SIDIdentity', 'SID\New-SIDResult', 'SID\Invoke-SIDProcessing' |
    ForEach-Object { . ".\Private\$_.ps1" }

$object  = Get-ADObject -Identity 'CN=User1,OU=Test,DC=contoso,DC=com' -Properties nTSecurityDescriptor, ObjectClass
$rules   = Get-ObjectAccessRule -ADObject $object -IncludeInherited
"Access rules: $($rules.Count)"
$results = Find-OrphanedSIDsInObject -ADObject $object -IncludeInherited
"Orphaned SIDs: $($results.Count)"
$results | Select-Object ObjectDN, OrphanedSID, LikelySource, Confidence, IsInherited
$results | Get-SIDProcessingStatistics | Select-Object TotalSIDsProcessed, TotalOrphanedSIDsFound, TotalErrorsEncountered, AverageProcessingTimeMS
Get-SIDValidationCacheStat
```

## Related Documentation

- `.\Troubleshooting\Common\Security-Descriptor-Warnings.md`
- `.\Troubleshooting\Common\Result-Creation-Issues.md`
- `.\Troubleshooting\Security\Security-Descriptor-Issues.md`
- `.\Troubleshooting\Security\Identity-Resolution-Issues.md`
- `.\Troubleshooting\Security\Orphaned-SID-Issues.md`
- `.\Troubleshooting\Performance\Memory-Management-Issues.md`

## Support Information

- **Module**: `Private\SID\Invoke-SIDProcessing.ps1`
- **Functions**: `Find-OrphanedSIDsInObject`, `Get-SIDProcessingStatistics`
- **Correlation ID**: include the run's `-CorrelationId` in support requests
