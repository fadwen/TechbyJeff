#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    ACL operations test suite for Find-UnknownSID

.DESCRIPTION
    Comprehensive Pester tests for ACL retrieval, modification, and SID removal operations.
    Tests all ACL-related functionality including error handling, validation, and recovery.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 40 tests covering 3 ACL functions
#>

# Import the module under test (relative path from Tests\Unit to module root)
Import-Module "$PSScriptRoot\..\..\Find-UnknownSID.ps1" -Force

Describe "ACL Operations Tests" -Tag "Unit", "ACL" {
    BeforeAll {
        # Set up test environment
        $TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $TestLogPath = Join-Path $env:TEMP "TestLogs\ACL_$TestCorrelationId.log"
        
        # Initialize script for ACL tests
        $script:TestInit = Initialize-ScriptExecution -LogPath $TestLogPath -CorrelationId $TestCorrelationId
        
        # Test data
        $script:TestDN = "CN=TestUser,OU=TestOU,DC=test,DC=local"
        $script:TestSID = "S-1-5-21-123456789-987654321-1122334455-1001"
        $script:TestPath = "C:\TestDirectory"
        
        # Mock ACL object for testing
        $script:MockACL = New-Object System.Security.AccessControl.DirectorySecurity
        $script:MockAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $script:TestSID,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $script:MockACL.SetAccessRule($script:MockAccessRule)
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $TestLogPath) { Remove-Item $TestLogPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path (Split-Path $TestLogPath)) { Remove-Item (Split-Path $TestLogPath) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context "Get-ACLForRemoval Function Tests" {
        It "Should retrieve ACL successfully with valid path" {
            Mock Get-Acl { return $script:MockACL }
            
            $result = Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ACL | Should -Not -BeNullOrEmpty
        }
        
        It "Should validate required Path parameter" {
            { Get-ACLForRemoval -Path $null -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be null*"
            { Get-ACLForRemoval -Path "" -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be empty*"
        }
        
        It "Should handle non-existent paths gracefully" {
            Mock Get-Acl { throw "Path not found" }
            
            $result = Get-ACLForRemoval -Path "C:\NonExistentPath" -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle access denied scenarios" {
            Mock Get-Acl { throw "Access denied" }
            
            $result = Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "*access*denied*"
        }
        
        It "Should retry on transient failures" {
            $script:CallCount = 0
            Mock Get-Acl { 
                $script:CallCount++
                if ($script:CallCount -lt 3) {
                    throw "Transient error"
                }
                return $script:MockACL
            }
            
            $result = Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $script:CallCount | Should -BeGreaterThan 1
        }
        
        It "Should validate Distinguished Name format for AD objects" {
            { Get-ACLForRemoval -ObjectDistinguishedName "InvalidDN" -CorrelationId $TestCorrelationId } | Should -Throw "*Distinguished Name*"
        }
        
        It "Should retrieve ACL from Active Directory objects" {
            Mock Get-Acl { return $script:MockACL }
            
            $result = Get-ACLForRemoval -ObjectDistinguishedName $script:TestDN -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }
        
        It "Should handle AD connectivity issues" {
            Mock Get-Acl { throw "The server is not operational" }
            
            $result = Get-ACLForRemoval -ObjectDistinguishedName $script:TestDN -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "*server*not*operational*"
        }
        
        It "Should include correlation ID in all operations" {
            Mock Write-StructuredLog { 
                param($Message, $Level, $Component, $CorrelationId)
                $CorrelationId | Should -Be $TestCorrelationId
            }
            Mock Get-Acl { return $script:MockACL }
            
            Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
        }
        
        It "Should support both file system and registry paths" {
            Mock Get-Acl { return $script:MockACL }
            
            $fsResult = Get-ACLForRemoval -Path "C:\TestFile.txt" -CorrelationId $TestCorrelationId
            $regResult = Get-ACLForRemoval -Path "HKLM:\SOFTWARE\Test" -CorrelationId $TestCorrelationId
            
            $fsResult.Success | Should -Be $true
            $regResult.Success | Should -Be $true
        }
        
        It "Should validate path format for different providers" {
            { Get-ACLForRemoval -Path "InvalidPath" -CorrelationId $TestCorrelationId } | Should -Throw "*path format*"
        }
        
        It "Should handle long path names correctly" {
            $longPath = "C:\" + ("TestDirectory\" * 50) + "TestFile.txt"
            Mock Get-Acl { return $script:MockACL }
            
            $result = Get-ACLForRemoval -Path $longPath -CorrelationId $TestCorrelationId
            $result.Success | Should -Be $true
        }
        
        It "Should preserve original ACL properties" {
            Mock Get-Acl { return $script:MockACL }
            
            $result = Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result.ACL.Access | Should -Not -BeNullOrEmpty
            $result.OriginalAccessRuleCount | Should -BeGreaterThan 0
        }
    }

    Context "Invoke-SIDRemoval Function Tests" {
        It "Should remove SID from ACL successfully" {
            Mock Get-Acl { return $script:MockACL }
            
            $result = Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.RemovedCount | Should -BeGreaterThan 0
        }
        
        It "Should validate ACL parameter" {
            { Invoke-SIDRemoval -ACL $null -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be null*"
        }
        
        It "Should validate SID format" {
            { Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove "InvalidSID" -CorrelationId $TestCorrelationId } | Should -Throw "*SID format*"
        }
        
        It "Should handle SID not found in ACL" {
            $nonExistentSID = "S-1-5-21-999999999-888888888-777777777-9999"
            
            $result = Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove $nonExistentSID -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.RemovedCount | Should -Be 0
        }
        
        It "Should remove multiple instances of the same SID" {
            # Add multiple rules with the same SID
            $multiACL = New-Object System.Security.AccessControl.DirectorySecurity
            $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($script:TestSID, "Read", "Allow")
            $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($script:TestSID, "Write", "Allow")
            $multiACL.SetAccessRule($rule1)
            $multiACL.SetAccessRule($rule2)
            
            $result = Invoke-SIDRemoval -ACL $multiACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.RemovedCount | Should -BeGreaterOrEqual 2
        }
        
        It "Should preserve other ACL entries" {
            $preserveACL = New-Object System.Security.AccessControl.DirectorySecurity
            $preserveRule = New-Object System.Security.AccessControl.FileSystemAccessRule("S-1-5-32-544", "FullControl", "Allow") # Administrators
            $removeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($script:TestSID, "Read", "Allow")
            $preserveACL.SetAccessRule($preserveRule)
            $preserveACL.SetAccessRule($removeRule)
            
            $originalCount = $preserveACL.Access.Count
            $result = Invoke-SIDRemoval -ACL $preserveACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $preserveACL.Access.Count | Should -Be ($originalCount - 1)
        }
        
        It "Should handle inherited ACL entries" {
            $inheritedACL = New-Object System.Security.AccessControl.DirectorySecurity
            $inheritedRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $script:TestSID,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $inheritedACL.SetAccessRule($inheritedRule)
            
            $result = Invoke-SIDRemoval -ACL $inheritedACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
        }
        
        It "Should log all removal operations" {
            Mock Write-StructuredLog { }
            
            Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter { $Message -match "SID removal" }
        }
        
        It "Should handle empty ACL gracefully" {
            $emptyACL = New-Object System.Security.AccessControl.DirectorySecurity
            
            $result = Invoke-SIDRemoval -ACL $emptyACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result.RemovedCount | Should -Be 0
        }
        
        It "Should return detailed removal statistics" {
            $result = Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            
            $result | Should -HaveProperty 'Success'
            $result | Should -HaveProperty 'RemovedCount'
            $result | Should -HaveProperty 'OriginalCount'
            $result | Should -HaveProperty 'FinalCount'
        }
    }

    Context "Set-ModifiedACL Function Tests" {
        It "Should apply modified ACL successfully" {
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
        }
        
        It "Should validate ACL parameter" {
            { Set-ModifiedACL -Path $script:TestPath -ACL $null -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be null*"
        }
        
        It "Should validate path parameter" {
            { Set-ModifiedACL -Path $null -ACL $script:MockACL -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be null*"
            { Set-ModifiedACL -Path "" -ACL $script:MockACL -CorrelationId $TestCorrelationId } | Should -Throw "*cannot be empty*"
        }
        
        It "Should handle access denied on ACL application" {
            Mock Set-Acl { throw "Access denied" }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.Error | Should -Match "*access*denied*"
        }
        
        It "Should retry ACL application on transient failures" {
            $script:SetCallCount = 0
            Mock Set-Acl { 
                $script:SetCallCount++
                if ($script:SetCallCount -lt 3) {
                    throw "Resource temporarily unavailable"
                }
            }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $script:SetCallCount | Should -BeGreaterThan 1
        }
        
        It "Should backup original ACL before modification" {
            Mock Get-Acl { return $script:MockACL }
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -BackupOriginal -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result | Should -HaveProperty 'OriginalACLBackup'
        }
        
        It "Should validate ACL changes before application" {
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -ValidateChanges -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result | Should -HaveProperty 'ValidationPassed'
        }
        
        It "Should handle file system paths" {
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path "C:\TestFile.txt" -ACL $script:MockACL -CorrelationId $TestCorrelationId
            $result.Success | Should -Be $true
        }
        
        It "Should handle registry paths" {
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path "HKLM:\SOFTWARE\Test" -ACL $script:MockACL -CorrelationId $TestCorrelationId
            $result.Success | Should -Be $true
        }
        
        It "Should handle Active Directory object paths" {
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -ObjectDistinguishedName $script:TestDN -ACL $script:MockACL -CorrelationId $TestCorrelationId
            $result.Success | Should -Be $true
        }
        
        It "Should verify ACL application success" {
            Mock Set-Acl { }
            Mock Get-Acl { return $script:MockACL }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -VerifyApplication -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $true
            $result | Should -HaveProperty 'VerificationPassed'
        }
        
        It "Should rollback on verification failure" {
            Mock Set-Acl { }
            Mock Get-Acl { 
                # Return different ACL to simulate verification failure
                return (New-Object System.Security.AccessControl.DirectorySecurity)
            }
            
            $result = Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -VerifyApplication -RollbackOnFailure -CorrelationId $TestCorrelationId
            
            $result.Success | Should -Be $false
            $result.RollbackPerformed | Should -Be $true
        }
        
        It "Should handle long path names" {
            $longPath = "C:\" + ("LongDirectory\" * 50) + "TestFile.txt"
            Mock Set-Acl { }
            
            $result = Set-ModifiedACL -Path $longPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
            $result.Success | Should -Be $true
        }
        
        It "Should log all ACL modification operations" {
            Mock Write-StructuredLog { }
            Mock Set-Acl { }
            
            Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter { $Message -match "ACL modification" }
        }
    }

    Context "Integration Tests" {
        It "Should complete full ACL workflow: Get -> Remove -> Set" {
            Mock Get-Acl { return $script:MockACL }
            Mock Set-Acl { }
            
            # Get ACL
            $getResult = Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            $getResult.Success | Should -Be $true
            
            # Remove SID
            $removeResult = Invoke-SIDRemoval -ACL $getResult.ACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            $removeResult.Success | Should -Be $true
            
            # Set modified ACL
            $setResult = Set-ModifiedACL -Path $script:TestPath -ACL $getResult.ACL -CorrelationId $TestCorrelationId
            $setResult.Success | Should -Be $true
        }
        
        It "Should maintain correlation ID throughout ACL workflow" {
            Mock Write-StructuredLog { 
                param($Message, $Level, $Component, $CorrelationId)
                $CorrelationId | Should -Be $TestCorrelationId
            }
            Mock Get-Acl { return $script:MockACL }
            Mock Set-Acl { }
            
            Get-ACLForRemoval -Path $script:TestPath -CorrelationId $TestCorrelationId
            Invoke-SIDRemoval -ACL $script:MockACL -SIDToRemove $script:TestSID -CorrelationId $TestCorrelationId
            Set-ModifiedACL -Path $script:TestPath -ACL $script:MockACL -CorrelationId $TestCorrelationId
        }
        
        It "Should handle complex ACL scenarios with multiple SIDs" {
            $complexACL = New-Object System.Security.AccessControl.DirectorySecurity
            
            # Add multiple SIDs
            $sids = @(
                "S-1-5-21-123456789-987654321-1122334455-1001",
                "S-1-5-21-123456789-987654321-1122334455-1002",
                "S-1-5-32-544"  # Administrators
            )
            
            foreach ($sid in $sids) {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, "FullControl", "Allow")
                $complexACL.SetAccessRule($rule)
            }
            
            Mock Get-Acl { return $complexACL }
            Mock Set-Acl { }
            
            # Remove first SID only
            $removeResult = Invoke-SIDRemoval -ACL $complexACL -SIDToRemove $sids[0] -CorrelationId $TestCorrelationId
            
            $removeResult.Success | Should -Be $true
            $removeResult.RemovedCount | Should -Be 1
            $complexACL.Access.Count | Should -Be ($sids.Count - 1)
        }
    }
}
