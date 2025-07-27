#Requires -Version 5.1

# Import the SecurityValidationResult class
. "$PSScriptRoot\..\..\..\Classes\SecurityValidationResult.ps1"

Describe "SecurityValidationResult Class Tests" {
    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $result = [SecurityValidationResult]::new()
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "SecurityValidationResult"
        }

        It "Should set ValidatedAt to current time" {
            $beforeCreate = Get-Date
            Start-Sleep -Milliseconds 10
            $result = [SecurityValidationResult]::new()
            $result.ValidatedAt | Should BeGreaterThan $beforeCreate
        }

        It "Should set ValidatorVersion to default value" {
            $result = [SecurityValidationResult]::new()
            $result.ValidatorVersion | Should Be "2.0.0"
        }

        It "Should initialize Issues as empty array" {
            $result = [SecurityValidationResult]::new()
            $result.Issues | Should BeNullOrEmpty
        }

        It "Should initialize BlockedSIDs as empty array" {
            $result = [SecurityValidationResult]::new()
            $result.BlockedSIDs | Should BeNullOrEmpty
        }

        It "Should initialize AllowedSIDs as empty array" {
            $result = [SecurityValidationResult]::new()
            $result.AllowedSIDs | Should BeNullOrEmpty
        }

        It "Should initialize IsValid to true" {
            $result = [SecurityValidationResult]::new()
            $result.IsValid | Should Be $true
        }

        It "Should initialize RiskLevel to Low" {
            $result = [SecurityValidationResult]::new()
            $result.RiskLevel | Should Be "Low"
        }

        It "Should initialize RequiresElevatedConfirmation to false" {
            $result = [SecurityValidationResult]::new()
            $result.RequiresElevatedConfirmation | Should Be $false
        }
    }

    Context "Property Assignment Tests" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should allow setting IsValid property" {
            $script:testResult.IsValid = $false
            $script:testResult.IsValid | Should Be $false
        }

        It "Should allow setting RiskLevel property" {
            $script:testResult.RiskLevel = "High"
            $script:testResult.RiskLevel | Should Be "High"
        }

        It "Should allow setting Issues array" {
            $script:testResult.Issues = @("Issue 1", "Issue 2")
            $script:testResult.Issues.Count | Should Be 2
            $script:testResult.Issues[0] | Should Be "Issue 1"
            $script:testResult.Issues[1] | Should Be "Issue 2"
        }

        It "Should allow setting RequiresElevatedConfirmation property" {
            $script:testResult.RequiresElevatedConfirmation = $true
            $script:testResult.RequiresElevatedConfirmation | Should Be $true
        }

        It "Should allow setting BlockedSIDs array" {
            $script:testResult.BlockedSIDs = @("S-1-5-32-544", "S-1-1-0")
            $script:testResult.BlockedSIDs.Count | Should Be 2
            $script:testResult.BlockedSIDs[0] | Should Be "S-1-5-32-544"
        }

        It "Should allow setting AllowedSIDs array" {
            $script:testResult.AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-500")
            $script:testResult.AllowedSIDs.Count | Should Be 1
            $script:testResult.AllowedSIDs[0] | Should Be "S-1-5-21-1234567890-1234567890-1234567890-500"
        }

        It "Should allow setting ValidatedAt property" {
            $customDate = [DateTime]::new(2024, 1, 1, 12, 0, 0)
            $script:testResult.ValidatedAt = $customDate
            $script:testResult.ValidatedAt | Should Be $customDate
        }

        It "Should allow setting ValidatorVersion property" {
            $script:testResult.ValidatorVersion = "3.0.0"
            $script:testResult.ValidatorVersion | Should Be "3.0.0"
        }
    }

    Context "Array Property Manipulation Tests" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should allow adding to Issues array" {
            $script:testResult.Issues += "New Issue"
            $script:testResult.Issues.Count | Should Be 1
            $script:testResult.Issues[0] | Should Be "New Issue"
        }

        It "Should allow adding to BlockedSIDs array" {
            $script:testResult.BlockedSIDs += "S-1-5-32-544"
            $script:testResult.BlockedSIDs.Count | Should Be 1
            $script:testResult.BlockedSIDs[0] | Should Be "S-1-5-32-544"
        }

        It "Should allow adding to AllowedSIDs array" {
            $script:testResult.AllowedSIDs += "S-1-5-21-1234567890-1234567890-1234567890-500"
            $script:testResult.AllowedSIDs.Count | Should Be 1
            $script:testResult.AllowedSIDs[0] | Should Be "S-1-5-21-1234567890-1234567890-1234567890-500"
        }

        It "Should handle empty array assignments" {
            $script:testResult.Issues = @()
            $script:testResult.BlockedSIDs = @()
            $script:testResult.AllowedSIDs = @()
            $script:testResult.Issues.Count | Should Be 0
            $script:testResult.BlockedSIDs.Count | Should Be 0
            $script:testResult.AllowedSIDs.Count | Should Be 0
        }
    }

    Context "DateTime Property Tests" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should allow setting custom ValidatedAt" {
            $customDate = [DateTime]::new(2025, 7, 26, 12, 0, 0)
            $script:testResult.ValidatedAt = $customDate
            $script:testResult.ValidatedAt | Should Be $customDate
        }

        It "Should handle past ValidatedAt dates" {
            $pastDate = [DateTime]::new(2020, 1, 1)
            $script:testResult.ValidatedAt = $pastDate
            $script:testResult.ValidatedAt | Should Be $pastDate
        }

        It "Should handle future ValidatedAt dates" {
            $futureDate = [DateTime]::new(2030, 1, 1)
            $script:testResult.ValidatedAt = $futureDate
            $script:testResult.ValidatedAt | Should Be $futureDate
        }

        It "Should preserve millisecond precision" {
            $preciseDate = [DateTime]::new(2025, 7, 26, 12, 0, 0, 123)
            $script:testResult.ValidatedAt = $preciseDate
            $script:testResult.ValidatedAt.Millisecond | Should Be 123
        }
    }

    Context "RiskLevel Property Tests" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should handle standard risk levels" {
            $riskLevels = @("Low", "Medium", "High", "Critical")
            foreach ($level in $riskLevels) {
                $script:testResult.RiskLevel = $level
                $script:testResult.RiskLevel | Should Be $level
            }
        }

        It "Should handle custom risk levels" {
            $script:testResult.RiskLevel = "Moderate"
            $script:testResult.RiskLevel | Should Be "Moderate"
        }

        It "Should handle risk level case sensitivity" {
            $script:testResult.RiskLevel = "HIGH"
            $script:testResult.RiskLevel | Should Be "HIGH"
        }
    }

    Context "Boolean Logic Tests" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should handle IsValid and RequiresElevatedConfirmation combinations" {
            # Valid + No elevation required
            $script:testResult.IsValid = $true
            $script:testResult.RequiresElevatedConfirmation = $false
            $script:testResult.IsValid | Should Be $true
            $script:testResult.RequiresElevatedConfirmation | Should Be $false

            # Invalid + Elevation required
            $script:testResult.IsValid = $false
            $script:testResult.RequiresElevatedConfirmation = $true
            $script:testResult.IsValid | Should Be $false
            $script:testResult.RequiresElevatedConfirmation | Should Be $true
        }

        It "Should handle risk level correlation with IsValid" {
            # High risk should correlate with invalid
            $script:testResult.RiskLevel = "Critical"
            $script:testResult.IsValid = $false
            $script:testResult.RiskLevel | Should Be "Critical"
            $script:testResult.IsValid | Should Be $false
        }
    }

    Context "Edge Cases and Error Handling" {
        BeforeEach {
            $script:testResult = [SecurityValidationResult]::new()
        }

        It "Should handle null string assignments" {
            $script:testResult.RiskLevel = $null
            $script:testResult.RiskLevel | Should BeNullOrEmpty

            $script:testResult.ValidatorVersion = $null
            $script:testResult.ValidatorVersion | Should BeNullOrEmpty
        }

        It "Should handle very long issue descriptions" {
            $longIssue = "A" * 1000
            $script:testResult.Issues += $longIssue
            $script:testResult.Issues[0].Length | Should Be 1000
        }

        It "Should handle special characters in issue descriptions" {
            $specialIssue = "Issue with special chars: !@#$%^&*(){}[]|\\:;`"'<>,.?/~"
            $script:testResult.Issues += $specialIssue
            $script:testResult.Issues[0] | Should Be $specialIssue
        }

        It "Should handle extreme date values" {
            $minDate = [DateTime]::MinValue
            $maxDate = [DateTime]::MaxValue
            
            $script:testResult.ValidatedAt = $minDate
            $script:testResult.ValidatedAt | Should Be $minDate
            
            $script:testResult.ValidatedAt = $maxDate
            $script:testResult.ValidatedAt | Should Be $maxDate
        }

        It "Should handle very long version strings" {
            $longVersion = "1.0.0." + ("1" * 100)
            $script:testResult.ValidatorVersion = $longVersion
            $script:testResult.ValidatorVersion | Should Be $longVersion
        }
    }

    Context "Performance Tests" {
        It "Should create instances quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 100; $i++) {
                $result = [SecurityValidationResult]::new()
            }
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }

        It "Should handle large arrays efficiently" {
            $result = [SecurityValidationResult]::new()
            $largeArray = 1..1000 | ForEach-Object { "Issue $_" }
            $result.Issues = $largeArray
            $result.Issues.Count | Should Be 1000
        }
    }
}
