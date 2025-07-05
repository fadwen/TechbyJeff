# Memory Management Issues - Troubleshooting Guide

## Overview
This guide addresses memory management issues that can occur during large-scale SID processing operations, including memory leaks, excessive memory usage, and out-of-memory conditions.

## Common Issues

### 1. Memory Leaks

#### Issue: Gradual Memory Growth During Processing
**Symptoms:**
- Memory usage increases continuously throughout processing
- Available system memory decreases over time
- System becomes sluggish during long-running operations
- Process memory doesn't decrease after processing completion

**Root Causes:**
- Objects not being properly disposed
- Event handlers not being unregistered
- Static collections accumulating objects
- Circular references preventing garbage collection

**Resolution Steps:**
1. **Identify Memory Leak Sources:**
   ```powershell
   function Find-MemoryLeaks {
       param(
           [int]$SampleIntervalSeconds = 30,
           [int]$MonitorDurationMinutes = 10,
           [string]$CorrelationId
       )

       $samples = [System.Collections.ArrayList]::new()
       $startTime = Get-Date
       $endTime = $startTime.AddMinutes($MonitorDurationMinutes)

       while ((Get-Date) -lt $endTime) {
           $memoryUsage = @{
               Timestamp = Get-Date
               ProcessMemoryMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
               GCMemoryMB = [Math]::Round([System.GC]::GetTotalMemory($false) / 1MB, 2)
               AvailableSystemMemoryMB = [Math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024, 2)
           }

           [void]$samples.Add($memoryUsage)
           Write-Verbose "Memory sample: Process=$($memoryUsage.ProcessMemoryMB)MB, GC=$($memoryUsage.GCMemoryMB)MB - CorrelationId: $CorrelationId"

           Start-Sleep -Seconds $SampleIntervalSeconds
       }

       # Analyze memory trend
       $firstSample = $samples[0]
       $lastSample = $samples[-1]
       $memoryGrowth = $lastSample.ProcessMemoryMB - $firstSample.ProcessMemoryMB
       $growthRate = $memoryGrowth / $MonitorDurationMinutes  # MB per minute

       if ($growthRate -gt 10) {
           Write-Warning "Potential memory leak detected: $($growthRate.ToString('F2')) MB/minute growth rate"
           return @{
               HasLeak = $true
               GrowthRateMBPerMinute = $growthRate
               TotalGrowthMB = $memoryGrowth
               Samples = $samples
           }
       }

       return @{
           HasLeak = $false
           GrowthRateMBPerMinute = $growthRate
           TotalGrowthMB = $memoryGrowth
           Samples = $samples
       }
   }
   ```

2. **Implement Proper Disposal Patterns:**
   ```powershell
   function Invoke-ProcessingWithDisposal {
       param(
           [PSCustomObject[]]$Objects,
           [string]$CorrelationId
       )

       $disposableResources = [System.Collections.ArrayList]::new()

       try {
           # Create resources that need disposal
           $streamingManager = New-StreamingResultsManager -CorrelationId $CorrelationId
           [void]$disposableResources.Add($streamingManager)

           $memoryManager = Initialize-MemoryManager -CorrelationId $CorrelationId
           [void]$disposableResources.Add($memoryManager)

           # Main processing
           $results = foreach ($object in $Objects) {
               $result = Process-SingleObject -Object $object -CorrelationId $CorrelationId

               # Clear intermediate variables
               $securityDescriptor = $null
               $identityInfo = $null

               $result
           }

           return $results
       }
       finally {
           # Dispose all resources in reverse order
           for ($i = $disposableResources.Count - 1; $i -ge 0; $i--) {
               try {
                   $resource = $disposableResources[$i]
                   if ($resource -and $resource -is [System.IDisposable]) {
                       Write-Verbose "Disposing resource: $($resource.GetType().Name) - CorrelationId: $CorrelationId"
                       $resource.Dispose()
                   }
               }
               catch {
                   Write-Warning "Failed to dispose resource: $($_.Exception.Message)"
               }
           }

           # Clear collections
           $disposableResources.Clear()

           # Force garbage collection
           [System.GC]::Collect()
           [System.GC]::WaitForPendingFinalizers()
           [System.GC]::Collect()
       }
   }
   ```

