# Find-UnknownSID Common Issues Troubleshooting Guide

## Overview

This guide covers the issues most often reported when running `Find-UnknownSID.ps1`, with the
exact messages the script emits and fixes that use its real parameters.

The script accepts: `-SearchBase` (string array, also from the pipeline, alias `DistinguishedName`),
`-OutputPath`, `-IncludeInherited`, `-Remove`, `-Restore`, `-BackupPath`, `-MaxRetries` (1-10,
default 3), `-ConfigPath`, `-MaxMemoryUsageMB` (100-16384, default 1024), `-PreserveTempFiles`,
`-LogPath`, `-CorrelationId`, `-LogLevel` (`Critical`, `Error`, `Warning`, `Information`, `Debug`,
`Verbose`; default `Information`), `-SuppressConsoleOutput`, `-Force`, `-WhatIf` and `-Confirm`.
There is no `-Credential`; the script runs as the current user.

The script writes nothing to the pipeline. Results reach disk only through `-OutputPath` (always
CSV) and the log file.

## Critical Issues (Immediate Resolution Required)

### 1. Script Fails to Start

#### Issue: "Active Directory PowerShell module is not available"

**Symptoms:**

- The script terminates in the `begin` block before any object is processed.
- Console shows `Script initialization failed: Active Directory PowerShell module is not available`.

**Root Cause:** the `ActiveDirectory` module is not installed, or is not visible to the PowerShell
edition in use.

**Resolution:**

```powershell
# Windows 10/11 and Server with Desktop Experience
Enable-WindowsOptionalFeature -Online -FeatureName RSATClient-Roles-AD-Powershell

# Windows Server Core
Add-WindowsFeature RSAT-AD-PowerShell

# Verify from the same PowerShell edition that will run the script
Get-Module -ListAvailable -Name ActiveDirectory
```

#### Issue: "Critical class import failure"

**Symptoms:**

- `Secure class loading failed: Class validation failed. Failed classes: N` followed by
  `Script initialization failed: Critical class import failure`.
- Occurs after `Loading security-validated components...` and before any AD query.

**Root Cause:** a file under `Classes\` is missing, unreadable, or its content no longer matches the
hash recorded by `Import-SecureClasses`. The nine required classes are `MemoryManager`,
`OrphanedSIDResult`, `ProcessingStatistics`, `RemovalOperationResult`, `RestoreOperationResult`,
`ScriptConfiguration`, `SecurityValidationResult`, `SIDAnalysisResult` and `StreamingResultsManager`.

**Resolution:**

```powershell
# Confirm every class file is present and readable
$scriptRoot = 'C:\Scripts\Find-UnknownSID'   # folder that holds Find-UnknownSID.ps1
$required = 'MemoryManager', 'OrphanedSIDResult', 'ProcessingStatistics', 'RemovalOperationResult',
    'RestoreOperationResult', 'ScriptConfiguration', 'SecurityValidationResult', 'SIDAnalysisResult',
    'StreamingResultsManager'
foreach ($name in $required) {
    $path = Join-Path $scriptRoot "Classes\$name.ps1"
    if (Test-Path $path) { "Found   $name" } else { "Missing $name" }
}

