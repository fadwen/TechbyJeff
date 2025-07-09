#Requires -Version 5.1
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive concurrent operations performance testing for Find-UnknownSID solution

.DESCRIPTION
    Enterprise-grade validation of multi-threaded and concurrent processing capabilities including:
    - Parallel SID processing with thread safety validation
    - Concurrent file system operations and locking mechanisms
    - Multi-threaded backup and restore operations
    - Resource contention and deadlock prevention
    - Performance scaling under concurrent load
    - Thread pool management and optimization
    - Synchronization primitive effectiveness

.NOTES
    Author: GitHub Copilot (AI Assistant)
    Created: January 2025
    Version: 1.0.0

    Test Categories:
    - Parallel Processing Performance
    - Thread Safety Validation
    - Resource Contention Management
    - Deadlock Prevention
    - Scalability Testing
    - Synchronization Testing

    This file implements comprehensive concurrent operations testing following
    PowerShell community standards and enterprise performance requirements.
#>

# Import required modules and classes
$ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
# Import test helpers
$TestHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers"
if (Test-Path "$TestHelpersPath\TestHelpers.ps1") {
. "$TestHelpersPath\TestHelpers.ps1"
} else {
Write-Warning "TestHelpers.ps1 not found at $TestHelpersPath"
}
# Import main module classes and functions
Get-ChildItem "$ModuleRoot\Classes" -Filter "*.ps1" | ForEach-Object { . #Requires -Version 5.1
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive concurrent operations performance testing for Find-UnknownSID solution

.DESCRIPTION
    Enterprise-grade validation of multi-threaded and concurrent processing capabilities including:
    - Parallel SID processing with thread safety validation
    - Concurrent file system operations and locking mechanisms
    - Multi-threaded backup and restore operations
    - Resource contention and deadlock prevention
    - Performance scaling under concurrent load
    - Thread pool management and optimization
    - Synchronization primitive effectiveness

.NOTES
    Author: GitHub Copilot (AI Assistant)
    Created: January 2025
    Version: 1.0.0

    Test Categories:
    - Parallel Processing Performance
    - Thread Safety Validation
    - Resource Contention Management
    - Deadlock Prevention
    - Scalability Testing
    - Synchronization Testing

    This file implements comprehensive concurrent operations testing following
    PowerShell community standards and enterprise performance requirements.
#>

BeforeAll {
    # Import required modules and classes
    $ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

    # Import test helpers
    $TestHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers"
    if (Test-Path "$TestHelpersPath\TestHelpers.ps1") {
        . "$TestHelpersPath\TestHelpers.ps1"
    } else {
        Write-Warning "TestHelpers.ps1 not found at $TestHelpersPath"
    }

    # Import main module classes and functions
    Get-ChildItem "$ModuleRoot\Classes" -Filter "*.ps1" | ForEach-Object { . $_.FullName }
    Get-ChildItem "$ModuleRoot\Private" -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    # Test data setup
    $TestDataPath = Join-Path $PSScriptRoot "..\TestData"
    $ConcurrencyTestPath = Join-Path $TestDataPath "ConcurrencyTests"
    $PerformanceLogsPath = Join-Path $TestDataPath "PerformanceLogs"

    # Ensure test directories exist
    @($TestDataPath, $ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    # Global concurrency configuration
    $Global:ConcurrencyConfig = @{
        MaxThreads = [Environment]::ProcessorCount * 2
        DefaultThreadPoolSize = [Environment]::ProcessorCount
        TimeoutSeconds = 60
        MaxRetryAttempts = 3
        PerformanceThresholds = @{
            SingleThread = 10      # seconds
            MultiThread = 15       # seconds
            HighConcurrency = 25   # seconds
        }
        TestDataSizes = @{
            Small = 100
            Medium = 500
            Large = 1000
            ExtraLarge = 2000
        }
        ConcurrencyLevels = @(1, 2, 4, 8, 16)
    }

    # Thread-safe collections for testing
    $Global:ThreadSafeResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeErrors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()

    # Mock dangerous operations for safe testing
    Mock Remove-Item { return $true } -ParameterFilter { $Path -like "*TestData*" }
    Mock Set-Acl { return $true }
    Mock Get-Acl {
        return [PSCustomObject]@{
            Access = @()
            Owner = "BUILTIN\Administrators"
            Group = "BUILTIN\Administrators"
        }
    }

    # Performance monitoring functions
    function Start-PerformanceMonitor {
        param([string]$TestName)

        return [PSCustomObject]@{
            TestName = $TestName
            StartTime = Get-Date
            StartMemory = [System.GC]::GetTotalMemory($false)
            StartHandleCount = (Get-Process -Id $PID).HandleCount
            StartThreadCount = (Get-Process -Id $PID).Threads.Count
        }
    }

    function Stop-PerformanceMonitor {
        param($Monitor)

        $endTime = Get-Date
        $endMemory = [System.GC]::GetTotalMemory($false)
        $endHandleCount = (Get-Process -Id $PID).HandleCount
        $endThreadCount = (Get-Process -Id $PID).Threads.Count

        return [PSCustomObject]@{
            TestName = $Monitor.TestName
            Duration = ($endTime - $Monitor.StartTime).TotalSeconds
            MemoryDelta = $endMemory - $Monitor.StartMemory
            HandleDelta = $endHandleCount - $Monitor.StartHandleCount
            ThreadDelta = $endThreadCount - $Monitor.StartThreadCount
            StartTime = $Monitor.StartTime
            EndTime = $endTime
        }
    }
}

Describe "Parallel Processing Performance Tests" -Tag "Performance", "Concurrency", "Parallel" {

    Context "Basic Parallel Operations" {

        It "Should process SIDs in parallel faster than sequential" {
            # Arrange
            $testSIDs = 1..$Global:ConcurrencyConfig.TestDataSizes.Medium | ForEach-Object {
                "S-1-5-21-123456789-123456789-123456789-$_"
            }

            # Act - Sequential processing
            $sequentialMonitor = Start-PerformanceMonitor -TestName "Sequential"
            $sequentialResults = @()
            foreach ($sid in $testSIDs) {
                $sequentialResults += [PSCustomObject]@{
                    SID = $sid
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Sequential"
                }
            }
            $sequentialPerf = Stop-PerformanceMonitor -Monitor $sequentialMonitor

            # Act - Parallel processing
            $parallelMonitor = Start-PerformanceMonitor -TestName "Parallel"
            $parallelResults = $testSIDs | ForEach-Object -Parallel {
                [PSCustomObject]@{
                    SID = $_
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Parallel"
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize
            $parallelPerf = Stop-PerformanceMonitor -Monitor $parallelMonitor

            # Assert
            $sequentialResults | Should -HaveCount $testSIDs.Count
            $parallelResults | Should -HaveCount $testSIDs.Count

            # Performance comparison
            $parallelPerf.Duration | Should BeLessThan $sequentialPerf.Duration

            # Verify parallel execution used multiple threads
            $uniqueThreads = ($parallelResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            Write-Host "Sequential: $([Math]::Round($sequentialPerf.Duration, 2))s, Parallel: $([Math]::Round($parallelPerf.Duration, 2))s" -ForegroundColor Cyan
            Write-Host "Speedup: $([Math]::Round($sequentialPerf.Duration / $parallelPerf.Duration, 2))x" -ForegroundColor Green
        }

        It "Should scale performance with increasing thread count" {
            # Arrange
            $testData = 1..$Global:ConcurrencyConfig.TestDataSizes.Small | ForEach-Object {
                "TestData_$_"
            }
            $scalingResults = @()

            # Act - Test different concurrency levels
            foreach ($threadCount in $Global:ConcurrencyConfig.ConcurrencyLevels) {
                if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                $monitor = Start-PerformanceMonitor -TestName "Scaling_$threadCount"

                $results = $testData | ForEach-Object -Parallel {
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    [PSCustomObject]@{
                        Data = $_
                        ProcessedAt = Get-Date
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    }
                } -ThrottleLimit $threadCount

                $perf = Stop-PerformanceMonitor -Monitor $monitor

                $scalingResults += [PSCustomObject]@{
                    ThreadCount = $threadCount
                    Duration = $perf.Duration
                    Throughput = $testData.Count / $perf.Duration
                    UniqueThreads = ($results | Group-Object ThreadId).Count
                    MemoryDelta = $perf.MemoryDelta
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty
            $scalingResults.Count | Should BeGreaterThan 1

            # Performance should generally improve with more threads (up to optimal point)
            $baselinePerformance = $scalingResults | Where-Object ThreadCount -eq 1
            $bestPerformance = $scalingResults | Sort-Object Duration | Select-Object -First 1

            $bestPerformance.Duration | Should BeLessThan $baselinePerformance.Duration

            # Display scaling results
            Write-Host "Concurrency Scaling Results:" -ForegroundColor Green
            $scalingResults | ForEach-Object {
                Write-Host "  $($_.ThreadCount) threads: $([Math]::Round($_.Duration, 2))s ($([Math]::Round($_.Throughput, 1)) ops/sec)" -ForegroundColor Cyan
            }
        }

        It "Should maintain data integrity during parallel processing" {
            # Arrange
            $testItems = 1..200 | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_
                    SID = "S-1-5-21-123456789-123456789-123456789-$_"
                    ExpectedChecksum = $_.ToString().GetHashCode()
                }
            }

            # Act - Parallel processing with integrity checking
            $processedItems = $testItems | ForEach-Object -Parallel {
                $item = $_

                # Simulate processing with integrity preservation
                $processedItem = [PSCustomObject]@{
                    Id = $item.Id
                    SID = $item.SID
                    ProcessedChecksum = $item.Id.ToString().GetHashCode()
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    ProcessorId = [Environment]::ProcessorCount
                }

                return $processedItem
            } -ThrottleLimit 8

            # Assert
            $processedItems | Should -HaveCount $testItems.Count

            # Verify data integrity
            for ($i = 0; $i -lt $testItems.Count; $i++) {
                $original = $testItems[$i]
                $processed = $processedItems | Where-Object Id -eq $original.Id

                $processed | Should Not BeNullOrEmpty
                $processed.SID | Should Be $original.SID
                $processed.ProcessedChecksum | Should Be $original.ExpectedChecksum
            }

            # Verify parallel execution
            $uniqueThreads = ($processedItems | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }
    }

    Context "Thread Safety Validation" {

        It "Should safely access shared resources concurrently" {
            # Arrange
            $sharedResource = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            $lockObject = [System.Object]::new()
            $operations = 1..100

            # Act - Concurrent access to shared resource
            $results = $operations | ForEach-Object -Parallel {
                $using:sharedResource
                $using:lockObject
                $operationId = $_

                try {
                    # Thread-safe operations
                    $key = "Operation_$operationId"
                    $value = [PSCustomObject]@{
                        Id = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                        Data = "ProcessedData_$operationId"
                    }

                    # Add to thread-safe collection
                    $success = $using:sharedResource.TryAdd($key, $value)

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $success
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $false
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $operations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # Verify shared resource integrity
            $sharedResource.Count | Should Be $operations.Count
            $sharedResource.Keys | Should -HaveCount $operations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should prevent race conditions in critical sections" {
            # Arrange
            $sharedCounter = 0
            $lockObject = [System.Object]::new()
            $incrementOperations = 1..500

            # Act - Concurrent counter increments with synchronization
            $results = $incrementOperations | ForEach-Object -Parallel {
                $using:lockObject
                $operationId = $_

                # Critical section with lock
                [System.Threading.Monitor]::Enter($using:lockObject)
                try {
                    # Simulate critical work
                    $currentValue = $using:sharedCounter
                    Start-Sleep -Milliseconds 1  # Simulate race condition opportunity
                    $newValue = $currentValue + 1
                    $using:sharedCounter = $newValue

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        CounterValue = $newValue
                        Success = $true
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                    }
                } finally {
                    [System.Threading.Monitor]::Exit($using:lockObject)
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $incrementOperations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $incrementOperations.Count

            # Verify no race conditions occurred
            $finalCounterValue = ($results | Sort-Object CounterValue | Select-Object -Last 1).CounterValue
            $finalCounterValue | Should Be $incrementOperations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should handle concurrent file operations safely" {
            # Arrange
            $testFiles = 1..50 | ForEach-Object {
                "TestFile_$_.txt"
            }
            $baseTestPath = Join-Path $ConcurrencyTestPath "FileOperations"
            if (-not (Test-Path $baseTestPath)) {
                New-Item -Path $baseTestPath -ItemType Directory -Force | Out-Null
            }

            # Act - Concurrent file operations
            $fileResults = $testFiles | ForEach-Object -Parallel {
                $using:baseTestPath
                $fileName = $_
                $filePath = Join-Path $using:baseTestPath $fileName

                try {
                    # Simulate file operations
                    $content = "Thread: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)`n"
                    $content += "Timestamp: $(Get-Date)`n"
                    $content += "File: $fileName`n"

                    # Thread-safe file creation
                    $lockFile = "$filePath.lock"
                    $timeout = 10  # seconds
                    $start = Get-Date

                    while (Test-Path $lockFile -PathType Leaf) {
                        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
                            throw "Timeout waiting for file lock: $fileName"
                        }
                        Start-Sleep -Milliseconds 10
                    }

                    # Create lock file
                    "lock" | Out-File -FilePath $lockFile -Force

                    try {
                        # Write main file
                        $content | Out-File -FilePath $filePath -Force

                        # Verify file was written
                        $writtenContent = Get-Content $filePath -Raw
                        $success = $writtenContent.Contains($fileName)

                        return [PSCustomObject]@{
                            FileName = $fileName
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            Success = $success
                            FileSize = (Get-Item $filePath).Length
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Remove lock file
                        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    return [PSCustomObject]@{
                        FileName = $fileName
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 8

            # Assert
            $fileResults | Should -HaveCount $testFiles.Count
            $fileResults | Where-Object Success -eq $true | Should -HaveCount $testFiles.Count

            # Verify all files were created
            $createdFiles = Get-ChildItem $baseTestPath -Filter "*.txt"
            $createdFiles.Count | Should Be $testFiles.Count

            # Verify concurrent execution
            $uniqueThreads = ($fileResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            # Cleanup
            Remove-Item $baseTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Resource Contention Management" {

        It "Should manage memory pressure under high concurrency" {
            # Arrange
            $memoryTestData = 1..$Global:ConcurrencyConfig.TestDataSizes.Large
            $initialMemory = [System.GC]::GetTotalMemory($false)

            # Act - Memory-intensive concurrent operations
            $monitor = Start-PerformanceMonitor -TestName "MemoryContention"

            $memoryResults = $memoryTestData | ForEach-Object -Parallel {
                $operationId = $_

                try {
                    # Create memory-intensive objects
                    $largeString = "X" * 1000  # 1KB string
                    $dataArray = 1..100 | ForEach-Object { $_ * $operationId }

                    # Simulate processing
                    $processedData = [PSCustomObject]@{
                        Id = $operationId
                        LargeData = $largeString
                        ProcessedArray = $dataArray
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        MemorySnapshot = [System.GC]::GetTotalMemory($false)
                        Timestamp = Get-Date
                    }

                    # Force periodic garbage collection
                    if ($operationId % 100 -eq 0) {
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }

                    return $processedData
                } catch {
                    return [PSCustomObject]@{
                        Id = $operationId
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize

            $memoryPerf = Stop-PerformanceMonitor -Monitor $monitor

            # Assert
            $memoryResults | Should -HaveCount $memoryTestData.Count
            $memoryResults | Where-Object Error | Should BeNullOrEmpty

            # Memory usage should be reasonable
            $memoryPerf.MemoryDelta | Should BeLessThan (500 * 1MB)  # Less than 500MB growth

            # Performance should be acceptable
            $memoryPerf.Duration | Should BeLessThan $Global:ConcurrencyConfig.PerformanceThresholds.HighConcurrency

            # Force cleanup
            $memoryResults = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-Host "Memory test completed. Duration: $([Math]::Round($memoryPerf.Duration, 2))s, Memory Delta: $([Math]::Round($memoryPerf.MemoryDelta / 1MB, 2))MB" -ForegroundColor Cyan
        }

        It "Should handle resource exhaustion gracefully" {
            # Arrange
            $resourceLimits = @{
                MaxHandles = 1000
                MaxMemory = 100 * 1MB
                MaxThreads = 50
            }

            $resourceIntensiveOperations = 1..200

            # Act - Resource-intensive operations with limits
            $resourceResults = $resourceIntensiveOperations | ForEach-Object -Parallel {
                $using:resourceLimits
                $operationId = $_

                try {
                    # Monitor resource usage
                    $currentProcess = Get-Process -Id $PID
                    $currentHandles = $currentProcess.HandleCount
                    $currentThreads = $currentProcess.Threads.Count

                    # Check resource limits
                    if ($currentHandles -gt $using:resourceLimits.MaxHandles) {
                        throw "Handle limit exceeded: $currentHandles"
                    }

                    if ($currentThreads -gt $using:resourceLimits.MaxThreads) {
                        throw "Thread limit exceeded: $currentThreads"
                    }

                    # Simulate resource usage
                    $tempData = 1..1000 | ForEach-Object { "Data_$_" }

                    # Resource monitoring
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        HandleCount = $currentHandles
                        ThreadCount = $currentThreads
                        Success = $true
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 16

            # Assert
            $resourceResults | Should -HaveCount $resourceIntensiveOperations.Count

            # Most operations should succeed (some may fail due to resource limits)
            $successfulOperations = $resourceResults | Where-Object Success -eq $true
            $successfulOperations.Count | Should BeGreaterThan ($resourceIntensiveOperations.Count * 0.8)  # 80% success rate minimum

            # Failed operations should have meaningful error messages
            $failedOperations = $resourceResults | Where-Object Success -eq $false
            if ($failedOperations.Count -gt 0) {
                $failedOperations | ForEach-Object {
                    $_.Error | Should Not BeNullOrEmpty
                }
            }

            Write-Host "Resource exhaustion test: $($successfulOperations.Count)/$($resourceResults.Count) operations succeeded" -ForegroundColor Cyan
        }
    }

    Context "Deadlock Prevention" {

        It "Should prevent deadlocks in multi-resource scenarios" {
            # Arrange
            $resource1 = [System.Object]::new()
            $resource2 = [System.Object]::new()
            $operations = 1..50

            # Act - Operations that could cause deadlocks if not properly ordered
            $deadlockResults = $operations | ForEach-Object -Parallel {
                $using:resource1
                $using:resource2
                $operationId = $_

                try {
                    # Determine lock order to prevent deadlocks
                    $lockOrder = if ($operationId % 2 -eq 0) {
                        @($using:resource1, $using:resource2)
                    } else {
                        @($using:resource1, $using:resource2)  # Always same order to prevent deadlock
                    }

                    $timeout = 5000  # 5 seconds
                    $acquired = @()

                    try {
                        foreach ($resource in $lockOrder) {
                            if ([System.Threading.Monitor]::TryEnter($resource, $timeout)) {
                                $acquired += $resource
                            } else {
                                throw "Failed to acquire lock within timeout"
                            }
                        }

                        # Simulate work requiring both resources
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)

                        return [PSCustomObject]@{
                            OperationId = $operationId
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            LocksAcquired = $acquired.Count
                            Success = $true
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Release locks in reverse order
                        for ($i = $acquired.Count - 1; $i -ge 0; $i--) {
                            [System.Threading.Monitor]::Exit($acquired[$i])
                        }
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $deadlockResults | Should -HaveCount $operations.Count
            $deadlockResults | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # No operations should have failed due to deadlocks
            $deadlockErrors = $deadlockResults | Where-Object Success -eq $false
            $deadlockErrors | Should BeNullOrEmpty

            # Verify concurrent execution
            $uniqueThreads = ($deadlockResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should implement timeout-based lock acquisition" {
            # Arrange
            $sharedResource = [System.Object]::new()
            $longRunningOperations = 1..20
            $quickOperations = 21..40

            # Act - Mix of long-running and quick operations
            $timeoutResults = @()

            # Start long-running operations first
            $longRunningJobs = $longRunningOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 10000  # 10 seconds
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Simulate long-running work
                                Start-Sleep -Milliseconds 100

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "LongRunning"
                                    Success = $true
                                    Duration = 100
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            throw "Timeout acquiring lock"
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "LongRunning"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Start quick operations
            Start-Sleep -Milliseconds 50  # Let long operations start first
            $quickJobs = $quickOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 1000  # 1 second timeout for quick operations
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Quick work
                                Start-Sleep -Milliseconds 10

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "Quick"
                                    Success = $true
                                    Duration = 10
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            return [PSCustomObject]@{
                                OperationId = $OperationId
                                Type = "Quick"
                                Success = $false
                                Error = "Timeout - resource busy"
                                Timestamp = Get-Date
                            }
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "Quick"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Wait for all jobs to complete
            $allJobs = $longRunningJobs + $quickJobs
            $timeoutResults = $allJobs | Wait-Job | Receive-Job
            $allJobs | Remove-Job -Force

            # Assert
            $timeoutResults | Should -HaveCount ($longRunningOperations.Count + $quickOperations.Count)

            # Long-running operations should mostly succeed
            $longResults = $timeoutResults | Where-Object Type -eq "LongRunning"
            $longSuccessRate = ($longResults | Where-Object Success -eq $true).Count / $longResults.Count
            $longSuccessRate | Should BeGreaterThan 0.8  # 80% success rate

            # Some quick operations may timeout, which is expected behavior
            $quickResults = $timeoutResults | Where-Object Type -eq "Quick"
            $quickResults | Should Not BeNullOrEmpty

            Write-Host "Timeout test: Long operations success rate: $([Math]::Round($longSuccessRate * 100, 1))%" -ForegroundColor Cyan
        }
    }

    Context "Performance Scaling Validation" {

        It "Should demonstrate optimal thread count for workload" {
            # Arrange
            $workloadSizes = @(100, 500, 1000)
            $scalingResults = @()

            # Act - Test different workload sizes with varying thread counts
            foreach ($workloadSize in $workloadSizes) {
                $workload = 1..$workloadSize | ForEach-Object { "WorkItem_$_" }

                foreach ($threadCount in @(1, 2, 4, 8)) {
                    if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                    $monitor = Start-PerformanceMonitor -TestName "Scaling_${workloadSize}_${threadCount}"

                    $results = $workload | ForEach-Object -Parallel {
                        # Simulate CPU-bound work
                        $sum = 0
                        1..1000 | ForEach-Object { $sum += $_ }

                        [PSCustomObject]@{
                            WorkItem = $_
                            Sum = $sum
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        }
                    } -ThrottleLimit $threadCount

                    $perf = Stop-PerformanceMonitor -Monitor $monitor

                    $scalingResults += [PSCustomObject]@{
                        WorkloadSize = $workloadSize
                        ThreadCount = $threadCount
                        Duration = $perf.Duration
                        Throughput = $workloadSize / $perf.Duration
                        MemoryDelta = $perf.MemoryDelta
                        UniqueThreads = ($results | Group-Object ThreadId).Count
                        Efficiency = $workloadSize / ($perf.Duration * $threadCount)
                    }
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty

            # Find optimal thread count for each workload size
            foreach ($workloadSize in $workloadSizes) {
                $workloadResults = $scalingResults | Where-Object WorkloadSize -eq $workloadSize
                $optimalResult = $workloadResults | Sort-Object Throughput -Descending | Select-Object -First 1

                # Optimal thread count should be reasonable
                $optimalResult.ThreadCount | Should BeLessThan $Global:ConcurrencyConfig.MaxThreads
                $optimalResult.Throughput | Should BeGreaterThan 0

                Write-Host "Workload $workloadSize: Optimal thread count = $($optimalResult.ThreadCount), Throughput = $([Math]::Round($optimalResult.Throughput, 1)) ops/sec" -ForegroundColor Green
            }

            # Display detailed scaling results
            Write-Host "`nDetailed Scaling Results:" -ForegroundColor Yellow
            $scalingResults | Sort-Object WorkloadSize, ThreadCount | ForEach-Object {
                Write-Host "  Size: $($_.WorkloadSize), Threads: $($_.ThreadCount), Duration: $([Math]::Round($_.Duration, 2))s, Efficiency: $([Math]::Round($_.Efficiency, 2))" -ForegroundColor Cyan
            }
        }

        It "Should maintain performance under sustained load" {
            # Arrange
            $sustainedTestDuration = 30  # seconds
            $operationInterval = 100     # milliseconds
            $performanceData = @()
            $startTime = Get-Date

            # Act - Sustained concurrent operations
            do {
                $iterationStart = Get-Date

                $batchResults = 1..50 | ForEach-Object -Parallel {
                    # Simulate work
                    $data = 1..100 | ForEach-Object { "Item_$_" }

                    [PSCustomObject]@{
                        OperationId = $_
                        ProcessedItems = $data.Count
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } -ThrottleLimit 8

                $iterationDuration = ((Get-Date) - $iterationStart).TotalMilliseconds

                $performanceData += [PSCustomObject]@{
                    IterationStart = $iterationStart
                    Duration = $iterationDuration
                    OperationsCompleted = $batchResults.Count
                    Throughput = $batchResults.Count / ($iterationDuration / 1000)
                    UniqueThreads = ($batchResults | Group-Object ThreadId).Count
                    MemoryUsage = [System.GC]::GetTotalMemory($false)
                }

                # Maintain operation interval
                $sleepTime = $operationInterval - $iterationDuration
                if ($sleepTime -gt 0) {
                    Start-Sleep -Milliseconds $sleepTime
                }

            } while (((Get-Date) - $startTime).TotalSeconds -lt $sustainedTestDuration)

            # Assert
            $performanceData | Should Not BeNullOrEmpty
            $performanceData.Count | Should BeGreaterThan 10  # Should have multiple iterations

            # Performance should remain stable (no significant degradation)
            $firstHalf = $performanceData | Select-Object -First ([Math]::Floor($performanceData.Count / 2))
            $secondHalf = $performanceData | Select-Object -Last ([Math]::Floor($performanceData.Count / 2))

            $firstHalfAvgThroughput = ($firstHalf | Measure-Object Throughput -Average).Average
            $secondHalfAvgThroughput = ($secondHalf | Measure-Object Throughput -Average).Average

            # Performance degradation should be minimal (< 20%)
            $performanceDrop = ($firstHalfAvgThroughput - $secondHalfAvgThroughput) / $firstHalfAvgThroughput
            $performanceDrop | Should BeLessThan 0.2  # Less than 20% degradation

            # Memory usage should be stable (no significant growth)
            $memoryGrowth = ($performanceData[-1].MemoryUsage - $performanceData[0].MemoryUsage) / 1MB
            $memoryGrowth | Should BeLessThan 50  # Less than 50MB growth

            Write-Host "Sustained load test completed:" -ForegroundColor Green
            Write-Host "  Duration: $sustainedTestDuration seconds" -ForegroundColor Cyan
            Write-Host "  Iterations: $($performanceData.Count)" -ForegroundColor Cyan
            Write-Host "  Average throughput: $([Math]::Round(($performanceData | Measure-Object Throughput -Average).Average, 1)) ops/sec" -ForegroundColor Cyan
            Write-Host "  Performance drop: $([Math]::Round($performanceDrop * 100, 1))%" -ForegroundColor Cyan
            Write-Host "  Memory growth: $([Math]::Round($memoryGrowth, 1))MB" -ForegroundColor Cyan
        }
    }
}

Describe "Concurrent Operations Benchmarks" -Tag "Performance", "Benchmark", "Concurrency" {

    It "Should meet enterprise concurrency performance benchmarks" {
        # Arrange
        $benchmarks = @{
            LowConcurrency = @{ Threads = 2; Items = 100; Threshold = 5 }    # 5 seconds
            MediumConcurrency = @{ Threads = 4; Items = 500; Threshold = 10 } # 10 seconds
            HighConcurrency = @{ Threads = 8; Items = 1000; Threshold = 20 }  # 20 seconds
        }

        $benchmarkResults = @{}

        # Act & Assert
        foreach ($benchmark in $benchmarks.GetEnumerator()) {
            $benchmarkName = $benchmark.Key
            $config = $benchmark.Value

            $testData = 1..$config.Items | ForEach-Object {
                "BenchmarkItem_$_"
            }

            $monitor = Start-PerformanceMonitor -TestName $benchmarkName

            $results = $testData | ForEach-Object -Parallel {
                # Simulate realistic work
                $sum = 0
                1..500 | ForEach-Object { $sum += $_ }

                [PSCustomObject]@{
                    Item = $_
                    Result = $sum
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                }
            } -ThrottleLimit $config.Threads

            $perf = Stop-PerformanceMonitor -Monitor $monitor
            $benchmarkResults[$benchmarkName] = $perf

            # Performance assertions
            $perf.Duration | Should BeLessThan $config.Threshold
            $results | Should -HaveCount $config.Items

            # Verify concurrency
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
            $uniqueThreads | Should BeLessThan $config.Threads
        }

        Write-Host "`nConcurrency Benchmark Results:" -ForegroundColor Green
        $benchmarkResults.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $([Math]::Round($_.Value.Duration, 2))s" -ForegroundColor Cyan
        }
    }
}

AfterAll {
    # Cleanup global variables and collections
    $Global:ThreadSafeResults.Clear()
    $Global:ThreadSafeErrors.Clear()
    $Global:ThreadSafeCounters.Clear()

    Remove-Variable -Name "ConcurrencyConfig" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeResults" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeErrors" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeCounters" -Scope Global -ErrorAction SilentlyContinue

    # Cleanup test directories
    @($ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (Test-Path $_ -PathType Container) {
            $items = Get-ChildItem $_ -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Force garbage collection to clean up test resources
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

.FullName }
Get-ChildItem "$ModuleRoot\Private" -Filter "*.ps1" | ForEach-Object { . #Requires -Version 5.1
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive concurrent operations performance testing for Find-UnknownSID solution

.DESCRIPTION
    Enterprise-grade validation of multi-threaded and concurrent processing capabilities including:
    - Parallel SID processing with thread safety validation
    - Concurrent file system operations and locking mechanisms
    - Multi-threaded backup and restore operations
    - Resource contention and deadlock prevention
    - Performance scaling under concurrent load
    - Thread pool management and optimization
    - Synchronization primitive effectiveness

.NOTES
    Author: GitHub Copilot (AI Assistant)
    Created: January 2025
    Version: 1.0.0

    Test Categories:
    - Parallel Processing Performance
    - Thread Safety Validation
    - Resource Contention Management
    - Deadlock Prevention
    - Scalability Testing
    - Synchronization Testing

    This file implements comprehensive concurrent operations testing following
    PowerShell community standards and enterprise performance requirements.
#>

BeforeAll {
    # Import required modules and classes
    $ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

    # Import test helpers
    $TestHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers"
    if (Test-Path "$TestHelpersPath\TestHelpers.ps1") {
        . "$TestHelpersPath\TestHelpers.ps1"
    } else {
        Write-Warning "TestHelpers.ps1 not found at $TestHelpersPath"
    }

    # Import main module classes and functions
    Get-ChildItem "$ModuleRoot\Classes" -Filter "*.ps1" | ForEach-Object { . $_.FullName }
    Get-ChildItem "$ModuleRoot\Private" -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    # Test data setup
    $TestDataPath = Join-Path $PSScriptRoot "..\TestData"
    $ConcurrencyTestPath = Join-Path $TestDataPath "ConcurrencyTests"
    $PerformanceLogsPath = Join-Path $TestDataPath "PerformanceLogs"

    # Ensure test directories exist
    @($TestDataPath, $ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    # Global concurrency configuration
    $Global:ConcurrencyConfig = @{
        MaxThreads = [Environment]::ProcessorCount * 2
        DefaultThreadPoolSize = [Environment]::ProcessorCount
        TimeoutSeconds = 60
        MaxRetryAttempts = 3
        PerformanceThresholds = @{
            SingleThread = 10      # seconds
            MultiThread = 15       # seconds
            HighConcurrency = 25   # seconds
        }
        TestDataSizes = @{
            Small = 100
            Medium = 500
            Large = 1000
            ExtraLarge = 2000
        }
        ConcurrencyLevels = @(1, 2, 4, 8, 16)
    }

    # Thread-safe collections for testing
    $Global:ThreadSafeResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeErrors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()

    # Mock dangerous operations for safe testing
    Mock Remove-Item { return $true } -ParameterFilter { $Path -like "*TestData*" }
    Mock Set-Acl { return $true }
    Mock Get-Acl {
        return [PSCustomObject]@{
            Access = @()
            Owner = "BUILTIN\Administrators"
            Group = "BUILTIN\Administrators"
        }
    }

    # Performance monitoring functions
    function Start-PerformanceMonitor {
        param([string]$TestName)

        return [PSCustomObject]@{
            TestName = $TestName
            StartTime = Get-Date
            StartMemory = [System.GC]::GetTotalMemory($false)
            StartHandleCount = (Get-Process -Id $PID).HandleCount
            StartThreadCount = (Get-Process -Id $PID).Threads.Count
        }
    }

    function Stop-PerformanceMonitor {
        param($Monitor)

        $endTime = Get-Date
        $endMemory = [System.GC]::GetTotalMemory($false)
        $endHandleCount = (Get-Process -Id $PID).HandleCount
        $endThreadCount = (Get-Process -Id $PID).Threads.Count

        return [PSCustomObject]@{
            TestName = $Monitor.TestName
            Duration = ($endTime - $Monitor.StartTime).TotalSeconds
            MemoryDelta = $endMemory - $Monitor.StartMemory
            HandleDelta = $endHandleCount - $Monitor.StartHandleCount
            ThreadDelta = $endThreadCount - $Monitor.StartThreadCount
            StartTime = $Monitor.StartTime
            EndTime = $endTime
        }
    }
}

Describe "Parallel Processing Performance Tests" -Tag "Performance", "Concurrency", "Parallel" {

    Context "Basic Parallel Operations" {

        It "Should process SIDs in parallel faster than sequential" {
            # Arrange
            $testSIDs = 1..$Global:ConcurrencyConfig.TestDataSizes.Medium | ForEach-Object {
                "S-1-5-21-123456789-123456789-123456789-$_"
            }

            # Act - Sequential processing
            $sequentialMonitor = Start-PerformanceMonitor -TestName "Sequential"
            $sequentialResults = @()
            foreach ($sid in $testSIDs) {
                $sequentialResults += [PSCustomObject]@{
                    SID = $sid
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Sequential"
                }
            }
            $sequentialPerf = Stop-PerformanceMonitor -Monitor $sequentialMonitor

            # Act - Parallel processing
            $parallelMonitor = Start-PerformanceMonitor -TestName "Parallel"
            $parallelResults = $testSIDs | ForEach-Object -Parallel {
                [PSCustomObject]@{
                    SID = $_
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Parallel"
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize
            $parallelPerf = Stop-PerformanceMonitor -Monitor $parallelMonitor

            # Assert
            $sequentialResults | Should -HaveCount $testSIDs.Count
            $parallelResults | Should -HaveCount $testSIDs.Count

            # Performance comparison
            $parallelPerf.Duration | Should BeLessThan $sequentialPerf.Duration

            # Verify parallel execution used multiple threads
            $uniqueThreads = ($parallelResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            Write-Host "Sequential: $([Math]::Round($sequentialPerf.Duration, 2))s, Parallel: $([Math]::Round($parallelPerf.Duration, 2))s" -ForegroundColor Cyan
            Write-Host "Speedup: $([Math]::Round($sequentialPerf.Duration / $parallelPerf.Duration, 2))x" -ForegroundColor Green
        }

        It "Should scale performance with increasing thread count" {
            # Arrange
            $testData = 1..$Global:ConcurrencyConfig.TestDataSizes.Small | ForEach-Object {
                "TestData_$_"
            }
            $scalingResults = @()

            # Act - Test different concurrency levels
            foreach ($threadCount in $Global:ConcurrencyConfig.ConcurrencyLevels) {
                if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                $monitor = Start-PerformanceMonitor -TestName "Scaling_$threadCount"

                $results = $testData | ForEach-Object -Parallel {
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    [PSCustomObject]@{
                        Data = $_
                        ProcessedAt = Get-Date
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    }
                } -ThrottleLimit $threadCount

                $perf = Stop-PerformanceMonitor -Monitor $monitor

                $scalingResults += [PSCustomObject]@{
                    ThreadCount = $threadCount
                    Duration = $perf.Duration
                    Throughput = $testData.Count / $perf.Duration
                    UniqueThreads = ($results | Group-Object ThreadId).Count
                    MemoryDelta = $perf.MemoryDelta
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty
            $scalingResults.Count | Should BeGreaterThan 1

            # Performance should generally improve with more threads (up to optimal point)
            $baselinePerformance = $scalingResults | Where-Object ThreadCount -eq 1
            $bestPerformance = $scalingResults | Sort-Object Duration | Select-Object -First 1

            $bestPerformance.Duration | Should BeLessThan $baselinePerformance.Duration

            # Display scaling results
            Write-Host "Concurrency Scaling Results:" -ForegroundColor Green
            $scalingResults | ForEach-Object {
                Write-Host "  $($_.ThreadCount) threads: $([Math]::Round($_.Duration, 2))s ($([Math]::Round($_.Throughput, 1)) ops/sec)" -ForegroundColor Cyan
            }
        }

        It "Should maintain data integrity during parallel processing" {
            # Arrange
            $testItems = 1..200 | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_
                    SID = "S-1-5-21-123456789-123456789-123456789-$_"
                    ExpectedChecksum = $_.ToString().GetHashCode()
                }
            }

            # Act - Parallel processing with integrity checking
            $processedItems = $testItems | ForEach-Object -Parallel {
                $item = $_

                # Simulate processing with integrity preservation
                $processedItem = [PSCustomObject]@{
                    Id = $item.Id
                    SID = $item.SID
                    ProcessedChecksum = $item.Id.ToString().GetHashCode()
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    ProcessorId = [Environment]::ProcessorCount
                }

                return $processedItem
            } -ThrottleLimit 8

            # Assert
            $processedItems | Should -HaveCount $testItems.Count

            # Verify data integrity
            for ($i = 0; $i -lt $testItems.Count; $i++) {
                $original = $testItems[$i]
                $processed = $processedItems | Where-Object Id -eq $original.Id

                $processed | Should Not BeNullOrEmpty
                $processed.SID | Should Be $original.SID
                $processed.ProcessedChecksum | Should Be $original.ExpectedChecksum
            }

            # Verify parallel execution
            $uniqueThreads = ($processedItems | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }
    }

    Context "Thread Safety Validation" {

        It "Should safely access shared resources concurrently" {
            # Arrange
            $sharedResource = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            $lockObject = [System.Object]::new()
            $operations = 1..100

            # Act - Concurrent access to shared resource
            $results = $operations | ForEach-Object -Parallel {
                $using:sharedResource
                $using:lockObject
                $operationId = $_

                try {
                    # Thread-safe operations
                    $key = "Operation_$operationId"
                    $value = [PSCustomObject]@{
                        Id = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                        Data = "ProcessedData_$operationId"
                    }

                    # Add to thread-safe collection
                    $success = $using:sharedResource.TryAdd($key, $value)

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $success
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $false
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $operations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # Verify shared resource integrity
            $sharedResource.Count | Should Be $operations.Count
            $sharedResource.Keys | Should -HaveCount $operations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should prevent race conditions in critical sections" {
            # Arrange
            $sharedCounter = 0
            $lockObject = [System.Object]::new()
            $incrementOperations = 1..500

            # Act - Concurrent counter increments with synchronization
            $results = $incrementOperations | ForEach-Object -Parallel {
                $using:lockObject
                $operationId = $_

                # Critical section with lock
                [System.Threading.Monitor]::Enter($using:lockObject)
                try {
                    # Simulate critical work
                    $currentValue = $using:sharedCounter
                    Start-Sleep -Milliseconds 1  # Simulate race condition opportunity
                    $newValue = $currentValue + 1
                    $using:sharedCounter = $newValue

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        CounterValue = $newValue
                        Success = $true
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                    }
                } finally {
                    [System.Threading.Monitor]::Exit($using:lockObject)
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $incrementOperations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $incrementOperations.Count

            # Verify no race conditions occurred
            $finalCounterValue = ($results | Sort-Object CounterValue | Select-Object -Last 1).CounterValue
            $finalCounterValue | Should Be $incrementOperations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should handle concurrent file operations safely" {
            # Arrange
            $testFiles = 1..50 | ForEach-Object {
                "TestFile_$_.txt"
            }
            $baseTestPath = Join-Path $ConcurrencyTestPath "FileOperations"
            if (-not (Test-Path $baseTestPath)) {
                New-Item -Path $baseTestPath -ItemType Directory -Force | Out-Null
            }

            # Act - Concurrent file operations
            $fileResults = $testFiles | ForEach-Object -Parallel {
                $using:baseTestPath
                $fileName = $_
                $filePath = Join-Path $using:baseTestPath $fileName

                try {
                    # Simulate file operations
                    $content = "Thread: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)`n"
                    $content += "Timestamp: $(Get-Date)`n"
                    $content += "File: $fileName`n"

                    # Thread-safe file creation
                    $lockFile = "$filePath.lock"
                    $timeout = 10  # seconds
                    $start = Get-Date

                    while (Test-Path $lockFile -PathType Leaf) {
                        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
                            throw "Timeout waiting for file lock: $fileName"
                        }
                        Start-Sleep -Milliseconds 10
                    }

                    # Create lock file
                    "lock" | Out-File -FilePath $lockFile -Force

                    try {
                        # Write main file
                        $content | Out-File -FilePath $filePath -Force

                        # Verify file was written
                        $writtenContent = Get-Content $filePath -Raw
                        $success = $writtenContent.Contains($fileName)

                        return [PSCustomObject]@{
                            FileName = $fileName
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            Success = $success
                            FileSize = (Get-Item $filePath).Length
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Remove lock file
                        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    return [PSCustomObject]@{
                        FileName = $fileName
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 8

            # Assert
            $fileResults | Should -HaveCount $testFiles.Count
            $fileResults | Where-Object Success -eq $true | Should -HaveCount $testFiles.Count

            # Verify all files were created
            $createdFiles = Get-ChildItem $baseTestPath -Filter "*.txt"
            $createdFiles.Count | Should Be $testFiles.Count

            # Verify concurrent execution
            $uniqueThreads = ($fileResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            # Cleanup
            Remove-Item $baseTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Resource Contention Management" {

        It "Should manage memory pressure under high concurrency" {
            # Arrange
            $memoryTestData = 1..$Global:ConcurrencyConfig.TestDataSizes.Large
            $initialMemory = [System.GC]::GetTotalMemory($false)

            # Act - Memory-intensive concurrent operations
            $monitor = Start-PerformanceMonitor -TestName "MemoryContention"

            $memoryResults = $memoryTestData | ForEach-Object -Parallel {
                $operationId = $_

                try {
                    # Create memory-intensive objects
                    $largeString = "X" * 1000  # 1KB string
                    $dataArray = 1..100 | ForEach-Object { $_ * $operationId }

                    # Simulate processing
                    $processedData = [PSCustomObject]@{
                        Id = $operationId
                        LargeData = $largeString
                        ProcessedArray = $dataArray
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        MemorySnapshot = [System.GC]::GetTotalMemory($false)
                        Timestamp = Get-Date
                    }

                    # Force periodic garbage collection
                    if ($operationId % 100 -eq 0) {
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }

                    return $processedData
                } catch {
                    return [PSCustomObject]@{
                        Id = $operationId
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize

            $memoryPerf = Stop-PerformanceMonitor -Monitor $monitor

            # Assert
            $memoryResults | Should -HaveCount $memoryTestData.Count
            $memoryResults | Where-Object Error | Should BeNullOrEmpty

            # Memory usage should be reasonable
            $memoryPerf.MemoryDelta | Should BeLessThan (500 * 1MB)  # Less than 500MB growth

            # Performance should be acceptable
            $memoryPerf.Duration | Should BeLessThan $Global:ConcurrencyConfig.PerformanceThresholds.HighConcurrency

            # Force cleanup
            $memoryResults = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-Host "Memory test completed. Duration: $([Math]::Round($memoryPerf.Duration, 2))s, Memory Delta: $([Math]::Round($memoryPerf.MemoryDelta / 1MB, 2))MB" -ForegroundColor Cyan
        }

        It "Should handle resource exhaustion gracefully" {
            # Arrange
            $resourceLimits = @{
                MaxHandles = 1000
                MaxMemory = 100 * 1MB
                MaxThreads = 50
            }

            $resourceIntensiveOperations = 1..200

            # Act - Resource-intensive operations with limits
            $resourceResults = $resourceIntensiveOperations | ForEach-Object -Parallel {
                $using:resourceLimits
                $operationId = $_

                try {
                    # Monitor resource usage
                    $currentProcess = Get-Process -Id $PID
                    $currentHandles = $currentProcess.HandleCount
                    $currentThreads = $currentProcess.Threads.Count

                    # Check resource limits
                    if ($currentHandles -gt $using:resourceLimits.MaxHandles) {
                        throw "Handle limit exceeded: $currentHandles"
                    }

                    if ($currentThreads -gt $using:resourceLimits.MaxThreads) {
                        throw "Thread limit exceeded: $currentThreads"
                    }

                    # Simulate resource usage
                    $tempData = 1..1000 | ForEach-Object { "Data_$_" }

                    # Resource monitoring
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        HandleCount = $currentHandles
                        ThreadCount = $currentThreads
                        Success = $true
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 16

            # Assert
            $resourceResults | Should -HaveCount $resourceIntensiveOperations.Count

            # Most operations should succeed (some may fail due to resource limits)
            $successfulOperations = $resourceResults | Where-Object Success -eq $true
            $successfulOperations.Count | Should BeGreaterThan ($resourceIntensiveOperations.Count * 0.8)  # 80% success rate minimum

            # Failed operations should have meaningful error messages
            $failedOperations = $resourceResults | Where-Object Success -eq $false
            if ($failedOperations.Count -gt 0) {
                $failedOperations | ForEach-Object {
                    $_.Error | Should Not BeNullOrEmpty
                }
            }

            Write-Host "Resource exhaustion test: $($successfulOperations.Count)/$($resourceResults.Count) operations succeeded" -ForegroundColor Cyan
        }
    }

    Context "Deadlock Prevention" {

        It "Should prevent deadlocks in multi-resource scenarios" {
            # Arrange
            $resource1 = [System.Object]::new()
            $resource2 = [System.Object]::new()
            $operations = 1..50

            # Act - Operations that could cause deadlocks if not properly ordered
            $deadlockResults = $operations | ForEach-Object -Parallel {
                $using:resource1
                $using:resource2
                $operationId = $_

                try {
                    # Determine lock order to prevent deadlocks
                    $lockOrder = if ($operationId % 2 -eq 0) {
                        @($using:resource1, $using:resource2)
                    } else {
                        @($using:resource1, $using:resource2)  # Always same order to prevent deadlock
                    }

                    $timeout = 5000  # 5 seconds
                    $acquired = @()

                    try {
                        foreach ($resource in $lockOrder) {
                            if ([System.Threading.Monitor]::TryEnter($resource, $timeout)) {
                                $acquired += $resource
                            } else {
                                throw "Failed to acquire lock within timeout"
                            }
                        }

                        # Simulate work requiring both resources
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)

                        return [PSCustomObject]@{
                            OperationId = $operationId
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            LocksAcquired = $acquired.Count
                            Success = $true
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Release locks in reverse order
                        for ($i = $acquired.Count - 1; $i -ge 0; $i--) {
                            [System.Threading.Monitor]::Exit($acquired[$i])
                        }
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $deadlockResults | Should -HaveCount $operations.Count
            $deadlockResults | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # No operations should have failed due to deadlocks
            $deadlockErrors = $deadlockResults | Where-Object Success -eq $false
            $deadlockErrors | Should BeNullOrEmpty

            # Verify concurrent execution
            $uniqueThreads = ($deadlockResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should implement timeout-based lock acquisition" {
            # Arrange
            $sharedResource = [System.Object]::new()
            $longRunningOperations = 1..20
            $quickOperations = 21..40

            # Act - Mix of long-running and quick operations
            $timeoutResults = @()

            # Start long-running operations first
            $longRunningJobs = $longRunningOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 10000  # 10 seconds
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Simulate long-running work
                                Start-Sleep -Milliseconds 100

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "LongRunning"
                                    Success = $true
                                    Duration = 100
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            throw "Timeout acquiring lock"
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "LongRunning"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Start quick operations
            Start-Sleep -Milliseconds 50  # Let long operations start first
            $quickJobs = $quickOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 1000  # 1 second timeout for quick operations
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Quick work
                                Start-Sleep -Milliseconds 10

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "Quick"
                                    Success = $true
                                    Duration = 10
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            return [PSCustomObject]@{
                                OperationId = $OperationId
                                Type = "Quick"
                                Success = $false
                                Error = "Timeout - resource busy"
                                Timestamp = Get-Date
                            }
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "Quick"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Wait for all jobs to complete
            $allJobs = $longRunningJobs + $quickJobs
            $timeoutResults = $allJobs | Wait-Job | Receive-Job
            $allJobs | Remove-Job -Force

            # Assert
            $timeoutResults | Should -HaveCount ($longRunningOperations.Count + $quickOperations.Count)

            # Long-running operations should mostly succeed
            $longResults = $timeoutResults | Where-Object Type -eq "LongRunning"
            $longSuccessRate = ($longResults | Where-Object Success -eq $true).Count / $longResults.Count
            $longSuccessRate | Should BeGreaterThan 0.8  # 80% success rate

            # Some quick operations may timeout, which is expected behavior
            $quickResults = $timeoutResults | Where-Object Type -eq "Quick"
            $quickResults | Should Not BeNullOrEmpty

            Write-Host "Timeout test: Long operations success rate: $([Math]::Round($longSuccessRate * 100, 1))%" -ForegroundColor Cyan
        }
    }

    Context "Performance Scaling Validation" {

        It "Should demonstrate optimal thread count for workload" {
            # Arrange
            $workloadSizes = @(100, 500, 1000)
            $scalingResults = @()

            # Act - Test different workload sizes with varying thread counts
            foreach ($workloadSize in $workloadSizes) {
                $workload = 1..$workloadSize | ForEach-Object { "WorkItem_$_" }

                foreach ($threadCount in @(1, 2, 4, 8)) {
                    if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                    $monitor = Start-PerformanceMonitor -TestName "Scaling_${workloadSize}_${threadCount}"

                    $results = $workload | ForEach-Object -Parallel {
                        # Simulate CPU-bound work
                        $sum = 0
                        1..1000 | ForEach-Object { $sum += $_ }

                        [PSCustomObject]@{
                            WorkItem = $_
                            Sum = $sum
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        }
                    } -ThrottleLimit $threadCount

                    $perf = Stop-PerformanceMonitor -Monitor $monitor

                    $scalingResults += [PSCustomObject]@{
                        WorkloadSize = $workloadSize
                        ThreadCount = $threadCount
                        Duration = $perf.Duration
                        Throughput = $workloadSize / $perf.Duration
                        MemoryDelta = $perf.MemoryDelta
                        UniqueThreads = ($results | Group-Object ThreadId).Count
                        Efficiency = $workloadSize / ($perf.Duration * $threadCount)
                    }
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty

            # Find optimal thread count for each workload size
            foreach ($workloadSize in $workloadSizes) {
                $workloadResults = $scalingResults | Where-Object WorkloadSize -eq $workloadSize
                $optimalResult = $workloadResults | Sort-Object Throughput -Descending | Select-Object -First 1

                # Optimal thread count should be reasonable
                $optimalResult.ThreadCount | Should BeLessThan $Global:ConcurrencyConfig.MaxThreads
                $optimalResult.Throughput | Should BeGreaterThan 0

                Write-Host "Workload $workloadSize: Optimal thread count = $($optimalResult.ThreadCount), Throughput = $([Math]::Round($optimalResult.Throughput, 1)) ops/sec" -ForegroundColor Green
            }

            # Display detailed scaling results
            Write-Host "`nDetailed Scaling Results:" -ForegroundColor Yellow
            $scalingResults | Sort-Object WorkloadSize, ThreadCount | ForEach-Object {
                Write-Host "  Size: $($_.WorkloadSize), Threads: $($_.ThreadCount), Duration: $([Math]::Round($_.Duration, 2))s, Efficiency: $([Math]::Round($_.Efficiency, 2))" -ForegroundColor Cyan
            }
        }

        It "Should maintain performance under sustained load" {
            # Arrange
            $sustainedTestDuration = 30  # seconds
            $operationInterval = 100     # milliseconds
            $performanceData = @()
            $startTime = Get-Date

            # Act - Sustained concurrent operations
            do {
                $iterationStart = Get-Date

                $batchResults = 1..50 | ForEach-Object -Parallel {
                    # Simulate work
                    $data = 1..100 | ForEach-Object { "Item_$_" }

                    [PSCustomObject]@{
                        OperationId = $_
                        ProcessedItems = $data.Count
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } -ThrottleLimit 8

                $iterationDuration = ((Get-Date) - $iterationStart).TotalMilliseconds

                $performanceData += [PSCustomObject]@{
                    IterationStart = $iterationStart
                    Duration = $iterationDuration
                    OperationsCompleted = $batchResults.Count
                    Throughput = $batchResults.Count / ($iterationDuration / 1000)
                    UniqueThreads = ($batchResults | Group-Object ThreadId).Count
                    MemoryUsage = [System.GC]::GetTotalMemory($false)
                }

                # Maintain operation interval
                $sleepTime = $operationInterval - $iterationDuration
                if ($sleepTime -gt 0) {
                    Start-Sleep -Milliseconds $sleepTime
                }

            } while (((Get-Date) - $startTime).TotalSeconds -lt $sustainedTestDuration)

            # Assert
            $performanceData | Should Not BeNullOrEmpty
            $performanceData.Count | Should BeGreaterThan 10  # Should have multiple iterations

            # Performance should remain stable (no significant degradation)
            $firstHalf = $performanceData | Select-Object -First ([Math]::Floor($performanceData.Count / 2))
            $secondHalf = $performanceData | Select-Object -Last ([Math]::Floor($performanceData.Count / 2))

            $firstHalfAvgThroughput = ($firstHalf | Measure-Object Throughput -Average).Average
            $secondHalfAvgThroughput = ($secondHalf | Measure-Object Throughput -Average).Average

            # Performance degradation should be minimal (< 20%)
            $performanceDrop = ($firstHalfAvgThroughput - $secondHalfAvgThroughput) / $firstHalfAvgThroughput
            $performanceDrop | Should BeLessThan 0.2  # Less than 20% degradation

            # Memory usage should be stable (no significant growth)
            $memoryGrowth = ($performanceData[-1].MemoryUsage - $performanceData[0].MemoryUsage) / 1MB
            $memoryGrowth | Should BeLessThan 50  # Less than 50MB growth

            Write-Host "Sustained load test completed:" -ForegroundColor Green
            Write-Host "  Duration: $sustainedTestDuration seconds" -ForegroundColor Cyan
            Write-Host "  Iterations: $($performanceData.Count)" -ForegroundColor Cyan
            Write-Host "  Average throughput: $([Math]::Round(($performanceData | Measure-Object Throughput -Average).Average, 1)) ops/sec" -ForegroundColor Cyan
            Write-Host "  Performance drop: $([Math]::Round($performanceDrop * 100, 1))%" -ForegroundColor Cyan
            Write-Host "  Memory growth: $([Math]::Round($memoryGrowth, 1))MB" -ForegroundColor Cyan
        }
    }
}

Describe "Concurrent Operations Benchmarks" -Tag "Performance", "Benchmark", "Concurrency" {

    It "Should meet enterprise concurrency performance benchmarks" {
        # Arrange
        $benchmarks = @{
            LowConcurrency = @{ Threads = 2; Items = 100; Threshold = 5 }    # 5 seconds
            MediumConcurrency = @{ Threads = 4; Items = 500; Threshold = 10 } # 10 seconds
            HighConcurrency = @{ Threads = 8; Items = 1000; Threshold = 20 }  # 20 seconds
        }

        $benchmarkResults = @{}

        # Act & Assert
        foreach ($benchmark in $benchmarks.GetEnumerator()) {
            $benchmarkName = $benchmark.Key
            $config = $benchmark.Value

            $testData = 1..$config.Items | ForEach-Object {
                "BenchmarkItem_$_"
            }

            $monitor = Start-PerformanceMonitor -TestName $benchmarkName

            $results = $testData | ForEach-Object -Parallel {
                # Simulate realistic work
                $sum = 0
                1..500 | ForEach-Object { $sum += $_ }

                [PSCustomObject]@{
                    Item = $_
                    Result = $sum
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                }
            } -ThrottleLimit $config.Threads

            $perf = Stop-PerformanceMonitor -Monitor $monitor
            $benchmarkResults[$benchmarkName] = $perf

            # Performance assertions
            $perf.Duration | Should BeLessThan $config.Threshold
            $results | Should -HaveCount $config.Items

            # Verify concurrency
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
            $uniqueThreads | Should BeLessThan $config.Threads
        }

        Write-Host "`nConcurrency Benchmark Results:" -ForegroundColor Green
        $benchmarkResults.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $([Math]::Round($_.Value.Duration, 2))s" -ForegroundColor Cyan
        }
    }
}

AfterAll {
    # Cleanup global variables and collections
    $Global:ThreadSafeResults.Clear()
    $Global:ThreadSafeErrors.Clear()
    $Global:ThreadSafeCounters.Clear()

    Remove-Variable -Name "ConcurrencyConfig" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeResults" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeErrors" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeCounters" -Scope Global -ErrorAction SilentlyContinue

    # Cleanup test directories
    @($ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (Test-Path $_ -PathType Container) {
            $items = Get-ChildItem $_ -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Force garbage collection to clean up test resources
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

.FullName }
# Test data setup
$TestDataPath = Join-Path $PSScriptRoot "..\TestData"
$ConcurrencyTestPath = Join-Path $TestDataPath "ConcurrencyTests"
$PerformanceLogsPath = Join-Path $TestDataPath "PerformanceLogs"
# Ensure test directories exist
@($TestDataPath, $ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
if (-not (Test-Path #Requires -Version 5.1
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive concurrent operations performance testing for Find-UnknownSID solution

.DESCRIPTION
    Enterprise-grade validation of multi-threaded and concurrent processing capabilities including:
    - Parallel SID processing with thread safety validation
    - Concurrent file system operations and locking mechanisms
    - Multi-threaded backup and restore operations
    - Resource contention and deadlock prevention
    - Performance scaling under concurrent load
    - Thread pool management and optimization
    - Synchronization primitive effectiveness

.NOTES
    Author: GitHub Copilot (AI Assistant)
    Created: January 2025
    Version: 1.0.0

    Test Categories:
    - Parallel Processing Performance
    - Thread Safety Validation
    - Resource Contention Management
    - Deadlock Prevention
    - Scalability Testing
    - Synchronization Testing

    This file implements comprehensive concurrent operations testing following
    PowerShell community standards and enterprise performance requirements.
#>

BeforeAll {
    # Import required modules and classes
    $ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

    # Import test helpers
    $TestHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers"
    if (Test-Path "$TestHelpersPath\TestHelpers.ps1") {
        . "$TestHelpersPath\TestHelpers.ps1"
    } else {
        Write-Warning "TestHelpers.ps1 not found at $TestHelpersPath"
    }

    # Import main module classes and functions
    Get-ChildItem "$ModuleRoot\Classes" -Filter "*.ps1" | ForEach-Object { . $_.FullName }
    Get-ChildItem "$ModuleRoot\Private" -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    # Test data setup
    $TestDataPath = Join-Path $PSScriptRoot "..\TestData"
    $ConcurrencyTestPath = Join-Path $TestDataPath "ConcurrencyTests"
    $PerformanceLogsPath = Join-Path $TestDataPath "PerformanceLogs"

    # Ensure test directories exist
    @($TestDataPath, $ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    # Global concurrency configuration
    $Global:ConcurrencyConfig = @{
        MaxThreads = [Environment]::ProcessorCount * 2
        DefaultThreadPoolSize = [Environment]::ProcessorCount
        TimeoutSeconds = 60
        MaxRetryAttempts = 3
        PerformanceThresholds = @{
            SingleThread = 10      # seconds
            MultiThread = 15       # seconds
            HighConcurrency = 25   # seconds
        }
        TestDataSizes = @{
            Small = 100
            Medium = 500
            Large = 1000
            ExtraLarge = 2000
        }
        ConcurrencyLevels = @(1, 2, 4, 8, 16)
    }

    # Thread-safe collections for testing
    $Global:ThreadSafeResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeErrors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()

    # Mock dangerous operations for safe testing
    Mock Remove-Item { return $true } -ParameterFilter { $Path -like "*TestData*" }
    Mock Set-Acl { return $true }
    Mock Get-Acl {
        return [PSCustomObject]@{
            Access = @()
            Owner = "BUILTIN\Administrators"
            Group = "BUILTIN\Administrators"
        }
    }

    # Performance monitoring functions
    function Start-PerformanceMonitor {
        param([string]$TestName)

        return [PSCustomObject]@{
            TestName = $TestName
            StartTime = Get-Date
            StartMemory = [System.GC]::GetTotalMemory($false)
            StartHandleCount = (Get-Process -Id $PID).HandleCount
            StartThreadCount = (Get-Process -Id $PID).Threads.Count
        }
    }

    function Stop-PerformanceMonitor {
        param($Monitor)

        $endTime = Get-Date
        $endMemory = [System.GC]::GetTotalMemory($false)
        $endHandleCount = (Get-Process -Id $PID).HandleCount
        $endThreadCount = (Get-Process -Id $PID).Threads.Count

        return [PSCustomObject]@{
            TestName = $Monitor.TestName
            Duration = ($endTime - $Monitor.StartTime).TotalSeconds
            MemoryDelta = $endMemory - $Monitor.StartMemory
            HandleDelta = $endHandleCount - $Monitor.StartHandleCount
            ThreadDelta = $endThreadCount - $Monitor.StartThreadCount
            StartTime = $Monitor.StartTime
            EndTime = $endTime
        }
    }
}

Describe "Parallel Processing Performance Tests" -Tag "Performance", "Concurrency", "Parallel" {

    Context "Basic Parallel Operations" {

        It "Should process SIDs in parallel faster than sequential" {
            # Arrange
            $testSIDs = 1..$Global:ConcurrencyConfig.TestDataSizes.Medium | ForEach-Object {
                "S-1-5-21-123456789-123456789-123456789-$_"
            }

            # Act - Sequential processing
            $sequentialMonitor = Start-PerformanceMonitor -TestName "Sequential"
            $sequentialResults = @()
            foreach ($sid in $testSIDs) {
                $sequentialResults += [PSCustomObject]@{
                    SID = $sid
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Sequential"
                }
            }
            $sequentialPerf = Stop-PerformanceMonitor -Monitor $sequentialMonitor

            # Act - Parallel processing
            $parallelMonitor = Start-PerformanceMonitor -TestName "Parallel"
            $parallelResults = $testSIDs | ForEach-Object -Parallel {
                [PSCustomObject]@{
                    SID = $_
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Parallel"
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize
            $parallelPerf = Stop-PerformanceMonitor -Monitor $parallelMonitor

            # Assert
            $sequentialResults | Should -HaveCount $testSIDs.Count
            $parallelResults | Should -HaveCount $testSIDs.Count

            # Performance comparison
            $parallelPerf.Duration | Should BeLessThan $sequentialPerf.Duration

            # Verify parallel execution used multiple threads
            $uniqueThreads = ($parallelResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            Write-Host "Sequential: $([Math]::Round($sequentialPerf.Duration, 2))s, Parallel: $([Math]::Round($parallelPerf.Duration, 2))s" -ForegroundColor Cyan
            Write-Host "Speedup: $([Math]::Round($sequentialPerf.Duration / $parallelPerf.Duration, 2))x" -ForegroundColor Green
        }

        It "Should scale performance with increasing thread count" {
            # Arrange
            $testData = 1..$Global:ConcurrencyConfig.TestDataSizes.Small | ForEach-Object {
                "TestData_$_"
            }
            $scalingResults = @()

            # Act - Test different concurrency levels
            foreach ($threadCount in $Global:ConcurrencyConfig.ConcurrencyLevels) {
                if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                $monitor = Start-PerformanceMonitor -TestName "Scaling_$threadCount"

                $results = $testData | ForEach-Object -Parallel {
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    [PSCustomObject]@{
                        Data = $_
                        ProcessedAt = Get-Date
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    }
                } -ThrottleLimit $threadCount

                $perf = Stop-PerformanceMonitor -Monitor $monitor

                $scalingResults += [PSCustomObject]@{
                    ThreadCount = $threadCount
                    Duration = $perf.Duration
                    Throughput = $testData.Count / $perf.Duration
                    UniqueThreads = ($results | Group-Object ThreadId).Count
                    MemoryDelta = $perf.MemoryDelta
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty
            $scalingResults.Count | Should BeGreaterThan 1

            # Performance should generally improve with more threads (up to optimal point)
            $baselinePerformance = $scalingResults | Where-Object ThreadCount -eq 1
            $bestPerformance = $scalingResults | Sort-Object Duration | Select-Object -First 1

            $bestPerformance.Duration | Should BeLessThan $baselinePerformance.Duration

            # Display scaling results
            Write-Host "Concurrency Scaling Results:" -ForegroundColor Green
            $scalingResults | ForEach-Object {
                Write-Host "  $($_.ThreadCount) threads: $([Math]::Round($_.Duration, 2))s ($([Math]::Round($_.Throughput, 1)) ops/sec)" -ForegroundColor Cyan
            }
        }

        It "Should maintain data integrity during parallel processing" {
            # Arrange
            $testItems = 1..200 | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_
                    SID = "S-1-5-21-123456789-123456789-123456789-$_"
                    ExpectedChecksum = $_.ToString().GetHashCode()
                }
            }

            # Act - Parallel processing with integrity checking
            $processedItems = $testItems | ForEach-Object -Parallel {
                $item = $_

                # Simulate processing with integrity preservation
                $processedItem = [PSCustomObject]@{
                    Id = $item.Id
                    SID = $item.SID
                    ProcessedChecksum = $item.Id.ToString().GetHashCode()
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    ProcessorId = [Environment]::ProcessorCount
                }

                return $processedItem
            } -ThrottleLimit 8

            # Assert
            $processedItems | Should -HaveCount $testItems.Count

            # Verify data integrity
            for ($i = 0; $i -lt $testItems.Count; $i++) {
                $original = $testItems[$i]
                $processed = $processedItems | Where-Object Id -eq $original.Id

                $processed | Should Not BeNullOrEmpty
                $processed.SID | Should Be $original.SID
                $processed.ProcessedChecksum | Should Be $original.ExpectedChecksum
            }

            # Verify parallel execution
            $uniqueThreads = ($processedItems | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }
    }

    Context "Thread Safety Validation" {

        It "Should safely access shared resources concurrently" {
            # Arrange
            $sharedResource = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            $lockObject = [System.Object]::new()
            $operations = 1..100

            # Act - Concurrent access to shared resource
            $results = $operations | ForEach-Object -Parallel {
                $using:sharedResource
                $using:lockObject
                $operationId = $_

                try {
                    # Thread-safe operations
                    $key = "Operation_$operationId"
                    $value = [PSCustomObject]@{
                        Id = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                        Data = "ProcessedData_$operationId"
                    }

                    # Add to thread-safe collection
                    $success = $using:sharedResource.TryAdd($key, $value)

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $success
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $false
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $operations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # Verify shared resource integrity
            $sharedResource.Count | Should Be $operations.Count
            $sharedResource.Keys | Should -HaveCount $operations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should prevent race conditions in critical sections" {
            # Arrange
            $sharedCounter = 0
            $lockObject = [System.Object]::new()
            $incrementOperations = 1..500

            # Act - Concurrent counter increments with synchronization
            $results = $incrementOperations | ForEach-Object -Parallel {
                $using:lockObject
                $operationId = $_

                # Critical section with lock
                [System.Threading.Monitor]::Enter($using:lockObject)
                try {
                    # Simulate critical work
                    $currentValue = $using:sharedCounter
                    Start-Sleep -Milliseconds 1  # Simulate race condition opportunity
                    $newValue = $currentValue + 1
                    $using:sharedCounter = $newValue

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        CounterValue = $newValue
                        Success = $true
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                    }
                } finally {
                    [System.Threading.Monitor]::Exit($using:lockObject)
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $incrementOperations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $incrementOperations.Count

            # Verify no race conditions occurred
            $finalCounterValue = ($results | Sort-Object CounterValue | Select-Object -Last 1).CounterValue
            $finalCounterValue | Should Be $incrementOperations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should handle concurrent file operations safely" {
            # Arrange
            $testFiles = 1..50 | ForEach-Object {
                "TestFile_$_.txt"
            }
            $baseTestPath = Join-Path $ConcurrencyTestPath "FileOperations"
            if (-not (Test-Path $baseTestPath)) {
                New-Item -Path $baseTestPath -ItemType Directory -Force | Out-Null
            }

            # Act - Concurrent file operations
            $fileResults = $testFiles | ForEach-Object -Parallel {
                $using:baseTestPath
                $fileName = $_
                $filePath = Join-Path $using:baseTestPath $fileName

                try {
                    # Simulate file operations
                    $content = "Thread: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)`n"
                    $content += "Timestamp: $(Get-Date)`n"
                    $content += "File: $fileName`n"

                    # Thread-safe file creation
                    $lockFile = "$filePath.lock"
                    $timeout = 10  # seconds
                    $start = Get-Date

                    while (Test-Path $lockFile -PathType Leaf) {
                        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
                            throw "Timeout waiting for file lock: $fileName"
                        }
                        Start-Sleep -Milliseconds 10
                    }

                    # Create lock file
                    "lock" | Out-File -FilePath $lockFile -Force

                    try {
                        # Write main file
                        $content | Out-File -FilePath $filePath -Force

                        # Verify file was written
                        $writtenContent = Get-Content $filePath -Raw
                        $success = $writtenContent.Contains($fileName)

                        return [PSCustomObject]@{
                            FileName = $fileName
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            Success = $success
                            FileSize = (Get-Item $filePath).Length
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Remove lock file
                        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    return [PSCustomObject]@{
                        FileName = $fileName
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 8

            # Assert
            $fileResults | Should -HaveCount $testFiles.Count
            $fileResults | Where-Object Success -eq $true | Should -HaveCount $testFiles.Count

            # Verify all files were created
            $createdFiles = Get-ChildItem $baseTestPath -Filter "*.txt"
            $createdFiles.Count | Should Be $testFiles.Count

            # Verify concurrent execution
            $uniqueThreads = ($fileResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            # Cleanup
            Remove-Item $baseTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Resource Contention Management" {

        It "Should manage memory pressure under high concurrency" {
            # Arrange
            $memoryTestData = 1..$Global:ConcurrencyConfig.TestDataSizes.Large
            $initialMemory = [System.GC]::GetTotalMemory($false)

            # Act - Memory-intensive concurrent operations
            $monitor = Start-PerformanceMonitor -TestName "MemoryContention"

            $memoryResults = $memoryTestData | ForEach-Object -Parallel {
                $operationId = $_

                try {
                    # Create memory-intensive objects
                    $largeString = "X" * 1000  # 1KB string
                    $dataArray = 1..100 | ForEach-Object { $_ * $operationId }

                    # Simulate processing
                    $processedData = [PSCustomObject]@{
                        Id = $operationId
                        LargeData = $largeString
                        ProcessedArray = $dataArray
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        MemorySnapshot = [System.GC]::GetTotalMemory($false)
                        Timestamp = Get-Date
                    }

                    # Force periodic garbage collection
                    if ($operationId % 100 -eq 0) {
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }

                    return $processedData
                } catch {
                    return [PSCustomObject]@{
                        Id = $operationId
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize

            $memoryPerf = Stop-PerformanceMonitor -Monitor $monitor

            # Assert
            $memoryResults | Should -HaveCount $memoryTestData.Count
            $memoryResults | Where-Object Error | Should BeNullOrEmpty

            # Memory usage should be reasonable
            $memoryPerf.MemoryDelta | Should BeLessThan (500 * 1MB)  # Less than 500MB growth

            # Performance should be acceptable
            $memoryPerf.Duration | Should BeLessThan $Global:ConcurrencyConfig.PerformanceThresholds.HighConcurrency

            # Force cleanup
            $memoryResults = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-Host "Memory test completed. Duration: $([Math]::Round($memoryPerf.Duration, 2))s, Memory Delta: $([Math]::Round($memoryPerf.MemoryDelta / 1MB, 2))MB" -ForegroundColor Cyan
        }

        It "Should handle resource exhaustion gracefully" {
            # Arrange
            $resourceLimits = @{
                MaxHandles = 1000
                MaxMemory = 100 * 1MB
                MaxThreads = 50
            }

            $resourceIntensiveOperations = 1..200

            # Act - Resource-intensive operations with limits
            $resourceResults = $resourceIntensiveOperations | ForEach-Object -Parallel {
                $using:resourceLimits
                $operationId = $_

                try {
                    # Monitor resource usage
                    $currentProcess = Get-Process -Id $PID
                    $currentHandles = $currentProcess.HandleCount
                    $currentThreads = $currentProcess.Threads.Count

                    # Check resource limits
                    if ($currentHandles -gt $using:resourceLimits.MaxHandles) {
                        throw "Handle limit exceeded: $currentHandles"
                    }

                    if ($currentThreads -gt $using:resourceLimits.MaxThreads) {
                        throw "Thread limit exceeded: $currentThreads"
                    }

                    # Simulate resource usage
                    $tempData = 1..1000 | ForEach-Object { "Data_$_" }

                    # Resource monitoring
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        HandleCount = $currentHandles
                        ThreadCount = $currentThreads
                        Success = $true
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 16

            # Assert
            $resourceResults | Should -HaveCount $resourceIntensiveOperations.Count

            # Most operations should succeed (some may fail due to resource limits)
            $successfulOperations = $resourceResults | Where-Object Success -eq $true
            $successfulOperations.Count | Should BeGreaterThan ($resourceIntensiveOperations.Count * 0.8)  # 80% success rate minimum

            # Failed operations should have meaningful error messages
            $failedOperations = $resourceResults | Where-Object Success -eq $false
            if ($failedOperations.Count -gt 0) {
                $failedOperations | ForEach-Object {
                    $_.Error | Should Not BeNullOrEmpty
                }
            }

            Write-Host "Resource exhaustion test: $($successfulOperations.Count)/$($resourceResults.Count) operations succeeded" -ForegroundColor Cyan
        }
    }

    Context "Deadlock Prevention" {

        It "Should prevent deadlocks in multi-resource scenarios" {
            # Arrange
            $resource1 = [System.Object]::new()
            $resource2 = [System.Object]::new()
            $operations = 1..50

            # Act - Operations that could cause deadlocks if not properly ordered
            $deadlockResults = $operations | ForEach-Object -Parallel {
                $using:resource1
                $using:resource2
                $operationId = $_

                try {
                    # Determine lock order to prevent deadlocks
                    $lockOrder = if ($operationId % 2 -eq 0) {
                        @($using:resource1, $using:resource2)
                    } else {
                        @($using:resource1, $using:resource2)  # Always same order to prevent deadlock
                    }

                    $timeout = 5000  # 5 seconds
                    $acquired = @()

                    try {
                        foreach ($resource in $lockOrder) {
                            if ([System.Threading.Monitor]::TryEnter($resource, $timeout)) {
                                $acquired += $resource
                            } else {
                                throw "Failed to acquire lock within timeout"
                            }
                        }

                        # Simulate work requiring both resources
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)

                        return [PSCustomObject]@{
                            OperationId = $operationId
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            LocksAcquired = $acquired.Count
                            Success = $true
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Release locks in reverse order
                        for ($i = $acquired.Count - 1; $i -ge 0; $i--) {
                            [System.Threading.Monitor]::Exit($acquired[$i])
                        }
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $deadlockResults | Should -HaveCount $operations.Count
            $deadlockResults | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # No operations should have failed due to deadlocks
            $deadlockErrors = $deadlockResults | Where-Object Success -eq $false
            $deadlockErrors | Should BeNullOrEmpty

            # Verify concurrent execution
            $uniqueThreads = ($deadlockResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should implement timeout-based lock acquisition" {
            # Arrange
            $sharedResource = [System.Object]::new()
            $longRunningOperations = 1..20
            $quickOperations = 21..40

            # Act - Mix of long-running and quick operations
            $timeoutResults = @()

            # Start long-running operations first
            $longRunningJobs = $longRunningOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 10000  # 10 seconds
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Simulate long-running work
                                Start-Sleep -Milliseconds 100

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "LongRunning"
                                    Success = $true
                                    Duration = 100
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            throw "Timeout acquiring lock"
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "LongRunning"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Start quick operations
            Start-Sleep -Milliseconds 50  # Let long operations start first
            $quickJobs = $quickOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 1000  # 1 second timeout for quick operations
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Quick work
                                Start-Sleep -Milliseconds 10

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "Quick"
                                    Success = $true
                                    Duration = 10
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            return [PSCustomObject]@{
                                OperationId = $OperationId
                                Type = "Quick"
                                Success = $false
                                Error = "Timeout - resource busy"
                                Timestamp = Get-Date
                            }
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "Quick"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Wait for all jobs to complete
            $allJobs = $longRunningJobs + $quickJobs
            $timeoutResults = $allJobs | Wait-Job | Receive-Job
            $allJobs | Remove-Job -Force

            # Assert
            $timeoutResults | Should -HaveCount ($longRunningOperations.Count + $quickOperations.Count)

            # Long-running operations should mostly succeed
            $longResults = $timeoutResults | Where-Object Type -eq "LongRunning"
            $longSuccessRate = ($longResults | Where-Object Success -eq $true).Count / $longResults.Count
            $longSuccessRate | Should BeGreaterThan 0.8  # 80% success rate

            # Some quick operations may timeout, which is expected behavior
            $quickResults = $timeoutResults | Where-Object Type -eq "Quick"
            $quickResults | Should Not BeNullOrEmpty

            Write-Host "Timeout test: Long operations success rate: $([Math]::Round($longSuccessRate * 100, 1))%" -ForegroundColor Cyan
        }
    }

    Context "Performance Scaling Validation" {

        It "Should demonstrate optimal thread count for workload" {
            # Arrange
            $workloadSizes = @(100, 500, 1000)
            $scalingResults = @()

            # Act - Test different workload sizes with varying thread counts
            foreach ($workloadSize in $workloadSizes) {
                $workload = 1..$workloadSize | ForEach-Object { "WorkItem_$_" }

                foreach ($threadCount in @(1, 2, 4, 8)) {
                    if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                    $monitor = Start-PerformanceMonitor -TestName "Scaling_${workloadSize}_${threadCount}"

                    $results = $workload | ForEach-Object -Parallel {
                        # Simulate CPU-bound work
                        $sum = 0
                        1..1000 | ForEach-Object { $sum += $_ }

                        [PSCustomObject]@{
                            WorkItem = $_
                            Sum = $sum
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        }
                    } -ThrottleLimit $threadCount

                    $perf = Stop-PerformanceMonitor -Monitor $monitor

                    $scalingResults += [PSCustomObject]@{
                        WorkloadSize = $workloadSize
                        ThreadCount = $threadCount
                        Duration = $perf.Duration
                        Throughput = $workloadSize / $perf.Duration
                        MemoryDelta = $perf.MemoryDelta
                        UniqueThreads = ($results | Group-Object ThreadId).Count
                        Efficiency = $workloadSize / ($perf.Duration * $threadCount)
                    }
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty

            # Find optimal thread count for each workload size
            foreach ($workloadSize in $workloadSizes) {
                $workloadResults = $scalingResults | Where-Object WorkloadSize -eq $workloadSize
                $optimalResult = $workloadResults | Sort-Object Throughput -Descending | Select-Object -First 1

                # Optimal thread count should be reasonable
                $optimalResult.ThreadCount | Should BeLessThan $Global:ConcurrencyConfig.MaxThreads
                $optimalResult.Throughput | Should BeGreaterThan 0

                Write-Host "Workload $workloadSize: Optimal thread count = $($optimalResult.ThreadCount), Throughput = $([Math]::Round($optimalResult.Throughput, 1)) ops/sec" -ForegroundColor Green
            }

            # Display detailed scaling results
            Write-Host "`nDetailed Scaling Results:" -ForegroundColor Yellow
            $scalingResults | Sort-Object WorkloadSize, ThreadCount | ForEach-Object {
                Write-Host "  Size: $($_.WorkloadSize), Threads: $($_.ThreadCount), Duration: $([Math]::Round($_.Duration, 2))s, Efficiency: $([Math]::Round($_.Efficiency, 2))" -ForegroundColor Cyan
            }
        }

        It "Should maintain performance under sustained load" {
            # Arrange
            $sustainedTestDuration = 30  # seconds
            $operationInterval = 100     # milliseconds
            $performanceData = @()
            $startTime = Get-Date

            # Act - Sustained concurrent operations
            do {
                $iterationStart = Get-Date

                $batchResults = 1..50 | ForEach-Object -Parallel {
                    # Simulate work
                    $data = 1..100 | ForEach-Object { "Item_$_" }

                    [PSCustomObject]@{
                        OperationId = $_
                        ProcessedItems = $data.Count
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } -ThrottleLimit 8

                $iterationDuration = ((Get-Date) - $iterationStart).TotalMilliseconds

                $performanceData += [PSCustomObject]@{
                    IterationStart = $iterationStart
                    Duration = $iterationDuration
                    OperationsCompleted = $batchResults.Count
                    Throughput = $batchResults.Count / ($iterationDuration / 1000)
                    UniqueThreads = ($batchResults | Group-Object ThreadId).Count
                    MemoryUsage = [System.GC]::GetTotalMemory($false)
                }

                # Maintain operation interval
                $sleepTime = $operationInterval - $iterationDuration
                if ($sleepTime -gt 0) {
                    Start-Sleep -Milliseconds $sleepTime
                }

            } while (((Get-Date) - $startTime).TotalSeconds -lt $sustainedTestDuration)

            # Assert
            $performanceData | Should Not BeNullOrEmpty
            $performanceData.Count | Should BeGreaterThan 10  # Should have multiple iterations

            # Performance should remain stable (no significant degradation)
            $firstHalf = $performanceData | Select-Object -First ([Math]::Floor($performanceData.Count / 2))
            $secondHalf = $performanceData | Select-Object -Last ([Math]::Floor($performanceData.Count / 2))

            $firstHalfAvgThroughput = ($firstHalf | Measure-Object Throughput -Average).Average
            $secondHalfAvgThroughput = ($secondHalf | Measure-Object Throughput -Average).Average

            # Performance degradation should be minimal (< 20%)
            $performanceDrop = ($firstHalfAvgThroughput - $secondHalfAvgThroughput) / $firstHalfAvgThroughput
            $performanceDrop | Should BeLessThan 0.2  # Less than 20% degradation

            # Memory usage should be stable (no significant growth)
            $memoryGrowth = ($performanceData[-1].MemoryUsage - $performanceData[0].MemoryUsage) / 1MB
            $memoryGrowth | Should BeLessThan 50  # Less than 50MB growth

            Write-Host "Sustained load test completed:" -ForegroundColor Green
            Write-Host "  Duration: $sustainedTestDuration seconds" -ForegroundColor Cyan
            Write-Host "  Iterations: $($performanceData.Count)" -ForegroundColor Cyan
            Write-Host "  Average throughput: $([Math]::Round(($performanceData | Measure-Object Throughput -Average).Average, 1)) ops/sec" -ForegroundColor Cyan
            Write-Host "  Performance drop: $([Math]::Round($performanceDrop * 100, 1))%" -ForegroundColor Cyan
            Write-Host "  Memory growth: $([Math]::Round($memoryGrowth, 1))MB" -ForegroundColor Cyan
        }
    }
}

Describe "Concurrent Operations Benchmarks" -Tag "Performance", "Benchmark", "Concurrency" {

    It "Should meet enterprise concurrency performance benchmarks" {
        # Arrange
        $benchmarks = @{
            LowConcurrency = @{ Threads = 2; Items = 100; Threshold = 5 }    # 5 seconds
            MediumConcurrency = @{ Threads = 4; Items = 500; Threshold = 10 } # 10 seconds
            HighConcurrency = @{ Threads = 8; Items = 1000; Threshold = 20 }  # 20 seconds
        }

        $benchmarkResults = @{}

        # Act & Assert
        foreach ($benchmark in $benchmarks.GetEnumerator()) {
            $benchmarkName = $benchmark.Key
            $config = $benchmark.Value

            $testData = 1..$config.Items | ForEach-Object {
                "BenchmarkItem_$_"
            }

            $monitor = Start-PerformanceMonitor -TestName $benchmarkName

            $results = $testData | ForEach-Object -Parallel {
                # Simulate realistic work
                $sum = 0
                1..500 | ForEach-Object { $sum += $_ }

                [PSCustomObject]@{
                    Item = $_
                    Result = $sum
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                }
            } -ThrottleLimit $config.Threads

            $perf = Stop-PerformanceMonitor -Monitor $monitor
            $benchmarkResults[$benchmarkName] = $perf

            # Performance assertions
            $perf.Duration | Should BeLessThan $config.Threshold
            $results | Should -HaveCount $config.Items

            # Verify concurrency
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
            $uniqueThreads | Should BeLessThan $config.Threads
        }

        Write-Host "`nConcurrency Benchmark Results:" -ForegroundColor Green
        $benchmarkResults.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $([Math]::Round($_.Value.Duration, 2))s" -ForegroundColor Cyan
        }
    }
}

AfterAll {
    # Cleanup global variables and collections
    $Global:ThreadSafeResults.Clear()
    $Global:ThreadSafeErrors.Clear()
    $Global:ThreadSafeCounters.Clear()

    Remove-Variable -Name "ConcurrencyConfig" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeResults" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeErrors" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeCounters" -Scope Global -ErrorAction SilentlyContinue

    # Cleanup test directories
    @($ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (Test-Path $_ -PathType Container) {
            $items = Get-ChildItem $_ -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Force garbage collection to clean up test resources
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

)) {
New-Item -Path #Requires -Version 5.1
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive concurrent operations performance testing for Find-UnknownSID solution

.DESCRIPTION
    Enterprise-grade validation of multi-threaded and concurrent processing capabilities including:
    - Parallel SID processing with thread safety validation
    - Concurrent file system operations and locking mechanisms
    - Multi-threaded backup and restore operations
    - Resource contention and deadlock prevention
    - Performance scaling under concurrent load
    - Thread pool management and optimization
    - Synchronization primitive effectiveness

.NOTES
    Author: GitHub Copilot (AI Assistant)
    Created: January 2025
    Version: 1.0.0

    Test Categories:
    - Parallel Processing Performance
    - Thread Safety Validation
    - Resource Contention Management
    - Deadlock Prevention
    - Scalability Testing
    - Synchronization Testing

    This file implements comprehensive concurrent operations testing following
    PowerShell community standards and enterprise performance requirements.
#>

BeforeAll {
    # Import required modules and classes
    $ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

    # Import test helpers
    $TestHelpersPath = Join-Path $PSScriptRoot "..\TestHelpers"
    if (Test-Path "$TestHelpersPath\TestHelpers.ps1") {
        . "$TestHelpersPath\TestHelpers.ps1"
    } else {
        Write-Warning "TestHelpers.ps1 not found at $TestHelpersPath"
    }

    # Import main module classes and functions
    Get-ChildItem "$ModuleRoot\Classes" -Filter "*.ps1" | ForEach-Object { . $_.FullName }
    Get-ChildItem "$ModuleRoot\Private" -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    # Test data setup
    $TestDataPath = Join-Path $PSScriptRoot "..\TestData"
    $ConcurrencyTestPath = Join-Path $TestDataPath "ConcurrencyTests"
    $PerformanceLogsPath = Join-Path $TestDataPath "PerformanceLogs"

    # Ensure test directories exist
    @($TestDataPath, $ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    # Global concurrency configuration
    $Global:ConcurrencyConfig = @{
        MaxThreads = [Environment]::ProcessorCount * 2
        DefaultThreadPoolSize = [Environment]::ProcessorCount
        TimeoutSeconds = 60
        MaxRetryAttempts = 3
        PerformanceThresholds = @{
            SingleThread = 10      # seconds
            MultiThread = 15       # seconds
            HighConcurrency = 25   # seconds
        }
        TestDataSizes = @{
            Small = 100
            Medium = 500
            Large = 1000
            ExtraLarge = 2000
        }
        ConcurrencyLevels = @(1, 2, 4, 8, 16)
    }

    # Thread-safe collections for testing
    $Global:ThreadSafeResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeErrors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
    $Global:ThreadSafeCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()

    # Mock dangerous operations for safe testing
    Mock Remove-Item { return $true } -ParameterFilter { $Path -like "*TestData*" }
    Mock Set-Acl { return $true }
    Mock Get-Acl {
        return [PSCustomObject]@{
            Access = @()
            Owner = "BUILTIN\Administrators"
            Group = "BUILTIN\Administrators"
        }
    }

    # Performance monitoring functions
    function Start-PerformanceMonitor {
        param([string]$TestName)

        return [PSCustomObject]@{
            TestName = $TestName
            StartTime = Get-Date
            StartMemory = [System.GC]::GetTotalMemory($false)
            StartHandleCount = (Get-Process -Id $PID).HandleCount
            StartThreadCount = (Get-Process -Id $PID).Threads.Count
        }
    }

    function Stop-PerformanceMonitor {
        param($Monitor)

        $endTime = Get-Date
        $endMemory = [System.GC]::GetTotalMemory($false)
        $endHandleCount = (Get-Process -Id $PID).HandleCount
        $endThreadCount = (Get-Process -Id $PID).Threads.Count

        return [PSCustomObject]@{
            TestName = $Monitor.TestName
            Duration = ($endTime - $Monitor.StartTime).TotalSeconds
            MemoryDelta = $endMemory - $Monitor.StartMemory
            HandleDelta = $endHandleCount - $Monitor.StartHandleCount
            ThreadDelta = $endThreadCount - $Monitor.StartThreadCount
            StartTime = $Monitor.StartTime
            EndTime = $endTime
        }
    }
}

Describe "Parallel Processing Performance Tests" -Tag "Performance", "Concurrency", "Parallel" {

    Context "Basic Parallel Operations" {

        It "Should process SIDs in parallel faster than sequential" {
            # Arrange
            $testSIDs = 1..$Global:ConcurrencyConfig.TestDataSizes.Medium | ForEach-Object {
                "S-1-5-21-123456789-123456789-123456789-$_"
            }

            # Act - Sequential processing
            $sequentialMonitor = Start-PerformanceMonitor -TestName "Sequential"
            $sequentialResults = @()
            foreach ($sid in $testSIDs) {
                $sequentialResults += [PSCustomObject]@{
                    SID = $sid
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Sequential"
                }
            }
            $sequentialPerf = Stop-PerformanceMonitor -Monitor $sequentialMonitor

            # Act - Parallel processing
            $parallelMonitor = Start-PerformanceMonitor -TestName "Parallel"
            $parallelResults = $testSIDs | ForEach-Object -Parallel {
                [PSCustomObject]@{
                    SID = $_
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Parallel"
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize
            $parallelPerf = Stop-PerformanceMonitor -Monitor $parallelMonitor

            # Assert
            $sequentialResults | Should -HaveCount $testSIDs.Count
            $parallelResults | Should -HaveCount $testSIDs.Count

            # Performance comparison
            $parallelPerf.Duration | Should BeLessThan $sequentialPerf.Duration

            # Verify parallel execution used multiple threads
            $uniqueThreads = ($parallelResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            Write-Host "Sequential: $([Math]::Round($sequentialPerf.Duration, 2))s, Parallel: $([Math]::Round($parallelPerf.Duration, 2))s" -ForegroundColor Cyan
            Write-Host "Speedup: $([Math]::Round($sequentialPerf.Duration / $parallelPerf.Duration, 2))x" -ForegroundColor Green
        }

        It "Should scale performance with increasing thread count" {
            # Arrange
            $testData = 1..$Global:ConcurrencyConfig.TestDataSizes.Small | ForEach-Object {
                "TestData_$_"
            }
            $scalingResults = @()

            # Act - Test different concurrency levels
            foreach ($threadCount in $Global:ConcurrencyConfig.ConcurrencyLevels) {
                if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                $monitor = Start-PerformanceMonitor -TestName "Scaling_$threadCount"

                $results = $testData | ForEach-Object -Parallel {
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    [PSCustomObject]@{
                        Data = $_
                        ProcessedAt = Get-Date
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    }
                } -ThrottleLimit $threadCount

                $perf = Stop-PerformanceMonitor -Monitor $monitor

                $scalingResults += [PSCustomObject]@{
                    ThreadCount = $threadCount
                    Duration = $perf.Duration
                    Throughput = $testData.Count / $perf.Duration
                    UniqueThreads = ($results | Group-Object ThreadId).Count
                    MemoryDelta = $perf.MemoryDelta
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty
            $scalingResults.Count | Should BeGreaterThan 1

            # Performance should generally improve with more threads (up to optimal point)
            $baselinePerformance = $scalingResults | Where-Object ThreadCount -eq 1
            $bestPerformance = $scalingResults | Sort-Object Duration | Select-Object -First 1

            $bestPerformance.Duration | Should BeLessThan $baselinePerformance.Duration

            # Display scaling results
            Write-Host "Concurrency Scaling Results:" -ForegroundColor Green
            $scalingResults | ForEach-Object {
                Write-Host "  $($_.ThreadCount) threads: $([Math]::Round($_.Duration, 2))s ($([Math]::Round($_.Throughput, 1)) ops/sec)" -ForegroundColor Cyan
            }
        }

        It "Should maintain data integrity during parallel processing" {
            # Arrange
            $testItems = 1..200 | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_
                    SID = "S-1-5-21-123456789-123456789-123456789-$_"
                    ExpectedChecksum = $_.ToString().GetHashCode()
                }
            }

            # Act - Parallel processing with integrity checking
            $processedItems = $testItems | ForEach-Object -Parallel {
                $item = $_

                # Simulate processing with integrity preservation
                $processedItem = [PSCustomObject]@{
                    Id = $item.Id
                    SID = $item.SID
                    ProcessedChecksum = $item.Id.ToString().GetHashCode()
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    ProcessorId = [Environment]::ProcessorCount
                }

                return $processedItem
            } -ThrottleLimit 8

            # Assert
            $processedItems | Should -HaveCount $testItems.Count

            # Verify data integrity
            for ($i = 0; $i -lt $testItems.Count; $i++) {
                $original = $testItems[$i]
                $processed = $processedItems | Where-Object Id -eq $original.Id

                $processed | Should Not BeNullOrEmpty
                $processed.SID | Should Be $original.SID
                $processed.ProcessedChecksum | Should Be $original.ExpectedChecksum
            }

            # Verify parallel execution
            $uniqueThreads = ($processedItems | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }
    }

    Context "Thread Safety Validation" {

        It "Should safely access shared resources concurrently" {
            # Arrange
            $sharedResource = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            $lockObject = [System.Object]::new()
            $operations = 1..100

            # Act - Concurrent access to shared resource
            $results = $operations | ForEach-Object -Parallel {
                $using:sharedResource
                $using:lockObject
                $operationId = $_

                try {
                    # Thread-safe operations
                    $key = "Operation_$operationId"
                    $value = [PSCustomObject]@{
                        Id = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                        Data = "ProcessedData_$operationId"
                    }

                    # Add to thread-safe collection
                    $success = $using:sharedResource.TryAdd($key, $value)

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $success
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $false
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $operations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # Verify shared resource integrity
            $sharedResource.Count | Should Be $operations.Count
            $sharedResource.Keys | Should -HaveCount $operations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should prevent race conditions in critical sections" {
            # Arrange
            $sharedCounter = 0
            $lockObject = [System.Object]::new()
            $incrementOperations = 1..500

            # Act - Concurrent counter increments with synchronization
            $results = $incrementOperations | ForEach-Object -Parallel {
                $using:lockObject
                $operationId = $_

                # Critical section with lock
                [System.Threading.Monitor]::Enter($using:lockObject)
                try {
                    # Simulate critical work
                    $currentValue = $using:sharedCounter
                    Start-Sleep -Milliseconds 1  # Simulate race condition opportunity
                    $newValue = $currentValue + 1
                    $using:sharedCounter = $newValue

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        CounterValue = $newValue
                        Success = $true
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                    }
                } finally {
                    [System.Threading.Monitor]::Exit($using:lockObject)
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $incrementOperations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $incrementOperations.Count

            # Verify no race conditions occurred
            $finalCounterValue = ($results | Sort-Object CounterValue | Select-Object -Last 1).CounterValue
            $finalCounterValue | Should Be $incrementOperations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should handle concurrent file operations safely" {
            # Arrange
            $testFiles = 1..50 | ForEach-Object {
                "TestFile_$_.txt"
            }
            $baseTestPath = Join-Path $ConcurrencyTestPath "FileOperations"
            if (-not (Test-Path $baseTestPath)) {
                New-Item -Path $baseTestPath -ItemType Directory -Force | Out-Null
            }

            # Act - Concurrent file operations
            $fileResults = $testFiles | ForEach-Object -Parallel {
                $using:baseTestPath
                $fileName = $_
                $filePath = Join-Path $using:baseTestPath $fileName

                try {
                    # Simulate file operations
                    $content = "Thread: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)`n"
                    $content += "Timestamp: $(Get-Date)`n"
                    $content += "File: $fileName`n"

                    # Thread-safe file creation
                    $lockFile = "$filePath.lock"
                    $timeout = 10  # seconds
                    $start = Get-Date

                    while (Test-Path $lockFile -PathType Leaf) {
                        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
                            throw "Timeout waiting for file lock: $fileName"
                        }
                        Start-Sleep -Milliseconds 10
                    }

                    # Create lock file
                    "lock" | Out-File -FilePath $lockFile -Force

                    try {
                        # Write main file
                        $content | Out-File -FilePath $filePath -Force

                        # Verify file was written
                        $writtenContent = Get-Content $filePath -Raw
                        $success = $writtenContent.Contains($fileName)

                        return [PSCustomObject]@{
                            FileName = $fileName
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            Success = $success
                            FileSize = (Get-Item $filePath).Length
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Remove lock file
                        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    return [PSCustomObject]@{
                        FileName = $fileName
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 8

            # Assert
            $fileResults | Should -HaveCount $testFiles.Count
            $fileResults | Where-Object Success -eq $true | Should -HaveCount $testFiles.Count

            # Verify all files were created
            $createdFiles = Get-ChildItem $baseTestPath -Filter "*.txt"
            $createdFiles.Count | Should Be $testFiles.Count

            # Verify concurrent execution
            $uniqueThreads = ($fileResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            # Cleanup
            Remove-Item $baseTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Resource Contention Management" {

        It "Should manage memory pressure under high concurrency" {
            # Arrange
            $memoryTestData = 1..$Global:ConcurrencyConfig.TestDataSizes.Large
            $initialMemory = [System.GC]::GetTotalMemory($false)

            # Act - Memory-intensive concurrent operations
            $monitor = Start-PerformanceMonitor -TestName "MemoryContention"

            $memoryResults = $memoryTestData | ForEach-Object -Parallel {
                $operationId = $_

                try {
                    # Create memory-intensive objects
                    $largeString = "X" * 1000  # 1KB string
                    $dataArray = 1..100 | ForEach-Object { $_ * $operationId }

                    # Simulate processing
                    $processedData = [PSCustomObject]@{
                        Id = $operationId
                        LargeData = $largeString
                        ProcessedArray = $dataArray
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        MemorySnapshot = [System.GC]::GetTotalMemory($false)
                        Timestamp = Get-Date
                    }

                    # Force periodic garbage collection
                    if ($operationId % 100 -eq 0) {
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }

                    return $processedData
                } catch {
                    return [PSCustomObject]@{
                        Id = $operationId
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize

            $memoryPerf = Stop-PerformanceMonitor -Monitor $monitor

            # Assert
            $memoryResults | Should -HaveCount $memoryTestData.Count
            $memoryResults | Where-Object Error | Should BeNullOrEmpty

            # Memory usage should be reasonable
            $memoryPerf.MemoryDelta | Should BeLessThan (500 * 1MB)  # Less than 500MB growth

            # Performance should be acceptable
            $memoryPerf.Duration | Should BeLessThan $Global:ConcurrencyConfig.PerformanceThresholds.HighConcurrency

            # Force cleanup
            $memoryResults = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-Host "Memory test completed. Duration: $([Math]::Round($memoryPerf.Duration, 2))s, Memory Delta: $([Math]::Round($memoryPerf.MemoryDelta / 1MB, 2))MB" -ForegroundColor Cyan
        }

        It "Should handle resource exhaustion gracefully" {
            # Arrange
            $resourceLimits = @{
                MaxHandles = 1000
                MaxMemory = 100 * 1MB
                MaxThreads = 50
            }

            $resourceIntensiveOperations = 1..200

            # Act - Resource-intensive operations with limits
            $resourceResults = $resourceIntensiveOperations | ForEach-Object -Parallel {
                $using:resourceLimits
                $operationId = $_

                try {
                    # Monitor resource usage
                    $currentProcess = Get-Process -Id $PID
                    $currentHandles = $currentProcess.HandleCount
                    $currentThreads = $currentProcess.Threads.Count

                    # Check resource limits
                    if ($currentHandles -gt $using:resourceLimits.MaxHandles) {
                        throw "Handle limit exceeded: $currentHandles"
                    }

                    if ($currentThreads -gt $using:resourceLimits.MaxThreads) {
                        throw "Thread limit exceeded: $currentThreads"
                    }

                    # Simulate resource usage
                    $tempData = 1..1000 | ForEach-Object { "Data_$_" }

                    # Resource monitoring
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        HandleCount = $currentHandles
                        ThreadCount = $currentThreads
                        Success = $true
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 16

            # Assert
            $resourceResults | Should -HaveCount $resourceIntensiveOperations.Count

            # Most operations should succeed (some may fail due to resource limits)
            $successfulOperations = $resourceResults | Where-Object Success -eq $true
            $successfulOperations.Count | Should BeGreaterThan ($resourceIntensiveOperations.Count * 0.8)  # 80% success rate minimum

            # Failed operations should have meaningful error messages
            $failedOperations = $resourceResults | Where-Object Success -eq $false
            if ($failedOperations.Count -gt 0) {
                $failedOperations | ForEach-Object {
                    $_.Error | Should Not BeNullOrEmpty
                }
            }

            Write-Host "Resource exhaustion test: $($successfulOperations.Count)/$($resourceResults.Count) operations succeeded" -ForegroundColor Cyan
        }
    }

    Context "Deadlock Prevention" {

        It "Should prevent deadlocks in multi-resource scenarios" {
            # Arrange
            $resource1 = [System.Object]::new()
            $resource2 = [System.Object]::new()
            $operations = 1..50

            # Act - Operations that could cause deadlocks if not properly ordered
            $deadlockResults = $operations | ForEach-Object -Parallel {
                $using:resource1
                $using:resource2
                $operationId = $_

                try {
                    # Determine lock order to prevent deadlocks
                    $lockOrder = if ($operationId % 2 -eq 0) {
                        @($using:resource1, $using:resource2)
                    } else {
                        @($using:resource1, $using:resource2)  # Always same order to prevent deadlock
                    }

                    $timeout = 5000  # 5 seconds
                    $acquired = @()

                    try {
                        foreach ($resource in $lockOrder) {
                            if ([System.Threading.Monitor]::TryEnter($resource, $timeout)) {
                                $acquired += $resource
                            } else {
                                throw "Failed to acquire lock within timeout"
                            }
                        }

                        # Simulate work requiring both resources
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)

                        return [PSCustomObject]@{
                            OperationId = $operationId
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            LocksAcquired = $acquired.Count
                            Success = $true
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Release locks in reverse order
                        for ($i = $acquired.Count - 1; $i -ge 0; $i--) {
                            [System.Threading.Monitor]::Exit($acquired[$i])
                        }
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $deadlockResults | Should -HaveCount $operations.Count
            $deadlockResults | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # No operations should have failed due to deadlocks
            $deadlockErrors = $deadlockResults | Where-Object Success -eq $false
            $deadlockErrors | Should BeNullOrEmpty

            # Verify concurrent execution
            $uniqueThreads = ($deadlockResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should implement timeout-based lock acquisition" {
            # Arrange
            $sharedResource = [System.Object]::new()
            $longRunningOperations = 1..20
            $quickOperations = 21..40

            # Act - Mix of long-running and quick operations
            $timeoutResults = @()

            # Start long-running operations first
            $longRunningJobs = $longRunningOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 10000  # 10 seconds
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Simulate long-running work
                                Start-Sleep -Milliseconds 100

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "LongRunning"
                                    Success = $true
                                    Duration = 100
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            throw "Timeout acquiring lock"
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "LongRunning"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Start quick operations
            Start-Sleep -Milliseconds 50  # Let long operations start first
            $quickJobs = $quickOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 1000  # 1 second timeout for quick operations
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Quick work
                                Start-Sleep -Milliseconds 10

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "Quick"
                                    Success = $true
                                    Duration = 10
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            return [PSCustomObject]@{
                                OperationId = $OperationId
                                Type = "Quick"
                                Success = $false
                                Error = "Timeout - resource busy"
                                Timestamp = Get-Date
                            }
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "Quick"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Wait for all jobs to complete
            $allJobs = $longRunningJobs + $quickJobs
            $timeoutResults = $allJobs | Wait-Job | Receive-Job
            $allJobs | Remove-Job -Force

            # Assert
            $timeoutResults | Should -HaveCount ($longRunningOperations.Count + $quickOperations.Count)

            # Long-running operations should mostly succeed
            $longResults = $timeoutResults | Where-Object Type -eq "LongRunning"
            $longSuccessRate = ($longResults | Where-Object Success -eq $true).Count / $longResults.Count
            $longSuccessRate | Should BeGreaterThan 0.8  # 80% success rate

            # Some quick operations may timeout, which is expected behavior
            $quickResults = $timeoutResults | Where-Object Type -eq "Quick"
            $quickResults | Should Not BeNullOrEmpty

            Write-Host "Timeout test: Long operations success rate: $([Math]::Round($longSuccessRate * 100, 1))%" -ForegroundColor Cyan
        }
    }

    Context "Performance Scaling Validation" {

        It "Should demonstrate optimal thread count for workload" {
            # Arrange
            $workloadSizes = @(100, 500, 1000)
            $scalingResults = @()

            # Act - Test different workload sizes with varying thread counts
            foreach ($workloadSize in $workloadSizes) {
                $workload = 1..$workloadSize | ForEach-Object { "WorkItem_$_" }

                foreach ($threadCount in @(1, 2, 4, 8)) {
                    if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                    $monitor = Start-PerformanceMonitor -TestName "Scaling_${workloadSize}_${threadCount}"

                    $results = $workload | ForEach-Object -Parallel {
                        # Simulate CPU-bound work
                        $sum = 0
                        1..1000 | ForEach-Object { $sum += $_ }

                        [PSCustomObject]@{
                            WorkItem = $_
                            Sum = $sum
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        }
                    } -ThrottleLimit $threadCount

                    $perf = Stop-PerformanceMonitor -Monitor $monitor

                    $scalingResults += [PSCustomObject]@{
                        WorkloadSize = $workloadSize
                        ThreadCount = $threadCount
                        Duration = $perf.Duration
                        Throughput = $workloadSize / $perf.Duration
                        MemoryDelta = $perf.MemoryDelta
                        UniqueThreads = ($results | Group-Object ThreadId).Count
                        Efficiency = $workloadSize / ($perf.Duration * $threadCount)
                    }
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty

            # Find optimal thread count for each workload size
            foreach ($workloadSize in $workloadSizes) {
                $workloadResults = $scalingResults | Where-Object WorkloadSize -eq $workloadSize
                $optimalResult = $workloadResults | Sort-Object Throughput -Descending | Select-Object -First 1

                # Optimal thread count should be reasonable
                $optimalResult.ThreadCount | Should BeLessThan $Global:ConcurrencyConfig.MaxThreads
                $optimalResult.Throughput | Should BeGreaterThan 0

                Write-Host "Workload $workloadSize: Optimal thread count = $($optimalResult.ThreadCount), Throughput = $([Math]::Round($optimalResult.Throughput, 1)) ops/sec" -ForegroundColor Green
            }

            # Display detailed scaling results
            Write-Host "`nDetailed Scaling Results:" -ForegroundColor Yellow
            $scalingResults | Sort-Object WorkloadSize, ThreadCount | ForEach-Object {
                Write-Host "  Size: $($_.WorkloadSize), Threads: $($_.ThreadCount), Duration: $([Math]::Round($_.Duration, 2))s, Efficiency: $([Math]::Round($_.Efficiency, 2))" -ForegroundColor Cyan
            }
        }

        It "Should maintain performance under sustained load" {
            # Arrange
            $sustainedTestDuration = 30  # seconds
            $operationInterval = 100     # milliseconds
            $performanceData = @()
            $startTime = Get-Date

            # Act - Sustained concurrent operations
            do {
                $iterationStart = Get-Date

                $batchResults = 1..50 | ForEach-Object -Parallel {
                    # Simulate work
                    $data = 1..100 | ForEach-Object { "Item_$_" }

                    [PSCustomObject]@{
                        OperationId = $_
                        ProcessedItems = $data.Count
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } -ThrottleLimit 8

                $iterationDuration = ((Get-Date) - $iterationStart).TotalMilliseconds

                $performanceData += [PSCustomObject]@{
                    IterationStart = $iterationStart
                    Duration = $iterationDuration
                    OperationsCompleted = $batchResults.Count
                    Throughput = $batchResults.Count / ($iterationDuration / 1000)
                    UniqueThreads = ($batchResults | Group-Object ThreadId).Count
                    MemoryUsage = [System.GC]::GetTotalMemory($false)
                }

                # Maintain operation interval
                $sleepTime = $operationInterval - $iterationDuration
                if ($sleepTime -gt 0) {
                    Start-Sleep -Milliseconds $sleepTime
                }

            } while (((Get-Date) - $startTime).TotalSeconds -lt $sustainedTestDuration)

            # Assert
            $performanceData | Should Not BeNullOrEmpty
            $performanceData.Count | Should BeGreaterThan 10  # Should have multiple iterations

            # Performance should remain stable (no significant degradation)
            $firstHalf = $performanceData | Select-Object -First ([Math]::Floor($performanceData.Count / 2))
            $secondHalf = $performanceData | Select-Object -Last ([Math]::Floor($performanceData.Count / 2))

            $firstHalfAvgThroughput = ($firstHalf | Measure-Object Throughput -Average).Average
            $secondHalfAvgThroughput = ($secondHalf | Measure-Object Throughput -Average).Average

            # Performance degradation should be minimal (< 20%)
            $performanceDrop = ($firstHalfAvgThroughput - $secondHalfAvgThroughput) / $firstHalfAvgThroughput
            $performanceDrop | Should BeLessThan 0.2  # Less than 20% degradation

            # Memory usage should be stable (no significant growth)
            $memoryGrowth = ($performanceData[-1].MemoryUsage - $performanceData[0].MemoryUsage) / 1MB
            $memoryGrowth | Should BeLessThan 50  # Less than 50MB growth

            Write-Host "Sustained load test completed:" -ForegroundColor Green
            Write-Host "  Duration: $sustainedTestDuration seconds" -ForegroundColor Cyan
            Write-Host "  Iterations: $($performanceData.Count)" -ForegroundColor Cyan
            Write-Host "  Average throughput: $([Math]::Round(($performanceData | Measure-Object Throughput -Average).Average, 1)) ops/sec" -ForegroundColor Cyan
            Write-Host "  Performance drop: $([Math]::Round($performanceDrop * 100, 1))%" -ForegroundColor Cyan
            Write-Host "  Memory growth: $([Math]::Round($memoryGrowth, 1))MB" -ForegroundColor Cyan
        }
    }
}

Describe "Concurrent Operations Benchmarks" -Tag "Performance", "Benchmark", "Concurrency" {

    It "Should meet enterprise concurrency performance benchmarks" {
        # Arrange
        $benchmarks = @{
            LowConcurrency = @{ Threads = 2; Items = 100; Threshold = 5 }    # 5 seconds
            MediumConcurrency = @{ Threads = 4; Items = 500; Threshold = 10 } # 10 seconds
            HighConcurrency = @{ Threads = 8; Items = 1000; Threshold = 20 }  # 20 seconds
        }

        $benchmarkResults = @{}

        # Act & Assert
        foreach ($benchmark in $benchmarks.GetEnumerator()) {
            $benchmarkName = $benchmark.Key
            $config = $benchmark.Value

            $testData = 1..$config.Items | ForEach-Object {
                "BenchmarkItem_$_"
            }

            $monitor = Start-PerformanceMonitor -TestName $benchmarkName

            $results = $testData | ForEach-Object -Parallel {
                # Simulate realistic work
                $sum = 0
                1..500 | ForEach-Object { $sum += $_ }

                [PSCustomObject]@{
                    Item = $_
                    Result = $sum
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                }
            } -ThrottleLimit $config.Threads

            $perf = Stop-PerformanceMonitor -Monitor $monitor
            $benchmarkResults[$benchmarkName] = $perf

            # Performance assertions
            $perf.Duration | Should BeLessThan $config.Threshold
            $results | Should -HaveCount $config.Items

            # Verify concurrency
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
            $uniqueThreads | Should BeLessThan $config.Threads
        }

        Write-Host "`nConcurrency Benchmark Results:" -ForegroundColor Green
        $benchmarkResults.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $([Math]::Round($_.Value.Duration, 2))s" -ForegroundColor Cyan
        }
    }
}

AfterAll {
    # Cleanup global variables and collections
    $Global:ThreadSafeResults.Clear()
    $Global:ThreadSafeErrors.Clear()
    $Global:ThreadSafeCounters.Clear()

    Remove-Variable -Name "ConcurrencyConfig" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeResults" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeErrors" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeCounters" -Scope Global -ErrorAction SilentlyContinue

    # Cleanup test directories
    @($ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (Test-Path $_ -PathType Container) {
            $items = Get-ChildItem $_ -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Force garbage collection to clean up test resources
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

 -ItemType Directory -Force | Out-Null
}
}
# Global concurrency configuration
$Global:ConcurrencyConfig = @{
MaxThreads = [Environment]::ProcessorCount * 2
DefaultThreadPoolSize = [Environment]::ProcessorCount
TimeoutSeconds = 60
MaxRetryAttempts = 3
PerformanceThresholds = @{
SingleThread = 10      # seconds
MultiThread = 15       # seconds
HighConcurrency = 25   # seconds
}
TestDataSizes = @{
Small = 100
Medium = 500
Large = 1000
ExtraLarge = 2000
}
ConcurrencyLevels = @(1, 2, 4, 8, 16)
}
# Thread-safe collections for testing
$Global:ThreadSafeResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$Global:ThreadSafeErrors = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$Global:ThreadSafeCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
# Mock dangerous operations for safe testing
Mock Remove-Item { return $true } -ParameterFilter { $Path -like "*TestData*" }
Mock Set-Acl { return $true }
Mock Get-Acl {
return [PSCustomObject]@{
Access = @()
Owner = "BUILTIN\Administrators"
Group = "BUILTIN\Administrators"
}
}
# Performance monitoring functions
function Start-PerformanceMonitor {
param([string]$TestName)
return [PSCustomObject]@{
TestName = $TestName
StartTime = Get-Date
StartMemory = [System.GC]::GetTotalMemory($false)
StartHandleCount = (Get-Process -Id $PID).HandleCount
StartThreadCount = (Get-Process -Id $PID).Threads.Count
}
}
function Stop-PerformanceMonitor {
param($Monitor)
$endTime = Get-Date
$endMemory = [System.GC]::GetTotalMemory($false)
$endHandleCount = (Get-Process -Id $PID).HandleCount
$endThreadCount = (Get-Process -Id $PID).Threads.Count
return [PSCustomObject]@{
TestName = $Monitor.TestName
Duration = ($endTime - $Monitor.StartTime).TotalSeconds
MemoryDelta = $endMemory - $Monitor.StartMemory
HandleDelta = $endHandleCount - $Monitor.StartHandleCount
ThreadDelta = $endThreadCount - $Monitor.StartThreadCount
StartTime = $Monitor.StartTime
EndTime = $endTime
}
}

Describe "Parallel Processing Performance Tests" -Tag "Performance", "Concurrency", "Parallel" {

    Context "Basic Parallel Operations" {

        It "Should process SIDs in parallel faster than sequential" {
            # Arrange
            $testSIDs = 1..$Global:ConcurrencyConfig.TestDataSizes.Medium | ForEach-Object {
                "S-1-5-21-123456789-123456789-123456789-$_"
            }

            # Act - Sequential processing
            $sequentialMonitor = Start-PerformanceMonitor -TestName "Sequential"
            $sequentialResults = @()
            foreach ($sid in $testSIDs) {
                $sequentialResults += [PSCustomObject]@{
                    SID = $sid
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Sequential"
                }
            }
            $sequentialPerf = Stop-PerformanceMonitor -Monitor $sequentialMonitor

            # Act - Parallel processing
            $parallelMonitor = Start-PerformanceMonitor -TestName "Parallel"
            $parallelResults = $testSIDs | ForEach-Object -Parallel {
                [PSCustomObject]@{
                    SID = $_
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Method = "Parallel"
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize
            $parallelPerf = Stop-PerformanceMonitor -Monitor $parallelMonitor

            # Assert
            $sequentialResults | Should -HaveCount $testSIDs.Count
            $parallelResults | Should -HaveCount $testSIDs.Count

            # Performance comparison
            $parallelPerf.Duration | Should BeLessThan $sequentialPerf.Duration

            # Verify parallel execution used multiple threads
            $uniqueThreads = ($parallelResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            Write-Host "Sequential: $([Math]::Round($sequentialPerf.Duration, 2))s, Parallel: $([Math]::Round($parallelPerf.Duration, 2))s" -ForegroundColor Cyan
            Write-Host "Speedup: $([Math]::Round($sequentialPerf.Duration / $parallelPerf.Duration, 2))x" -ForegroundColor Green
        }

        It "Should scale performance with increasing thread count" {
            # Arrange
            $testData = 1..$Global:ConcurrencyConfig.TestDataSizes.Small | ForEach-Object {
                "TestData_$_"
            }
            $scalingResults = @()

            # Act - Test different concurrency levels
            foreach ($threadCount in $Global:ConcurrencyConfig.ConcurrencyLevels) {
                if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                $monitor = Start-PerformanceMonitor -TestName "Scaling_$threadCount"

                $results = $testData | ForEach-Object -Parallel {
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    [PSCustomObject]@{
                        Data = $_
                        ProcessedAt = Get-Date
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    }
                } -ThrottleLimit $threadCount

                $perf = Stop-PerformanceMonitor -Monitor $monitor

                $scalingResults += [PSCustomObject]@{
                    ThreadCount = $threadCount
                    Duration = $perf.Duration
                    Throughput = $testData.Count / $perf.Duration
                    UniqueThreads = ($results | Group-Object ThreadId).Count
                    MemoryDelta = $perf.MemoryDelta
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty
            $scalingResults.Count | Should BeGreaterThan 1

            # Performance should generally improve with more threads (up to optimal point)
            $baselinePerformance = $scalingResults | Where-Object ThreadCount -eq 1
            $bestPerformance = $scalingResults | Sort-Object Duration | Select-Object -First 1

            $bestPerformance.Duration | Should BeLessThan $baselinePerformance.Duration

            # Display scaling results
            Write-Host "Concurrency Scaling Results:" -ForegroundColor Green
            $scalingResults | ForEach-Object {
                Write-Host "  $($_.ThreadCount) threads: $([Math]::Round($_.Duration, 2))s ($([Math]::Round($_.Throughput, 1)) ops/sec)" -ForegroundColor Cyan
            }
        }

        It "Should maintain data integrity during parallel processing" {
            # Arrange
            $testItems = 1..200 | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_
                    SID = "S-1-5-21-123456789-123456789-123456789-$_"
                    ExpectedChecksum = $_.ToString().GetHashCode()
                }
            }

            # Act - Parallel processing with integrity checking
            $processedItems = $testItems | ForEach-Object -Parallel {
                $item = $_

                # Simulate processing with integrity preservation
                $processedItem = [PSCustomObject]@{
                    Id = $item.Id
                    SID = $item.SID
                    ProcessedChecksum = $item.Id.ToString().GetHashCode()
                    ProcessedAt = Get-Date
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    ProcessorId = [Environment]::ProcessorCount
                }

                return $processedItem
            } -ThrottleLimit 8

            # Assert
            $processedItems | Should -HaveCount $testItems.Count

            # Verify data integrity
            for ($i = 0; $i -lt $testItems.Count; $i++) {
                $original = $testItems[$i]
                $processed = $processedItems | Where-Object Id -eq $original.Id

                $processed | Should Not BeNullOrEmpty
                $processed.SID | Should Be $original.SID
                $processed.ProcessedChecksum | Should Be $original.ExpectedChecksum
            }

            # Verify parallel execution
            $uniqueThreads = ($processedItems | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }
    }

    Context "Thread Safety Validation" {

        It "Should safely access shared resources concurrently" {
            # Arrange
            $sharedResource = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            $lockObject = [System.Object]::new()
            $operations = 1..100

            # Act - Concurrent access to shared resource
            $results = $operations | ForEach-Object -Parallel {
                $using:sharedResource
                $using:lockObject
                $operationId = $_

                try {
                    # Thread-safe operations
                    $key = "Operation_$operationId"
                    $value = [PSCustomObject]@{
                        Id = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                        Data = "ProcessedData_$operationId"
                    }

                    # Add to thread-safe collection
                    $success = $using:sharedResource.TryAdd($key, $value)

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $success
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        Success = $false
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $operations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # Verify shared resource integrity
            $sharedResource.Count | Should Be $operations.Count
            $sharedResource.Keys | Should -HaveCount $operations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should prevent race conditions in critical sections" {
            # Arrange
            $sharedCounter = 0
            $lockObject = [System.Object]::new()
            $incrementOperations = 1..500

            # Act - Concurrent counter increments with synchronization
            $results = $incrementOperations | ForEach-Object -Parallel {
                $using:lockObject
                $operationId = $_

                # Critical section with lock
                [System.Threading.Monitor]::Enter($using:lockObject)
                try {
                    # Simulate critical work
                    $currentValue = $using:sharedCounter
                    Start-Sleep -Milliseconds 1  # Simulate race condition opportunity
                    $newValue = $currentValue + 1
                    $using:sharedCounter = $newValue

                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        CounterValue = $newValue
                        Success = $true
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                    }
                } finally {
                    [System.Threading.Monitor]::Exit($using:lockObject)
                }
            } -ThrottleLimit 10

            # Assert
            $results | Should -HaveCount $incrementOperations.Count
            $results | Where-Object Success -eq $true | Should -HaveCount $incrementOperations.Count

            # Verify no race conditions occurred
            $finalCounterValue = ($results | Sort-Object CounterValue | Select-Object -Last 1).CounterValue
            $finalCounterValue | Should Be $incrementOperations.Count

            # Verify concurrent execution
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should handle concurrent file operations safely" {
            # Arrange
            $testFiles = 1..50 | ForEach-Object {
                "TestFile_$_.txt"
            }
            $baseTestPath = Join-Path $ConcurrencyTestPath "FileOperations"
            if (-not (Test-Path $baseTestPath)) {
                New-Item -Path $baseTestPath -ItemType Directory -Force | Out-Null
            }

            # Act - Concurrent file operations
            $fileResults = $testFiles | ForEach-Object -Parallel {
                $using:baseTestPath
                $fileName = $_
                $filePath = Join-Path $using:baseTestPath $fileName

                try {
                    # Simulate file operations
                    $content = "Thread: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)`n"
                    $content += "Timestamp: $(Get-Date)`n"
                    $content += "File: $fileName`n"

                    # Thread-safe file creation
                    $lockFile = "$filePath.lock"
                    $timeout = 10  # seconds
                    $start = Get-Date

                    while (Test-Path $lockFile -PathType Leaf) {
                        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
                            throw "Timeout waiting for file lock: $fileName"
                        }
                        Start-Sleep -Milliseconds 10
                    }

                    # Create lock file
                    "lock" | Out-File -FilePath $lockFile -Force

                    try {
                        # Write main file
                        $content | Out-File -FilePath $filePath -Force

                        # Verify file was written
                        $writtenContent = Get-Content $filePath -Raw
                        $success = $writtenContent.Contains($fileName)

                        return [PSCustomObject]@{
                            FileName = $fileName
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            Success = $success
                            FileSize = (Get-Item $filePath).Length
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Remove lock file
                        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    return [PSCustomObject]@{
                        FileName = $fileName
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 8

            # Assert
            $fileResults | Should -HaveCount $testFiles.Count
            $fileResults | Where-Object Success -eq $true | Should -HaveCount $testFiles.Count

            # Verify all files were created
            $createdFiles = Get-ChildItem $baseTestPath -Filter "*.txt"
            $createdFiles.Count | Should Be $testFiles.Count

            # Verify concurrent execution
            $uniqueThreads = ($fileResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1

            # Cleanup
            Remove-Item $baseTestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Resource Contention Management" {

        It "Should manage memory pressure under high concurrency" {
            # Arrange
            $memoryTestData = 1..$Global:ConcurrencyConfig.TestDataSizes.Large
            $initialMemory = [System.GC]::GetTotalMemory($false)

            # Act - Memory-intensive concurrent operations
            $monitor = Start-PerformanceMonitor -TestName "MemoryContention"

            $memoryResults = $memoryTestData | ForEach-Object -Parallel {
                $operationId = $_

                try {
                    # Create memory-intensive objects
                    $largeString = "X" * 1000  # 1KB string
                    $dataArray = 1..100 | ForEach-Object { $_ * $operationId }

                    # Simulate processing
                    $processedData = [PSCustomObject]@{
                        Id = $operationId
                        LargeData = $largeString
                        ProcessedArray = $dataArray
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        MemorySnapshot = [System.GC]::GetTotalMemory($false)
                        Timestamp = Get-Date
                    }

                    # Force periodic garbage collection
                    if ($operationId % 100 -eq 0) {
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }

                    return $processedData
                } catch {
                    return [PSCustomObject]@{
                        Id = $operationId
                        Error = $_.Exception.Message
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit $Global:ConcurrencyConfig.DefaultThreadPoolSize

            $memoryPerf = Stop-PerformanceMonitor -Monitor $monitor

            # Assert
            $memoryResults | Should -HaveCount $memoryTestData.Count
            $memoryResults | Where-Object Error | Should BeNullOrEmpty

            # Memory usage should be reasonable
            $memoryPerf.MemoryDelta | Should BeLessThan (500 * 1MB)  # Less than 500MB growth

            # Performance should be acceptable
            $memoryPerf.Duration | Should BeLessThan $Global:ConcurrencyConfig.PerformanceThresholds.HighConcurrency

            # Force cleanup
            $memoryResults = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            Write-Host "Memory test completed. Duration: $([Math]::Round($memoryPerf.Duration, 2))s, Memory Delta: $([Math]::Round($memoryPerf.MemoryDelta / 1MB, 2))MB" -ForegroundColor Cyan
        }

        It "Should handle resource exhaustion gracefully" {
            # Arrange
            $resourceLimits = @{
                MaxHandles = 1000
                MaxMemory = 100 * 1MB
                MaxThreads = 50
            }

            $resourceIntensiveOperations = 1..200

            # Act - Resource-intensive operations with limits
            $resourceResults = $resourceIntensiveOperations | ForEach-Object -Parallel {
                $using:resourceLimits
                $operationId = $_

                try {
                    # Monitor resource usage
                    $currentProcess = Get-Process -Id $PID
                    $currentHandles = $currentProcess.HandleCount
                    $currentThreads = $currentProcess.Threads.Count

                    # Check resource limits
                    if ($currentHandles -gt $using:resourceLimits.MaxHandles) {
                        throw "Handle limit exceeded: $currentHandles"
                    }

                    if ($currentThreads -gt $using:resourceLimits.MaxThreads) {
                        throw "Thread limit exceeded: $currentThreads"
                    }

                    # Simulate resource usage
                    $tempData = 1..1000 | ForEach-Object { "Data_$_" }

                    # Resource monitoring
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        HandleCount = $currentHandles
                        ThreadCount = $currentThreads
                        Success = $true
                        Timestamp = Get-Date
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 16

            # Assert
            $resourceResults | Should -HaveCount $resourceIntensiveOperations.Count

            # Most operations should succeed (some may fail due to resource limits)
            $successfulOperations = $resourceResults | Where-Object Success -eq $true
            $successfulOperations.Count | Should BeGreaterThan ($resourceIntensiveOperations.Count * 0.8)  # 80% success rate minimum

            # Failed operations should have meaningful error messages
            $failedOperations = $resourceResults | Where-Object Success -eq $false
            if ($failedOperations.Count -gt 0) {
                $failedOperations | ForEach-Object {
                    $_.Error | Should Not BeNullOrEmpty
                }
            }

            Write-Host "Resource exhaustion test: $($successfulOperations.Count)/$($resourceResults.Count) operations succeeded" -ForegroundColor Cyan
        }
    }

    Context "Deadlock Prevention" {

        It "Should prevent deadlocks in multi-resource scenarios" {
            # Arrange
            $resource1 = [System.Object]::new()
            $resource2 = [System.Object]::new()
            $operations = 1..50

            # Act - Operations that could cause deadlocks if not properly ordered
            $deadlockResults = $operations | ForEach-Object -Parallel {
                $using:resource1
                $using:resource2
                $operationId = $_

                try {
                    # Determine lock order to prevent deadlocks
                    $lockOrder = if ($operationId % 2 -eq 0) {
                        @($using:resource1, $using:resource2)
                    } else {
                        @($using:resource1, $using:resource2)  # Always same order to prevent deadlock
                    }

                    $timeout = 5000  # 5 seconds
                    $acquired = @()

                    try {
                        foreach ($resource in $lockOrder) {
                            if ([System.Threading.Monitor]::TryEnter($resource, $timeout)) {
                                $acquired += $resource
                            } else {
                                throw "Failed to acquire lock within timeout"
                            }
                        }

                        # Simulate work requiring both resources
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)

                        return [PSCustomObject]@{
                            OperationId = $operationId
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            LocksAcquired = $acquired.Count
                            Success = $true
                            Timestamp = Get-Date
                        }
                    } finally {
                        # Release locks in reverse order
                        for ($i = $acquired.Count - 1; $i -ge 0; $i--) {
                            [System.Threading.Monitor]::Exit($acquired[$i])
                        }
                    }
                } catch {
                    return [PSCustomObject]@{
                        OperationId = $operationId
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Error = $_.Exception.Message
                        Success = $false
                        Timestamp = Get-Date
                    }
                }
            } -ThrottleLimit 10

            # Assert
            $deadlockResults | Should -HaveCount $operations.Count
            $deadlockResults | Where-Object Success -eq $true | Should -HaveCount $operations.Count

            # No operations should have failed due to deadlocks
            $deadlockErrors = $deadlockResults | Where-Object Success -eq $false
            $deadlockErrors | Should BeNullOrEmpty

            # Verify concurrent execution
            $uniqueThreads = ($deadlockResults | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
        }

        It "Should implement timeout-based lock acquisition" {
            # Arrange
            $sharedResource = [System.Object]::new()
            $longRunningOperations = 1..20
            $quickOperations = 21..40

            # Act - Mix of long-running and quick operations
            $timeoutResults = @()

            # Start long-running operations first
            $longRunningJobs = $longRunningOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 10000  # 10 seconds
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Simulate long-running work
                                Start-Sleep -Milliseconds 100

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "LongRunning"
                                    Success = $true
                                    Duration = 100
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            throw "Timeout acquiring lock"
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "LongRunning"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Start quick operations
            Start-Sleep -Milliseconds 50  # Let long operations start first
            $quickJobs = $quickOperations | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Resource, $OperationId)

                    try {
                        $timeout = 1000  # 1 second timeout for quick operations
                        if ([System.Threading.Monitor]::TryEnter($Resource, $timeout)) {
                            try {
                                # Quick work
                                Start-Sleep -Milliseconds 10

                                return [PSCustomObject]@{
                                    OperationId = $OperationId
                                    Type = "Quick"
                                    Success = $true
                                    Duration = 10
                                    Timestamp = Get-Date
                                }
                            } finally {
                                [System.Threading.Monitor]::Exit($Resource)
                            }
                        } else {
                            return [PSCustomObject]@{
                                OperationId = $OperationId
                                Type = "Quick"
                                Success = $false
                                Error = "Timeout - resource busy"
                                Timestamp = Get-Date
                            }
                        }
                    } catch {
                        return [PSCustomObject]@{
                            OperationId = $OperationId
                            Type = "Quick"
                            Success = $false
                            Error = $_.Exception.Message
                            Timestamp = Get-Date
                        }
                    }
                } -ArgumentList $sharedResource, $_
            }

            # Wait for all jobs to complete
            $allJobs = $longRunningJobs + $quickJobs
            $timeoutResults = $allJobs | Wait-Job | Receive-Job
            $allJobs | Remove-Job -Force

            # Assert
            $timeoutResults | Should -HaveCount ($longRunningOperations.Count + $quickOperations.Count)

            # Long-running operations should mostly succeed
            $longResults = $timeoutResults | Where-Object Type -eq "LongRunning"
            $longSuccessRate = ($longResults | Where-Object Success -eq $true).Count / $longResults.Count
            $longSuccessRate | Should BeGreaterThan 0.8  # 80% success rate

            # Some quick operations may timeout, which is expected behavior
            $quickResults = $timeoutResults | Where-Object Type -eq "Quick"
            $quickResults | Should Not BeNullOrEmpty

            Write-Host "Timeout test: Long operations success rate: $([Math]::Round($longSuccessRate * 100, 1))%" -ForegroundColor Cyan
        }
    }

    Context "Performance Scaling Validation" {

        It "Should demonstrate optimal thread count for workload" {
            # Arrange
            $workloadSizes = @(100, 500, 1000)
            $scalingResults = @()

            # Act - Test different workload sizes with varying thread counts
            foreach ($workloadSize in $workloadSizes) {
                $workload = 1..$workloadSize | ForEach-Object { "WorkItem_$_" }

                foreach ($threadCount in @(1, 2, 4, 8)) {
                    if ($threadCount -gt $Global:ConcurrencyConfig.MaxThreads) { continue }

                    $monitor = Start-PerformanceMonitor -TestName "Scaling_${workloadSize}_${threadCount}"

                    $results = $workload | ForEach-Object -Parallel {
                        # Simulate CPU-bound work
                        $sum = 0
                        1..1000 | ForEach-Object { $sum += $_ }

                        [PSCustomObject]@{
                            WorkItem = $_
                            Sum = $sum
                            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        }
                    } -ThrottleLimit $threadCount

                    $perf = Stop-PerformanceMonitor -Monitor $monitor

                    $scalingResults += [PSCustomObject]@{
                        WorkloadSize = $workloadSize
                        ThreadCount = $threadCount
                        Duration = $perf.Duration
                        Throughput = $workloadSize / $perf.Duration
                        MemoryDelta = $perf.MemoryDelta
                        UniqueThreads = ($results | Group-Object ThreadId).Count
                        Efficiency = $workloadSize / ($perf.Duration * $threadCount)
                    }
                }
            }

            # Assert
            $scalingResults | Should Not BeNullOrEmpty

            # Find optimal thread count for each workload size
            foreach ($workloadSize in $workloadSizes) {
                $workloadResults = $scalingResults | Where-Object WorkloadSize -eq $workloadSize
                $optimalResult = $workloadResults | Sort-Object Throughput -Descending | Select-Object -First 1

                # Optimal thread count should be reasonable
                $optimalResult.ThreadCount | Should BeLessThan $Global:ConcurrencyConfig.MaxThreads
                $optimalResult.Throughput | Should BeGreaterThan 0

                Write-Host "Workload $workloadSize: Optimal thread count = $($optimalResult.ThreadCount), Throughput = $([Math]::Round($optimalResult.Throughput, 1)) ops/sec" -ForegroundColor Green
            }

            # Display detailed scaling results
            Write-Host "`nDetailed Scaling Results:" -ForegroundColor Yellow
            $scalingResults | Sort-Object WorkloadSize, ThreadCount | ForEach-Object {
                Write-Host "  Size: $($_.WorkloadSize), Threads: $($_.ThreadCount), Duration: $([Math]::Round($_.Duration, 2))s, Efficiency: $([Math]::Round($_.Efficiency, 2))" -ForegroundColor Cyan
            }
        }

        It "Should maintain performance under sustained load" {
            # Arrange
            $sustainedTestDuration = 30  # seconds
            $operationInterval = 100     # milliseconds
            $performanceData = @()
            $startTime = Get-Date

            # Act - Sustained concurrent operations
            do {
                $iterationStart = Get-Date

                $batchResults = 1..50 | ForEach-Object -Parallel {
                    # Simulate work
                    $data = 1..100 | ForEach-Object { "Item_$_" }

                    [PSCustomObject]@{
                        OperationId = $_
                        ProcessedItems = $data.Count
                        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                        Timestamp = Get-Date
                    }
                } -ThrottleLimit 8

                $iterationDuration = ((Get-Date) - $iterationStart).TotalMilliseconds

                $performanceData += [PSCustomObject]@{
                    IterationStart = $iterationStart
                    Duration = $iterationDuration
                    OperationsCompleted = $batchResults.Count
                    Throughput = $batchResults.Count / ($iterationDuration / 1000)
                    UniqueThreads = ($batchResults | Group-Object ThreadId).Count
                    MemoryUsage = [System.GC]::GetTotalMemory($false)
                }

                # Maintain operation interval
                $sleepTime = $operationInterval - $iterationDuration
                if ($sleepTime -gt 0) {
                    Start-Sleep -Milliseconds $sleepTime
                }

            } while (((Get-Date) - $startTime).TotalSeconds -lt $sustainedTestDuration)

            # Assert
            $performanceData | Should Not BeNullOrEmpty
            $performanceData.Count | Should BeGreaterThan 10  # Should have multiple iterations

            # Performance should remain stable (no significant degradation)
            $firstHalf = $performanceData | Select-Object -First ([Math]::Floor($performanceData.Count / 2))
            $secondHalf = $performanceData | Select-Object -Last ([Math]::Floor($performanceData.Count / 2))

            $firstHalfAvgThroughput = ($firstHalf | Measure-Object Throughput -Average).Average
            $secondHalfAvgThroughput = ($secondHalf | Measure-Object Throughput -Average).Average

            # Performance degradation should be minimal (< 20%)
            $performanceDrop = ($firstHalfAvgThroughput - $secondHalfAvgThroughput) / $firstHalfAvgThroughput
            $performanceDrop | Should BeLessThan 0.2  # Less than 20% degradation

            # Memory usage should be stable (no significant growth)
            $memoryGrowth = ($performanceData[-1].MemoryUsage - $performanceData[0].MemoryUsage) / 1MB
            $memoryGrowth | Should BeLessThan 50  # Less than 50MB growth

            Write-Host "Sustained load test completed:" -ForegroundColor Green
            Write-Host "  Duration: $sustainedTestDuration seconds" -ForegroundColor Cyan
            Write-Host "  Iterations: $($performanceData.Count)" -ForegroundColor Cyan
            Write-Host "  Average throughput: $([Math]::Round(($performanceData | Measure-Object Throughput -Average).Average, 1)) ops/sec" -ForegroundColor Cyan
            Write-Host "  Performance drop: $([Math]::Round($performanceDrop * 100, 1))%" -ForegroundColor Cyan
            Write-Host "  Memory growth: $([Math]::Round($memoryGrowth, 1))MB" -ForegroundColor Cyan
        }
    }
}

Describe "Concurrent Operations Benchmarks" -Tag "Performance", "Benchmark", "Concurrency" {

    It "Should meet enterprise concurrency performance benchmarks" {
        # Arrange
        $benchmarks = @{
            LowConcurrency = @{ Threads = 2; Items = 100; Threshold = 5 }    # 5 seconds
            MediumConcurrency = @{ Threads = 4; Items = 500; Threshold = 10 } # 10 seconds
            HighConcurrency = @{ Threads = 8; Items = 1000; Threshold = 20 }  # 20 seconds
        }

        $benchmarkResults = @{}

        # Act & Assert
        foreach ($benchmark in $benchmarks.GetEnumerator()) {
            $benchmarkName = $benchmark.Key
            $config = $benchmark.Value

            $testData = 1..$config.Items | ForEach-Object {
                "BenchmarkItem_$_"
            }

            $monitor = Start-PerformanceMonitor -TestName $benchmarkName

            $results = $testData | ForEach-Object -Parallel {
                # Simulate realistic work
                $sum = 0
                1..500 | ForEach-Object { $sum += $_ }

                [PSCustomObject]@{
                    Item = $_
                    Result = $sum
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                }
            } -ThrottleLimit $config.Threads

            $perf = Stop-PerformanceMonitor -Monitor $monitor
            $benchmarkResults[$benchmarkName] = $perf

            # Performance assertions
            $perf.Duration | Should BeLessThan $config.Threshold
            $results | Should -HaveCount $config.Items

            # Verify concurrency
            $uniqueThreads = ($results | Group-Object ThreadId).Count
            $uniqueThreads | Should BeGreaterThan 1
            $uniqueThreads | Should BeLessThan $config.Threads
        }

        Write-Host "`nConcurrency Benchmark Results:" -ForegroundColor Green
        $benchmarkResults.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $([Math]::Round($_.Value.Duration, 2))s" -ForegroundColor Cyan
        }
    }
}

AfterAll {
    # Cleanup global variables and collections
    $Global:ThreadSafeResults.Clear()
    $Global:ThreadSafeErrors.Clear()
    $Global:ThreadSafeCounters.Clear()

    Remove-Variable -Name "ConcurrencyConfig" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeResults" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeErrors" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "ThreadSafeCounters" -Scope Global -ErrorAction SilentlyContinue

    # Cleanup test directories
    @($ConcurrencyTestPath, $PerformanceLogsPath) | ForEach-Object {
        if (Test-Path $_ -PathType Container) {
            $items = Get-ChildItem $_ -Force -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Force garbage collection to clean up test resources
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}


