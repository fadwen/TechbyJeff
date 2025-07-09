#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Security validation test suite for Find-UnknownSID

.DESCRIPTION
    Comprehensive Pester tests for security validation, compliance checks, and security descriptor operations.
    Tests all security-related functionality including validation, compliance, and security descriptor handling.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 2 tests covering security validation functions
#>

# Import the module under test (relative path from Tests\Unit to module root)
Import-Module "$PSScriptRoot\..\..\Find-UnknownSID.ps1" -Force

Describe "Security Validation Tests" -Tag "Unit", "Security" {
    BeforeAll {
        # Set up test environment
        $TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $TestLogPath = Join-Path $env:TEMP "TestLogs\Security_$TestCorrelationId.log"
        
        # Initialize script for security tests
        $script:TestInit = Initialize-ScriptExecution -LogPath $TestLogPath -CorrelationId $TestCorrelationId
        
        # Test data
        $script:TestSID = "S-1-5-21-123456789-987654321-1122334455-1001"
        $script:TestPath = "C:\TestDirectory"
        $script:TestDN = "CN=TestUser,OU=TestOU,DC=test,DC=local"
        
        # Mock security descriptor for testing
        $script:MockSecurityDescriptor = @{
            Owner = "BUILTIN\Administrators"
            Group = "BUILTIN\Users"
            Access = @(
                @{
                    IdentityReference = $script:TestSID
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                }
            )
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $TestLogPath) { Remove-Item $TestLogPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path (Split-Path $TestLogPath)) { Remove-Item (Split-Path $TestLogPath) -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context "Invoke-SecurityValidation Function Tests" {
        It "Should validate security configuration successfully" {
            Mock Test-PathTraversal { return @{ Valid = $true; ValidationsPassed = 5 } }
            Mock Test-ClassIntegrity { return @{ Valid = $true; ChecksPassed = 10 } }
            Mock Get-SecurityDescriptor { return $script:MockSecurityDescriptor }
            
            $result = Invoke-SecurityValidation -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ValidationsPassed | Should -BeGreaterThan 0
            $result.SecurityLevel | Should -BeIn @('Low', 'Medium', 'High', 'Critical')
        }
        
        It "Should perform comprehensive security compliance checks" {
            Mock Test-PathTraversal { return @{ Valid = $true; ValidationsPassed = 5 } }
            Mock Test-ClassIntegrity { return @{ Valid = $true; ChecksPassed = 10 } }
            Mock Get-SecurityDescriptor { return $script:MockSecurityDescriptor }
            Mock Invoke-RemovalVerification { return @{ Valid = $true; ComplianceScore = 95 } }
            
            $result = Invoke-SecurityValidation -Path $script:TestPath -ComprehensiveCheck -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.ComprehensiveCheck | Should -Be $true
            $result.ComplianceScore | Should -BeGreaterOrEqual 90
            $result | Should -HaveProperty 'PathTraversalValidation'
            $result | Should -HaveProperty 'ClassIntegrityValidation'
            $result | Should -HaveProperty 'SecurityDescriptorValidation'
            $result | Should -HaveProperty 'RemovalVerification'
        }
    }

    Context "Get-SecurityDescriptor Function Tests" {
        It "Should retrieve security descriptor with full details" {
            Mock Get-Acl { 
                $acl = New-Object System.Security.AccessControl.DirectorySecurity
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $script:TestSID,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.SetAccessRule($rule)
                return $acl
            }
            
            $result = Get-SecurityDescriptor -Path $script:TestPath -CorrelationId $TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.SecurityDescriptor | Should -Not -BeNullOrEmpty
            $result.AccessRuleCount | Should -BeGreaterThan 0
            $result | Should -HaveProperty 'Owner'
            $result | Should -HaveProperty 'Group'
            $result | Should -HaveProperty 'AccessRules'
        }
    }
}