3. **Monitor Object References:**
   ```powershell
   function Test-ObjectReferences {
       param([string]$CorrelationId)

       # Get current generation counts
       $gen0Before = [System.GC]::CollectionCount(0)
       $gen1Before = [System.GC]::CollectionCount(1)
       $gen2Before = [System.GC]::CollectionCount(2)

       # Force garbage collection
       [System.GC]::Collect()
       [System.GC]::WaitForPendingFinalizers()
       [System.GC]::Collect()

       # Get post-collection counts
       $gen0After = [System.GC]::CollectionCount(0)
       $gen1After = [System.GC]::CollectionCount(1)
       $gen2After = [System.GC]::CollectionCount(2)

       $collectionInfo = @{
           Gen0Collections = $gen0After - $gen0Before
           Gen1Collections = $gen1After - $gen1Before
           Gen2Collections = $gen2After - $gen2Before
           TotalMemoryAfterGC = [System.GC]::GetTotalMemory($true)
       }

       Write-Verbose "GC Statistics - Gen0: $($collectionInfo.Gen0Collections), Gen1: $($collectionInfo.Gen1Collections), Gen2: $($collectionInfo.Gen2Collections) - CorrelationId: $CorrelationId"

       return $collectionInfo
   }
   ```

#### Issue: Large Object Heap (LOH) Fragmentation
**Symptoms:**
- OutOfMemoryException despite apparent available memory
- Sudden memory allocation failures
- Performance degradation over time

**Root Causes:**
- Frequent allocation of large objects (>85KB)
- Long-lived large objects preventing LOH compaction
- Fragmented memory space preventing large allocations

**Resolution Steps:**
1. **Monitor Large Object Allocations:**
   ```powershell
   function Monitor-LargeObjectAllocations {
       param(
           [scriptblock]$Operation,
           [string]$CorrelationId
       )

       $initialLOHSize = [System.GC]::GetTotalMemory($false)
       [System.GC]::Collect(2, [System.GCCollectionMode]::Forced)
       $initialLOHCompacted = [System.GC]::GetTotalMemory($true)

       try {
           $result = & $Operation
       }
       finally {
           $finalLOHSize = [System.GC]::GetTotalMemory($false)
           [System.GC]::Collect(2, [System.GCCollectionMode]::Forced)
           $finalLOHCompacted = [System.GC]::GetTotalMemory($true)

           $lohGrowth = $finalLOHSize - $initialLOHSize
           $lohFragmentation = ($finalLOHSize - $finalLOHCompacted) / $finalLOHSize * 100

           if ($lohGrowth -gt 50MB) {
               Write-Warning "Large LOH growth detected: $([Math]::Round($lohGrowth / 1MB, 2)) MB - CorrelationId: $CorrelationId"
           }

           if ($lohFragmentation -gt 20) {
               Write-Warning "High LOH fragmentation: $($lohFragmentation.ToString('F1'))% - CorrelationId: $CorrelationId"
           }
       }
   }
   ```

