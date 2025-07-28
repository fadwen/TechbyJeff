# Corrupt Backup Files

## Overview
This directory contains intentionally corrupted backup files used for testing error handling, recovery procedures, and validation mechanisms in the Find-UnknownSID module. These files simulate various corruption scenarios that might occur in real-world environments.

## File Inventory

### Current Files
*(Directory is currently empty - files will be generated as needed)*

### Expected Files
- `partial-corruption-backup.json` - Backup with partial data corruption
- `invalid-json-backup.json` - Backup with JSON syntax errors
- `missing-metadata-backup.json` - Backup missing required metadata
- `checksum-mismatch-backup.json` - Backup with invalid checksums
- `truncated-backup.json` - Backup file that was truncated during write
- `encoding-corruption-backup.json` - Backup with character encoding issues
- `oversized-fields-backup.json` - Backup with malformed oversized data fields
- `circular-reference-backup.json` - Backup with circular JSON references
- `malformed-timestamps-backup.json` - Backup with invalid timestamp formats
- `binary-corruption-backup.bin` - Binary corrupted backup file

## Usage

### Testing Corruption Detection
```powershell
# Test detection of various corruption types
$corruptFiles = Get-ChildItem -Path "." -Filter "*corrupt*"
foreach ($file in $corruptFiles) {
    try {
        $validation = Test-BackupIntegrity -Path $file.FullName
        Write-Host "File: $($file.Name) - Validation: $($validation.IsValid)"
        if (-not $validation.IsValid) {
            Write-Host "  Errors: $($validation.Errors -join ', ')"
        }
    }
    catch {
        Write-Host "File: $($file.Name) - Exception: $($_.Exception.Message)"
    }
}
```

### Recovery Testing
```powershell
# Test recovery mechanisms
$corruptBackup = ".\partial-corruption-backup.json"
try {
    $result = Restore-UnknownSIDData -BackupFile $corruptBackup -ErrorAction Stop
}
catch {
    Write-Host "Expected failure: $($_.Exception.Message)"
    
    # Test recovery attempt
    $recoveryResult = Restore-UnknownSIDData -BackupFile $corruptBackup -AttemptRecovery -SkipValidation
}
```

### Error Handling Validation
```powershell
# Validate error handling for different corruption types
$testCases = @(
    @{ File = "invalid-json-backup.json"; ExpectedError = "JSON" }
    @{ File = "missing-metadata-backup.json"; ExpectedError = "Metadata" }
    @{ File = "checksum-mismatch-backup.json"; ExpectedError = "Checksum" }
    @{ File = "truncated-backup.json"; ExpectedError = "Truncated" }
)

foreach ($test in $testCases) {
    try {
        Import-UnknownSIDBackup -Path $test.File -ErrorAction Stop
        Write-Warning "Expected error not thrown for $($test.File)"
    }
    catch {
        if ($_.Exception.Message -match $test.ExpectedError) {
            Write-Host "✓ Correct error handling for $($test.File)"
        }
        else {
            Write-Warning "✗ Unexpected error for $($test.File): $($_.Exception.Message)"
        }
    }
}
```

## File Generation Commands

### Generate Partial Corruption Backup
```powershell
# Create a valid backup first
$validBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        totalObjects = 100
    }
    data = @{
        orphanedSIDs = 1..5 | ForEach-Object {
            @{
                sid = "S-1-5-21-1234567890-$_"
                objectPath = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                confidence = 95
            }
        }
    }
}

# Convert to JSON and introduce corruption
$jsonContent = $validBackup | ConvertTo-Json -Depth 10

# Corrupt some data (replace random characters)
$corruptedContent = $jsonContent.ToCharArray()
$corruptionPoints = Get-Random -Minimum 5 -Maximum 15
for ($i = 0; $i -lt $corruptionPoints; $i++) {
    $randomIndex = Get-Random -Minimum 100 -Maximum ($corruptedContent.Length - 100)
    $corruptedContent[$randomIndex] = '@'  # Replace with invalid character
}

$corruptedContent -join '' | Out-File "partial-corruption-backup.json"
```

