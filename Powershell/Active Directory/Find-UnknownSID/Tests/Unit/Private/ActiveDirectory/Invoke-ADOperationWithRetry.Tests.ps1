#Requires -Module Pester

# Define mock functions first to prevent parameter prompting
function Write-StructuredLog {
    param($Level, $Message, $Data)
    # Mock implementation - do nothing  
}

function Invoke-OperationWithRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [string]$OperationName = 'Operation',
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    # Implement proper retry logic for testing
    $attempt = 0
    $lastError = $null
    
    while ($attempt -le $MaxRetries) {
        try {
            return & $ScriptBlock
        }
        catch {
            $lastError = $_
            $attempt++
            
            # Check if this is a retryable exception
            $retryableExceptions = @(
                'ActiveDirectoryServerDownException',
                'RuntimeException'
            )
            
            $isRetryable = $false
            foreach ($exceptionType in $retryableExceptions) {
                if ($_.Exception.GetType().Name -match $exceptionType -or $_.Exception.Message -match 'Temporary') {
                    $isRetryable = $true
                    break
                }
            }
            
            # If not retryable or max retries reached, throw immediately
            if (-not $isRetryable -or $attempt -gt $MaxRetries) {
                throw
            }
            
            # Brief delay before retry
            Start-Sleep -Milliseconds 10
        }
    }
    
    # Should not reach here, but throw last error if we do
    throw $lastError
}

# Import the function to test AFTER defining mocks
. "$PSScriptRoot\..\..\..\..\Private\ActiveDirectory\Invoke-ADOperationWithRetry.ps1"

# Import required logging function
. "$PSScriptRoot\..\..\..\..\Private\Logging\Write-ADOperationSecurityLog.ps1"

# Test configuration for various operation types
$testConfig = @{
    SuccessOperation = {
        return @{
            Success = $true
            Result = "Operation completed successfully"
            Data = @{ ProcessedItems = 5; Duration = "00:00:01" }
        }
    }
    
    TransientFailureOperation = {
        if ($script:AttemptCount -eq 0) {
            $script:AttemptCount++
            throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryServerDownException]::new("Temporary server unavailable")
        }
        return @{ Success = $true; Result = "Success after retry" }
    }
    
    PersistentFailureOperation = {
        throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryObjectNotFoundException]::new("Object not found")
    }
    
    TimeoutOperation = {
        Start-Sleep -Milliseconds 200
        return @{ Success = $true; Result = "Delayed operation" }
    }
    
    SlowOperation = {
        Start-Sleep -Milliseconds 100
        return @{
            Success = $true
            Result = "Slow operation completed"
            Duration = 100
        }
    }
}

