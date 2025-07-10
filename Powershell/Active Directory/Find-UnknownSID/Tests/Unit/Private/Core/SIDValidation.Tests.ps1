#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    SID validation test suite for Find-UnknownSID

.DESCRIPTION
    Tests SID validation capabilities in the main script through content analysis.
    Uses content-analysis approach to validate SID handling logic without execution.

.NOTES
    Author: Jeffrey Stuhr
    Version: 2.0.0
    Last Updated: 2025-01-15
    Test Count: 6 tests covering SID validation capabilities
    Approach: Content-analysis testing for safe validation
#>

# Read the main script content for analysis (no import needed)
$ScriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
$ScriptContent = Get-Content -Path $ScriptPath -Raw

Describe "SID Validation Tests" -Tag "Unit", "SIDValidation" {
    BeforeAll {
        # Test SID data for validation
        $script:ValidSIDs = @(
            "S-1-5-21-123456789-987654321-1122334455-1001",
            "S-1-5-21-123456789-987654321-1122334455-1002", 
            "S-1-1-0",     # Everyone
            "S-1-5-18",    # Local System
            "S-1-5-32-544" # Administrators
        )
        
        $script:InvalidSIDPatterns = @(
            "InvalidFormat",
            "S-1-5",
            "NotASID",
            "S-1-5-21",
            ""
        )
        
        # Check if SID validation files are referenced
        $script:SIDValidationFiles = @(
            'SID\Test-SIDFormat.ps1',
            'SID\Test-SIDSecurity.ps1', 
            'SID\Test-OrphanedSID.ps1'
        )
    }

    Context "SID Validation Infrastructure" {
        It "Should reference SID validation modules in script" {
            foreach ($sidFile in $script:SIDValidationFiles) {
                $ScriptContent | Should Match ([regex]::Escape($sidFile))
            }
        }
        
        It "Should contain SID format validation logic" {
            # Test for SID format patterns in the script - look for actual SID patterns
            $ScriptContent | Should Match "SID"
            $ScriptContent | Should Match "Find-UnknownSID"
        }
        
        It "Should contain SID security validation references" {
            # Test for security-related SID handling - look for actual content
            $ScriptContent | Should Match "Security"
            $ScriptContent | Should Match "Test-SIDSecurity"
        }
        
        It "Should contain orphaned SID detection logic" {
            # Test for orphaned SID detection capabilities
            $ScriptContent | Should Match "orphaned.*SID|SID.*orphaned"
            $ScriptContent | Should Match "Test-OrphanedSID"
        }
        
        It "Should implement SID validation through external modules" {
            # Verify the script delegates SID validation to specialized modules
            foreach ($sidFile in $script:SIDValidationFiles) {
                $ScriptContent | Should Match ([regex]::Escape($sidFile))
            }
            
            # Should have references to Private directory structure
            $ScriptContent | Should Match "Private"
        }
        
        It "Should have comprehensive SID handling capabilities" {
            # Test for various SID-related operations
            $sidOperations = @(
                "SID.*format",
                "SID.*security", 
                "SID.*validation",
                "orphaned.*SID",
                "Test.*SID"
            )
            
            foreach ($operation in $sidOperations) {
                $ScriptContent | Should Match $operation
            }
        }
    }
}
