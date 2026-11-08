# Security Logging Troubleshooting Guide

## Overview

`Find-UnknownSID.ps1` writes two kinds of entries to the same log file
(`.\Logs\Find-UnknownSID_<yyyyMMdd_HHmmss>.log` by default, or `-LogPath`):

| Kind | Written by | File format | Filtered by `-LogLevel`? |
|---|---|---|---|
| Regular | `Write-StructuredLog` -> `Write-StructuredLogEntry` | `[timestamp] [Level] [Component] [CorrelationId] Message` | Yes (file only; console is not filtered) |
| Security audit | `Write-SecurityLog`, `Write-ADOperationSecurityLog`, `Write-RemovalSecurityLog` -> `Write-SecurityStructuredLogEntry` | One compressed JSON object per line, `Component` is `SecurityAudit` | No; always written |

A security entry looks like:

```json
{"Timestamp":"2025-07-02T14:30:52.118+02:00","Level":"Information","Component":"SecurityAudit","CorrelationId":"<guid>","Message":"[ObjectAccess] [Success] Successfully completed Active Directory operation: AD-ObjectDiscovery","SecurityEventType":"ObjectAccess","Outcome":"Success","UserContext":"user@HOST", ...}
```

The `Message` is `[<SecurityEventType>] [<Outcome>] <text>`. `Outcome` `Attempt` and `Success`
are written at `Information`, `Failure` at `Warning`. On the console only `Warning`, `Error` and
`Critical` security entries appear, prefixed `[SECURITY]`; `Information` security entries go to the
file only.

The logging modules live in `Private\Logging\` and are loaded by
`Private\Core\Import-LoggingSystem.ps1`.

## Reading Security Entries

Because security entries are JSON lines, filter them by parsing rather than by bracket matching:

```powershell
function Get-SecurityLogEntry {
    param([Parameter(Mandatory)][string]$LogPath)
    Get-Content -Path $LogPath |
        Where-Object { $_.StartsWith('{') } |
        ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
        Where-Object { $_.Component -eq 'SecurityAudit' }
}