# Re-run with Debug logging to see which class failed validation and why
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -LogLevel Debug -WhatIf
```

If a class file was edited locally, restore it from source control. Hash validation is described in
`.\Documentation\Class-Loading-Security-Analysis.md`.

#### Issue: "Missing critical dependency" or "Module file not found"

**Symptoms:**

- `ClassManagement function not found: <path>` then `Missing critical dependency: <file>.ps1`.
- `Modular logging system not found: <path>\Private\Core\Import-LoggingSystem.ps1`.
- `WARNING: Module file not found: <path>` for a file under `Private\`.

**Root Cause:** the `Private\` tree was copied incompletely. The script dot-sources one function per
file from `Private\<Area>\*.ps1`; a missing `ClassManagement` or `Core` file stops the run, a
missing file elsewhere is warned about and the dependent command later fails with
"is not recognized".

**Resolution:** redeploy the whole folder. Verify with:

```powershell
Get-ChildItem -Path .\Private -Recurse -Filter *.ps1 | Measure-Object
```

### 2. Authentication and Authorization Failures

#### Issue: "Access denied" during AD operations

**Symptoms:**

- `WARNING: Failed to retrieve objects from search base '<DN>': Insufficient access rights ...`
  during discovery.
- Repeated `All security descriptor retrieval methods failed for <DN>` warnings (see
  `.\Troubleshooting\Common\Security-Descriptor-Warnings.md`).
- With `-Remove`: `Failed to retrieve ACL for <DN>` or Set-Acl access-denied errors.

**Required permissions:**

| Mode | Permission on target objects |
| --- | --- |
| Discovery (default) | Read all properties and Read permissions |
| `-Remove` | Modify permissions (and the backup folder must be writable) |
| `-Restore` | Modify permissions |

**Resolution:**

```powershell
# Confirm the account running the script
whoami
whoami /groups | findstr /i "Domain Admins Account Operators"

# Read test on the search base
Get-ADObject -SearchBase 'OU=Test,DC=contoso,DC=com' -Filter * -ResultSetSize 1 -ErrorAction Stop

# Permission read test on one object
Get-Acl -Path 'AD:\CN=User1,OU=Test,DC=contoso,DC=com' | Select-Object -ExpandProperty Access | Measure-Object
```

#### Issue: "The RPC server is unavailable"

**Symptoms:** intermittent failures on `Get-ADObject` or `Get-Acl`, usually in large runs.

**Resolution:**

```powershell
$dc = (Get-ADDomainController).HostName
Test-NetConnection -ComputerName $dc -Port 389 -InformationLevel Detailed
Resolve-DnsName -Name $dc -Type A

# Raise the retry count for SID lookups and object discovery (default 3, maximum 10)
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -MaxRetries 5
```

`-MaxRetries` governs the per-object retry loop in `Invoke-MainProcessingLogic`: when processing an
object throws, the object is retried up to that many times with a 2, 4, 6... second back-off
(`Retry attempt N of M for object <DN>`). SID lookups and the ACL steps of `-Remove` go through
`Invoke-ADOperationWithRetry`, which has its own fixed default of 3 attempts and retries only
errors matching `timeout|network|connection|busy|unavailable|server not operational|replication|domain controller`.
Object discovery (`Get-ADObject -SearchBase`) and `Get-Acl` are not retried.

### 3. Destructive Modes Refuse to Run

#### Issue: "Refusing to remove orphaned SIDs from ACLs without confirmation"

**Symptoms:** a `-Remove` or `-Restore` run stops immediately after the search base is resolved with
one of:

```text
Refusing to remove orphaned SIDs from ACLs without confirmation. Re-run with -Force to proceed unattended, or with -WhatIf to preview the changes.
Refusing to restore ACLs from backup without confirmation. Re-run with -Force to proceed unattended, or with -WhatIf to preview the changes.
```

**Root Cause:** `-Remove` and `-Restore` require an explicit go-ahead. In an interactive console the
script asks once (`This will remove orphaned SIDs from ACLs for: <search bases>` under the caption
`Confirm destructive operation`); answering No produces the message above. A session that cannot
prompt - a scheduled task, CI agent, or remote host - is treated as a refusal.

**Resolution:**

```powershell
# Preview without any prompt or change
.\Find-UnknownSID.ps1 -Remove -SearchBase 'OU=Test,DC=contoso,DC=com' -WhatIf

# Unattended run - skips the confirmation
.\Find-UnknownSID.ps1 -Remove -SearchBase 'OU=Test,DC=contoso,DC=com' -Force
```

`-WhatIf` never prompts. `-Force` only affects this confirmation; it does not change what is
removed or restored.

## High Priority Issues

### 4. Performance and Memory Issues

#### Issue: Memory warnings or "Out of memory" during processing

**Symptoms:**

- Memory threshold warnings from the memory manager in the log.
- The host process working set grows beyond `-MaxMemoryUsageMB`.

**Resolution:**

```powershell
# Raise the ceiling (100-16384 MB; default 1024)
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -MaxMemoryUsageMB 4096

