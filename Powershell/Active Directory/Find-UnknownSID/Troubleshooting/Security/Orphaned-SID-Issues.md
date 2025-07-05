# Orphaned SID Detection Troubleshooting Guide

## Overview

This guide provides troubleshooting information for the `Test-OrphanedSID.ps1` module, which handles orphaned SID detection and cache management for the Find-UnknownSID solution.

## Common Issues

### 1. False Positives - Valid SIDs Marked as Orphaned

**Symptoms:**
- Valid Active Directory accounts showing as orphaned
- Recently created accounts not being found
- Service accounts incorrectly marked as orphaned

**Causes:**
- Active Directory replication delays
- Permissions issues preventing AD object lookup
- Network connectivity problems to domain controllers
- Caching of stale data

**Solutions:**

```powershell
# Clear cache and retry for suspected false positives
Clear-SIDValidationCache
$result = Test-OrphanedSID -SID "S-1-5-21-1234567890-1234567890-1234567890-1001"

# Manual verification steps
$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"

# Test 1: Direct AD lookup
try {
    $adObject = Get-ADObject -Filter "objectSid -eq '$testSID'" -ErrorAction Stop
    Write-Output "Found AD Object: $($adObject.DistinguishedName)"
} catch {
    Write-Output "AD Object not found: $($_.Exception.Message)"
}

# Test 2: SecurityIdentifier translation
try {
    $sid = [System.Security.Principal.SecurityIdentifier]::new($testSID)
    $account = $sid.Translate([System.Security.Principal.NTAccount])
    Write-Output "Account Name: $($account.Value)"
} catch {
    Write-Output "Translation failed: $($_.Exception.Message)"
}

# Test 3: Specific object type lookups
$objectTypes = @('Get-ADUser', 'Get-ADGroup', 'Get-ADComputer')
foreach ($cmdlet in $objectTypes) {
    try {
        $result = & $cmdlet -Filter "SID -eq '$testSID'" -ErrorAction Stop
        if ($result) {
            Write-Output "$cmdlet found: $($result.DistinguishedName)"
        }
    } catch {
        Write-Output "$cmdlet failed: $($_.Exception.Message)"
    }
}
```

**Prevention:**
- Ensure proper AD permissions for the service account
- Check AD replication status before large operations
- Use correlation IDs to track specific SID validation issues

### 2. False Negatives - Orphaned SIDs Marked as Valid

**Symptoms:**
- Deleted accounts still showing as valid
- Disabled accounts not being detected as orphaned
- Foreign domain SIDs incorrectly validated

**Causes:**
- Cached validation results for deleted accounts
- Deleted objects still present in AD (not purged)
- Trust relationships allowing foreign SID validation

**Solutions:**

```powershell
# Force fresh validation
Clear-SIDValidationCache

# Check for deleted objects specifically
$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"
try {
    $deletedObject = Get-ADObject -Filter "objectSid -eq '$testSID'" -IncludeDeletedObjects -ErrorAction Stop
    if ($deletedObject) {
        Write-Output "Found in deleted objects: $($deletedObject.DistinguishedName)"
        Write-Output "Deleted: $($deletedObject.Deleted)"
        Write-Output "IsDeleted: $($deletedObject.isDeleted)"
    }
} catch {
    Write-Output "Not found in deleted objects: $($_.Exception.Message)"
}

# Check account status if found
try {
    $user = Get-ADUser -Filter "SID -eq '$testSID'" -Properties Enabled -ErrorAction Stop
    Write-Output "User found - Enabled: $($user.Enabled)"
} catch {
    Write-Output "User not found or not a user object"
}
```

**Configuration Check:**
```powershell
# Verify deleted object handling
$deletedObjectsLifetime = (Get-ADObject -SearchBase ((Get-ADRootDSE).configurationNamingContext) -Filter "cn -eq 'Directory Service'" -Properties deletedObjectLifetime).deletedObjectLifetime
Write-Output "Deleted Objects Lifetime: $deletedObjectsLifetime days"
```

### 3. Performance Issues

**Symptoms:**
- Slow SID validation operations
- High CPU usage during batch processing
- Memory growth during large operations
- Timeouts on AD operations

**Causes:**
- Large cache size consuming memory
- Inefficient AD queries
- Network latency to domain controllers
- Insufficient batch processing

**Solutions:**

```powershell
# Monitor cache performance
$stats = Get-SIDValidationCacheStat
Write-Output "Cache Statistics:"
Write-Output "  Total Entries: $($stats.TotalEntries)"
Write-Output "  Cache Hit Ratio: $($stats.CacheHitRatio)%"
Write-Output "  Orphaned SIDs: $($stats.OrphanedSIDs)"
Write-Output "  Valid SIDs: $($stats.ValidSIDs)"

# Performance testing
$testSIDs = @()
for ($i = 1000; $i -lt 1100; $i++) {
    $testSIDs += "S-1-5-21-1234567890-1234567890-1234567890-$i"
}

# Test with cache
Measure-Command {
    $results = $testSIDs | Test-OrphanedSID
}

# Test without cache
Clear-SIDValidationCache
Measure-Command {
    $results = $testSIDs | Test-OrphanedSID
}
```

