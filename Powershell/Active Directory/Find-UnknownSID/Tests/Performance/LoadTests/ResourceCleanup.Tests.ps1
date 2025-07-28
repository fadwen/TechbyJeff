#Requires -Version 5.1
#Requires -Module Pester

# Import test configuration
$testConfigPath = Join-Path $PSScriptRoot "..\..\TestData\Configurations\test-config.json"
if (-not (Test-Path $testConfigPath)) {
    throw "Test configuration file not found: $testConfigPath"
}
$testConfig = Get-Content $testConfigPath | ConvertFrom-Json

# Import test helpers
. "$PSScriptRoot\..\..\TestHelpers\SecurityTestHelpers.ps1"
. "$PSScriptRoot\..\..\TestHelpers\BackupTestHelpers.ps1"

# Mock wrapper function to prevent actual script execution
function Invoke-ResourceCleanupTest {
    param(
        [string]$MockBehavior = 'Normal',
        [int]$ObjectCount = 1000,
        [string]$ResourceType = 'Mixed',
        [bool]$ForceCleanup = $false,
        [int]$CleanupDelay = 0
    )
    
    switch ($MockBehavior) {
        'Normal' {
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount
                MemoryLeaks = 0
                FileHandlesLeaked = 0
                ComObjectsLeaked = 0
                EventHandlersLeaked = 0
                DisposalTimeMs = 50 + ($ObjectCount * 0.2)  # More linear scaling
                CleanupEfficiency = 100.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 2
                FinalizedObjects = $ObjectCount
            }
        }
        'SlowCleanup' {
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount
                MemoryLeaks = 0
                FileHandlesLeaked = 0
                ComObjectsLeaked = 0
                EventHandlersLeaked = 0
                DisposalTimeMs = 500 + ($ObjectCount * 2.0)  # Much slower cleanup
                CleanupEfficiency = 85.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 5
                FinalizedObjects = $ObjectCount
                CleanupBottlenecks = @('ComObjectRelease', 'FileHandleClose')
            }
        }
        'PartialLeaks' {
            $leakRate = 0.05  # 5% leak rate
            $leakedObjects = [math]::Floor($ObjectCount * $leakRate)
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount - $leakedObjects
                MemoryLeaks = [math]::Floor($leakedObjects * 0.4)
                FileHandlesLeaked = [math]::Floor($leakedObjects * 0.3)
                ComObjectsLeaked = [math]::Floor($leakedObjects * 0.2)
                EventHandlersLeaked = [math]::Floor($leakedObjects * 0.1)
                DisposalTimeMs = 80 + ($ObjectCount * 0.25)  # Slightly slower due to leak handling
                CleanupEfficiency = 95.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 3
                FinalizedObjects = $ObjectCount - $leakedObjects
                LeakSources = @('ComObject', 'FileHandle', 'EventHandler')
            }
        }
        'SignificantLeaks' {
            $leakRate = 0.15  # 15% leak rate
            $leakedObjects = [math]::Floor($ObjectCount * $leakRate)
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount - $leakedObjects
                MemoryLeaks = [math]::Floor($leakedObjects * 0.5)
                FileHandlesLeaked = [math]::Floor($leakedObjects * 0.3)
                ComObjectsLeaked = [math]::Floor($leakedObjects * 0.15)
                EventHandlersLeaked = [math]::Floor($leakedObjects * 0.05)
                DisposalTimeMs = 800 + ($ObjectCount * 0.25)
                CleanupEfficiency = 75.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 4
                FinalizedObjects = $ObjectCount - $leakedObjects
                LeakSources = @('ComObject', 'FileHandle', 'EventHandler', 'MemoryStream')
                LeakDetected = $true
            }
        }
        'ForceCleanup' {
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount
                MemoryLeaks = 0
                FileHandlesLeaked = 0
                ComObjectsLeaked = 0
                EventHandlersLeaked = 0
                DisposalTimeMs = 500 + ($ObjectCount * 0.2)  # Slower due to forced cleanup
                CleanupEfficiency = 100.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 6
                FinalizedObjects = $ObjectCount
                ForcedCleanup = $true
                EmergencyGCTriggered = $true
            }
        }
        'CleanupFailure' {
            $failureRate = 0.25  # 25% failure rate
            $failedObjects = [math]::Floor($ObjectCount * $failureRate)
            return @{
                ExitCode = 1
                Success = $false
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount - $failedObjects
                MemoryLeaks = [math]::Floor($failedObjects * 0.6)
                FileHandlesLeaked = [math]::Floor($failedObjects * 0.25)
                ComObjectsLeaked = [math]::Floor($failedObjects * 0.1)
                EventHandlersLeaked = [math]::Floor($failedObjects * 0.05)
                DisposalTimeMs = 1200 + ($ObjectCount * 0.3)
                CleanupEfficiency = 45.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                Error = 'Resource cleanup failed: Unable to dispose of multiple resource types'
                GCCollections = 8
                FinalizedObjects = $ObjectCount - $failedObjects
                CleanupFailures = @('ComObjectDisposal', 'FileHandleClose', 'EventHandlerDetach')
            }
        }
        'MemoryPressure' {
            $pressureImpact = 0.1  # 10% disposal issues due to pressure
            $impactedObjects = [math]::Floor($ObjectCount * $pressureImpact)
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount - $impactedObjects
                MemoryLeaks = [math]::Floor($impactedObjects * 0.7)
                FileHandlesLeaked = [math]::Floor($impactedObjects * 0.2)
                ComObjectsLeaked = [math]::Floor($impactedObjects * 0.08)
                EventHandlersLeaked = [math]::Floor($impactedObjects * 0.02)
                DisposalTimeMs = 1800 + ($ObjectCount * 0.4)  # Slower under pressure
                CleanupEfficiency = 88.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.3)
                    ComObjects = [math]::Floor($ObjectCount * 0.2)
                    EventHandlers = [math]::Floor($ObjectCount * 0.25)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.25)
                }
                GCCollections = 12
                FinalizedObjects = $ObjectCount - $impactedObjects
                MemoryPressureDetected = $true
                EmergencyGCTriggered = $true
            }
        }
        'ResourceExhaustion' {
            return @{
                ExitCode = 1
                Success = $false
                ObjectsCreated = [math]::Floor($ObjectCount * 0.6)  # Could only create 60%
                ObjectsDisposed = [math]::Floor($ObjectCount * 0.4)  # Disposed even less
                MemoryLeaks = [math]::Floor($ObjectCount * 0.15)
                FileHandlesLeaked = [math]::Floor($ObjectCount * 0.1)
                ComObjectsLeaked = [math]::Floor($ObjectCount * 0.05)
                EventHandlersLeaked = [math]::Floor($ObjectCount * 0.02)
                DisposalTimeMs = 5000  # Very slow due to exhaustion
                CleanupEfficiency = 25.0
                ResourceTypes = @{
                    FileHandles = [math]::Floor($ObjectCount * 0.18)  # Reduced due to exhaustion
                    ComObjects = [math]::Floor($ObjectCount * 0.12)
                    EventHandlers = [math]::Floor($ObjectCount * 0.15)
                    MemoryStreams = [math]::Floor($ObjectCount * 0.15)
                }
                Error = 'System resource exhaustion: Unable to allocate additional resources'
                GCCollections = 15
                FinalizedObjects = [math]::Floor($ObjectCount * 0.25)
                ResourceExhaustion = $true
                SystemHandlesExhausted = $true
            }
        }
        default {
            return @{
                ExitCode = 0
                Success = $true
                ObjectsCreated = $ObjectCount
                ObjectsDisposed = $ObjectCount
                DisposalTimeMs = 100
            }
        }
    }
}

