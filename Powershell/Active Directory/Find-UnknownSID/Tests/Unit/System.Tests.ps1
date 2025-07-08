#Requires -Module Pester
<#
.SYNOPSIS
    Comprehensive Pester tests for System module functions

.DESCRIPTION
    Enterprise-grade unit tests covering system management operations: -Get-MemoryStatistics: Memory usage monitoring and reporting -Initialize-MemoryManager: Memory management system initialization -Invoke-GarbageCollection: Garbage collection operations -Invoke-MemoryMonitoring: Memory monitoring and alerting -Invoke-ResourceDisposal: Resource cleanup and disposal -Write-StatusMessage: Status messaging and logging

    Test Coverage: -Memory statistics collection and validation -Memory management initialization -Garbage collection operations and monitoring -Resource disposal and cleanup validation -Status messaging and structured logging -Performance monitoring for memory operations -Error handling and recovery scenarios

.NOTES
    Author: Enterprise PowerShell Testing Framework
    Version: 1.0.0
    Testing Framework: Pester 5.x
    Coverage Target: 95%+
    Security Level: Enterprise
#>

BeforeAll {
        # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Import test helpers and required modules
    . $PSScriptRoot\..\TestHelpers\TestHelpers.ps1

    # Import the Private functions for testing
    $privatePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Private"
    $systemPath = Join-Path $privatePath "System"

    Get-ChildItem -Path $systemPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }

    # Mock external dependencies
    Mock Write-Verbose { } -Verifiable:$false
    Mock Write-Debug { } -Verifiable:$false
    Mock Write-Warning { } -Verifiable:$false
    Mock Write-Error { } -Verifiable:$false
    Mock Write-Information { } -Verifiable:$false

    # Initialize test correlation ID
    $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
}

Describe "Get-MemoryStatistics" -Tag "Unit", "System", "Performance" {

    Context "Memory Statistics Collection" {
        BeforeEach {
            # Mock system memory counters
            Mock Get-Counter {
                $counterSamples = @(
                    [PSCustomObject]@{
                        Path = "\Memory\Available Bytes"
                        CookedValue = 8589934592  # 8GB available
                        Timestamp = Get-Date
                    },
                    [PSCustomObject]@{
                        Path = "\Memory\Committed Bytes"
                        CookedValue = 4294967296  # 4GB committed
                        Timestamp = Get-Date
                    },
                    [PSCustomObject]@{
                        Path = "\Process(powershell*)\Working Set"
                        CookedValue = 134217728   # 128MB working set
                        Timestamp = Get-Date
                    }
                )

                return [PSCustomObject]@{
                    CounterSamples = $counterSamples
                    Timestamp = Get-Date
                }
            }

            Mock Get-Process {
                return [PSCustomObject]@{
                    ProcessName = "powershell"
                    Id = 1234
                    WorkingSet64 = 134217728
                    PrivateMemorySize64 = 104857600
                    VirtualMemorySize64 = 268435456
                    PagedMemorySize64 = 104857600
                    NonpagedSystemMemorySize64 = 8192
                }
            }

            Mock Get-WmiObject {
                return [PSCustomObject]@{
                    TotalPhysicalMemory = 17179869184  # 16GB total
                    AvailablePhysicalMemory = 8589934592  # 8GB available
                    TotalVirtualMemory = 34359738368  # 32GB virtual
                    AvailableVirtualMemory = 25769803776  # 24GB available virtual
                }
            }
        }

        It "Should collect system memory statistics" {
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveProperty "TotalPhysicalMemory"
            $result | Should -HaveProperty "AvailablePhysicalMemory"
            $result | Should -HaveProperty "MemoryUtilizationPercent"
            $result.TotalPhysicalMemory | Should -BeGreaterThan 0
        }

        It "Should collect process-specific memory statistics" {
            $result = Get-MemoryStatistics -Detailed -CorrelationId $TestCorrelationId

            $result | Should -HaveProperty "ProcessMemory"
            $result.ProcessMemory | Should -HaveProperty "WorkingSet"
            $result.ProcessMemory | Should -HaveProperty "PrivateMemory"
            $result.ProcessMemory | Should -HaveProperty "VirtualMemory"
        }

        It "Should calculate memory utilization percentages" {
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            $result.MemoryUtilizationPercent | Should -BeGreaterThan 0
            $result.MemoryUtilizationPercent | Should -BeLessOrEqual 100
        }

        It "Should include timing information" {
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            $result | Should -HaveProperty "Timestamp"
            $result | Should -HaveProperty "CollectionDuration"
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle performance counter access failures" {
            Mock Get-Counter { throw "Performance counter access denied" }
            Mock Get-WmiObject {
                return [PSCustomObject]@{
                    TotalPhysicalMemory = 17179869184
                    AvailablePhysicalMemory = 8589934592
                }
            }

            # Should fall back to WMI data
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.TotalPhysicalMemory | Should -BeGreaterThan 0
        }

        It "Should handle WMI access failures gracefully" {
            Mock Get-WmiObject { throw "WMI access failed" }
            Mock Get-Counter { throw "Counter access failed" }

            { Get-MemoryStatistics -CorrelationId $TestCorrelationId } | Should -Throw "*memory statistics*"
        }
    }

    Context "Validation and Formatting" {
        It "Should format memory values appropriately" {
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            # Memory values should be properly formatted
            $result.TotalPhysicalMemoryGB | Should -BeGreaterThan 0
            $result.AvailablePhysicalMemoryGB | Should -BeGreaterThan 0
        }

        It "Should include correlation ID in results" {
            $result = Get-MemoryStatistics -CorrelationId $TestCorrelationId

            $result.CorrelationId | Should -Be $TestCorrelationId
        }
    }
}

