# Orphaned SID Detection Troubleshooting Guide

## Overview

This guide covers `Private\SID\Test-OrphanedSID.ps1`, which decides whether a SID still exists in
Active Directory and caches the answer for the rest of the run.

`Test-OrphanedSID -SID <sid>` returns `$true` (orphaned) or `$false` (exists). It works through
these steps and stops at the first that decides:

1. `Test-SIDFormat`; an invalid format is treated as orphaned (Warning
   `SID format invalid - treating as orphaned: <SID>`).
2. Cache lookup in `$script:SIDValidationCache` (Debug `SID validation cache hit for <SID>`).
3. `Get-ADObject -Filter "objectSid -eq '<SID>'"`; found means not orphaned.
4. The same query with `-IncludeDeletedObjects`; a match in the Deleted Objects container is
   treated as **orphaned** (the account is gone and the ACE should be cleaned).
5. `SecurityIdentifier.Translate([NTAccount])`; a resolved name that is not itself a SID means not
   orphaned.
6. `Get-ADUser`, `Get-ADGroup`, `Get-ADComputer` with `SID -eq '<SID>'`.
7. Otherwise orphaned (Debug `SID could not be resolved - marking as orphaned: <SID>`).

Directory calls go through `Invoke-ADOperationWithRetry`, so transient failures are retried before
a method is considered to have failed. Any unexpected exception marks the SID orphaned for safety
(Error `Error testing SID for orphaned status <SID> : ...`).

