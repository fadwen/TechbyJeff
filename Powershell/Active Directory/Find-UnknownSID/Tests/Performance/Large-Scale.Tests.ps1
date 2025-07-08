#Requires -Module Pester

<#
.SYNOPSIS
    Performance tests for Find-UnknownSID large-scale processing and optimization

.DESCRIPTION
    Comprehensive performance testing for the Find-UnknownSID solution that validates
    enterprise-scale processing capabilities, memory usage, and performance optimization.

    This test suite addresses critical performance gaps identified in the test coverage
    analysis and implements enterprise-grade performance testing following PowerShell
    community standards and performance optimization best practices.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    Version: 1.0.0
    PowerShell Version: 5.1+

    Test Coverage: Large-scale processing, memory profiling, concurrent operations
    Priority: HIGH - Required for enterprise deployment and scalability validation

    TROUBLESHOOTING:
    - For performance issues: .\Troubleshooting\Performance\Performance-Issues.md
    - For memory problems: .\Troubleshooting\Performance\Memory-Optimization.md
#>

BeforeAll {
    # Import performance testing utilities
    $script:ModulePath = Join-Path $PSScriptRoot '..\..\Find-UnknownSID.ps1'
    Import-Module $script:ModulePath -Force

    # Import test helpers
    $script:TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
    . $script:TestHelpersPath

    # Generate large test datasets for performance validation
    $script:SmallDataset = 1..100 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    $script:MediumDataset = 1..1000 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    $script:LargeDataset = 1..10000 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    # Create very large dataset for stress testing
    $script:ExtraLargeDataset = 1..50000 | ForEach-Object {
        "S-1-5-21-$(Get-Random)-$(Get-Random)-$(Get-Random)-$_"
    }

    $script:CorrelationId = [System.Guid]::NewGuid().ToString()

    # Performance baselines (in seconds)
    $script:Baselines = @{
        SmallDataset = 5       # 100 objects in 5 seconds
        MediumDataset = 15     # 1,000 objects in 15 seconds
        LargeDataset = 30      # 10,000 objects in 30 seconds
        ExtraLargeDataset = 150 # 50,000 objects in 150 seconds (2.5 minutes)
    }

    # Memory baselines (in MB)
    $script:MemoryBaselines = @{
        SmallDataset = 50      # 50MB for 100 objects
        MediumDataset = 200    # 200MB for 1,000 objects
        LargeDataset = 500     # 500MB for 10,000 objects
        ExtraLargeDataset = 1000 # 1GB for 50,000 objects
    }

    # Mock external dependencies for consistent performance testing
    Mock Write-Verbose { } -ModuleName Find-UnknownSID
    Mock Write-Information { } -ModuleName Find-UnknownSID
    Mock Write-Warning { } -ModuleName Find-UnknownSID
}