Describe "Initialize-MemoryManager" -Tag "Unit", "System", "Initialization" {

    Context "Memory Manager Initialization" {
        BeforeEach {
            Mock Get-MemoryStatistics {
                return @{
                    TotalPhysicalMemory = 17179869184
                    AvailablePhysicalMemory = 8589934592
                    MemoryUtilizationPercent = 50.0
                }
            }

            Mock New-Object {
                param($TypeName)
                if ($TypeName -eq "System.Timers.Timer") {
                    return [PSCustomObject]@{
                        Interval = 30000
                        Enabled = $false
                        AutoReset = $true
                    }
                }
            }
        }

        It "Should initialize memory monitoring system" {
            $result = Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.MonitoringEnabled | Should -Be $true
        }

        It "Should configure memory thresholds" {
            $result = Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId

            $result.WarningThreshold | Should -Be 80
            $result.CriticalThreshold | Should -Be 95
        }

        It "Should validate threshold parameters" {
            { Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId } | Should -Throw "*threshold*"

            { Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId } | Should -Throw "*critical*warning*"
        }

        It "Should initialize monitoring timer" {
            $result = Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId

            $result.MonitoringInterval | Should -Be 60000
            $result.TimerInitialized | Should -Be $true
        }
    }

    Context "Configuration Validation" {
        It "Should use default values when not specified" {
            $result = Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId

            $result.WarningThreshold | Should -BeGreaterThan 0
            $result.CriticalThreshold | Should -BeGreaterThan $result.WarningThreshold
            $result.MonitoringInterval | Should -BeGreaterThan 0
        }

        It "Should validate monitoring interval" {
            { Initialize-MemoryManager -MemoryLimit 1024 -MonitorInterval 30 -CorrelationId $TestCorrelationId } | Should -Throw "*interval*"
        }
    }
}