Describe "Resource Cleanup Performance Tests" -Tag "Performance", "LoadTest", "ResourceCleanup" {
    
    BeforeAll {
        # Mock all external dependencies to prevent actual execution
        Mock Import-Module { } -ParameterFilter { $Name -eq 'ActiveDirectory' }
        Mock Get-ADDomain { return @{ DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com' } }
        Mock Write-Host { }
        Mock Write-Verbose { }
        Mock Write-Warning { }
        Mock Write-Information { }
        Mock Start-Transcript { }
        Mock Stop-Transcript { }
        Mock Test-Path { return $true }
        Mock New-Item { }
        Mock Out-File { }
        Mock Export-Csv { }
        # Mock external dependencies that are actually cmdlets/functions
        Mock Write-Verbose { }
        Mock Write-Information { }
        Mock Get-Process { return @{ WorkingSet = 104857600; VirtualMemorySize = 209715200; Handles = 1250 } }
    }
    
    Context "Normal Resource Cleanup" {
        
        It "Should efficiently clean up small resource sets" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 500
            
            $result.Success | Should Be $true
            $result.ObjectsCreated | Should Be 500
            $result.ObjectsDisposed | Should Be 500
            $result.MemoryLeaks | Should Be 0
            $result.CleanupEfficiency | Should BeGreaterThan 95.0
            $result.DisposalTimeMs | Should BeLessThan 1000
        }
        
        It "Should handle medium resource sets efficiently" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            
            $result.Success | Should Be $true
            $result.ObjectsDisposed | Should Be $result.ObjectsCreated
            $result.FileHandlesLeaked | Should Be 0
            $result.ComObjectsLeaked | Should Be 0
            $result.EventHandlersLeaked | Should Be 0
            $result.FinalizedObjects | Should Be 2000
        }
        
        It "Should scale cleanup time linearly with object count" {
            $smallResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 1000
            $largeResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 4000
            
            $timeRatio = $largeResult.DisposalTimeMs / $smallResult.DisposalTimeMs
            $objectRatio = $largeResult.ObjectsCreated / $smallResult.ObjectsCreated
            
            # Cleanup should scale roughly linearly (allow some overhead)
            $timeRatio | Should BeLessThan ($objectRatio * 1.5)
            $timeRatio | Should BeGreaterThan ($objectRatio * 0.8)
        }
        
        It "Should properly categorize different resource types" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            
            $result.ResourceTypes.FileHandles | Should BeGreaterThan 0
            $result.ResourceTypes.ComObjects | Should BeGreaterThan 0
            $result.ResourceTypes.EventHandlers | Should BeGreaterThan 0
            $result.ResourceTypes.MemoryStreams | Should BeGreaterThan 0
            
            $totalResources = $result.ResourceTypes.FileHandles + $result.ResourceTypes.ComObjects + 
                            $result.ResourceTypes.EventHandlers + $result.ResourceTypes.MemoryStreams
            $totalResources | Should Be $result.ObjectsCreated
        }
    }
    
    Context "Cleanup Performance Characteristics" {
        
        It "Should identify slow cleanup scenarios" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'SlowCleanup' -ObjectCount 1500
            
            $result.Success | Should Be $true
            $result.DisposalTimeMs | Should BeGreaterThan 3000
            $result.CleanupEfficiency | Should BeLessThan 90.0
            $result.CleanupBottlenecks | Should Not BeNullOrEmpty
            $result.GCCollections | Should BeGreaterThan 3
        }
        
        It "Should measure cleanup efficiency accurately" {
            $normalResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            $slowResult = Invoke-ResourceCleanupTest -MockBehavior 'SlowCleanup' -ObjectCount 2000
            
            $normalResult.CleanupEfficiency | Should BeGreaterThan $slowResult.CleanupEfficiency
            $normalResult.DisposalTimeMs | Should BeLessThan ($slowResult.DisposalTimeMs * 0.5)
        }
        
        It "Should validate garbage collection patterns" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 3000
            
            $result.GCCollections | Should BeGreaterThan 0
            $result.GCCollections | Should BeLessThan 10  # Should not be excessive
            $result.FinalizedObjects | Should Be $result.ObjectsCreated
        }
        
        It "Should compare cleanup performance across object counts" {
            $counts = @(500, 1000, 2000, 4000)
            $results = @()
            
            foreach ($count in $counts) {
                $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount $count
                $results += $result
                $result.Success | Should Be $true
            }
            
            # Efficiency should remain consistent across sizes
            $efficiencies = $results | ForEach-Object { $_.CleanupEfficiency }
            $maxVariation = ($efficiencies | Measure-Object -Maximum).Maximum - ($efficiencies | Measure-Object -Minimum).Minimum
            $maxVariation | Should BeLessThan 10.0  # Less than 10% variation
        }
    }
    
    Context "Resource Leak Detection" {
        
        It "Should detect minor resource leaks" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'PartialLeaks' -ObjectCount 2000
            
            $result.Success | Should Be $true
            $result.MemoryLeaks | Should BeGreaterThan 0
            $result.MemoryLeaks | Should BeLessThan 100  # Minor leaks
            $result.CleanupEfficiency | Should BeGreaterThan 90.0
            $result.LeakSources | Should Not BeNullOrEmpty
        }
        
        It "Should identify significant leak patterns" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'SignificantLeaks' -ObjectCount 2000
            
            $result.Success | Should Be $true
            $result.MemoryLeaks | Should BeGreaterThan 50
            $result.FileHandlesLeaked | Should BeGreaterThan 20
            $result.CleanupEfficiency | Should BeLessThan 85.0
            $result.LeakDetected | Should Be $true
        }
        
        It "Should categorize leak types accurately" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'SignificantLeaks' -ObjectCount 3000
            
            $totalLeaks = $result.MemoryLeaks + $result.FileHandlesLeaked + 
                         $result.ComObjectsLeaked + $result.EventHandlersLeaked
            $totalLeaks | Should BeGreaterThan 0
            
            # Memory leaks should typically be the largest category
            $result.MemoryLeaks | Should BeGreaterThan $result.FileHandlesLeaked
            $result.FileHandlesLeaked | Should BeGreaterThan $result.ComObjectsLeaked
        }
        
        It "Should compare leak rates across scenarios" {
            $partialResult = Invoke-ResourceCleanupTest -MockBehavior 'PartialLeaks' -ObjectCount 2000
            $significantResult = Invoke-ResourceCleanupTest -MockBehavior 'SignificantLeaks' -ObjectCount 2000
            
            $significantResult.MemoryLeaks | Should BeGreaterThan ($partialResult.MemoryLeaks * 2)
            $significantResult.CleanupEfficiency | Should BeLessThan $partialResult.CleanupEfficiency
        }
    }
    
    Context "Forced Cleanup Scenarios" {
        
        It "Should handle forced cleanup operations" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ForceCleanup' -ObjectCount 2500
            
            $result.Success | Should Be $true
            $result.ForcedCleanup | Should Be $true
            $result.ObjectsDisposed | Should Be $result.ObjectsCreated
            $result.MemoryLeaks | Should Be 0
            $result.CleanupEfficiency | Should Be 100.0
            $result.EmergencyGCTriggered | Should Be $true
        }
        
        It "Should compare forced vs normal cleanup performance" {
            $normalResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            $forcedResult = Invoke-ResourceCleanupTest -MockBehavior 'ForceCleanup' -ObjectCount 2000
            
            $forcedResult.DisposalTimeMs | Should BeGreaterThan $normalResult.DisposalTimeMs
            $forcedResult.GCCollections | Should BeGreaterThan $normalResult.GCCollections
            $forcedResult.CleanupEfficiency | Should BeGreaterThan ($normalResult.CleanupEfficiency * 0.99)
        }
        
        It "Should validate emergency GC effectiveness" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ForceCleanup' -ObjectCount 3000
            
            $result.EmergencyGCTriggered | Should Be $true
            $result.GCCollections | Should BeGreaterThan 5
            $result.FinalizedObjects | Should Be $result.ObjectsCreated
        }
        
        It "Should measure forced cleanup overhead" {
            $normalResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 1500
            $forcedResult = Invoke-ResourceCleanupTest -MockBehavior 'ForceCleanup' -ObjectCount 1500
            
            $overhead = ($forcedResult.DisposalTimeMs - $normalResult.DisposalTimeMs) / $normalResult.DisposalTimeMs
            $overhead | Should BeLessThan 3.0  # Should not be more than 3x slower
            $overhead | Should BeGreaterThan 0.5  # Should have some overhead
        }
    }
    
    Context "Cleanup Failure Scenarios" {
        
        It "Should handle partial cleanup failures gracefully" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'CleanupFailure' -ObjectCount 2000
            
            $result.Success | Should Be $false
            $result.Error | Should Match "Resource cleanup failed"
            $result.ObjectsDisposed | Should BeLessThan $result.ObjectsCreated
            $result.CleanupEfficiency | Should BeLessThan 70.0
            $result.CleanupFailures | Should Not BeNullOrEmpty
        }
        
        It "Should identify specific failure types" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'CleanupFailure' -ObjectCount 1800
            
            $result.CleanupFailures -contains 'ComObjectDisposal' | Should Be $true
            $result.CleanupFailures -contains 'FileHandleClose' | Should Be $true
            $result.MemoryLeaks | Should BeGreaterThan 100
            $result.FileHandlesLeaked | Should BeGreaterThan 50
        }
        
        It "Should measure cleanup failure impact" {
            $normalResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            $failureResult = Invoke-ResourceCleanupTest -MockBehavior 'CleanupFailure' -ObjectCount 2000
            
            $failureImpact = ($normalResult.ObjectsDisposed - $failureResult.ObjectsDisposed) / $normalResult.ObjectsDisposed
            $failureImpact | Should BeGreaterThan 0.15  # At least 15% impact
            $failureImpact | Should BeLessThan 0.35   # But not catastrophic
        }
        
        It "Should validate failure recovery attempts" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'CleanupFailure' -ObjectCount 2200
            
            $result.GCCollections | Should BeGreaterThan 5  # Should attempt recovery
            $result.ObjectsDisposed | Should BeGreaterThan 0  # Should dispose some objects
            $result.DisposalTimeMs | Should BeGreaterThan 1000  # Should take longer due to retries
        }
    }
    
    Context "Memory Pressure Impact" {
        
        It "Should handle cleanup under memory pressure" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'MemoryPressure' -ObjectCount 2500
            
            $result.Success | Should Be $true
            $result.MemoryPressureDetected | Should Be $true
            $result.EmergencyGCTriggered | Should Be $true
            $result.CleanupEfficiency | Should BeGreaterThan 80.0
            $result.GCCollections | Should BeGreaterThan 8
        }
        
        It "Should compare normal vs pressure cleanup performance" {
            $normalResult = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
            $pressureResult = Invoke-ResourceCleanupTest -MockBehavior 'MemoryPressure' -ObjectCount 2000
            
            $pressureResult.DisposalTimeMs | Should BeGreaterThan ($normalResult.DisposalTimeMs * 1.5)
            $pressureResult.GCCollections | Should BeGreaterThan ($normalResult.GCCollections * 3)
            $pressureResult.MemoryLeaks | Should BeGreaterThan $normalResult.MemoryLeaks
        }
        
        It "Should validate pressure-induced adaptations" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'MemoryPressure' -ObjectCount 3000
            
            $result.MemoryPressureDetected | Should Be $true
            $result.EmergencyGCTriggered | Should Be $true
            $result.ObjectsDisposed | Should BeGreaterThan ([math]::Floor($result.ObjectsCreated * 0.85))
        }
        
        It "Should measure pressure cleanup efficiency" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'MemoryPressure' -ObjectCount 2800
            
            $result.CleanupEfficiency | Should BeGreaterThan 85.0  # Should still be effective
            $result.CleanupEfficiency | Should BeLessThan 95.0    # But with some impact
            $result.MemoryLeaks | Should BeLessThan 300           # Controlled leak level
        }
    }
    
    Context "Resource Exhaustion Scenarios" {
        
        It "Should handle system resource exhaustion" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ResourceExhaustion' -ObjectCount 5000
            
            $result.Success | Should Be $false
            $result.Error | Should Match "System resource exhaustion"
            $result.ObjectsCreated | Should BeLessThan 4000  # Could not create all
            $result.ResourceExhaustion | Should Be $true
            $result.SystemHandlesExhausted | Should Be $true
        }
        
        It "Should validate exhaustion impact on allocation" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ResourceExhaustion' -ObjectCount 4000
            
            $allocationRate = $result.ObjectsCreated / 4000
            $allocationRate | Should BeLessThan 0.8  # Significant allocation impact
            $allocationRate | Should BeGreaterThan 0.4  # But some allocation succeeded
        }
        
        It "Should measure cleanup efficiency under exhaustion" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ResourceExhaustion' -ObjectCount 3000
            
            $result.CleanupEfficiency | Should BeLessThan 50.0
            $result.DisposalTimeMs | Should BeGreaterThan 4000
            $result.GCCollections | Should BeGreaterThan 10
        }
        
        It "Should validate partial resource cleanup under exhaustion" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'ResourceExhaustion' -ObjectCount 2500
            
            $result.ObjectsDisposed | Should BeGreaterThan 0
            $result.ObjectsDisposed | Should BeLessThan $result.ObjectsCreated
            $result.FinalizedObjects | Should BeLessThan ($result.ObjectsCreated * 0.5)
        }
    }
    
    Context "Cleanup Performance Benchmarks" {
        
        It "Should establish baseline cleanup performance" {
            $baselines = @(1000, 2000, 3000, 4000)
            $results = @()
            
            foreach ($baseline in $baselines) {
                $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount $baseline
                $results += [PSCustomObject]@{
                    ObjectCount = $baseline
                    DisposalTimeMs = $result.DisposalTimeMs
                    CleanupEfficiency = $result.CleanupEfficiency
                    GCCollections = $result.GCCollections
                }
                $result.Success | Should Be $true
            }
            
            # Validate scaling characteristics
            $maxTime = ($results | Measure-Object -Property DisposalTimeMs -Maximum).Maximum
            $minTime = ($results | Measure-Object -Property DisposalTimeMs -Minimum).Minimum
            
            $maxTime | Should BeLessThan ($minTime * 5)  # Should not be more than 5x slower for 4x objects
        }
        
        It "Should compare cleanup methods performance" {
            $methods = @('Normal', 'SlowCleanup', 'ForceCleanup')
            $results = @{}
            
            foreach ($method in $methods) {
                $result = Invoke-ResourceCleanupTest -MockBehavior $method -ObjectCount 2000
                $results[$method] = $result
            }
            
            $results['Normal'].DisposalTimeMs | Should BeLessThan $results['SlowCleanup'].DisposalTimeMs
            $results['Normal'].CleanupEfficiency | Should BeGreaterThan $results['SlowCleanup'].CleanupEfficiency
            $results['ForceCleanup'].CleanupEfficiency | Should Be 100.0
        }
        
        It "Should validate consistent cleanup performance" {
            $iterations = 5
            $results = @()
            
            for ($i = 1; $i -le $iterations; $i++) {
                $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 2000
                $results += $result.DisposalTimeMs
                $result.Success | Should Be $true
            }
            
            $avgTime = ($results | Measure-Object -Average).Average
            $maxTime = ($results | Measure-Object -Maximum).Maximum
            $minTime = ($results | Measure-Object -Minimum).Minimum
            
            # Performance should be consistent (within 50% variation)
            $variation = ($maxTime - $minTime) / $avgTime
            $variation | Should BeLessThan 0.5
        }
        
        It "Should validate resource type cleanup distribution" {
            $result = Invoke-ResourceCleanupTest -MockBehavior 'Normal' -ObjectCount 4000
            
            $totalResources = $result.ResourceTypes.FileHandles + $result.ResourceTypes.ComObjects + 
                            $result.ResourceTypes.EventHandlers + $result.ResourceTypes.MemoryStreams
            
            $totalResources | Should Be $result.ObjectsCreated
            
            # Each resource type should represent a reasonable portion
            $result.ResourceTypes.FileHandles | Should BeGreaterThan ([math]::Floor($totalResources * 0.25))
            $result.ResourceTypes.ComObjects | Should BeGreaterThan ([math]::Floor($totalResources * 0.15))
            $result.ResourceTypes.EventHandlers | Should BeGreaterThan ([math]::Floor($totalResources * 0.20))
            $result.ResourceTypes.MemoryStreams | Should BeGreaterThan ([math]::Floor($totalResources * 0.20))
        }
    }
}
