#Requires -Version 5.1

# Import required classes first
. "$PSScriptRoot\..\..\..\..\Classes\RemovalOperationResult.ps1"

# Import logging functions
. "$PSScriptRoot\..\..\..\..\Private\Logging\Format-LogMessage.ps1"
. "$PSScriptRoot\..\..\..\..\Private\Logging\Write-StructuredLog.ps1"
. "$PSScriptRoot\..\..\..\..\Private\Logging\Write-StructuredLogEntry.ps1"
. "$PSScriptRoot\..\..\..\..\Private\Logging\Write-RemovalSecurityLog.ps1"

# Import ACL functions
. "$PSScriptRoot\..\..\..\..\Private\ACL\Get-ACLForRemoval.ps1"
. "$PSScriptRoot\..\..\..\..\Private\ACL\Invoke-SIDRemoval.ps1"
. "$PSScriptRoot\..\..\..\..\Private\ACL\Set-ModifiedACL.ps1"

# Import Security functions
. "$PSScriptRoot\..\..\..\..\Private\Security\Invoke-RemovalVerification.ps1"

# Import Backup functions
. "$PSScriptRoot\..\..\..\..\Private\Backup\New-ACLBackup.ps1"

# Import the function under test (depends on all above functions)
. "$PSScriptRoot\..\..\..\..\Private\Operations\Invoke-RemovalWorkflow.ps1"

