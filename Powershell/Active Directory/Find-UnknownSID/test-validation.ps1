. ".\Private\Security\Test-ClassIntegrity.ps1"

Describe "Parameter Validation Test" {
    It "Should throw for empty string" {
        try {
            Test-ClassIntegrity -Class ""
            throw "Function should have thrown an exception but didn't"
        } catch {
            $_.Exception.Message | Should Match "Class parameter cannot be null or empty"
        }
    }
    
    It "Should throw for null" {
        try {
            Test-ClassIntegrity -Class $null
            throw "Function should have thrown an exception but didn't"
        } catch {
            $_.Exception.Message | Should Match "Cannot bind argument to parameter 'Class'"
        }
    }
}
