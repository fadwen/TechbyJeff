#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for Invoke-MemoryCheck Private/System functions

.DESCRIPTION
    Comprehensive test suite for memory monitoring functionality:
    - Invoke-MemoryCheck: Memory threshold monitoring and alerting

.NOTES
    PowerShell Version: 5.1+ (Windows PowerShell)
    Pester Version: 3.4.x (Legacy compatible)
    Test Framework: Enterprise-grade validation with mocking

    Author: Jeffrey Stuhr
    Last Updated: January 15, 2025
#>

# Import the main script and dependencies
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptPath)))

# Source the MemoryManager class and memory monitoring functions
. "$ModulePath\Classes\MemoryManager.ps1"
. "$ModulePath\Private\System\Invoke-MemoryMonitoring.ps1"

# The file contains: Invoke-MemoryCheck and Test-MemoryThreshold

# Stub Write-StructuredLog for mocking
if (-not (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue)) {
    function Write-StructuredLog {
        param($Message, $Level, $Component, $CorrelationId)
        # Stub implementation for testing
    }
}

# Stub .NET static methods that cannot be mocked directly in Pester 3.4
if (-not (Get-Command 'Get-SystemGCTotalMemory' -ErrorAction SilentlyContinue)) {
    function Get-SystemGCTotalMemory {
        param([bool]$forceFullCollection = $false)
        return [System.GC]::GetTotalMemory($forceFullCollection)
    }
}

if (-not (Get-Command 'Get-SystemGCCollectionCount' -ErrorAction SilentlyContinue)) {
    function Get-SystemGCCollectionCount {
        param([int]$generation)
        return [System.GC]::CollectionCount($generation)
    }
}

if (-not (Get-Command 'Invoke-SystemGCCollect' -ErrorAction SilentlyContinue)) {
    function Invoke-SystemGCCollect {
        param([int]$generation = -1)
        if ($generation -eq -1) {
            [System.GC]::Collect()
        } else {
            [System.GC]::Collect($generation)
        }
    }
}