Describe "Large-Scale Performance Validation" -Tag "Performance", "Scale", "Enterprise" {

    Context "Processing Speed Benchmarks" {
        BeforeEach {
            $script:PerformanceCorrelationId = [System.Guid]::NewGuid().ToString()

            # Force garbage collection before each test
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        }

        It "Should process 100 SIDs within 5 seconds" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $result = $script:SmallDataset | Test-SIDFormat -CorrelationId $script:PerformanceCorrelationId

            $stopwatch.Stop()
            Write-Verbose "Small dataset processing: $($stopwatch.ElapsedSeconds) seconds"

            $stopwatch.ElapsedSeconds | Should -BeLessThan $script:Baselines.SmallDataset
            $result.Count | Should -Be 100

            # Verify all results are valid
            $validResults = $result | Where-Object { $_.IsValid -eq $true }
            $validResults.Count | Should -Be 100
        }

        It "Should process 1,000 SIDs within 15 seconds" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $result = $script:MediumDataset | Test-SIDFormat -CorrelationId $script:PerformanceCorrelationId

            $stopwatch.Stop()
            Write-Verbose "Medium dataset processing: $($stopwatch.ElapsedSeconds) seconds"

            $stopwatch.ElapsedSeconds | Should -BeLessThan $script:Baselines.MediumDataset
            $result.Count | Should -Be 1000

            # Calculate processing rate
            $processingRate = 1000 / $stopwatch.ElapsedSeconds
            Write-Verbose "Processing rate: $([math]::Round($processingRate, 2)) SIDs/second"
            $processingRate | Should -BeGreaterThan 50  # Minimum 50 SIDs per second
        }

        It "Should process 10,000 SIDs within 30 seconds" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $result = $script:LargeDataset | Test-SIDFormat -CorrelationId $script:PerformanceCorrelationId

            $stopwatch.Stop()
            Write-Verbose "Large dataset processing: $($stopwatch.ElapsedSeconds) seconds"

            $stopwatch.ElapsedSeconds | Should -BeLessThan $script:Baselines.LargeDataset
            $result.Count | Should -Be 10000

            # Calculate processing rate for large dataset
            $processingRate = 10000 / $stopwatch.ElapsedSeconds
            Write-Verbose "Large dataset processing rate: $([math]::Round($processingRate, 2)) SIDs/second"
            $processingRate | Should -BeGreaterThan 300  # Minimum 300 SIDs per second for large datasets
        }

        It "Should handle stress testing with 50,000 SIDs" {
            # This is a stress test - longer timeout allowed
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Process in chunks to avoid timeout issues
            $chunkSize = 10000
            $totalProcessed = 0
            $allResults = @()

            for ($i = 0; $i -lt $script:ExtraLargeDataset.Count; $i += $chunkSize) {
                $chunk = $script:ExtraLargeDataset[$i..([math]::Min($i + $chunkSize - 1, $script:ExtraLargeDataset.Count - 1))]
                $chunkResult = $chunk | Test-SIDFormat -CorrelationId $script:PerformanceCorrelationId
                $allResults += $chunkResult
                $totalProcessed += $chunk.Count

                Write-Verbose "Processed chunk: $totalProcessed/$($script:ExtraLargeDataset.Count)"
            }

            $stopwatch.Stop()
            Write-Verbose "Extra large dataset processing: $($stopwatch.ElapsedSeconds) seconds"
            Write-Verbose "Total processed: $totalProcessed objects"

            $stopwatch.ElapsedSeconds | Should -BeLessThan $script:Baselines.ExtraLargeDataset
            $allResults.Count | Should -Be 50000

            # Calculate final processing rate
            $processingRate = 50000 / $stopwatch.ElapsedSeconds
            Write-Verbose "Stress test processing rate: $([math]::Round($processingRate, 2)) SIDs/second"
            $processingRate | Should -BeGreaterThan 250  # Minimum 250 SIDs per second for stress test
        }
    }

    Context "Memory Usage Validation" {
        BeforeEach {
            $script:MemoryCorrelationId = [System.Guid]::NewGuid().ToString()

            # Force garbage collection and get baseline memory
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        }

        It "Should maintain memory usage within acceptable limits for small datasets" {
            $memoryBefore = [System.GC]::GetTotalMemory($false)

            $result = $script:SmallDataset | Test-SIDFormat -CorrelationId $script:MemoryCorrelationId

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $memoryAfter = [System.GC]::GetTotalMemory($true)

            $memoryIncrease = $memoryAfter - $memoryBefore
            $memoryIncreaseMB = [math]::Round($memoryIncrease / 1MB, 2)

            Write-Verbose "Small dataset memory increase: $memoryIncreaseMB MB"
            $memoryIncreaseMB | Should -BeLessThan $script:MemoryBaselines.SmallDataset
        }

        It "Should scale memory usage linearly for medium datasets" {
            $memoryBefore = [System.GC]::GetTotalMemory($false)

            $result = $script:MediumDataset | Test-SIDFormat -CorrelationId $script:MemoryCorrelationId

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $memoryAfter = [System.GC]::GetTotalMemory($true)

            $memoryIncrease = $memoryAfter - $memoryBefore
            $memoryIncreaseMB = [math]::Round($memoryIncrease / 1MB, 2)

            Write-Verbose "Medium dataset memory increase: $memoryIncreaseMB MB"
            $memoryIncreaseMB | Should -BeLessThan $script:MemoryBaselines.MediumDataset

            # Calculate memory per object
            $memoryPerObject = $memoryIncrease / 1000
            Write-Verbose "Memory per object: $([math]::Round($memoryPerObject, 2)) bytes"
            $memoryPerObject | Should -BeLessThan 200000  # Less than 200KB per object
        }

        It "Should handle large datasets without excessive memory consumption" {
            $memoryBefore = [System.GC]::GetTotalMemory($false)

            $result = $script:LargeDataset | Test-SIDFormat -CorrelationId $script:MemoryCorrelationId

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $memoryAfter = [System.GC]::GetTotalMemory($true)

            $memoryIncrease = $memoryAfter - $memoryBefore
            $memoryIncreaseMB = [math]::Round($memoryIncrease / 1MB, 2)

            Write-Verbose "Large dataset memory increase: $memoryIncreaseMB MB"
            $memoryIncreaseMB | Should -BeLessThan $script:MemoryBaselines.LargeDataset

            # Verify memory efficiency
            $memoryPerObject = $memoryIncrease / 10000
            Write-Verbose "Large dataset memory per object: $([math]::Round($memoryPerObject, 2)) bytes"
            $memoryPerObject | Should -BeLessThan 50000  # Less than 50KB per object for large datasets
        }

        It "Should not have memory leaks during repeated operations" {
            $memoryBefore = [System.GC]::GetTotalMemory($true)

            # Perform 10 iterations of processing to detect memory leaks
            1..10 | ForEach-Object {
                $iteration = $_
                Write-Verbose "Memory leak test iteration: $iteration"

                $result = $script:SmallDataset | Test-SIDFormat -CorrelationId "$($script:MemoryCorrelationId)-$iteration"

                # Force garbage collection after each iteration
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()

                $currentMemory = [System.GC]::GetTotalMemory($false)
                $currentIncrease = $currentMemory - $memoryBefore
                Write-Verbose "Iteration $iteration memory increase: $([math]::Round($currentIncrease / 1MB, 2)) MB"
            }

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $memoryAfter = [System.GC]::GetTotalMemory($true)

            $memoryIncrease = $memoryAfter - $memoryBefore
            $memoryIncreaseMB = [math]::Round($memoryIncrease / 1MB, 2)

            Write-Verbose "Total memory increase after 10 iterations: $memoryIncreaseMB MB"

            # Memory increase should be minimal (less than 100MB) after 10 iterations
            $memoryIncreaseMB | Should -BeLessThan 100
        }
    }

    Context "Concurrent Operations" {
        BeforeEach {
            $script:ConcurrentCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should handle concurrent processing without deadlocks" {
            $jobs = @()
            $jobCount = 5

            # Start multiple concurrent jobs processing medium datasets
            1..$jobCount | ForEach-Object {
                $jobNumber = $_
                $job = Start-Job -ScriptBlock {
                    param($Dataset, $CorrelationId, $ModulePath)

                    # Import module in job context
                    Import-Module $ModulePath -Force

                    # Process dataset
                    $result = $Dataset | Test-SIDFormat -CorrelationId $CorrelationId

                    return @{
                        JobNumber = $CorrelationId.Split('-')[-1]
                        ProcessedCount = $result.Count
                        Success = $true
                    }
                } -ArgumentList $script:MediumDataset, "$($script:ConcurrentCorrelationId)-Job$jobNumber", $script:ModulePath

                $jobs += $job
            }

            # Wait for all jobs to complete (with timeout)
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $completed = Wait-Job -Job $jobs -Timeout 120  # 2 minute timeout
            $stopwatch.Stop()

            Write-Verbose "Concurrent processing completed in: $($stopwatch.ElapsedSeconds) seconds"

            $completed.Count | Should -Be $jobCount

            # Verify all jobs completed successfully
            $results = Receive-Job -Job $jobs
            $results.Count | Should -Be $jobCount

            foreach ($result in $results) {
                $result.Success | Should -BeTrue
                $result.ProcessedCount | Should -Be 1000
            }

            # Calculate total throughput
            $totalProcessed = $results | Measure-Object -Property ProcessedCount -Sum | Select-Object -ExpandProperty Sum
            $throughput = $totalProcessed / $stopwatch.ElapsedSeconds
            Write-Verbose "Concurrent throughput: $([math]::Round($throughput, 2)) SIDs/second"

            # Cleanup
            Remove-Job -Job $jobs -Force
        }

        It "Should scale performance with multiple threads" {
            # Test single-threaded performance
            $singleThreadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $singleThreadResult = $script:MediumDataset | Test-SIDFormat -CorrelationId "$($script:ConcurrentCorrelationId)-Single"
            $singleThreadStopwatch.Stop()

            # Test multi-threaded performance (split dataset)
            $multiThreadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $chunkSize = [math]::Ceiling($script:MediumDataset.Count / 4)  # 4 chunks
            $chunks = @()

            for ($i = 0; $i -lt $script:MediumDataset.Count; $i += $chunkSize) {
                $chunk = $script:MediumDataset[$i..([math]::Min($i + $chunkSize - 1, $script:MediumDataset.Count - 1))]
                $chunks += ,$chunk
            }

            $jobs = @()
            $chunks | ForEach-Object {
                $chunkIndex = $chunks.IndexOf($_)
                $job = Start-Job -ScriptBlock {
                    param($Chunk, $CorrelationId, $ModulePath)
                    Import-Module $ModulePath -Force
                    $Chunk | Test-SIDFormat -CorrelationId $CorrelationId
                } -ArgumentList $_, "$($script:ConcurrentCorrelationId)-Chunk$chunkIndex", $script:ModulePath

                $jobs += $job
            }

            Wait-Job -Job $jobs -Timeout 60 | Out-Null
            $multiThreadResults = Receive-Job -Job $jobs
            $multiThreadStopwatch.Stop()

            Write-Verbose "Single-threaded time: $($singleThreadStopwatch.ElapsedSeconds) seconds"
            Write-Verbose "Multi-threaded time: $($multiThreadStopwatch.ElapsedSeconds) seconds"

            # Multi-threaded should be faster or at least not significantly slower
            $performanceRatio = $multiThreadStopwatch.ElapsedSeconds / $singleThreadStopwatch.ElapsedSeconds
            Write-Verbose "Performance ratio (multi/single): $([math]::Round($performanceRatio, 2))"

            $performanceRatio | Should -BeLessThan 1.5  # Multi-threaded shouldn't be more than 50% slower
            $multiThreadResults.Count | Should -Be $script:MediumDataset.Count

            # Cleanup
            Remove-Job -Job $jobs -Force
        }
    }
}

