# Memory Management Troubleshooting

## Overview

The Find-UnknownSID script uses a sophisticated memory management architecture combining streaming result processing with aggressive garbage collection to maintain stable memory usage even in very large Active Directory environments.

## Architecture Components

### 1. StreamingResultsManager
- **Purpose**: Eliminates memory accumulation by streaming results to disk in batches
- **Batch Size**: Default 50 results per batch file
- **Memory Benefits**: Prevents unbounded growth of in-memory result collections
- **Storage**: Uses temporary JSON files in system temp directory
- **Cleanup**: Automatic disposal and optional file cleanup

### 2. MemoryManager Class
- **Purpose**: Monitors and manages system memory usage during processing
- **Check Frequency**: Every 25 operations (improved from 50)
- **Threshold Monitoring**: Configurable memory limits with automatic cleanup
- **Garbage Collection**: Aggressive GC with memory pressure techniques

### 3. Processing Loop Optimizations
- **Frequent GC**: Additional forced garbage collection every 100 objects
- **Object Cleanup**: Explicit disposal of security descriptor objects
- **Memory Logging**: Detailed memory usage tracking for troubleshooting

## Memory Usage Patterns

### Expected Behavior
```
✅ EXCELLENT: Memory increase < 20MB over baseline
✅ GOOD: Memory increase < 50MB over baseline
⚠️ ACCEPTABLE: Memory increase < 100MB over baseline
❌ CONCERNING: Memory increase >= 100MB over baseline
```

### Streaming Benefits
- **Constant Memory**: Results are streamed to disk, not accumulated in memory
- **Batch Processing**: Small in-memory batches (50 results) prevent large allocations
- **Automatic Cleanup**: Aggressive garbage collection after each batch
- **Scalable**: Memory usage remains stable regardless of total result count

## Common Memory Issues

### 1. Memory Leaks
**Symptoms:**
- Continuously increasing memory usage
- Script becomes unresponsive over time
- System performance degradation


## Common Memory Issues

### Issue: High Memory Usage (Legacy)
**Symptoms**: Memory grows continuously during large-scale operations
**Root Cause**: Previous versions accumulated all results in `$script:AllResults`
**Resolution**: Upgrade to streaming architecture (current version)

### Issue: Memory Not Released After Processing
**Symptoms**: Memory remains high after script completion
**Resolution**:
```powershell
# Manual cleanup if needed
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()
```

### Issue: Temporary File Accumulation
**Symptoms**: Disk space consumed by temporary batch files
**Resolution**:
```powershell
# Use PreserveTempFiles parameter to control cleanup
.\Find-UnknownSID.ps1 -SearchBase "DC=domain,DC=com" -PreserveTempFiles:$false
```

## Monitoring and Diagnostics

### Memory Monitoring Commands
```powershell
# Check current PowerShell process memory
$process = Get-Process -Id $PID
$memoryMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
Write-Host "Current Memory Usage: $memoryMB MB"

# Monitor during script execution
Get-Process powershell | Select-Object ProcessName, Id, @{Name="MemoryMB";Expression={[Math]::Round($_.WorkingSet64/1MB,2)}}
```

### Streaming Diagnostics
```powershell
# Test streaming functionality
.\Tools\Test-StreamingMemory.ps1

# Check temp directory usage
$tempDir = $env:TEMP
Get-ChildItem $tempDir -Filter "*SIDStreaming*" -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host "$($_.Name): $([Math]::Round($size, 2)) MB"
}
```

## Performance Optimization

### Memory Thresholds
```powershell
# Adjust memory threshold based on environment size
$memoryThreshold = switch ($objectCount) {
    {$_ -lt 1000} { 1024 }      # 1GB for small environments
    {$_ -lt 10000} { 2048 }     # 2GB for medium environments
    {$_ -lt 50000} { 4096 }     # 4GB for large environments
    default { 8192 }            # 8GB for very large environments
}

.\Find-UnknownSID.ps1 -MaxMemoryUsageMB $memoryThreshold
```

