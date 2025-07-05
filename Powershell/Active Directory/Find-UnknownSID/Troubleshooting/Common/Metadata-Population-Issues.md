# Metadata Population Issues - Troubleshooting Guide

## Overview
This guide addresses issues related to metadata population in SID analysis result objects, focusing on timestamp accuracy, processing metrics, and audit trail completeness.

## Common Issues

### 1. Timestamp Issues

#### Issue: Inconsistent Timestamps
**Symptoms:**
- Timestamps showing different time zones within same processing run
- Timestamps appearing in the future or significantly in the past
- Timestamp format inconsistencies across result objects

**Root Causes:**
- Mixed use of local time vs UTC
- System clock synchronization issues
- Time zone configuration problems
- Daylight saving time transitions

**Resolution Steps:**
1. **Standardize on UTC:**
   ```powershell
   # Always use UTC for consistent timestamps
   $timestamp = [DateTime]::UtcNow

   # Verify UTC usage
   if ($timestamp.Kind -ne [DateTimeKind]::Utc) {
       Write-Warning "Timestamp is not UTC: $($timestamp.Kind)"
   }
   ```

2. **Validate System Clock:**
   ```powershell
   # Check system time accuracy
   $systemTime = Get-Date
   $utcTime = [DateTime]::UtcNow
   $localToUtcDiff = ($systemTime - $utcTime.ToLocalTime()).TotalSeconds

   if ([Math]::Abs($localToUtcDiff) -gt 5) {
       Write-Warning "System clock may be inaccurate. Difference: $localToUtcDiff seconds"
   }
   ```

3. **Test Time Zone Configuration:**
   ```powershell
   # Verify time zone settings
   $timeZone = Get-TimeZone
   Write-Verbose "Current time zone: $($timeZone.DisplayName)"
   Write-Verbose "UTC offset: $($timeZone.BaseUtcOffset)"

   # Check for daylight saving time
   if ($timeZone.SupportsDaylightSavingTime) {
       $isDST = $timeZone.IsDaylightSavingTime((Get-Date))
       Write-Verbose "Daylight saving time active: $isDST"
   }
   ```

#### Issue: Missing or Null Timestamps
**Symptoms:**
- Timestamp properties contain null values
- Creation time not recorded for result objects
- Audit trail incomplete due to missing time information

**Root Causes:**
- Exception during timestamp generation
- Memory pressure preventing DateTime creation
- Incorrect property initialization order

**Resolution Steps:**
1. **Implement Defensive Timestamp Creation:**
   ```powershell
   # Safe timestamp creation with fallback
   try {
       $timestamp = [DateTime]::UtcNow
   }
   catch {
       Write-Warning "Failed to get current time, using fallback"
       $timestamp = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
   }

   # Validate timestamp before use
   if ($timestamp -eq [DateTime]::MinValue) {
       $timestamp = [DateTime]::UtcNow
   }
   ```

2. **Monitor Memory Pressure:**
   ```powershell
   # Check memory before timestamp operations
   $availableMemory = Get-MemoryStatistics
   if ($availableMemory.AvailableMemoryMB -lt 50) {
       Write-Warning "Low memory may affect timestamp creation"
       Invoke-GarbageCollection -Force
   }
   ```

### 2. Processing Metrics Issues

#### Issue: Inaccurate Processing Time
**Symptoms:**
- Processing time showing as zero or negative values
- Inconsistent timing measurements
- Performance metrics don't match actual processing time

**Root Causes:**
- Stopwatch not started or stopped correctly
- Timer overflow with very long operations
- System performance counter issues

**Resolution Steps:**
1. **Validate Stopwatch Usage:**
   ```powershell
   # Proper stopwatch implementation
   $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

   try {
       # Processing logic here
       Start-Sleep -Milliseconds 10  # Simulate work
   }
   finally {
       $stopwatch.Stop()

       # Validate timing result
       if ($stopwatch.ElapsedMilliseconds -lt 0) {
           Write-Warning "Invalid negative processing time detected"
           $processingTime = [TimeSpan]::Zero
       }
       else {
           $processingTime = $stopwatch.Elapsed
       }
   }
   ```

