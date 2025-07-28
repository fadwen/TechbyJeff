#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for Invoke-GarbageCollection Private/System functionality

.DESCRIPTION
    Comprehensive test suite for garbage collection functionality:
    - Invoke-GarbageCollection: Memory cleanup and garbage collection operations

.NOTES
    PowerShell Version: 5.1+ (Windows PowerShell)
    Pester Version: 3.4.x (Legacy compatible)
    Test Framework: Enterprise-grade validation with mocking

    Author: Jeffrey Stuhr
    Last Updated: January 15, 2025
#>

# Source the Invoke-GarbageCollection function
$functionPath = Join-Path $PSScriptRoot "..\..\..\..\Private\System\Invoke-GarbageCollection.ps1"
if (Test-Path $functionPath) {
    . $functionPath
} else {
    throw "Could not find function file at: $functionPath"
}

# Stub Write-StructuredLog for mocking
if (-not (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue)) {
    function Write-StructuredLog {
        param($Message, $Level, $Component, $CorrelationId)
        # Stub implementation for testing
    }
}

# Stub .NET static methods that can't be mocked in Pester 3.4
if (-not (Get-Command Invoke-GCCollect -ErrorAction SilentlyContinue)) {
    function Invoke-GCCollect { [System.GC]::Collect() }
}
if (-not (Get-Command Invoke-GCWaitForPendingFinalizers -ErrorAction SilentlyContinue)) {
    function Invoke-GCWaitForPendingFinalizers { [System.GC]::WaitForPendingFinalizers() }
}
if (-not (Get-Command Get-GCTotalMemory -ErrorAction SilentlyContinue)) {
    function Get-GCTotalMemory { param($forceCollection) return [System.GC]::GetTotalMemory($forceCollection) }
}

Describe "Invoke-GarbageCollection" {
    
    Context "Parameter Validation" {
        It "Should accept optional Force parameter" {
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection } | Should Not Throw
            { Invoke-GarbageCollection -Force } | Should Not Throw
        }
        
        It "Should accept optional CorrelationId parameter" {
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Invoke-GarbageCollection -CorrelationId $correlationId } | Should Not Throw
        }
    }
    
    Context "Core Functionality" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Get-GCTotalMemory { return 1000000 }
        }
        
        It "Should perform basic garbage collection" {
            $result = Invoke-GarbageCollection
            
            Assert-MockCalled Invoke-GCCollect -Exactly 2  # Called twice in full collection
            Assert-MockCalled Invoke-GCWaitForPendingFinalizers -Exactly 1
            $result.Success | Should Be $true
        }
        
        It "Should return PSCustomObject with expected properties" {
            $result = Invoke-GarbageCollection
            
            $result | Should Not BeNullOrEmpty
            $result | Should BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name -contains "Success" | Should Be $true
            $result.PSObject.Properties.Name -contains "MemoryBefore" | Should Be $true
            $result.PSObject.Properties.Name -contains "MemoryAfter" | Should Be $true
            $result.PSObject.Properties.Name -contains "CorrelationId" | Should Be $true
        }
        
        It "Should accept CorrelationId parameter" {
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection -Force -CorrelationId 'test-id' } | Should Not Throw
        }
    }
    
    Context "Basic Garbage Collection" {
        BeforeEach {
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Get-GCTotalMemory { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1000MB }
            }
            Mock Write-StructuredLog { }
        }
        
        It "Should call GC.Collect() without force by default" {
            Invoke-GarbageCollection
            
            Assert-MockCalled Invoke-GCCollect -Times 1
        }
        
        It "Should call GC.Collect() with force when specified" {
            Invoke-GarbageCollection -Force
            
            Assert-MockCalled Invoke-GCCollect -Times 1
        }
        
        It "Should wait for pending finalizers" {
            Invoke-GarbageCollection
            
            Assert-MockCalled Invoke-GCWaitForPendingFinalizers -Times 1
        }
        
        It "Should perform final collection after finalizers" {
            Invoke-GarbageCollection
            
            # Should be called twice: initial collection + final collection
            Assert-MockCalled Invoke-GCCollect -Times 2
        }
        
        It "Should return memory statistics" {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Get-GCTotalMemory {
                param([bool]$ForceFullCollection)
                if ($ForceFullCollection) { return 800MB } else { return 1000MB }
            }
            
            $result = Invoke-GarbageCollection
            
            $result | Should Not BeNullOrEmpty
            $result.MemoryBefore | Should Be 1000
            $result.MemoryAfter | Should Be 800
        }
    }
    
    Context "Error Handling" {
        It "Should handle GC.Collect() failure" {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect {
                throw "Garbage collection failed"
            }
            
            { Invoke-GarbageCollection } | Should Throw
        }
        
        It "Should log collection failure" {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect {
                throw "Test collection error"
            }
            
            try {
                Invoke-GarbageCollection -CorrelationId 'error-test-id'
            }
            catch {
                # Expected to throw
            }
            
            Assert-MockCalled Write-StructuredLog -Times 1
        }
        
        It "Should handle memory measurement failure" {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Get-GCTotalMemory {
                throw "Memory measurement failed"
            }
            
            { Invoke-GarbageCollection } | Should Throw "Memory measurement failed"
        }
    }
}