### Batch Size Tuning
```powershell
# Smaller batches for memory-constrained environments
# Larger batches for high-performance environments
# (Controlled internally by StreamingResultsManager)
```

## Enterprise Recommendations

### Production Environments
- **Memory Monitoring**: Implement continuous memory monitoring during execution
- **Baseline Testing**: Establish memory usage baselines for your environment
- **Streaming Validation**: Run streaming memory tests before production deployment
- **Resource Planning**: Allocate sufficient disk space for temporary streaming files

### Large-Scale Deployments (>10,000 objects)
- **Memory Threshold**: Use 2048MB+ for optimal performance
- **Batch Processing**: Leverage streaming architecture for consistent memory usage
- **Monitoring Integration**: Integrate with enterprise monitoring solutions
- **Staged Execution**: Consider processing in smaller search base chunks for very large environments

### Troubleshooting Workflow
1. **Check Current Memory**: Monitor baseline before script execution
2. **Enable Verbose Logging**: Use `-Verbose` parameter for detailed memory tracking
3. **Run Streaming Test**: Execute `Test-StreamingMemory.ps1` to validate functionality
4. **Monitor Temp Files**: Check temporary file creation and cleanup
5. **Adjust Thresholds**: Increase memory threshold if needed for environment size
6. **Review Logs**: Analyze detailed logs for memory management events

## Emergency Procedures

### Script Hanging or High Memory
```powershell
# Emergency memory cleanup
$processes = Get-Process powershell | Where-Object { $_.WorkingSet64 -gt 500MB }
$processes | Select-Object Id, ProcessName, @{Name="MemoryMB";Expression={[Math]::Round($_.WorkingSet64/1MB,2)}}

# If necessary, terminate runaway processes
# $processes | Stop-Process -Force
```

### Temporary File Cleanup
```powershell
# Manual cleanup of streaming temp files
$tempPattern = Join-Path $env:TEMP "*SIDStreaming*"
Get-ChildItem $tempPattern -Directory | Remove-Item -Recurse -Force -WhatIf

# Remove WhatIf to execute cleanup
```

## Validation and Testing

### Memory Test Results (Expected)
```
Test: 2000 results, batch size 100
Initial: ~90 MB
Final: ~78 MB
Memory Increase: ~-12 MB (Memory actually decreased!)
Performance: EXCELLENT
```

### Key Success Metrics
- ✅ Memory usage stable or decreasing during processing
- ✅ Temporary files created and cleaned up properly
- ✅ CSV export successful with all results
- ✅ No memory-related errors or warnings
- ✅ Streaming summary matches expected result counts

This streaming architecture ensures reliable, scalable memory management for enterprise Active Directory environments of any size.

## Implementation Details

### StreamingResultsManager Class Location
```
.\Classes\StreamingResultsManager.ps1
```

### Key Methods
- `AddResult($result)`: Adds result to current batch, flushes when full
- `FlushBatch()`: Writes current batch to disk, clears memory
- `GetAllResults()`: Retrieves all results from disk (for final export)
- `ExportToCsv($path)`: Efficient direct CSV export from streaming files
- `Dispose()`: Cleanup and final batch flush
- `Cleanup()`: Remove temporary files (optional)

### Integration Points
- **Main Processing**: Results added via `$script:StreamingResults.AddResult()`
- **Export Logic**: CSV export via `$streamingManager.ExportToCsv()`
- **Cleanup**: Automatic disposal in finally block
- **Monitoring**: Memory usage tracking integrated with streaming operations

### Configuration Options
```powershell
# Control temporary file preservation
.\Find-UnknownSID.ps1 -PreserveTempFiles:$true

# Adjust memory monitoring (existing parameter)
.\Find-UnknownSID.ps1 -MaxMemoryUsageMB 2048
```

This comprehensive approach ensures enterprise-grade memory management with predictable, scalable performance characteristics.
```powershell
# Force garbage collection at strategic points
if ($ProcessedItems % 1000 -eq 0) {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}
```

### 4. Large-Scale Discovery Memory Growth
**Symptoms:**
- Memory usage steadily increases during processing (e.g., 3659MB at 11,000 objects)
- Memory exceeds configured threshold (e.g., 1024MB limit)
- Processing continues but with warnings about memory usage