2. **Handle Timer Overflow:**
   ```powershell
   # Check for timer overflow (operations > 24 days)
   if ($stopwatch.Elapsed.TotalDays -gt 24) {
       Write-Warning "Processing time overflow detected, using maximum value"
       $processingTime = [TimeSpan]::FromDays(24)
   }
   ```

3. **Test Performance Counter Access:**
   ```powershell
   # Verify performance counter functionality
   try {
       $testStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
       Start-Sleep -Milliseconds 1
       $testStopwatch.Stop()

       if ($testStopwatch.ElapsedMilliseconds -eq 0) {
           Write-Warning "Performance counters may not be working correctly"
       }
   }
   catch {
       Write-Error "Performance counter access failed: $($_.Exception.Message)"
   }
   ```

#### Issue: Memory Statistics Collection Failures
**Symptoms:**
- Memory usage metrics showing as zero or null
- Memory statistics not updated during processing
- Out of memory errors despite showing available memory

**Root Causes:**
- WMI service issues preventing memory queries
- Insufficient permissions for performance counter access
- Memory pressure causing query failures

**Resolution Steps:**
1. **Test WMI Connectivity:**
   ```powershell
   # Verify WMI service availability
   try {
       $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
       $totalMemory = [Math]::Round($os.TotalVisibleMemorySize / 1024, 0)
       Write-Verbose "Total system memory: $totalMemory MB"
   }
   catch {
       Write-Error "WMI query failed: $($_.Exception.Message)"
   }
   ```

2. **Check Performance Counter Permissions:**
   ```powershell
   # Test performance counter access
   try {
       $process = Get-Process -Name "powershell" | Select-Object -First 1
       $workingSet = $process.WorkingSet64
       Write-Verbose "Current process memory: $([Math]::Round($workingSet / 1MB, 2)) MB"
   }
   catch {
       Write-Warning "Cannot access process memory information: $($_.Exception.Message)"
   }
   ```

3. **Implement Fallback Memory Detection:**
   ```powershell
   # Fallback memory detection methods
   try {
       # Primary method: WMI
       $memInfo = Get-CimInstance Win32_OperatingSystem
       $availableMemory = [Math]::Round($memInfo.FreePhysicalMemory / 1024, 0)
   }
   catch {
       try {
           # Fallback method: .NET GC
           $gcMemory = [System.GC]::GetTotalMemory($false)
           $availableMemory = [Math]::Round((2GB - $gcMemory) / 1MB, 0)  # Estimate
           Write-Warning "Using estimated memory values"
       }
       catch {
           Write-Error "All memory detection methods failed"
           $availableMemory = 0
       }
   }
   ```

### 3. Correlation ID Issues

#### Issue: Duplicate Correlation IDs
**Symptoms:**
- Multiple result objects sharing the same correlation ID
- Difficulty tracing individual processing operations
- Audit trail confusion

**Root Causes:**
- GUID generation not called for each object
- Correlation ID being reused across objects
- Threading issues with shared correlation ID

**Resolution Steps:**
1. **Ensure Unique ID Generation:**
   ```powershell
   # Generate unique ID for each result
   function New-UniqueCorrelationId {
       $guid = [System.Guid]::NewGuid()
       $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
       return "$timestamp-$($guid.ToString('N').Substring(0, 8))"
   }

   # Validate uniqueness
   $correlationId = New-UniqueCorrelationId
   if ([string]::IsNullOrEmpty($correlationId)) {
       throw "Failed to generate correlation ID"
   }
   ```

2. **Test GUID Generation:**
   ```powershell
   # Verify GUID generation is working
   $testGuids = 1..100 | ForEach-Object { [System.Guid]::NewGuid() }
   $uniqueGuids = $testGuids | Select-Object -Unique

   if ($testGuids.Count -ne $uniqueGuids.Count) {
       Write-Error "GUID generation producing duplicates"
   }
   ```

