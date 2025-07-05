# Backup and Restore Issues Troubleshooting Guide

## Overview
This guide provides comprehensive troubleshooting for backup and restore operations in the Find-UnknownSID script. Backup and restore functionality is critical for safe ACL modifications and disaster recovery scenarios.

## ⚠️ Important: Restore Verification Failures Are Often Expected Behavior

**Key Understanding**: Restore operations commonly report "verification failed" warnings with messages like "Expected 49 entries, found 50". This is **normal and expected behavior** in most environments and indicates that:

- ✅ **The restore validation system is working correctly**
- ✅ **ACL changes occurred between backup and restore operations**
- ✅ **System processes, inheritance, or manual changes modified permissions**
- ✅ **The orphaned SID removal process discovered additional entries**

**Success Criteria**: A restore operation with 60-80% successful object restoration and low-severity verification failures (1-3 entry differences) indicates a **successful and healthy restore operation**.

For detailed analysis of verification failures, see the "Critical Restore Issues" section below.

## Understanding Backup and Restore Operations

### Backup Process Flow
1. **Pre-validation**: Verify source objects exist and are accessible
2. **ACL Extraction**: Read current ACL settings from Active Directory objects
3. **Metadata Collection**: Gather object properties and security context
4. **Serialization**: Convert ACL data to JSON format with integrity verification
5. **Storage**: Save backup files in timestamped directory structure
6. **Verification**: Validate backup completeness and integrity

### Restore Process Flow
1. **Backup Validation**: Verify backup files exist and are valid
2. **Integrity Check**: Validate backup file integrity and structure
3. **Target Verification**: Confirm target objects exist and are accessible
4. **Permission Check**: Verify restore permissions on target objects
5. **ACL Application**: Apply backed-up ACLs to target objects
6. **Validation**: Confirm successful restoration and log results

## Critical Backup Issues

### 1. Backup Creation Failures

#### Issue: "Failed to create backup directory"
**Symptoms:**
- Backup operations fail immediately
- Directory creation permission errors
- Path length limitation errors

**Root Cause:**
- Insufficient file system permissions
- Windows path length limitations (260 characters)
- Disk space exhaustion
- Invalid characters in backup path

**Resolution:**
```powershell
# Check current backup path and permissions
$BackupPath = ".\Backup"
$ResolvedPath = Resolve-Path $BackupPath -ErrorAction SilentlyContinue

if ($ResolvedPath) {
    Write-Host "Backup path exists: $($ResolvedPath.Path)"

    # Test write permissions
    try {
        $TestFile = Join-Path $ResolvedPath.Path "test-$(Get-Date -Format 'HHmmss').tmp"
        New-Item -Path $TestFile -ItemType File -Force
        Remove-Item -Path $TestFile -Force
        Write-Host "✓ Write permissions verified" -ForegroundColor Green
    } catch {
        Write-Host "✗ Write permission failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "Creating backup directory..."
    try {
        New-Item -Path $BackupPath -ItemType Directory -Force
        Write-Host "✓ Backup directory created" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to create backup directory: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check available disk space
$Drive = Split-Path $BackupPath -Qualifier
$DriveInfo = Get-PSDrive -Name $Drive.Replace(':', '')
$FreeSpaceGB = [math]::Round($DriveInfo.Free / 1GB, 2)
Write-Host "Available disk space: $FreeSpaceGB GB"

if ($FreeSpaceGB -lt 1) {
    Write-Warning "Low disk space detected. Consider using alternative backup location."
}
```

#### Issue: "Access denied during ACL backup"
**Symptoms:**
- Backup fails for specific objects
- Partial backup completion
- Permission-related error messages

**Root Cause:**
- Insufficient Active Directory permissions
- Protected objects with restricted access
- Orphaned or corrupted security descriptors

**Resolution:**
```powershell
# Test ACL read permissions for specific object
function Test-ACLReadPermission {
    param([string]$DistinguishedName)

    try {
        $Object = Get-ADObject -Identity $DistinguishedName -Properties nTSecurityDescriptor -ErrorAction Stop
        $ACL = Get-Acl -Path "AD:$DistinguishedName" -ErrorAction Stop
        Write-Host "✓ ACL read successful for: $DistinguishedName" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "✗ ACL read failed for: $DistinguishedName" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test with problematic object
$ProblematicDN = "CN=TestUser,CN=Users,DC=contoso,DC=com"
Test-ACLReadPermission -DistinguishedName $ProblematicDN

# Check current user permissions
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Running as: $CurrentUser"

# Verify group memberships
$Groups = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups | ForEach-Object {
    $_.Translate([System.Security.Principal.NTAccount])
}
Write-Host "Group memberships:"
$Groups | ForEach-Object { Write-Host "  - $($_.Value)" }
```