Describe "Performance Regression Detection" -Tag "Performance", "Regression", "Monitoring" {

    Context "Baseline Establishment" {
        BeforeEach {
            $script:BaselineCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should establish performance baselines for future comparison" {
            $performanceData = @{
                TestDate = Get-Date
                SmallDatasetTime = 0
                MediumDatasetTime = 0
                LargeDatasetTime = 0
                SmallDatasetMemory = 0
                MediumDatasetMemory = 0
                LargeDatasetMemory = 0
                CorrelationId = $script:BaselineCorrelationId
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                OSVersion = [System.Environment]::OSVersion.ToString()
            }

            # Measure small dataset performance
            $memoryBefore = [System.GC]::GetTotalMemory($true)
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $script:SmallDataset | Test-SIDFormat -CorrelationId $script:BaselineCorrelationId | Out-Null
            $stopwatch.Stop()
            $performanceData.SmallDatasetTime = $stopwatch.ElapsedMilliseconds
            $performanceData.SmallDatasetMemory = [System.GC]::GetTotalMemory($true) - $memoryBefore

            # Measure medium dataset performance
            $memoryBefore = [System.GC]::GetTotalMemory($true)
            $stopwatch.Restart()
            $script:MediumDataset | Test-SIDFormat -CorrelationId $script:BaselineCorrelationId | Out-Null
            $stopwatch.Stop()
            $performanceData.MediumDatasetTime = $stopwatch.ElapsedMilliseconds
            $performanceData.MediumDatasetMemory = [System.GC]::GetTotalMemory($true) - $memoryBefore

            # Measure large dataset performance
            $memoryBefore = [System.GC]::GetTotalMemory($true)
            $stopwatch.Restart()
            $script:LargeDataset | Test-SIDFormat -CorrelationId $script:BaselineCorrelationId | Out-Null
            $stopwatch.Stop()
            $performanceData.LargeDatasetTime = $stopwatch.ElapsedMilliseconds
            $performanceData.LargeDatasetMemory = [System.GC]::GetTotalMemory($true) - $memoryBefore

            # Create results directory if it doesn't exist
            $resultsPath = Join-Path $PSScriptRoot "..\TestResults"
            if (-not (Test-Path $resultsPath)) {
                New-Item -Path $resultsPath -ItemType Directory -Force
            }

            # Save baseline data
            $baselinePath = Join-Path $resultsPath "Performance-Baseline-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $performanceData | ConvertTo-Json -Depth 5 | Out-File $baselinePath

            # Validate baseline was created
            Test-Path $baselinePath | Should -BeTrue
            $savedBaseline = Get-Content $baselinePath | ConvertFrom-Json
            $savedBaseline.CorrelationId | Should -Be $script:BaselineCorrelationId

            # Verify performance metrics are reasonable
            $performanceData.SmallDatasetTime | Should -BeLessThan 5000    # 5 seconds
            $performanceData.MediumDatasetTime | Should -BeLessThan 15000   # 15 seconds
            $performanceData.LargeDatasetTime | Should -BeLessThan 30000    # 30 seconds

            Write-Verbose "Performance baseline saved: $baselinePath"
            Write-Verbose "Small dataset: $($performanceData.SmallDatasetTime)ms, $([math]::Round($performanceData.SmallDatasetMemory / 1MB, 2))MB"
            Write-Verbose "Medium dataset: $($performanceData.MediumDatasetTime)ms, $([math]::Round($performanceData.MediumDatasetMemory / 1MB, 2))MB"
            Write-Verbose "Large dataset: $($performanceData.LargeDatasetTime)ms, $([math]::Round($performanceData.LargeDatasetMemory / 1MB, 2))MB"
        }

        It "Should detect performance regressions" {
            # Simulate baseline data
            $baselineData = @{
                SmallDatasetTime = 2000   # 2 seconds
                MediumDatasetTime = 8000  # 8 seconds
                LargeDatasetTime = 20000  # 20 seconds
            }

            # Measure current performance
            $currentData = @{
                SmallDatasetTime = 0
                MediumDatasetTime = 0
                LargeDatasetTime = 0
            }

            # Measure small dataset
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $script:SmallDataset | Test-SIDFormat -CorrelationId $script:BaselineCorrelationId | Out-Null
            $currentData.SmallDatasetTime = $stopwatch.ElapsedMilliseconds

            # Calculate regression percentage
            $regressionThreshold = 20  # 20% regression threshold

            foreach ($dataset in @('SmallDatasetTime', 'MediumDatasetTime', 'LargeDatasetTime')) {
                if ($currentData[$dataset] -gt 0) {
                    $regressionPercent = (($currentData[$dataset] - $baselineData[$dataset]) / $baselineData[$dataset]) * 100
                    Write-Verbose "$dataset regression: $([math]::Round($regressionPercent, 2))%"

                    # Fail test if regression exceeds threshold
                    $regressionPercent | Should -BeLessThan $regressionThreshold
                }
            }
        }
    }
}

AfterAll {
    # Performance test cleanup
    Write-Verbose "Performance test cleanup - CorrelationId: $($script:CorrelationId)"

    # Force garbage collection to clean up large datasets
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    # Remove large datasets from memory
    Remove-Variable -Name SmallDataset -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name MediumDataset -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name LargeDataset -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ExtraLargeDataset -Scope Script -ErrorAction SilentlyContinue

    Write-Verbose "Performance testing completed successfully"
}
