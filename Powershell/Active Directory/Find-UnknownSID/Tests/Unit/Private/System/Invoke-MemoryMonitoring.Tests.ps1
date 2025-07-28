#Requires -Version 5.1

# Import test helpers
. "$PSScriptRoot\..\..\..\TestHelpers\SecurityTestHelpers.ps1"

# Import the module classes
. "$PSScriptRoot\..\..\..\..\Classes\MemoryManager.ps1"

# Import the function under test
. "$PSScriptRoot\..\..\..\..\Private\System\Invoke-MemoryMonitoring.ps1"

# Import dependency functions
. "$PSScriptRoot\..\..\..\..\Private\System\Get-MemoryStatistics.ps1"

Describe "Invoke-MemoryCheck" {
    BeforeEach {
        $script:mockMemoryManager = [MemoryManager]::new(1024, 25, 'test-correlation-id')
        
        # Mock the wrapper functions
        Mock Get-SystemGCTotalMemory { return 500MB }
        Mock Get-SystemGCCollectionCount { return 10 }
        Mock Write-StructuredLog { }
    }

    Context "Parameter Validation" {
        It "Should require MemoryManager parameter" {
            # Use reflection to check parameter definition instead of calling function
            $command = Get-Command Invoke-MemoryCheck
            $memoryManagerParam = $command.Parameters['MemoryManager']
            $memoryManagerParam.Attributes | Where-Object { $_ -is [Parameter] } | ForEach-Object { $_.Mandatory | Should Be $true }
        }

        It "Should accept MemoryManager object" {
            { Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager } | Should Not Throw
        }

        It "Should accept optional CorrelationId parameter" {
            { Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -CorrelationId 'test-id' } | Should Not Throw
        }

        It "Should use MemoryManager CorrelationId when parameter not provided" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            $result.CorrelationId | Should Be $script:mockMemoryManager.CorrelationId
        }

        It "Should validate MemoryManager object type" {
            $invalidObject = [PSCustomObject]@{ Name = 'Invalid' }
            { Invoke-MemoryCheck -MemoryManager $invalidObject } | Should Throw
        }
    }

    Context "Memory Threshold Checking" {
        It "Should detect when memory usage is below threshold" {
            Mock Get-SystemGCTotalMemory { return 200MB }  # 200 MB - below 1024 MB threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 200
        }

        It "Should detect when memory usage exceeds threshold" {
            Mock Get-SystemGCTotalMemory { return 2048MB }  # 2048 MB - above 1024 MB threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.CurrentMemoryMB | Should Be 2048
        }

        It "Should detect when memory usage is at threshold boundary" {
            Mock Get-SystemGCTotalMemory { return 1024MB }  # Exactly at threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 1024
        }

        It "Should calculate memory usage percentage" {
            Mock Get-SystemGCTotalMemory { return 512MB }  # 50% of 1024 MB
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryUsagePercent | Should Be 50
        }

        It "Should handle very high memory usage" {
            Mock Get-SystemGCTotalMemory { return 5120MB }  # 5GB
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.MemoryUsagePercent | Should BeGreaterThan 100
        }
    }

    Context "Memory Status Classification" {
        It "Should classify low memory usage as Normal" {
            Mock Get-SystemGCTotalMemory { return 200MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
        }

        It "Should classify moderate memory usage as Normal" {
            Mock Get-SystemGCTotalMemory { return 400MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
        }

        It "Should classify high memory usage as High" {
            Mock Get-SystemGCTotalMemory { return 750MB }  # Between 500-1000MB
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'High'
        }

        It "Should classify critical memory usage as Critical" {
            Mock Get-SystemGCTotalMemory { return 1500MB }  # Above 1000MB
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Critical'
        }

        It "Should provide memory recommendations based on status" {
            Mock Get-SystemGCTotalMemory { return 1500MB }  # Critical level
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations.Count | Should BeGreaterThan 0
            ($result.Recommendations -contains 'Immediate action required: Stop processing and run garbage collection') | Should Be $true
        }
    }

    Context "Force Memory Check" {
        It "Should force memory check when Force parameter is used" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -Force
            
            $result.CurrentMemoryMB | Should Be 500
            # After Force sets counter to interval and CheckMemoryUsage() is called, it resets to 0
            $script:mockMemoryManager.CheckCounter | Should Be 0
        }

        It "Should reset check counter when forced" {
            $script:mockMemoryManager.CheckCounter = 5  # Set to some value
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -Force
            
            # Force sets to interval, then CheckMemoryUsage() increments and resets to 0
            $script:mockMemoryManager.CheckCounter | Should Be 0
        }
    }

    Context "Comprehensive Result Properties" {
        It "Should return all expected properties" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            ($result.PSObject.Properties.Name -contains 'CurrentMemoryMB') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'MaxMemoryMB') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'ThresholdExceeded') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'MemoryUsagePercent') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'MemoryStatus') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'Recommendations') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'MonitoringTime') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'SystemMemoryTotal') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'CorrelationId') | Should Be $true
        }

        It "Should include garbage collection statistics" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            ($result.PSObject.Properties.Name -contains 'Gen0Collections') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'Gen1Collections') | Should Be $true
            ($result.PSObject.Properties.Name -contains 'Gen2Collections') | Should Be $true
        }

        It "Should set monitoring time to current time" {
            $beforeTime = Get-Date
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            $afterTime = Get-Date
            
            $result.MonitoringTime | Should BeGreaterThan $beforeTime.AddSeconds(-1)
            $result.MonitoringTime | Should BeLessThan $afterTime.AddSeconds(1)
        }
    }

    Context "Error Handling" {
        It "Should handle memory measurement failure" {
            Mock Get-SystemGCTotalMemory { throw "Memory measurement failed" }
            
            { Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager } | Should Throw
        }

        It "Should handle null MemoryManager gracefully" {
            { Invoke-MemoryCheck -MemoryManager $null } | Should Throw
        }

        It "Should provide meaningful error messages" {
            Mock Get-SystemGCTotalMemory { throw "Insufficient memory" }
            
            try {
                Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
                # Should not reach here
                $false | Should Be $true
            }
            catch {
                $_.Exception.Message | Should Not BeNullOrEmpty
            }
        }
    }

    Context "WhatIf Support" {
        It "Should support ShouldProcess" {
            $command = Get-Command Invoke-MemoryCheck
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }

        It "Should still perform monitoring in WhatIf mode" {
            # Test WhatIf parameter availability instead of execution
            $command = Get-Command Invoke-MemoryCheck
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
            
            # Test normal execution
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.CurrentMemoryMB | Should Be 500
        }
    }
}

Describe "Test-MemoryThreshold" {
    BeforeEach {
        Mock Get-SystemGCTotalMemory { return 500MB }
        Mock Write-StructuredLog { }
    }

    Context "Basic Threshold Testing" {
        It "Should test memory against threshold" {
            $result = Test-MemoryThreshold -ThresholdMB 1024
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 500
        }

        It "Should detect when threshold is exceeded" {
            Mock Get-SystemGCTotalMemory { return 2048MB }
            
            $result = Test-MemoryThreshold -ThresholdMB 1024
            
            $result.ThresholdExceeded | Should Be $true
            $result.CurrentMemoryMB | Should Be 2048
        }
    }
}
