# Security Logging

## Overview

Find-UnknownSID keeps two logging paths. Ordinary entries go through `Write-StructuredLog` /
`Write-StructuredLogEntry`, and their file output honours `-LogLevel`. Security audit entries go
through `Write-SecurityStructuredLogEntry`, which writes to the log file regardless of `-LogLevel`,
so an operator who lowers the file verbosity to `Error` still gets a complete record of Active
Directory access and of every SID that was blocked or removed.

## Regular Logging and -LogLevel

`Write-StructuredLogEntry` (`Private/Logging/Write-StructuredLogEntry.ps1`) formats each entry as

```text
[<timestamp>] [<Level>] [<Component>] [<CorrelationId>] <Message>
```

appending ` | Details: {...}` when structured data is attached. It always writes the entry to the
console (unless `-SuppressConsoleOutput` was given) and writes it to the file only when
`Test-LogLevel` accepts the level. Levels are ordered `Critical` (0), `Error` (1), `Warning` (2),
`Information` (3), `Debug` (4), `Verbose` (5); an entry is written when its number is less than or
equal to the configured level's number. `-LogLevel Warning` therefore keeps `Critical`, `Error` and
`Warning` in the file and drops the rest.

The level is held in module state by `Private/Logging/Initialize-LoggingConfiguration.ps1`, which
also exposes `Set-LogLevel -Level <level>` and `Get-LogLevel` for code that needs to change it at
run time.

## Security Logging Path

### Write-SecurityStructuredLogEntry

`Private/Logging/Write-SecurityStructuredLogEntry.ps1` accepts `-Message`, `-Level` (`Critical`,
`Error`, `Warning` or `Information`; `Debug` and `Verbose` are not allowed for security entries),
`-Component` (default `SecurityAudit`), `-Data` and `-CorrelationId`. For each entry it:

1. Formats the message with `Format-LogMessage`.
2. Writes it to the console with a `[SECURITY]` prefix, except that `Information`-level security
   entries are file-only to keep the console readable. `Critical` is shown via `Write-Host` in red
   on yellow, `Error` via `Write-Error`, `Warning` via `Write-Warning`. `-SuppressConsoleOutput`
   suppresses all of this.
3. Appends the entry to the log file with `Add-Content`, without consulting `Test-LogLevel`.

If the log file is not initialised or the write fails, the entry is retried directly against the
configured log path and then written to `%TEMP%\Find-UnknownSID-Security-<yyyyMMdd>.log` with a
warning naming that file. If formatting itself fails, a plain-text line is written to the log path,
and as a last resort to `%TEMP%\Find-UnknownSID-Security-Emergency.log`. Only when every location
fails does the function raise `CRITICAL SECURITY LOGGING FAILURE`.

### Write-SecurityLog

`Private/Logging/Write-SecurityLog.ps1` is the entry point the rest of the code uses:

```powershell
Write-SecurityLog -SecurityEventType <string> -Message <string> -Outcome Attempt|Success|Failure
                  [-SecurityContext <hashtable>] [-CorrelationId <string>]
```

It builds a data block (timestamp, event type, outcome, `UserContext` as `user@computer`, process
ID, correlation ID, plus every `SecurityContext` key prefixed `Security_`), maps the outcome to a
level (`Attempt` and `Success` to `Information`, `Failure` to `Warning`), and calls
`Write-SecurityStructuredLogEntry` with the component `SecurityAudit` and the message
`[<SecurityEventType>] [<Outcome>] <Message>`. If that call throws, the line is appended to
`%TEMP%\Find-UnknownSID-Security-Fallback.log`.

### Write-ADOperationSecurityLog

`Private/Logging/Write-ADOperationSecurityLog.ps1` wraps `Write-SecurityLog` for Active Directory
access:

```powershell
Write-ADOperationSecurityLog -OperationName <string> -Outcome Attempt|Success|Failure
                             [-SecurityContext <hashtable>] [-CorrelationId <string>]
```

It emits an `ObjectAccess` event with the message `Attempting Active Directory operation: <name>`,
`Successfully completed Active Directory operation: <name>` or
`Failed Active Directory operation: <name>`.

### Where Security Entries Come From

- `Private/ActiveDirectory/Get-ADObjectsSequential.ps1` and
  `Private/ActiveDirectory/Invoke-ADOperationWithRetry.ps1`: every AD query, attempt and outcome
- `Private/Core/Invoke-MainProcessingLogic.ps1`: workflow-level access events
- `Private/SID/Test-SIDSecurity.ps1`: `DataValidation` events for every SID checked before removal,
  including the reason a SID was blocked, and `RiskAssessment` events
- `Private/Operations/Invoke-RemovalWorkflow.ps1` via `Write-RemovalSecurityLog`
  (`Private/Logging/Write-RemovalSecurityLog.ps1`): `PrivilegeUse` events around each ACL
  modification, forwarded to `Write-SecurityLog`

### Load Order

`Private/Core/Import-LoggingSystem.ps1` loads the logging files in a fixed order:
`Initialize-LoggingConfiguration`, `Initialize-LogDirectory`, `Initialize-LoggingSystem`,
`Format-LogMessage`, `Protect-LogMessage`, `Write-StructuredLogEntry`,
`Write-SecurityStructuredLogEntry`, `Write-SecurityLogEvent`, `Get-LogFileSummary`,
`Export-DiagnosticData`. The security writer is therefore available before any function that
calls it.

## What This Provides

- **Complete audit trail at any -LogLevel.** AD access attempts and results, SID validation
  outcomes and ACL changes reach the file even with `-LogLevel Error` or `Critical`.
- **Correlation.** Every security entry carries the run's correlation ID, the same value that is
  on regular log lines and inside each backup file.
- **Fallback locations.** A security event that cannot reach the log file lands in `%TEMP%` under
  one of the three names above rather than being lost.
- **Separation from operational noise.** Security entries are identifiable by the `SecurityAudit`
  component in the file and the `[SECURITY]` prefix on the console.

What it does not provide: log integrity protection or tamper evidence. The log file is plain
UTF-8 text that anyone with write access can edit; protect the log folder with file-system ACLs
and forward the file to a central log store if the audit trail must survive the host.

## Usage

```powershell
# Only Error and Critical operational entries reach the file; all security entries still do
.\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -LogLevel Error

# Read back the security entries for a run
Select-String -Path ".\Logs\Find-UnknownSID_*.log" -Pattern "\[SecurityAudit\]" |
    Where-Object { $_.Line -match "12345678-1234-1234-1234-123456789012" }
```

From inside a function that already has the logging system loaded:

```powershell
Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Reading ACL' -Outcome 'Attempt' -CorrelationId $CorrelationId
Write-ADOperationSecurityLog -OperationName 'Get-Acl' -Outcome 'Success' -CorrelationId $CorrelationId
```

## Troubleshooting

- **Security entries appear in the file but not on the console**: expected for `Information`
  outcomes (`Attempt`, `Success`); only `Warning`, `Error` and `Critical` are echoed.
- **"Security log written to emergency location: ..."**: the main log file could not be written;
  check `-LogPath` permissions and collect the named `%TEMP%` file.
- **No `[SecurityAudit]` lines at all**: the logging system failed to initialise before the first
  security event; look for `Initialize-LoggingSystem` errors at the top of the console output.

See [Security-Logging-Issues.md](../Troubleshooting/Security/Security-Logging-Issues.md).
