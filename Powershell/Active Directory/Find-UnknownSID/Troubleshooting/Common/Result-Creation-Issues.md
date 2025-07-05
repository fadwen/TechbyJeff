# Result Creation Issues - Troubleshooting Guide

## Overview
This guide addresses common issues encountered when using the `New-SIDResult.ps1` module for creating and managing SID analysis result objects.

## Common Issues

### 1. Result Object Creation Failures

#### Issue: Result Object Creation Returns Null
**Symptoms:**
- `New-OrphanedSIDResult` returns null instead of result object
- No error messages in logs
- Processing appears to complete successfully

**Root Causes:**
- Invalid input parameters (null/empty SID or ObjectPath)
- Memory pressure preventing object creation
- Serialization issues with complex data types

**Resolution Steps:**
1. **Validate Input Parameters:**
   ```powershell
   # Check for null/empty required parameters
   if ([string]::IsNullOrWhiteSpace($SID)) {
       Write-Error "SID parameter cannot be null or empty"
   }
   if ([string]::IsNullOrWhiteSpace($ObjectPath)) {
       Write-Error "ObjectPath parameter cannot be null or empty"
   }
   ```

2. **Monitor Memory Usage:**
   ```powershell
   # Check available memory before result creation
   $memStats = Get-MemoryStatistics
   if ($memStats.AvailableMemoryMB -lt 100) {
       Invoke-GarbageCollection -Force
   }
   ```

3. **Validate Result Object:**
   ```powershell
   $result = New-OrphanedSIDResult -SID $sid -ObjectPath $path
   if ($null -eq $result) {
       Write-Error "Failed to create result object for SID: $sid"
   }
   ```

#### Issue: PSTypeName Not Set Correctly
**Symptoms:**
- Result objects don't have expected type name
- Type-based filtering doesn't work
- Custom formatting not applied

**Root Causes:**
- PSTypeName property not being set during creation
- Type name being overwritten by subsequent operations
- Incorrect type name format

**Resolution Steps:**
1. **Verify Type Name Setting:**
   ```powershell
   # Ensure PSTypeName is set correctly
   $result.PSTypeName | Should -Be 'OrphanedSIDResult'
   ```

2. **Check Type Name After Creation:**
   ```powershell
   $result = New-OrphanedSIDResult -SID $sid -ObjectPath $path
   Write-Verbose "Result type: $($result.PSTypeName)"
   ```

### 2. Property Population Issues

#### Issue: Metadata Properties Missing
**Symptoms:**
- Timestamp, ProcessingTime, or CorrelationId properties are null
- Inconsistent metadata across result objects
- Missing audit trail information

**Root Causes:**
- Clock synchronization issues causing invalid timestamps
- Performance counter failures
- Correlation ID generation failures

**Resolution Steps:**
1. **Validate System Clock:**
   ```powershell
   # Verify system time is accurate
   $systemTime = Get-Date
   Write-Verbose "System time: $systemTime"

   # Check time zone settings
   $timeZone = Get-TimeZone
   Write-Verbose "Time zone: $($timeZone.DisplayName)"
   ```

2. **Monitor Performance Counters:**
   ```powershell
   # Test performance counter access
   try {
       $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
       Start-Sleep -Milliseconds 1
       $stopwatch.Stop()
       Write-Verbose "Performance timing working: $($stopwatch.ElapsedMilliseconds)ms"
   }
   catch {
       Write-Warning "Performance counter issue: $($_.Exception.Message)"
   }
   ```

3. **Verify Correlation ID Generation:**
   ```powershell
   # Test GUID generation
   $correlationId = [System.Guid]::NewGuid().ToString()
   if ([string]::IsNullOrEmpty($correlationId)) {
       Write-Error "Failed to generate correlation ID"
   }
   ```

#### Issue: SID Properties Incomplete
**Symptoms:**
- SID property contains raw SID but translated name is missing
- Domain information not populated
- SID type information missing

**Root Causes:**
- Domain controller connectivity issues
- Insufficient permissions for SID translation
- SID format validation failures

**Resolution Steps:**
1. **Test Domain Controller Connectivity:**
   ```powershell
   # Verify domain controller access
   try {
       $dc = Get-ADDomainController -Discover
       Write-Verbose "Connected to DC: $($dc.HostName)"
   }
   catch {
       Write-Error "Cannot connect to domain controller: $($_.Exception.Message)"
   }
   ```

2. **Validate SID Format:**
   ```powershell
   # Test SID format before translation
   if (-not (Test-SIDFormat -SID $sid)) {
       Write-Error "Invalid SID format: $sid"
   }
   ```

