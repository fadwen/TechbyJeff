# Performance Tuning Guide - Find-UnknownSID

## Overview

`Find-UnknownSID.ps1` processes Active Directory objects sequentially: one `Get-ADObject` query per
search base, then for each object one security descriptor read and one or more directory lookups
per distinct SID. There is no parallel processing and no connection pooling, so run time is
dominated by the number of objects, the number of access control entries per object, the number
of distinct SIDs, and domain controller latency. This guide lists the levers that exist and how to
measure their effect.

## Where the Time Goes

| Phase | Code | Cost driver |
|---|---|---|
| Object discovery | `Get-ADObjectFromSearchBase` requesting `nTSecurityDescriptor` | Objects under each search base |
| ACL retrieval | `Get-ObjectAccessRule`: `Get-Acl -Path AD:\<DN>`, falling back to the binary descriptor, then a fresh `Get-ADObject` | One call per object; inherited ACEs multiply the entries to inspect |
| SID resolution | `Test-OrphanedSID`: `Get-ADObject` by `objectSid`, deleted-object lookup, `SecurityIdentifier.Translate`, then `Get-ADUser`/`Get-ADGroup`/`Get-ADComputer` | One round of lookups per distinct SID; results are cached per SID for the run |
| Retries | `Invoke-OperationWithRetry` for AD calls, per-object retry loop in `Invoke-MainProcessingLogic` | Transient failures multiply wall time through back-off sleeps |
| Memory management | `Invoke-MemoryCheck` per object, `Invoke-Cleanup` every 100 objects | Fixed overhead; three forced collections per cleanup |
| Export | `StreamingResultsManager.ExportToCsv` | Reads every batch file back before `Export-Csv` |

An orphaned SID costs the most: every lookup method fails before it is declared orphaned. A valid
SID usually returns on the first `Get-ADObject`. The validation cache means each distinct SID pays
this once per run.

## Tuning Levers

### -MaxMemoryUsageMB

Range 100-16384, default 1024. This is the working-set threshold at which `MemoryManager` forces
garbage collection. Set it high enough that the threshold is not crossed during normal processing;
each forced collection pauses the run.

```powershell
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -MaxMemoryUsageMB 4096
```

See [Memory-Management.md](./Memory-Management.md) for the behaviour behind the threshold.

### MemoryCheckInterval (configuration key)

Number of objects between working-set checks. Default 50; `-ConfigPath` JSON accepts 1-100. A
larger interval means fewer `Get-Process` calls; a smaller one catches growth earlier. The
difference is small either way because a check costs a few milliseconds.

```powershell
@{ MemoryCheckInterval = 100 } | ConvertTo-Json | Set-Content .\config.json
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -ConfigPath .\config.json
```

### BatchSize (configuration key)

`BatchSize` (1-1000, default 50) is the number of results `StreamingResultsManager` holds in
memory before writing a batch file to `<TEMP>\Find-UnknownSID-<CorrelationId>\`. A larger value
means fewer, larger writes and a slightly higher working set; a smaller value flushes more often.
The effect is small either way because each result is a few hundred bytes. Change it only when the
log shows memory warnings on a host with very little RAM (lower it) or when the temp folder fills
with thousands of tiny files on a very large OU (raise it).

```powershell
@{ BatchSize = 200 } | ConvertTo-Json | Set-Content .\config.json
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -ConfigPath .\config.json
```

### -MaxRetries

Range 1-10, default 3. Two retry layers use it:

- `Invoke-OperationWithRetry` wraps AD cmdlet calls. It retries only errors matching its
  retryable-error pattern, sleeping `2^(attempt-1)` seconds plus up to 1 second of jitter, capped
  at 30 seconds, between attempts.
- `Invoke-MainProcessingLogic` retries a whole object after a processing error, sleeping
  `2 * attempt` seconds between attempts.

On a healthy domain controller retries never fire and the value is irrelevant. On a flaky link,
lower it to fail fast and re-run the affected search base, or raise it to ride out short outages
at the cost of long pauses.

### -LogLevel

File logging honours `-LogLevel`; console output does not. `Debug` and `Verbose` write several
lines per access rule and per SID lookup, which on a large domain means hundreds of megabytes of
log and measurable I/O. Use `Information` (the default) or `Warning` for production runs and reserve
`Debug` for reproducing a specific object. Security audit entries are written regardless of level.

```powershell
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -LogLevel Warning
```

`-SuppressConsoleOutput` removes console writes for scheduled runs; file logging is unaffected.

### -IncludeInherited

By default only explicit ACEs are inspected. `-IncludeInherited` includes inherited entries, which
on a deep OU tree can multiply the ACEs per object several times over and surfaces the same
inherited orphan on every descendant. Use it for a full audit; omit it for routine hygiene scans.

### Splitting the search base

`-SearchBase` accepts an array and pipeline input. Separate runs per OU keep each process short,
bound the CSV export size, and let a failed OU be re-run alone:

```powershell
$searchBases = @(
    "OU=Users,DC=contoso,DC=com"
    "OU=Computers,DC=contoso,DC=com"
    "OU=Groups,DC=contoso,DC=com"
)

