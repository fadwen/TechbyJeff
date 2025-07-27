#Requires -Version 5.1
#Requires -Module Pester

$ModuleRoot = Resolve-Path "$PSScriptRoot\..\..\.."

# Import the class file
. "$ModuleRoot\Classes\MemoryManager.ps1"

Describe "MemoryManager Class Tests" -Tag "Unit", "Classes", "MemoryManager" {

    Context "Constructor Tests" {
        It "Should create instance with new 3-argument constructor" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            $manager = [MemoryManager]::new(100, 10, $correlationId)
            
            $manager | Should Not BeNullOrEmpty
            $manager.MaxMemoryMB | Should Be 100
            $manager.CheckInterval | Should Be 10
            $manager.CorrelationId | Should Be $correlationId
            $manager.CheckCounter | Should Be 0
            $manager.PeakMemoryUsage | Should Be 0
            $manager.Disposed | Should Be $false
            $manager.Timer | Should Not BeNullOrEmpty
            $manager.Timer.IsRunning | Should Be $true
        }

        It "Should create instance with legacy 2-argument constructor" {
            $manager = [MemoryManager]::new(200, 20)
            
            $manager | Should Not BeNullOrEmpty
            $manager.MaxMemoryMB | Should Be 200
            $manager.CheckInterval | Should Be 20
            $manager.CorrelationId | Should Not BeNullOrEmpty
            $manager.CorrelationId | Should Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            $manager.CheckCounter | Should Be 0
            $manager.PeakMemoryUsage | Should Be 0
            $manager.Disposed | Should Be $false
            $manager.Timer | Should Not BeNullOrEmpty
            $manager.Timer.IsRunning | Should Be $true
        }

        It "Should generate new CorrelationId when null provided to 3-argument constructor" {
            $manager = [MemoryManager]::new(100, 10, $null)
            
            $manager.CorrelationId | Should Not BeNullOrEmpty
            $manager.CorrelationId | Should Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        }

        It "Should generate new CorrelationId when empty string provided to 3-argument constructor" {
            $manager = [MemoryManager]::new(100, 10, "")
            
            $manager.CorrelationId | Should Not BeNullOrEmpty
            $manager.CorrelationId | Should Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        }
    }

    Context "CheckMemoryUsage Method Tests" {
        BeforeEach {
            $script:testManager = [MemoryManager]::new(50, 3, [System.Guid]::NewGuid().ToString())
        }

        AfterEach {
            if ($script:testManager -and -not $script:testManager.Disposed) {
                $script:testManager.Dispose()
            }
        }

        It "Should increment CheckCounter on each call" {
            $initialCounter = $script:testManager.CheckCounter
            
            $script:testManager.CheckMemoryUsage()
            $script:testManager.CheckCounter | Should Be ($initialCounter + 1)
            
            $script:testManager.CheckMemoryUsage()
            $script:testManager.CheckCounter | Should Be ($initialCounter + 2)
        }

        It "Should reset CheckCounter when reaching CheckInterval" {
            # Set CheckCounter to CheckInterval - 1
            $script:testManager.CheckCounter = $script:testManager.CheckInterval - 1
            
            $script:testManager.CheckMemoryUsage()
            $script:testManager.CheckCounter | Should Be 0
        }

        It "Should track peak memory usage" {
            $initialPeak = $script:testManager.PeakMemoryUsage
            
            # Force multiple memory checks to trigger peak tracking
            for ($i = 0; $i -lt $script:testManager.CheckInterval; $i++) {
                $script:testManager.CheckMemoryUsage()
            }
            
            # Peak should be updated (current memory should be > 0)
            $script:testManager.PeakMemoryUsage | Should BeGreaterThan $initialPeak
        }

        It "Should not perform memory check when disposed" {
            $script:testManager.Dispose()
            $initialCounter = $script:testManager.CheckCounter
            
            $script:testManager.CheckMemoryUsage()
            $script:testManager.CheckCounter | Should Be $initialCounter
        }

        It "Should handle Get-Process errors gracefully" {
            # Create manager that will trigger memory check
            $testManager = [MemoryManager]::new(50, 1, [System.Guid]::NewGuid().ToString())
            
            # Mock Get-Process to throw an error
            Mock Get-Process { throw "Process not found" } -ModuleName $null
            
            # This should not throw an exception
            { $testManager.CheckMemoryUsage() } | Should Not Throw
            
            $testManager.Dispose()
        }

        It "Should perform garbage collection when memory limit exceeded" {
            # Create manager with very low memory limit to trigger GC
            $lowMemoryManager = [MemoryManager]::new(1, 1, [System.Guid]::NewGuid().ToString())
            
            # Force memory check - should trigger GC without throwing
            { $lowMemoryManager.CheckMemoryUsage() } | Should Not Throw
            
            $lowMemoryManager.Dispose()
        }
    }

    Context "GetPeakMemoryUsage Method Tests" {
        BeforeEach {
            $script:testManager = [MemoryManager]::new(100, 5, [System.Guid]::NewGuid().ToString())
        }

        AfterEach {
            if ($script:testManager -and -not $script:testManager.Disposed) {
                $script:testManager.Dispose()
            }
        }

        It "Should return current peak memory usage" {
            $peakUsage = $script:testManager.GetPeakMemoryUsage()
            $peakUsage | Should Be $script:testManager.PeakMemoryUsage
            $peakUsage | Should BeOfType [long]
        }

        It "Should return zero initially" {
            $peakUsage = $script:testManager.GetPeakMemoryUsage()
            $peakUsage | Should Be 0
        }

        It "Should reflect updated peak after memory checks" {
            # Force memory checks to update peak
            for ($i = 0; $i -lt $script:testManager.CheckInterval; $i++) {
                $script:testManager.CheckMemoryUsage()
            }
            
            $peakUsage = $script:testManager.GetPeakMemoryUsage()
            $peakUsage | Should BeGreaterThan 0
        }
    }

    Context "Dispose Method Tests" {
        It "Should properly dispose resources" {
            $manager = [MemoryManager]::new(100, 10, [System.Guid]::NewGuid().ToString())
            
            $manager.Disposed | Should Be $false
            $manager.Timer | Should Not BeNullOrEmpty
            
            $manager.Dispose()
            
            $manager.Disposed | Should Be $true
            $manager.Timer | Should BeNullOrEmpty
        }

        It "Should be safe to call Dispose multiple times" {
            $manager = [MemoryManager]::new(100, 10, [System.Guid]::NewGuid().ToString())
            
            { $manager.Dispose() } | Should Not Throw
            { $manager.Dispose() } | Should Not Throw
            
            $manager.Disposed | Should Be $true
        }

        It "Should stop timer when disposing" {
            $manager = [MemoryManager]::new(100, 10, [System.Guid]::NewGuid().ToString())
            
            $manager.Timer.IsRunning | Should Be $true
            
            $manager.Dispose()
            
            # Timer should be null after dispose
            $manager.Timer | Should BeNullOrEmpty
        }
    }

    Context "Property Validation Tests" {
        BeforeEach {
            $script:testManager = [MemoryManager]::new(150, 25, "test-correlation-id")
        }

        AfterEach {
            if ($script:testManager -and -not $script:testManager.Disposed) {
                $script:testManager.Dispose()
            }
        }

        It "Should have correct property types" {
            $script:testManager.MaxMemoryMB | Should BeOfType [int]
            $script:testManager.CheckInterval | Should BeOfType [int]
            $script:testManager.CheckCounter | Should BeOfType [int]
            $script:testManager.Timer | Should BeOfType [System.Diagnostics.Stopwatch]
            $script:testManager.PeakMemoryUsage | Should BeOfType [long]
            $script:testManager.Disposed | Should BeOfType [bool]
            $script:testManager.CorrelationId | Should BeOfType [string]
        }

        It "Should maintain property values" {
            $script:testManager.MaxMemoryMB | Should Be 150
            $script:testManager.CheckInterval | Should Be 25
            $script:testManager.CorrelationId | Should Be "test-correlation-id"
        }
    }

    Context "Integration Tests" {
        It "Should manage memory through complete lifecycle" {
            $manager = [MemoryManager]::new(100, 2, [System.Guid]::NewGuid().ToString())
            
            # Initial state
            $manager.CheckCounter | Should Be 0
            $manager.PeakMemoryUsage | Should Be 0
            $manager.Disposed | Should Be $false
            
            # Perform memory checks
            $manager.CheckMemoryUsage()
            $manager.CheckCounter | Should Be 1
            
            $manager.CheckMemoryUsage()
            $manager.CheckCounter | Should Be 0  # Should reset after reaching interval
            
            # Get peak usage
            $peakUsage = $manager.GetPeakMemoryUsage()
            $peakUsage | Should BeGreaterThan -1
            
            # Dispose properly
            $manager.Dispose()
            $manager.Disposed | Should Be $true
        }

        It "Should handle edge case with zero interval" {
            # This tests boundary condition
            $manager = [MemoryManager]::new(100, 0, [System.Guid]::NewGuid().ToString())
            
            # Should not cause infinite loop or crash
            { $manager.CheckMemoryUsage() } | Should Not Throw
            
            $manager.Dispose()
        }

        It "Should handle large memory limits" {
            $manager = [MemoryManager]::new([int]::MaxValue, 1, [System.Guid]::NewGuid().ToString())
            
            # Should not trigger memory warnings with max int limit
            { $manager.CheckMemoryUsage() } | Should Not Throw
            
            $manager.Dispose()
        }
    }

    Context "Error Handling Tests" {
        It "Should handle null correlation ID gracefully in constructor" {
            $manager = [MemoryManager]::new(100, 10, $null)
            
            $manager.CorrelationId | Should Not BeNullOrEmpty
            $manager.CorrelationId | Should Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            
            $manager.Dispose()
        }

        It "Should handle negative values in constructor" {
            # PowerShell type system will handle these, but test the behavior
            $manager = [MemoryManager]::new(-100, -10, [System.Guid]::NewGuid().ToString())
            
            $manager.MaxMemoryMB | Should Be -100
            $manager.CheckInterval | Should Be -10
            
            # Should still function without crashing
            { $manager.CheckMemoryUsage() } | Should Not Throw
            
            $manager.Dispose()
        }
    }

    Context "Memory Management Tests" {
        It "Should properly clean up resources on disposal" {
            $manager = [MemoryManager]::new(100, 10, [System.Guid]::NewGuid().ToString())
            
            # Verify timer is running
            $manager.Timer.IsRunning | Should Be $true
            
            # Dispose and verify cleanup
            $manager.Dispose()
            
            # Timer should be null (cleaned up)
            $manager.Timer | Should BeNullOrEmpty
            $manager.Disposed | Should Be $true
        }
    }
}

