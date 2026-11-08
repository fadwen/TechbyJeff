# ACL Backup and Restore Operations

## Overview

Find-UnknownSID backs up the full security descriptor of every Active Directory object it modifies
and can apply those backups again later. Backups are written before any access control entry is
removed, and a removal is abandoned for an object whose backup could not be written. This document
describes where backups land, what they contain, and how the `-Restore` mode reads them back.

## Backup Operations

### Automatic Backup Creation

Every `-Remove` run that is not a `-WhatIf` preview creates a backup for each object before touching
its ACL. `-BackupPath` is optional:

```powershell
# Backups written under C:\Backups\<yyyyMMdd_HHmmss>\
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"

# No -BackupPath: backups written under <script folder>\Backup\<yyyyMMdd_HHmmss>\
# The script warns "No backup path specified. Using default: ..." when it creates that folder.
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com"
```

For `-Remove`, the parent of `-BackupPath` must already exist; the folder itself and the per-run
timestamped subfolder are created on demand. Each script run gets its own subfolder, so repeated
runs never overwrite one another.

Under `-WhatIf` no backup is written, because no ACL is changed.

### Backup Function

Backups are produced by `New-ACLBackup` in `Private/Backup/New-ACLBackup.ps1`. It takes
`-ObjectDN`, `-ACL` (the `System.DirectoryServices.ActiveDirectorySecurity` object read from the
`AD:` drive), `-BackupPath` and an optional `-CorrelationId`, and returns `$true` or `$false`. It
depends on the logging functions the main script loads, so it is not intended to be dot-sourced on
its own; the main script's `-Remove` mode is the supported way to create backups.

### Backup File Format

Each backup is one file written with `Export-Clixml`, so it is a CliXML document that
`Import-Clixml` reads back as a `PSCustomObject`.

- **Location**: `<BackupPath>\<yyyyMMdd_HHmmss>\` (the run timestamp)
- **File name**: `<SafeObjectName>_<yyyyMMdd_HHmmss>.xml`, where `SafeObjectName` is the object's
  distinguished name with every `\ / : * ? " < > | , =` character and every run of whitespace
  replaced by `_`, truncated to 200 characters with a `_truncated` suffix when longer. For example
  `CN=User1,CN=Users,DC=contoso,DC=com` becomes
  `CN_User1_CN_Users_DC_contoso_DC_com_20250127_143022.xml`.
- **Integrity**: a SHA256 hash of the UTF-8 SDDL string, stored Base64-encoded in `SDDLHash`. The
  file is re-read immediately after writing and the hash compared; a mismatch fails the backup.

### Backup File Contents

| Property | Value |
|----------|-------|
| `ObjectDN` | Distinguished name of the backed-up object |
| `BackupDate` | Timestamp in `yyyy-MM-ddTHH:mm:ss.fffZ` format |
| `CorrelationId` | Correlation ID of the run that created the backup |
| `SDDL` | Full security descriptor in SDDL form (all sections) |
| `SDDLHash` | Base64 SHA256 of the SDDL string |
| `BackupVersion` | `2.1` |
| `PowerShellVersion` | `$PSVersionTable.PSVersion` of the creating session |
| `UserContext` | `$env:USERNAME` |
| `ComputerName` | `$env:COMPUTERNAME` |
| `DomainContext` | `$env:USERDOMAIN` |
| `ScriptVersion` | `2.1.0` |
| `ValidationSignature` | `PSSecurityBackup_v2.1` |
| `BackupMethod` | `New-ACLBackup` |
| `ACLEntryCount` | Number of access rules in the backed-up ACL |
| `Platform` | `$PSVersionTable.Platform`, or `Windows` when that is empty |
| `PSEdition` | `$PSVersionTable.PSEdition` |

## Restore Operations

### Using the Restore Parameter

`-Restore` is a separate parameter set. `-BackupPath` is mandatory and must be the folder that
directly contains the `.xml` files, normally one of the timestamped subfolders; the search is not
recursive. `-SearchBase` names the object or objects to restore.

```powershell
# Restore one object from the backups in a specific run folder
.\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022"

# Preview the restore without changing anything
.\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022" -WhatIf

# Restore several objects in one run
.\Find-UnknownSID.ps1 -Restore -SearchBase @("CN=User1,CN=Users,DC=contoso,DC=com", "CN=User2,CN=Users,DC=contoso,DC=com") -BackupPath "C:\Backups\20250127_143022"

# Restore every backed-up object under an OU
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022"
```

The script processes each `-SearchBase` value in turn and selects backup files as follows:

- **Single mode**: the value is an individual object. Files whose name contains the first DN
  component (for example `CN=User1`, or its sanitized form `CN_User1`) are candidates, and the most
  recently modified candidate is used. No candidate is an error for that object.
- **Bulk mode**: the value starts with `OU=` or `DC=` and the folder holds more than one backup
  file. Every file whose `ObjectDN` ends with the search base is restored.

