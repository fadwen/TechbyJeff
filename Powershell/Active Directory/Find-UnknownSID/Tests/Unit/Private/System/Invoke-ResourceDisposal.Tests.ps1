#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for Invoke-ResourceDisposal Private/System functions

.DESCRIPTION
    Comprehensive test suite for resource disposal functionality:
    - Invoke-ResourceDisposal: Resource cleanup and disposal operations

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

# Source the Invoke-ResourceDisposal function
. "$ModulePath\Private\System\Invoke-ResourceDisposal.ps1"

# Import dependencies
. "$ModulePath\Private\Logging\Write-StructuredLog.ps1"

# Create stub functions for .NET static methods that can't be mocked directly
function Invoke-GCCollect { [System.GC]::Collect() }
function Invoke-GCWaitForPendingFinalizers { [System.GC]::WaitForPendingFinalizers() }

# Stub Write-StructuredLog for mocking
if (-not (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue)) {
    function Write-StructuredLog {
        param($Message, $Level, $Component, $CorrelationId)
        # Stub implementation for testing
    }
}

Describe "Invoke-ResourceDisposal" {
    BeforeEach {
        # Mock Write-StructuredLog to prevent output during tests
        Mock Write-StructuredLog {}
        
        # Create stub functions for .NET static methods instead of mocking them directly
        function Invoke-GarbageCollect { [System.GC]::Collect() }
        function Get-MemoryUsage { [System.GC]::GetTotalMemory($false) }
        
        # Mock the stub functions instead
        Mock Invoke-GarbageCollect {}
        Mock Get-MemoryUsage { return 1048576 }
    }
    
    Context "Parameter Validation" {
        It "Should require Resources parameter" {
            { Invoke-ResourceDisposal } | Should Throw
        }
        
        It "Should accept array of objects" {
            $mockResources = @(
                [PSCustomObject]@{ Name = 'Resource1' },
                [PSCustomObject]@{ Name = 'Resource2' }
            )
            
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            { Invoke-ResourceDisposal -Resources $mockResources } | Should Not Throw
        }
        
        It "Should accept single object" {
            $mockResource = [PSCustomObject]@{ Name = 'SingleResource' }
            
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            { Invoke-ResourceDisposal -Resources $mockResource } | Should Not Throw
        }
        
        It "Should accept optional Force parameter" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            { Invoke-ResourceDisposal -Resources $mockResource -Force } | Should Not Throw
        }
        
        It "Should accept optional CorrelationId parameter" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            { Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'test-correlation-id' } | Should Not Throw
        }
        
        It "Should handle empty resource array" {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            { Invoke-ResourceDisposal -Resources @() } | Should Not Throw
        }
        
        It "Should generate GUID when CorrelationId is empty" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock -CommandName '[System.Guid]::NewGuid' -MockWith { 
                return [PSCustomObject]@{ ToString = { return 'generated-guid' } }
            }
            
            { Invoke-ResourceDisposal -Resources $mockResource -CorrelationId '' } | Should Not Throw
        }
    }
    
    Context "IDisposable Resource Disposal" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            
            # Create mock disposable resources
            $script:disposeCallCount = 0
            $script:mockDisposable = [PSCustomObject]@{
                PSTypeName = 'System.IDisposable'
                Name = 'DisposableResource'
                IsDisposed = $false
                Dispose = {
                    $script:disposeCallCount++
                    $this.IsDisposed = $true
                }.GetNewClosure()
            }
            $script:mockDisposable | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $script:disposeCallCount++
                $this.IsDisposed = $true
            } -Force
        }
        
        It "Should dispose IDisposable resources" {
            $result = Invoke-ResourceDisposal -Resources $script:mockDisposable
            
            $result.DisposedCount | Should Be 1
            $result.SkippedCount | Should Be 0
            $result.FailedCount | Should Be 0
        }
        
        It "Should handle multiple disposable resources" {
            $disposableResources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Resource1' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Resource2' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Resource3' }
            )
            
            foreach ($resource in $disposableResources) {
                $resource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            }
            
            $result = Invoke-ResourceDisposal -Resources $disposableResources
            
            $result.DisposedCount | Should Be 3
            $result.TotalResources | Should Be 3
        }
        
        It "Should skip non-disposable resources" {
            $mixedResources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Disposable' },
                [PSCustomObject]@{ Name = 'NonDisposable1' },
                [PSCustomObject]@{ Name = 'NonDisposable2' }
            )
            
            $mixedResources[0] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mixedResources
            
            $result.DisposedCount | Should Be 1
            $result.SkippedCount | Should Be 2
            $result.TotalResources | Should Be 3
        }
        
        It "Should handle disposal failures gracefully" {
            $faultyResource = [PSCustomObject]@{
                PSTypeName = 'System.IDisposable'
                Name = 'FaultyResource'
            }
            $faultyResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                throw "Disposal failed"
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $faultyResource
            
            $result.FailedCount | Should Be 1
            $result.DisposedCount | Should Be 0
            $result.FailedResources.Count | Should Be 1
        }
        
        It "Should continue disposing other resources after failure" {
            $resources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Good1' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Bad' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Good2' }
            )
            
            $resources[0] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            $resources[1] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { throw "Error" } -Force
            $resources[2] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            
            $result = Invoke-ResourceDisposal -Resources $resources
            
            $result.DisposedCount | Should Be 2
            $result.FailedCount | Should Be 1
        }
    }
    
    Context "Stream and Connection Disposal" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
        }
        
        It "Should close stream resources" {
            $mockStream = [PSCustomObject]@{
                PSTypeName = 'System.IO.Stream'
                Name = 'TestStream'
                IsClosed = $false
            }
            $mockStream | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
                $this.IsClosed = $true
            } -Force
            $mockStream | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $this.Close()
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockStream
            
            $result.DisposedCount | Should Be 1
            $result.StreamsClosed | Should Be 1
        }
        
        It "Should close connection resources" {
            $mockConnection = [PSCustomObject]@{
                PSTypeName = 'System.Data.SqlClient.SqlConnection'
                Name = 'TestConnection'
                State = 'Open'
            }
            $mockConnection | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
                $this.State = 'Closed'
            } -Force
            $mockConnection | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $this.Close()
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockConnection
            
            $result.DisposedCount | Should Be 1
            $result.ConnectionsClosed | Should Be 1
        }
        
        It "Should handle file handles" {
            $mockFileHandle = [PSCustomObject]@{
                PSTypeName = 'System.IO.FileStream'
                Name = 'TestFile.txt'
                CanRead = $true
            }
            $mockFileHandle | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
                $this.CanRead = $false
            } -Force
            $mockFileHandle | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $this.Close()
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockFileHandle
            
            $result.DisposedCount | Should Be 1
            $result.FileHandlesClosed | Should Be 1
        }
        
        It "Should handle registry keys" {
            $mockRegistryKey = [PSCustomObject]@{
                PSTypeName = 'Microsoft.Win32.RegistryKey'
                Name = 'TestKey'
                IsOpen = $true
            }
            $mockRegistryKey | Add-Member -MemberType ScriptMethod -Name 'Close' -Value {
                $this.IsOpen = $false
            } -Force
            $mockRegistryKey | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $this.Close()
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockRegistryKey
            
            $result.DisposedCount | Should Be 1
        }
    }
    
    Context "Forced Disposal" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
        }
        
        It "Should force garbage collection when Force parameter is used" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -Force
            
            Assert-MockCalled Invoke-GCCollect -Times 2  # Once normal, once forced
        }
        
        It "Should wait for finalizers multiple times with Force" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -Force
            
            Assert-MockCalled Invoke-GCWaitForPendingFinalizers -Times 2
        }
        
        It "Should attempt disposal retry with Force" {
            $attemptCount = 0
            $mockResource = [PSCustomObject]@{
                PSTypeName = 'System.IDisposable'
                Name = 'RetryResource'
            }
            $mockResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $script:attemptCount++
                if ($script:attemptCount -lt 2) {
                    throw "First attempt fails"
                }
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockResource -Force
            
            $result.DisposedCount | Should Be 1
            $result.RetriedDisposals | Should Be 1
        }
        
        It "Should indicate forced collection in results" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            $result = Invoke-ResourceDisposal -Resources $mockResource -Force
            
            $result.ForcedCollection | Should Be $true
        }
        
        It "Should log forced disposal operations" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -Force -CorrelationId 'force-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Forced resource disposal*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'force-test-id'
            }
        }
    }
    
    Context "Logging Integration" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
        }
        
        It "Should log disposal start" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Starting resource disposal*" -and
                $Level -eq 'Information' -and
                $Component -eq 'ResourceManagement' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log resource counts" {
            $mockResources = @(
                [PSCustomObject]@{ Name = 'Resource1' },
                [PSCustomObject]@{ Name = 'Resource2' },
                [PSCustomObject]@{ Name = 'Resource3' }
            )
            
            Invoke-ResourceDisposal -Resources $mockResources -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Processing 3 resources*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log successful disposals" {
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'DisposableResource' }
            $mockResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            
            Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Successfully disposed*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log disposal failures" {
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'FailingResource' }
            $mockResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                throw "Disposal error"
            } -Force
            
            Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Failed to dispose*" -and
                $Level -eq 'Warning' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should log disposal completion" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Resource disposal completed*" -and
                $Level -eq 'Information' -and
                $CorrelationId -eq 'log-test-id'
            }
        }
        
        It "Should generate correlation ID when not provided" {
            Mock -CommandName '[System.Guid]::NewGuid' -MockWith { 
                return [PSCustomObject]@{ ToString = { return 'auto-generated-guid' } }
            }
            
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $CorrelationId -eq 'auto-generated-guid'
            }
        }
    }
    
    Context "WhatIf Support" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
            Mock Write-Verbose { }
        }
        
        It "Should support ShouldProcess" {
            $command = Get-Command Invoke-ResourceDisposal
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }
        
        It "Should not dispose resources in WhatIf mode" {
            $disposeCallCount = 0
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'TestResource' }
            $mockResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                $script:disposeCallCount++
            } -Force
            
            Invoke-ResourceDisposal -Resources $mockResource -WhatIf
            
            $script:disposeCallCount | Should Be 0
        }
        
        It "Should analyze resources in WhatIf mode" {
            $mockResources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Disposable1' },
                [PSCustomObject]@{ Name = 'NonDisposable' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Disposable2' }
            )
            
            $result = Invoke-ResourceDisposal -Resources $mockResources -WhatIf
            
            $result.WhatIfMode | Should Be $true
            $result.WouldDispose | Should Be 2
            $result.WouldSkip | Should Be 1
            $result.TotalResources | Should Be 3
        }
        
        It "Should log WhatIf simulation" {
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'TestResource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'whatif-test-id' -WhatIf
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Resource disposal simulation*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'whatif-test-id'
            }
        }
        
        It "Should show verbose WhatIf message" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -WhatIf
            
            Assert-MockCalled Write-Verbose -Times 1 -ParameterFilter {
                $Message -like "*WhatIf: Would dispose resources*"
            }
        }
        
        It "Should not perform garbage collection in WhatIf mode" {
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            Invoke-ResourceDisposal -Resources $mockResource -WhatIf
            
            Assert-MockCalled Invoke-GCCollect -Times 0
        }
        
        It "Should include simulation details in results" {
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'TestResource' }
            
            $result = Invoke-ResourceDisposal -Resources $mockResource -WhatIf
            
            $result.WhatIfMode | Should Be $true
            $result.SimulationOnly | Should Be $true
            $result.ActualDisposals | Should Be 0
        }
    }
    
    Context "Error Handling" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
        }
        
        It "Should handle null resources gracefully" {
            { Invoke-ResourceDisposal -Resources $null } | Should Throw
        }
        
        It "Should handle garbage collection failure" {
            Mock Invoke-GarbageCollect {
                throw "GC failed"
            }
            
            $mockResource = [PSCustomObject]@{ Name = 'Resource' }
            
            $result = Invoke-ResourceDisposal -Resources $mockResource -CorrelationId 'gc-error-test'
            
            # Should still complete despite GC failure
            $result.TotalResources | Should Be 1
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Garbage collection failed*" -and
                $Level -eq 'Warning'
            }
        }
        
        It "Should provide meaningful error messages" {
            $mockResource = [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'ErrorResource' }
            $mockResource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                throw "Access denied"
            } -Force
            
            $result = Invoke-ResourceDisposal -Resources $mockResource
            
            $result.FailedResources[0].Error | Should Match "Access denied"
        }
        
        It "Should handle resource identification failure" {
            $corruptResource = [PSCustomObject]@{ }
            
            $result = Invoke-ResourceDisposal -Resources $corruptResource
            
            # Should handle resources without names or types
            $result.TotalResources | Should Be 1
            $result.SkippedCount | Should Be 1
        }
        
        It "Should accumulate all errors for reporting" {
            $resources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Error1' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Error2' }
            )
            
            $resources[0] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { throw "Error 1" } -Force
            $resources[1] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { throw "Error 2" } -Force
            
            $result = Invoke-ResourceDisposal -Resources $resources
            
            $result.FailedCount | Should Be 2
            $result.FailedResources.Count | Should Be 2
        }
    }
    
    Context "Performance and Memory Safety" {
        BeforeEach {
            Mock Write-StructuredLog { }
            Mock Invoke-GCCollect { }
            Mock Invoke-GCWaitForPendingFinalizers { }
        }
        
        It "Should complete disposal within reasonable time" {
            $resources = 1..10 | ForEach-Object {
                [PSCustomObject]@{ Name = "Resource$_" }
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Invoke-ResourceDisposal -Resources $resources
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should handle large resource collections efficiently" {
            $largeResourceSet = 1..100 | ForEach-Object {
                [PSCustomObject]@{ Name = "Resource$_" }
            }
            
            $result = Invoke-ResourceDisposal -Resources $largeResourceSet
            
            $result.TotalResources | Should Be 100
            $result.ProcessingTime.TotalSeconds | Should BeLessThan 5
        }
        
        It "Should not leak memory during disposal" {
            $beforeMemory = [System.GC]::GetTotalMemory($false)
            
            $resources = 1..50 | ForEach-Object {
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = "Resource$_" }
            }
            
            foreach ($resource in $resources) {
                $resource | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            }
            
            Invoke-ResourceDisposal -Resources $resources
            
            $afterMemory = [System.GC]::GetTotalMemory($true)
            $memoryIncrease = ($afterMemory - $beforeMemory) / 1MB
            
            $memoryIncrease | Should BeLessThan 5
        }
        
        It "Should provide comprehensive disposal statistics" {
            $resources = @(
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Disposable1' },
                [PSCustomObject]@{ PSTypeName = 'System.IDisposable'; Name = 'Disposable2' },
                [PSCustomObject]@{ Name = 'NonDisposable' }
            )
            
            $resources[0] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            $resources[1] | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { throw "Error" } -Force
            
            $result = Invoke-ResourceDisposal -Resources $resources
            
            $result.Keys | Should Contain 'TotalResources'
            $result.Keys | Should Contain 'DisposedCount'
            $result.Keys | Should Contain 'SkippedCount'
            $result.Keys | Should Contain 'FailedCount'
            $result.Keys | Should Contain 'ProcessingTime'
            $result.Keys | Should Contain 'FinalGarbageCollection'
        }
    }
}