**Root Cause Analysis:**
This issue typically occurs due to:
- Security descriptor objects accumulating in memory
- Insufficient garbage collection frequency during large operations
- Large result sets being held in memory simultaneously

**Diagnostic Steps:**
```powershell
# Monitor memory during large operations
Write-Host "Starting memory monitoring for large discovery..."
$startMemory = (Get-Process -Id $PID).WorkingSet64 / 1MB
Write-Host "Initial memory: $startMemory MB"

# Check memory every 1000 objects
$checkInterval = 1000
if ($processedCount % $checkInterval -eq 0) {
    $currentMemory = (Get-Process -Id $PID).WorkingSet64 / 1MB
    $memoryGrowth = $currentMemory - $startMemory
    Write-Host "Objects: $processedCount, Memory: $currentMemory MB, Growth: $memoryGrowth MB"
}
```

**Resolution (Implemented in Latest Version):**
1. **Reduced Memory Check Interval**: Now checks every 25 operations instead of 50
2. **Enhanced Garbage Collection**:
   ```powershell
   # Additional cleanup every 100 operations
   if ($processedCount % 100 -eq 0) {
       [System.GC]::Collect()
   }

   # Aggressive cleanup with memory pressure
   [System.GC]::AddMemoryPressure(50MB)
   [System.GC]::RemoveMemoryPressure(50MB)
   ```
3. **Object Disposal**: Automatic cleanup of security descriptors
4. **Non-Blocking Processing**: Warnings instead of errors when memory remains high

**Workaround for Extreme Cases:**
```powershell
# Increase memory limit for very large environments
.\Find-UnknownSID.ps1 -SearchBase "DC=domain,DC=com" -MaxMemoryUsageMB 4096

# Process in smaller batches
$searchBases = @("OU=Users,DC=domain,DC=com", "OU=Computers,DC=domain,DC=com")
foreach ($base in $searchBases) {
    .\Find-UnknownSID.ps1 -SearchBase $base -MaxMemoryUsageMB 2048
}
```

## Memory Optimization Strategies

### 1. Efficient Data Structures
```powershell
# Use appropriate collection types
$hashTable = @{}                    # Fast lookups
$arrayList = [System.Collections.ArrayList]::new()  # Dynamic sizing
$stringBuilder = [System.Text.StringBuilder]::new() # String concatenation
```

### 2. Memory-Efficient Processing
```powershell
# Process data in chunks rather than loading everything
$chunkSize = 1000
$allItems = Get-LargeDataSet
for ($i = 0; $i -lt $allItems.Count; $i += $chunkSize) {
    $chunk = $allItems[$i..($i + $chunkSize - 1)]
    Process-Chunk -Data $chunk

    # Clear chunk from memory
    $chunk = $null
    [System.GC]::Collect()
}
```

### 3. Resource Management
```powershell
# Implement proper disposal patterns
try {
    $resource = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open)
    # Use resource
} finally {
    if ($resource -and $resource -is [System.IDisposable]) {
        $resource.Dispose()
    }
}
```

## Performance Monitoring

### Memory Baseline Establishment
```powershell
# Establish memory baseline before script execution
$baseline = @{
    Timestamp = Get-Date
    WorkingSet = (Get-Process -Id $PID).WorkingSet64
    PrivateMemory = (Get-Process -Id $PID).PrivateMemorySize64
    VirtualMemory = (Get-Process -Id $PID).VirtualMemorySize64
    AvailableMemory = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
}
```

### Continuous Monitoring
```powershell
# Set up performance counters
$performanceCounters = @(
    '\Process(powershell*)\Working Set'
    '\Process(powershell*)\Private Bytes'
    '\Process(powershell*)\Virtual Bytes'
    '\Memory\Available Bytes'
)
```

## Enterprise Configuration