### Confirmation and -Force

`-Remove` and `-Restore` both change Active Directory, so without `-WhatIf` the script asks for
confirmation once before it starts. In an interactive console this is a yes/no prompt. In a session
that cannot answer (scheduled task, CI runner, no host UI) the prompt is treated as a refusal and
the script stops with:

```text
Refusing to restore ACLs from backup without confirmation. Re-run with -Force to proceed unattended, or with -WhatIf to preview the changes.
```

`-Force` skips the prompt. `-WhatIf` never prompts.

```powershell
# Unattended restore
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022" -Force
```

### Restore Workflow Functions

The main script hands each target to `Start-OrchestrationWorkflow -OperationType 'Restore'`, which
calls `Invoke-RestoreWorkflow` (`Private/Backup/Invoke-RestoreWorkflow.ps1`) with
`-TargetObjectDN`, `-BackupPath`, `-VerifyRestoration` and the run's `-CorrelationId`. For each
selected file `Restore-IndividualObject` validates the backup, validates the target, and calls
`Set-ObjectACL` (`Private/Backup/Restore-ACLOperation.ps1`), which rebuilds the security descriptor
from the stored SDDL and applies it with `Set-Acl` on the `AD:` drive.

## Validation and Safety Features

### Backup Validation

Before a backup is applied, `Test-BackupIntegrity` (defined in
`Private/Backup/Test-BackupValidation.ps1`) runs at the `Standard` level and fails the restore of
that object on any of these:

- A missing required property: `ObjectDN`, `BackupDate`, `SDDL`, `SDDLHash`, `ValidationSignature`
- A `ValidationSignature` other than `PSSecurityBackup_v1.0`, `PSSecurityBackup_v2.0` or
  `PSSecurityBackup_v2.1`
- An `ObjectDN` that does not match the target object
- A SHA256 of the stored `SDDL` that does not equal `SDDLHash`
- An `SDDL` string that cannot be parsed into a security descriptor

### Restore Verification

After the ACL is applied (not under `-WhatIf`), `Confirm-RestorationSuccess` reads the object's
current SDDL and compares its access control entries with the backup. At the default `Standard`
tolerance at least 80 percent of the expected entries must be present for the restore to be
reported as verified; `Strict` requires 100 percent and `Permissive` 60 percent. The tolerance is
fixed at `Standard` for script-driven restores.

### Safety Summary

- **Confirmation**: one prompt per run unless `-Force` or `-WhatIf` is given
- **WhatIf**: `-WhatIf` lists what would be restored and writes nothing
- **Logging**: every step is logged with the run's correlation ID
- **Failure isolation**: a failed object is recorded and the run continues with the next target

## Recovery Scenarios

### Rollback After a Removal

```powershell
# 1. Removal with backups
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -Force

# 2. Find the run folder that was created (named by the run timestamp)
Get-ChildItem "C:\Backups" -Directory | Sort-Object Name -Descending | Select-Object -First 1

# 3. Restore everything under the OU from that folder
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022" -WhatIf
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups\20250127_143022" -Force
```

### Selective Object Restoration

```powershell
$problemObjects = @(
    "CN=User1,CN=Users,DC=contoso,DC=com",
    "CN=User2,CN=Users,DC=contoso,DC=com"
)

.\Find-UnknownSID.ps1 -Restore -SearchBase $problemObjects -BackupPath "C:\Backups\20250127_143022"
```

## Best Practices

1. Preview with `-WhatIf` before every restore.
2. Point `-BackupPath` at the exact run folder you intend to restore from.
3. Keep the correlation ID from the removal run; it is stored in each backup and appears in every
   log line of the run.
4. Store backup folders where only the operators who may restore them have access; a backup holds
   the complete security descriptor of each object.
5. Remove old run folders deliberately; the script never deletes backups.

## Troubleshooting

### Common Issues

- **Backup creation fails**: the account cannot create `-BackupPath` or its timestamped subfolder.
  The removal of that object is abandoned with "Failed to create ACL backup - aborting removal
  operation".
- **"No backup files found for object ... in path ..."**: `-BackupPath` points at the base folder
  rather than a run subfolder, or the file name does not contain the object's first DN component.
- **"Backup validation failed: ..."**: a required property is missing, the signature is unknown, the
  `ObjectDN` does not match, or the SHA256 hash does not match the stored SDDL.
- **"Target validation failed: ..."**: the object no longer exists or cannot be read.
- **"Refusing to restore ACLs from backup without confirmation"**: the session is not interactive;
  add `-Force` or `-WhatIf`.

See [Backup-Restore-Issues.md](../Troubleshooting/Common/Backup-Restore-Issues.md) for more.

### Log Analysis

Every log line carries the correlation ID in its fourth bracketed field:

```powershell
# All lines for one run (default log location)
Select-String -Path ".\Logs\Find-UnknownSID_*.log" -Pattern "12345678-1234-1234-1234-123456789012"
```
