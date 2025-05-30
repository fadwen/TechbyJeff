<#
.SYNOPSIS
    Sample PowerShell script containing intentional coding standard violations for testing.

.DESCRIPTION
    This script contains deliberate violations of company coding standards and is designed
    specifically for testing custom PSScriptAnalyzer rules. It serves as a test case to
    verify that custom rules can properly detect and report various types of violations.

    The violations included are:
    - Functions with improper naming conventions (not following Verb-Company pattern)
    - Missing comment-based help in public functions
    - Incorrect parameter naming (not using PascalCase)
    - Incorrect variable naming (not using camelCase)
    - Mixed good and bad examples for comprehensive testing

    This file should trigger multiple warnings and information messages when analyzed
    with the custom company rules, making it useful for validating rule functionality
    and testing rule modifications.

.EXAMPLE
    PS> Invoke-ScriptAnalyzer -Path ".\badcode.ps1" -CustomRulePath ".\CompanyRules.psm1"

    Analyzes this file with custom company rules to see detected violations.

.EXAMPLE
    PS> Test-CompanyRule

    Uses this file's content in the Test-CompanyRules.ps1 script for testing.

.NOTES
    Author: Jeffrey Stuhr
    Last Updated: 2025-05-29
    Version: 1.0

    This file is intentionally written with poor coding practices and should NOT
    be used as a reference for proper PowerShell coding standards. It exists
    solely for testing custom PSScriptAnalyzer rules.

    Expected violations when analyzed:
    - Function naming convention warnings
    - Missing help documentation notifications
    - Parameter and variable naming issues
#>

# BadCode.ps1 - This file contains violations for testing PSScriptAnalyzer

# Violation: Bad function name
function BadFunctionName {
    param($badparam, $Another_Bad_Param)

    $WRONG_CASE_VAR = "This should be camelCase"
    $another_wrong_var = "This too"

    Write-Host "This function has no help and bad naming"
}

# Violation: Missing help for public function
function Get-CompanyData {
    param($ProperParam, $AnotherParam)

    $properVariable = "This follows camelCase"
    $anotherGoodVar = 42

    return "Good function"
}

# Violation: Missing help for public function
function Set-CompanyValue {
    param($Value)
    return $Value
}

# Good function - should not trigger violations
function New-CompanyReport {
    <#
    .SYNOPSIS
        Creates a new company report.
    #>
    param($ReportType)

    $reportData = "Sample data"
    return $reportData
}