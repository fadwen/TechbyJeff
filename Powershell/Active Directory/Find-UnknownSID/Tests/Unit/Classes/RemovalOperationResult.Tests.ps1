#Requires -Version 5.1
#Requires -Module Pester

$ModuleRoot = "C:\Users\Administrator\TechbyJeff\Powershell\Active Directory\Find-UnknownSID"
. "$ModuleRoot\Classes\RemovalOperationResult.ps1"

Describe "RemovalOperationResult Class Tests" {
    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $result = [RemovalOperationResult]::new()
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "RemovalOperationResult"
        }

        It "Should generate unique CorrelationId for each instance" {
            $result1 = [RemovalOperationResult]::new()
            $result2 = [RemovalOperationResult]::new()
            
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
        }

        It "Should initialize arrays as empty" {
            $result = [RemovalOperationResult]::new()
            
            $result.IntendedRemovals.GetType().IsArray | Should Be $true
            $result.IntendedRemovals.Count | Should Be 0
            $result.RemovedSIDs.GetType().IsArray | Should Be $true
            $result.RemovedSIDs.Count | Should Be 0
            $result.FailedSIDs.GetType().IsArray | Should Be $true
            $result.FailedSIDs.Count | Should Be 0
            $result.BlockedSIDs.GetType().IsArray | Should Be $true
            $result.BlockedSIDs.Count | Should Be 0
        }

        It "Should initialize counters to zero" {
            $result = [RemovalOperationResult]::new()
            
            $result.ActualRemovals | Should Be 0
            $result.FailedRemovals | Should Be 0
        }

        It "Should initialize Success to false" {
            $result = [RemovalOperationResult]::new()
            $result.Success | Should Be $false
        }

        It "Should initialize ProcessingTime to zero" {
            $result = [RemovalOperationResult]::new()
            $result.ProcessingTime | Should Be ([System.TimeSpan]::Zero)
        }

        It "Should initialize optional properties to null" {
            $result = [RemovalOperationResult]::new()
            
            $result.ObjectDN | Should BeNullOrEmpty
            $result.ErrorMessage | Should BeNullOrEmpty
            $result.SecurityValidation | Should BeNullOrEmpty
        }
    }

    Context "Property Tests" {
        BeforeEach {
            $script:testResult = [RemovalOperationResult]::new()
        }

        It "Should have correct property types" {
            $script:testResult.ObjectDN = "Test"
            $script:testResult.IntendedRemovals = @("Test")
            $script:testResult.ActualRemovals = 1
            $script:testResult.FailedRemovals = 1
            $script:testResult.RemovedSIDs = @("Test")
            $script:testResult.FailedSIDs = @("Test")
            $script:testResult.BlockedSIDs = @("Test")
            $script:testResult.Success = $true
            $script:testResult.ErrorMessage = "Test"
            $script:testResult.ProcessingTime = [System.TimeSpan]::FromSeconds(1)
            $script:testResult.CorrelationId = "Test"
            $script:testResult.SecurityValidation = @{ Test = "Value" }

            $script:testResult.ObjectDN | Should BeOfType [string]
            $script:testResult.IntendedRemovals.GetType().Name | Should Be "String[]"
            $script:testResult.ActualRemovals | Should BeOfType [int]
            $script:testResult.FailedRemovals | Should BeOfType [int]
            $script:testResult.RemovedSIDs.GetType().Name | Should Be "String[]"
            $script:testResult.FailedSIDs.GetType().Name | Should Be "String[]"
            $script:testResult.BlockedSIDs.GetType().Name | Should Be "String[]"
            $script:testResult.Success | Should BeOfType [bool]
            $script:testResult.ErrorMessage | Should BeOfType [string]
            $script:testResult.ProcessingTime | Should BeOfType [System.TimeSpan]
            $script:testResult.CorrelationId | Should BeOfType [string]
            $script:testResult.SecurityValidation | Should BeOfType [hashtable]
        }

        It "Should allow setting ObjectDN property" {
            $testDN = "CN=TestUser,OU=Users,DC=example,DC=com"
            $script:testResult.ObjectDN = $testDN
            $script:testResult.ObjectDN | Should Be $testDN
        }

        It "Should allow setting IntendedRemovals array" {
            $testArray = @("S-1-5-21-1-1-1-500", "S-1-5-21-2-2-2-501")
            $script:testResult.IntendedRemovals = $testArray
            $script:testResult.IntendedRemovals.Count | Should Be 2
            $script:testResult.IntendedRemovals[0] | Should Be "S-1-5-21-1-1-1-500"
        }

        It "Should allow setting ActualRemovals count" {
            $script:testResult.ActualRemovals = 5
            $script:testResult.ActualRemovals | Should Be 5
        }

        It "Should allow setting FailedRemovals count" {
            $script:testResult.FailedRemovals = 3
            $script:testResult.FailedRemovals | Should Be 3
        }

        It "Should allow setting RemovedSIDs array" {
            $testArray = @("S-1-5-21-1-1-1-500")
            $script:testResult.RemovedSIDs = $testArray
            $script:testResult.RemovedSIDs.Count | Should Be 1
            $script:testResult.RemovedSIDs[0] | Should Be "S-1-5-21-1-1-1-500"
        }

        It "Should allow setting FailedSIDs array" {
            $testArray = @("S-1-5-21-2-2-2-501", "S-1-5-21-3-3-3-502")
            $script:testResult.FailedSIDs = $testArray
            $script:testResult.FailedSIDs.Count | Should Be 2
        }

        It "Should allow setting BlockedSIDs array" {
            $testArray = @("S-1-5-21-4-4-4-503")
            $script:testResult.BlockedSIDs = $testArray
            $script:testResult.BlockedSIDs.Count | Should Be 1
        }

        It "Should allow setting Success property" {
            $script:testResult.Success = $true
            $script:testResult.Success | Should Be $true
            
            $script:testResult.Success = $false
            $script:testResult.Success | Should Be $false
        }

        It "Should allow setting ErrorMessage property" {
            $testMessage = "Test error message"
            $script:testResult.ErrorMessage = $testMessage
            $script:testResult.ErrorMessage | Should Be $testMessage
        }

        It "Should allow setting ProcessingTime property" {
            $testTime = [System.TimeSpan]::FromSeconds(10)
            $script:testResult.ProcessingTime = $testTime
            $script:testResult.ProcessingTime.TotalSeconds | Should Be 10
        }

        It "Should allow setting CorrelationId property" {
            $testId = "test-correlation-id-123"
            $script:testResult.CorrelationId = $testId
            $script:testResult.CorrelationId | Should Be $testId
        }

        It "Should allow setting SecurityValidation property" {
            $testValidation = @{ Valid = $true; Risk = "Low" }
            $script:testResult.SecurityValidation = $testValidation
            $script:testResult.SecurityValidation.Valid | Should Be $true
            $script:testResult.SecurityValidation.Risk | Should Be "Low"
        }
    }

    Context "Integration Tests" {
        It "Should create complete RemovalOperationResult" {
            $result = [RemovalOperationResult]::new()
            $result.ObjectDN = "CN=TestUser,OU=Users,DC=example,DC=com"
            $result.IntendedRemovals = @("S-1-5-21-1-1-1-500", "S-1-5-21-2-2-2-501", "S-1-5-21-3-3-3-502")
            $result.ActualRemovals = 2
            $result.FailedRemovals = 1
            $result.RemovedSIDs = @("S-1-5-21-1-1-1-500", "S-1-5-21-2-2-2-501")
            $result.FailedSIDs = @("S-1-5-21-3-3-3-502")
            $result.BlockedSIDs = @()
            $result.Success = $true
            $result.ErrorMessage = $null
            $result.ProcessingTime = [System.TimeSpan]::FromMilliseconds(150)
            
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=example,DC=com"
            $result.IntendedRemovals.Count | Should Be 3
            $result.ActualRemovals | Should Be 2
            $result.FailedRemovals | Should Be 1
            $result.RemovedSIDs.Count | Should Be 2
            $result.FailedSIDs.Count | Should Be 1
            $result.BlockedSIDs.Count | Should Be 0
            $result.Success | Should Be $true
        }
    }
}