$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1
$security = Get-SecurityLogEntry -LogPath $log.FullName
$security | Group-Object SecurityEventType, Outcome | Select-Object Name, Count
$security | Where-Object Outcome -eq 'Failure' | Select-Object Timestamp, Message
```

Regular entries are the lines that do not start with `{`:

```powershell
$regular = Get-Content $log.FullName | Where-Object { -not $_.StartsWith('{') }
$regular | Where-Object { $_ -match '^\[[^\]]+\] \[Information\]' } | Measure-Object
```

## Common Issues

### Issue 1: Security entries missing from the file

**Symptoms**

- `[SECURITY]` warnings on the console but no JSON lines in the log file.
- Warnings `Security log written to emergency file: ...` or
  `Security log written to emergency location: ...`.

**Diagnosis**

```powershell
# In a session where the script's modules are loaded
Get-Command Write-SecurityStructuredLogEntry -ErrorAction SilentlyContinue

$state = Get-LoggingSystemState
"Log path: $($state.LogPath)"
"Initialized: $($state.LogFileInitialized)"
```

`Write-SecurityFileEntry` writes to `$state.LogPath` only when `LogFileInitialized` is true;
otherwise it falls back to `Write-SecurityFileEntryDirect`.

**Solutions**

1. Load the logging system from its real location when working interactively:

   ```powershell
   . .\Private\Core\Import-LoggingSystem.ps1
   Initialize-LoggingSystem -CorrelationId ([guid]::NewGuid().ToString()) -LogLevel Information
   Initialize-LogDirectory -LogPath .\Logs\manual-test.log
   ```

2. Check that the log directory is writable:

   ```powershell
   $logDir = Split-Path $state.LogPath -Parent
   Test-Path $logDir -PathType Container
   [IO.File]::OpenWrite((Join-Path $logDir 'write-test.tmp')).Dispose(); Remove-Item (Join-Path $logDir 'write-test.tmp')
   ```

3. Look for emergency files; see Issue 4.

### Issue 2: Security entries thought to be filtered by -LogLevel

**Symptoms**

- A run with `-LogLevel Warning` or `Error` shows no `Information` security entries.

**Root cause**

Normally this is a reading problem, not a filtering one: `Information` security entries are in the
file as JSON lines and are invisible to a search for `[Information]`. Use the parsing approach
above. Only entries routed through `Write-StructuredLogEntry` are filtered, so a component that
logs security-relevant text with `Write-StructuredLog` instead of a security function will be
filtered.

**Verification**

```powershell
. .\Private\Core\Import-LoggingSystem.ps1
Initialize-LoggingSystem -CorrelationId ([guid]::NewGuid().ToString()) -LogLevel Error
Initialize-LogDirectory -LogPath .\Logs\filter-test.log

Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Compliance test entry' -Outcome 'Success'
Write-StructuredLogEntry -Message 'Regular test entry' -Level Information -Component 'Test'

$logPath = (Get-LoggingSystemState).LogPath
$lines = Get-Content $logPath
"Security entries (expect 1): " + @($lines | Where-Object { $_.StartsWith('{') -and $_ -match '"Component":"SecurityAudit"' }).Count
"Regular Information entries (expect 0): " + @($lines | Where-Object { $_ -match '\[Information\] \[Test\]' }).Count
```

### Issue 3: Security logging overhead

**Symptoms**

- Slower runs when many objects contain orphaned SIDs.

**Diagnosis**

```powershell
$metrics = $script:SecurityLoggingMetrics
"Total security entries: $($metrics.TotalSecurityEntries)"
"By level: $($metrics.SecurityEntriesByLevel | ConvertTo-Json -Compress)"
"Last entry: $($metrics.LastSecurityLogTime)"
```

**What is logged**

`Invoke-MainProcessingLogic` writes an `AD-ObjectDiscovery` attempt/success pair per search base,
an `OrphanedSID-Detection` entry per object with findings, and an `OrphanedSID-Removal`
attempt/success (or failure) pair per SID removed. `Test-SIDSecurity` writes a `DataValidation`
entry per SID validated. These counts are proportional to findings, not to objects scanned; on a
clean domain the security log is small. The entries cannot be suppressed; they are the audit trail.

### Issue 4: Emergency security logs in the temp directory

**Symptoms**

- Files matching `$env:TEMP\Find-UnknownSID-Security-*.log`:
  - `Find-UnknownSID-Security-Emergency.log`: written when formatting or the direct write threw.
  - `Find-UnknownSID-Security-<yyyyMMdd>.log`: written when the main log path was unavailable.
  - `Find-UnknownSID-Security-Fallback.log`: written by `Write-SecurityLog` when
    `Write-SecurityStructuredLogEntry` itself failed.

**Root cause**

The main log file could not be written: directory missing, permissions, disk full, or the logging
system not initialised when the security function ran.

**Diagnosis**

```powershell
$state = Get-LoggingSystemState
"Main log path: $($state.LogPath)"
"File exists: $(Test-Path $state.LogPath)"
Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime
```

**Solutions**

```powershell
# Recreate the log directory
$logDir = Split-Path $state.LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# Merge emergency entries into the main log and remove them
Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log" -ErrorAction SilentlyContinue | ForEach-Object {
    Add-Content -Path $state.LogPath -Value (Get-Content $_.FullName) -Encoding UTF8
    Remove-Item $_.FullName
}
```

Emergency entries use a plain-text form
(`<timestamp> [SECURITY-EMERGENCY] [<Level>] <message> (CorrelationId: <id>)`), so after merging
they will not parse as JSON; keep that in mind when reporting.

### Issue 5: Entries without a correlation ID or context

**Symptoms**

- Security entries whose `CorrelationId` differs from the run's.

**Root cause**

`Write-SecurityLog` generates a new GUID when none is passed. All call sites in the script pass the
run's ID, so a mismatch indicates a manual call or a helper invoked outside the script.

**Solution**

Always pass the ID and a context hashtable:

```powershell
$correlationId = [guid]::NewGuid().ToString()
Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Manual check' -Outcome 'Success' -CorrelationId $correlationId -SecurityContext @{
    OperationType = 'ManualReview'
    SearchBase    = 'OU=Users,DC=contoso,DC=com'
}
```

Context keys are stored in the JSON object prefixed `Security_`.

## Validation Procedures

### Confirm security entries survive a restrictive log level

```powershell
.\Find-UnknownSID.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -LogLevel Error -WhatIf

$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1
$security = Get-Content $log.FullName | Where-Object { $_.StartsWith('{') -and $_ -match '"Component":"SecurityAudit"' }
if ($security.Count -gt 0) {
    "Security logging verified: $($security.Count) entries"
} else {
    Write-Warning "No security entries found in $($log.FullName)"
}
```

### Monitor for emergency logging

```powershell
function Test-EmergencySecurityLogs {
    $files = Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log" -ErrorAction SilentlyContinue
    if ($files) {
        Write-Warning "Emergency security logs present - the main log was unavailable at some point"
        $files | Select-Object FullName, Length, LastWriteTime
        return $false
    }
    return $true
}
```

### Check recent security activity in a log

```powershell
function Test-SecurityLoggingHealth {
    param([Parameter(Mandatory)][string]$LogPath, [int]$WithinMinutes = 60)
    $since = (Get-Date).AddMinutes(-$WithinMinutes)
    $recent = Get-SecurityLogEntry -LogPath $LogPath | Where-Object { [datetime]$_.Timestamp -gt $since }
    if (-not $recent) {
        Write-Warning "No security entries in the last $WithinMinutes minutes"
        return $false
    }
    return $true
}
```

## Related Documentation

- [Security Validation Guide](./Security-Validation-Guide.md)
- [Find-UnknownSID Issues](../Common/Find-UnknownSID-Issues.md)
- [Enterprise Integration Guide](../Integration/Enterprise-Integration-Guide.md)
