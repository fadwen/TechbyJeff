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