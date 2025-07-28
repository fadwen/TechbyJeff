# Sample Backups

## Overview
This directory contains sample backup files used for testing backup/restore functionality of the Find-UnknownSID module. These files simulate various backup scenarios including successful backups, partial backups, and error conditions.

## File Inventory

### Current Files
*(Directory is currently empty - files will be generated as needed)*

### Expected Files
- `complete-backup-20240115-120000.json` - Complete system backup
- `incremental-backup-20240115-180000.json` - Incremental changes backup
- `differential-backup-20240115-210000.json` - Differential backup
- `configuration-backup-20240115-120000.xml` - Configuration-only backup
- `metadata-backup-20240115-120000.json` - Metadata and settings backup
- `large-backup-20240115-120000.json` - Large dataset backup (100K+ objects)
- `compressed-backup-20240115-120000.gz` - Compressed backup file
- `encrypted-backup-20240115-120000.enc` - Encrypted backup file

## Usage

### Loading Sample Backups
```powershell
# Load a complete backup for restore testing
$backup = Get-Content ".\complete-backup-20240115-120000.json" | ConvertFrom-Json

# Load and validate backup integrity
$backupValidation = Test-BackupIntegrity -BackupFile ".\complete-backup-20240115-120000.json"

# Restore from backup
Restore-UnknownSIDData -BackupFile ".\complete-backup-20240115-120000.json" -Confirm:$false
```

### Backup Testing Scenarios
```powershell
# Test backup creation
$testData = Get-UnknownSIDData -Sample
$backupResult = New-UnknownSIDBackup -Data $testData -Path ".\test-backup.json"

# Test incremental backup
$incrementalData = Get-UnknownSIDData -Since (Get-Date).AddHours(-1)
$incrementalBackup = New-UnknownSIDBackup -Data $incrementalData -Type Incremental

# Test backup compression
$compressedBackup = New-UnknownSIDBackup -Data $testData -Compressed -Path ".\test-backup.gz"

# Test backup encryption
$encryptedBackup = New-UnknownSIDBackup -Data $testData -Encrypted -Password (Read-Host -AsSecureString)
```

### Restore Testing
```powershell
# Test restore validation
$restoreValidation = Test-RestoreCapability -BackupFile ".\complete-backup-20240115-120000.json"

# Test partial restore
$partialRestore = Restore-UnknownSIDData -BackupFile ".\complete-backup-20240115-120000.json" -ObjectType "User" -Selective

# Test restore with verification
$restoreResult = Restore-UnknownSIDData -BackupFile ".\complete-backup-20240115-120000.json" -Verify
```

## File Generation Commands

### Generate Complete Backup
```powershell
$completeBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        generatedBy = "Find-UnknownSID"
        totalObjects = 5000
        totalSIDs = 25000
        compressionUsed = $false
        encryptionUsed = $false
    }
    configuration = @{
        scanSettings = @{
            includeInherited = $true
            includeExplicit = $true
            maxDepth = 10
            timeout = 300
        }
        reportSettings = @{
            format = "JSON"
            includeDetails = $true
            includeStatistics = $true
        }
        securitySettings = @{
            logLevel = "Information"
            auditEnabled = $true
            encryptionRequired = $false
        }
    }
    data = @{
        orphanedSIDs = 1..100 | ForEach-Object {
            @{
                sid = "S-1-5-21-1234567890-$_"
                objectPath = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                objectType = "User"
                lastSeen = (Get-Date).AddDays(-([Random]::new().Next(1, 30)))
                confidence = [Random]::new().Next(80, 100)
                source = "ActiveDirectory"
            }
        }
        securityDescriptors = 1..200 | ForEach-Object {
            @{
                objectDN = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                descriptor = "O:BAG:BAD:(A;;CCDCLCSWRPWPDTLOCRRCWDWO;;;BA)"
                aceCount = [Random]::new().Next(1, 10)
                hasOrphanedSIDs = ($_ % 5 -eq 0)
                lastModified = (Get-Date).AddDays(-([Random]::new().Next(1, 90)))
            }
        }
        statistics = @{
            totalObjectsScanned = 5000
            orphanedSIDsFound = 100
            securityDescriptorsAnalyzed = 200
            processingTimeMinutes = 15.5
            memoryUsageMB = 250
            errorsEncountered = 0
        }
    }
    auditTrail = @{
        backupInitiated = "2024-01-15T12:00:00Z"
        backupCompleted = "2024-01-15T12:05:00Z"
        backupSize = "5.2MB"
        checksumMD5 = "d41d8cd98f00b204e9800998ecf8427e"
        checksumSHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        validationStatus = "Passed"
    }
}

$completeBackup | ConvertTo-Json -Depth 10 | Out-File "complete-backup-20240115-120000.json"
```

