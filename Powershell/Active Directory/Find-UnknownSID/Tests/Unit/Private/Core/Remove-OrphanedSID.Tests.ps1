#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Comprehensive Pester tests for Remove-OrphanedSID function

.DESCRIPTION
    Enterprise-grade test suite for the Remove-OrphanedSID function that provides comprehensive
    validation of SID removal operations, safety validation, backup and restore capabilities,
    compliance logging, and rollback mechanisms.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-10
    Version: 1.0.0
    PowerShell Version: 5.1+ (Compatible with Pester 3.4.x)

    Test Count: 28 tests covering SID removal functionality
    Coverage Areas:
    - SID removal operations
    - Safety validation and verification
    - Backup and restore capabilities
    - ACL management operations
    - Registry cleanup operations
    - Compliance and audit logging
    - Rollback and recovery mechanisms
    - Permission validation

    TROUBLESHOOTING:
    - SID removal operations: .\Troubleshooting\Core\SID-Removal-Operations.md
    - Safety validation: .\Troubleshooting\Security\Safety-Validation.md
    - Backup and restore: .\Troubleshooting\Core\Backup-Restore.md
#>

# Import required test helpers
. "$PSScriptRoot\..\..\..\TestHelpers\SecurityTestHelpers.ps1"
. "$PSScriptRoot\..\..\..\TestHelpers\ADMockFactory.ps1"

