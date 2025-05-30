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