Describe "Invoke-RemovalWorkflow" -Tag "Unit", "Operations" {
    
    # Create stub functions for mocking
    function Invoke-SecurityValidation { }
    
    # Mock all external dependencies
    Mock Write-StructuredLog { }
    Mock Write-RemovalSecurityLog { }
    Mock Get-ACLForRemoval { 
        return @{
            Owner = "DOMAIN\TestUser"
            Access = @(
                @{ IdentityReference = "S-1-5-21-1234567890-1001"; AccessControlType = "Allow" }
                @{ IdentityReference = "S-1-5-21-1234567890-1002"; AccessControlType = "Allow" }
            )
        }
    }

    Mock Invoke-SecurityValidation {
        return @{
            IsValid = $true
            RiskLevel = "Low"
            AllowedSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
            BlockedSIDs = @()
            Issues = @()
        }
    }

    Mock New-ACLBackup { return $true }

    Mock Invoke-SIDRemoval {
        return @{
            RemovedSIDs = @("S-1-5-21-1234567890-1001")
            FailedSIDs = @()
            ModifiedACL = @{ Modified = $true }
        }
    }

    Mock Set-ModifiedACL { return $true }

    Mock Invoke-RemovalVerification {
        return @{
            Success = $true
            ErrorMessage = $null
            RemainingOrphanedSIDs = @()
        }
    }
    
    Context "Parameter Validation" {
        It "Should accept valid parameters" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "RemovalOperationResult"
        }
        
        It "Should generate CorrelationId when not provided" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }
        
        It "Should accept custom CorrelationId" {
            $customId = [System.Guid]::NewGuid().ToString()
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") -CorrelationId $customId
            $result.CorrelationId | Should Be $customId
        }
    }
    
    Context "Successful Workflow Execution" {
        It "Should complete full workflow successfully" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=TestUser,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
            
            $result.Success | Should Be $true
            $result.ObjectDN | Should Be "CN=TestUser,DC=domain,DC=com"
            $result.IntendedRemovals | Should Be 2
            $result.ActualRemovals | Should Be 1
            $result.FailedRemovals | Should Be 0
            $result.ProcessingTime | Should Not BeNullOrEmpty
        }
        
        It "Should initialize result object properly" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.ObjectDN | Should Be "CN=Test,DC=domain,DC=com"
            $result.IntendedRemovals | Should Be 1
            $result.CorrelationId | Should Not BeNullOrEmpty
        }
        
        It "Should handle multiple SIDs correctly" {
            $sids = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002", "S-1-5-21-1234567890-1003")
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs $sids
            
            $result.IntendedRemovals | Should Be 3
            $result.Success | Should Be $true
        }
        
        It "Should measure processing time accurately" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.ProcessingTime | Should Not BeNullOrEmpty
            $result.ProcessingTime.GetType().Name | Should Be "TimeSpan"
        }
    }
    
    Context "Security Validation Handling" {
        It "Should stop workflow when security validation fails" {
            Mock Invoke-SecurityValidation {
                return @{
                    IsValid = $false
                    RiskLevel = "High"
                    AllowedSIDs = @()
                    BlockedSIDs = @("S-1-5-21-1234567890-1001")
                    Issues = @("SID is protected system account")
                }
            }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "Security validation failed"
            $result.BlockedSIDs.Count | Should Be 1
        }
        
        It "Should include security validation results in response" {
            Mock Invoke-SecurityValidation {
                return @{
                    IsValid = $true
                    RiskLevel = "Medium"
                    AllowedSIDs = @("S-1-5-21-1234567890-1001")
                    BlockedSIDs = @("S-1-5-21-1234567890-1002")
                    Issues = @()
                }
            }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
            
            $result.SecurityValidation | Should Not BeNullOrEmpty
            $result.SecurityValidation.RiskLevel | Should Be "Medium"
            $result.BlockedSIDs.Count | Should Be 1
        }
    }
    
    Context "Error Handling and Recovery" {
        It "Should handle ACL retrieval failures" {
            Mock Get-ACLForRemoval { throw "Access denied" }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "Access denied"
        }
        
        It "Should handle SID removal failures" {
            # Reset all mocks to defaults first
            Mock Write-StructuredLog { }
            Mock Write-RemovalSecurityLog { }
            Mock Get-ACLForRemoval { 
                return @{
                    Owner = "DOMAIN\TestUser"
                    Access = @(
                        @{ IdentityReference = "S-1-5-21-1234567890-1001"; AccessControlType = "Allow" }
                        @{ IdentityReference = "S-1-5-21-1234567890-1002"; AccessControlType = "Allow" }
                    )
                }
            }
            Mock Invoke-SecurityValidation {
                return @{
                    IsValid = $true
                    RiskLevel = "Low"
                    AllowedSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
                    BlockedSIDs = @()
                    Issues = @()
                }
            }
            Mock New-ACLBackup { return $true }
            Mock Set-ModifiedACL { return $true }
            Mock Invoke-RemovalVerification {
                return @{
                    Success = $true
                    ErrorMessage = $null
                    RemainingOrphanedSIDs = @()
                }
            }
            
            # Now override the specific mock for this test
            Mock Invoke-SIDRemoval { throw "SID removal error" }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "SID removal error"
        }
        
        It "Should handle ACL application failures" {
            # Reset all mocks to defaults first
            Mock Write-StructuredLog { }
            Mock Write-RemovalSecurityLog { }
            Mock Get-ACLForRemoval { 
                return @{
                    Owner = "DOMAIN\TestUser"
                    Access = @(
                        @{ IdentityReference = "S-1-5-21-1234567890-1001"; AccessControlType = "Allow" }
                        @{ IdentityReference = "S-1-5-21-1234567890-1002"; AccessControlType = "Allow" }
                    )
                }
            }
            Mock Invoke-SecurityValidation {
                return @{
                    IsValid = $true
                    RiskLevel = "Low"
                    AllowedSIDs = @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
                    BlockedSIDs = @()
                    Issues = @()
                }
            }
            Mock New-ACLBackup { return $true }
            Mock Invoke-SIDRemoval {
                return @{
                    RemovedSIDs = @("S-1-5-21-1234567890-1001")
                    FailedSIDs = @()
                    ModifiedACL = @{ Modified = $true }
                }
            }
            Mock Invoke-RemovalVerification {
                return @{
                    Success = $true
                    ErrorMessage = $null
                    RemainingOrphanedSIDs = @()
                }
            }
            
            # Now override the specific mock for this test
            Mock Set-ModifiedACL { return $false }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Be "Failed to apply ACL changes"
        }
    }
    
    Context "Integration with Dependencies" {
        It "Should handle partial SID removal results correctly" {
            Mock Invoke-SIDRemoval {
                return @{
                    RemovedSIDs = @("S-1-5-21-1234567890-1001")
                    FailedSIDs = @("S-1-5-21-1234567890-1002")
                    ModifiedACL = @{ Modified = $true }
                }
            }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001", "S-1-5-21-1234567890-1002")
            
            $result.ActualRemovals | Should Be 1
            $result.FailedRemovals | Should Be 1
            $result.RemovedSIDs.Count | Should Be 1
            $result.FailedSIDs.Count | Should Be 1
        }
    }
    
    Context "WhatIf Mode Functionality" {
        It "Should support WhatIf preference" {
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001") -WhatIf
            
            # In WhatIf mode, the function should not throw errors
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle no changes scenario gracefully" {
            Mock Invoke-SIDRemoval {
                return @{
                    RemovedSIDs = @()
                    FailedSIDs = @()
                    ModifiedACL = @{ Modified = $false }
                }
            }
            
            $result = Invoke-RemovalWorkflow -ObjectDistinguishedName "CN=Test,DC=domain,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")
            
            $result.Success | Should Be $true
            $result.ActualRemovals | Should Be 0
        }
    }
}
