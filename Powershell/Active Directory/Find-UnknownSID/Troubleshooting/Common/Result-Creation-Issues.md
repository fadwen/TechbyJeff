# Result Creation Issues - Troubleshooting Guide

## Overview

`New-OrphanedSIDResult` in `Private\SID\New-SIDResult.ps1` is the only place the script creates
result objects. It returns an instance of the `OrphanedSIDResult` class defined in
`Classes\OrphanedSIDResult.ps1`. This guide covers the ways that creation can fail or produce an
object that looks incomplete.

## The Function and the Class

```powershell
New-OrphanedSIDResult
    -ObjectDN <string>            # Mandatory
    [-ObjectClass <string>]       # default 'Unknown'
    -OrphanedSID <string>         # Mandatory; must pass Test-SIDFormat
    -AccessRule <PSObject>        # Mandatory; the access rule the SID came from
    [-LikelySource <string>]      # default 'Unknown'
    [-Confidence High|Medium|Low] # default 'Medium'
    [-Notes <string>]
    [-ProcessingMethod <string>]  # default 'Standard'; the pipeline passes 'Identity-Resolution'
    [-CorrelationId <string>]
```

The returned object has these members:

| Member | Type | Set by |
| --- | --- | --- |
| `ObjectDN`, `ObjectClass`, `OrphanedSID` | string | parameters |
| `LikelySource`, `Confidence`, `AnalysisNotes` | string | parameters (`-Notes` -> `AnalysisNotes`) |
| `AccessControlType` | `AccessControlType` | `Set-ACLMetadata` |
| `ActiveDirectoryRights` | `ActiveDirectoryRights` | `Set-ACLMetadata` |
| `InheritanceType` | `InheritanceFlags` | `Set-ACLMetadata` |
| `ObjectType`, `InheritedObjectType` | `Guid` | `Set-ACLMetadata` |
| `IsInherited` | bool | `Set-ACLMetadata` |
| `ProcessingMethod`, `ActionTaken` | string | `Add-ProcessingMetadata` (`ActionTaken` is always `Detected`) |
| `CorrelationId` | string | `Add-ProcessingMetadata` |
| `Timestamp` | DateTime (local) | `Add-ProcessingMetadata` |

There is no `SID`, `ObjectPath`, `ProcessingTime` or `PSTypeName` member. The type is the class
itself:

```powershell
$result -is [OrphanedSIDResult]        # $true
$result.PSObject.TypeNames[0]          # 'OrphanedSIDResult'
```

## Common Issues

### 1. Creation Throws

`New-OrphanedSIDResult` never returns `$null`. Any failure is rethrown as
`Failed to create OrphanedSIDResult: <inner message>` after logging
`Error creating OrphanedSIDResult object for <DN> : <inner message>` at Error level.

#### Issue: `Failed to create OrphanedSIDResult: Invalid SID format provided: <value>`

**Root Cause:** `-OrphanedSID` did not pass `Test-SIDFormat`. In the normal pipeline this cannot
happen, because `Test-SIDValidityAndType` rejects malformed values first. It occurs when calling the
function by hand with an account name or an `ORPHANED_ACCOUNT:<name>` marker instead of a SID.

**Resolution:**

```powershell
. .\Private\Core\Import-LoggingSystem.ps1
. .\Private\SID\Test-SIDFormat.ps1
Test-SIDFormat -SID 'S-1-5-21-1234567890-1234567890-1234567890-1001'   # $true
Test-SIDFormat -SID 'CONTOSO\OldGroup'                                  # $false
```

#### Issue: "Cannot bind argument to parameter 'AccessRule' because it is null"

**Root Cause:** `-AccessRule` is mandatory. The function reads `AccessControlType`,
`ActiveDirectoryRights`, `InheritanceFlags`, `ObjectType`, `InheritedObjectType` and `IsInherited`
from it. Pass the `ActiveDirectoryAccessRule` the SID was found in; for a manual test any object
with those properties will do.

#### Issue: "Unable to find type [OrphanedSIDResult]"