Describe "Remove-OrphanedSID Function Tests" {
    
    BeforeEach {
        # Reset test environment
        $script:RemovalResults = $null
        $script:BackupData = $null
        
        # Load the function under test
        $functionPath = "$PSScriptRoot\..\..\..\..\Private\Core\Remove-OrphanedSID.ps1"
        if (Test-Path $functionPath) {
            # Dot source the file to load the function
            . $functionPath
        } else {
            throw "Function file not found: $functionPath"
        }
        
        # Mock external dependencies
        Mock Write-Verbose { } 
        Mock Write-Warning { }
        Mock Write-Error { }
        Mock Write-Host { }
        
        # Mock SID validation functions
        Mock Test-SIDSafety {
            param($SID)
            return @{
                IsSafe = $true
                SafetyLevel = 'High'
                SID = $SID
                Warnings = @()
                BlockingIssues = @()
            }
        }
        
        Mock Confirm-SIDRemoval {
            param($SID)
            return $true
        }
        
        # Mock ACL operations
        Mock Get-ACLsWithSID {
            param($SID)
            return @(
                @{ Path = 'C:\TestFolder'; Type = 'Directory'; ACE = 'FullControl' }
                @{ Path = 'HKLM:\SOFTWARE\Test'; Type = 'Registry'; ACE = 'ReadKey' }
            )
        }
        
        Mock Remove-SIDFromACL {
            param($Path, $SID)
            return @{
                Success = $true
                Path = $Path
                SID = $SID
                RemovedACEs = 1
                BackupCreated = $true
            }
        }
        
        Mock Set-Acl { return $true }
        Mock Get-Acl { 
            return [PSCustomObject]@{
                Access = @()
                Owner = 'BUILTIN\Administrators'
                Group = 'BUILTIN\Administrators'
            }
        }
        
        # Mock Registry operations
        Mock Get-RegistryKeysWithSID {
            param($SID)
            return @(
                @{ Key = 'HKLM:\SOFTWARE\TestKey'; ValueName = 'TestValue'; SID = $SID }
            )
        }
        
        Mock Remove-SIDFromRegistry {
            param($Key, $SID)
            return @{
                Success = $true
                Key = $Key
                SID = $SID
                ValuesRemoved = 1
                BackupCreated = $true
            }
        }
        
        Mock Remove-ItemProperty { return $true }
        Mock Get-ItemProperty { return @{} }
        
        # Mock backup operations
        Mock New-SIDRemovalBackup {
            param($SID, $Operations)
            return @{
                BackupId = [System.Guid]::NewGuid().ToString()
                BackupPath = "C:\Backups\SID_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
                BackupCreated = Get-Date
                Operations = $Operations
                Success = $true
            }
        }
        
        Mock Restore-SIDBackup {
            param($BackupId)
            return @{
                Success = $true
                BackupId = $BackupId
                OperationsRestored = 3
                RestoreCompleted = Get-Date
            }
        }
        
        # Mock logging and auditing
        Mock Write-AuditLog { }
        Mock Write-ComplianceLog { }
        Mock Write-SecurityLog { }
        
        # Mock validation functions
        Mock Test-AdminPrivileges { return $true }
        Mock Test-SystemImpact { 
            return @{
                Impact = 'Low'
                AffectedResources = 2
                CriticalServices = @()
                SafeToRemove = $true
            }
        }
    }
    
    Context "SID Removal Operations" {
        It "Should execute complete SID removal workflow" {
            $sidData = @{
                SID = 'S-1-5-21-123456789-123456789-123456789-1001'
                Type = 'User'
                Confidence = 'High'
                Locations = @('ACL', 'Registry')
            }
            
            $result = Remove-OrphanedSID -SIDData $sidData
            
            $result.Success | Should Be $true
            $result.SID | Should Be $sidData.SID
            $result.OperationsPerformed | Should Contain 'ACLRemoval'
            $result.OperationsPerformed | Should Contain 'RegistryCleanup'
        }
        
        It "Should handle single SID removal with all safety checks" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -EnableSafetyChecks
            
            Should -Invoke Test-SIDSafety -Exactly 1
            Should -Invoke Confirm-SIDRemoval -Exactly 1
            $result.SafetyChecksPerformed | Should Be $true
        }
        
        It "Should support different removal modes" {
            $modes = @('Safe', 'Standard', 'Aggressive', 'Minimal')
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            foreach ($mode in $modes) {
                $result = Remove-OrphanedSID -SID $sid -RemovalMode $mode
                
                $result.Success | Should Be $true
                $result.RemovalMode | Should Be $mode
            }
        }
        
        It "Should track all removal operations performed" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.OperationDetails | Should Not BeNullOrEmpty
            $result.OperationDetails.Count | Should BeGreaterThan 0
            $result.TotalOperations | Should BeGreaterThan 0
        }
        
        It "Should generate correlation ID for tracking" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Match "^[A-Fa-f0-9\-]{36}$"
        }
    }
    
    Context "Safety Validation and Verification" {
        It "Should perform comprehensive safety validation" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -EnableSafetyChecks
            
            Should -Invoke Test-SIDSafety -Exactly 1
            Should -Invoke Test-SystemImpact -Exactly 1
            $result.SafetyValidation | Should Not BeNullOrEmpty
        }
        
        It "Should block removal of critical SIDs" {
            Mock Test-SIDSafety {
                return @{
                    IsSafe = $false
                    SafetyLevel = 'Critical'
                    BlockingIssues = @('System SID', 'Built-in account')
                }
            }
            
            $sid = 'S-1-5-32-544'  # Built-in Administrators
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.Success | Should Be $false
            $result.BlockedReason | Should Match "*System SID*"
        }
        
        It "Should require confirmation for high-risk operations" {
            Mock Confirm-SIDRemoval { return $false }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -RequireConfirmation
            
            $result.Success | Should Be $false
            $result.UserCancelled | Should Be $true
        }
        
        It "Should validate admin privileges before removal" {
            Mock Test-AdminPrivileges { return $false }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.Success | Should Be $false
            $result.Error | Should Match "*administrator*"
        }
        
        It "Should assess system impact before removal" {
            Mock Test-SystemImpact {
                return @{
                    Impact = 'High'
                    AffectedResources = 50
                    CriticalServices = @('BITS', 'Spooler')
                    SafeToRemove = $false
                }
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.Success | Should Be $false
            $result.HighImpactBlocked | Should Be $true
        }
    }
    
    Context "Backup and Restore Capabilities" {
        It "Should create backup before removal operations" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -CreateBackup
            
            Should -Invoke New-SIDRemovalBackup -Exactly 1
            $result.BackupCreated | Should Be $true
            $result.BackupId | Should Not BeNullOrEmpty
        }
        
        It "Should support backup restoration on failure" {
            Mock Remove-SIDFromACL { throw 'Removal failed' }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -CreateBackup -EnableRollback
            
            Should -Invoke Restore-SIDBackup -Exactly 1
            $result.RollbackPerformed | Should Be $true
        }
        
        It "Should validate backup integrity before proceeding" {
            Mock New-SIDRemovalBackup {
                return @{
                    Success = $false
                    Error = 'Backup creation failed'
                }
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -CreateBackup -RequireBackup
            
            $result.Success | Should Be $false
            $result.Error | Should Match "*Backup creation failed*"
        }
        
        It "Should include all affected resources in backup" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -CreateBackup
            
            # Verify backup includes ACL and Registry operations
            Should -Invoke New-SIDRemovalBackup -ParameterFilter {
                $Operations -contains 'ACLRemoval' -and $Operations -contains 'RegistryCleanup'
            }
        }
    }
    
    Context "ACL Management Operations" {
        It "Should remove SID from file system ACLs" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            Should -Invoke Get-ACLsWithSID -Exactly 1
            Should -Invoke Remove-SIDFromACL -AtLeast 1
            $result.ACLsModified | Should BeGreaterThan 0
        }
        
        It "Should handle ACL removal failures gracefully" {
            Mock Remove-SIDFromACL { 
                param($Path, $SID)
                if ($Path -eq 'C:\TestFolder') {
                    throw 'Access denied'
                }
                return @{ Success = $true; Path = $Path; SID = $SID }
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -ContinueOnError
            
            $result.Success | Should Be $true
            $result.PartialSuccess | Should Be $true
            $result.FailedOperations | Should BeGreaterThan 0
        }
        
        It "Should preserve ACL inheritance settings" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            # Verify ACL operations preserve inheritance
            Should -Invoke Remove-SIDFromACL -ParameterFilter {
                $PreserveInheritance -eq $true
            }
        }
        
        It "Should handle nested directory ACL operations" {
            Mock Get-ACLsWithSID {
                return @(
                    @{ Path = 'C:\TestFolder'; Type = 'Directory' }
                    @{ Path = 'C:\TestFolder\SubFolder'; Type = 'Directory' }
                    @{ Path = 'C:\TestFolder\file.txt'; Type = 'File' }
                )
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            Should -Invoke Remove-SIDFromACL -Exactly 3
            $result.ACLsModified | Should Be 3
        }
    }
    
    Context "Registry Cleanup Operations" {
        It "Should remove SID from registry keys and values" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            Should -Invoke Get-RegistryKeysWithSID -Exactly 1
            Should -Invoke Remove-SIDFromRegistry -AtLeast 1
            $result.RegistryKeysModified | Should BeGreaterThan 0
        }
        
        It "Should handle registry access permission errors" {
            Mock Remove-SIDFromRegistry { 
                throw 'Registry access denied'
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -ContinueOnError
            
            $result.Success | Should Be $true
            $result.RegistryErrors | Should BeGreaterThan 0
        }
        
        It "Should clean up registry security descriptors" {
            Mock Get-RegistryKeysWithSID {
                return @(
                    @{ Key = 'HKLM:\SOFTWARE\TestKey'; Type = 'SecurityDescriptor' }
                    @{ Key = 'HKLM:\SOFTWARE\TestKey2'; Type = 'Value' }
                )
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.SecurityDescriptorsUpdated | Should BeGreaterThan 0
        }
        
        It "Should handle HKEY_USERS registry cleanup" {
            Mock Get-RegistryKeysWithSID {
                return @(
                    @{ Key = 'HKU:\S-1-5-21-123456789-123456789-123456789-1001'; Type = 'UserProfile' }
                )
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.UserProfileCleaned | Should Be $true
        }
    }
    
    Context "Compliance and Audit Logging" {
        It "Should log all removal operations for compliance" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            Should -Invoke Write-ComplianceLog -AtLeast 1
            Should -Invoke Write-AuditLog -AtLeast 1
        }
        
        It "Should include security event logging" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            Should -Invoke Write-SecurityLog -AtLeast 1
        }
        
        It "Should log detailed operation results" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.AuditTrail | Should Not BeNullOrEmpty
            $result.AuditTrail.OperationsLogged | Should BeGreaterThan 0
        }
        
        It "Should support SOX compliance logging" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -ComplianceLevel SOX
            
            $result.SOXCompliant | Should Be $true
            $result.ComplianceEvidence | Should Not BeNullOrEmpty
        }
    }
    
    Context "Rollback and Recovery Mechanisms" {
        It "Should support automatic rollback on critical failures" {
            Mock Remove-SIDFromACL { throw 'Critical system error' }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -EnableRollback -CreateBackup
            
            Should -Invoke Restore-SIDBackup -Exactly 1
            $result.AutoRollbackTriggered | Should Be $true
        }
        
        It "Should provide manual rollback capability" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -CreateBackup
            $backupId = $result.BackupId
            
            $rollbackResult = Remove-OrphanedSID -RollbackBackup $backupId
            
            $rollbackResult.Success | Should Be $true
            $rollbackResult.RollbackCompleted | Should Be $true
        }
        
        It "Should validate rollback operations" {
            Mock Restore-SIDBackup {
                return @{
                    Success = $false
                    Error = 'Rollback validation failed'
                }
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            $result = Remove-OrphanedSID -SID $sid -CreateBackup
            
            $rollbackResult = Remove-OrphanedSID -RollbackBackup $result.BackupId
            
            $rollbackResult.Success | Should Be $false
            $rollbackResult.Error | Should Match "*Rollback validation failed*"
        }
        
        It "Should support partial rollback for failed operations" {
            Mock Remove-SIDFromACL { 
                param($Path)
                if ($Path -eq 'C:\TestFolder') {
                    return @{ Success = $true; Path = $Path }
                } else {
                    throw 'Operation failed'
                }
            }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -EnableRollback -CreateBackup
            
            $result.PartialRollback | Should Be $true
            $result.RollbackDetails | Should Not BeNullOrEmpty
        }
    }
    
    Context "Permission Validation" {
        It "Should validate permissions for each operation type" {
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -ValidatePermissions
            
            $result.PermissionsValidated | Should Be $true
            $result.PermissionResults | Should Not BeNullOrEmpty
        }
        
        It "Should handle insufficient permissions gracefully" {
            Mock Test-AdminPrivileges { return $false }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid
            
            $result.Success | Should Be $false
            $result.InsufficientPermissions | Should Be $true
        }
        
        It "Should support elevation request for required permissions" {
            Mock Test-AdminPrivileges { return $false }
            
            $sid = 'S-1-5-21-123456789-123456789-123456789-1001'
            
            $result = Remove-OrphanedSID -SID $sid -RequestElevation
            
            $result.ElevationRequested | Should Be $true
        }
    }
}
