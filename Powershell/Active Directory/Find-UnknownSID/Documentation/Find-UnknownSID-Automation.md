# Find-UnknownSID Automation Guide

This guide covers running `Find-UnknownSID.ps1` from a scheduled task, a CI/CD job or any other
session where nobody can answer a prompt, and how such a job reads the results.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | The script ran to completion. Individual objects may still have failed; check the log and the CSV. |
| 1 | A critical error reached the script's `end` block. The message is logged at `Error` level and the script stops. |

There are no other exit codes. A failed object, a blocked SID or a failed backup does not change
the exit code; those outcomes are recorded in the log and in the per-object results.

## Parameters for Unattended Runs

| Parameter | Purpose in automation |
|-----------|----------------------|
| `-SearchBase <string[]>` | OU or object DNs to scan. Omitted: the current domain root, with a warning. |
| `-OutputPath <path>` | CSV file for discovery and removal results. The parent folder must exist. Without it, results exist only in the log. |
| `-LogPath <path>` | Log file. Default `.\Logs\Find-UnknownSID_<yyyyMMdd_HHmmss>.log` relative to the working directory. |
| `-LogLevel <level>` | Minimum level written to the log file: `Critical`, `Error`, `Warning`, `Information` (default), `Debug`, `Verbose`. Security audit entries are written regardless. |
| `-SuppressConsoleOutput` | Suppresses console log output. File logging is unaffected. |
| `-CorrelationId <string>` | Identifier stamped on every log line and every backup. Supply one from the orchestrator to correlate across systems; default is a new GUID. |
| `-Force` | Required for an unattended `-Remove` or `-Restore`. See [Confirmation](#confirmation-in-non-interactive-sessions). |
| `-WhatIf` | Previews `-Remove` or `-Restore` without changing anything and never prompts. |
| `-ConfigPath <path>` | JSON configuration file. See [Configuration File](#configuration-file). |
| `-MaxMemoryUsageMB <int>` | Memory threshold in MB, 100 to 16384, default 1024. |
| `-MaxRetries <int>` | Retries per Active Directory operation, 1 to 10, default 3. |
| `-IncludeInherited` | Also report inherited access control entries. |
| `-PreserveTempFiles` | Keep the per-run streaming results folder after the run. |

The script writes nothing to the pipeline. `$result = .\Find-UnknownSID.ps1 ...` captures nothing
useful; read `$LASTEXITCODE`, the CSV and the log instead.

## Confirmation in Non-Interactive Sessions

`-Remove` and `-Restore` ask for confirmation once unless `-Force` or `-WhatIf` is given. A session
that cannot show a prompt (scheduled task, CI agent, no host UI) is treated as a refusal, and the
script stops with exit code 1 and this message in the log and on the error stream:

```text
Refusing to remove orphaned SIDs from ACLs without confirmation. Re-run with -Force to proceed unattended, or with -WhatIf to preview the changes.
```

Discovery mode (neither switch) never prompts.

```powershell
# Discovery, unattended
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -OutputPath "C:\Reports\orphaned-sids.csv" -SuppressConsoleOutput

# Removal preview, unattended
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -WhatIf -SuppressConsoleOutput

# Removal, unattended
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -Force -SuppressConsoleOutput
```

## CI/CD Integration

The script does not detect CI environments and has no automation-specific mode; a pipeline step
is an ordinary unattended run. Pass a correlation ID from the pipeline so the log can be tied back
to the job.

### Azure DevOps Pipeline

```yaml
- task: PowerShell@2
  displayName: 'Scan for orphaned SIDs'
  inputs:
    filePath: 'Powershell/Active Directory/Find-UnknownSID/Find-UnknownSID.ps1'
    arguments: >-
      -SearchBase "DC=contoso,DC=com"
      -OutputPath "$(Build.ArtifactStagingDirectory)/orphaned-sids.csv"
      -LogPath "$(Build.ArtifactStagingDirectory)/Find-UnknownSID.log"
      -CorrelationId "$(Build.BuildId)"
      -SuppressConsoleOutput
    failOnStderr: false
```

### GitHub Actions

```yaml
- name: Scan for orphaned SIDs
  shell: pwsh
  run: |
    & "./Powershell/Active Directory/Find-UnknownSID/Find-UnknownSID.ps1" `
        -SearchBase "DC=contoso,DC=com" `
        -OutputPath "$env:RUNNER_TEMP/orphaned-sids.csv" `
        -LogPath "$env:RUNNER_TEMP/Find-UnknownSID.log" `
        -CorrelationId "$env:GITHUB_RUN_ID" `
        -SuppressConsoleOutput
    if ($LASTEXITCODE -ne 0) { throw "Find-UnknownSID exited with $LASTEXITCODE" }
```

### Scheduled Task

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
    '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Find-UnknownSID\Find-UnknownSID.ps1" ' +
    '-SearchBase "DC=contoso,DC=com" -OutputPath "C:\Reports\orphaned-sids.csv" ' +
    '-LogPath "C:\Logs\Find-UnknownSID.log" -SuppressConsoleOutput'
)
```

## Reading the Results

### CSV Output

With `-OutputPath`, discovery and removal results are exported with `Export-Csv -NoTypeInformation`
(UTF-8). One row per orphaned access control entry, with these columns:

`ObjectDN`, `ObjectClass`, `OrphanedSID`, `LikelySource`, `Confidence`, `AnalysisNotes`,
`AccessControlType`, `ActiveDirectoryRights`, `InheritanceType`, `ObjectType`,
`InheritedObjectType`, `IsInherited`, `ProcessingMethod`, `ActionTaken`, `CorrelationId`,
`Timestamp`.

No CSV is written when nothing was found, or under `-WhatIf`.

```powershell
$results = Import-Csv "C:\Reports\orphaned-sids.csv"
$results | Group-Object ObjectDN | Sort-Object Count -Descending | Select-Object -First 10
```

### Log File

Each log line has the form:

```text
[2025-01-27T14:30:22.123] [Information] [Main] [12345678-1234-1234-1234-123456789012] Starting main processing workflow
```

Entries with structured details append ` | Details: {...}` as compact JSON. Security audit
entries carry the component `SecurityAudit`. Filter by the correlation ID to isolate one run when
several share a log file:

```powershell
Select-String -Path "C:\Logs\Find-UnknownSID.log" -Pattern "\[12345678-1234-1234-1234-123456789012\]" |
    Where-Object { $_.Line -match '\[(Error|Warning)\]' }
```

`-LogLevel` filters what reaches the file: `Warning` keeps `Critical`, `Error` and `Warning`
lines and drops `Information`, `Debug` and `Verbose`. Security audit entries bypass the filter.

### Temporary Files

Discovery results are streamed in batches to `<TEMP>\Find-UnknownSID-<CorrelationId>\` as
`batch_<n>.json`, `results_<timestamp>.json` and `summary_<timestamp>.json`. The folder is deleted
when the run ends unless `-PreserveTempFiles` is given, in which case its path is logged.

## Configuration File

`-ConfigPath` points at a JSON file. Only these keys are read; anything else is ignored.

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `WellKnownSIDPatterns` | string[] | Built-in list of regexes for well-known SIDs | Each value must compile as a .NET regex |
| `ProtectedSIDs` | string[] | `S-1-5-32-544`, `S-1-5-32-545`, `S-1-5-32-546`, `S-1-5-18`, `S-1-5-19`, `S-1-5-20` | Each value must match `^S-1-\d+(-\d+)*$` |
| `BatchSize` | int | 50 | 1 to 1000; results per streaming batch file |
| `MemoryCheckInterval` | int | 50 | 1 to 100; objects processed between memory checks |
| `EnableDetailedLogging` | bool | false | |
| `LogLevel` | string | `Information` | Same values as `-LogLevel` |
| `LogFilePath` | string | none | When set, entries written after configuration load go to this file instead of `-LogPath`; its folder must exist. Startup entries are already in `-LogPath` |
| `EnableLogFileRotation` | bool | true | Rotate an existing log larger than `MaxLogFileSizeMB` at startup |
| `MaxLogFileSizeMB` | int | 10 | |

`CriticalObjectPatterns` is part of the default configuration but cannot be set from the file.

```json
{
  "BatchSize": 200,
  "MemoryCheckInterval": 25,
  "LogLevel": "Warning",
  "ProtectedSIDs": ["S-1-5-32-544", "S-1-5-32-548"]
}
```

## Best Practices

1. Run with `-WhatIf` in a new environment before the first `-Remove`.
2. Always pass `-OutputPath` and `-LogPath` to known locations and collect both as job artifacts.
3. Pass the job identifier as `-CorrelationId`; it is stamped on every log line and every backup
   file.
4. Treat exit code 0 as "the run finished", not as "nothing failed"; inspect `[Error]` and
   `[Warning]` lines before acting on the output.
5. Keep `-Force` out of discovery runs; it only matters for `-Remove` and `-Restore`.
