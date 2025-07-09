#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Operations test suite for Find-UnknownSID

.DESCRIPTION
    Comprehensive Pester tests for operational functions including retry logic, removal workflows,
    and operational validation. Tests all operations-related functionality including error handling,
    retry mechanisms, and workflow orchestration.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 30 tests covering 2 operation functions
#>

# Import the module under test (relative path from Tests\Unit to module root)
Import-Module "$PSScriptRoot\..\..\Find-UnknownSID.ps1" -Force

Describe "Operations Tests" -Tag "Unit", "Operations" {
    BeforeAll {
        # Set up test environment
        $TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $TestLogPath = Join-Path $env:TEMP "TestLogs\Operations_$TestCorrelationId.log"
        
        # Initialize script for operations tests
        $script:TestInit = Initialize-ScriptExecution -LogPath $TestLogPath -CorrelationId $TestCorrelationId
        
        # Test data
        $script:TestSIDInfo = @{
            SID = "S-1-5-21-123456789-987654321-1122334455-1001"
            Path = "C:\TestDirectory"
            Type = "Directory"
            Source = "FileSystem"
        }
        
        $script:TestSIDCollection = @(
            @{ SID = "S-1-5-21-123-456-789-1001"; Path = "C:\Test1"; Type = "File" }
            @{ SID = "S-1-5-21-123-456-789-1002"; Path = "C:\Test2"; Type = "Directory" }
            @{ SID = "S-1-5-21-123-456-789-1003"; Path = "HKLM:\SOFTWARE\Test"; Type = "Registry" }
        )
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $TestLogPath) { Remove-Item $TestLogPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path (Split-Path $TestLogPath)) { Remove-Item (Split-Path $TestLogPath) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context "Invoke-OperationWithRetry Function Tests" {
        It "Should execute operation successfully on first attempt" {
            $operation = { return @{ Success = $true; Result = "Operation completed" } }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "TestOperation" -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.AttemptCount | Should -Be 1
            $result.Result | Should -Be "Operation completed"
        }
        
        It "Should retry operation on transient failures" {
            $script:CallCount = 0
            $operation = { 
                $script:CallCount++
                if ($script:CallCount -lt 3) {
                    throw "Transient error occurred"
                }
                return @{ Success = $true; Result = "Succeeded after retry" }
            }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "RetryTest" -MaxRetries 5 -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.AttemptCount | Should -Be 3
            $script:CallCount | Should -Be 3
        }
        
        It "Should fail after exceeding maximum retry attempts" {
            $operation = { throw "Persistent error" }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "FailTest" -MaxRetries 3 -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.AttemptCount | Should -Be 3
            $result.Error | Should -Match "*Persistent error*"
        }
        
        It "Should validate operation parameter" {
            { Invoke-OperationWithRetry -Operation $null -OperationName "NullTest" -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be null*"
        }
        
        It "Should validate operation name parameter" {
            $operation = { return @{ Success = $true } }
            { Invoke-OperationWithRetry -Operation $operation -OperationName "" -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be empty*"
        }
        
        It "Should validate maximum retry count" {
            $operation = { return @{ Success = $true } }
            { Invoke-OperationWithRetry -Operation $operation -OperationName "ValidationTest" -MaxRetries -1 -CorrelationId $TestCorrelationId } | Should -Throw "*validation*"
            { Invoke-OperationWithRetry -Operation $operation -OperationName "ValidationTest" -MaxRetries 101 -CorrelationId $TestCorrelationId } | Should -Throw "*validation*"
        }
        
        It "Should implement exponential backoff delay" {
            $script:CallTimes = @()
            $operation = { 
                $script:CallTimes += Get-Date
                if ($script:CallTimes.Count -lt 3) {
                    throw "Retry needed"
                }
                return @{ Success = $true }
            }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "BackoffTest" -MaxRetries 5 -RetryDelay 100 -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $script:CallTimes.Count | Should -Be 3
            
            # Verify delays increased (allowing for timing variance)
            if ($script:CallTimes.Count -ge 2) {
                $delay1 = ($script:CallTimes[1] - $script:CallTimes[0]).TotalMilliseconds
                $delay2 = ($script:CallTimes[2] - $script:CallTimes[1]).TotalMilliseconds
                $delay2 | Should -BeGreaterThan $delay1
            }
        }
        
        It "Should handle different exception types appropriately" {
            # Transient exceptions should be retried
            $transientOperation = { throw [System.IO.IOException]::new("Network error") }
            $transientResult = Invoke-OperationWithRetry -Operation $transientOperation -OperationName "TransientTest" -MaxRetries 2 -CorrelationId $TestCorrelationId
            $transientResult.AttemptCount | Should -Be 2
            
            # Fatal exceptions should not be retried
            $fatalOperation = { throw [System.ArgumentNullException]::new("Parameter cannot be null") }
            $fatalResult = Invoke-OperationWithRetry -Operation $fatalOperation -OperationName "FatalTest" -MaxRetries 5 -CorrelationId $TestCorrelationId
            $fatalResult.AttemptCount | Should -Be 1  # No retries for fatal exceptions
        }
        
        It "Should log retry attempts appropriately" {
            Mock Write-StructuredLog { }
            $script:RetryCallCount = 0
            $operation = { 
                $script:RetryCallCount++
                if ($script:RetryCallCount -lt 3) {
                    throw "Retry needed"
                }
                return @{ Success = $true }
            }
            
            Invoke-OperationWithRetry -Operation $operation -OperationName "LogTest" -MaxRetries 5 -CorrelationId $TestCorrelationId
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter { $Message -match "retry" } -Exactly 2
        }
        
        It "Should support custom retry conditions" {
            $script:CustomCallCount = 0
            $operation = { 
                $script:CustomCallCount++
                if ($script:CustomCallCount -lt 4) {
                    return @{ Success = $false; Error = "Custom retry condition" }
                }
                return @{ Success = $true; Result = "Custom success" }
            }
            
            $retryCondition = { param($result) return -not $result.Success }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "CustomTest" -MaxRetries 5 -CustomRetryCondition $retryCondition -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.AttemptCount | Should -Be 4
        }
        
        It "Should handle timeout scenarios" {
            $timeoutOperation = { 
                Start-Sleep -Seconds 2
                return @{ Success = $true }
            }
            
            $result = Invoke-OperationWithRetry -Operation $timeoutOperation -OperationName "TimeoutTest" -MaxRetries 1 -OperationTimeout 1000 -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "*timeout*"
        }
        
        It "Should collect detailed operation metrics" {
            $operation = { return @{ Success = $true; ProcessedItems = 10 } }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "MetricsTest" -CollectMetrics -CorrelationId $TestCorrelationId
            
            $result | Should -HaveProperty 'Metrics'
            $result.Metrics | Should -HaveProperty 'StartTime'
            $result.Metrics | Should -HaveProperty 'EndTime'
            $result.Metrics | Should -HaveProperty 'TotalDuration'
        }
        
        It "Should support operation cancellation" {
            $cancellationToken = New-Object System.Threading.CancellationTokenSource
            $operation = { 
                param($token)
                Start-Sleep -Milliseconds 500
                if ($token.IsCancellationRequested) {
                    throw [System.OperationCanceledException]::new("Operation was cancelled")
                }
                return @{ Success = $true }
            }
            
            # Cancel after short delay
            $timer = New-Object System.Timers.Timer(200)
            $timer.AutoReset = $false
            $timer.Add_Elapsed({ $cancellationToken.Cancel() })
            $timer.Start()
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "CancelTest" -CancellationToken $cancellationToken.Token -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "*cancelled*"
            
            $timer.Dispose()
            $cancellationToken.Dispose()
        }
        
        It "Should handle circuit breaker pattern" {
            $script:CircuitCallCount = 0
            $operation = { 
                $script:CircuitCallCount++
                throw "Persistent failure"
            }
            
            # First operation should try all retries
            $result1 = Invoke-OperationWithRetry -Operation $operation -OperationName "CircuitTest" -MaxRetries 3 -EnableCircuitBreaker -CorrelationId $TestCorrelationId
            $result1.AttemptCount | Should -Be 3
            
            # Subsequent operations should fail fast due to circuit breaker
            $result2 = Invoke-OperationWithRetry -Operation $operation -OperationName "CircuitTest" -MaxRetries 3 -EnableCircuitBreaker -CorrelationId $TestCorrelationId
            $result2.AttemptCount | Should -Be 1
            $result2.CircuitBreakerOpen | Should -Be $true
        }
    }

    Context "Invoke-RemovalWorkflow Function Tests" {
        It "Should execute removal workflow for single SID" {
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ProcessedCount | Should -Be 1
            $result.SuccessfulRemovals | Should -Be 1
        }
        
        It "Should execute removal workflow for multiple SIDs" {
            Mock Remove-OrphanedSID { 
                param($SIDInfo)
                return @{ Success = $true; Removed = $true; SID = $SIDInfo.SID }
            }
            
            $result = Invoke-RemovalWorkflow -SIDInfoCollection $script:TestSIDCollection -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.ProcessedCount | Should -Be $script:TestSIDCollection.Count
            $result.SuccessfulRemovals | Should -Be $script:TestSIDCollection.Count
            $result.FailedRemovals | Should -Be 0
        }
        
        It "Should validate SIDInfo parameter structure" {
            $invalidSIDInfo = @{ SID = "InvalidSID" }  # Missing required properties
            
            { Invoke-RemovalWorkflow -SIDInfo $invalidSIDInfo -CorrelationId $TestCorrelationId } | Should -Throw "*required properties*"
        }
        
        It "Should handle partial failures in batch operations" {
            Mock Remove-OrphanedSID { 
                param($SIDInfo)
                if ($SIDInfo.SID -eq "S-1-5-21-123-456-789-1002") {
                    throw "Removal failed for this SID"
                }
                return @{ Success = $true; Removed = $true; SID = $SIDInfo.SID }
            }
            
            $result = Invoke-RemovalWorkflow -SIDInfoCollection $script:TestSIDCollection -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true  # Overall success despite partial failures
            $result.ProcessedCount | Should -Be $script:TestSIDCollection.Count
            $result.SuccessfulRemovals | Should -Be ($script:TestSIDCollection.Count - 1)
            $result.FailedRemovals | Should -Be 1
            $result.Errors | Should -HaveCount 1
        }
        
        It "Should support dry run mode" {
            Mock Remove-OrphanedSID { 
                param($SIDInfo, $DryRun)
                $DryRun | Should -Be $true
                return @{ Success = $true; Removed = $false; SID = $SIDInfo.SID; DryRun = $true }
            }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -DryRun -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.DryRun | Should -Be $true
            $result.ActualRemovals | Should -Be 0
        }
        
        It "Should implement parallel processing for large collections" {
            $largeSIDCollection = 1..20 | ForEach-Object {
                @{ SID = "S-1-5-21-123-456-789-$_"; Path = "C:\Test$_"; Type = "File" }
            }
            
            Mock Remove-OrphanedSID { 
                param($SIDInfo)
                Start-Sleep -Milliseconds 100  # Simulate processing time
                return @{ Success = $true; Removed = $true; SID = $SIDInfo.SID }
            }
            
            $sequentialStart = Get-Date
            $result = Invoke-RemovalWorkflow -SIDInfoCollection $largeSIDCollection -CorrelationId $TestCorrelationId
            $sequentialDuration = (Get-Date) - $sequentialStart
            
            $parallelStart = Get-Date
            $parallelResult = Invoke-RemovalWorkflow -SIDInfoCollection $largeSIDCollection -ParallelProcessing -MaxConcurrency 5 -CorrelationId $TestCorrelationId
            $parallelDuration = (Get-Date) - $parallelStart
            
            $parallelResult.Success | Should -Be $true
            $parallelResult.ProcessedCount | Should -Be $largeSIDCollection.Count
            $parallelDuration.TotalMilliseconds | Should -BeLessThan ($sequentialDuration.TotalMilliseconds * 0.8)  # Parallel should be faster
        }
        
        It "Should create backup before removal operations" {
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            Mock New-ACLBackup { return @{ Success = $true; BackupPath = "C:\Backup\backup.json" } }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CreateBackup -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.BackupCreated | Should -Be $true
            $result.BackupPath | Should -Not -BeNullOrEmpty
        }
        
        It "Should rollback changes on critical failures" {
            Mock Remove-OrphanedSID { throw "Critical system error" }
            Mock Restore-ACLFromBackup { return @{ Success = $true; RestoredCount = 1 } }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CreateBackup -RollbackOnFailure -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.RollbackPerformed | Should -Be $true
            $result.RestoredCount | Should -Be 1
        }
        
        It "Should validate workflow prerequisites" {
            Mock Test-RemovalPrerequisites { return @{ Valid = $false; MissingRequirements = @("Administrator privileges", "Backup location") } }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -ValidatePrerequisites -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.PrerequisiteValidation | Should -Be $false
            $result.MissingRequirements | Should -HaveCount 2
        }
        
        It "Should generate comprehensive workflow reports" {
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -GenerateReport -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.Report | Should -Not -BeNullOrEmpty
            $result.Report | Should -HaveProperty 'WorkflowSummary'
            $result.Report | Should -HaveProperty 'ProcessingDetails'
            $result.Report | Should -HaveProperty 'PerformanceMetrics'
        }
        
        It "Should support custom validation rules" {
            $customValidator = { 
                param($SIDInfo)
                return @{ 
                    Valid = $SIDInfo.Type -eq "Directory"
                    Reason = if ($SIDInfo.Type -ne "Directory") { "Only directories allowed" } else { $null }
                }
            }
            
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            
            # Should succeed for directory
            $result1 = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CustomValidator $customValidator -CorrelationId $TestCorrelationId
            $result1.Success | Should -Be $true
            
            # Should fail for file
            $fileSIDInfo = @{ SID = "S-1-5-21-123-456-789-1001"; Path = "C:\TestFile.txt"; Type = "File" }
            $result2 = Invoke-RemovalWorkflow -SIDInfo $fileSIDInfo -CustomValidator $customValidator -CorrelationId $TestCorrelationId
            $result2.Success | Should -Be $false
            $result2.ValidationFailures | Should -HaveCount 1
        }
        
        It "Should implement progress tracking for long operations" {
            $largeSIDCollection = 1..10 | ForEach-Object {
                @{ SID = "S-1-5-21-123-456-789-$_"; Path = "C:\Test$_"; Type = "File" }
            }
            
            $progressUpdates = @()
            $progressCallback = { 
                param($current, $total, $currentSID)
                $progressUpdates += @{ Current = $current; Total = $total; SID = $currentSID }
            }
            
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            
            $result = Invoke-RemovalWorkflow -SIDInfoCollection $largeSIDCollection -ProgressCallback $progressCallback -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $progressUpdates | Should -HaveCount $largeSIDCollection.Count
            $progressUpdates[0].Current | Should -Be 1
            $progressUpdates[-1].Current | Should -Be $largeSIDCollection.Count
        }
        
        It "Should handle workflow cancellation gracefully" {
            $cancellationToken = New-Object System.Threading.CancellationTokenSource
            
            Mock Remove-OrphanedSID { 
                param($SIDInfo, $CancellationToken)
                if ($CancellationToken.IsCancellationRequested) {
                    throw [System.OperationCanceledException]::new("Workflow cancelled")
                }
                Start-Sleep -Milliseconds 200
                return @{ Success = $true; Removed = $true; SID = $SIDInfo.SID }
            }
            
            # Cancel after processing starts
            $timer = New-Object System.Timers.Timer(100)
            $timer.AutoReset = $false
            $timer.Add_Elapsed({ $cancellationToken.Cancel() })
            $timer.Start()
            
            $result = Invoke-RemovalWorkflow -SIDInfoCollection $script:TestSIDCollection -CancellationToken $cancellationToken.Token -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Cancelled | Should -Be $true
            $result.ProcessedCount | Should -BeLessThan $script:TestSIDCollection.Count
            
            $timer.Dispose()
            $cancellationToken.Dispose()
        }
        
        It "Should maintain detailed error context for troubleshooting" {
            Mock Remove-OrphanedSID { 
                param($SIDInfo)
                $error = @{
                    SID = $SIDInfo.SID
                    Path = $SIDInfo.Path
                    ErrorType = "AccessDenied"
                    ErrorMessage = "Access denied to modify ACL"
                    Timestamp = Get-Date
                    CorrelationId = $TestCorrelationId
                    StackTrace = "Mock stack trace"
                }
                throw $error | ConvertTo-Json
            }
            
            $result = Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -DetailedErrorReporting -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.DetailedErrors | Should -HaveCount 1
            $result.DetailedErrors[0] | Should -HaveProperty 'SID'
            $result.DetailedErrors[0] | Should -HaveProperty 'Path'
            $result.DetailedErrors[0] | Should -HaveProperty 'ErrorType'
            $result.DetailedErrors[0] | Should -HaveProperty 'CorrelationId'
        }
    }

    Context "Integration Tests" {
        It "Should complete full workflow with retry and recovery" {
            $script:OperationCallCount = 0
            Mock Remove-OrphanedSID { 
                $script:OperationCallCount++
                if ($script:OperationCallCount -eq 1) {
                    throw "Transient network error"
                }
                return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID }
            }
            
            $operation = { Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CorrelationId $TestCorrelationId }
            
            $result = Invoke-OperationWithRetry -Operation $operation -OperationName "IntegrationTest" -MaxRetries 3 -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.AttemptCount | Should -Be 2
            $script:OperationCallCount | Should -Be 2
        }
        
        It "Should maintain correlation ID throughout complex operations" {
            Mock Write-StructuredLog { 
                param($Message, $Level, $Component, $CorrelationId)
                $CorrelationId | Should -Be $TestCorrelationId
            }
            Mock Remove-OrphanedSID { return @{ Success = $true; Removed = $true; SID = $script:TestSIDInfo.SID } }
            
            $operation = { Invoke-RemovalWorkflow -SIDInfo $script:TestSIDInfo -CorrelationId $TestCorrelationId }
            Invoke-OperationWithRetry -Operation $operation -OperationName "CorrelationTest" -CorrelationId $TestCorrelationId
        }
    }
}
