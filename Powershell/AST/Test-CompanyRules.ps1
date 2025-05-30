<#
.SYNOPSIS
    Tests the custom PSScriptAnalyzer company rules with sample code to verify their functionality.

.DESCRIPTION
    This script provides comprehensive testing for the custom PSScriptAnalyzer rules defined
    in CompanyRules.psm1. It demonstrates how the custom rules work by running them against
    sample code that contains various coding standard violations.

    The script validates:
    - Function naming convention violations
    - Missing comment-based help in public functions
    - Parameter naming standard violations
    - Variable naming convention violations

    It shows how violations are detected and reported, making it useful for understanding
    the custom rule behavior and for debugging rule logic during development.

.EXAMPLE
    PS> .\Test-CompanyRules.ps1

    Runs the test function which loads the custom rules module and tests it against
    sample code containing various violations.

.EXAMPLE
    PS> Test-CompanyRule

    Directly calls the test function to demonstrate custom rule functionality.

.NOTES
    Author: Jeffrey Stuhr
    Last Updated: 2025-05-29
    Version: 1.0

    This script requires:
    - CompanyRules.psm1 module to be in the same directory
    - PowerShell 5.0 or higher for AST parsing capabilities

    The test demonstrates violations such as:
    - Functions not following Verb-Company naming pattern
    - Missing .SYNOPSIS in public functions
    - Incorrect parameter and variable casing
#>

function Test-CompanyRule {
    <#
    .SYNOPSIS
        Tests the custom company rule with sample code.

    .DESCRIPTION
        Demonstrates how the custom PSScriptAnalyzer rule works with various code samples.
    #>

    # Sample script that violates company standards
    $sampleScript = @'
# This script has several violations for testing

function BadFunction {
    param($badparam, $Another_Bad_Param)

    $WRONG_CASE_VAR = "This should be camelCase"
    $another_wrong_var = "This too"

    Write-Host "This function has no help and bad naming"
}

function Get-CompanyData {
    <#
    .SYNOPSIS
        This function follows company standards.
    #>
    param($ProperParam, $AnotherParam)

    $properVariable = "This follows camelCase"
    $anotherGoodVar = 42

    return "Good function"
}

function Set-CompanyValue {
    param($Value)
    # Missing help for public function
    return $Value
}
'@

    Write-Host "Testing custom PSScriptAnalyzer rule..." -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Gray

    # Parse the sample script
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sampleScript, [ref]$null, [ref]$null)

    # Run our custom rule
    $violations = Measure-CompanyStandards -ScriptBlockAst $ast -Verbose

    if ($violations.Count -eq 0) {
        Write-Host "✅ No violations found!" -ForegroundColor Green
    } else {
        Write-Host "Found $($violations.Count) violations:" -ForegroundColor Red
        Write-Host ""

        foreach ($violation in $violations) {
            $severityColor = switch ($violation.Severity) {
                'Error' { 'Red' }
                'Warning' { 'Yellow' }
                'Information' { 'Cyan' }
                default { 'White' }
            }

            Write-Host "[$($violation.Severity)] " -ForegroundColor $severityColor -NoNewline
            Write-Host "$($violation.RuleName): " -ForegroundColor Gray -NoNewline
            Write-Host "$($violation.Message)" -ForegroundColor White
            Write-Host "  Line: $($violation.Extent.StartLineNumber), Column: $($violation.Extent.StartColumnNumber)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    Write-Host "Test complete!" -ForegroundColor Green
}