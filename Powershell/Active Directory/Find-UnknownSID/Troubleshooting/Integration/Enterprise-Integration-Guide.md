# Enterprise Integration Guide - Find-UnknownSID

## Overview

This guide covers running `Find-UnknownSID.ps1` from schedulers, pipelines and monitoring systems,
and the integration problems that follow from how the script actually behaves:

- It writes **nothing to the pipeline**. Results are available only as the CSV named by
  `-OutputPath` and in the log file.
- The log file is **plain text**, one line per entry:
  `[<yyyy-MM-ddTHH:mm:ss.fff>] [<Level>] [<Component>] [<CorrelationId>] <Message>`. Entries with
  extra data end with a space followed by `| Details: <json>`.
- The correlation ID is in every line but **never in the file name**
  (`Find-UnknownSID_<yyyyMMdd_HHmmss>.log` by default).
- `-OutputPath` always produces **CSV**, whatever extension is given.
- There is no parallel mode, no throttle parameter and no `-Credential`; the script runs as the
  invoking account.
- `-Remove` and `-Restore` require `-Force` to run unattended; without it a non-interactive session
  stops with `Refusing to <operation> without confirmation. Re-run with -Force to proceed
  unattended, or with -WhatIf to preview the changes.`

## Integration Scenarios

### 1. SIEM Integration

Point `-LogPath` at a folder the forwarder watches and parse the bracketed fields:

```powershell
$logPath = 'C:\Program Files\SplunkUniversalForwarder\var\log\splunk\Find-UnknownSID.log'
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -LogPath $logPath -LogLevel Information `
    -CorrelationId ([guid]::NewGuid().ToString())
```

Field extraction (regex for the SIEM):

```text
^\[(?<timestamp>[^\]]+)\] \[(?<level>[^\]]+)\] \[(?<component>[^\]]+)\] \[(?<correlationId>[^\]]+)\] (?<message>.*?)(?: \| Details: (?<details>\{.*\}))?$
```

Security-relevant events carry the component names `Security`, `SecurityAudit`, `SecurityAlert`,
`ADOperations` and `RemovalSecurityLogging`, and bypass the `-LogLevel` filter, so they are written
even with `-LogLevel Error`. Fields worth indexing: `level`, `component`, `correlationId`, and the
`Orphaned SIDs found: N` summary message.

**Common issues:**

- **Expecting JSON lines**: the file is not JSON. Use the regex above, or post-process with
  `ConvertTo-Json` per line.
- **Log rotation**: an existing log larger than `MaxLogFileSizeMB` (config, default 10 MB) is
  renamed to `<name>_<yyyyMMdd_HHmmss>.log` at start-up when `EnableLogFileRotation` is true. Watch
  the folder, not a single file name.
- **Correlation ID format**: any string is accepted, but `-Restore` validates GUID format
  internally. Use GUIDs so the same convention works for every mode.

### 2. Monitoring (SCOM, Event Log)

Read the summary from the log or the CSV; the script returns no object to test.

```powershell
$id = [guid]::NewGuid().ToString()
$csv = "D:\Reports\sid-audit-$(Get-Date -Format 'yyyyMMdd').csv"
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -OutputPath $csv -CorrelationId $id -MaxMemoryUsageMB 2048

$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$found = [int](Select-String -Path $log.FullName -Pattern "\[$id\] Orphaned SIDs found: (\d+)" |
    ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -Last 1)