### Generate Invalid JSON Backup
```powershell
$invalidJson = @"
{
    "metadata": {
        "backupType": "Complete",
        "timestamp": "2024-01-15T12:00:00Z",
        "version": "1.0.0"
        // Missing comma here - invalid JSON
        "totalObjects": 100
    },
    "data": {
        "orphanedSIDs": [
            {
                "sid": "S-1-5-21-1234567890-1",
                "objectPath": "CN=Object1,OU=TestObjects,DC=test,DC=local"
                "confidence": 95  // Missing comma
            }
            {  // Missing comma before this object
                "sid": "S-1-5-21-1234567890-2",
                "objectPath": "CN=Object2,OU=TestObjects,DC=test,DC=local",
                "confidence": 90
            }
        ]
    }
    // Missing closing brace
"@

$invalidJson | Out-File "invalid-json-backup.json"
```

### Generate Missing Metadata Backup
```powershell
$missingMetadata = @{
    # Missing required metadata section
    data = @{
        orphanedSIDs = @(
            @{
                sid = "S-1-5-21-1234567890-1"
                objectPath = "CN=Object1,OU=TestObjects,DC=test,DC=local"
                confidence = 95
            }
        )
    }
    configuration = @{
        scanSettings = @{
            timeout = 300
        }
    }
    # Missing auditTrail section
}

$missingMetadata | ConvertTo-Json -Depth 10 | Out-File "missing-metadata-backup.json"
```

### Generate Checksum Mismatch Backup
```powershell
$checksumBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        totalObjects = 50
    }
    data = @{
        orphanedSIDs = 1..3 | ForEach-Object {
            @{
                sid = "S-1-5-21-1234567890-$_"
                objectPath = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                confidence = 95
            }
        }
    }
    auditTrail = @{
        checksumMD5 = "INVALID_CHECKSUM_12345"  # Intentionally wrong checksum
        checksumSHA256 = "ANOTHER_INVALID_CHECKSUM_67890"
        validationStatus = "Failed"
    }
}

$checksumBackup | ConvertTo-Json -Depth 10 | Out-File "checksum-mismatch-backup.json"
```

### Generate Truncated Backup
```powershell
# Create a valid backup
$truncatedBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        totalObjects = 1000
    }
    data = @{
        orphanedSIDs = 1..50 | ForEach-Object {
            @{
                sid = "S-1-5-21-1234567890-$_"
                objectPath = "CN=Object$_,OU=TestObjects,DC=test,DC=local"
                confidence = [Random]::new().Next(70, 100)
            }
        }
    }
}

# Convert to JSON and truncate
$fullContent = $truncatedBackup | ConvertTo-Json -Depth 10
$truncatedContent = $fullContent.Substring(0, [Math]::Floor($fullContent.Length * 0.7))  # Keep only 70%

$truncatedContent | Out-File "truncated-backup.json"
```

### Generate Encoding Corruption Backup
```powershell
$encodingBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        description = "Backup with special characters: àáâãäåæçèéêë"
    }
    data = @{
        orphanedSIDs = @(
            @{
                sid = "S-1-5-21-1234567890-1"
                objectPath = "CN=Üser1,OU=Tëst Öbjects,DC=tést,DC=lócal"  # Special characters
                displayName = "Tëst Üsèr with spëcial cháracters"
                confidence = 95
            }
        )
    }
}

# Save with different encoding to cause issues
$content = $encodingBackup | ConvertTo-Json -Depth 10
$content | Out-File "encoding-corruption-backup.json" -Encoding ASCII  # Force ASCII encoding to corrupt special chars
```

### Generate Oversized Fields Backup
```powershell
$oversizedBackup = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "2024-01-15T12:00:00Z"
        version = "1.0.0"
        description = "A" * 100000  # Extremely long description
    }
    data = @{
        orphanedSIDs = @(
            @{
                sid = "S-1-5-21-1234567890-1"
                objectPath = "CN=Object1,OU=TestObjects,DC=test,DC=local"
                massiveField = "X" * 1000000  # 1MB field
                confidence = 95
            }
        )
    }
}

$oversizedBackup | ConvertTo-Json -Depth 10 | Out-File "oversized-fields-backup.json"
```