### Memory Limits
```powershell
# Configure memory limits for enterprise deployment
$memoryLimitMB = 2048  # 2GB limit
$currentMemoryMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)

if ($currentMemoryMB -gt $memoryLimitMB) {
    Write-Warning "Memory usage ($currentMemoryMB MB) exceeds limit ($memoryLimitMB MB)"
    # Implement memory reduction strategy
}
```

### Monitoring Integration
```powershell
# Integration with enterprise monitoring systems
$memoryMetrics = @{
    ScriptName = 'Find-UnknownSID'
    Timestamp = Get-Date
    WorkingSetMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
    PrivateMemoryMB = [Math]::Round((Get-Process -Id $PID).PrivateMemorySize64 / 1MB, 2)
    VirtualMemoryMB = [Math]::Round((Get-Process -Id $PID).VirtualMemorySize64 / 1MB, 2)
    CorrelationId = $CorrelationId
}

# Send to monitoring system
Send-Metrics -Data $memoryMetrics -Endpoint $MonitoringEndpoint
```

## Troubleshooting Workflows

### Memory Leak Detection
1. **Baseline Measurement**
   - Record initial memory usage
   - Document expected memory growth patterns
   - Set monitoring thresholds

2. **Periodic Monitoring**
   - Sample memory usage every 5 minutes
   - Compare against baseline and thresholds
   - Log anomalies for analysis

3. **Leak Analysis**
   - Identify memory growth patterns
   - Correlate with script operations
   - Implement targeted fixes

### Performance Degradation
1. **Symptom Identification**
   - Measure operation duration
   - Monitor memory allocation patterns
   - Check for excessive garbage collection

2. **Root Cause Analysis**
   - Profile memory usage during operations
   - Identify memory-intensive functions
   - Analyze data structure efficiency

3. **Optimization Implementation**
   - Implement memory-efficient algorithms
   - Add strategic garbage collection
   - Optimize data structures

## Best Practices

### Memory Management
- **Proactive Monitoring**: Implement continuous memory monitoring
- **Resource Cleanup**: Always dispose of resources properly
- **Efficient Data Structures**: Use appropriate collection types
- **Batch Processing**: Process large datasets in chunks
- **Strategic GC**: Force garbage collection at appropriate intervals

### Performance Optimization
- **Memory Profiling**: Regular profiling during development
- **Threshold Management**: Set and monitor memory thresholds
- **Efficient Algorithms**: Use memory-efficient processing patterns
- **Resource Pooling**: Reuse objects when possible
- **Lazy Loading**: Load data only when needed

### Enterprise Integration
- **Centralized Monitoring**: Integrate with enterprise monitoring systems
- **Alerting**: Set up proactive alerts for memory issues
- **Documentation**: Maintain detailed memory usage documentation
- **Capacity Planning**: Plan memory requirements for scale
- **Compliance**: Ensure memory usage meets enterprise standards

## Diagnostic Tools

### PowerShell Commands
```powershell
# Memory diagnostics
Get-Process -Id $PID | Select-Object WorkingSet64, PrivateMemorySize64, VirtualMemorySize64
Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory, TotalVisibleMemorySize
[System.GC]::GetTotalMemory($false)
```

### Performance Counters
```powershell
# Set up performance monitoring
$counters = @(
    '\Process(powershell*)\Working Set'
    '\Process(powershell*)\Private Bytes'
    '\Memory\Available Bytes'
    '\Memory\Pages/sec'
)

foreach ($counter in $counters) {
    Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples 10
}
```

## Related Documentation
- [Performance Tuning Guide](./Performance-Tuning.md)
- [Security Validation Guide](../Security/Security-Validation-Guide.md)
- [Enterprise Integration Guide](../Integration/Enterprise-Integration-Guide.md)
- [Find-UnknownSID Issues](../Common/Find-UnknownSID-Issues.md)

## Support and Escalation
For persistent memory issues that cannot be resolved using this guide:
1. Collect memory diagnostic data
2. Document reproduction steps
3. Gather system configuration details
4. Contact enterprise support with correlation ID
5. Escalate to PowerShell development team if needed

---
*Last Updated: $(Get-Date)*
*Version: 1.0.0*
*Author: Enterprise PowerShell Team*