2. **Implement LOH-Friendly Patterns:**
   ```powershell
   function Invoke-LOHFriendlyProcessing {
       param(
           [PSCustomObject[]]$Objects,
           [int]$BatchSize = 100,
           [string]$CorrelationId
       )

       # Use smaller, reusable buffers instead of large arrays
       $resultBuffer = New-Object System.Collections.ArrayList($BatchSize)
       $allResults = [System.Collections.ArrayList]::new()

       for ($i = 0; $i -lt $Objects.Count; $i += $BatchSize) {
           $batchEnd = [Math]::Min($i + $BatchSize - 1, $Objects.Count - 1)
           $batch = $Objects[$i..$batchEnd]

           # Clear previous batch results
           $resultBuffer.Clear()

           foreach ($object in $batch) {
               $result = Process-SingleObject -Object $object -CorrelationId $CorrelationId
               [void]$resultBuffer.Add($result)
           }

           # Copy results to final collection
           foreach ($result in $resultBuffer) {
               [void]$allResults.Add($result)
           }

           # Periodic cleanup to prevent LOH pressure
           if (($i / $BatchSize) % 10 -eq 0) {
               [System.GC]::Collect(2, [System.GCCollectionMode]::Optimized)
           }
       }

       return $allResults
   }
   ```

### 2. Excessive Memory Usage

#### Issue: Memory Usage Exceeds Available System Memory
**Symptoms:**
- System paging activity increases significantly
- Processing becomes extremely slow
- System becomes unresponsive
- Other applications start failing

**Root Causes:**
- Processing datasets larger than available memory
- Inefficient data structures
- Holding references to all processed objects
- Not implementing streaming patterns

**Resolution Steps:**
1. **Implement Memory Monitoring with Thresholds:**
   ```powershell
   function Invoke-ProcessingWithMemoryLimits {
       param(
           [PSCustomObject[]]$Objects,
           [int]$MaxMemoryMB = 2048,
           [int]$WarningThresholdMB = 1536,
           [string]$CorrelationId
       )

       $processedCount = 0
       $results = [System.Collections.ArrayList]::new()

       foreach ($object in $Objects) {
           # Check memory before processing each object
           $currentMemoryMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 0)

           if ($currentMemoryMB -ge $MaxMemoryMB) {
               Write-Error "Memory limit exceeded: $currentMemoryMB MB >= $MaxMemoryMB MB"
               throw "Processing halted due to memory limit"
           }

           if ($currentMemoryMB -ge $WarningThresholdMB) {
               Write-Warning "Memory usage high: $currentMemoryMB MB (threshold: $WarningThresholdMB MB) - CorrelationId: $CorrelationId"

               # Aggressive cleanup
               [System.GC]::Collect()
               [System.GC]::WaitForPendingFinalizers()
               [System.GC]::Collect()

               $afterCleanupMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 0)
               Write-Verbose "Memory after cleanup: $afterCleanupMB MB - CorrelationId: $CorrelationId"
           }

           try {
               $result = Process-SingleObject -Object $object -CorrelationId $CorrelationId
               [void]$results.Add($result)
               $processedCount++

               # Periodic cleanup
               if ($processedCount % 100 -eq 0) {
                   Invoke-GarbageCollection
               }
           }
           catch {
               Write-Error "Failed to process object due to memory issues: $($_.Exception.Message)"
               throw
           }
       }

       return $results
   }
   ```

2. **Implement Streaming Results:**
   ```powershell
   function Invoke-StreamingProcessing {
       param(
           [PSCustomObject[]]$Objects,
           [string]$OutputPath,
           [string]$CorrelationId
       )

       $resultCount = 0
       $streamWriter = $null

       try {
           # Initialize streaming output
           $streamWriter = New-Object System.IO.StreamWriter($OutputPath)
           $streamWriter.WriteLine('[')  # Start JSON array

           foreach ($object in $Objects) {
               $result = Process-SingleObject -Object $object -CorrelationId $CorrelationId

               # Convert to JSON and stream to file
               if ($resultCount -gt 0) {
                   $streamWriter.WriteLine(',')
               }

               $jsonResult = $result | ConvertTo-Json -Compress
               $streamWriter.Write($jsonResult)

               $resultCount++

               # Don't hold references to processed results
               $result = $null

               # Periodic cleanup
               if ($resultCount % 50 -eq 0) {
                   [System.GC]::Collect(0, [System.GCCollectionMode]::Optimized)
                   Write-Verbose "Streamed $resultCount results - CorrelationId: $CorrelationId"
               }
           }

           $streamWriter.WriteLine()  # New line
           $streamWriter.WriteLine(']')  # End JSON array

           Write-Output "Streamed $resultCount results to $OutputPath"
       }
       finally {
           if ($streamWriter) {
               $streamWriter.Dispose()
           }
       }
   }
   ```