if ($found -gt 100) {
    Write-EventLog -LogName Application -Source 'Find-UnknownSID' -EventId 1001 -EntryType Warning `
        -Message "High orphaned SID count detected: $found (CorrelationId $id)"
}
```

Register the event source once with `New-EventLog -LogName Application -Source 'Find-UnknownSID'`.
`Write-EventLog` and `New-EventLog` exist in Windows PowerShell 5.1 only; on PowerShell 7 use
`New-WinEvent` or load them through the `WindowsCompatibility` module. The CSV exists only when at
least one orphaned SID was found; `Test-Path $csv` is a valid zero-result check.

### 3. Desired State Configuration

The `Script` resource must read the CSV or the log, as above:

```powershell
Configuration ADSecurityMaintenance {
    param(
        [string]$ScriptPath = 'C:\Scripts\Find-UnknownSID\Find-UnknownSID.ps1',
        [string]$SearchBase = 'DC=contoso,DC=com',
        [int]$MaxOrphanedSIDs = 50
    )

    Script OrphanedSIDCheck {
        TestScript = {
            $csv = Join-Path $env:TEMP 'dsc-sid-audit.csv'
            Remove-Item -Path $csv -ErrorAction SilentlyContinue
            & $using:ScriptPath -SearchBase $using:SearchBase -OutputPath $csv -LogLevel Warning
            $count = if (Test-Path $csv) { @(Import-Csv -Path $csv).Count } else { 0 }
            return ($count -le $using:MaxOrphanedSIDs)
        }
        SetScript = {
            throw 'Orphaned SID count exceeds threshold; review the audit CSV before running -Remove'
        }
        GetScript = {
            $csv = Join-Path $env:TEMP 'dsc-sid-audit.csv'
            @{ Result = if (Test-Path $csv) { @(Import-Csv -Path $csv).Count } else { 0 } }
        }
    }
}
```

### 4. Azure Monitor / Log Analytics

Upload the CSV rows, not a script return value:

```powershell
$csv = '.\Reports\sid-audit.csv'
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -OutputPath $csv
if (Test-Path $csv) {
    $body = Import-Csv -Path $csv | ConvertTo-Json -Depth 3
    # Send $body with the Log Analytics HTTP Data Collector API or a Logs Ingestion DCR endpoint
}
```

### 5. Scheduled Tasks

```powershell
$action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument @(
    '-NoProfile', '-NonInteractive', '-File', '"C:\Scripts\Find-UnknownSID\Find-UnknownSID.ps1"',
    '-SearchBase', '"DC=contoso,DC=com"', '-OutputPath', '"D:\Reports\sid-audit.csv"', '-LogLevel', 'Warning'
) -join ' '
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 02:00
Register-ScheduledTask -TaskName 'Find-UnknownSID Audit' -Action $action -Trigger $trigger -User 'CONTOSO\svc-adsecurity' -RunLevel Highest
```

The task's account needs Read permissions for discovery and Modify permissions for `-Remove`.
Because the task is non-interactive, a `-Remove` run must include `-Force`; without it the run logs
the `Refusing to remove orphaned SIDs from ACLs without confirmation` message and stops.

## Common Integration Issues

### 1. Authentication and Authorization

#### Issue: Access denied under the service account

**Symptoms:** `Failed to retrieve objects from search base '<DN>': ...` warnings, many
`All security descriptor retrieval methods failed for <DN>` warnings, or `Failed to retrieve ACL for
<DN>` during removal.

**Resolution:** grant the service account Read permissions on the search base for discovery and
Modify permissions for `-Remove`/`-Restore`. Verify as that account:

```powershell
Get-ADObject -SearchBase 'DC=contoso,DC=com' -Filter * -ResultSetSize 1 -ErrorAction Stop
Get-Acl -Path 'AD:\CN=Users,DC=contoso,DC=com' | Select-Object -ExpandProperty Access | Measure-Object
```

#### Issue: Credential prompts

The script never prompts for credentials and has no `-Credential` parameter. A prompt comes from
the environment (for example a `Get-Credential` in a wrapper). Run the task as the intended account
instead.

### 2. Performance and Scalability

#### Issue: Memory pressure on large domains

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -MaxMemoryUsageMB 4096 -LogLevel Warning
```

`-MaxMemoryUsageMB` must be at least 256 (lower values fail `Initialize-MemoryManager`
validation). Splitting the domain by OU across several runs is the only way to shorten a run; see
`.\Troubleshooting\Performance\Performance-Tuning.md`.

#### Issue: Network timeouts

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -MaxRetries 5
```

`-MaxRetries` (1-10) controls the per-object retry loop: an object whose processing threw is
re-run up to that many times. SID lookups and the ACL steps of `-Remove` are wrapped by
`Invoke-ADOperationWithRetry` with a fixed default of 3 attempts for transient errors. Object
discovery is not retried. There are no timeout settings in the configuration file. When every lookup
for a SID fails, that SID is reported as orphaned; do not run `-Remove` from a run whose log contains
`lookup failed for SID`.

### 3. Logging and Monitoring

#### Issue: Log growth

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -LogLevel Warning -LogPath '\\fileserver\logs\ADSecurity\Find-UnknownSID.log'
```

`-LogLevel` filters file output only; console output is unaffected. The folder part of `-LogPath`
is created if missing (`Cannot create log directory: <dir> - <message>` on failure).

#### Issue: Correlating one run across systems

Generate the ID once and pass it everywhere:

```powershell
$id = [guid]::NewGuid().ToString()
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -CorrelationId $id -OutputPath ".\Reports\$id.csv"
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern "\[$id\]"
```

Every row of the CSV carries a `CorrelationId` column, but that value is the per-object ID
generated during processing, not the run ID. Use the file name or the log to tie a CSV to a run.

## Automation Framework Examples

### Jenkins

```groovy
pipeline {
    agent any
    parameters {
        string(name: 'SEARCH_BASE', defaultValue: 'DC=contoso,DC=com', description: 'AD search base')
        choice(name: 'OPERATION', choices: ['Discovery', 'Removal'], description: 'Operation')
    }
    stages {
        stage('AD Security Audit') {
            steps {
                powershell """
                    \$id = [guid]::NewGuid().ToString()
                    \$csv = "\$env:WORKSPACE\\sid-audit-${env.BUILD_NUMBER}.csv"
                    if ('${params.OPERATION}' -eq 'Removal') {
                        .\\Find-UnknownSID.ps1 -Remove -Force -SearchBase '${params.SEARCH_BASE}' -BackupPath "\$env:WORKSPACE\\ACLBackups" -CorrelationId \$id -OutputPath \$csv
                    } else {
                        .\\Find-UnknownSID.ps1 -SearchBase '${params.SEARCH_BASE}' -CorrelationId \$id -OutputPath \$csv
                    }
                """
                archiveArtifacts artifacts: 'sid-audit-*.csv, ACLBackups/**', allowEmptyArchive: true
            }
        }
    }
}
```

`-Force` is required for the removal branch because the agent is non-interactive. Archive the
backup folder with the results; it is the only way to undo a removal.

### Azure DevOps

```yaml
schedules:
- cron: "0 2 * * 1"
  displayName: Weekly AD Security Audit
  branches:
    include:
    - main

pool:
  vmImage: 'windows-latest'

steps:
- powershell: |
    $id = [guid]::NewGuid().ToString()
    .\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -CorrelationId $id `
        -OutputPath "$(Build.ArtifactStagingDirectory)\sid-audit-results.csv" `
        -LogPath "$(Build.ArtifactStagingDirectory)\Find-UnknownSID.log"
  displayName: 'Execute AD Security Audit'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: '$(Build.ArtifactStagingDirectory)'
    ArtifactName: 'SID-Audit-Results'
```

## Configuration Management

`-ConfigPath` points at a JSON file. Only these top-level keys are read; nested objects and other
keys are ignored silently:

```json
{
  "BatchSize": 50,
  "MemoryCheckInterval": 50,
  "EnableDetailedLogging": false,
  "LogLevel": "Information",
  "LogFilePath": "\\\\fileserver\\logs\\ADSecurity\\Find-UnknownSID.log",
  "EnableLogFileRotation": true,
  "MaxLogFileSizeMB": 10,
  "ProtectedSIDs": ["S-1-5-32-544", "S-1-5-32-545", "S-1-5-32-546", "S-1-5-18", "S-1-5-19", "S-1-5-20"],
  "WellKnownSIDPatterns": ["^S-1-1-0$", "^S-1-5-11$", "^S-1-5-32-", "^S-1-3-[0-4]$", "^S-1-5-18$", "^S-1-5-19$", "^S-1-5-20$"]
}
```

`LogFilePath` in the file overrides `-LogPath`; unlike `-LogPath`, its folder is not created
automatically, so it must already exist or every entry fails with
`Failed to write log entry to file: <message>`. Search base, memory limit, retries, and output path
are parameters only and cannot be set in the file. Validate a file before deploying it:

```powershell
$known = 'WellKnownSIDPatterns', 'ProtectedSIDs', 'BatchSize', 'MemoryCheckInterval',
    'EnableDetailedLogging', 'LogLevel', 'LogFilePath', 'EnableLogFileRotation', 'MaxLogFileSizeMB'
(Get-Content -Path .\config.json -Raw | ConvertFrom-Json).PSObject.Properties.Name |
    Where-Object { $_ -notin $known } | ForEach-Object { "Ignored key: $_" }
```

## Monitoring and Alerting

```powershell
function Send-SecurityAlert {
    param(
        [string]$AlertType,
        [string]$Message,
        [string]$CorrelationId
    )
    $alert = @{
        AlertType     = $AlertType
        Message       = $Message
        CorrelationId = $CorrelationId
        Timestamp     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Source        = 'Find-UnknownSID'
    }
    Invoke-RestMethod -Uri 'https://monitoring.contoso.com/api/alerts' -Method Post `
        -Body ($alert | ConvertTo-Json) -ContentType 'application/json'
}

$id  = [guid]::NewGuid().ToString()
$csv = ".\Reports\$id.csv"
.\Find-UnknownSID.ps1 -SearchBase 'DC=contoso,DC=com' -CorrelationId $id -OutputPath $csv
$count = if (Test-Path $csv) { @(Import-Csv -Path $csv).Count } else { 0 }
if ($count -gt 100) {
    Send-SecurityAlert -AlertType 'HighOrphanedSIDCount' -Message "Found $count orphaned SIDs" -CorrelationId $id
}
```

## Troubleshooting Integration Issues

### Diagnostic information

```powershell
function Get-IntegrationDiagnostics {
    param([string]$CorrelationId = [guid]::NewGuid().ToString())

    $dc = Get-ADDomainController
    @{
        CorrelationId   = $CorrelationId
        PowerShell      = $PSVersionTable.PSVersion.ToString()
        Edition         = $PSVersionTable.PSEdition
        RunningAs       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Interactive     = [Environment]::UserInteractive
        ADModule        = [bool](Get-Module -ListAvailable -Name ActiveDirectory)
        DomainController = $dc.HostName
        Ldap389         = (Test-NetConnection -ComputerName $dc.HostName -Port 389 -InformationLevel Quiet)
        DomainMode      = (Get-ADDomain).DomainMode
    }
}
```

`Interactive = False` means a `-Remove` or `-Restore` run needs `-Force`.

### Common error patterns

| Error | Cause | Resolution |
| --- | --- | --- |
| `Refusing to remove orphaned SIDs from ACLs without confirmation. ...` | Non-interactive `-Remove` without `-Force` | Add `-Force`, or `-WhatIf` for a preview |
| `Script initialization failed: Active Directory PowerShell module is not available` | RSAT AD module missing on the agent | Install RSAT-AD-PowerShell |
| `The RPC server is unavailable` inside AD lookups | DC connectivity | Check port 389/636 and DNS; raise `-MaxRetries` |
| `Cannot validate argument on parameter 'OutputPath'` | Folder in `-OutputPath` does not exist | Create it first |
| `Cannot validate argument on parameter 'MaxMemoryMB'` | `-MaxMemoryUsageMB` below 256 | Use 256 or more |
| CSV missing after a run | No orphaned SIDs found | Treat as a zero result; check `Orphaned SIDs found: 0` in the log |

### Batch processing for large environments

```powershell
$ous = Get-ADOrganizationalUnit -Filter * -SearchScope OneLevel | Select-Object -ExpandProperty DistinguishedName
$batchSize = 10
for ($i = 0; $i -lt $ous.Count; $i += $batchSize) {
    $batch = $ous[$i..([Math]::Min($i + $batchSize - 1, $ous.Count - 1))]
    $id = [guid]::NewGuid().ToString()
    .\Find-UnknownSID.ps1 -SearchBase $batch -CorrelationId $id -OutputPath ".\Reports\batch-$($i / $batchSize + 1)-$id.csv"
}
```

`-SearchBase` accepts an array, and distinguished names can also be piped
(`$ous | .\Find-UnknownSID.ps1`).

## Related Documentation

- `.\Documentation\Find-UnknownSID-Automation.md`
- `.\Documentation\Security-Logging-Compliance.md`
- `.\Troubleshooting\Common\Find-UnknownSID-Issues.md`
- `.\Troubleshooting\Common\Backup-Restore-Issues.md`
- `.\Troubleshooting\Performance\Performance-Tuning.md`
- `.\Troubleshooting\Security\Security-Logging-Issues.md`
