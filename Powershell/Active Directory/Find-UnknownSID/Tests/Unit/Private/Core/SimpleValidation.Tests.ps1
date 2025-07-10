#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Simple validation test suite for Find-UnknownSID

.DESCRIPTION
    Basic validation tests for common input validation and parameter checking.
    Tests fundamental validation logic used throughout the application.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 2 tests covering basic validation functions
#>

# Import the module under test (relative path from Tests\Unit to module root)
Import-Module "$PSScriptRoot\..\..\Find-UnknownSID.ps1" -Force

Describe "Simple Validation Tests" -Tag "Unit", "Validation" {
    BeforeAll {
        # Set up test environment
        $TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Test data
        $script:ValidSID = "S-1-5-21-123456789-987654321-1122334455-1001"
        $script:InvalidSID = "InvalidSIDFormat"
        $script:ValidPath = "C:\TestDirectory"
        $script:InvalidPath = "C:\<Invalid>Path"
    }

    Context "Basic Input Validation Tests" {
        It "Should validate SID format correctly" {
            # Test valid SID formats
            $validSIDs = @(
                "S-1-5-21-123456789-987654321-1122334455-1001",
                "S-1-5-32-544",  # Built-in Administrators
                "S-1-1-0",       # Everyone
                "S-1-5-18"       # Local System
            )
            
            foreach ($sid in $validSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result.Valid | Should -Be $true -Because "SID $sid should be valid"
            }
            
            # Test invalid SID formats
            $invalidSIDs = @(
                "InvalidSID",
                "S-1-5",         # Too short
                "S-1-5-21-123",  # Incomplete
                "",              # Empty
                $null            # Null
            )
            
            foreach ($sid in $invalidSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result.Valid | Should -Be $false -Because "SID '$sid' should be invalid"
            }
        }
        
        It "Should validate path format correctly" {
            # Test valid path formats
            $validPaths = @(
                "C:\Windows\System32",
                "\\server\share\folder",
                "D:\Data\Files",
                "C:\Program Files\Application"
            )
            
            foreach ($path in $validPaths) {
                $result = Test-PathFormat -Path $path
                $result.Valid | Should -Be $true -Because "Path '$path' should be valid"
            }
            
            # Test invalid path formats
            $invalidPaths = @(
                "C:\<Invalid>Characters",
                "C:\Path\With|Pipe",
                "",                      # Empty
                $null                    # Null
            )
            
            foreach ($path in $invalidPaths) {
                $result = Test-PathFormat -Path $path
                $result.Valid | Should -Be $false -Because "Path '$path' should be invalid"
            }
        }
    }
}