3. **Check Translation Permissions:**
   ```powershell
   # Verify permissions for SID translation
   try {
       $testSID = [System.Security.Principal.SecurityIdentifier]::new($sid)
       $translated = $testSID.Translate([System.Security.Principal.NTAccount])
       Write-Verbose "SID translation successful: $translated"
   }
   catch [System.Security.Principal.IdentityNotMappedException] {
       Write-Verbose "SID not found in directory (expected for orphaned SIDs)"
   }
   catch {
       Write-Error "SID translation failed: $($_.Exception.Message)"
   }
   ```

### 3. Performance Issues

#### Issue: Slow Result Creation
**Symptoms:**
- High latency when creating result objects
- Memory usage increases during result creation
- Performance degrades with large datasets

**Root Causes:**
- Inefficient property population methods
- Memory fragmentation
- Synchronous operations blocking processing

**Resolution Steps:**
1. **Profile Result Creation:**
   ```powershell
   # Measure result creation performance
   $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
   $result = New-OrphanedSIDResult -SID $sid -ObjectPath $path
   $stopwatch.Stop()

   if ($stopwatch.ElapsedMilliseconds -gt 100) {
       Write-Warning "Slow result creation: $($stopwatch.ElapsedMilliseconds)ms"
   }
   ```

2. **Monitor Memory Patterns:**
   ```powershell
   # Track memory usage during result creation
   $beforeMemory = [System.GC]::GetTotalMemory($false)
   $result = New-OrphanedSIDResult -SID $sid -ObjectPath $path
   $afterMemory = [System.GC]::GetTotalMemory($false)

   $memoryDelta = $afterMemory - $beforeMemory
   if ($memoryDelta -gt 1MB) {
       Write-Warning "High memory usage for result creation: $($memoryDelta / 1MB) MB"
   }
   ```

3. **Optimize Property Population:**
   ```powershell
   # Use efficient data structures
   $properties = [ordered]@{
       SID = $sid
       ObjectPath = $path
       Timestamp = [DateTime]::UtcNow
       CorrelationId = $correlationId
   }
   $result = [PSCustomObject]$properties
   $result.PSTypeName = 'OrphanedSIDResult'
   ```

## Validation Commands

### Test Result Creation
```powershell
# Test basic result creation
$testSID = "S-1-5-21-1234567890-1234567890-1234567890-1001"
$testPath = "CN=TestObject,DC=domain,DC=com"
$result = New-OrphanedSIDResult -SID $testSID -ObjectPath $testPath

# Validate result structure
$result | Should -Not -BeNullOrEmpty
$result.PSTypeName | Should -Be 'OrphanedSIDResult'
$result.SID | Should -Be $testSID
$result.ObjectPath | Should -Be $testPath
$result.Timestamp | Should -BeOfType [DateTime]
$result.CorrelationId | Should -Not -BeNullOrEmpty
```

### Test Property Population
```powershell
# Test metadata population
$result = New-OrphanedSIDResult -SID $testSID -ObjectPath $testPath
$result.Timestamp | Should -BeGreaterThan (Get-Date).AddMinutes(-1)
$result.ProcessingTime | Should -BeOfType [TimeSpan]
[Guid]::Parse($result.CorrelationId) | Should -Not -BeNullOrEmpty
```

### Test Performance
```powershell
# Measure creation performance
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
1..100 | ForEach-Object {
    New-OrphanedSIDResult -SID $testSID -ObjectPath $testPath
}
$stopwatch.Stop()

$averageTime = $stopwatch.ElapsedMilliseconds / 100
$averageTime | Should -BeLessThan 10  # Less than 10ms per creation
```

## Best Practices

### 1. Result Creation
- Always validate input parameters before result creation
- Use correlation IDs for tracing result objects through processing pipeline
- Implement proper error handling for failed result creation
- Monitor memory usage during bulk result creation

### 2. Property Management
- Populate all required metadata during creation
- Use UTC timestamps for consistency across time zones
- Validate property types and formats
- Implement property change tracking for audit purposes

### 3. Performance Optimization
- Create results in batches to reduce overhead
- Use efficient data structures for property population
- Implement object pooling for high-volume scenarios
- Monitor and profile result creation performance

### 4. Error Handling
- Implement comprehensive validation for all input parameters
- Use structured error reporting with correlation IDs
- Log detailed error information for troubleshooting
- Provide meaningful error messages for common failure scenarios

## Related Documentation
- [Metadata Population Issues](./Metadata-Population-Issues.md)
- [Result Validation Issues](./Result-Validation-Issues.md)
- [SID Processing Orchestration Issues](./SID-Processing-Orchestration-Issues.md)
- [Memory Management Issues](../Performance/Memory-Management-Issues.md)

## Support Information
- **Module**: New-SIDResult.ps1
- **Function**: New-OrphanedSIDResult
- **Last Updated**: $(Get-Date -Format 'yyyy-MM-dd')
- **Correlation ID**: Include in all support requests for faster resolution