3. **Implement Memory-Efficient Data Structures:**
   ```powershell
   function New-MemoryEfficientProcessor {
       param([string]$CorrelationId)

       return [PSCustomObject]@{
           # Use concurrent collections for thread safety and efficiency
           Results = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
           Errors = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

           # Statistics using value types
           ProcessedCount = [ref]0
           ErrorCount = [ref]0

           # Memory tracking
           LastMemoryCheck = [DateTime]::UtcNow
           MemoryThresholdMB = 1024

           CorrelationId = $CorrelationId

           # Methods
           AddResult = {
               param($Result)
               $this.Results.Add($Result)
               [System.Threading.Interlocked]::Increment($this.ProcessedCount)
           }

           AddError = {
               param($ErrorMessage)
               $this.Errors.Enqueue($ErrorMessage)
               [System.Threading.Interlocked]::Increment($this.ErrorCount)
           }

           CheckMemory = {
               $currentMemoryMB = [Math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 0)
               if ($currentMemoryMB -gt $this.MemoryThresholdMB) {
                   [System.GC]::Collect(0, [System.GCCollectionMode]::Optimized)
                   Write-Verbose "Memory check triggered cleanup at $currentMemoryMB MB"
               }
               $this.LastMemoryCheck = [DateTime]::UtcNow
           }

           GetStatistics = {
               return @{
                   ProcessedCount = $this.ProcessedCount.Value
                   ErrorCount = $this.ErrorCount.Value
                   ResultsInMemory = $this.Results.Count
                   ErrorsInQueue = $this.Errors.Count
                   LastMemoryCheck = $this.LastMemoryCheck
               }
           }

           Dispose = {
               $this.Results = $null
               $this.Errors = $null
               [System.GC]::Collect()
           }
       }
   }
   ```

### 3. Out-of-Memory Conditions

#### Issue: OutOfMemoryException During Processing
**Symptoms:**
- Processing terminates with OutOfMemoryException
- System reports insufficient memory for allocation
- Application becomes unresponsive before crash

**Root Causes:**
- Attempting to allocate objects larger than available memory
- Memory fragmentation preventing large allocations
- 32-bit process limitations (2GB address space)
- System-wide memory pressure

**Resolution Steps:**
1. **Implement Memory Pressure Detection:**
   ```powershell
   function Test-MemoryPressure {
       param([string]$CorrelationId)

       try {
           # Check system memory
           $os = Get-CimInstance Win32_OperatingSystem
           $totalMemoryGB = [Math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 2)
           $freeMemoryGB = [Math]::Round($os.FreePhysicalMemory / 1024 / 1024, 2)
           $memoryUsagePercent = (($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100

           # Check process memory
           $process = Get-Process -Id $PID
           $processMemoryGB = [Math]::Round($process.WorkingSet64 / 1GB, 2)
           $peakMemoryGB = [Math]::Round($process.PeakWorkingSet64 / 1GB, 2)

           # Check for 32-bit limitations
           $is32Bit = [IntPtr]::Size -eq 4
           $maxProcessMemoryGB = if ($is32Bit) { 2 } else { $totalMemoryGB }

           $memoryPressure = @{
               SystemMemoryUsagePercent = $memoryUsagePercent
               ProcessMemoryGB = $processMemoryGB
               PeakProcessMemoryGB = $peakMemoryGB
               AvailableSystemMemoryGB = $freeMemoryGB
               MaxProcessMemoryGB = $maxProcessMemoryGB
               Is32BitProcess = $is32Bit
               HasPressure = $false
               Warnings = @()
           }

           # Detect pressure conditions
           if ($memoryUsagePercent -gt 90) {
               $memoryPressure.HasPressure = $true
               $memoryPressure.Warnings += "System memory usage is critically high: $($memoryUsagePercent.ToString('F1'))%"
           }

           if ($processMemoryGB -gt ($maxProcessMemoryGB * 0.8)) {
               $memoryPressure.HasPressure = $true
               $memoryPressure.Warnings += "Process memory usage is high: $processMemoryGB GB (max: $maxProcessMemoryGB GB)"
           }

           if ($freeMemoryGB -lt 0.5) {
               $memoryPressure.HasPressure = $true
               $memoryPressure.Warnings += "System free memory is critically low: $freeMemoryGB GB"
           }

           return $memoryPressure
       }
       catch {
           Write-Error "Failed to check memory pressure: $($_.Exception.Message)"
           return @{ HasPressure = $true; Warnings = @("Memory pressure check failed") }
       }
   }
   ```

