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

Describe "Invoke-MemoryCheck" {
    
    BeforeEach {
        # Create a real MemoryManager object for testing with proper constructor
        $script:mockMemoryManager = [MemoryManager]::new(1024, 25, 'test-correlation-id')
        # Add the additional properties that Invoke-MemoryCheck expects
        $script:mockMemoryManager | Add-Member -NotePropertyName 'WarningThresholdPercent' -NotePropertyValue 80 -Force
        $script:mockMemoryManager | Add-Member -NotePropertyName 'CriticalThresholdPercent' -NotePropertyValue 95 -Force
        $script:mockMemoryManager | Add-Member -NotePropertyName 'MonitoringEnabled' -NotePropertyValue $true -Force
    }
    
    Context "Parameter Validation" {
        
        It "Should require MemoryManager parameter" {
            # Use reflection to check parameter definition instead of calling function
            $command = Get-Command Invoke-MemoryCheck
            $memoryManagerParam = $command.Parameters['MemoryManager']
            $memoryManagerParam.Attributes | Where-Object { $_ -is [Parameter] } | ForEach-Object { $_.Mandatory | Should Be $true }
        }
        
        It "Should accept MemoryManager object" {
            $mockMemoryManager = [MemoryManager]::new(1024, 25, 'test-id')
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock -CommandName 'Get-SystemGCCollectionCount' -MockWith { return 100 }
            Mock Write-StructuredLog { }
            
            { Invoke-MemoryCheck -MemoryManager $mockMemoryManager } | Should Not Throw
        }
        
        It "Should accept optional CorrelationId parameter" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            
            { Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager -CorrelationId 'test-123' } | Should Not Throw
        }
        
        It "Should use MemoryManager CorrelationId when parameter not provided" {
            $script:mockMemoryManager.CorrelationId = 'manager-correlation-id'
            
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            $result.CorrelationId | Should Be 'manager-correlation-id'
        }
        
        It "Should validate MemoryManager object type" {
            $invalidManager = @{ MaxMemoryMB = 1024 }  # Hashtable instead of MemoryManager
            
            { Invoke-MemoryCheck -MemoryManager $invalidManager } | Should Throw
        }
    }
    
    Context "Memory Threshold Checking" {
        
        It "Should detect when memory usage is below threshold" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 500MB }  # Below 1024MB threshold
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false
            $result.CurrentMemoryMB | Should Be 500
            $result.MaxMemoryMB | Should Be 1024
            $result.MemoryStatus | Should Be 'Normal'
        }
        
        It "Should detect when memory usage exceeds threshold" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1200MB }  # Above 1024MB threshold
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.CurrentMemoryMB | Should Be 1200
            $result.MaxMemoryMB | Should Be 1024
            $result.MemoryStatus | Should Be 'Critical'
        }
        
        It "Should detect when memory usage is at threshold boundary" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 1024MB }  # Exactly at threshold
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $false  # Should be false for exact match
            $result.CurrentMemoryMB | Should Be 1024
        }
        
        It "Should calculate memory usage percentage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 512MB }  # 50% of 1024MB threshold
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryUsagePercent | Should Be 50
            $result.MemoryStatus | Should Be 'Normal'
        }
        
        It "Should handle very high memory usage" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 2048MB }  # 200% of threshold
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.ThresholdExceeded | Should Be $true
            $result.MemoryUsagePercent | Should Be 200
            $result.MemoryStatus | Should Be 'Critical'
        }
    }
    
    Context "Memory Status Classification" {
        
        It "Should classify low memory usage as Normal" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 400MB }  # ~39% of 1024MB
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
            $result.MemoryUsagePercent | Should BeLessThan 80
        }
        
        It "Should classify moderate memory usage as Normal" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 700MB }  # ~68% of 1024MB
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Normal'
            $result.MemoryUsagePercent | Should BeLessThan 80
        }
        
        It "Should classify high memory usage as Critical" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 850MB }  # ~83% of 1024MB (above 75% high threshold)
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'High'
            $result.MemoryUsagePercent | Should BeGreaterThan 75
        }
        
        It "Should classify critical memory usage as Critical" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 980MB }  # ~96% of 1024MB (above 95% critical)
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.MemoryStatus | Should Be 'Critical'
            $result.MemoryUsagePercent | Should BeGreaterThan 95
        }
        
        It "Should provide memory recommendations based on status" {
            Mock -CommandName 'Get-SystemGCTotalMemory' -MockWith { return 900MB }  # High level (87% of 1024MB)
            Mock Write-StructuredLog { }
            
            $result = Invoke-MemoryCheck -MemoryManager $script:mockMemoryManager
            
            $result.Recommendations | Should Not BeNullOrEmpty
            ($result.Recommendations -contains 'Consider running garbage collection') | Should Be $true
        }
    }
}
