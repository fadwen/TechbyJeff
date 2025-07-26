#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for Invoke-GarbageCollection Private/Syste        It "Should accept CorrelationId parameter" {
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection -CorrelationId 'test-correlation-id' } | Should Not Throw
        }
        
        It "Should generate GUID when CorrelationId is empty" {
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Write-StructuredLog { }
            Mock -CommandName '[System.Guid]::NewGuid' -MockWith { 
                return [PSCustomObject]@{ ToString = { return 'generated-guid' } }
            }
            
            { Invoke-GarbageCollection -CorrelationId '' } | Should Not Throw
        }SCRIPTION
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
if (-not (Get-Command Wait-GCPendingFinalizers -ErrorAction SilentlyContinue)) {
    function Wait-GCPendingFinalizers { [System.GC]::WaitForPendingFinalizers() }
}
if (-not (Get-Command Get-GCTotalMemory -ErrorAction SilentlyContinue)) {
    function Get-GCTotalMemory { param($forceCollection) return [System.GC]::GetTotalMemory($forceCollection) }
}
if (-not (Get-Command Invoke-GCCollectGeneration -ErrorAction SilentlyContinue)) {
    function Invoke-GCCollectGeneration { param($generation) [System.GC]::Collect($generation) }
}

Describe "Invoke-GarbageCollection" {
    
    Context "Parameter Validation" {
        It "Should accept optional Force parameter" {
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection } | Should Not Throw
            { Invoke-GarbageCollection -Force } | Should Not Throw
        }
        
        It "Should accept optional CompactLOH parameter" {
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection -CompactLOH } | Should Not Throw
        }
        
        It "Should accept optional CorrelationId parameter" {
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Write-StructuredLog { }
            
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Invoke-GarbageCollection -CorrelationId $correlationId } | Should Not Throw
        }
    }
    
    Context "Core Functionality" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Wait-GCPendingFinalizers { }
            Mock Get-GCTotalMemory { return 1000000 }
        }
        
        It "Should perform basic garbage collection" {
            $result = Invoke-GarbageCollection
            
            Assert-MockCalled Invoke-GCCollect -Exactly 1
            Assert-MockCalled Wait-GCPendingFinalizers -Exactly 1
            $result.Success | Should Be $true
        }
        
        It "Should return PSCustomObject with expected properties" {
            $result = Invoke-GarbageCollection
            
            $result | Should Not BeNullOrEmpty
            $result | Should BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name -contains "Success" | Should Be $true
            $result.PSObject.Properties.Name -contains "MemoryBefore" | Should Be $true
        }
        
        It "Should accept CorrelationId parameter" {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock Write-StructuredLog { }
            
            { Invoke-GarbageCollection -Force -CompactLOH -CorrelationId 'test-id' } | Should Not Throw
        }
        
        It "Should generate GUID when CorrelationId is empty" {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock Write-StructuredLog { }
            Mock -CommandName '[System.Guid]::NewGuid' -MockWith { 
                return [PSCustomObject]@{ ToString = { return 'generated-guid' } }
            }
            
            { Invoke-GarbageCollection -CorrelationId '' } | Should Not Throw
        }
    }
    
    Context "Basic Garbage Collection" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1000MB }
            }
            Mock Write-StructuredLog { }
        }
        
        It "Should call GC.Collect() without force by default" {
            Invoke-GarbageCollection
            
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 1 -ParameterFilter { $args.Count -eq 0 }
        }
        
        It "Should call GC.Collect() with force when specified" {
            Invoke-GarbageCollection -Force
            
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 1 -ParameterFilter { $args.Count -gt 0 }
        }
        
        It "Should wait for pending finalizers" {
            Invoke-GarbageCollection
            
            Assert-MockCalled -CommandName '[System.GC]::WaitForPendingFinalizers' -Times 1
        }
        
        It "Should perform final collection after finalizers" {
            Invoke-GarbageCollection
            
            # Should be called twice: initial collection + final collection
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 2
        }
        
        It "Should return memory statistics" {
            $result = Invoke-GarbageCollection
            
            $result | Should Not BeNullOrEmpty
            $result.MemoryBeforeCollection | Should Be (1000MB)
            $result.MemoryAfterCollection | Should Be (500MB)
            $result.MemoryFreed | Should Be (500MB)
        }
        
        It "Should include collection completion status" {
            $result = Invoke-GarbageCollection
            
            $result.CollectionCompleted | Should Be $true
            $result.FinalizersProcessed | Should Be $true
        }
    }
    
    Context "Large Object Heap Compaction" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { return 1000MB }
            Mock Write-StructuredLog { }
            
            # Mock LOH compaction setting
            $script:LOHCompactionModeSet = $false
            Mock -CommandName '[System.Runtime.GCSettings]::LargeObjectHeapCompactionMode' -MockWith {
                param($value)
                if ($value -ne $null) {
                    $script:LOHCompactionModeSet = $true
                    return $value
                }
                return 'Default'
            }
        }
        
        It "Should not set LOH compaction by default" {
            Invoke-GarbageCollection
            
            $script:LOHCompactionModeSet | Should Be $false
        }
        
        It "Should set LOH compaction when requested" {
            Invoke-GarbageCollection -CompactLOH
            
            $script:LOHCompactionModeSet | Should Be $true
        }
        
        It "Should indicate LOH compaction in results" {
            $result = Invoke-GarbageCollection -CompactLOH
            
            $result.LOHCompactionRequested | Should Be $true
        }
        
        It "Should not indicate LOH compaction when not requested" {
            $result = Invoke-GarbageCollection
            
            $result.LOHCompactionRequested | Should Be $false
        }
        
        It "Should force collection when LOH compaction is requested" {
            Invoke-GarbageCollection -CompactLOH
            
            # LOH compaction requires forced collection
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 1 -ParameterFilter { $args.Count -gt 0 }
        }
        
        It "Should log LOH compaction activity" {
            Invoke-GarbageCollection -CompactLOH -CorrelationId 'loh-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Large Object Heap compaction enabled*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'loh-test-id'
            }
        }
    }
    
    Context "Memory Pressure Handling" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock Write-StructuredLog { }
            
            # Mock memory pressure methods
            Mock -CommandName '[System.GC]::AddMemoryPressure' -MockWith { }
            Mock -CommandName '[System.GC]::RemoveMemoryPressure' -MockWith { }
        }
        
        It "Should handle high memory usage (>1GB)" {
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1500MB }
            }
            
            $result = Invoke-GarbageCollection -Force
            
            $result.MemoryPressureDetected | Should Be $true
            $result.ForcedCollection | Should Be $true
        }
        
        It "Should handle normal memory usage (<1GB)" {
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 400MB } else { return 800MB }
            }
            
            $result = Invoke-GarbageCollection
            
            $result.MemoryPressureDetected | Should Be $false
        }
        
        It "Should log memory pressure detection" {
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1500MB }
            }
            
            Invoke-GarbageCollection -CorrelationId 'pressure-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*High memory usage detected*" -and
                $Level -eq 'Warning' -and
                $CorrelationId -eq 'pressure-test-id'
            }
        }
        
        It "Should perform aggressive collection under memory pressure" {
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1500MB }
            }
            
            Invoke-GarbageCollection
            
            # Should perform additional collections under pressure
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 3
        }
    }
    
    Context "Logging Integration" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1000MB }
            }
            Mock Write-StructuredLog { }
        }
        
        It "Should log garbage collection start" {
            Invoke-GarbageCollection -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Starting garbage collection*" -and
                $Level -eq 'Information' -and
                $Component -eq 'MemoryManagement' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log memory statistics" {
            Invoke-GarbageCollection -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory before collection*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log collection completion" {
            Invoke-GarbageCollection -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Garbage collection completed*" -and
                $Level -eq 'Information' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log memory freed details" {
            Invoke-GarbageCollection -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory freed*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should generate correlation ID when not provided" {
            Mock -CommandName '[System.Guid]::NewGuid' -MockWith { 
                return [PSCustomObject]@{ ToString = { return 'auto-generated-guid' } }
            }
            
            Invoke-GarbageCollection
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $CorrelationId -eq 'auto-generated-guid'
            }
        }
    }
    
    Context "WhatIf Support" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { return 1000MB }
            Mock Write-StructuredLog { }
            Mock Write-Verbose { }
        }
        
        It "Should support ShouldProcess" {
            $command = Get-Command Invoke-GarbageCollection
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }
        
        It "Should not perform actual collection in WhatIf mode" {
            Invoke-GarbageCollection -WhatIf
            
            Assert-MockCalled -CommandName '[System.GC]::Collect' -Times 0
        }
        
        It "Should still gather memory statistics in WhatIf mode" {
            $result = Invoke-GarbageCollection -WhatIf
            
            $result.MemoryBeforeCollection | Should Be (1000MB)
            $result.WhatIfMode | Should Be $true
        }
        
        It "Should log WhatIf simulation" {
            Invoke-GarbageCollection -CorrelationId 'whatif-test-id' -WhatIf
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Garbage collection simulation*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'whatif-test-id'
            }
        }
        
        It "Should show verbose WhatIf message" {
            Invoke-GarbageCollection -WhatIf
            
            Assert-MockCalled Write-Verbose -Times 1 -ParameterFilter {
                $Message -like "*WhatIf: Would perform garbage collection*"
            }
        }
        
        It "Should indicate simulation mode in results" {
            $result = Invoke-GarbageCollection -WhatIf
            
            $result.WhatIfMode | Should Be $true
            $result.CollectionCompleted | Should Be $false
        }
    }
    
    Context "Error Handling" {
        BeforeEach {
            Mock Write-StructuredLog { }
        }
        
        It "Should handle GC.Collect() failure" {
            Mock -CommandName '[System.GC]::Collect' -MockWith {
                throw "Garbage collection failed"
            }
            
            { Invoke-GarbageCollection } | Should Throw
        }
        
        It "Should log collection failure" {
            Mock -CommandName '[System.GC]::Collect' -MockWith {
                throw "Test collection error"
            }
            
            try {
                Invoke-GarbageCollection -CorrelationId 'error-test-id'
            }
            catch {
                # Expected to throw
            }
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Garbage collection failed*" -and
                $Level -eq 'Error' -and
                $CorrelationId -eq 'error-test-id'
            }
        }
        
        It "Should handle memory measurement failure" {
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith {
                throw "Memory measurement failed"
            }
            
            try {
                Invoke-GarbageCollection
            }
            catch {
                $_.Exception.Message | Should Match "Failed to complete garbage collection"
            }
        }
        
        It "Should handle LOH compaction failure gracefully" {
            Mock -CommandName '[System.Runtime.GCSettings]::LargeObjectHeapCompactionMode' -MockWith {
                throw "LOH compaction not supported"
            }
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { return 1000MB }
            
            $result = Invoke-GarbageCollection -CompactLOH -CorrelationId 'loh-error-test'
            
            # Should still complete collection despite LOH failure
            $result.CollectionCompleted | Should Be $true
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*LOH compaction failed*" -and
                $Level -eq 'Warning'
            }
        }
        
        It "Should provide meaningful error messages" {
            Mock -CommandName '[System.GC]::Collect' -MockWith {
                throw "Out of memory"
            }
            
            try {
                Invoke-GarbageCollection
            }
            catch {
                $_.Exception.Message | Should Match "Failed to complete garbage collection"
            }
        }
    }
    
    Context "Performance and Memory Safety" {
        BeforeEach {
            Mock -CommandName '[System.GC]::Collect' -MockWith { }
            Mock -CommandName '[System.GC]::WaitForPendingFinalizers' -MockWith { }
            Mock -CommandName '[System.GC]::GetTotalMemory' -MockWith { 
                param($forceFullCollection)
                if ($forceFullCollection) { return 500MB } else { return 1000MB }
            }
            Mock Write-StructuredLog { }
        }
        
        It "Should complete garbage collection within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Invoke-GarbageCollection
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should handle multiple concurrent collections" {
            $results = 1..3 | ForEach-Object {
                Invoke-GarbageCollection -CorrelationId "concurrent-$_"
            }
            
            $results | Should HaveCount 3
            $results | ForEach-Object { $_.CollectionCompleted | Should Be $true }
        }
        
        It "Should measure timing accurately" {
            $result = Invoke-GarbageCollection
            
            $result.ExecutionTime | Should Not BeNullOrEmpty
            $result.ExecutionTime.TotalMilliseconds | Should BeGreaterThan 0
        }
        
        It "Should provide detailed statistics" {
            $result = Invoke-GarbageCollection -Force -CompactLOH
            
            $result.Keys | Should Contain 'MemoryBeforeCollection'
            $result.Keys | Should Contain 'MemoryAfterCollection' 
            $result.Keys | Should Contain 'MemoryFreed'
            $result.Keys | Should Contain 'CollectionCompleted'
            $result.Keys | Should Contain 'FinalizersProcessed'
            $result.Keys | Should Contain 'LOHCompactionRequested'
            $result.Keys | Should Contain 'ForcedCollection'
            $result.Keys | Should Contain 'ExecutionTime'
        }
    }
}