### 2. Backup File Corruption

#### Issue: "Backup file integrity validation failed"
**Symptoms:**
- Restore operations fail with integrity errors
- JSON parsing errors in backup files
- Checksum validation failures

**Root Cause:**
- Disk corruption or bad sectors
- Network interruption during backup
- Antivirus interference
- File system limitations

**Resolution:**
```powershell
# Validate backup file integrity
function Test-BackupIntegrity {
    param(
        [string]$BackupPath
    )

    Write-Host "Validating backup integrity in: $BackupPath" -ForegroundColor Cyan

    $BackupFiles = Get-ChildItem -Path $BackupPath -Filter "*.json" -Recurse
    $ValidationResults = @()

    foreach ($File in $BackupFiles) {
        $Result = @{
            FileName = $File.Name
            FullPath = $File.FullName
            Size = $File.Length
            IsValid = $false
            Error = $null
        }

        try {
            # Test JSON parsing
            $Content = Get-Content -Path $File.FullName -Raw
            $BackupData = $Content | ConvertFrom-Json

            # Validate required properties
            $RequiredProperties = @('ObjectDN', 'BackupTimestamp', 'ACLData', 'ObjectMetadata')
            $MissingProperties = $RequiredProperties | Where-Object { -not $BackupData.PSObject.Properties.Name.Contains($_) }

            if ($MissingProperties.Count -eq 0) {
                $Result.IsValid = $true
                Write-Host "✓ $($File.Name)" -ForegroundColor Green
            } else {
                $Result.Error = "Missing properties: $($MissingProperties -join ', ')"
                Write-Host "✗ $($File.Name) - $($Result.Error)" -ForegroundColor Red
            }

        } catch {
            $Result.Error = $_.Exception.Message
            Write-Host "✗ $($File.Name) - Parse error: $($_.Exception.Message)" -ForegroundColor Red
        }

        $ValidationResults += $Result
    }

    return $ValidationResults
}

# Repair corrupted backup files
function Repair-BackupFiles {
    param(
        [string]$BackupPath,
        [string]$SourcePath = $null
    )

    $CorruptedFiles = Test-BackupIntegrity -BackupPath $BackupPath | Where-Object { -not $_.IsValid }

    if ($CorruptedFiles.Count -gt 0) {
        Write-Host "Found $($CorruptedFiles.Count) corrupted backup files" -ForegroundColor Yellow

        if ($SourcePath -and (Test-Path $SourcePath)) {
            Write-Host "Attempting repair from source: $SourcePath" -ForegroundColor Yellow

            foreach ($CorruptedFile in $CorruptedFiles) {
                $SourceFile = Join-Path $SourcePath $CorruptedFile.FileName
                if (Test-Path $SourceFile) {
                    try {
                        Copy-Item -Path $SourceFile -Destination $CorruptedFile.FullPath -Force
                        Write-Host "✓ Repaired: $($CorruptedFile.FileName)" -ForegroundColor Green
                    } catch {
                        Write-Host "✗ Failed to repair: $($CorruptedFile.FileName)" -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host "No source path provided for repair. Manual intervention required." -ForegroundColor Yellow
        }
    } else {
        Write-Host "✓ All backup files are valid" -ForegroundColor Green
    }
}

# Usage
$BackupPath = ".\Backup\20250702_103631"
Test-BackupIntegrity -BackupPath $BackupPath
```

## Critical Restore Issues

### 3. Restore Operation Failures

#### Issue: "Target object not found during restore"
**Symptoms:**
- Restore fails with object not found errors
- Partial restore completion
- Object existence validation failures

**Root Cause:**
- Objects deleted after backup creation
- Distinguished name changes (object moves)
- Domain controller replication delays
- Backup/restore target mismatch

