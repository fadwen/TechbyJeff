# Pester 3.4 tests for Write-ADOperationSecurityLog.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

# Import dependencies
. "$here\..\..\..\..\Private\Logging\Write-SecurityLog.ps1"

Describe "Write-ADOperationSecurityLog" -Tags @('Unit', 'Logging', 'Security', 'ActiveDirectory') {

    BeforeEach {
        # Reset mock call counters for each test
        # Mock dependencies inside BeforeEach to ensure clean state
        Mock Write-SecurityLog { } -Verifiable
    }

    Context "Parameter Validation" {
        
        It "Should accept valid Outcome values" {
            $validOutcomes = @('Attempt', 'Success', 'Failure')
            foreach ($outcome in $validOutcomes) {
                { Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome $outcome } | Should Not Throw
            }
        }

        It "Should accept optional SecurityContext hashtable" {
            $context = @{ ObjectDN = "CN=TestUser,OU=Users,DC=domain,DC=com" }
            { Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -SecurityContext $context } | Should Not Throw
        }

        It "Should accept optional CorrelationId" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -CorrelationId $correlationId } | Should Not Throw
        }

        It "Should generate CorrelationId when not provided" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $CorrelationId -ne $null -and $CorrelationId -ne ""
            }
        }

        It "Should create standardized audit context" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext -ne $null -and
                $SecurityContext.OperationName -eq "Get-ADUser" -and
                $SecurityContext.Outcome -eq "Success" -and
                $SecurityContext.Component -eq "ADOperations" -and
                $SecurityContext.SecurityEventType -eq "ObjectAccess"
            }
        }

        It "Should include timestamp in audit context" {
            $beforeTime = Get-Date
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.Timestamp -ne $null -and
                $SecurityContext.Timestamp -ge $beforeTime.AddSeconds(-1)
            }
        }

        It "Should include user context information" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.UserContext -match "$env:USERNAME@$env:COMPUTERNAME"
            }
        }

        It "Should use provided CorrelationId in context" {
            $testCorrelationId = "test-correlation-123"
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.CorrelationId -eq $testCorrelationId -and
                $CorrelationId -eq $testCorrelationId
            }
        }

        It "Should merge additional security context" {
            $additionalContext = @{
                ObjectDN = "CN=TestUser,OU=Users,DC=domain,DC=com"
                Filter = "samAccountName -eq 'testuser'"
                Properties = @("Name", "SamAccountName", "DistinguishedName")
            }
            
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -SecurityContext $additionalContext
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.ObjectDN -eq "CN=TestUser,OU=Users,DC=domain,DC=com" -and
                $SecurityContext.Filter -eq "samAccountName -eq 'testuser'" -and
                $SecurityContext.Properties -ne $null
            }
        }

        It "Should handle empty additional security context" {
            $emptyContext = @{}
            
            { Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -SecurityContext $emptyContext } | Should Not Throw
            
            Assert-MockCalled Write-SecurityLog
        }
    }

    Context "Outcome-Based Message Generation" {
        
        It "Should generate attempt message for Attempt outcome" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Attempt"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -eq "Attempting Active Directory operation: Get-ADUser" -and
                $Outcome -eq "Attempt"
            }
        }

        It "Should generate success message for Success outcome" {
            Write-ADOperationSecurityLog -OperationName "Set-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -eq "Successfully completed Active Directory operation: Set-ADUser" -and
                $Outcome -eq "Success"
            }
        }

        It "Should generate failure message for Failure outcome" {
            Write-ADOperationSecurityLog -OperationName "Remove-ADUser" -Outcome "Failure"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -eq "Failed Active Directory operation: Remove-ADUser" -and
                $Outcome -eq "Failure"
            }
        }
    }

    Context "Write-SecurityLog Integration" {
        
        It "Should always use ObjectAccess security event type" {
            $operationNames = @("Get-ADUser", "Set-ADUser", "New-ADUser", "Remove-ADUser")
            $outcomes = @("Attempt", "Success", "Failure")
            
            foreach ($operation in $operationNames) {
                foreach ($outcome in $outcomes) {
                    Write-ADOperationSecurityLog -OperationName $operation -Outcome $outcome
                    
                    Assert-MockCalled Write-SecurityLog -ParameterFilter {
                        $SecurityEventType -eq "ObjectAccess"
                    }
                }
            }
        }

        It "Should pass through CorrelationId to Write-SecurityLog" {
            $testCorrelationId = "integration-test-456"
            
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $CorrelationId -eq $testCorrelationId
            }
        }

        It "Should pass complete security context to Write-SecurityLog" {
            $additionalContext = @{ Filter = "Department -eq 'IT'" }
            
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -SecurityContext $additionalContext
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext -ne $null -and
                $SecurityContext.Count -ge 7  # Standard context plus additional
            }
        }
    }

    Context "Common AD Operations" {
        
        It "Should handle Get-ADUser operations" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -match "Get-ADUser"
            }
        }

        It "Should handle Set-ADUser operations" {
            Write-ADOperationSecurityLog -OperationName "Set-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -match "Set-ADUser"
            }
        }

        It "Should handle New-ADUser operations" {
            Write-ADOperationSecurityLog -OperationName "New-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -match "New-ADUser"
            }
        }

        It "Should handle Remove-ADUser operations" {
            Write-ADOperationSecurityLog -OperationName "Remove-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -match "Remove-ADUser"
            }
        }

        It "Should handle custom AD operation names" {
            Write-ADOperationSecurityLog -OperationName "Custom-ADOperation" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $Message -match "Custom-ADOperation"
            }
        }
    }

    Context "Compliance and Audit Requirements" {
        
        It "Should always include required audit fields" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.OperationName -ne $null -and
                $SecurityContext.Outcome -ne $null -and
                $SecurityContext.Timestamp -ne $null -and
                $SecurityContext.UserContext -ne $null -and
                $SecurityContext.CorrelationId -ne $null -and
                $SecurityContext.Component -eq "ADOperations" -and
                $SecurityContext.SecurityEventType -eq "ObjectAccess"
            }
        }

        It "Should generate unique audit entries for each call" {
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Attempt"
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success"
            
            Assert-MockCalled Write-SecurityLog
        }

        It "Should support traceability through CorrelationId" {
            $traceId = "compliance-trace-789"
            
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Attempt" -CorrelationId $traceId
            Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" -CorrelationId $traceId
            
            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $CorrelationId -eq $traceId
            }
        }
    }

    Context "Error Scenarios" {
        
        It "Should handle Write-SecurityLog failures gracefully" {
            Mock Write-SecurityLog { throw "Security log system failure" } 
            
            { Write-ADOperationSecurityLog -OperationName "Get-ADUser" -Outcome "Success" } | Should Throw
        }
    }
}