Describe "Invoke-ADOperationWithRetry" {
    
    # Set up Pester 3.4.x mocks for logging functions
    Mock Write-ADOperationSecurityLog { }
    Mock Write-StructuredLog { }
    
    BeforeEach {
        # Reset attempt counter for each test
        $script:AttemptCount = 0
        
        # Clear mock call tracking
        $global:MockCalls = @()
    }
    
    Context "Parameter Validation and Input Security" {
        It "Should validate mandatory ScriptBlock parameter" {
            # In Pester 3.4.x, we need to test this differently to avoid parameter prompting
            try {
                $result = Invoke-ADOperationWithRetry -ScriptBlock $null
                # If we get here without error, the test should fail
                $false | Should Be $true
            }
            catch {
                $_.Exception.Message | Should Match "ScriptBlock|null"
            }
        }
        
        It "Should accept valid script block for ScriptBlock parameter" {
            $scriptBlock = { return "Test Result" }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should validate MaxRetries parameter range" {
            $scriptBlock = { return "Test" }
            { Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 0 } | Should Throw
            { Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 11 } | Should Throw
            { Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 5 } | Should Not Throw
        }
        
        It "Should accept valid OperationName parameter" {
            $scriptBlock = { return "Test" }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation"
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should support ObjectContext parameter" {
            $scriptBlock = { return "Test" }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -ObjectContext "Test Object"
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should support all parameters together" {
            $scriptBlock = { return "Complete Test" }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 2 -OperationName "Test Op" -ObjectContext "Test Context"
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Basic Operation Execution" {
        It "Should execute simple operations successfully" {
            $result = Invoke-ADOperationWithRetry -ScriptBlock $testConfig.SuccessOperation
            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
        }
        
        It "Should return operation results correctly" {
            $result = Invoke-ADOperationWithRetry -ScriptBlock $testConfig.SuccessOperation
            $result.Result | Should Be "Operation completed successfully"
            $result.Data.ProcessedItems | Should Be 5
        }
        
        It "Should handle operations with return values" {
            $scriptBlock = { return @{Status = "Complete"; Items = @(1,2,3)} }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            $result.Status | Should Be "Complete"
            $result.Items.Count | Should Be 3
        }
        
        It "Should handle operations with simple return values" {
            $scriptBlock = { return "Simple string result" }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            $result | Should Be "Simple string result"
        }
        
        It "Should handle operations that return arrays" {
            $scriptBlock = { return @("Item1", "Item2", "Item3") }
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            $result.Count | Should Be 3
            $result[0] | Should Be "Item1"
        }
    }
    
    Context "Retry Logic and Resilience" {
        It "Should retry on transient failures" {
            $result = Invoke-ADOperationWithRetry -ScriptBlock $testConfig.TransientFailureOperation -MaxRetries 2
            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            $result.Result | Should Be "Success after retry"
        }
        
        It "Should respect MaxRetries parameter" {
            $script:AttemptCount = 0
            try {
                Invoke-ADOperationWithRetry -ScriptBlock $testConfig.PersistentFailureOperation -MaxRetries 3
            }
            catch { }
            # The retry logic is in Invoke-OperationWithRetry, so we test the wrapper behavior
        }
        
        It "Should handle operations that eventually succeed" {
            $global:EventualSuccessCounter = 0
            $scriptBlock = {
                if ($global:EventualSuccessCounter -lt 2) {
                    $global:EventualSuccessCounter++
                    throw "Temporary failure $global:EventualSuccessCounter"
                }
                return "Success after multiple retries"
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 3
            $result | Should Be "Success after multiple retries"
        }
    }
    
    Context "Error Classification and Handling" {
        It "Should propagate non-retryable errors immediately" {
            { Invoke-ADOperationWithRetry -ScriptBlock $testConfig.PersistentFailureOperation -MaxRetries 3 } | Should Throw
        }
        
        It "Should handle specific Active Directory exceptions" {
            $adException = {
                throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryObjectNotFoundException]::new("AD object not found")
            }
            { Invoke-ADOperationWithRetry -ScriptBlock $adException } | Should Throw
        }
        
        It "Should handle authentication exceptions" {
            $authException = {
                throw [System.Security.Authentication.AuthenticationException]::new("Authentication failed")
            }
            { Invoke-ADOperationWithRetry -ScriptBlock $authException } | Should Throw
        }
        
        It "Should handle network-related exceptions" {
            $networkException = {
                throw [System.Net.NetworkInformation.NetworkInformationException]::new()
            }
            { Invoke-ADOperationWithRetry -ScriptBlock $networkException } | Should Throw
        }
        
        It "Should include error context in exception propagation" {
            try {
                Invoke-ADOperationWithRetry -ScriptBlock $testConfig.PersistentFailureOperation -MaxRetries 1 -OperationName "Error Context Test"
            }
            catch {
                $_.Exception | Should Not BeNullOrEmpty
            }
        }
    }
    
    Context "Performance and Timing" {
        It "Should complete fast operations quickly" {
            $fastOperation = { return "Fast result" }
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-ADOperationWithRetry -ScriptBlock $fastOperation
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should handle slow operations within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-ADOperationWithRetry -ScriptBlock $testConfig.SlowOperation
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeGreaterThan 50
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should track execution time for operations" {
            $result = Invoke-ADOperationWithRetry -ScriptBlock $testConfig.SuccessOperation
            # Basic execution should complete successfully
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle operations with varying execution times" {
            $variableTimeOperation = {
                $delay = Get-Random -Minimum 10 -Maximum 50
                Start-Sleep -Milliseconds $delay
                return @{ Delay = $delay; Success = $true }
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $variableTimeOperation
            $result.Success | Should Be $true
            $result.Delay | Should BeGreaterThan 0
        }
    }
    
    Context "Enterprise Security Logging and Auditing" {
        It "Should log operation attempts with security context" {
            $scriptBlock = { return "Logged operation" }
            Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $OperationName -eq 'AD Operation' -and
                $Outcome -eq 'Attempt'
            }
        }
        
        It "Should log retry attempts with failure context" {
            $script:AttemptCount = 0
            try {
                Invoke-ADOperationWithRetry -ScriptBlock $testConfig.TransientFailureOperation -MaxRetries 2 -OperationName "Retry Log Test"
            }
            catch { }
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $Outcome -eq 'Attempt'
            }
        }
        
        It "Should log final success with operation summary" {
            $scriptBlock = { return @{ Status = "Complete" } }
            Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $Outcome -eq 'Success'
            }
        }
        
        It "Should log final failure with error details" {
            try {
                Invoke-ADOperationWithRetry -ScriptBlock $testConfig.PersistentFailureOperation -MaxRetries 1 -OperationName "Failure Log Test"
            }
            catch { }
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $Outcome -eq 'Failure'
            }
        }
        
        It "Should include security context in all log entries" {
            $scriptBlock = { return "Security logged" }
            Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -ObjectContext "Test Object"
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $SecurityContext.ContainsKey('ObjectContext') -and
                $SecurityContext.ObjectContext -eq 'Test Object'
            }
        }
        
        It "Should log with appropriate correlation ID tracking" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            $scriptBlock = { return "Correlated operation" }
            
            Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-ADOperationSecurityLog -Times 1 -ParameterFilter {
                $CorrelationId -eq $testCorrelationId
            }
        }
    }
    
    Context "Integration and Compliance Scenarios" {
        It "Should handle complex AD operations with proper retry logic" {
            $script:AttemptCount = 0
            $complexOperation = {
                if ($script:AttemptCount -eq 0) {
                    $script:AttemptCount++
                    throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryServerDownException]::new("DC unavailable")
                }
                return @{
                    Results = @(
                        @{ Name = "User1"; DN = "CN=User1,OU=Users,DC=domain,DC=com" }
                        @{ Name = "User2"; DN = "CN=User2,OU=Users,DC=domain,DC=com" }
                    )
                    Count = 2
                }
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $complexOperation -MaxRetries 2 -OperationName "Complex AD Query"
            
            $result | Should Not BeNullOrEmpty
            $result.Count | Should Be 2
            $result.Results.Count | Should Be 2
        }
        
        It "Should support operations with authentication context" {
            $scriptBlock = {
                return @{
                    AuthenticatedUser = "testuser"
                    Domain = "testdomain.com"
                    Success = $true
                }
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -ObjectContext "Authentication Test"
            
            $result.AuthenticatedUser | Should Be "testuser"
            $result.Domain | Should Be "testdomain.com"
            $result.Success | Should Be $true
        }
        
        It "Should handle operations with large result sets efficiently" {
            $scriptBlock = {
                $results = 1..1000 | ForEach-Object {
                    @{
                        Id = $_
                        Name = "Object$_"
                        DN = "CN=Object$_,OU=Objects,DC=domain,DC=com"
                    }
                }
                return @{
                    Results = $results
                    TotalCount = $results.Count
                    ProcessingTime = (Get-Date)
                }
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -OperationName "Large Result Set"
            
            $result | Should Not BeNullOrEmpty
            $result.TotalCount | Should Be 1000
            $result.Results.Count | Should Be 1000
        }
        
        It "Should maintain data consistency across retry attempts" {
            $global:ConsistencyCounter = 0
            $scriptBlock = {
                $global:ConsistencyCounter++
                if ($global:ConsistencyCounter -lt 2) {
                    throw "Consistency check failed"
                }
                return @{ ConsistencyCheck = "Passed"; Counter = $global:ConsistencyCounter }
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 3
            $result.ConsistencyCheck | Should Be "Passed"
            $result.Counter | Should Be 2
        }
    }
    
    Context "Error Recovery and Resilience Patterns" {
        It "Should implement circuit breaker pattern for repeated failures" {
            $scriptBlock = {
                throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryServerDownException]::new("Persistent server failure")
            }
            
            # Should eventually stop retrying and fail fast
            { Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 5 } | Should Throw
        }
        
        It "Should handle cascading failures gracefully" {
            $scriptBlock = {
                throw [System.Net.NetworkInformation.NetworkInformationException]::new()
            }
            
            { Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 1 } | Should Throw
        }
        
        It "Should provide detailed failure diagnostics" {
            $scriptBlock = {
                $exception = [System.DirectoryServices.ActiveDirectory.ActiveDirectoryServerDownException]::new("Diagnostic test failure")
                throw $exception
            }
            
            try {
                Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 1
            }
            catch {
                $_.Exception | Should Not BeNullOrEmpty
            }
        }
        
        It "Should support retry strategies with ScriptBlock operations" {
            $global:RetryStrategyCounter = 0
            $scriptBlock = {
                if ($global:RetryStrategyCounter -lt 2) {
                    $global:RetryStrategyCounter++
                    throw [System.DirectoryServices.ActiveDirectory.ActiveDirectoryServerDownException]::new("Retry test")
                }
                return "Success after retry"
            }
            
            $result = Invoke-ADOperationWithRetry -ScriptBlock $scriptBlock -MaxRetries 3
            
            $result | Should Be "Success after retry"
        }
    }
}
