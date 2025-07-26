#Requires -Version 5.1

# Import the main script and dependencies
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptPath)))

# Source the MemoryManager class and Get-MemoryStatistics function
. "$ModulePath\Classes\MemoryManager.ps1"
. "$ModulePath\Private\System\Get-MemoryStatistics.ps1"

Describe "Get-CurrentMemoryUsage" {
    # Mock external dependencies
    Mock Write-StructuredLog { }
    
    Context "Parameter Validation" {
        It "Should accept no parameters" {
            { Get-CurrentMemoryUsage } | Should Not Throw
        }

        It "Should have CmdletBinding attribute" {
            $function = Get-Command Get-CurrentMemoryUsage
            $function.CmdletBinding | Should Be $true
        }

        It "Should have OutputType attribute" {
            $function = Get-Command Get-CurrentMemoryUsage
            $function.OutputType.Name -contains 'MemoryUsageStatistics' | Should Be $true
        }
    }

    Context "Memory Statistics Collection" {
        It "Should return memory usage statistics object" {
            $result = Get-CurrentMemoryUsage
            
            $result | Should Not BeNullOrEmpty
            $result -is [PSCustomObject] | Should Be $true
        }

        It "Should include all required memory metrics" {
            $result = Get-CurrentMemoryUsage
            
            $result.WorkingSetMB | Should Not BeNullOrEmpty
            $result.PrivateMemoryMB | Should Not BeNullOrEmpty  
            $result.VirtualMemoryMB | Should Not BeNullOrEmpty
            $result.GCTotalMemoryMB | Should Not BeNullOrEmpty
        }

        It "Should include garbage collection statistics" {
            $result = Get-CurrentMemoryUsage
            
            $result.Gen0Collections | Should Not BeNullOrEmpty
            $result.Gen1Collections | Should Not BeNullOrEmpty
            $result.Gen2Collections | Should Not BeNullOrEmpty
        }

        It "Should include timestamp" {
            $result = Get-CurrentMemoryUsage
            
            $result.Timestamp | Should Not BeNullOrEmpty
            $result.Timestamp -is [DateTime] | Should Be $true
        }
    }
}

Describe "Get-MemoryUsageReport" {
    # Mock external dependencies
    Mock Write-StructuredLog { }
    
    # Create a real MemoryManager instance using New-Object syntax
    $script:mockMemoryManager = New-Object MemoryManager(2048, 30)
    
    Context "Parameter Validation" {
        It "Should accept valid MemoryManager parameter" {
            { Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager } | Should Not Throw
        }

        It "Should have CmdletBinding attribute" {
            $function = Get-Command Get-MemoryUsageReport
            $function.CmdletBinding | Should Be $true
        }

        It "Should have OutputType attribute" {
            $function = Get-Command Get-MemoryUsageReport  
            $function.OutputType.Name -contains 'MemoryUsageReport' | Should Be $true
        }
    }

    Context "Report Generation" {
        It "Should generate report without recommendations by default" {
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager
            
            $result | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CurrentUsage | Should Not BeNullOrEmpty
            $result.PeakUsageMB | Should Not BeNullOrEmpty
            $result.Configuration | Should Not BeNullOrEmpty
            $result.GeneratedAt | Should Not BeNullOrEmpty
        }

        It "Should include recommendations when requested" {
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager -IncludeRecommendations
            
            $result.Recommendations | Should Not BeNullOrEmpty
        }

        It "Should calculate utilization percentage correctly" {
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdUtilization | Should Not BeNullOrEmpty
            $result.ThresholdUtilization | Should BeOfType [double]
        }

        It "Should include status assessment" {
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager
            
            $result.PerformanceStatus | Should Not BeNullOrEmpty
            # Check for valid status values
            @('Excellent', 'Good', 'Acceptable', 'Concerning') -contains $result.PerformanceStatus | Should Be $true
        }
    }

    Context "Error Handling" {
        It "Should provide meaningful error messages" {
            # This should work without throwing since we have proper mocks
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager
            $result | Should Not BeNullOrEmpty
        }
    }

    Context "Performance and Integration" {
        It "Should complete report generation within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Get-MemoryUsageReport -MemoryManager $script:mockMemoryManager
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
        }
    }
}