### Generate Incremental Backup
```powershell
$incrementalBackup = @{
    metadata = @{
        backupType = "Incremental"
        timestamp = "2024-01-15T18:00:00Z"
        basedOn = "complete-backup-20240115-120000.json"
        version = "1.0.0"
        changedObjects = 25
        newOrphanedSIDs = 5
        resolvedSIDs = 3
    }
    changes = @{
        newOrphanedSIDs = 1..5 | ForEach-Object {
            @{
                sid = "S-1-5-21-1234567890-$([Random]::new().Next(10000, 99999))"
                objectPath = "CN=NewObject$_,OU=TestObjects,DC=test,DC=local"
                objectType = "Computer"
                discoveredAt = "2024-01-15T17:$($_.ToString('00')):00Z"
                confidence = [Random]::new().Next(75, 95)
            }
        }
        resolvedSIDs = @(
            @{
                sid = "S-1-5-21-1234567890-123"
                resolvedTo = "CN=ResolvedUser,OU=Users,DC=test,DC=local"
                resolvedAt = "2024-01-15T17:30:00Z"
                method = "ActiveDirectoryLookup"
            }
        )
        modifiedObjects = 1..20 | ForEach-Object {
            @{
                objectDN = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                changeType = "SecurityDescriptorModified"
                modifiedAt = "2024-01-15T17:$($_.ToString('00')):00Z"
                previousChecksum = "abc123def456"
                currentChecksum = "def456ghi789"
            }
        }
    }
    auditTrail = @{
        incrementalBackupStarted = "2024-01-15T18:00:00Z"
        incrementalBackupCompleted = "2024-01-15T18:01:30Z"
        backupSize = "250KB"
        changeDetectionMethod = "TimestampComparison"
        validationStatus = "Passed"
    }
}

$incrementalBackup | ConvertTo-Json -Depth 10 | Out-File "incremental-backup-20240115-180000.json"
```

### Generate Configuration Backup
```powershell
$configBackup = @{
    metadata = @{
        backupType = "Configuration"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        description = "Configuration and settings backup"
    }
    moduleConfiguration = @{
        version = "2.1.0"
        installPath = "C:\Program Files\WindowsPowerShell\Modules\Find-UnknownSID"
        configurationFile = "Find-UnknownSID.config"
        lastUpdated = "2024-01-10T14:30:00Z"
    }
    scanSettings = @{
        defaultTimeout = 300
        maxConcurrentThreads = 4
        enableProgressReporting = $true
        verboseLogging = $false
        includeInheritedPermissions = $true
        scanDepthLimit = 15
        excludeSystemObjects = $false
        skipBuiltInSIDs = $true
    }
    reportSettings = @{
        defaultFormat = "HTML"
        includeStatistics = $true
        includeTimestamps = $true
        includeObjectDetails = $true
        enableDataExport = $true
        customCSSFile = ""
        reportTitle = "Orphaned SIDs Report"
    }
    securitySettings = @{
        requireAdminRights = $true
        enableAuditLogging = $true
        auditLogPath = "C:\Logs\Find-UnknownSID"
        encryptSensitiveData = $false
        allowRemoteExecution = $false
        trustedDomains = @("contoso.com", "fabrikam.com")
    }
    databaseSettings = @{
        enableDatabaseLogging = $false
        connectionString = ""
        commandTimeout = 30
        enableConnectionPooling = $true
        maxPoolSize = 100
    }
    performanceSettings = @{
        enablePerformanceCounters = $true
        memoryLimit = "2GB"
        diskSpaceLimit = "10GB"
        enableCaching = $true
        cacheTimeout = 3600
    }
}

$configBackup | ConvertTo-Json -Depth 10 | Out-File "configuration-backup-20240115-120000.xml"
```