**Optimization Strategies:**
```powershell
# Batch processing for better performance
$batchSize = 25
$allSIDs = @('SID1', 'SID2', '...')  # Your SID list
$allResults = @()

for ($i = 0; $i -lt $allSIDs.Count; $i += $batchSize) {
    $batch = $allSIDs[$i..([Math]::Min($i + $batchSize - 1, $allSIDs.Count - 1))]

    Write-Progress -Activity "Processing SIDs" -Status "Batch $([Math]::Floor($i/$batchSize) + 1)" -PercentComplete (($i / $allSIDs.Count) * 100)

    $batchResults = $batch | Test-OrphanedSID
    $allResults += $batchResults

    # Optional: Clear cache periodically to manage memory
    if ($i % 500 -eq 0) {
        Clear-SIDValidationCache
    }
}
```

### 4. Active Directory Connection Issues

**Symptoms:**
- "Unable to contact the server" errors
- Authentication failures
- Timeout errors during AD operations

**Causes:**
- Network connectivity issues
- Domain controller availability
- Authentication problems
- Firewall blocking AD traffic

**Solutions:**

```powershell
# Test AD connectivity
try {
    $domain = Get-ADDomain -Current LocalComputer
    Write-Output "Connected to domain: $($domain.DNSRoot)"
    Write-Output "Domain Controller: $($domain.PDCEmulator)"
} catch {
    Write-Output "AD connection failed: $($_.Exception.Message)"
}

# Test specific domain controller
$dcName = (Get-ADDomain).PDCEmulator
try {
    $testUser = Get-ADUser -Identity $env:USERNAME -Server $dcName
    Write-Output "Successfully connected to DC: $dcName"
} catch {
    Write-Output "Failed to connect to DC $dcName : $($_.Exception.Message)"
}

# Network connectivity test
$dcName = (Get-ADDomain).PDCEmulator
Test-NetConnection -ComputerName $dcName -Port 389  # LDAP
Test-NetConnection -ComputerName $dcName -Port 636  # LDAPS
Test-NetConnection -ComputerName $dcName -Port 3268 # Global Catalog
```

## Cache Management Issues

### 1. Memory Usage Growth

**Problem:** SID validation cache consuming excessive memory

**Solution:**
```powershell
# Monitor memory usage
$process = Get-Process -Id $PID
$beforeMemory = $process.WorkingSet64 / 1MB

# Get cache statistics
$stats = Get-SIDValidationCacheStat
Write-Output "Cache entries before cleanup: $($stats.TotalEntries)"

# Clear cache if too large
if ($stats.TotalEntries -gt 10000) {
    Clear-SIDValidationCache
    Write-Output "Cache cleared due to size: $($stats.TotalEntries) entries"
}

$afterMemory = (Get-Process -Id $PID).WorkingSet64 / 1MB
Write-Output "Memory usage: Before $($beforeMemory) MB, After $($afterMemory) MB"
```

### 2. Stale Cache Data

**Problem:** Cache contains outdated validation results

**Solution:**
```powershell
# Implement cache aging
$cacheMaxAge = [TimeSpan]::FromHours(1)
$currentTime = Get-Date

# Note: This would require cache timestamp tracking in future enhancement
# For now, use periodic clearing
Clear-SIDValidationCache
Write-Output "Cache cleared to ensure fresh data"
```

### 3. Cache Statistics Accuracy

**Problem:** Cache statistics don't match expected values

**Solution:**
```powershell
# Detailed cache analysis
$stats = Get-SIDValidationCacheStat
Write-Output "Detailed Cache Analysis:"
Write-Output "  Total Entries: $($stats.TotalEntries)"
Write-Output "  Orphaned SIDs: $($stats.OrphanedSIDs)"
Write-Output "  Valid SIDs: $($stats.ValidSIDs)"
Write-Output "  Cache Hit Ratio: $($stats.CacheHitRatio)%"

# Verify cache integrity
if ($script:SIDValidationCache) {
    $actualTotal = $script:SIDValidationCache.Count
    $actualOrphaned = ($script:SIDValidationCache.Values | Where-Object { $_ -eq $true }).Count
    $actualValid = ($script:SIDValidationCache.Values | Where-Object { $_ -eq $false }).Count

    Write-Output "Direct Cache Verification:"
    Write-Output "  Actual Total: $actualTotal"
    Write-Output "  Actual Orphaned: $actualOrphaned"
    Write-Output "  Actual Valid: $actualValid"
    Write-Output "  Calculated Total: $($actualOrphaned + $actualValid)"
}
```

