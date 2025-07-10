#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    SID validation test suite for Find-UnknownSID

.DESCRIPTION
    Comprehensive SID validation tests beyond the Private/SID directory functions.
    Tests advanced SID validation, format checking, and SID-specific business logic.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 6 tests covering SID validation functions
#>

# Import the module under test (relative path from Tests\Unit to module root)
Import-Module "$PSScriptRoot\..\..\Find-UnknownSID.ps1" -Force

Describe "SID Validation Tests" -Tag "Unit", "SIDValidation" {
    BeforeAll {
        # Set up test environment
        $TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Test SID data
        $script:WellKnownSIDs = @{
            "S-1-1-0" = "Everyone"
            "S-1-5-18" = "Local System"
            "S-1-5-19" = "Local Service"
            "S-1-5-20" = "Network Service"
            "S-1-5-32-544" = "Administrators"
            "S-1-5-32-545" = "Users"
        }
        
        $script:OrphanedSIDs = @(
            "S-1-5-21-123456789-987654321-1122334455-1001",
            "S-1-5-21-123456789-987654321-1122334455-1002",
            "S-1-5-21-987654321-123456789-1122334455-2001"
        )
        
        $script:InvalidSIDs = @(
            "InvalidFormat",
            "S-1-5",
            "S-1-5-21",
            "",
            $null
        )
    }

    Context "Advanced SID Format Validation" {
        It "Should validate standard domain SID format" {
            foreach ($sid in $script:OrphanedSIDs) {
                $result = Test-SIDFormat -SID $sid -Detailed
                
                $result.Valid | Should -Be $true
                $result.SIDType | Should -Be "Domain"
                $result.Components | Should -Not -BeNullOrEmpty
                $result.Authority | Should -Be "5"  # NT Authority
            }
        }
        
        It "Should identify well-known SIDs correctly" {
            foreach ($wellKnownSID in $script:WellKnownSIDs.Keys) {
                $result = Test-SIDFormat -SID $wellKnownSID -Detailed
                
                $result.Valid | Should -Be $true
                $result.SIDType | Should -Be "WellKnown"
                $result.Description | Should -Be $script:WellKnownSIDs[$wellKnownSID]
            }
        }
        
        It "Should reject invalid SID formats with detailed error information" {
            foreach ($invalidSID in $script:InvalidSIDs) {
                $result = Test-SIDFormat -SID $invalidSID -Detailed
                
                $result.Valid | Should -Be $false
                $result.Error | Should -Not -BeNullOrEmpty
                $result.ErrorType | Should -BeIn @("InvalidFormat", "TooShort", "NullOrEmpty")
            }
        }
        
        It "Should validate SID authority numbers correctly" {
            $testCases = @(
                @{ SID = "S-1-0-0"; Authority = "0"; Valid = $true }     # Null Authority
                @{ SID = "S-1-1-0"; Authority = "1"; Valid = $true }     # World Authority
                @{ SID = "S-1-2-0"; Authority = "2"; Valid = $true }     # Local Authority
                @{ SID = "S-1-3-0"; Authority = "3"; Valid = $true }     # Creator Authority
                @{ SID = "S-1-5-18"; Authority = "5"; Valid = $true }    # NT Authority
                @{ SID = "S-1-999-0"; Authority = "999"; Valid = $false } # Invalid Authority
            )
            
            foreach ($testCase in $testCases) {
                $result = Test-SIDFormat -SID $testCase.SID -ValidateAuthority
                
                if ($testCase.Valid) {
                    $result.Valid | Should -Be $true
                    $result.Authority | Should -Be $testCase.Authority
                } else {
                    $result.Valid | Should -Be $false
                    $result.Error | Should -Match "*authority*"
                }
            }
        }
        
        It "Should validate SID subauthority count limits" {
            # Test SIDs with different subauthority counts
            $testCases = @(
                @{ SID = "S-1-5-18"; SubAuthorityCount = 1; Valid = $true }
                @{ SID = "S-1-5-21-123456789"; SubAuthorityCount = 2; Valid = $true }
                @{ SID = "S-1-5-21-123456789-987654321-1122334455-1001"; SubAuthorityCount = 5; Valid = $true }
                # Test with maximum subauthorities (15 is typical limit)
                @{ SID = "S-1-5-21-1-2-3-4-5-6-7-8-9-10-11-12-1001"; SubAuthorityCount = 14; Valid = $true }
            )
            
            foreach ($testCase in $testCases) {
                $result = Test-SIDFormat -SID $testCase.SID -ValidateSubAuthorityCount
                
                $result.Valid | Should -Be $testCase.Valid
                if ($testCase.Valid) {
                    $result.SubAuthorityCount | Should -Be $testCase.SubAuthorityCount
                }
            }
        }
        
        It "Should identify removable vs protected SIDs" {
            # Well-known SIDs should be protected
            foreach ($wellKnownSID in $script:WellKnownSIDs.Keys) {
                $result = Test-SIDRemovability -SID $wellKnownSID
                
                $result.Removable | Should -Be $false
                $result.Reason | Should -Match "*well-known*|*protected*"
                $result.ProtectionLevel | Should -BeIn @("Critical", "High")
            }
            
            # Domain SIDs should typically be removable (if orphaned)
            foreach ($orphanedSID in $script:OrphanedSIDs) {
                $result = Test-SIDRemovability -SID $orphanedSID -AssumeOrphaned
                
                $result.Removable | Should -Be $true
                $result.ProtectionLevel | Should -Be "None"
            }
            
            # System SIDs should be protected
            $systemSIDs = @("S-1-5-18", "S-1-5-19", "S-1-5-20")
            foreach ($systemSID in $systemSIDs) {
                $result = Test-SIDRemovability -SID $systemSID
                
                $result.Removable | Should -Be $false
                $result.ProtectionLevel | Should -Be "Critical"
            }
        }
    }
}
