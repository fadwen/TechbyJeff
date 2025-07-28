# Write-StructuredLogEntry.Tests.ps1

# Import the function being tested
. "$PSScriptRoot\..\..\..\..\Private\Logging\Write-StructuredLogEntry.ps1"

Describe "Write-StructuredLogEntry" {
    # Mock all external dependencies that might not exist
    Mock Add-Content { }
    Mock Write-Warning { }
    Mock Write-Error { }
    Mock Write-Information { }
    Mock Write-Debug { }
    Mock Write-Verbose { }
    Mock Write-Host { }
    
    # Mock Write-ConsoleLogEntry which is defined in the same file
    Mock Write-ConsoleLogEntry { }
    
    # Mock Get-Command to simulate availability of Get-LoggingSystemState
    Mock Get-Command { 
        return $null 
    } -ParameterFilter { $Name -eq 'Get-LoggingSystemState' }
    
    Context "Parameter Validation" {
        It "Should accept valid parameters without error" {
            { Write-StructuredLogEntry -Message "Test" -Level "Information" } | Should Not Throw
        }
        
        It "Should work with all optional parameters" {
            { Write-StructuredLogEntry -Message "Test" -Level "Information" -Component "Test" -CorrelationId "123" -Details @{Key="Value"} } | Should Not Throw
        }
    }
    
    Context "Basic Functionality" {
        It "Should complete without error" {
            { Write-StructuredLogEntry -Message "Test message" -Level "Information" } | Should Not Throw
        }
    }
}
