#Requires -Module Pester

<#
.SYNOPSIS
    Memory profiling and resource management tests for Find-UnknownSID

.DESCRIPTION
    Comprehensive memory profiling and resource management testing for the Find-UnknownSID
    solution that validates memory usage patterns, garbage collection efficiency, and
    resource disposal in enterprise-scale processing scenarios.

    This test suite addresses critical memory and performance gaps identified in the test
    coverage analysis and implements enterprise-grade memory testing following PowerShell
    community standards and performance optimization best practices.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    Version: 1.0.0
    PowerShell Version: 5.1+

    Test Coverage: Memory profiling, resource management, garbage collection, memory leaks
    Priority: HIGH - Required for enterprise deployment and long-running operations

    TROUBLESHOOTING:
    - For memory issues: .\Troubleshooting\Performance\Memory-Issues.md
    - For resource leaks: .\Troubleshooting\Performance\Resource-Leak-Analysis.md
    - For GC problems: .\Troubleshooting\Performance\Garbage-Collection-Issues.md
#>

BeforeAll {
    # Import memory profiling utilities
    $script:ModulePath = Join-Path $PSScriptRoot '..\..\Find-UnknownSID.ps1'
    Import-Module $script:ModulePath -Force

    # Import test helpers
    $script:TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
    . $script:TestHelpersPath

    # Set up memory profiling test environment
    $script:CorrelationId = [System.Guid]::NewGuid().ToString()

    # Memory thresholds for enterprise environments (in MB)
    $script:MemoryThresholds = @{
        BaselineMemory = 50      # Baseline memory usage (MB)
        SmallDataset = 100       # Small dataset processing (MB)
        MediumDataset = 250      # Medium dataset processing (MB)
        LargeDataset = 500       # Large dataset processing (MB)
        MaximumMemory = 1024     # Maximum allowed memory usage (MB)
        GCEfficiency = 0.80      # GC should reclaim at least 80% of allocated memory
    }

    # Generate test datasets for memory testing
    $script:SmallSIDDataset = 1..100 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    $script:MediumSIDDataset = 1..1000 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    $script:LargeSIDDataset = 1..10000 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    # Memory utility functions
    function Get-CurrentMemoryUsage {
        param([string]$CorrelationId)

        $process = Get-Process -Id $PID
        return [Math]::Round($process.WorkingSet64 / 1MB, 2)
    }

    function Invoke-GarbageCollection {
        param([string]$CorrelationId)

        Write-Verbose "Invoking garbage collection - CorrelationId: $CorrelationId"
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        Start-Sleep -Milliseconds 500  # Allow GC to complete
    }

    function Measure-MemoryDelta {
        param(
            [scriptblock]$Operation,
            [string]$CorrelationId
        )

        Invoke-GarbageCollection -CorrelationId $CorrelationId
        $beforeMemory = Get-CurrentMemoryUsage -CorrelationId $CorrelationId

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = & $Operation
        $stopwatch.Stop()

        $afterMemory = Get-CurrentMemoryUsage -CorrelationId $CorrelationId
        Invoke-GarbageCollection -CorrelationId $CorrelationId
        $postGCMemory = Get-CurrentMemoryUsage -CorrelationId $CorrelationId

        return @{
            BeforeMemory = $beforeMemory
            AfterMemory = $afterMemory
            PostGCMemory = $postGCMemory
            MemoryDelta = $afterMemory - $beforeMemory
            MemoryReclaimed = $afterMemory - $postGCMemory
            GCEfficiency = if ($afterMemory -gt $beforeMemory) { ($afterMemory - $postGCMemory) / ($afterMemory - $beforeMemory) } else { 1.0 }
            ExecutionTime = $stopwatch.ElapsedMilliseconds
            OperationResult = $result
            CorrelationId = $CorrelationId
        }
    }
}

