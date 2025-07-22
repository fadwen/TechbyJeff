# Write-StructuredLogEntry.Tests.ps1

Describe "Write-StructuredLogEntry" {
    
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
