# ACL Backup and Restore Operations

## Overview

The Find-UnknownSID solution provides comprehensive backup and restore capabilities for Active Directory ACL operations. This ensures safe SID removal operations with the ability to rollback changes if needed.

## Backup Operations

### Automatic Backup Creation

When using the `-Remove` parameter, ACL backups are automatically created if a backup path is specified:

```powershell
# Automatic backup during removal
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"
```

### Manual Backup Creation

The `Backup-ObjectACL` function can be used directly for manual backup operations:

```powershell
# Load the module first
. .\Private\RemovalOperations.ps1

# Create manual backup
$acl = Get-Acl -Path "AD:\CN=User1,CN=Users,DC=contoso,DC=com"
Backup-ObjectACL -ObjectDN "CN=User1,CN=Users,DC=contoso,DC=com" -ACL $acl -BackupPath "C:\Backups"
```

### Backup File Format

Backup files are stored in XML format with the following features:

- **File naming**: `{SafeObjectName}_{Timestamp}.xml`
- **Integrity verification**: SHA256 hash of SDDL content
- **Comprehensive metadata**: Backup date, user context, correlation ID, etc.
- **SDDL format**: Security Descriptor Definition Language for full ACL representation

### Backup File Contents

Each backup file contains:

```xml
<PSCustomObject>
    <ObjectDN>CN=User1,CN=Users,DC=contoso,DC=com</ObjectDN>
    <BackupDate>2025-01-27T14:30:22</BackupDate>
    <CorrelationId>12345678-1234-1234-1234-123456789012</CorrelationId>
    <SDDL>O:S-1-5-21-...D:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;DA)...</SDDL>
    <SDDLHash>base64-encoded-sha256-hash</SDDLHash>
    <ValidationSignature>PSSecurityBackup_v1.0</ValidationSignature>
    <!-- Additional metadata -->
</PSCustomObject>
```

## Restore Operations

### Using Restore Parameter

The main script supports direct restore operations:

```powershell
# Restore specific object from backup directory
.\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"

# Preview restore operation (WhatIf mode)
.\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -WhatIf

# Restore multiple objects
.\Find-UnknownSID.ps1 -Restore -SearchBase @("CN=User1,CN=Users,DC=contoso,DC=com", "CN=User2,CN=Users,DC=contoso,DC=com") -BackupPath "C:\Backups"
```

### Direct Function Usage

The `Restore-ObjectACL` function provides fine-grained control:

```powershell
# Load the module first
. .\Private\RemovalOperations.ps1

# Restore from specific backup file
Restore-ObjectACL -ObjectDN "CN=User1,CN=Users,DC=contoso,DC=com" -BackupFile "C:\Backups\CN_User1_20250127_143022.xml"

# Restore using most recent backup from directory
Restore-ObjectACL -ObjectDN "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"

# Preview restore operation
Restore-ObjectACL -ObjectDN "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -WhatIfMode

# Automated restore without confirmation prompts
Restore-ObjectACL -ObjectDN "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -Force
```

## Validation and Safety Features

### Backup Validation

All restore operations include comprehensive validation:

- **Integrity verification**: SHA256 hash validation of SDDL content
- **Format validation**: Ensures backup file format compatibility
- **Object DN matching**: Verifies backup matches target object
- **SDDL format validation**: Confirms SDDL can be parsed correctly

### Safety Confirmations

- **Interactive confirmation**: User confirmation required unless `-Force` is used
- **WhatIf support**: Preview operations without making changes
- **Detailed logging**: All operations logged with correlation IDs
- **Error handling**: Comprehensive error handling with rollback capability

## Disaster Recovery Scenarios

### Scenario 1: Rollback Failed SID Removal

```powershell
# 1. Perform SID removal with backup
.\Find-UnknownSID.ps1 -Remove -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"

# 2. If issues are discovered, restore from backup
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups"
```

### Scenario 2: Selective Object Restoration

```powershell
# Restore only specific objects that had issues
$problemObjects = @(
    "CN=User1,CN=Users,DC=contoso,DC=com",
    "CN=User2,CN=Users,DC=contoso,DC=com"
)

.\Find-UnknownSID.ps1 -Restore -SearchBase $problemObjects -BackupPath "C:\Backups"
```

### Scenario 3: Mass Recovery Operation

```powershell
# Preview mass restoration
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -WhatIf

# Execute mass restoration with automation
.\Find-UnknownSID.ps1 -Restore -SearchBase "OU=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -Force
```

## Best Practices

### Backup Management

1. **Regular cleanup**: Remove old backup files to manage disk space
2. **Backup validation**: Periodically verify backup integrity
3. **Secure storage**: Store backups in secure, access-controlled locations
4. **Documentation**: Maintain logs of backup and restore operations

### Restore Operations

1. **WhatIf first**: Always use `-WhatIf` to preview restore operations
2. **Selective restoration**: Restore only affected objects when possible
3. **Validation**: Verify restored permissions meet business requirements
4. **Documentation**: Document reasons for restoration in change management systems

### Security Considerations

1. **Access control**: Limit backup and restore permissions to authorized personnel
2. **Audit trails**: Maintain comprehensive logs of all operations
3. **Change approval**: Follow organizational change management processes
4. **Testing**: Test restore procedures in non-production environments

## Troubleshooting

### Common Issues

#### Backup Creation Failures
- **Issue**: Insufficient permissions to create backup directory
- **Solution**: Ensure service account has write permissions to backup path
- **Prevention**: Pre-create backup directories with appropriate permissions

#### Restore Validation Failures
- **Issue**: Backup integrity check fails
- **Solution**: Use alternative backup file or recreate backup if source still available
- **Prevention**: Verify backup integrity immediately after creation

#### Object Access Errors
- **Issue**: Cannot access AD object for restoration
- **Solution**: Verify object still exists and account has appropriate permissions
- **Prevention**: Use accounts with Domain Admin privileges for restore operations

### Error Codes and Solutions

| Error Type | Typical Cause | Solution |
|------------|---------------|----------|
| Backup integrity failure | Corrupted backup file | Use different backup or recreate |
| Object not found | Object deleted/moved | Update object DN or use alternative backup |
| Access denied | Insufficient permissions | Use elevated account or request permissions |
| Invalid SDDL | Backup format corruption | Use alternative backup file |

### Log Analysis

Use correlation IDs to track operations across log files:

```powershell
# Find all log entries for a specific operation
Get-Content ".\Logs\*.log" | Where-Object { $_ -match "12345678-1234-1234-1234-123456789012" }
```

## Integration with Change Management

### Pre-Change Documentation
- Document objects to be modified
- Create backup strategy and location
- Define rollback criteria and procedures

### Change Execution
- Use correlation IDs for tracking
- Create backups before modifications
- Monitor operations through logging

### Post-Change Validation
- Verify intended changes were applied
- Validate business functionality
- Document any issues or rollbacks needed

### Rollback Procedures
- Identify affected objects
- Use restore functionality to rollback changes
- Validate restored state meets requirements
- Update change management documentation

## Compliance and Auditing

### Audit Trail Requirements
- All backup and restore operations are logged
- Correlation IDs provide end-to-end tracking
- User context and timestamps recorded
- Integration with enterprise SIEM systems supported

### Compliance Documentation
- Backup files include comprehensive metadata
- Integrity verification ensures data accuracy
- Change management integration supports compliance
- Detailed logging supports audit requirements

---

*For additional troubleshooting guidance, see the `./Troubleshooting/` directory for specialized documentation.*