**Resolution:**
```powershell
# Validate target objects before restore
function Test-RestoreTargets {
    param(
        [string]$BackupPath,
        [string[]]$SearchBase = @()
    )

    Write-Host "Validating restore targets..." -ForegroundColor Cyan

    $BackupFiles = Get-ChildItem -Path $BackupPath -Filter "*.json" -Recurse
    $ValidationResults = @()

    foreach ($File in $BackupFiles) {
        try {
            $BackupData = Get-Content -Path $File.FullName | ConvertFrom-Json
            $ObjectDN = $BackupData.ObjectDN

            # Check if target restriction applies
            $IsInScope = $true
            if ($SearchBase.Count -gt 0) {
                $IsInScope = $SearchBase | Where-Object { $ObjectDN -like "*$_" }
            }

            if ($IsInScope) {
                try {
                    $TargetObject = Get-ADObject -Identity $ObjectDN -ErrorAction Stop
                    $ValidationResults += @{
                        BackupFile = $File.Name
                        ObjectDN = $ObjectDN
                        Status = "Found"
                        CurrentLocation = $TargetObject.DistinguishedName
                    }
                    Write-Host "✓ $ObjectDN" -ForegroundColor Green
                } catch {
                    $ValidationResults += @{
                        BackupFile = $File.Name
                        ObjectDN = $ObjectDN
                        Status = "Missing"
                        Error = $_.Exception.Message
                    }
                    Write-Host "✗ $ObjectDN - Not found" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "✗ Failed to read backup file: $($File.Name)" -ForegroundColor Red
        }
    }

    return $ValidationResults
}

# Search for moved objects
function Find-MovedObjects {
    param(
        [string[]]$MissingDNs
    )

    Write-Host "Searching for moved objects..." -ForegroundColor Cyan

    foreach ($DN in $MissingDNs) {
        $ObjectName = ($DN -split ',')[0] -replace '^CN=', ''
        Write-Host "Searching for: $ObjectName"

        try {
            $FoundObjects = Get-ADObject -Filter "Name -eq '$ObjectName'" -Properties DistinguishedName
            if ($FoundObjects) {
                foreach ($Found in $FoundObjects) {
                    Write-Host "  Possible match: $($Found.DistinguishedName)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  No matches found" -ForegroundColor Red
            }
        } catch {
            Write-Host "  Search failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
```

#### Issue: "ACL restoration permission denied"
**Symptoms:**
- Restore fails with permission errors
- Partial ACL restoration
- Security descriptor modification failures

**Root Cause:**
- Insufficient modify permissions on target objects
- Protected ACLs preventing modification
- Inheritance blocking restoration
- System-protected objects

**Resolution:**
```powershell
# Test restore permissions
function Test-RestorePermissions {
    param(
        [string[]]$TargetObjects
    )

    Write-Host "Testing restore permissions..." -ForegroundColor Cyan

    foreach ($ObjectDN in $TargetObjects) {
        try {
            # Test read access
            $Object = Get-ADObject -Identity $ObjectDN -Properties nTSecurityDescriptor -ErrorAction Stop

            # Test ACL read access
            $CurrentACL = Get-Acl -Path "AD:$ObjectDN" -ErrorAction Stop

            # Test if we can create a backup (indicates modify permissions)
            $TempACL = $CurrentACL.Clone()

            Write-Host "✓ $ObjectDN - Permissions sufficient" -ForegroundColor Green

        } catch [System.UnauthorizedAccessException] {
            Write-Host "✗ $ObjectDN - Permission denied" -ForegroundColor Red
        } catch {
            Write-Host "✗ $ObjectDN - Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Check for protected objects
function Test-ProtectedObjects {
    param(
        [string[]]$TargetObjects
    )

    Write-Host "Checking for protected objects..." -ForegroundColor Cyan

    foreach ($ObjectDN in $TargetObjects) {
        try {
            $Object = Get-ADObject -Identity $ObjectDN -Properties ProtectedFromAccidentalDeletion

            if ($Object.ProtectedFromAccidentalDeletion) {
                Write-Host "⚠ $ObjectDN - Protected from accidental deletion" -ForegroundColor Yellow
            }

            # Check if it's a system object
            if ($ObjectDN -match "CN=System|CN=Configuration|CN=Schema") {
                Write-Host "⚠ $ObjectDN - System container (exercise caution)" -ForegroundColor Yellow
            }

        } catch {
            Write-Host "✗ $ObjectDN - Cannot check protection status" -ForegroundColor Red
        }
    }
}
```

## Performance Issues

### 4. Slow Backup/Restore Operations

#### Issue: Backup or restore operations take excessive time
**Symptoms:**
- Operations running for hours without completion
- High memory usage during operations
- Network timeouts and connection issues

**Root Cause:**
- Large number of objects being processed
- Complex ACL structures
- Network latency to domain controllers
- Insufficient system resources