The functions are private; load them as shown in
[Identity-Resolution-Issues.md](./Identity-Resolution-Issues.md#loading-the-functions-in-a-session).

## Common Issues

### 1. False positives: valid SIDs marked as orphaned

**Symptoms**

- Existing accounts or groups appear in the results CSV.
- Recently created accounts are reported.
- Service accounts or accounts from a trusted domain are reported.

**Causes**

- Replication lag: the object exists on one domain controller but not on the one answering.
- The running account lacks read permission on the object, so every lookup fails.
- The SID belongs to a trusted domain; `Get-ADObject` queries the local domain only, and
  translation may fail across a one-way trust.
- A cached `$true` from an earlier lookup in the same run.

**Solutions**

```powershell
# Clear the cache and retry one SID
Clear-SIDValidationCache
$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"
Test-OrphanedSID -SID $testSID -Verbose

# Test 1: direct AD lookup
try {
    $adObject = Get-ADObject -Filter "objectSid -eq '$testSID'" -ErrorAction Stop
    "Found AD object: $($adObject.DistinguishedName)"
} catch {
    "AD object not found: $($_.Exception.Message)"
}

# Test 2: SecurityIdentifier translation
try {
    $account = [System.Security.Principal.SecurityIdentifier]::new($testSID).Translate([System.Security.Principal.NTAccount])
    "Account name: $($account.Value)"
} catch {
    "Translation failed: $($_.Exception.Message)"
}

# Test 3: typed lookups
foreach ($cmdlet in 'Get-ADUser', 'Get-ADGroup', 'Get-ADComputer') {
    try {
        $result = & $cmdlet -Filter "SID -eq '$testSID'" -ErrorAction Stop
        if ($result) { "$cmdlet found: $($result.DistinguishedName)" }
    } catch {
        "$cmdlet failed: $($_.Exception.Message)"
    }
}
```

For a foreign SID, resolve it against its own domain:

```powershell
Get-ADObject -Server trusted.example.com -Filter "objectSid -eq '$testSID'"
```

**Prevention**

- Run as an account with read access to every object in scope.
- Check replication (`repadmin /replsummary`) before a large run.
- Always run `-WhatIf` and review the CSV before `-Remove`.

### 2. False negatives: orphaned SIDs marked as valid

**Symptoms**

- A SID known to be deleted is not reported.

**Causes**

- A cached `$false` from an earlier lookup in the same run (the cache does not expire).
- The SID resolves through a trust, so `Translate` succeeds although no local object exists.

Deleted objects are not a cause: an object found in the Deleted Objects container is treated as
orphaned.

**Solutions**

```powershell
Clear-SIDValidationCache

$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"
try {
    $deleted = Get-ADObject -Filter "objectSid -eq '$testSID'" -IncludeDeletedObjects -ErrorAction Stop
    if ($deleted) { "In deleted objects: $($deleted.DistinguishedName)" }
} catch {
    "Not in deleted objects: $($_.Exception.Message)"
}

# Which method is accepting the SID?
try {
    [System.Security.Principal.SecurityIdentifier]::new($testSID).Translate([System.Security.Principal.NTAccount]).Value
} catch {
    "Translate failed: $($_.Exception.Message)"
}
```

Disabled accounts are not orphaned; the script reports only SIDs with no object.

### 3. Performance problems

**Symptoms**

- Slow progress once discovery has finished.
- Many `Retry attempt` warnings.

**Causes**

- Each distinct SID costs up to six directory operations when it is orphaned.
- Domain controller latency or load.
- Retries after transient errors (see `-MaxRetries` in
  [Performance-Tuning.md](../Performance/Performance-Tuning.md)).

**Solutions**

```powershell
# Cache effectiveness for the current session
$stats = Get-SIDValidationCacheStat
"Entries: $($stats.TotalEntries)  Orphaned: $($stats.OrphanedSIDs)  Valid: $($stats.ValidSIDs)  Hit ratio: $($stats.CacheHitRatio)%"

# Time cached versus uncached lookups
$testSIDs = 1000..1099 | ForEach-Object { "S-1-5-21-1234567890-1234567890-1234567890-$_" }
Clear-SIDValidationCache
(Measure-Command { $testSIDs | Test-OrphanedSID }).TotalSeconds   # uncached
(Measure-Command { $testSIDs | Test-OrphanedSID }).TotalSeconds   # cached
```

`CacheHitRatio` is cache hits divided by lookups, as a percentage, since the cache was last
cleared. During a real run the ratio rises with the number of objects that share principals; a
ratio near zero on a large OU means almost every ACE names a different SID and the run is bound by
directory latency.

### 4. Active Directory connection problems

**Symptoms**

- `Unable to contact the server` or authentication errors.
- Every SID marked orphaned.

**Solutions**

```powershell
try {
    $domain = Get-ADDomain -Current LocalComputer
    "Connected to $($domain.DNSRoot); PDC: $($domain.PDCEmulator)"
} catch {
    "AD connection failed: $($_.Exception.Message)"
}

$dc = (Get-ADDomain).PDCEmulator
Test-NetConnection -ComputerName $dc -Port 389    # LDAP
Test-NetConnection -ComputerName $dc -Port 636    # LDAPS
Test-NetConnection -ComputerName $dc -Port 3268   # Global Catalog
```

Do not run `-Remove` while connectivity is uncertain: a run that cannot reach the directory marks
SIDs orphaned on error.

## Cache Management

The cache is `$script:SIDValidationCache`, a hashtable of SID to boolean (`$true` = orphaned). It
lives for the PowerShell session or process, grows by one entry per distinct SID tested, and is
cleared only by `Clear-SIDValidationCache`, which also resets the hit and lookup counters.

```powershell
$stats = Get-SIDValidationCacheStat
if ($stats.TotalEntries -gt 10000) {
    Clear-SIDValidationCache
}

# Direct inspection
$script:SIDValidationCache.Count
($script:SIDValidationCache.Values | Where-Object { $_ }).Count        # orphaned
($script:SIDValidationCache.Values | Where-Object { -not $_ }).Count   # valid
```

Entries have no timestamp; clear the cache if the directory changed during a long interactive
session. The main script creates a fresh cache every time it is invoked as a new process.

## Error Messages

| Message | Level | Meaning |
|---|---|---|
| `SID format invalid - treating as orphaned: <SID>` | Warning | Failed `Test-SIDFormat`; reported as orphaned |
| `SID validation cache hit for <SID>` | Debug | Answer returned from cache |
| `SID found in AD via Get-ADObject: <DN>` | Debug | Not orphaned |
| `SID found in deleted objects: <DN> - treating as orphaned` | Debug | Tombstoned object; orphaned |
| `SID could not be translated - likely orphaned: <SID>` | Debug | Translation step failed; later steps still run |
| `SID could not be resolved - marking as orphaned: <SID>` | Debug | Every method failed |
| `Error testing SID for orphaned status <SID> : <error>` | Error | Unexpected exception; marked orphaned |
| `Cleared SID validation cache (N entries)` | Information | `Clear-SIDValidationCache` ran |

Debug lines appear in the log file only with `-LogLevel Debug`.

## Diagnostics

```powershell
# Trace one SID with its own correlation ID
$correlationId = [guid]::NewGuid().ToString()
Test-OrphanedSID -SID "S-1-5-21-1234567890-1234567890-1234567890-1001" -CorrelationId $correlationId -Verbose

# Then search the log for that ID
$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1
Select-String -Path $log.FullName -Pattern $correlationId
```

## Best Practices

- Review `-WhatIf` output before any `-Remove` run; a SID marked orphaned because of an error is
  indistinguishable from a real orphan in the CSV.
- Run from a host close to a domain controller; per-SID latency dominates run time.
- In an interactive session, clear the cache between runs against different domains.
- Use correlation IDs to tie a reported SID back to the exact lookup sequence in the log.

## Related Documentation

- [Identity Resolution Issues](./Identity-Resolution-Issues.md)
- [SID Format Issues](./SID-Format-Issues.md)
- [SID Analysis Issues](./SID-Analysis-Issues.md)
- [Performance Tuning](../Performance/Performance-Tuning.md)
- [Find-UnknownSID Issues](../Common/Find-UnknownSID-Issues.md)