**Root Cause:** the class file was not loaded in the session. The main script dot-sources every file
in `Classes\` after hash validation; a diagnostic session must do so explicitly.

**Resolution:**

```powershell
Set-Location 'C:\Scripts\Find-UnknownSID'
Get-ChildItem .\Classes\*.ps1 | ForEach-Object { . $_.FullName }
. .\Private\Core\Import-LoggingSystem.ps1
. .\Private\SID\Test-SIDFormat.ps1
. .\Private\SID\New-SIDResult.ps1

$rule = [PSCustomObject]@{
    IdentityReference     = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
    AccessControlType     = 'Allow'
    ActiveDirectoryRights = 'GenericRead'
    InheritanceFlags      = 'None'
    IsInherited           = $false
}
$result = New-OrphanedSIDResult -ObjectDN 'CN=User1,OU=Test,DC=contoso,DC=com' -ObjectClass 'user' `
    -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $rule
$result | Format-List
```

### 2. Properties Look Incomplete

#### Issue: `ActiveDirectoryRights` is `GenericRead` and `AccessControlType` is `Allow` for every result

**Root Cause:** the access rule lacked those properties, so `Set-ACLMetadata` applied its defaults
(see the table in `.\Troubleshooting\Common\Metadata-Population-Issues.md`). This happens with
deserialized access rules whose property names differ.

**Resolution:** run with `-LogLevel Debug` and look for
`ActiveDirectoryRights property missing, set to GenericRead`. Then check how the object reached the
script; `Get-ObjectAccessRule` prefers a live `Get-Acl`, which returns fully typed rules.

#### Issue: `LikelySource` is `Unknown` and `Confidence` is `Medium`

**Root Cause:** these come from `Get-SIDAnalysis -SIDString <sid> [-CurrentDomainSID <sid>]`
(`Private\SID\Get-SIDAnalysis.ps1`), called by `Test-AccessRuleForOrphanedSID`. Without a domain
SID to compare against, foreign-domain classification falls back to `Unknown`. The main processing
logic does not pass `-CurrentDomainSID`, so `Unknown` is common for SIDs outside the well-known
ranges. See `.\Troubleshooting\Security\SID-Analysis-Issues.md`.

#### Issue: `Timestamp` is not UTC

By design; see `.\Troubleshooting\Common\Metadata-Population-Issues.md`.

### 3. Unresolvable Account Names Produce No Result

An access rule whose `IdentityReference` is an `NTAccount` that no longer translates is logged at
Information level as
`ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount '<name>' to SID - likely orphaned: <message>`
by `Convert-NTAccountToSID`. The function returns the marker `ORPHANED_ACCOUNT:<name>`, which then
fails `Test-SIDFormat`, so no `OrphanedSIDResult` is created and the entry does not appear in the
CSV. Search the log for these entries when the CSV seems short:

```powershell
Select-String -Path .\Logs\Find-UnknownSID_*.log -Pattern 'ORPHANED ACCOUNT DETECTED'
```

### 4. Performance

Creation is cheap: one `Test-SIDFormat`, one `[OrphanedSIDResult]::new()` and a handful of
property reads, each logged at Debug level. With `-LogLevel Debug` the roughly fifteen log lines per
result dominate the cost; use `Information` for large runs.

## Validation Commands

```powershell
# In a diagnostic session prepared as above
$result = New-OrphanedSIDResult -ObjectDN 'CN=User1,OU=Test,DC=contoso,DC=com' `
    -OrphanedSID 'S-1-5-21-1234567890-1234567890-1234567890-1001' -AccessRule $rule

$result -is [OrphanedSIDResult]
$result.ObjectDN -eq 'CN=User1,OU=Test,DC=contoso,DC=com'
$result.OrphanedSID -match '^S-1-'
$result.ActionTaken -eq 'Detected'
[guid]::TryParse($result.CorrelationId, [ref][guid]::Empty)
$result.Timestamp -gt (Get-Date).AddMinutes(-1)
```

## Related Documentation

- `.\Troubleshooting\Common\Metadata-Population-Issues.md`
- `.\Troubleshooting\Common\Result-Validation-Issues.md`
- `.\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md`
- `.\Troubleshooting\Security\SID-Format-Issues.md`

## Support Information

- **Module**: `Private\SID\New-SIDResult.ps1`
- **Function**: `New-OrphanedSIDResult`
- **Class**: `Classes\OrphanedSIDResult.ps1`