2. **Implement Memory-Safe Processing:**
   ```powershell
   function Invoke-MemorySafeProcessing {
       param(
           [PSCustomObject[]]$Objects,
           [string]$CorrelationId
       )

       $memoryPressure = Test-MemoryPressure -CorrelationId $CorrelationId

       if ($memoryPressure.HasPressure) {
           Write-Warning "Memory pressure detected before processing:"
           $memoryPressure.Warnings | ForEach-Object { Write-Warning "  $_" }

           # Use conservative settings under memory pressure
           $batchSize = 25
           $gcFrequency = 10
           $memoryCheckFrequency = 5
       }
       else {
           # Normal settings
           $batchSize = 100
           $gcFrequency = 50
           $memoryCheckFrequency = 25
       }

       $processedCount = 0
       $results = [System.Collections.ArrayList]::new()

       try {
           for ($i = 0; $i -lt $Objects.Count; $i += $batchSize) {
               $batchEnd = [Math]::Min($i + $batchSize - 1, $Objects.Count - 1)
               $batch = $Objects[$i..$batchEnd]

               # Pre-batch memory check
               if ($processedCount % $memoryCheckFrequency -eq 0) {
                   $currentPressure = Test-MemoryPressure -CorrelationId $CorrelationId
                   if ($currentPressure.HasPressure) {
                       Write-Warning "Memory pressure during processing - triggering aggressive cleanup"
                       [System.GC]::Collect()
                       [System.GC]::WaitForPendingFinalizers()
                       [System.GC]::Collect()
                   }
               }

               # Process batch
               foreach ($object in $batch) {
                   try {
                       $result = Process-SingleObject -Object $object -CorrelationId $CorrelationId
                       [void]$results.Add($result)
                       $processedCount++
                   }
                   catch [System.OutOfMemoryException] {
                       Write-Error "Out of memory processing object $($object.DistinguishedName)"

                       # Emergency cleanup
                       [System.GC]::Collect()
                       [System.GC]::WaitForPendingFinalizers()
                       [System.GC]::Collect()

                       throw "Processing halted due to memory exhaustion"
                   }
               }

               # Periodic garbage collection
               if ($processedCount % $gcFrequency -eq 0) {
                   [System.GC]::Collect(0, [System.GCCollectionMode]::Optimized)
               }
           }

           return $results
       }
       catch {
           Write-Error "Memory-safe processing failed: $($_.Exception.Message)"
           throw
       }
   }
   ```

## Validation Commands

### Test Memory Management
```powershell
# Test memory leak detection
function Test-MemoryLeakDetection {
    param([string]$CorrelationId = [System.Guid]::NewGuid().ToString())

    $leakTest = Find-MemoryLeaks -SampleIntervalSeconds 5 -MonitorDurationMinutes 2 -CorrelationId $CorrelationId

    if ($leakTest.HasLeak) {
        Write-Warning "Memory leak detected: $($leakTest.GrowthRateMBPerMinute) MB/minute"
        return $false
    }
    else {
        Write-Output "No memory leaks detected"
        return $true
    }
}
```