### Generate Large Backup (100K objects)
```powershell
# Warning: This generates a very large file
$largeBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        totalObjects = 100000
        totalSIDs = 500000
        description = "Large-scale enterprise backup"
        estimatedSize = "2GB"
    }
    data = @{
        orphanedSIDs = 1..10000 | ForEach-Object {
            @{
                sid = "S-1-5-21-$(Get-Random -Minimum 1000000000 -Maximum 9999999999)-$_"
                objectPath = "CN=LargeObject$_,OU=LargeTestObjects,DC=enterprise,DC=local"
                objectType = @("User", "Computer", "Group")[(Get-Random -Minimum 0 -Maximum 3)]
                lastSeen = (Get-Date).AddDays(-([Random]::new().Next(1, 365)))
                confidence = [Random]::new().Next(60, 100)
            }
        }
        # Note: In actual implementation, would generate full 100K objects
        # Truncated here for README example
    }
}

# Compress large backup
$largeBackup | ConvertTo-Json -Depth 10 -Compress | Out-File "large-backup-20240115-120000.json"
```

## Performance Considerations

### Backup Performance
- **Small Backups** (< 1MB): < 5 seconds
- **Medium Backups** (1-100MB): < 30 seconds  
- **Large Backups** (100MB-1GB): < 5 minutes
- **Enterprise Backups** (> 1GB): < 30 minutes

### Restore Performance
- **Configuration Restore**: < 10 seconds
- **Incremental Restore**: < 30 seconds
- **Complete Restore**: Variable based on data size
- **Verification**: +50% of restore time

## File Formats

### JSON Backup Format
```json
{
  "metadata": { ... },
  "configuration": { ... },
  "data": { ... },
  "auditTrail": { ... }
}
```

### Compressed Format (.gz)
- Standard gzip compression
- Typical compression ratio: 70-80%
- Use `Expand-Archive` or gzip tools

### Encrypted Format (.enc)
- AES-256 encryption
- Password-protected
- Includes integrity verification

## Validation Commands
```powershell
# Validate backup file integrity
Test-BackupIntegrity -Path ".\complete-backup-20240115-120000.json"

# Validate backup chain consistency
Test-BackupChain -BasePath ".\complete-backup-20240115-120000.json" -IncrementalPaths @(".\incremental-backup-20240115-180000.json")

# Validate backup restoration
Test-RestoreCapability -BackupPath ".\complete-backup-20240115-120000.json" -TestMode
```

## Cleanup Commands
```powershell
# Remove all test backups
Get-ChildItem -Path "." -Filter "*backup*.json" | Remove-Item -Force

# Remove backups older than 30 days
Get-ChildItem -Path "." -Filter "*backup*" | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force

# Remove large backup files (> 100MB)
Get-ChildItem -Path "." -Filter "*backup*" | Where-Object { $_.Length -gt 100MB } | Remove-Item -Force -Confirm
```

## Best Practices
1. **Regular Testing**: Test backup/restore procedures regularly
2. **Validation**: Always validate backup integrity after creation
3. **Versioning**: Maintain backup version compatibility
4. **Compression**: Use compression for large backups
5. **Encryption**: Encrypt backups containing sensitive data
6. **Documentation**: Document backup procedures and schedules

## Troubleshooting
- **Corrupt Backup**: Use `Test-BackupIntegrity` to diagnose
- **Restore Failures**: Check file permissions and disk space
- **Performance Issues**: Consider backup compression and incremental strategies
- **Large Files**: Use streaming or chunked processing for very large backups
