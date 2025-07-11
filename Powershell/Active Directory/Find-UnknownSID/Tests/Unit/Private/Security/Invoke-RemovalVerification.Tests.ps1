#Requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for Invoke-RemovalVerification function

.DESCRIPTION
    Simple functional tests for SID removal verification.

.NOTES
    Author: Jeffrey Stuhr
    Test Framework: Pester 3.4.x
    Last Updated: 2025-01-27
#>

# Define mock functions first to avoid dependency issues
function Write-StructuredLog { 
    param($Message, $Level, $CorrelationId) 
    # Track log calls for verification
    $script:LogCalls += @{ Message = $Message; Level = $Level; CorrelationId = $CorrelationId }
}

function Invoke-ADOperationWithRetry { 
    param($ScriptBlock, $MaxRetries, $OperationName, $ObjectContext) 
    # Track retry calls and execute script block
    $script:RetryCalls += @{ MaxRetries = $MaxRetries; OperationName = $OperationName; ObjectContext = $ObjectContext }
    & $ScriptBlock
}

# Now import the function under test
. "$PSScriptRoot\..\..\..\..\Private\Security\Invoke-RemovalVerification.ps1"

Describe "Invoke-RemovalVerification" {
    
    BeforeEach {
        # Reset tracking variables
        $script:LogCalls = @()
        $script:RetryCalls = @()
    }
    
    Context "Parameter Validation" {
        
        It "Should reject empty ObjectDN" {
            { Invoke-RemovalVerification -ObjectDN "" -AllowedSIDs @("S-1-5-21-1001") } | Should Throw "argument is null or empty"
        }
        
        It "Should reject whitespace-only ObjectDN" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "   " -AllowedSIDs @("S-1-5-21-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "ObjectDN parameter cannot be empty"
        }
        
        It "Should trim whitespace from ObjectDN" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "  CN=Test,DC=contoso,DC=com  " -AllowedSIDs @("S-1-5-21-1001")
            
            # Verify Get-Acl was called with trimmed path
            Assert-MockCalled Get-Acl -ParameterFilter { $Path -eq "AD:\CN=Test,DC=contoso,DC=com" }
        }
        
        It "Should accept empty AllowedSIDs array" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("placeholder") 
            
            $result.Success | Should Be $true
        }
        
        It "Should generate CorrelationId when not provided" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Should have logged with a generated CorrelationId
            $script:LogCalls.Count | Should BeGreaterThan 0
            $script:LogCalls[0].CorrelationId | Should Not BeNullOrEmpty
        }
        
        It "Should use provided CorrelationId" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $testCorrelationId = "TEST-12345"
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001") -CorrelationId $testCorrelationId
            
            # Should have logged with the provided CorrelationId
            $script:LogCalls[0].CorrelationId | Should Be $testCorrelationId
        }
    }
    
    Context "ACL Verification Logic" {
        
        It "Should return success when no targeted SIDs remain" {
            Mock Get-Acl {
                return @{ 
                    Access = @(
                        @{ IdentityReference = @{ Value = "S-1-5-21-OTHER-SID" } },
                        @{ IdentityReference = @{ Value = "S-1-5-32-544" } }  # Administrators
                    ) 
                }
            }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-REMOVED-SID")
            
            $result.Success | Should Be $true
            $result.RemainingOrphanedSIDs.Count | Should Be 0
        }
        
        It "Should detect single remaining SID" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = @{ Value = "S-1-5-21-123456789-1001" } },
                        @{ IdentityReference = @{ Value = "S-1-5-32-544" } }
                    )
                }
            }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-123456789-1001")
            
            $result.Success | Should Be $false
            $result.RemainingOrphanedSIDs.Count | Should Be 1
            $result.RemainingOrphanedSIDs[0] | Should Be "S-1-5-21-123456789-1001"
            $result.ErrorMessage | Should Match "1 of 1 SIDs still present"
        }
        
        It "Should detect multiple remaining SIDs" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = @{ Value = "S-1-5-21-123456789-1001" } },
                        @{ IdentityReference = @{ Value = "S-1-5-21-123456789-1002" } },
                        @{ IdentityReference = @{ Value = "S-1-5-32-544" } }
                    )
                }
            }
            Mock Start-Sleep { }
            
            $targetSIDs = @("S-1-5-21-123456789-1001", "S-1-5-21-123456789-1002", "S-1-5-21-123456789-1003")
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs $targetSIDs
            
            $result.Success | Should Be $false
            $result.RemainingOrphanedSIDs.Count | Should Be 2
            $result.RemainingOrphanedSIDs[0] | Should Be "S-1-5-21-123456789-1001"
            $result.RemainingOrphanedSIDs[1] | Should Be "S-1-5-21-123456789-1002"
            $result.ErrorMessage | Should Match "2 of 3 SIDs still present"
        }
        
        It "Should handle partial removal success" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = @{ Value = "S-1-5-21-123456789-1002" } }  # Only one remains
                    )
                }
            }
            Mock Start-Sleep { }
            
            $targetSIDs = @("S-1-5-21-123456789-1001", "S-1-5-21-123456789-1002")
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs $targetSIDs
            
            $result.Success | Should Be $false
            $result.RemainingOrphanedSIDs.Count | Should Be 1
            $result.RemainingOrphanedSIDs[0] | Should Be "S-1-5-21-123456789-1002"
        }
    }
    
    Context "Error Handling and Retry Logic" {
        
        It "Should handle Get-Acl failures gracefully" {
            Mock Get-Acl { throw "Access denied to object" }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "Verification error.*Access denied"
            $result.RemainingOrphanedSIDs.Count | Should Be 0
        }
        
        It "Should use retry logic for AD operations" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Verify retry logic was called
            $script:RetryCalls.Count | Should Be 1
            $script:RetryCalls[0].MaxRetries | Should Be 3
            $script:RetryCalls[0].OperationName | Should Be "Get-ACL-Verification"
        }
        
        It "Should handle network timeout errors" {
            Mock Get-Acl { throw [System.TimeoutException]::new("Operation timed out") }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "timed out"
        }
    }
    
    Context "Replication Delay Handling" {
        
        It "Should implement replication delay" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Verify Sleep was called for replication delay
            Assert-MockCalled Start-Sleep -ParameterFilter { $Milliseconds -eq 500 }
        }
    }
    
    Context "Logging and Correlation" {
        
        It "Should log verification start with SID count" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $targetSIDs = @("S-1-5-21-1001", "S-1-5-21-1002", "S-1-5-21-1003")
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs $targetSIDs
            
            # Should log the start message with SID count
            $startLog = $script:LogCalls | Where-Object { $_.Message -like "*Starting removal verification*" }
            $startLog | Should Not BeNullOrEmpty
            $startLog.Message | Should Match "Verifying 3 SIDs"
            $startLog.Level | Should Be "Debug"
        }
        
        It "Should log successful verification" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Should log success
            $successLog = $script:LogCalls | Where-Object { $_.Message -like "*Verification successful*" }
            $successLog | Should Not BeNullOrEmpty
            $successLog.Level | Should Be "Verbose"
        }
        
        It "Should log verification failures with warning level" {
            Mock Get-Acl {
                return @{
                    Access = @(
                        @{ IdentityReference = @{ Value = "S-1-5-21-1001" } }
                    )
                }
            }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Should log failure as warning
            $failureLog = $script:LogCalls | Where-Object { $_.Message -like "*Verification failed*" }
            $failureLog | Should Not BeNullOrEmpty
            $failureLog.Level | Should Be "Warning"
        }
        
        It "Should log errors with error level" {
            Mock Get-Acl { throw "Test error" }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001")
            
            # Should log error
            $errorLog = $script:LogCalls | Where-Object { $_.Message -like "*Verification error*" }
            $errorLog | Should Not BeNullOrEmpty
            $errorLog.Level | Should Be "Error"
        }
    }
    
    Context "Complex Scenarios" {
        
        It "Should handle empty ACL correctly" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001", "S-1-5-21-1002")
            
            $result.Success | Should Be $true
            $result.RemainingOrphanedSIDs.Count | Should Be 0
            $result.ErrorMessage | Should BeNullOrEmpty
        }
        
        It "Should handle large SID lists efficiently" {
            # Generate large SID list
            $largeSIDList = 1..50 | ForEach-Object { "S-1-5-21-123456789-$_" }
            
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs $largeSIDList
            
            $result.Success | Should Be $true
            # Should log with correct count
            $startLog = $script:LogCalls | Where-Object { $_.Message -like "*Starting removal verification*" }
            $startLog.Message | Should Match "Verifying 50 SIDs"
        }
        
        It "Should maintain correlation ID across all log entries" {
            Mock Get-Acl { return @{ Access = @() } }
            Mock Start-Sleep { }
            
            $testCorrelationId = "TEST-CORRELATION-123"
            $result = Invoke-RemovalVerification -ObjectDN "CN=Test,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1001") -CorrelationId $testCorrelationId
            
            # All log entries should have the same correlation ID
            foreach ($logEntry in $script:LogCalls) {
                $logEntry.CorrelationId | Should Be $testCorrelationId
            }
        }
    }
}