### Test Memory Pressure Handling
```powershell
# Test memory pressure detection and handling
function Test-MemoryPressureHandling {
    param([string]$CorrelationId = [System.Guid]::NewGuid().ToString())

    $memoryPressure = Test-MemoryPressure -CorrelationId $CorrelationId

    Write-Output "Memory Pressure Status:"
    Write-Output "  System Memory Usage: $($memoryPressure.SystemMemoryUsagePercent.ToString('F1'))%"
    Write-Output "  Process Memory: $($memoryPressure.ProcessMemoryGB) GB"
    Write-Output "  Available Memory: $($memoryPressure.AvailableSystemMemoryGB) GB"
    Write-Output "  Has Pressure: $($memoryPressure.HasPressure)"

    if ($memoryPressure.Warnings.Count -gt 0) {
        Write-Warning "Memory warnings:"
        $memoryPressure.Warnings | ForEach-Object { Write-Warning "  $_" }
    }

    return $memoryPressure
}
```

### Test Garbage Collection Effectiveness
```powershell
# Test garbage collection effectiveness
function Test-GarbageCollectionEffectiveness {
    param([string]$CorrelationId = [System.Guid]::NewGuid().ToString())

    $beforeMemory = [System.GC]::GetTotalMemory($false)

    # Create temporary objects
    $tempObjects = 1..1000 | ForEach-Object {
        New-Object PSCustomObject -Property @{
            Data = "x" * 1000  # 1KB per object
            Index = $_
        }
    }

    $afterCreation = [System.GC]::GetTotalMemory($false)
    $createdMemory = $afterCreation - $beforeMemory

    # Clear references
    $tempObjects = $null

    # Force garbage collection
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    $afterCollection = [System.GC]::GetTotalMemory($true)
    $releasedMemory = $afterCreation - $afterCollection
    $releasePercentage = ($releasedMemory / $createdMemory) * 100

    Write-Output "Garbage Collection Test Results:"
    Write-Output "  Memory created: $([Math]::Round($createdMemory / 1KB, 2)) KB"
    Write-Output "  Memory released: $([Math]::Round($releasedMemory / 1KB, 2)) KB"
    Write-Output "  Release percentage: $($releasePercentage.ToString('F1'))%"

    # Effective GC should release at least 90% of temporary objects
    return $releasePercentage -ge 90
}
```

## Best Practices

### 1. Memory Monitoring
- Implement continuous memory monitoring during processing
- Set appropriate memory thresholds and alerts
- Monitor both process and system memory usage
- Track memory growth patterns to identify leaks

### 2. Resource Management
- Always dispose of IDisposable objects in finally blocks
- Use using statements where possible for automatic disposal
- Clear object references when no longer needed
- Implement proper cleanup patterns for custom classes

### 3. Garbage Collection
- Force garbage collection at appropriate intervals
- Use different GC modes based on processing requirements
- Monitor GC effectiveness and adjust strategies
- Avoid frequent small allocations that pressure Gen0

### 4. Large Object Heap Management
- Minimize large object allocations (>85KB)
- Use object pooling for frequently allocated large objects
- Implement streaming patterns for large datasets
- Monitor LOH fragmentation and adjust algorithms

## Related Documentation
- [SID Processing Orchestration Issues](../Common/SID-Processing-Orchestration-Issues.md)
- [Result Creation Issues](../Common/Result-Creation-Issues.md)
- [Security Descriptor Issues](../Security/Security-Descriptor-Issues.md)
- [Performance Optimization Guide](./Optimization-Guide.md)

## Support Information
- **Components**: All processing modules
- **Focus**: Memory management and garbage collection
- **Last Updated**: $(Get-Date -Format 'yyyy-MM-dd')
- **Correlation ID**: Include in all support requests for faster resolution
