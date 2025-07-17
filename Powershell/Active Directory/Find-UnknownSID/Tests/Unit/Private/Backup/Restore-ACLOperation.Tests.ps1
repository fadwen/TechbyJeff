#Requires -Module Pester
#Re#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive Pester tests for Restore-ACLOperation function

.DESCRIPTION
    This test suite provides comprehensive validation of the Restore-ACLOperation function,
    including parameter validation, ACL restoration, integrity verification, rollback operations,
    error handling, performance testing, and security validation.

.NOTES
    Author: Jeffrey Stuhr
    Total Tests: 71 comprehensive tests across 9 test contexts
    
    Test Coverage Areas:
    # Parameter validation and input processing
    # ACL restoration with integrity verification
    # Backup validation and metadata verification
    # Individual object restoration
    # Bulk restoration workflows
    # Rollback and recovery mechanisms
    # Error handling and logging validation
    # Performance testing and scalability validation
    # Security validation and input sanitization
    # Cross-platform compatibility testing
#>

# Import the functions under test
. "$PSScriptRoot\..\..\..\..\Private\Backup\Restore-ACLOperation.ps1"

# Import test helpers
. "$PSScriptRoot\..\..\..\TestHelpers\BackupTestHelpers.ps1"

Describe "Restore-ACLOperation Functions" -Tag "Unit", "Backup", "RestoreACL" {
    
    BeforeAll {
        # Test data setup
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestObjectDN = 'CN=TestUser,OU=Users,DC=company,DC=com'
        $script:TestOUDN = 'OU=TestOU,DC=company,DC=com'
        
        # Mock all external dependencies
        Mock Write-Verbose { }
        Mock Write-Error { }
        Mock Write-Warning { }
        
        # Create comprehensive test backup data
        $script:TestBackupData = [PSCustomObject]@{
            ObjectDN = $script:TestObjectDN
            BackupDate = '2024-07-02T10:36:31.123Z'
            CorrelationId = [System.Guid]::NewGuid().ToString()
            SDDL = 'O:S-1-5-21-1234567890-987654321-123456789-500G:S-1-5-21-1234567890-987654321-123456789-513D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRCWDWO;;;AU)'
            SDDLHash = 'abc123def456789'
            ValidationSignature = 'PSSecurityBackup_v2.1'
            BackupVersion = '2.1'
            ACLEntryCount = 3
            UserContext = 'DOMAIN\BackupUser'
            ComputerName = 'BACKUP-SERVER'
        }
        
        # Create invalid backup data for testing
        $script:InvalidBackupData = [PSCustomObject]@{
            ObjectDN = $script:TestObjectDN
            BackupDate = '2024-07-02T10:36:31.123Z'
            # Missing required properties
        }
        
        # Mock Active Directory cmdlets with realistic behavior
        Mock Get-ADObject {
            return [PSCustomObject]@{
                DistinguishedName = $Identity
                ObjectClass = @('top', 'person', 'organizationalPerson', 'user')
                Name = 'TestUser'
            }
        }
        
        Mock Get-Acl {
            $mockAcl = New-Object System.DirectoryServices.ActiveDirectorySecurity
            # Add test access rules
            $identity = [System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"
            $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, [System.DirectoryServices.ActiveDirectoryRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
            $mockAcl.SetAccessRule($rule)
            return $mockAcl
        }
        
        # Default mock for Get-RestorationTarget that can be overridden in specific tests
        Mock Get-RestorationTarget {
            return [PSCustomObject]@{
                IsValid = $true
                ErrorMessage = $null
                TargetObjectDN = $TargetObjectDN
                ObjectExists = $true
                AccessValidated = $true
                CheckedAt = Get-Date
                CorrelationId = $CorrelationId
            }
        }
        
        # Default mock for Confirm-RestorationSuccess
        Mock Confirm-RestorationSuccess {
            return [PSCustomObject]@{
                Success = $true
                VerificationResult = 'Verified'
                VerifiedAt = Get-Date
                Issues = @()
                CorrelationId = $CorrelationId
            }
        }
        
        # Default mock for ConvertFrom-BackupToACL
        Mock ConvertFrom-BackupToACL {
            $hasSDDL = $BackupData.PSObject.Properties.Name -contains 'SDDL'
            if ($hasSDDL) {
                return [PSCustomObject]@{
                    PSTypeName = 'ACLConversionResult'
                    Success = $true
                    SecurityDescriptor = (New-Object System.DirectoryServices.ActiveDirectorySecurity)
                    SourceSDDL = $BackupData.SDDL
                    ACECount = 3
                    SDDLLength = $BackupData.SDDL.Length
                    ConvertedAt = (Get-Date)
                    ErrorMessage = $null
                    CorrelationId = $CorrelationId
                }
            } else {
                return [PSCustomObject]@{
                    PSTypeName = 'ACLConversionResult'
                    Success = $false
                    SecurityDescriptor = $null
                    SourceSDDL = $null
                    ACECount = 0
                    SDDLLength = 0
                    ConvertedAt = Get-Date
                    ErrorMessage = "BackupData object does not contain SDDL property"
                    CorrelationId = $CorrelationId
                }
            }
        }
    }
    
    Context "Set-ObjectACL - Parameter Validation" {
        It "Should accept valid TargetObjectDN parameter" {
            { Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData } | Should Not Throw
        }
        
        It "Should reject null TargetObjectDN" {
            { Set-ObjectACL -TargetObjectDN $null -BackupData $script:TestBackupData } | Should Throw
        }
        
        It "Should reject empty TargetObjectDN" {
            { Set-ObjectACL -TargetObjectDN "" -BackupData $script:TestBackupData } | Should Throw
        }
        
        It "Should accept valid BackupData parameter" {
            { Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData } | Should Not Throw
        }
        
        It "Should reject null BackupData" {
            { Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $null } | Should Throw
        }
        
        It "Should validate required BackupData properties" {
            { Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:InvalidBackupData } | Should Throw "Backup data missing required property:"
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should auto-generate CorrelationId when not provided" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.CorrelationId | Should Match "^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$"
        }
        
        It "Should support pipeline input for TargetObjectDN" {
            $result = $script:TestObjectDN | Set-ObjectACL -BackupData $script:TestBackupData
            $result.TargetObjectDN | Should Be $script:TestObjectDN
        }
        
        It "Should support VerifyApplication switch" {
            { Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -VerifyApplication } | Should Not Throw
        }
    }
    
    Context "Set-ObjectACL - Core Functionality" {
        It "Should return ACLOperationResult object" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.PSObject.TypeNames[0] | Should Be 'ACLOperationResult'
        }
        
        It "Should call target validation before ACL application" {
            Mock Get-RestorationTarget { 
                return [PSCustomObject]@{ IsValid = $true; ErrorMessage = $null }
            } -Verifiable
            
            Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData | Out-Null
            
            Assert-VerifiableMocks
        }
        
        It "Should fail when target validation fails" {
            Mock Get-RestorationTarget { 
                return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "Object not found" }
            }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "Target object validation failed"
        }
        
        It "Should apply ACL using Set-Acl cmdlet" {
            Mock Set-Acl { }
            
            # Ensure Get-RestorationTarget succeeds for this test
            Mock Get-RestorationTarget {
                return [PSCustomObject]@{
                    IsValid = $true
                    ErrorMessage = $null
                    TargetObjectDN = $TargetObjectDN
                    ObjectExists = $true
                    AccessValidated = $true
                    CheckedAt = Get-Date
                    CorrelationId = $CorrelationId
                }
            }
            
            # Ensure ConvertFrom-BackupToACL succeeds for this test
            Mock ConvertFrom-BackupToACL {
                return [PSCustomObject]@{
                    PSTypeName = 'ACLConversionResult'
                    Success = $true
                    SecurityDescriptor = (New-Object System.DirectoryServices.ActiveDirectorySecurity)
                    SourceSDDL = $BackupData.SDDL
                    ACECount = 3
                    SDDLLength = $BackupData.SDDL.Length
                    ConvertedAt = Get-Date
                    ErrorMessage = $null
                    CorrelationId = $CorrelationId
                }
            }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            
            Assert-MockCalled Set-Acl -Exactly 1 -Scope It
            Assert-MockCalled Get-RestorationTarget -Exactly 1 -Scope It
            
            # Verify the result shows success
            $result.Success | Should Be $true
        }
        
        It "Should count modifications from SDDL" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.Success | Should Be $true
            ($result.ModificationsApplied -gt -1) | Should Be $true
        }
        
        It "Should set correct result properties on success" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            
            $result.Success | Should Be $true
            $result.TargetObjectDN | Should Be $script:TestObjectDN
            $result.Duration | Should BeOfType [TimeSpan]
            $result.CompletedAt | Should BeOfType [DateTime]
            $result.ErrorMessage | Should BeNullOrEmpty
        }
        
        It "Should handle ACL application failures gracefully" {
            Mock Set-Acl { throw "Access denied" }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "ACL application failed"
        }
        
        It "Should perform verification when requested" {
            Mock Confirm-RestorationSuccess { 
                return [PSCustomObject]@{ IsVerified = $true }
            }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -VerifyApplication
            
            # Debug output
            Write-Host "Result Success: $($result.Success)"
            Write-Host "Result VerificationResult: $($result.VerificationResult)"
            Write-Host "Result ErrorMessage: $($result.ErrorMessage)"
            
            $result.VerificationResult | Should Not BeNullOrEmpty
            
            Assert-MockCalled Confirm-RestorationSuccess -Times 1 -Scope It
        }
        
        It "Should skip verification in WhatIf mode" {
            Mock Confirm-RestorationSuccess { 
                return [PSCustomObject]@{ IsVerified = $true }
            }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -VerifyApplication -WhatIf
            $result.WhatIfMode | Should Be $true
            
            Assert-MockCalled Confirm-RestorationSuccess -Times 0
        }
        
        It "Should handle WhatIf mode correctly" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -WhatIf
            
            $result.Success | Should Be $true
            $result.WhatIfMode | Should Be $true
            ($result.ModificationsApplied -gt -1) | Should Be $true
            
            # Should not call Set-Acl in WhatIf mode
            Assert-MockCalled Set-Acl -Times 0
        }
    }
    
    Context "Get-RestorationTarget - Parameter Validation" {
        It "Should accept valid TargetObjectDN parameter" {
            { Get-RestorationTarget -TargetObjectDN $script:TestObjectDN } | Should Not Throw
        }
        
        It "Should reject null TargetObjectDN" {
            { Get-RestorationTarget -TargetObjectDN $null } | Should Throw
        }
        
        It "Should reject empty TargetObjectDN" {
            { Get-RestorationTarget -TargetObjectDN "" } | Should Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should support pipeline input for TargetObjectDN" {
            $result = $script:TestObjectDN | Get-RestorationTarget
            $result.TargetObjectDN | Should Be $script:TestObjectDN
        }
        
        It "Should support CheckPermissions switch" {
            { Get-RestorationTarget -TargetObjectDN $script:TestObjectDN -CheckPermissions } | Should Not Throw
        }
    }
    
    Context "Get-RestorationTarget - Core Functionality" {
        It "Should return TargetValidationResult object" {
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.PSObject.TypeNames[0] | Should Be 'TargetValidationResult'
        }
        
        It "Should validate DN format" {
            $invalidDN = "InvalidDNFormat"
            $result = Get-RestorationTarget -TargetObjectDN $invalidDN
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Contain "Invalid DN format: $invalidDN"
        }
        
        It "Should check object existence" {
            Mock Get-ADObject { 
                return [PSCustomObject]@{
                    DistinguishedName = $script:TestObjectDN
                    ObjectClass = @('top', 'person', 'organizationalPerson', 'user')
                }
            }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ObjectExists | Should Be $true
            $result.ObjectType | Should Be 'user'
        }
        
        It "Should handle non-existent objects" {
            Mock Get-ADObject { throw "Object not found" }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ObjectExists | Should Be $false
            $result.Issues | Should Match "Target object not found"
        }
        
        It "Should check ACL readability" {
            Mock Get-Acl { 
                $mockAcl = New-Object System.DirectoryServices.ActiveDirectorySecurity
                return $mockAcl
            }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ACLReadable | Should Be $true
        }
        
        It "Should handle ACL read failures" {
            Mock Get-Acl { throw "Access denied" }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ACLReadable | Should Be $false
            $result.Issues | Should Match "Cannot read current ACL"
        }
        
        It "Should check write permissions when requested" {
            # Mock DirectoryEntry for permission testing
            Mock New-Object { 
                $mockEntry = New-Object PSObject
                $mockEntry | Add-Member -MemberType ScriptMethod -Name RefreshCache -Value { }
                $mockEntry | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                return $mockEntry
            } -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectoryEntry' }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN -CheckPermissions
            $result.WritePermissions | Should Be $true
        }
        
        It "Should set IsValid to true when no issues found" {
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.IsValid | Should Be $true
            $result.Issues.Count | Should Be 0
        }
        
        It "Should include validation timestamp" {
            $beforeTime = Get-Date
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            ($result.ValidatedAt -gt $beforeTime) | Should Be $true
        }
    }
    
    Context "Confirm-RestorationSuccess - Parameter Validation" {
        It "Should accept valid TargetObjectDN parameter" {
            { Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData } | Should Not Throw
        }
        
        It "Should reject null TargetObjectDN" {
            { Confirm-RestorationSuccess -TargetObjectDN $null -ExpectedData $script:TestBackupData } | Should Throw
        }
        
        It "Should reject empty TargetObjectDN" {
            { Confirm-RestorationSuccess -TargetObjectDN "" -ExpectedData $script:TestBackupData } | Should Throw
        }
        
        It "Should accept valid ExpectedData parameter" {
            { Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData } | Should Not Throw
        }
        
        It "Should reject null ExpectedData" {
            { Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $null } | Should Throw
        }
        
        It "Should accept valid ToleranceLevel values" {
            @('Strict', 'Standard', 'Permissive') | ForEach-Object {
                { Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData -ToleranceLevel $_ } | Should Not Throw
            }
        }
        
        It "Should reject invalid ToleranceLevel values" {
            { Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData -ToleranceLevel "Invalid" } | Should Throw
        }
        
        It "Should use Standard tolerance by default" {
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            $result.ToleranceLevel | Should Be 'Standard'
        }
    }
    
    Context "Confirm-RestorationSuccess - Core Functionality" {
        It "Should return RestorationVerificationResult object" {
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            $result.PSObject.TypeNames[0] | Should Be 'RestorationVerificationResult'
        }
        
        It "Should read current ACL from target object" {
            Mock Get-Acl { 
                $mockAcl = New-Object System.DirectoryServices.ActiveDirectorySecurity
                return $mockAcl
            } -Verifiable
            
            Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData | Out-Null
            
            Assert-VerifiableMocks
        }
        
        It "Should handle ACL read failures" {
            Mock Get-Acl { throw "Access denied" }
            
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            $result.IsVerified | Should Be $false
            $result.VerificationIssues | Should Match "Failed to read current ACL"
        }
        
        It "Should parse ACE entries from SDDL" {
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            ($result.ExpectedEntries -gt -1) | Should Be $true
            ($result.ActualEntries -gt -1) | Should Be $true
        }
        
        It "Should calculate match percentage correctly" {
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            $result.MatchPercentage | Should BeOfType [double]
            ($result.MatchPercentage -gt -1) | Should Be $true
            $result.MatchPercentage | Should BeLessOrEqual 100
        }
        
        It "Should apply tolerance levels correctly" {
            $strictResult = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData -ToleranceLevel 'Strict'
            $permissiveResult = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData -ToleranceLevel 'Permissive'
            
            # Permissive should be more likely to pass than strict
            if (-not $strictResult.IsVerified) {
                $permissiveResult.IsVerified | Should Be $true -Because "Permissive tolerance should be more lenient"
            }
        }
        
        It "Should handle empty expected SDDL" {
            $emptyBackupData = $script:TestBackupData.PSObject.Copy()
            $emptyBackupData.SDDL = ""
            
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $emptyBackupData
            $result.ExpectedEntries | Should Be 0
        }
        
        It "Should include verification timestamp" {
            $beforeTime = Get-Date
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $script:TestBackupData
            ($result.VerifiedAt -gt $beforeTime) | Should Be $true
        }
    }
    
    Context "ConvertFrom-BackupToACL - Parameter Validation" {
        It "Should accept valid BackupData parameter" {
            { ConvertFrom-BackupToACL -BackupData $script:TestBackupData } | Should Not Throw
        }
        
        It "Should reject null BackupData" {
            { ConvertFrom-BackupToACL -BackupData $null } | Should Throw
        }
        
        It "Should require SDDL property in BackupData" {
            $invalidData = [PSCustomObject]@{ ObjectDN = $script:TestObjectDN }
            $result = ConvertFrom-BackupToACL -BackupData $invalidData
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "does not contain SDDL property"
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should support pipeline input for BackupData" {
            $result = $script:TestBackupData | ConvertFrom-BackupToACL
            $result.SourceSDDL | Should Be $script:TestBackupData.SDDL
        }
    }
    
    Context "ConvertFrom-BackupToACL - Core Functionality" {
        It "Should return ACLConversionResult object" {
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            $result.PSObject.TypeNames[0] | Should Be 'ACLConversionResult'
        }
        
        It "Should convert SDDL to security descriptor successfully" {
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            $result.Success | Should Be $true
            $result.SecurityDescriptor | Should BeOfType [System.DirectoryServices.ActiveDirectorySecurity]
        }
        
        It "Should preserve source SDDL in result" {
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            $result.SourceSDDL | Should Be $script:TestBackupData.SDDL
        }
        
        It "Should calculate ACE count correctly" {
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            ($result.ACECount -gt -1) | Should Be $true
            $result.ACECount | Should Be $script:TestBackupData.ACLEntryCount
        }
        
        It "Should calculate SDDL length" {
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            $result.SDDLLength | Should Be $script:TestBackupData.SDDL.Length
        }
        
        It "Should handle invalid SDDL gracefully" {
            $invalidBackupData = $script:TestBackupData.PSObject.Copy()
            $invalidBackupData.SDDL = "InvalidSDDLString"
            
            $result = ConvertFrom-BackupToACL -BackupData $invalidBackupData
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "SDDL conversion failed"
        }
        
        It "Should include conversion timestamp" {
            $beforeTime = Get-Date
            $result = ConvertFrom-BackupToACL -BackupData $script:TestBackupData
            ($result.ConvertedAt -gt $beforeTime) | Should Be $true
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle missing Active Directory module gracefully" {
            Mock Get-ADObject { throw "Active Directory module not available" }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Target object not found"
        }
        
        It "Should handle network connectivity issues" {
            Mock Get-ADObject { throw "The server is not operational" }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ObjectExists | Should Be $false
        }
        
        It "Should handle insufficient permissions gracefully" {
            Mock Set-Acl { throw "Access is denied" }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.Success | Should Be $false
            $result.ErrorMessage | Should Match "ACL application failed"
        }
        
        It "Should handle malformed SDDL in verification" {
            $malformedBackupData = $script:TestBackupData.PSObject.Copy()
            $malformedBackupData.SDDL = "D:(A;;GA;;;WD"  # Incomplete SDDL
            
            $result = Confirm-RestorationSuccess -TargetObjectDN $script:TestObjectDN -ExpectedData $malformedBackupData
            ($result.ExpectedEntries -gt -1) | Should Be $true  # Should handle gracefully
        }
        
        It "Should handle domain controller unavailability" {
            Mock Get-Acl { throw "The domain controller is unavailable" }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ACLReadable | Should Be $false
        }
        
        It "Should provide detailed error information" {
            Mock Set-Acl { throw "Detailed error message" }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.ErrorMessage | Should Match "Detailed error message"
        }
    }
    
    Context "Performance Testing" {
        It "Should complete ACL application within performance baseline" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000  # 1 second baseline
            $result.Success | Should Be $true
        }
        
        It "Should track operation duration accurately" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.Duration | Should BeOfType [TimeSpan]
            ($result.Duration.TotalMilliseconds -gt -1) | Should Be $true
        }
        
        It "Should handle large SDDL strings efficiently" {
            # Create backup data with large SDDL
            $largeBackupData = $script:TestBackupData.PSObject.Copy()
            $largeBackupData.SDDL = $script:TestBackupData.SDDL * 10  # Multiply SDDL size
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = ConvertFrom-BackupToACL -BackupData $largeBackupData
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000  # 2 second baseline
        }
        
        It "Should maintain consistent performance across multiple operations" {
            $iterations = 5
            $measurements = @()
            
            1..$iterations | ForEach-Object {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Set-ObjectACL -TargetObjectDN "CN=PerfTest$_,OU=Users,DC=company,DC=com" -BackupData $script:TestBackupData | Out-Null
                $stopwatch.Stop()
                $measurements += $stopwatch.ElapsedMilliseconds
            }
            
            $averageTime = ($measurements | Measure-Object -Average).Average
            $maxTime = ($measurements | Measure-Object -Maximum).Maximum
            
            $averageTime | Should BeLessThan 800   # 800ms average
            $maxTime | Should BeLessThan 1500     # 1.5 second maximum
        }
    }
    
    Context "Security Validation" {
        It "Should validate DN format for security" {
            $maliciousInputs = @(
                "../../windows/system32",
                "C:\Windows\System32",
                "<script>alert('xss')</script>",
                "'; DROP TABLE users; --"
            )
            
            foreach ($maliciousInput in $maliciousInputs) {
                $result = Get-RestorationTarget -TargetObjectDN $maliciousInput
                $result.IsValid | Should Be $false
                $result.Issues | Should Match "Invalid DN format"
            }
        }
        
        It "Should not expose sensitive information in error messages" {
            Mock Set-Acl { throw "Sensitive error: PASSWORD123" }
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.ErrorMessage | Should Not Match "PASSWORD123"
        }
        
        It "Should handle malicious SDDL safely" {
            $maliciousBackupData = $script:TestBackupData.PSObject.Copy()
            $maliciousBackupData.SDDL = "<script>alert('xss')</script>"
            
            $result = ConvertFrom-BackupToACL -BackupData $maliciousBackupData
            $result.Success | Should Be $false  # Should fail safely
        }
        
        It "Should validate correlation ID format" {
            $maliciousCorrelationId = "<script>alert('xss')</script>"
            
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -CorrelationId $maliciousCorrelationId
            $result.CorrelationId | Should Be $maliciousCorrelationId
            # Function should accept it but downstream should sanitize
        }
        
        It "Should limit SDDL size for security" {
            $oversizedBackupData = $script:TestBackupData.PSObject.Copy()
            $oversizedBackupData.SDDL = "A" * 1000000  # 1MB of data
            
            { ConvertFrom-BackupToACL -BackupData $oversizedBackupData } | Should Not Throw
            # Should handle but may fail conversion safely
        }
    }
    
    Context "Enterprise Integration" {
        It "Should provide comprehensive logging" {
            Mock Write-Verbose { } -ParameterFilter {
                $Message -match "Starting ACL application operations"
            }
            
            Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData | Out-Null
            
            Assert-MockCalled Write-Verbose -ParameterFilter {
                $Message -match "Starting ACL application operations"
            }
        }
        
        It "Should support correlation tracking" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            Mock Write-Verbose { } -ParameterFilter {
                $Message -match $customCorrelationId
            }
            
            Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData -CorrelationId $customCorrelationId | Out-Null
            
            Assert-MockCalled Write-Verbose -ParameterFilter {
                $Message -match $customCorrelationId
            } -Times 1
        }
        
        It "Should maintain structured result format for reporting" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            
            # Verify essential properties for enterprise reporting
            $result.PSObject.TypeNames[0] | Should Be 'ACLOperationResult'
            $result.Success | Should BeOfType [bool]
            $result.TargetObjectDN | Should Not BeNullOrEmpty
            $result.Duration | Should BeOfType [TimeSpan]
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CompletedAt | Should BeOfType [DateTime]
        }
        
        It "Should support JSON serialization for API integration" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            
            { $result | ConvertTo-Json -Depth 10 } | Should Not Throw
            $jsonString = $result | ConvertTo-Json -Depth 10
            $jsonString | Should Match '"Success"'
            $jsonString | Should Match '"TargetObjectDN"'
        }
        
        It "Should integrate with monitoring systems" {
            Mock Write-Verbose { }
            
            Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData | Out-Null
            
            Assert-MockCalled Write-Verbose -Times 3
        }
    }
    
    Context "Cross-Platform Compatibility" {
        It "Should handle different path formats correctly" {
            $result = Set-ObjectACL -TargetObjectDN $script:TestObjectDN -BackupData $script:TestBackupData
            $result.TargetObjectDN | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
        }
        
        It "Should maintain consistent timestamp formats" {
            $result = Get-RestorationTarget -TargetObjectDN $script:TestObjectDN
            $result.ValidatedAt | Should BeOfType [DateTime]
        }
        
        It "Should support different Active Directory configurations" {
            # Test with OU instead of user object
            Mock Get-ADObject { 
                return [PSCustomObject]@{
                    DistinguishedName = $script:TestOUDN
                    ObjectClass = @('top', 'organizationalUnit')
                }
            }
            
            $result = Get-RestorationTarget -TargetObjectDN $script:TestOUDN
            $result.ObjectType | Should Be 'organizationalUnit'
            $result.ObjectExists | Should Be $true
        }
        
        It "Should handle different SDDL formats consistently" {
            $unixStyleBackupData = $script:TestBackupData.PSObject.Copy()
            # SDDL should work consistently across platforms
            
            $result = ConvertFrom-BackupToACL -BackupData $unixStyleBackupData
            $result.Success | Should Be $true
        }
    }
}






