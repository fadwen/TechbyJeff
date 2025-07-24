#Requires -Version 5.1

# Import the function under test
. "$PSScriptRoot\..\..\..\..\Private\Operations\Invoke-OperationWithRetry.ps1"

Describe "Invoke-OperationWithRetry" -Tag "Unit", "Operations" {
    
    Context "Parameter Validation" {
        It "Should accept valid parameters" {
            { Invoke-OperationWithRetry -ScriptBlock { "test" } -MaxRetries 1 } | Should Not Throw
        }
        
        It "Should use default MaxRetries when not specified" {
            $result = Invoke-OperationWithRetry -ScriptBlock { "test" }
            $result | Should Be "test"
        }
    }
    
    Context "Successful Operation Execution" {
        It "Should execute ScriptBlock successfully" {
            $result = Invoke-OperationWithRetry -ScriptBlock { 
                return @{
                    Success = $true
                    Result = "Operation completed"
                }
            }
            
            $result.Success | Should Be $true
            $result.Result | Should Be "Operation completed"
        }
        
        It "Should return ScriptBlock result" {
            $expectedResult = "Test result"
            $result = Invoke-OperationWithRetry -ScriptBlock { 
                return $expectedResult 
            }
            
            $result | Should Be $expectedResult
        }
    }
    
    Context "Integration" {
        It "Should work with real operations" {
            $result = Invoke-OperationWithRetry -ScriptBlock { 
                Get-Date | Select-Object -ExpandProperty DayOfWeek
            }
            
            $result | Should Not BeNullOrEmpty
        }
    }
}