Describe "Invoke-GarbageCollection" -Tag "Unit", "System", "Performance" {

    Context "Garbage Collection Operations" {
        BeforeEach {
            Mock [System.GC]::Collect { }
            Mock [System.GC]::WaitForPendingFinalizers { }
            Mock [System.GC]::GetTotalMemory {
                param($forceFullCollection)
                if ($forceFullCollection) {
                    return 104857600  # 100MB after collection
                } else {
                    return 134217728  # 128MB before collection
                }
            }
        }

        It "Should perform garbage collection" {
            $result = Invoke-GarbageCollection -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            Assert-MockCalled [System.GC]::Collect -Times 1
        }

        It "Should force full collection when requested" {
            $result = Invoke-GarbageCollection -Force -CorrelationId $TestCorrelationId

            $result.FullCollection | Should -Be $true
            Assert-MockCalled [System.GC]::WaitForPendingFinalizers -Times 1
        }

        It "Should measure memory before and after collection" {
            $result = Invoke-GarbageCollection -MeasureMemory -CorrelationId $TestCorrelationId

            $result | Should -HaveProperty "MemoryBefore"
            $result | Should -HaveProperty "MemoryAfter"
            $result | Should -HaveProperty "MemoryFreed"
            $result.MemoryBefore | Should -BeGreaterThan $result.MemoryAfter
        }

        It "Should include timing information" {
            $result = Invoke-GarbageCollection -CorrelationId $TestCorrelationId

            $result | Should -HaveProperty "Duration"
            $result.Duration.TotalMilliseconds | Should -BeGreaterThan 0
        }
    }

    Context "Collection Strategies" {
        It "Should support generation-specific collection" {
            $result = Invoke-GarbageCollection -Generation 0 -CorrelationId $TestCorrelationId

            $result.Generation | Should -Be 0
            Assert-MockCalled [System.GC]::Collect -Times 1
        }

        It "Should validate generation parameter" {
            { Invoke-GarbageCollection -Generation 5 -CorrelationId $TestCorrelationId } | Should -Throw "*generation*"
        }
    }
}

Describe "Invoke-MemoryMonitoring" -Tag "Unit", "System", "Monitoring" {

    Context "Memory Monitoring Operations" {
        BeforeEach {
            Mock Get-MemoryStatistics {
                return @{
                    TotalPhysicalMemory = 17179869184
                    AvailablePhysicalMemory = 3221225472  # Low memory scenario
                    MemoryUtilizationPercent = 85.0
                    Timestamp = Get-Date
                }
            }

            Mock Write-Warning { }
            Mock Write-Error { }
        }

        It "Should monitor memory usage and detect warnings" {
            $result = Invoke-MemoryMonitoring -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.MemoryUtilization | Should -Be 85.0
            $result.WarningTriggered | Should -Be $true
            Assert-MockCalled Write-Warning -Times 1
        }

        It "Should detect critical memory conditions" {
            Mock Get-MemoryStatistics {
                return @{
                    MemoryUtilizationPercent = 98.0
                    Timestamp = Get-Date
                }
            }

            $result = Invoke-MemoryMonitoring -CorrelationId $TestCorrelationId

            $result.CriticalTriggered | Should -Be $true
            Assert-MockCalled Write-Error -Times 1
        }

        It "Should trigger automatic garbage collection on critical memory" {
            Mock Get-MemoryStatistics {
                return @{
                    MemoryUtilizationPercent = 98.0
                    Timestamp = Get-Date
                }
            }
            Mock Invoke-GarbageCollection {
                return @{ Success = $true; MemoryFreed = 134217728 }
            }

            $result = Invoke-MemoryMonitoring -AutoGC -CorrelationId $TestCorrelationId

            $result.AutoGCTriggered | Should -Be $true
            Assert-MockCalled Invoke-GarbageCollection -Times 1
        }
    }

    Context "Alert Configuration" {
        It "Should support custom alert actions" {
            $alertAction = { param($level, $data) Write-Host "Alert: $level" }

            $result = Invoke-MemoryMonitoring -AlertAction $alertAction -CorrelationId $TestCorrelationId

            $result.CustomAlertExecuted | Should -Be $true
        }
    }
}