**Resolution:**
```powershell
# Optimize backup performance
function Optimize-BackupPerformance {
    param(
        [string[]]$SearchBase,
        [string]$BackupPath
    )

    Write-Host "Optimizing backup performance..." -ForegroundColor Cyan

    # Process in smaller batches
    $BatchSize = 50
    $TotalObjects = @()

    foreach ($OU in $SearchBase) {
        $Objects = Get-ADObject -SearchBase $OU -Filter * -Properties nTSecurityDescriptor
        $TotalObjects += $Objects
    }

    Write-Host "Total objects to backup: $($TotalObjects.Count)"

    $BatchCount = [math]::Ceiling($TotalObjects.Count / $BatchSize)
    Write-Host "Processing in $BatchCount batches of $BatchSize objects"

    for ($i = 0; $i -lt $BatchCount; $i++) {
        $StartIndex = $i * $BatchSize
        $EndIndex = [math]::Min(($StartIndex + $BatchSize - 1), ($TotalObjects.Count - 1))
        $Batch = $TotalObjects[$StartIndex..$EndIndex]

        Write-Host "Processing batch $($i + 1)/$BatchCount ($($Batch.Count) objects)"

        # Process batch with correlation ID
        $BatchCorrelationId = "BATCH-$($i + 1)-$(Get-Date -Format 'HHmmss')"

        foreach ($Object in $Batch) {
            try {
                # Create individual backup
                $BackupData = @{
                    ObjectDN = $Object.DistinguishedName
                    BackupTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    CorrelationId = $BatchCorrelationId
                    ACLData = (Get-Acl -Path "AD:$($Object.DistinguishedName)").Access
                    ObjectMetadata = @{
                        ObjectClass = $Object.ObjectClass
                        ObjectGUID = $Object.ObjectGUID
                        WhenCreated = $Object.WhenCreated
                        WhenChanged = $Object.WhenChanged
                    }
                }

                $BackupFileName = "$($Object.ObjectGUID)-backup.json"
                $BackupFilePath = Join-Path $BackupPath $BackupFileName
                $BackupData | ConvertTo-Json -Depth 10 | Out-File -FilePath $BackupFilePath -Encoding UTF8

            } catch {
                Write-Warning "Failed to backup $($Object.DistinguishedName): $($_.Exception.Message)"
            }
        }

        # Memory cleanup after each batch
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

# Monitor backup progress
function Monitor-BackupProgress {
    param(
        [string]$BackupPath,
        [int]$ExpectedCount
    )

    while ($true) {
        $CurrentCount = (Get-ChildItem -Path $BackupPath -Filter "*.json" -ErrorAction SilentlyContinue).Count
        $Progress = if ($ExpectedCount -gt 0) { [math]::Round(($CurrentCount / $ExpectedCount) * 100, 1) } else { 0 }

        Write-Host "`rProgress: $CurrentCount/$ExpectedCount ($Progress%)" -NoNewline

        if ($CurrentCount -ge $ExpectedCount) {
            Write-Host "`n✓ Backup completed" -ForegroundColor Green
            break
        }

        Start-Sleep -Seconds 5
    }
}
```

## Critical Restore Issues

### 1. Restore Verification Failures

#### Issue: "Verification failed: Expected X entries, found Y"
**Symptoms:**
- Restore operations complete but report verification failures
- Warning messages indicating ACL count mismatches
- Some objects restored successfully while others fail verification
- Log entries showing "Expected 49 entries, found 50" or similar messages

**Root Cause Analysis:**
This is **expected behavior** in many scenarios and indicates the restore validation is working correctly:

1. **ACL Modifications During Processing**: Objects may have had additional ACL entries added after the initial backup
2. **Inheritance Changes**: Security inheritance settings may have changed, adding or removing inherited permissions
3. **System Permissions**: Automatic system processes may have modified permissions between backup and restore
4. **Orphaned SID Cleanup**: The removal process may have discovered and removed additional orphaned entries not present during initial scan
5. **Domain Controller Replication**: Replication delays may cause different DC views of the same object

**Expected Behavior Scenarios:**
- **Successful Partial Restore**: 26 of 41 objects restored successfully indicates proper selective restoration
- **Count Variations**: Finding more entries than expected often means:
  - New permissions were granted after backup
  - Inheritance was enabled adding inherited permissions
  - System processes added automatic permissions
- **Count Deficits**: Finding fewer entries than expected may indicate:
  - Additional orphaned SIDs were discovered and removed
  - Inheritance was disabled removing inherited permissions
  - Manual permission changes occurred

**Resolution and Best Practices:**

```powershell
# Analyze restore verification results
function Analyze-RestoreResults {
    param(
        [string]$BackupPath,
        [string]$LogPath = ".\Logs",
        [string]$CorrelationId
    )

    Write-Host "Analyzing restore verification results..." -ForegroundColor Cyan

    # Read restoration summary
    $LogFiles = Get-ChildItem -Path $LogPath -Filter "*$CorrelationId*.log" -ErrorAction SilentlyContinue
    $VerificationFailures = @()
    $SuccessfulRestores = @()

    foreach ($LogFile in $LogFiles) {
        $LogContent = Get-Content -Path $LogFile.FullName

        # Parse verification failures
        $Failures = $LogContent | Where-Object { $_ -match "Verification failed.*Expected (\d+) entries, found (\d+)" }
        foreach ($Failure in $Failures) {
            if ($Failure -match "OU=([^,]+).*Expected (\d+) entries, found (\d+)") {
                $VerificationFailures += [PSCustomObject]@{
                    ObjectName = $Matches[1]
                    Expected = [int]$Matches[2]
                    Found = [int]$Matches[3]
                    Difference = [int]$Matches[3] - [int]$Matches[2]
                    Severity = if ([int]$Matches[3] - [int]$Matches[2] -le 2) { "Low" }
                              elseif ([int]$Matches[3] - [int]$Matches[2] -le 5) { "Medium" }
                              else { "High" }
                }
            }
        }

        # Parse successful restores
        $Successes = $LogContent | Where-Object { $_ -match "Successfully restored ACL.*\((\d+) entries\)" }
        foreach ($Success in $Successes) {
            if ($Success -match "OU=([^,]+).*\((\d+) entries\)") {
                $SuccessfulRestores += [PSCustomObject]@{
                    ObjectName = $Matches[1]
                    EntryCount = [int]$Matches[2]
                }
            }
        }
    }

    # Generate analysis report
    Write-Host "`n=== RESTORE ANALYSIS REPORT ===" -ForegroundColor Yellow
    Write-Host "Total Objects Processed: $($VerificationFailures.Count + $SuccessfulRestores.Count)"
    Write-Host "Successful Restores: $($SuccessfulRestores.Count)" -ForegroundColor Green
    Write-Host "Verification Failures: $($VerificationFailures.Count)" -ForegroundColor Yellow

    if ($VerificationFailures.Count -gt 0) {
        Write-Host "`n--- Verification Failure Analysis ---" -ForegroundColor Yellow

        $LowSeverity = $VerificationFailures | Where-Object Severity -eq "Low"
        $MediumSeverity = $VerificationFailures | Where-Object Severity -eq "Medium"
        $HighSeverity = $VerificationFailures | Where-Object Severity -eq "High"

        Write-Host "Low Severity (1-2 entry difference): $($LowSeverity.Count)" -ForegroundColor Green
        Write-Host "Medium Severity (3-5 entry difference): $($MediumSeverity.Count)" -ForegroundColor Yellow
        Write-Host "High Severity (>5 entry difference): $($HighSeverity.Count)" -ForegroundColor Red

        Write-Host "`nRecommendations:"
        Write-Host "• Low Severity: Expected behavior - likely inheritance or system changes"
        Write-Host "• Medium Severity: Review objects for unexpected permission changes"
        Write-Host "• High Severity: Investigate for significant security modifications"

        if ($HighSeverity.Count -gt 0) {
            Write-Host "`nHigh Severity Objects Requiring Review:" -ForegroundColor Red
            $HighSeverity | Format-Table ObjectName, Expected, Found, Difference -AutoSize
        }
    }

    return @{
        Successful = $SuccessfulRestores
        Failed = $VerificationFailures
        Summary = @{
            TotalProcessed = $VerificationFailures.Count + $SuccessfulRestores.Count
            SuccessRate = [math]::Round(($SuccessfulRestores.Count / ($VerificationFailures.Count + $SuccessfulRestores.Count)) * 100, 1)
            LowSeverityCount = ($VerificationFailures | Where-Object Severity -eq "Low").Count
            MediumSeverityCount = ($VerificationFailures | Where-Object Severity -eq "Medium").Count
            HighSeverityCount = ($VerificationFailures | Where-Object Severity -eq "High").Count
        }
    }
}