foreach ($base in $searchBases) {
    $name = ($base -split ',')[0] -replace '^OU=', ''
    .\Find-UnknownSID.ps1 -SearchBase $base -OutputPath ".\Reports\$name.csv" -MaxMemoryUsageMB 2048 -LogLevel Warning
}
```

Each run starts a fresh SID validation cache, so an orphaned SID that appears under several OUs is
re-resolved once per run. For domains where the same few orphans are everywhere, a single run
over the parent container is faster.

### -PreserveTempFiles

Keeps `<TEMP>\Find-UnknownSID-<CorrelationId>\batch_N.json` after the run. Use it to inspect
intermediate results without re-running, or to recover results when the CSV export failed:

```powershell
.\Find-UnknownSID.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -PreserveTempFiles -CorrelationId 'perf-01'
$dir = Join-Path ([System.IO.Path]::GetTempPath()) 'Find-UnknownSID-perf-01'
Get-ChildItem $dir -Filter 'batch_*.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json } |
    Export-Csv .\recovered.csv -NoTypeInformation
```

Remove the folder when done; it contains object DNs and SIDs.

## Measuring a Run

The script writes nothing to the pipeline. Its metrics are in the processing summary at the end of
the log and on the console:

```text
=== PROCESSING SUMMARY ===
Total objects processed: 4812
Processing duration: 00:06:41.208
Processing rate: 12.0 objects/second
Peak memory usage: 611 MB
```

To time a run and extract those lines:

```powershell
$correlationId = [guid]::NewGuid().ToString()
$elapsed = Measure-Command {
    .\Find-UnknownSID.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -CorrelationId $correlationId -LogLevel Information
}
"Wall time: $($elapsed.TotalSeconds) s"

# Log files are named by timestamp, not by correlation ID; take the newest
$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1
Select-String -Path $log.FullName -Pattern 'Total objects processed|Processing duration|Processing rate|Peak memory usage|Orphaned SIDs found'
```

Progress lines `Processing: N/M objects (P%) - Orphaned SIDs found: K` are written every 50
objects; the gap between their timestamps gives the throughput for that segment.

### Comparing settings

Run the same search base with two settings on a quiet domain controller and compare `Processing
duration`. Only change one lever at a time. The levers with a visible effect on wall time are
`-IncludeInherited`, `-LogLevel Debug`/`Verbose`, and `-MaxRetries` when the link is unreliable.
`-MaxMemoryUsageMB` matters only when the threshold is being crossed; `MemoryCheckInterval` is
noise.

## Diagnosing Slow Runs

| Observation | Likely cause | Action |
|---|---|---|
| Progress lines far apart, CPU idle | Domain controller or network latency on per-SID lookups | Run on or near a DC; check `Test-NetConnection <dc> -Port 389` |
| `Retry attempt N of M for object ...` warnings | Transient AD errors | Check DC health; lower `-MaxRetries` to fail fast |
| `Memory usage threshold exceeded` warnings | Threshold too low for the session | Raise `-MaxMemoryUsageMB` |
| Rate collapses when `-IncludeInherited` is set | Inherited ACEs multiply entries | Drop the switch unless a full audit is required |
| Long pause after `Completed <searchbase>` | CSV export reading all batch files | Split the search base; smaller exports |
| Log file in the hundreds of MB | `-LogLevel Debug` or `Verbose` | Use `Information` or `Warning` |

## Related Documentation

- [Memory Management](./Memory-Management.md)
- [Memory Management Issues](./Memory-Management-Issues.md)
- [Memory WhatIf Behavior](./Memory-WhatIf-Behavior.md)
- [Find-UnknownSID Issues](../Common/Find-UnknownSID-Issues.md)
- [Enterprise Integration Guide](../Integration/Enterprise-Integration-Guide.md)