## Error Messages

### "SID format invalid - treating as orphaned"

**Meaning:** The SID string failed format validation

**Resolution:**
1. Verify SID string integrity using Test-SIDFormat
2. Check data source for corruption
3. Validate SID encoding

### "SID validation cache hit for [SID]"

**Meaning:** Result returned from cache (debug message)

**Action:** Normal operation, no action needed

### "SID could not be resolved - marking as orphaned"

**Meaning:** All AD lookup methods failed to find the SID

**Resolution:**
1. Verify the SID actually exists in AD
2. Check AD connectivity and permissions
3. Consider if SID is from a different domain/forest

### "Error testing SID for orphaned status"

**Meaning:** Unexpected error during the detection process

**Resolution:**
1. Check correlation ID in logs for detailed error context
2. Verify AD module availability
3. Check system resource constraints

## Logging and Diagnostics

### Enable Debug Logging

```powershell
# Enable detailed logging for troubleshooting
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# Test with correlation tracking
$correlationId = [System.Guid]::NewGuid().ToString()
$result = Test-OrphanedSID -SID "S-1-5-21-1234567890-1234567890-1234567890-1001" -CorrelationId $correlationId -Verbose

# Search logs for correlation ID to trace the operation
```

### Cache Performance Monitoring

```powershell
# Continuous cache monitoring
$monitoringInterval = 60  # seconds
$maxIterations = 10

for ($i = 0; $i -lt $maxIterations; $i++) {
    $stats = Get-SIDValidationCacheStat
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Output "[$timestamp] Cache Stats - Total: $($stats.TotalEntries), Hit Ratio: $($stats.CacheHitRatio)%"

    Start-Sleep -Seconds $monitoringInterval
}
```

## Best Practices

### 1. Batch Processing

Process SIDs in manageable batches:

```powershell
# Recommended batch processing pattern
function Invoke-BatchOrphanedSIDTest {
    param(
        [Parameter(Mandatory)]
        [string[]]$SIDList,

        [int]$BatchSize = 50,

        [switch]$ClearCachePerBatch
    )

    $results = @{}
    $totalBatches = [Math]::Ceiling($SIDList.Count / $BatchSize)

    for ($i = 0; $i -lt $SIDList.Count; $i += $BatchSize) {
        $currentBatch = [Math]::Floor($i / $BatchSize) + 1
        $batch = $SIDList[$i..([Math]::Min($i + $BatchSize - 1, $SIDList.Count - 1))]

        Write-Progress -Activity "Testing Orphaned SIDs" -Status "Batch $currentBatch of $totalBatches" -PercentComplete (($i / $SIDList.Count) * 100)

        foreach ($sid in $batch) {
            $results[$sid] = Test-OrphanedSID -SID $sid
        }

        if ($ClearCachePerBatch) {
            Clear-SIDValidationCache
        }
    }

    Write-Progress -Activity "Testing Orphaned SIDs" -Completed
    return $results
}
```

### 2. Error Handling

Implement comprehensive error handling:

```powershell
try {
    $correlationId = [System.Guid]::NewGuid().ToString()
    $isOrphaned = Test-OrphanedSID -SID $sidString -CorrelationId $correlationId

    if ($isOrphaned) {
        Write-Warning "SID is orphaned: $sidString"
        # Handle orphaned SID appropriately
    } else {
        Write-Information "SID is valid: $sidString"
        # Continue processing
    }
} catch {
    Write-Error "Failed to test SID $sidString : $($_.Exception.Message)"
    # Log error with correlation ID for troubleshooting
}
```

### 3. Cache Management

Implement proactive cache management:

```powershell
# Regular cache maintenance
function Invoke-CacheMaintenance {
    $stats = Get-SIDValidationCacheStat

    # Clear cache if too large
    if ($stats.TotalEntries -gt 5000) {
        Write-Warning "Cache size ($($stats.TotalEntries)) exceeds threshold, clearing cache"
        Clear-SIDValidationCache
    }

    # Monitor cache efficiency
    if ($stats.TotalEntries -gt 100 -and $stats.CacheHitRatio -lt 50) {
        Write-Warning "Low cache efficiency ($($stats.CacheHitRatio)%), consider cache strategy review"
    }
}
```

## Contact Information

For additional support:
- **Author:** Jeffrey Stuhr
- **Blog:** https://www.techbyjeff.net
- **LinkedIn:** https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For urgent issues, check the main troubleshooting directory:
- `.\Troubleshooting\Common\` - General issues
- `.\Troubleshooting\Security\` - Security-specific problems
- `.\Troubleshooting\Performance\` - Performance optimization