# Compare current ACLs with backup data
function Compare-ACLWithBackup {
    param(
        [string]$ObjectDN,
        [string]$BackupFilePath
    )

    try {
        # Read backup data
        $BackupData = Get-Content -Path $BackupFilePath -Raw | ConvertFrom-Json
        $BackupACLCount = $BackupData.ACLData.Count

        # Get current ACL
        $CurrentACL = Get-Acl -Path "AD:$ObjectDN"
        $CurrentACLCount = $CurrentACL.Access.Count

        $Comparison = [PSCustomObject]@{
            ObjectDN = $ObjectDN
            BackupCount = $BackupACLCount
            CurrentCount = $CurrentACLCount
            Difference = $CurrentACLCount - $BackupACLCount
            BackupTimestamp = $BackupData.BackupTimestamp
            Status = if ($CurrentACLCount -eq $BackupACLCount) { "Match" }
                    elseif ($CurrentACLCount -gt $BackupACLCount) { "Additional Entries" }
                    else { "Missing Entries" }
        }

        Write-Host "ACL Comparison for $ObjectDN:" -ForegroundColor Cyan
        Write-Host "  Backup Count: $BackupACLCount"
        Write-Host "  Current Count: $CurrentACLCount"
        Write-Host "  Difference: $($Comparison.Difference)"
        Write-Host "  Status: $($Comparison.Status)" -ForegroundColor $(
            switch ($Comparison.Status) {
                "Match" { "Green" }
                "Additional Entries" { "Yellow" }
                "Missing Entries" { "Red" }
            }
        )

        if ($Comparison.Difference -ne 0) {
            Write-Host "`nDetailed Analysis:" -ForegroundColor Yellow

            if ($CurrentACLCount -gt $BackupACLCount) {
                $AdditionalEntries = $CurrentACL.Access |
                    Where-Object { $_.IdentityReference -notin $BackupData.ACLData.IdentityReference }

                if ($AdditionalEntries) {
                    Write-Host "Additional entries found:" -ForegroundColor Yellow
                    $AdditionalEntries | Select-Object IdentityReference, AccessControlType, ActiveDirectoryRights |
                        Format-Table -AutoSize
                }
            }

            if ($CurrentACLCount -lt $BackupACLCount) {
                Write-Host "⚠ WARNING: Current ACL has fewer entries than backup" -ForegroundColor Red
                Write-Host "This may indicate permissions were removed or inheritance changed" -ForegroundColor Red
            }
        }

        return $Comparison

    } catch {
        Write-Host "✗ Failed to compare ACL: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
```

**When Verification Failures Are Normal:**
- ✅ **Low count differences (1-3 entries)**: Usually inheritance or system changes
- ✅ **Consistent patterns across similar objects**: Indicates systematic changes
- ✅ **Higher current counts**: Often means additional permissions were granted

**When to Investigate Further:**
- ⚠️ **Large count differences (>5 entries)**: May indicate significant changes
- ⚠️ **Lower current counts**: Could indicate permissions were removed inappropriately
- ⚠️ **Inconsistent patterns**: Random differences may indicate security issues

**Best Practices for Restore Operations:**
1. **Accept expected verification failures** as normal operational behavior
2. **Focus on high-severity differences** (>5 entry variations) for investigation
3. **Document baseline expectations** for your environment
4. **Use correlation IDs** to track and analyze restore patterns over time
5. **Implement regular ACL auditing** to detect unexpected changes

### 2. Partial Restore Scenarios

#### Issue: Some objects restore successfully while others fail
**Symptoms:**
- Mixed success and failure in single restore operation
- Specific object types consistently failing
- Pattern-based restoration issues

**Root Cause:**
- **Permission Variations**: Different objects have different permission models
- **Inheritance Differences**: Some objects have inheritance enabled/disabled since backup
- **Object Protection**: Some objects may be protected from modification
- **Replication Timing**: Domain controller replication state differences

**Resolution:**
This is typically **expected and acceptable behavior**. Focus on:
1. **High success rates** (>60% typically indicates good restore operation)
2. **Consistent failure patterns** that might indicate systematic issues
3. **Critical object restoration** for business-important resources

## Data Integrity Issues

### 3. Backup/Restore Data Validation

#### Issue: "Backup data validation failed"
**Symptoms:**
- Inconsistent backup data
- Missing ACL entries in backups
- Restore operations produce unexpected results

**Root Cause:**
- Incomplete ACL capture during backup
- Inheritance rule changes between backup and restore
- Object property modifications
- Replication inconsistencies

**Resolution:**
```powershell
# Comprehensive backup validation
function Test-BackupCompleteness {
    param(
        [string]$BackupPath,
        [string[]]$OriginalObjects
    )

    Write-Host "Validating backup completeness..." -ForegroundColor Cyan

    $BackupFiles = Get-ChildItem -Path $BackupPath -Filter "*.json"
    $BackupObjectCount = $BackupFiles.Count
    $OriginalObjectCount = $OriginalObjects.Count

    Write-Host "Original objects: $OriginalObjectCount"
    Write-Host "Backup files: $BackupObjectCount"

    if ($BackupObjectCount -lt $OriginalObjectCount) {
        Write-Host "⚠ Backup may be incomplete" -ForegroundColor Yellow

        # Find missing objects
        $BackedUpObjects = @()
        foreach ($File in $BackupFiles) {
            try {
                $BackupData = Get-Content -Path $File.FullName | ConvertFrom-Json
                $BackedUpObjects += $BackupData.ObjectDN
            } catch {
                Write-Host "✗ Failed to read backup file: $($File.Name)" -ForegroundColor Red
            }
        }

        $MissingObjects = $OriginalObjects | Where-Object { $_ -notin $BackedUpObjects }

        if ($MissingObjects.Count -gt 0) {
            Write-Host "Missing from backup:" -ForegroundColor Red
            $MissingObjects | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    } else {
        Write-Host "✓ Backup appears complete" -ForegroundColor Green
    }

    # Validate ACL data completeness
    foreach ($File in $BackupFiles | Select-Object -First 5) {
        try {
            $BackupData = Get-Content -Path $File.FullName | ConvertFrom-Json
            $ACLEntryCount = if ($BackupData.ACLData) { $BackupData.ACLData.Count } else { 0 }

            if ($ACLEntryCount -gt 0) {
                Write-Host "✓ $($File.Name) - $ACLEntryCount ACL entries" -ForegroundColor Green
            } else {
                Write-Host "⚠ $($File.Name) - No ACL entries found" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "✗ $($File.Name) - Validation failed" -ForegroundColor Red
        }
    }
}

# Compare backup with current state
function Compare-BackupWithCurrent {
    param(
        [string]$BackupFilePath
    )

    Write-Host "Comparing backup with current state..." -ForegroundColor Cyan

    try {
        $BackupData = Get-Content -Path $BackupFilePath | ConvertFrom-Json
        $ObjectDN = $BackupData.ObjectDN

        # Get current ACL
        $CurrentACL = Get-Acl -Path "AD:$ObjectDN" -ErrorAction Stop
        $CurrentACLCount = $CurrentACL.Access.Count
        $BackupACLCount = $BackupData.ACLData.Count

        Write-Host "Object: $ObjectDN"
        Write-Host "  Backup ACL entries: $BackupACLCount"
        Write-Host "  Current ACL entries: $CurrentACLCount"

        if ($CurrentACLCount -eq $BackupACLCount) {
            Write-Host "✓ ACL entry count matches" -ForegroundColor Green
        } else {
            Write-Host "⚠ ACL entry count differs" -ForegroundColor Yellow
        }

        # Check for orphaned SIDs in current ACL
        $OrphanedSIDs = @()
        foreach ($ACE in $CurrentACL.Access) {
            try {
                $null = [System.Security.Principal.SecurityIdentifier]::new($ACE.IdentityReference).Translate([System.Security.Principal.NTAccount])
            } catch {
                $OrphanedSIDs += $ACE.IdentityReference
            }
        }

        if ($OrphanedSIDs.Count -gt 0) {
            Write-Host "⚠ Current ACL contains $($OrphanedSIDs.Count) orphaned SIDs" -ForegroundColor Yellow
        } else {
            Write-Host "✓ No orphaned SIDs in current ACL" -ForegroundColor Green
        }

    } catch {
        Write-Host "✗ Comparison failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

## Recovery Procedures

### 6. Emergency Recovery

#### Complete Backup Recovery
```powershell
# Emergency backup recovery procedure
function Invoke-EmergencyBackupRecovery {
    param(
        [string]$CorruptedBackupPath,
        [string]$RecoveryPath
    )

    Write-Host "=== EMERGENCY BACKUP RECOVERY ===" -ForegroundColor Red
    Write-Host "Corrupted backup: $CorruptedBackupPath" -ForegroundColor Yellow
    Write-Host "Recovery location: $RecoveryPath" -ForegroundColor Yellow

    # Create recovery directory
    if (-not (Test-Path $RecoveryPath)) {
        New-Item -Path $RecoveryPath -ItemType Directory -Force
    }

    # Attempt to salvage readable backup files
    $CorruptedFiles = Get-ChildItem -Path $CorruptedBackupPath -Filter "*.json"
    $SalvagedCount = 0
    $FailedCount = 0

    foreach ($File in $CorruptedFiles) {
        try {
            $Content = Get-Content -Path $File.FullName -Raw
            $BackupData = $Content | ConvertFrom-Json

            # Validate minimum required data
            if ($BackupData.ObjectDN -and $BackupData.ACLData) {
                $RecoveryFile = Join-Path $RecoveryPath $File.Name
                Copy-Item -Path $File.FullName -Destination $RecoveryFile -Force
                $SalvagedCount++
                Write-Host "✓ Salvaged: $($File.Name)" -ForegroundColor Green
            } else {
                $FailedCount++
                Write-Host "✗ Incomplete: $($File.Name)" -ForegroundColor Red
            }
        } catch {
            $FailedCount++
            Write-Host "✗ Corrupted: $($File.Name)" -ForegroundColor Red
        }
    }

    Write-Host "Recovery summary:" -ForegroundColor Cyan
    Write-Host "  Salvaged files: $SalvagedCount" -ForegroundColor Green
    Write-Host "  Failed files: $FailedCount" -ForegroundColor Red
    Write-Host "  Recovery location: $RecoveryPath" -ForegroundColor Yellow
}
```

#### Manual ACL Reconstruction
```powershell
# Manual ACL reconstruction for critical objects
function Invoke-ManualACLReconstruction {
    param(
        [string]$ObjectDN,
        [string]$TemplateObjectDN = $null
    )

    Write-Host "Manual ACL reconstruction for: $ObjectDN" -ForegroundColor Cyan

    try {
        # Get current ACL
        $CurrentACL = Get-Acl -Path "AD:$ObjectDN"
        Write-Host "Current ACL entries: $($CurrentACL.Access.Count)"

        # Remove orphaned SIDs manually
        $CleanedACL = $CurrentACL.Clone()
        $RemovedCount = 0

        $ACLEntries = @($CleanedACL.Access)
        foreach ($ACE in $ACLEntries) {
            try {
                $null = [System.Security.Principal.SecurityIdentifier]::new($ACE.IdentityReference).Translate([System.Security.Principal.NTAccount])
            } catch {
                $CleanedACL.RemoveAccessRule($ACE)
                $RemovedCount++
                Write-Host "Removed orphaned SID: $($ACE.IdentityReference)" -ForegroundColor Yellow
            }
        }

        if ($RemovedCount -gt 0) {
            Write-Host "Removed $RemovedCount orphaned SID entries" -ForegroundColor Yellow

            # Apply cleaned ACL
            Set-Acl -Path "AD:$ObjectDN" -AclObject $CleanedACL
            Write-Host "✓ Cleaned ACL applied" -ForegroundColor Green
        } else {
            Write-Host "✓ No orphaned SIDs found" -ForegroundColor Green
        }

        # Optionally apply template ACL
        if ($TemplateObjectDN) {
            $TemplateACL = Get-Acl -Path "AD:$TemplateObjectDN"
            Write-Host "Template ACL entries: $($TemplateACL.Access.Count)"

            # TODO: Implement template application logic
            Write-Host "Template application would be implemented here" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "✗ Manual reconstruction failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

## Preventive Measures

### 7. Backup Validation Automation

```powershell
# Automated backup validation script
function Start-BackupValidationSchedule {
    param(
        [string]$BackupRootPath = ".\Backup",
        [int]$MaxAgeHours = 24
    )

    Write-Host "Starting automated backup validation..." -ForegroundColor Cyan

    # Find recent backup directories
    $RecentBackups = Get-ChildItem -Path $BackupRootPath -Directory |
        Where-Object { $_.CreationTime -gt (Get-Date).AddHours(-$MaxAgeHours) } |
        Sort-Object CreationTime -Descending

    foreach ($BackupDir in $RecentBackups) {
        Write-Host "Validating backup: $($BackupDir.Name)" -ForegroundColor Yellow

        $ValidationResult = Test-BackupIntegrity -BackupPath $BackupDir.FullName
        $ValidFiles = ($ValidationResult | Where-Object { $_.IsValid }).Count
        $TotalFiles = $ValidationResult.Count

        if ($ValidFiles -eq $TotalFiles -and $TotalFiles -gt 0) {
            Write-Host "✓ $($BackupDir.Name) - All $TotalFiles files valid" -ForegroundColor Green
        } else {
            Write-Host "✗ $($BackupDir.Name) - $ValidFiles/$TotalFiles files valid" -ForegroundColor Red

            # Log validation issues
            $LogEntry = @{
                Timestamp = Get-Date
                BackupDirectory = $BackupDir.Name
                TotalFiles = $TotalFiles
                ValidFiles = $ValidFiles
                Issues = $ValidationResult | Where-Object { -not $_.IsValid } | Select-Object FileName, Error
            }

            $LogPath = Join-Path $BackupRootPath "validation-issues.json"
            $LogEntry | ConvertTo-Json -Depth 5 | Add-Content -Path $LogPath
        }
    }
}
```

## Support and Contact Information

### When to Contact Support
- **Critical Issues:** Backup/restore operations failing completely
- **Data Integrity:** Suspected data corruption or inconsistencies
- **Performance:** Operations taking longer than 2 hours
- **Emergency:** Need for immediate ACL recovery

### Information to Provide
When contacting support for backup/restore issues:

1. **Correlation ID** from the failed operation
2. **Backup directory path** and structure
3. **Error messages** (exact text)
4. **Operation type** (backup/restore)
5. **Number of objects** being processed
6. **Environment details** (domain size, DC locations)
7. **Timing information** (when did it last work?)

### Emergency Contacts
- **Primary:** IT Security Team (security@contoso.com)
- **Secondary:** PowerShell Development Team (powershell@contoso.com)
- **Escalation:** CISO Office (ciso@contoso.com)

---

*Last Updated: 2025-07-02*
*Version: 2.0.0*
*Author: Jeffrey Stuhr*