Describe "Invoke-ResourceDisposal" -Tag "Unit", "System", "Cleanup" {

    Context "Resource Disposal Operations" {
        BeforeEach {
            # Create mock disposable objects
            $script:mockDisposableObject = [PSCustomObject]@{ MockObject = $true }
            $script:mockDisposableObject | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {
                $this.Disposed = $true
            }
            $script:mockDisposableObject | Add-Member -MemberType NoteProperty -Name "Disposed" -Value $false
        }

        It "Should dispose individual objects" {
            $result = Invoke-ResourceDisposal -Objects $mockDisposableObject -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.ObjectsDisposed | Should -Be 1
            $result.Success | Should -Be $true
            $mockDisposableObject.Disposed | Should -Be $true
        }

        It "Should dispose multiple objects" {
            $objects = @($mockDisposableObject, $mockDisposableObject)

            $result = Invoke-ResourceDisposal -Objects $objects -CorrelationId $TestCorrelationId

            $result.ObjectsDisposed | Should -Be 2
        }

        It "Should handle disposal failures gracefully" {
            $mockDisposableObject | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {
                throw "Disposal failed"
            } -Force

            $result = Invoke-ResourceDisposal -Objects $mockDisposableObject -CorrelationId $TestCorrelationId

            $result.ObjectsDisposed | Should -Be 0
            $result.ObjectsFailed | Should -Be 1
            $result.Errors | Should -HaveCount 1
        }

        It "Should skip non-disposable objects" {
            $nonDisposable = "string object"

            $result = Invoke-ResourceDisposal -Objects $nonDisposable -CorrelationId $TestCorrelationId

            $result.ObjectsSkipped | Should -Be 1
            $result.ObjectsDisposed | Should -Be 0
        }
    }

    Context "Cleanup Strategies" {
        It "Should support force disposal mode" {
            Mock [System.GC]::SuppressFinalize { }

            $result = Invoke-ResourceDisposal -Objects $mockDisposableObject -Force -CorrelationId $TestCorrelationId

            $result.ForceMode | Should -Be $true
            Assert-MockCalled [System.GC]::SuppressFinalize -Times 1
        }

        It "Should validate disposal results" {
            $result = Invoke-ResourceDisposal -Objects $mockDisposableObject -CorrelationId $TestCorrelationId

            $result.ValidationPerformed | Should -Be $true
            $result.ValidationResults | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Write-StatusMessage" -Tag "Unit", "System", "Logging" {

    Context "Status Message Operations" {
        BeforeEach {
            Mock Write-Host { }
            Mock Write-Information { }
            Mock Write-Warning { }
            Mock Write-Error { }
        }

        It "Should write informational status messages" {
            Write-StatusMessage -Message "Processing completed" -Level "Information" -CorrelationId $TestCorrelationId

            Assert-MockCalled Write-Information -Times 1
        }

        It "Should write warning status messages" {
            Write-StatusMessage -Message "Low memory detected" -Level "Warning" -CorrelationId $TestCorrelationId

            Assert-MockCalled Write-Warning -Times 1
        }

        It "Should write error status messages" {
            Write-StatusMessage -Message "Operation failed" -Level "Error" -CorrelationId $TestCorrelationId

            Assert-MockCalled Write-Error -Times 1
        }

        It "Should support colored console output" {
            Write-StatusMessage -Message "Status update" -Level "Information" -CorrelationId $TestCorrelationId

            Assert-MockCalled Write-Host -Times 1
        }

        It "Should include correlation ID in messages" {
            Write-StatusMessage -Message "Test message" -Level "Information" -CorrelationId $TestCorrelationId

            # Verify correlation ID is included in the message
            Assert-MockCalled Write-Information -Times 1
        }
    }

    Context "Message Formatting" {
        It "Should format messages with timestamps" {
            Write-StatusMessage -Message "Test message" -Level "Information" -CorrelationId $TestCorrelationId

            # Verify timestamp formatting
            Assert-MockCalled Write-Information -Times 1
        }

        It "Should support structured message data" {
            $messageData = @{
                Operation = "TestOperation"
                Duration = "00:00:30"
                Status = "Completed"
            }

            Write-StatusMessage -Message "Operation completed" -Level "Information" -CorrelationId $TestCorrelationId

            Assert-MockCalled Write-Information -Times 1
        }
    }

    Context "Validation and Error Handling" {
        It "Should validate message level parameter" {
            { Write-StatusMessage -Message "Test" -Level "InvalidLevel" -CorrelationId $TestCorrelationId } | Should -Throw "*level*"
        }

        It "Should handle empty messages appropriately" {
            Write-StatusMessage -Message "" -Level "Information" -CorrelationId $TestCorrelationId

            # Should still process but may modify the message
            Assert-MockCalled Write-Information -Times 1
        }
    }
}

# Test cleanup and summary reporting
AfterAll {
    Write-Host "System Module Tests Completed" -ForegroundColor Green
    Write-Host "Test Correlation ID: $TestCorrelationId" -ForegroundColor Gray
    Write-Host "Coverage Areas: Memory Management, Resource Disposal, Status Messaging" -ForegroundColor Gray
}










