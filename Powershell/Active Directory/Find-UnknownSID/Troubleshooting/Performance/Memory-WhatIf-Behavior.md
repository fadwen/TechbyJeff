# Memory Management WhatIf Behavior

## Overview

`-WhatIf` previews the changes a run would make to Active Directory. The memory management
functions deliberately do not treat `-WhatIf` as a reason to skip work: a preview of a 50,000
object domain allocates as much as a real run, so the memory manager, the periodic cleanup and the
final disposal all execute regardless. Only their logging goes through `ShouldProcess`.

## Design Principle

In `Private\System\*.ps1`, `ShouldProcess` guards the log statements, not the operation:

```powershell
if ($PSCmdlet.ShouldProcess("Memory", "Perform cleanup")) {
    Write-StructuredLog "Starting memory cleanup operation..." -Level Information ...
} else {
    Write-Verbose "WhatIf: Would perform memory cleanup"
}

# Executes in both modes
[System.GC]::AddMemoryPressure(50MB)
...
```

- **Always execute**: memory manager creation, memory checks, `Invoke-Cleanup` garbage
  collection, resource disposal, final collection.
- **Respect -WhatIf**: Information and Debug log lines, which are replaced by `WhatIf: Would ...`
  verbose lines.

## Functions Affected

### `Initialize-MemoryManager`

```powershell
Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -WhatIf
```

Creates and returns the `MemoryManager` instance. Under `-WhatIf` it logs
`WhatIf: Would initialize memory manager with threshold 1024 MB` (verbose) and
`Memory manager created for WhatIf simulation` (debug) instead of the normal initialisation lines.

### `Invoke-MemoryCheck`

```powershell
Invoke-MemoryCheck -MemoryManager $manager -WhatIf
```

Calls `$MemoryManager.CheckMemoryUsage()` and returns the status object in both modes. The
returned object's `WhatIfMode` property reflects `$WhatIfPreference`. The check itself only
measures when the manager's internal counter reaches `CheckInterval`; pass `-Force` to measure on
this call.

### `Invoke-Cleanup`

```powershell
Invoke-Cleanup -CorrelationId $id -WhatIf
```

Runs the full three-cycle collection with memory pressure in both modes and returns a
`MemoryCleanupResult` whose `WhatIfMode` is `$true` under `-WhatIf`. Under `-WhatIf` the log shows
`WhatIf: Would perform memory cleanup` (verbose) and
`WhatIf simulation: memory cleanup would be performed` (debug) in place of
`Starting memory cleanup operation...` and `Memory after cleanup: N MB (Freed: M MB)`.

### `Invoke-ResourceCleanup`

```powershell
Invoke-ResourceCleanup -MemoryManager $manager -WhatIf
```

Disposes `AdditionalResources`, disposes the memory manager and runs the final collection in both
modes. Under `-WhatIf` the log shows `WhatIf: Would dispose and cleanup resources` (verbose) and
`WhatIf simulation: resource disposal would be performed` (debug).

### Functions that do honour -WhatIf

- `Invoke-GarbageCollection` (same file as `Invoke-Cleanup`) is a targeted helper that is not
  called by the main processing loop. Under `-WhatIf` it skips the collection, logs
  `WhatIf: Would perform garbage collection`, and returns `MemoryAfter` equal to `MemoryBefore`
  with `WhatIfMode = $true`.
- `StreamingResultsManager` in WhatIf mode creates no temp directory and writes no batch files; it
  still clears each batch from memory and collects, so memory behaviour matches a real run.

## Verification

Load the helpers into a session (see
[Memory-Management-Issues.md](./Memory-Management-Issues.md#validation-commands) for the
dot-source list), then:

```powershell
# Manager is created despite -WhatIf
$manager = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 10 -WhatIf
$null -ne $manager                      # True

# Cleanup runs despite -WhatIf
$result = Invoke-Cleanup -WhatIf -Verbose
$result.WhatIfMode                      # True
$result.GCCycles                        # 3

# Disposal runs despite -WhatIf
Invoke-ResourceCleanup -MemoryManager $manager -WhatIf
$manager.Disposed                       # True
```

Comparing `[System.GC]::GetTotalMemory($false)` before and after `Invoke-Cleanup -WhatIf` on an
idle session proves little, because there may be nothing to reclaim; the `Disposed` flag and the
`GCCycles` count are the reliable indicators.

## Log Analysis

Lines that prove the operations executed, regardless of mode (Debug lines need `-LogLevel Debug`):

```text
Garbage collection completed (3 cycles)
Memory manager disposed successfully
Final garbage collection completed
```

Lines that appear only under `-WhatIf` (verbose stream, so pass `-Verbose`):

```text
WhatIf: Would initialize memory manager with threshold 1024 MB
WhatIf: Would check memory usage and cleanup if needed
WhatIf: Would perform memory cleanup
WhatIf: Would dispose and cleanup resources
WhatIf: Would create temporary directory: <TEMP>\Find-UnknownSID-<CorrelationId>
WhatIf: Would flush batch 1 with 50 results to <TEMP>\Find-UnknownSID-<CorrelationId>\batch_1.json
```

## Troubleshooting

**Memory still climbs with -WhatIf.** Expected: the preview performs the full discovery, including
every `Get-Acl` and every SID lookup, and only skips the ACL writes. Tune `-MaxMemoryUsageMB` and
the search base as for a real run.

**Verbose output is noisy under -WhatIf.** Expected: each guarded log statement is replaced by a
`WhatIf: Would ...` verbose line. Drop `-Verbose` to silence them; the operations still run.

**Disposal errors under -WhatIf.** Resource disposal is real in both modes, so a disposal error
points at an actual resource problem (for example a temp directory removed by another process), not
at the simulation.

## Related Documentation

- [Memory Management](./Memory-Management.md)
- [Memory Management Issues](./Memory-Management-Issues.md)
- [Performance Tuning](./Performance-Tuning.md)