# Watch the process while it runs (pwsh or powershell depending on host)
Get-Process -Id $PID | Select-Object ProcessName, @{ n = 'WorkingSetMB'; e = { [math]::Round($_.WorkingSet64 / 1MB) } }

# Split a large domain into several runs
$ous = Get-ADOrganizationalUnit -Filter * -SearchScope OneLevel | Select-Object -ExpandProperty DistinguishedName
foreach ($ou in $ous) {
    .\Find-UnknownSID.ps1 -SearchBase $ou -OutputPath ".\Reports\$($ou.Split(',')[0].Substring(3)).csv"
}
```

Objects are processed one at a time; there is no parallel mode and no throttle parameter. Results
are streamed to batch files under `$env:TEMP\Find-UnknownSID-<CorrelationId>\` so result count does
not drive memory use. See `.\Troubleshooting\Performance\Memory-Management-Issues.md` and
`.\Troubleshooting\Performance\Performance-Tuning.md`.

#### Issue: Initialization fails with a MaxMemoryMB validation error

**Symptoms:** `Script initialization failed: Cannot validate argument on parameter 'MaxMemoryMB'`
when `-MaxMemoryUsageMB` is below 256.

**Root Cause:** `-MaxMemoryUsageMB` accepts 100-16384, but `Initialize-MemoryManager` requires
`-MaxMemoryMB` in 256-16384. The same applies to a config `MemoryCheckInterval` below 5, which
`Initialize-MemoryManager -CheckInterval` rejects.

**Resolution:** use 256 or higher for `-MaxMemoryUsageMB`, and 5-100 for `MemoryCheckInterval`.

#### Issue: Script appears to hang

**Symptoms:** no progress line for a long time. Progress is logged every 50 objects as
`Processing: <n>/<total> objects (<pct>%) - Orphaned SIDs found: <k>`.

**Root Cause:** most often a slow domain controller during SID lookups. Each unknown SID can cost
up to five AD queries (`Get-ADObject` by `objectSid`, deleted-objects query, `Get-ADUser`,
`Get-ADGroup`, `Get-ADComputer`), each retried up to 3 times by `Invoke-ADOperationWithRetry`
when the error looks transient.

**Resolution:**

```powershell
# See each lookup as it happens
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -LogLevel Debug

# Bound the run from a wrapper
$job = Start-Job -ScriptBlock { & 'C:\Scripts\Find-UnknownSID\Find-UnknownSID.ps1' -SearchBase 'OU=Test,DC=contoso,DC=com' }
if (-not (Wait-Job -Job $job -Timeout 1800)) {
    Stop-Job -Job $job
    Write-Warning 'Find-UnknownSID did not finish within 30 minutes'
}
Receive-Job -Job $job
```

Lookup results are cached per SID for the run, so repeated SIDs cost one lookup set.

### 5. Configuration and Parameter Issues

#### Issue: "Configuration file not found" or JSON parsing errors

**Symptoms:**

- `Cannot validate argument on parameter 'ConfigPath'. Configuration file not found: <path>`.
- `Script initialization failed: Failed to load configuration from <path> : <message>`.
- Settings in the file appear to be ignored.

**Root Cause:** the path is wrong, the JSON is malformed, or the file uses keys the loader does not
read. `ScriptConfiguration.LoadFromFile` reads only these top-level keys:

| Key | Type | Default | Accepted |
| --- | --- | --- | --- |
| `WellKnownSIDPatterns` | string[] of regex | built-in list | each must compile |
| `ProtectedSIDs` | string[] | built-in list | `^S-1-\d+(-\d+)*$` |
| `BatchSize` | int | 50 | 1-1000; results per streaming batch file |
| `MemoryCheckInterval` | int | 50 | 1-100 (use 5-100; see above) |
| `EnableDetailedLogging` | bool | false | |
| `LogLevel` | string | Information | Critical, Error, Warning, Information, Debug, Verbose |
| `LogFilePath` | string | null | overrides `-LogPath` when set |
| `EnableLogFileRotation` | bool | true | |
| `MaxLogFileSizeMB` | int | 10 | |

Any other key, and any nested object, is ignored without a warning.

**Resolution:**

```powershell
$configPath = '.\config.json'
if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        'Configuration file parses'
        $known = 'WellKnownSIDPatterns', 'ProtectedSIDs', 'BatchSize', 'MemoryCheckInterval',
            'EnableDetailedLogging', 'LogLevel', 'LogFilePath', 'EnableLogFileRotation', 'MaxLogFileSizeMB'
        $config.PSObject.Properties.Name | Where-Object { $_ -notin $known } |
            ForEach-Object { "Ignored key: $_" }
    } catch {
        "Configuration file invalid: $($_.Exception.Message)"
    }
} else {
    "Configuration file not found: $configPath"
}