3. **Implement Thread-Safe ID Generation:**
   ```powershell
   # Thread-safe correlation ID generation
   $script:correlationIdCounter = 0
   $script:correlationIdLock = [object]::new()

   function Get-ThreadSafeCorrelationId {
       [System.Threading.Monitor]::Enter($script:correlationIdLock)
       try {
           $counter = ++$script:correlationIdCounter
           $guid = [System.Guid]::NewGuid()
           return "$counter-$($guid.ToString('N').Substring(0, 12))"
       }
       finally {
           [System.Threading.Monitor]::Exit($script:correlationIdLock)
       }
   }
   ```

#### Issue: Correlation ID Format Issues
**Symptoms:**
- Correlation IDs containing invalid characters
- Inconsistent ID formats across processing runs
- Log parsing failures due to format variations

**Root Causes:**
- Manual ID construction introducing errors
- Character encoding issues
- Format changes between script versions

**Resolution Steps:**
1. **Standardize ID Format:**
   ```powershell
   # Standard correlation ID format
   function New-StandardCorrelationId {
       param(
           [string]$Prefix = "SID"
       )

       $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
       $guid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpper()

       return "$Prefix-$timestamp-$guid"
   }

   # Validate format
   $correlationId = New-StandardCorrelationId
   if ($correlationId -notmatch '^[A-Z]+-\d{14}-[A-F0-9]{8}$') {
       Write-Error "Invalid correlation ID format: $correlationId"
   }
   ```

2. **Implement Format Validation:**
   ```powershell
   # Validate correlation ID format
   function Test-CorrelationIdFormat {
       param([string]$CorrelationId)

       # Expected format: PREFIX-YYYYMMDDHHMMSS-HEXSTRING
       $pattern = '^[A-Z]+-\d{14}-[A-F0-9]{8}$'

       if ($CorrelationId -match $pattern) {
           return $true
       }
       else {
           Write-Warning "Invalid correlation ID format: $CorrelationId"
           return $false
       }
   }
   ```

## Validation Commands

### Test Timestamp Accuracy
```powershell
# Test timestamp consistency
$results = 1..10 | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = [DateTime]::UtcNow
        Index = $_
    }
    Start-Sleep -Milliseconds 10
}

# Verify timestamps are sequential and UTC
$timestamps = $results | ForEach-Object { $_.Timestamp }
$timestamps | Should -BeOrdered
$timestamps | ForEach-Object { $_.Kind | Should -Be ([DateTimeKind]::Utc) }
```

### Test Processing Time Measurement
```powershell
# Test stopwatch accuracy
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Milliseconds 100
$stopwatch.Stop()

$elapsed = $stopwatch.ElapsedMilliseconds
$elapsed | Should -BeGreaterThan 90
$elapsed | Should -BeLessThan 200
```

### Test Correlation ID Uniqueness
```powershell
# Test correlation ID uniqueness
$correlationIds = 1..1000 | ForEach-Object {
    [System.Guid]::NewGuid().ToString()
}

$uniqueIds = $correlationIds | Select-Object -Unique
$correlationIds.Count | Should -Be $uniqueIds.Count
```

## Best Practices

### 1. Timestamp Management
- Always use UTC timestamps for consistency
- Validate timestamps before using in calculations
- Implement time zone awareness for display purposes
- Monitor system clock accuracy

### 2. Processing Metrics
- Use high-resolution timers for accurate measurements
- Implement proper stopwatch lifecycle management
- Validate timing results for reasonableness
- Include performance metrics in all result objects

### 3. Correlation ID Management
- Generate unique IDs for each processing operation
- Use consistent ID format across all systems
- Implement ID validation and verification
- Include correlation IDs in all log entries

### 4. Error Handling
- Implement defensive programming for metadata creation
- Provide fallback values for critical metadata
- Log metadata population failures with context
- Validate metadata completeness before using results

## Related Documentation
- [Result Creation Issues](./Result-Creation-Issues.md)
- [Result Validation Issues](./Result-Validation-Issues.md)
- [SID Processing Orchestration Issues](./SID-Processing-Orchestration-Issues.md)
- [Memory Management Issues](../Performance/Memory-Management-Issues.md)

## Support Information
- **Module**: New-SIDResult.ps1
- **Functions**: New-OrphanedSIDResult, Set-ResultMetadata
- **Last Updated**: $(Get-Date -Format 'yyyy-MM-dd')
- **Correlation ID**: Include in all support requests for faster resolution
