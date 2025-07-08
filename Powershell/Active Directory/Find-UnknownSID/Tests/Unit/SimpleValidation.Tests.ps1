#Requires -Module Pester

Describe "Simple Test Validation" -Tag "Unit", "Validation" {

    Context "Basic Functionality" {
        It "Should perform simple assertion" {
            $result = 2 + 2
            $result | Should -Be 4
        }

        It "Should handle string operations" {
            $text = "Hello World"
            $text | Should -Match "World"
        }
    }
}