# Minimal valid file
@{
    BatchSize           = 50
    MemoryCheckInterval = 50
    LogLevel            = 'Information'
    MaxLogFileSizeMB    = 10
} | ConvertTo-Json | Set-Content -Path .\config.json -Encoding UTF8
```

## Medium Priority Issues

### 6. Output and Reporting Issues

#### Issue: No CSV is produced, or the CSV is empty

**Symptoms:**

- `Cannot validate argument on parameter 'OutputPath'` - the folder part of the path does not exist.
- The summary ends with `No orphaned SIDs found. Active Directory ACLs appear to be clean.` and no
  file is written.
- `Failed to export results to CSV: <message>` in the summary section.

**Root Cause:** the export runs only when at least one orphaned SID was found. The file is always
CSV (`StreamingResultsManager.ExportToCsv`), whatever extension `-OutputPath` carries. The folder
must already exist.

**Resolution:**

```powershell
New-Item -Path .\Reports -ItemType Directory -Force | Out-Null
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -OutputPath '.\Reports\orphaned-sids.csv'

# Confirm from the log
Select-String -Path (Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Pattern 'Orphaned SIDs found:|Results exported to:'
```

Columns follow the `OrphanedSIDResult` class: `ObjectDN`, `ObjectClass`, `OrphanedSID`,
`LikelySource`, `Confidence`, `AnalysisNotes`, `AccessControlType`, `ActiveDirectoryRights`,
`InheritanceType`, `ObjectType`, `InheritedObjectType`, `IsInherited`, `ProcessingMethod`,
`ActionTaken`, `CorrelationId`, `Timestamp`.

#### Issue: Correlation ID cannot be found in the logs

**Symptoms:** `Select-String` for the ID returns nothing, or returns lines from several runs.

**Root Cause:** the correlation ID is written in every log line as the fourth bracketed field,
`[<timestamp>] [<Level>] [<Component>] [<CorrelationId>] <Message>`. It is never part of the log
file name, which is `Find-UnknownSID_<yyyyMMdd_HHmmss>.log` by default. When `-CorrelationId` is
not given a new GUID is generated per run.

**Resolution:**

```powershell
$correlationId = [guid]::NewGuid().ToString()
.\Find-UnknownSID.ps1 -SearchBase 'OU=Test,DC=contoso,DC=com' -CorrelationId $correlationId
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern "\[$correlationId\]" | Select-Object -First 20
```

Any string is accepted for `-CorrelationId` on the main script, but `Test-BackupValidation` in the
restore path requires GUID format, so keep GUIDs for runs that use `-Restore`.

### 7. Backup Issues During Removal

#### Issue: Removal aborts with a backup error

**Symptoms:**

- `Failed to create ACL backup for <DN> : <message>` followed by
  `Failed to create ACL backup - aborting removal operation` for that object.
- `WARNING: No backup path specified. Using default: <script folder>\Backup`.

**Root Cause:** every removal first writes `<sanitized DN>_<yyyyMMdd_HHmmss>.xml` (Export-Clixml)
to `-BackupPath\<yyyyMMdd_HHmmss>\`. When `-BackupPath` is omitted the script creates
`<script folder>\Backup`. A failed backup aborts that object's removal; other objects continue.

**Resolution:**

```powershell
$backupRoot = 'D:\ACLBackups'
New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
$drive = Get-PSDrive -Name $backupRoot.Substring(0, 1)
"Free space: $([math]::Round($drive.Free / 1GB, 2)) GB"

.\Find-UnknownSID.ps1 -Remove -SearchBase 'OU=Test,DC=contoso,DC=com' -BackupPath $backupRoot -WhatIf
```

The parent of `-BackupPath` must exist (`Parent directory does not exist for backup path: <dir>`
otherwise). Full backup and restore guidance is in
`.\Troubleshooting\Common\Backup-Restore-Issues.md`.

## Low Priority Issues

### 8. Logging Issues

#### Issue: Log files grow too large

**Resolution:**

```powershell
# Write only Warning and above to the file; console output is unaffected
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -LogLevel Warning

# Remove logs older than 30 days
Get-ChildItem -Path .\Logs -Filter 'Find-UnknownSID_*.log' |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force
```

At start-up an existing log file larger than `MaxLogFileSizeMB` (config, default 10) is renamed to
`<name>_<yyyyMMdd_HHmmss>.log` when `EnableLogFileRotation` is true. Security events bypass the
`-LogLevel` filter and are always written.

#### Issue: `-Verbose` or `-Debug` changes the log level unexpectedly

When `-LogLevel` is not given, `-Verbose` sets the file level to `Verbose` and `-Debug` sets it to
`Debug`. Pass `-LogLevel` explicitly to keep a fixed level while using the common parameters.

## Diagnostic Commands

### Quick health check

```powershell
function Test-FindUnknownSIDHealth {
    param([string]$ScriptRoot = (Get-Location).Path)

    "PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    if (Get-Module -ListAvailable -Name ActiveDirectory) { 'ActiveDirectory module: available' }
    else { 'ActiveDirectory module: MISSING' }

    $files = 'Find-UnknownSID.ps1',
        'Private\Core\Import-LoggingSystem.ps1',
        'Private\ClassManagement\Import-SecureClasses.ps1',
        'Classes\ScriptConfiguration.ps1',
        'Classes\StreamingResultsManager.ps1'
    foreach ($file in $files) {
        if (Test-Path (Join-Path $ScriptRoot $file)) { "Present: $file" } else { "MISSING: $file" }
    }

    try {
        $domain = Get-ADDomain -ErrorAction Stop
        "AD connectivity: $($domain.DNSRoot)"
    } catch {
        "AD connectivity failed: $($_.Exception.Message)"
    }
}
```

### Collect diagnostics for a support request

```powershell
$diag = ".\Diagnostics\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -Path $diag -ItemType Directory -Force | Out-Null
$PSVersionTable | Out-File "$diag\powershell-version.txt"
Get-ADDomain | Out-File "$diag\ad-domain.txt"
if (Test-Path .\config.json) { Copy-Item .\config.json "$diag\config.json" }
Get-ChildItem .\Logs -Filter 'Find-UnknownSID_*.log' | Sort-Object LastWriteTime -Descending |
    Select-Object -First 3 | Copy-Item -Destination $diag
"Diagnostic package: $diag"
```

Include the correlation ID of the failed run, the exact error text, and the domain size.

## Related Documentation

- `.\Troubleshooting\Common\Backup-Restore-Issues.md`
- `.\Troubleshooting\Common\Security-Descriptor-Warnings.md`
- `.\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md`
- `.\Troubleshooting\Performance\Memory-Management-Issues.md`
- `.\Troubleshooting\Security\Orphaned-SID-Issues.md`
- `.\Documentation\Find-UnknownSID-Automation.md`
