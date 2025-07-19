# Test file for Get-ClassValidationResult function
# Pester 3.4.0 compatible test

# Load the function
. "$PSScriptRoot\..\..\..\..\Private\ClassManagement\Get-ClassValidationResult.ps1"

Describe "Get-ClassValidationResult" {
    
    Context "Parameter Validation" {
        It "Should require LoadingResults parameter" {
            # In Pester 3.4, we test mandatory parameters by ensuring they're marked as mandatory
            # rather than calling the function without them (which causes prompts)
            $paramInfo = (Get-Command Get-ClassValidationResult).Parameters.LoadingResults
            $paramInfo.Attributes.Mandatory | Should Be $true
        }
        
        It "Should accept valid LoadingResults hashtable" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should accept IntegrityResults parameter" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $integrityResults = @{
                IntegrityChecks = @()
                HashValidation = @{}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults -IntegrityResults $integrityResults
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should accept SecurityResults parameter" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $securityResults = @{
                SecurityChecks = @()
                Violations = @()
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults -SecurityResults $securityResults
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should accept PathResults parameter" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $pathResults = @(@{Path = "C:\test.ps1"; Valid = $true})
            $result = Get-ClassValidationResult -LoadingResults $loadingResults -PathResults $pathResults
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Core Functionality" {
        It "Should return an object with required properties" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults
            $result.GetType().Name | Should Be "PSCustomObject"
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.Success | Should Not BeNullOrEmpty
        }
        
        It "Should include loading results in output" {
            $loadingResults = @{
                LoadedClasses = @("TestClass1", "TestClass2")
                FailedClasses = @()
                LoadingMetadata = @{Count = 2}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults
            $result.LoadedClasses | Should Not BeNullOrEmpty
        }
    }
    
    Context "Error Handling" {
        It "Should handle empty LoadingResults" {
            $loadingResults = @{}
            $result = Get-ClassValidationResult -LoadingResults $loadingResults
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle null parameters gracefully" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults -IntegrityResults $null
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Return Structure" {
        It "Should return consistent structure" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $result = Get-ClassValidationResult -LoadingResults $loadingResults
            $result.PSObject.Properties.Name -contains "CorrelationId" | Should Be $true
            $result.PSObject.Properties.Name -contains "Success" | Should Be $true
            $result.PSObject.Properties.Name -contains "LoadedClasses" | Should Be $true
        }
        
        It "Should include correlation ID when provided" {
            $loadingResults = @{
                LoadedClasses = @()
                FailedClasses = @()
                LoadingMetadata = @{}
            }
            $testCorrelationId = "test-correlation-123"
            $result = Get-ClassValidationResult -LoadingResults $loadingResults -CorrelationId $testCorrelationId
            $result.CorrelationId | Should Be $testCorrelationId
        }
    }
}


