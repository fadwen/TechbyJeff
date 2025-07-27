#Requires -Version 5.1

# Import the class
. $PSScriptRoot\..\..\..\Classes\ProcessingStatistics.ps1

Describe "ProcessingStatistics Class Tests" {
    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $stats = [ProcessingStatistics]::new()
            $stats | Should Not BeNullOrEmpty
            $stats.GetType().Name | Should Be 'ProcessingStatistics'
        }
        
        It "Should set StartTime to current time" {
            $beforeCreate = Get-Date
            Start-Sleep -Milliseconds 50
            $stats = [ProcessingStatistics]::new()
            $afterCreate = Get-Date
            
            $stats.StartTime | Should BeGreaterThan $beforeCreate
            $stats.StartTime | Should BeLessThan $afterCreate.AddMilliseconds(1)
        }
        
        It "Should initialize counters to zero" {
            $stats = [ProcessingStatistics]::new()
            
            $stats.TotalObjects | Should Be 0
            $stats.ProcessedObjects | Should Be 0
            $stats.OrphanedSIDsFound | Should Be 0
            $stats.ProcessingErrors | Should Be 0
            $stats.CriticalErrors | Should Be 0
        }
        
        It "Should leave EndTime as default DateTime initially" {
            $stats = [ProcessingStatistics]::new()
            
            # Default DateTime is 1/1/0001 12:00:00 AM
            $stats.EndTime | Should Be ([DateTime]::MinValue)
        }
        
        It "Should leave Duration as default TimeSpan initially" {
            $stats = [ProcessingStatistics]::new()
            
            $stats.Duration | Should Be ([TimeSpan]::Zero)
        }
        
        It "Should initialize ObjectsPerSecond to zero" {
            $stats = [ProcessingStatistics]::new()
            
            $stats.ObjectsPerSecond | Should Be 0
        }
        
        It "Should initialize PeakMemoryUsageMB to zero" {
            $stats = [ProcessingStatistics]::new()
            
            $stats.PeakMemoryUsageMB | Should Be 0
        }
    }
    
    Context "Property Tests" {
        BeforeEach {
            $script:testStats = [ProcessingStatistics]::new()
            # Set properties to test their types
            $script:testStats.TotalObjects = 100
            $script:testStats.ProcessedObjects = 50
            $script:testStats.OrphanedSIDsFound = 25
            $script:testStats.ProcessingErrors = 5
            $script:testStats.CriticalErrors = 2
            $script:testStats.ObjectsPerSecond = 10.5
            $script:testStats.PeakMemoryUsageMB = 256
        }
        
        It "Should have correct property types" {
            $script:testStats.TotalObjects | Should BeOfType [int]
            $script:testStats.ProcessedObjects | Should BeOfType [int]
            $script:testStats.OrphanedSIDsFound | Should BeOfType [int]
            $script:testStats.ProcessingErrors | Should BeOfType [int]
            $script:testStats.CriticalErrors | Should BeOfType [int]
            $script:testStats.StartTime | Should BeOfType [DateTime]
            $script:testStats.EndTime | Should BeOfType [DateTime]
            $script:testStats.Duration | Should BeOfType [TimeSpan]
            $script:testStats.ObjectsPerSecond | Should BeOfType [double]
            $script:testStats.PeakMemoryUsageMB | Should BeOfType [long]
        }
        
        It "Should allow setting TotalObjects property" {
            $script:testStats.TotalObjects = 100
            $script:testStats.TotalObjects | Should Be 100
        }
        
        It "Should allow setting ProcessedObjects property" {
            $script:testStats.ProcessedObjects = 75
            $script:testStats.ProcessedObjects | Should Be 75
        }
        
        It "Should allow setting OrphanedSIDsFound property" {
            $script:testStats.OrphanedSIDsFound = 15
            $script:testStats.OrphanedSIDsFound | Should Be 15
        }
        
        It "Should allow setting ProcessingErrors property" {
            $script:testStats.ProcessingErrors = 5
            $script:testStats.ProcessingErrors | Should Be 5
        }
        
        It "Should allow setting CriticalErrors property" {
            $script:testStats.CriticalErrors = 3
            $script:testStats.CriticalErrors | Should Be 3
        }
        
        It "Should allow setting StartTime property" {
            $newTime = (Get-Date).AddHours(-1)
            $script:testStats.StartTime = $newTime
            $script:testStats.StartTime | Should Be $newTime
        }
        
        It "Should allow setting EndTime property" {
            $newTime = Get-Date
            $script:testStats.EndTime = $newTime
            $script:testStats.EndTime | Should Be $newTime
        }
        
        It "Should allow setting Duration property" {
            $newDuration = [TimeSpan]::FromMinutes(5)
            $script:testStats.Duration = $newDuration
            $script:testStats.Duration | Should Be $newDuration
        }
        
        It "Should allow setting ObjectsPerSecond property" {
            $script:testStats.ObjectsPerSecond = 15.7
            $script:testStats.ObjectsPerSecond | Should Be 15.7
        }
        
        It "Should allow setting PeakMemoryUsageMB property" {
            $script:testStats.PeakMemoryUsageMB = 512
            $script:testStats.PeakMemoryUsageMB | Should Be 512
        }
    }
    
    Context "Complete Method Tests" {
        BeforeEach {
            $script:testStats = [ProcessingStatistics]::new()
            $script:testStats.ProcessedObjects = 100
        }
        
        It "Should complete processing and set EndTime" {
            $beforeComplete = Get-Date
            Start-Sleep -Milliseconds 50
            $script:testStats.Complete()
            $afterComplete = Get-Date
            
            $script:testStats.EndTime | Should BeGreaterThan $beforeComplete
            $script:testStats.EndTime | Should BeLessThan $afterComplete.AddMilliseconds(1)
        }
        
        It "Should calculate Duration" {
            Start-Sleep -Milliseconds 100
            $script:testStats.Complete()
            
            $script:testStats.Duration | Should BeOfType [TimeSpan]
            $script:testStats.Duration.TotalMilliseconds | Should BeGreaterThan 90
        }
        
        It "Should calculate ObjectsPerSecond when Duration > 0" {
            $script:testStats.ProcessedObjects = 200
            Start-Sleep -Milliseconds 100
            $script:testStats.Complete()
            
            $script:testStats.ObjectsPerSecond | Should BeGreaterThan 0
            $script:testStats.ObjectsPerSecond | Should BeOfType [double]
        }
        
        It "Should handle zero duration gracefully" {
            # Force same start and end time
            $now = Get-Date
            $script:testStats.StartTime = $now
            $script:testStats.EndTime = $now
            $script:testStats.Duration = [TimeSpan]::Zero
            
            # Test that Complete doesn't throw
            { $script:testStats.Complete() } | Should Not Throw
        }
        
        It "Should update EndTime on subsequent calls" {
            $script:testStats.Complete()
            $firstEndTime = $script:testStats.EndTime
            
            Start-Sleep -Milliseconds 50
            $script:testStats.Complete()
            
            $script:testStats.EndTime | Should BeGreaterThan $firstEndTime
        }
    }
    
    Context "Integration Tests" {
        It "Should track complete processing workflow" {
            $stats = [ProcessingStatistics]::new()
            
            # Simulate processing workflow
            $stats.TotalObjects = 500
            $stats.ProcessedObjects = 495
            $stats.OrphanedSIDsFound = 25
            $stats.ProcessingErrors = 5
            $stats.CriticalErrors = 2
            $stats.PeakMemoryUsageMB = 128
            
            Start-Sleep -Milliseconds 100
            $stats.Complete()
            
            $stats.EndTime | Should BeGreaterThan $stats.StartTime
            $stats.Duration | Should BeOfType [TimeSpan]
            $stats.Duration.TotalMilliseconds | Should BeGreaterThan 90
            $stats.ObjectsPerSecond | Should BeGreaterThan 0
        }
        
        It "Should maintain consistent state across multiple operations" {
            $stats = [ProcessingStatistics]::new()
            
            # Set initial values
            $stats.TotalObjects = 100
            $stats.ProcessedObjects = 95
            $stats.OrphanedSIDsFound = 10
            $initialTotalObjects = $stats.TotalObjects
            $initialProcessedObjects = $stats.ProcessedObjects
            $initialOrphanedSIDsFound = $stats.OrphanedSIDsFound
            
            # Complete processing
            $stats.Complete()
            
            # Values should remain consistent
            $stats.TotalObjects | Should Be $initialTotalObjects
            $stats.ProcessedObjects | Should Be $initialProcessedObjects
            $stats.OrphanedSIDsFound | Should Be $initialOrphanedSIDsFound
        }
        
        It "Should support multiple instances with independent state" {
            $stats1 = [ProcessingStatistics]::new()
            $stats2 = [ProcessingStatistics]::new()
            
            # Set different values for each instance
            $stats1.TotalObjects = 100
            $stats1.ProcessedObjects = 95
            $stats1.OrphanedSIDsFound = 10
            
            $stats2.TotalObjects = 200
            $stats2.ProcessedObjects = 190
            $stats2.OrphanedSIDsFound = 25
            
            # Complete only one instance
            $stats1.Complete()
            
            # Verify independent state
            $stats1.EndTime | Should Not Be ([DateTime]::MinValue)
            $stats2.EndTime | Should Be ([DateTime]::MinValue)
            
            $stats1.TotalObjects | Should Be 100
            $stats2.TotalObjects | Should Be 200
            
            $stats1.OrphanedSIDsFound | Should Be 10
            $stats2.OrphanedSIDsFound | Should Be 25
        }
    }
    
    Context "Edge Cases and Error Handling" {
        BeforeEach {
            $script:testStats = [ProcessingStatistics]::new()
        }
        
        It "Should handle negative counter values" {
            $script:testStats.TotalObjects = -10
            $script:testStats.ProcessingErrors = -5
            
            $script:testStats.TotalObjects | Should Be -10
            $script:testStats.ProcessingErrors | Should Be -5
        }
        
        It "Should handle very large counter values" {
            $largeValue = [int]::MaxValue
            $script:testStats.TotalObjects = $largeValue
            
            $script:testStats.TotalObjects | Should Be $largeValue
        }
        
        It "Should handle very large memory values" {
            $largeMemory = [long]::MaxValue
            $script:testStats.PeakMemoryUsageMB = $largeMemory
            
            $script:testStats.PeakMemoryUsageMB | Should Be $largeMemory
        }
        
        It "Should handle EndTime in the past relative to StartTime" {
            $script:testStats.StartTime = Get-Date
            $script:testStats.EndTime = (Get-Date).AddHours(-1)
            
            # Duration calculation should handle negative values
            $script:testStats.Duration = $script:testStats.EndTime - $script:testStats.StartTime
            $script:testStats.Duration.TotalHours | Should BeLessThan 0
        }
        
        It "Should handle zero ProcessedObjects in Complete method" {
            $script:testStats.ProcessedObjects = 0
            
            { $script:testStats.Complete() } | Should Not Throw
            $script:testStats.ObjectsPerSecond | Should Be 0
        }
    }
    
    Context "Performance Tests" {
        It "Should create instances quickly" {
            $iterations = 1000
            $elapsedTime = Measure-Command {
                1..$iterations | ForEach-Object {
                    $stats = [ProcessingStatistics]::new()
                }
            }
            
            # Should create 1000 instances in under 1 second
            $elapsedTime.TotalSeconds | Should BeLessThan 1.0
        }
        
        It "Should perform Complete operations quickly" {
            $script:testStats.ProcessedObjects = 1000
            
            $elapsedTime = Measure-Command {
                1..100 | ForEach-Object {
                    $script:testStats.Complete()
                }
            }
            
            # Should perform 100 Complete operations in under 100ms
            $elapsedTime.TotalMilliseconds | Should BeLessThan 100
        }
    }
}