### Generate Malformed Timestamps Backup
```powershell
$malformedTimestamps = @{
    metadata = @{
        backupType = "Complete"
        timestamp = "INVALID-TIMESTAMP"  # Invalid format
        version = "1.0.0"
        createdAt = "2024-13-45T25:70:90Z"  # Invalid date values
    }
    data = @{
        orphanedSIDs = @(
            @{
                sid = "S-1-5-21-1234567890-1"
                objectPath = "CN=Object1,OU=TestObjects,DC=test,DC=local"
                lastSeen = "Not a date"  # Invalid timestamp
                confidence = 95
            }
        )
    }
    auditTrail = @{
        backupCompleted = "2024-01-32T12:00:00Z"  # Invalid day
        validationTime = 123456789  # Numeric instead of string
    }
}

$malformedTimestamps | ConvertTo-Json -Depth 10 | Out-File "malformed-timestamps-backup.json"
```

### Generate Binary Corruption
```powershell
# Create random binary data to simulate corruption
$binaryData = New-Object byte[] 1024
(New-Object Random).NextBytes($binaryData)

[System.IO.File]::WriteAllBytes("$(Get-Location)\binary-corruption-backup.bin", $binaryData)
```

## Corruption Types and Detection

### JSON Syntax Errors
- **Symptoms**: Parse exceptions, malformed JSON
- **Detection**: JSON validation fails
- **Recovery**: Manual correction or skip corrupted sections

### Missing Required Fields
- **Symptoms**: Validation failures, incomplete data
- **Detection**: Schema validation
- **Recovery**: Use defaults or prompt for missing data

### Checksum Mismatches
- **Symptoms**: Data integrity warnings
- **Detection**: Hash comparison
- **Recovery**: Re-download or use backup copy

### Truncated Files
- **Symptoms**: Unexpected end of data
- **Detection**: File size vs. expected content
- **Recovery**: Partial restore with warnings

### Encoding Issues
- **Symptoms**: Garbled text, special character corruption
- **Detection**: Character validation
- **Recovery**: Re-encode or manual correction

### Oversized Fields
- **Symptoms**: Performance issues, memory errors
- **Detection**: Field size validation
- **Recovery**: Truncate or skip oversized fields

## Testing Guidelines

### Automated Testing
```powershell
# Run automated corruption detection tests
Invoke-Pester -Path ".\Tests\CorruptionDetection.Tests.ps1"

# Test recovery mechanisms
Invoke-Pester -Path ".\Tests\RecoveryProcedures.Tests.ps1"
```

### Manual Testing
1. **Load each corrupt file** and verify appropriate error messages
2. **Test recovery mechanisms** for each corruption type
3. **Validate error logging** captures sufficient detail
4. **Verify graceful degradation** when possible

### Performance Testing
- Test detection speed for large corrupt files
- Verify memory usage during corruption analysis
- Test timeout behavior for severely corrupted files

## Recovery Strategies

### Partial Recovery
```powershell
# Attempt to recover valid sections from corrupt backup
$partialRecovery = Restore-UnknownSIDData -BackupFile $corruptFile -PartialRecovery -IgnoreErrors
```

### Validation Override
```powershell
# Skip validation for testing purposes (use with caution)
$forcedRestore = Restore-UnknownSIDData -BackupFile $corruptFile -SkipValidation -Force
```

### Manual Repair
```powershell
# Extract repairable sections manually
$content = Get-Content $corruptFile -Raw
$repaired = Repair-CorruptedBackup -Content $content -RepairMethod "BestEffort"
```

## Best Practices
1. **Always Validate**: Run integrity checks before using backups
2. **Multiple Backups**: Maintain multiple backup copies
3. **Error Logging**: Log detailed error information for analysis
4. **Graceful Degradation**: Handle corruption gracefully where possible
5. **Recovery Testing**: Regularly test recovery procedures
6. **Monitoring**: Monitor backup integrity over time

## Cleanup Commands
```powershell
# Remove all corrupt test files
Get-ChildItem -Path "." -Filter "*corrupt*" | Remove-Item -Force

# Remove all test backup files
Get-ChildItem -Path "." -Filter "*backup*" | Remove-Item -Force
```