Describe "Invoke-MemoryCheck" {
    
    Context "Parameter Validation" {
        It "Should require MemoryManager parameter" {
            { Invoke-MemoryCheck } | Should Throw
        }
        
        It "Should accept MemoryManager object" {
            $mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'test-id'
            }
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            
            { Invoke-MemoryCheck -MemoryManager $mockMemoryManager } | Should Not Throw
        }
        
        It "Should accept optional CorrelationId parameter" {
            $mockMemoryManager = [PSCustomObject]@{
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'manager-id'
            }
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            
            { Invoke-MemoryCheck -MemoryManager $mockMemoryManager -CorrelationId 'custom-id' } | Should Not Throw
        }
        
        It "Should use MemoryManager CorrelationId when parameter not provided" {
            $mockMemoryManager = [PSCustomObject]@{
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'manager-correlation-id'
            }
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            
            Invoke-MemoryCheck -MemoryManager $mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $CorrelationId -eq 'manager-correlation-id'
            }
        }
        
        It "Should validate MemoryManager object type" {
            $invalidObject = [PSCustomObject]@{
                SomeProperty = 'SomeValue'
            }
            
            { Invoke-MemoryCheck -MemoryManager $invalidObject } | Should Throw
        }
    }
    
    Context "Memory Threshold Checking" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'threshold-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should detect when memory usage is below threshold" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }  # Below 1024MB threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 500
            $result.ThresholdMB | Should Be 1024
            $result.MemoryStatus | Should Be 'Normal'
        }
        
        It "Should detect when memory usage exceeds threshold" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1500MB }  # Above 1024MB threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.CurrentMemoryMB | Should Be 1500
            $result.ThresholdMB | Should Be 1024
            $result.MemoryStatus | Should Be 'High'
        }
        
        It "Should detect when memory usage is at threshold boundary" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1024MB }  # Exactly at threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 1024
            $result.MemoryStatus | Should Be 'Normal'
        }
        
        It "Should calculate memory usage percentage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 512MB }  # 50% of 1024MB
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryUsagePercent | Should Be 50
        }
        
        It "Should handle very high memory usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 3072MB }  # 300% of threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.MemoryUsagePercent | Should Be 300
            $result.MemoryStatus | Should Be 'Critical'
        }
    }
    
    Context "Memory Status Classification" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1000
                CheckInterval = 25
                CorrelationId = 'status-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should classify low memory usage as Normal" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 250MB }  # 25% of threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
            $result.RiskLevel | Should Be 'Low'
        }
        
        It "Should classify moderate memory usage as Normal" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 700MB }  # 70% of threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
            $result.RiskLevel | Should Be 'Medium'
        }
        
        It "Should classify high memory usage as High" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1200MB }  # 120% of threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'High'
            $result.RiskLevel | Should Be 'High'
        }
        
        It "Should classify critical memory usage as Critical" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 2000MB }  # 200% of threshold
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Critical'
            $result.RiskLevel | Should Be 'Critical'
        }
        
        It "Should provide memory recommendations based on status" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1500MB }  # High usage
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Not BeNullOrEmpty
            $result.Recommendations | Should Contain 'Consider garbage collection'
        }
    }
    
    Context "Monitoring Statistics" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'stats-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should track monitoring timestamp" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            
            $beforeTime = Get-Date
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            $afterTime = Get-Date
            
            $result.MonitoringTime | Should BeGreaterThan $beforeTime
            $result.MonitoringTime | Should BeLessThan $afterTime
        }
        
        It "Should include system memory information" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock -CommandName 'Get-CimInstance' -MockWith {
                return [PSCustomObject]@{
                    TotalPhysicalMemory = 8GB
                    AvailablePhysicalMemory = 4GB
                }
            }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.SystemMemoryTotal | Should Be 8GB
            $result.SystemMemoryAvailable | Should Be 4GB
        }
        
        It "Should calculate memory ratios" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 512MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryToThresholdRatio | Should Be 0.5
            $result.MemoryUsagePercent | Should Be 50
        }
        
        It "Should include generation information" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock -CommandName 'Get-SystemGCCollectionCount' -MockWith {
                param($generation)
                switch ($generation) {
                    0 { return 100 }
                    1 { return 50 }
                    2 { return 10 }
                }
            }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Gen0Collections | Should Be 100
            $result.Gen1Collections | Should Be 50
            $result.Gen2Collections | Should Be 10
        }
    }
    
    Context "Logging Integration" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'logging-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should log monitoring start" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Starting memory monitoring*" -and
                $Level -eq 'Debug' -and
                $Component -eq 'MemoryManagement' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
        
        It "Should log normal memory status" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory usage normal*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
        
        It "Should log high memory warning" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1500MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory threshold exceeded*" -and
                $Level -eq 'Warning' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
        
        It "Should log critical memory alert" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 2500MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Critical memory usage detected*" -and
                $Level -eq 'Error' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
        
        It "Should log memory statistics" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 768MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Current memory: 768 MB*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
        
        It "Should log monitoring completion" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory monitoring completed*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'logging-test-id'
            }
        }
    }
    
    Context "Alert Recommendations" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'alert-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should provide no recommendations for normal memory usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Be @()
        }
        
        It "Should recommend garbage collection for high memory usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1200MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Contain 'Consider garbage collection'
        }
        
        It "Should recommend immediate action for critical memory usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 2500MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Contain 'Immediate garbage collection required'
            $result.Recommendations | Should Contain 'Consider reducing data set size'
        }
        
        It "Should recommend LOH compaction for very high usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 3000MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Contain 'Large Object Heap compaction recommended'
        }
        
        It "Should include threshold adjustment recommendations" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1800MB }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Contain 'Consider increasing memory threshold'
        }
    }
    
    Context "WhatIf Support" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'whatif-test-id'
            }
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            Mock Write-Verbose { }
        }
        
        It "Should support ShouldProcess" {
            $command = Get-Command Invoke-MemoryCheck
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }
        
        It "Should perform monitoring in WhatIf mode" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -WhatIf
            
            $result.CurrentMemoryMB | Should Be 500
            $result.WhatIfMode | Should Be $true
        }
        
        It "Should log WhatIf simulation" {
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -WhatIf
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory monitoring simulation*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'whatif-test-id'
            }
        }
        
        It "Should show verbose WhatIf message" {
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -WhatIf
            
            Assert-MockCalled Write-Verbose -Times 1 -ParameterFilter {
                $Message -like "*WhatIf: Would monitor memory usage*"
            }
        }
        
        It "Should include simulation details in results" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -WhatIf
            
            $result.WhatIfMode | Should Be $true
            $result.SimulationOnly | Should Be $true
        }
    }
    
    Context "Error Handling" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'error-test-id'
            }
            
            Mock Write-StructuredLog { }
        }
        
        It "Should handle memory measurement failure" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith {
                throw "Memory measurement failed"
            }
            
            { Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager } | Should Throw
        }
        
        It "Should log measurement failure" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith {
                throw "Test measurement error"
            }
            
            try {
                Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            }
            catch {
                # Expected to throw
            }
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Failed to monitor memory usage*" -and
                $Level -eq 'Error' -and
                $CorrelationId -eq 'error-test-id'
            }
        }
        
        It "Should handle null MemoryManager gracefully" {
            { Invoke-MemoryCheck -MemoryManager $null } | Should Throw
        }
        
        It "Should handle system information failure gracefully" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock -CommandName 'Get-CimInstance' -MockWith {
                throw "WMI access denied"
            }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            # Should still complete monitoring despite system info failure
            $result.CurrentMemoryMB | Should Be 500
            $result.SystemMemoryTotal | Should Be 0
        }
        
        It "Should provide meaningful error messages" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith {
                throw "Insufficient memory"
            }
            
            try {
                Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            }
            catch {
                $_.Exception.Message | Should Match "Memory monitoring failed"
            }
        }
    }
    
    Context "Performance and Memory Safety" {
        BeforeEach {
            $script:mockMemoryManager = [PSCustomObject]@{
                PSTypeName = 'MemoryManager'
                MaxMemoryMB = 1024
                CheckInterval = 25
                CorrelationId = 'perf-test-id'
            }
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
        }
        
        It "Should complete monitoring within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
        }
        
        It "Should not consume excessive memory during monitoring" {
            $beforeMemory = Get-SystemGCTotalMemory($false)
            
            1..10 | ForEach-Object { 
                Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager 
            }
            
            $afterMemory = Get-SystemGCTotalMemory($true)
            $memoryIncrease = ($afterMemory - $beforeMemory) / 1MB
            
            $memoryIncrease | Should BeLessThan 5
        }
        
        It "Should handle high-frequency monitoring" {
            $results = 1..20 | ForEach-Object {
                Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            }
            
            $results | Should HaveCount 20
            $results | ForEach-Object { $_.CurrentMemoryMB | Should Be 500 }
        }
        
        It "Should provide comprehensive monitoring results" {
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Keys | Should Contain 'CurrentMemoryMB'
            $result.Keys | Should Contain 'ThresholdMB'
            $result.Keys | Should Contain 'ThresholdExceeded'
            $result.Keys | Should Contain 'MemoryStatus'
            $result.Keys | Should Contain 'MemoryUsagePercent'
            $result.Keys | Should Contain 'RiskLevel'
            $result.Keys | Should Contain 'Recommendations'
            $result.Keys | Should Contain 'MonitoringTime'
        }
    }
}
