# Find-UnknownSID has moved

The orphaned-SID discovery, removal and restore tooling that lived here is now the **OrphanedSid**
PowerShell module, in its own repository with its history:

- Repository: <https://github.com/fadwen/OrphanedSid>
- Install: `Install-PSResource -Name OrphanedSid -Scope CurrentUser -TrustRepository`

The three modes of `Find-UnknownSID.ps1` became three commands:

| Script usage | Module command |
| --- | --- |
| `.\Find-UnknownSID.ps1 -SearchBase <dn>` | `Find-OrphanedSid -SearchBase <dn>` |
| `.\Find-UnknownSID.ps1 -SearchBase <dn> -Remove -Force` | `Remove-OrphanedSid -SearchBase <dn> -Force` |
| `.\Find-UnknownSID.ps1 -Restore -SearchBase <dn> -BackupPath <folder>` | `Restore-OrphanedSidBackup -TargetObjectDN <dn> -BackupPath <folder>` |

The last version of the script in this repository is at
[tag `find-unknownsid-final`](https://github.com/fadwen/TechbyJeff/tree/find-unknownsid-final/Powershell/Active%20Directory/Find-UnknownSID).