Describe "Memory Usage Profiling" -Tag "Performance", "Memory", "Profiling" {

    Context "Baseline Memory Validation" {
        BeforeEach {
            $script:BaselineCorrelationId = [System.Guid]::NewGuid().ToString()
            Invoke-GarbageCollection -CorrelationId $script:BaselineCorrelationId
        }

        It "Should maintain reasonable baseline memory usage" {
            # Test baseline memory consumption
            $baselineMemory = Get-CurrentMemoryUsage -CorrelationId $script:BaselineCorrelationId

            $baselineMemory | Should -BeLessThan $script:MemoryThresholds.BaselineMemory

            Write-Verbose "Baseline memory usage: $baselineMemory MB - CorrelationId: $script:BaselineCorrelationId"
        }

        It "Should establish consistent memory measurement" {
            # Test memory measurement consistency
            $measurements = @()

            for ($i = 0; $i -lt 5; $i++) {
                Start-Sleep -Milliseconds 100
                $measurements += Get-CurrentMemoryUsage -CorrelationId $script:BaselineCorrelationId
            }

            $maxVariation = ($measurements | Measure-Object -Maximum).Maximum - ($measurements | Measure-Object -Minimum).Minimum
            $maxVariation | Should -BeLessThan 10  # Less than 10MB variation

            Write-Verbose "Memory measurement variation: $maxVariation MB - CorrelationId: $script:BaselineCorrelationId"
        }

        It "Should validate garbage collection effectiveness" {
            # Test GC effectiveness
            $beforeGC = Get-CurrentMemoryUsage -CorrelationId $script:BaselineCorrelationId

            # Create temporary objects
            $tempData = 1..1000 | ForEach-Object {
                [PSCustomObject]@{
                    ID = $_
                    Data = "TempData" * 100
                    Timestamp = Get-Date
                }
            }

            $afterAllocation = Get-CurrentMemoryUsage -CorrelationId $script:BaselineCorrelationId
            Remove-Variable tempData

            Invoke-GarbageCollection -CorrelationId $script:BaselineCorrelationId
            $afterGC = Get-CurrentMemoryUsage -CorrelationId $script:BaselineCorrelationId

            $memoryReclaimed = $afterAllocation - $afterGC
            $gcEfficiency = $memoryReclaimed / ($afterAllocation - $beforeGC)

            $gcEfficiency | Should -BeGreaterThan $script:MemoryThresholds.GCEfficiency

            Write-Verbose "GC efficiency: $([Math]::Round($gcEfficiency * 100, 2))% - CorrelationId: $script:BaselineCorrelationId"
        }
    }

    Context "Small Dataset Memory Profiling" {
        BeforeEach {
            $script:SmallDataCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should process small SID datasets within memory limits" {
            # Test small dataset memory usage
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:SmallDataCorrelationId -Operation {
                Mock Test-SIDFormat {
                    return @{
                        SID = $args[0]
                        IsValid = $true
                        CorrelationId = $script:SmallDataCorrelationId
                    }
                } -ModuleName Find-UnknownSID

                $results = $script:SmallSIDDataset | ForEach-Object {
                    Test-SIDFormat -SID $_ -CorrelationId $script:SmallDataCorrelationId
                }

                return $results
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan $script:MemoryThresholds.SmallDataset
            $memoryProfile.GCEfficiency | Should -BeGreaterThan $script:MemoryThresholds.GCEfficiency
            $memoryProfile.OperationResult.Count | Should -Be $script:SmallSIDDataset.Count

            Write-Verbose "Small dataset memory delta: $($memoryProfile.MemoryDelta) MB, GC efficiency: $([Math]::Round($memoryProfile.GCEfficiency * 100, 2))% - CorrelationId: $script:SmallDataCorrelationId"
        }

        It "Should efficiently manage temporary objects in small datasets" {
            # Test temporary object management
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:SmallDataCorrelationId -Operation {
                $tempResults = @()

                foreach ($sid in $script:SmallSIDDataset) {
                    $tempObject = [PSCustomObject]@{
                        SID = $sid
                        ProcessedTime = Get-Date
                        ValidationResult = @{
                            IsValid = $true
                            Format = 'Standard'
                            CorrelationId = $script:SmallDataCorrelationId
                        }
                    }

                    $tempResults += $tempObject
                }

                # Process and cleanup
                $finalResults = $tempResults | Where-Object { $_.ValidationResult.IsValid }
                Remove-Variable tempResults

                return $finalResults
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan $script:MemoryThresholds.SmallDataset
            $memoryProfile.GCEfficiency | Should -BeGreaterThan 0.70  # 70% efficiency for temporary objects

            Write-Verbose "Temporary object management - Memory delta: $($memoryProfile.MemoryDelta) MB - CorrelationId: $script:SmallDataCorrelationId"
        }

        It "Should handle string operations efficiently in small datasets" {
            # Test string operation memory efficiency
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:SmallDataCorrelationId -Operation {
                $stringBuilder = [System.Text.StringBuilder]::new()

                foreach ($sid in $script:SmallSIDDataset) {
                    [void]$stringBuilder.AppendLine("Processing SID: $sid at $(Get-Date)")
                }

                $result = $stringBuilder.ToString()
                $stringBuilder.Clear()

                return @{
                    OutputLength = $result.Length
                    ProcessedCount = $script:SmallSIDDataset.Count
                    CorrelationId = $script:SmallDataCorrelationId
                }
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan 20  # 20MB for string operations
            $memoryProfile.OperationResult.ProcessedCount | Should -Be $script:SmallSIDDataset.Count

            Write-Verbose "String operations memory delta: $($memoryProfile.MemoryDelta) MB - CorrelationId: $script:SmallDataCorrelationId"
        }
    }

    Context "Medium Dataset Memory Profiling" {
        BeforeEach {
            $script:MediumDataCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should process medium SID datasets within memory limits" {
            # Test medium dataset memory usage
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:MediumDataCorrelationId -Operation {
                Mock Get-OrphanedSIDs {
                    return $script:MediumSIDDataset | ForEach-Object {
                        @{
                            SID = $_
                            Status = 'Orphaned'
                            CorrelationId = $script:MediumDataCorrelationId
                        }
                    }
                } -ModuleName Find-UnknownSID

                $results = Get-OrphanedSIDs -CorrelationId $script:MediumDataCorrelationId
                return $results
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan $script:MemoryThresholds.MediumDataset
            $memoryProfile.GCEfficiency | Should -BeGreaterThan $script:MemoryThresholds.GCEfficiency
            $memoryProfile.OperationResult.Count | Should -Be $script:MediumSIDDataset.Count

            Write-Verbose "Medium dataset memory delta: $($memoryProfile.MemoryDelta) MB, GC efficiency: $([Math]::Round($memoryProfile.GCEfficiency * 100, 2))% - CorrelationId: $script:MediumDataCorrelationId"
        }

        It "Should manage collections efficiently in medium datasets" {
            # Test collection management
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:MediumDataCorrelationId -Operation {
                # Use ArrayList for better performance
                $results = [System.Collections.ArrayList]::new()

                foreach ($sid in $script:MediumSIDDataset) {
                    $validationResult = @{
                        SID = $sid
                        IsValid = $sid -match "^S-1-5-21-"
                        ProcessedAt = Get-Date
                        CorrelationId = $script:MediumDataCorrelationId
                    }

                    [void]$results.Add($validationResult)
                }

                # Convert to regular array for return
                return $results.ToArray()
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan $script:MemoryThresholds.MediumDataset
            $memoryProfile.OperationResult.Count | Should -Be $script:MediumSIDDataset.Count

            Write-Verbose "Collection management memory delta: $($memoryProfile.MemoryDelta) MB - CorrelationId: $script:MediumDataCorrelationId"
        }

        It "Should handle chunked processing efficiently" {
            # Test chunked processing memory efficiency
            $chunkSize = 250
            $chunks = [Math]::Ceiling($script:MediumSIDDataset.Count / $chunkSize)

            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:MediumDataCorrelationId -Operation {
                $allResults = @()

                for ($i = 0; $i -lt $chunks; $i++) {
                    $startIndex = $i * $chunkSize
                    $endIndex = [Math]::Min(($i + 1) * $chunkSize - 1, $script:MediumSIDDataset.Count - 1)
                    $chunk = $script:MediumSIDDataset[$startIndex..$endIndex]

                    $chunkResults = $chunk | ForEach-Object {
                        @{
                            SID = $_
                            ChunkId = $i
                            CorrelationId = $script:MediumDataCorrelationId
                        }
                    }

                    $allResults += $chunkResults

                    # Force GC after each chunk to maintain low memory
                    if ($i % 2 -eq 1) {
                        [System.GC]::Collect()
                    }
                }

                return $allResults
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan ($script:MemoryThresholds.MediumDataset * 0.8)  # 20% better than non-chunked
            $memoryProfile.OperationResult.Count | Should -Be $script:MediumSIDDataset.Count

            Write-Verbose "Chunked processing memory delta: $($memoryProfile.MemoryDelta) MB for $chunks chunks - CorrelationId: $script:MediumDataCorrelationId"
        }
    }

    Context "Large Dataset Memory Profiling" {
        BeforeEach {
            $script:LargeDataCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should process large SID datasets within memory limits" {
            # Test large dataset memory usage
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LargeDataCorrelationId -Operation {
                # Use pipeline for memory efficiency
                $results = $script:LargeSIDDataset | ForEach-Object {
                    @{
                        SID = $_
                        IsValid = $_ -match "^S-1-5-21-"
                        ProcessedAt = Get-Date
                        CorrelationId = $script:LargeDataCorrelationId
                    }
                } | Where-Object { $_.IsValid }

                return @($results)  # Force enumeration
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan $script:MemoryThresholds.LargeDataset
            $memoryProfile.OperationResult.Count | Should -Be $script:LargeSIDDataset.Count

            Write-Verbose "Large dataset memory delta: $($memoryProfile.MemoryDelta) MB - CorrelationId: $script:LargeDataCorrelationId"
        }

        It "Should use streaming processing for large datasets" {
            # Test streaming processing
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LargeDataCorrelationId -Operation {
                $processedCount = 0
                $validCount = 0

                # Process without storing all results in memory
                foreach ($sid in $script:LargeSIDDataset) {
                    $isValid = $sid -match "^S-1-5-21-"
                    if ($isValid) {
                        $validCount++
                    }
                    $processedCount++

                    # Periodic cleanup
                    if ($processedCount % 1000 -eq 0) {
                        [System.GC]::Collect()
                    }
                }

                return @{
                    ProcessedCount = $processedCount
                    ValidCount = $validCount
                    CorrelationId = $script:LargeDataCorrelationId
                }
            }

            $memoryProfile.MemoryDelta | Should -BeLessThan 100  # Streaming should use minimal memory
            $memoryProfile.OperationResult.ProcessedCount | Should -Be $script:LargeSIDDataset.Count

            Write-Verbose "Streaming processing memory delta: $($memoryProfile.MemoryDelta) MB - CorrelationId: $script:LargeDataCorrelationId"
        }

        It "Should maintain consistent memory usage during extended processing" {
            # Test memory stability over time
            $memorySnapshots = @()
            $startTime = Get-Date

            foreach ($batch in (0..9)) {
                $batchData = $script:LargeSIDDataset[($batch * 1000)..(($batch + 1) * 1000 - 1)]

                $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LargeDataCorrelationId -Operation {
                    $batchResults = $batchData | ForEach-Object {
                        [PSCustomObject]@{
                            SID = $_
                            BatchId = $batch
                            ProcessedAt = Get-Date
                        }
                    }

                    # Simulate processing without retaining results
                    $batchResults | Out-Null

                    return $batchData.Count
                }

                $memorySnapshots += @{
                    Batch = $batch
                    MemoryUsage = $memoryProfile.PostGCMemory
                    ProcessingTime = $memoryProfile.ExecutionTime
                    CorrelationId = $script:LargeDataCorrelationId
                }

                # Force cleanup between batches
                [System.GC]::Collect()
                Start-Sleep -Milliseconds 100
            }

            # Check memory stability (no significant growth)
            $initialMemory = $memorySnapshots[0].MemoryUsage
            $finalMemory = $memorySnapshots[-1].MemoryUsage
            $memoryGrowth = $finalMemory - $initialMemory

            $memoryGrowth | Should -BeLessThan 50  # Less than 50MB growth over time

            Write-Verbose "Memory growth over extended processing: $memoryGrowth MB - CorrelationId: $script:LargeDataCorrelationId"
        }
    }

    Context "Memory Leak Detection" {
        BeforeEach {
            $script:LeakDetectionCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should detect and prevent memory leaks in repeated operations" {
            # Test for memory leaks in repeated operations
            $initialMemory = Get-CurrentMemoryUsage -CorrelationId $script:LeakDetectionCorrelationId
            $memoryReadings = @()

            for ($iteration = 1; $iteration -le 10; $iteration++) {
                $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LeakDetectionCorrelationId -Operation {
                    # Simulate repeated SID processing
                    $tempData = $script:SmallSIDDataset | ForEach-Object {
                        [PSCustomObject]@{
                            SID = $_
                            Iteration = $iteration
                            Data = "ProcessingData" * 50
                            Timestamp = Get-Date
                        }
                    }

                    # Process and cleanup
                    $processedCount = ($tempData | Where-Object { $_.SID }).Count
                    Remove-Variable tempData

                    return $processedCount
                }

                $memoryReadings += @{
                    Iteration = $iteration
                    MemoryAfterGC = $memoryProfile.PostGCMemory
                    MemoryDelta = $memoryProfile.MemoryDelta
                    GCEfficiency = $memoryProfile.GCEfficiency
                }

                # Force cleanup between iterations
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
                Start-Sleep -Milliseconds 200
            }

            # Check for memory leak (consistent growth)
            $firstHalfAvg = ($memoryReadings[0..4] | Measure-Object -Property MemoryAfterGC -Average).Average
            $secondHalfAvg = ($memoryReadings[5..9] | Measure-Object -Property MemoryAfterGC -Average).Average
            $memoryTrend = $secondHalfAvg - $firstHalfAvg

            $memoryTrend | Should -BeLessThan 20  # Less than 20MB trend over iterations

            Write-Verbose "Memory trend over 10 iterations: $memoryTrend MB - CorrelationId: $script:LeakDetectionCorrelationId"
        }

        It "Should properly dispose of IDisposable objects" {
            # Test IDisposable object disposal
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LeakDetectionCorrelationId -Operation {
                $disposableObjects = @()

                try {
                    # Create disposable objects
                    for ($i = 0; $i -lt 100; $i++) {
                        $stringWriter = New-Object System.IO.StringWriter
                        $stringWriter.WriteLine("Test data $i")
                        $disposableObjects += $stringWriter
                    }

                    # Use objects
                    $outputLength = ($disposableObjects | ForEach-Object { $_.ToString().Length } | Measure-Object -Sum).Sum

                    return @{
                        ObjectCount = $disposableObjects.Count
                        OutputLength = $outputLength
                        CorrelationId = $script:LeakDetectionCorrelationId
                    }
                }
                finally {
                    # Ensure disposal
                    foreach ($obj in $disposableObjects) {
                        if ($obj -and $obj -is [System.IDisposable]) {
                            $obj.Dispose()
                        }
                    }
                }
            }

            $memoryProfile.GCEfficiency | Should -BeGreaterThan 0.90  # 90% efficiency expected with proper disposal

            Write-Verbose "IDisposable object test - GC efficiency: $([Math]::Round($memoryProfile.GCEfficiency * 100, 2))% - CorrelationId: $script:LeakDetectionCorrelationId"
        }

        It "Should handle event handler cleanup properly" {
            # Test event handler memory management
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:LeakDetectionCorrelationId -Operation {
                $eventSources = @()

                try {
                    # Create objects with event handlers
                    for ($i = 0; $i -lt 50; $i++) {
                        $timer = New-Object System.Timers.Timer
                        $timer.Interval = 1000

                        # Add event handler
                        $handler = {
                            param($source, $eventArgs)
                            Write-Verbose "Timer elapsed: $($source.Interval)"
                        }
                        $timer.add_Elapsed($handler)

                        $eventSources += @{
                            Timer = $timer
                            Handler = $handler
                        }
                    }

                    return @{
                        EventSourceCount = $eventSources.Count
                        CorrelationId = $script:LeakDetectionCorrelationId
                    }
                }
                finally {
                    # Clean up event handlers
                    foreach ($source in $eventSources) {
                        if ($source.Timer) {
                            $source.Timer.remove_Elapsed($source.Handler)
                            $source.Timer.Dispose()
                        }
                    }
                }
            }

            $memoryProfile.GCEfficiency | Should -BeGreaterThan 0.85  # 85% efficiency with event cleanup

            Write-Verbose "Event handler cleanup test - GC efficiency: $([Math]::Round($memoryProfile.GCEfficiency * 100, 2))% - CorrelationId: $script:LeakDetectionCorrelationId"
        }
    }

    Context "Resource Management Validation" {
        BeforeEach {
            $script:ResourceCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should properly manage file handle resources" {
            # Test file handle management
            $memoryProfile = Measure-MemoryDelta -CorrelationId $script:ResourceCorrelationId -Operation {
                $fileHandles = @()

                try {
                    # Create multiple file handles
                    for ($i = 0; $i -lt 20; $i++) {
                        $tempFile = Join-Path $TestDrive "TempFile$i.txt"
                        "Test content $i" | Set-Content -Path $tempFile

                        $fileStream = [System.IO.File]::OpenRead($tempFile)
                        $fileHandles += $fileStream
                    }

                    # Use file handles
                    $totalBytes = ($fileHandles | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum

                    return @{
                        FileHandleCount = $fileHandles.Count
                        TotalBytes = $totalBytes
                        CorrelationId = $script:ResourceCorrelationId
                    }
                }
                finally {
                    # Clean up file handles
                    foreach ($handle in $fileHandles) {
                        if ($handle) {
                            $handle.Close()
                            $handle.Dispose()
                        }
                    }
                }
            }

            $memoryProfile.GCEfficiency | Should -BeGreaterThan 0.80
            $memoryProfile.OperationResult.FileHandleCount | Should -Be 20

            Write-Verbose "File handle management - GC efficiency: $([Math]::Round($memoryProfile.GCEfficiency * 100, 2))% - CorrelationId: $script:ResourceCorrelationId"
        }

        It "Should validate maximum memory usage limits" {
            # Test memory usage limits enforcement
            $currentMemory = Get-CurrentMemoryUsage -CorrelationId $script:ResourceCorrelationId

            $currentMemory | Should -BeLessThan $script:MemoryThresholds.MaximumMemory

            if ($currentMemory -gt ($script:MemoryThresholds.MaximumMemory * 0.8)) {
                Write-Warning "Memory usage approaching limit: $currentMemory MB / $($script:MemoryThresholds.MaximumMemory) MB"
            }

            Write-Verbose "Current memory usage: $currentMemory MB (Limit: $($script:MemoryThresholds.MaximumMemory) MB) - CorrelationId: $script:ResourceCorrelationId"
        }
    }
}

Describe "Memory Profiling Infrastructure" -Tag "Performance", "Infrastructure", "Memory" {

    Context "Memory Testing Framework" {
        It "Should have proper memory threshold definitions" {
            # Validate memory thresholds
            $script:MemoryThresholds.BaselineMemory | Should -BeGreaterThan 0
            $script:MemoryThresholds.SmallDataset | Should -BeGreaterThan $script:MemoryThresholds.BaselineMemory
            $script:MemoryThresholds.MediumDataset | Should -BeGreaterThan $script:MemoryThresholds.SmallDataset
            $script:MemoryThresholds.LargeDataset | Should -BeGreaterThan $script:MemoryThresholds.MediumDataset
            $script:MemoryThresholds.MaximumMemory | Should -BeGreaterThan $script:MemoryThresholds.LargeDataset
            $script:MemoryThresholds.GCEfficiency | Should -BeGreaterThan 0.5
            $script:MemoryThresholds.GCEfficiency | Should -BeLessThan 1.0
        }

        It "Should have comprehensive test datasets" {
            # Validate test datasets
            $script:SmallSIDDataset.Count | Should -Be 100
            $script:MediumSIDDataset.Count | Should -Be 1000
            $script:LargeSIDDataset.Count | Should -Be 10000

            # Validate SID format
            $script:SmallSIDDataset[0] | Should -Match "^S-1-5-21-"
            $script:MediumSIDDataset[0] | Should -Match "^S-1-5-21-"
            $script:LargeSIDDataset[0] | Should -Match "^S-1-5-21-"
        }

        It "Should have functional memory utility functions" {
            # Test utility functions
            $currentMemory = Get-CurrentMemoryUsage -CorrelationId $script:CorrelationId
            $currentMemory | Should -BeGreaterThan 0

            { Invoke-GarbageCollection -CorrelationId $script:CorrelationId } | Should -Not -Throw

            $memoryDelta = Measure-MemoryDelta -CorrelationId $script:CorrelationId -Operation {
                $tempData = 1..100 | ForEach-Object { "Test$_" }
                return $tempData.Count
            }

            $memoryDelta.CorrelationId | Should -Be $script:CorrelationId
            $memoryDelta.OperationResult | Should -Be 100
        }
    }
}

AfterAll {
    # Cleanup memory profiling test environment
    Write-Verbose "Memory profiling test cleanup - CorrelationId: $($script:CorrelationId)"

    # Final garbage collection
    Invoke-GarbageCollection -CorrelationId $script:CorrelationId

    # Log final memory usage
    $finalMemory = Get-CurrentMemoryUsage -CorrelationId $script:CorrelationId
    Write-Information "Memory profiling tests completed - Final memory usage: $finalMemory MB" -InformationAction Continue
}
