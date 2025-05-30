# Debug-CompanyRules.ps1 - Test and debug the custom rules

function Test-CompanyRuleDebug {
    Write-Host "=== DEBUGGING COMPANY RULES ===" -ForegroundColor Magenta

    # First, let's test if the module loads correctly
    try {
        Import-Module ".\CompanyRules.psm1" -Force
        Write-Host "✅ Module loaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to load module: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Test if the function exists
    if (Get-Command Measure-CompanyStandards -ErrorAction SilentlyContinue) {
        Write-Host "✅ Measure-CompanyStandards function found" -ForegroundColor Green
    } else {
        Write-Host "❌ Measure-CompanyStandards function not found" -ForegroundColor Red
        return
    }

    Write-Host "`n=== TESTING WITH SAMPLE CODE ===" -ForegroundColor Cyan

    # Sample code with clear violations
    $testCode = @'
function BadFunction {
    param($badParam)
    $BadVariable = "test"
    Write-Host "No help"
}

function Get-CompanyData {
    param($Data)
    $result = "missing help"
    return $result
}
'@

    Write-Host "Test code:" -ForegroundColor Yellow
    Write-Host $testCode -ForegroundColor White

    # Parse the code
    Write-Host "`n=== PARSING CODE ===" -ForegroundColor Cyan
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($testCode, [ref]$null, [ref]$null)
    Write-Host "✅ Code parsed successfully" -ForegroundColor Green

    # Check what functions were found
    $functions = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true)
    Write-Host "Found $($functions.Count) functions:" -ForegroundColor Yellow
    foreach ($func in $functions) {
        Write-Host "  - $($func.Name)" -ForegroundColor White
    }

    # Run the custom rule
    Write-Host "`n=== RUNNING CUSTOM RULE ===" -ForegroundColor Cyan
    try {
        $violations = Measure-CompanyStandards -ScriptBlockAst $ast
        Write-Host "✅ Rule executed successfully" -ForegroundColor Green
        Write-Host "Found $($violations.Count) violations:" -ForegroundColor Yellow

        if ($violations.Count -eq 0) {
            Write-Host "❌ No violations found - this might indicate an issue with the rule logic" -ForegroundColor Red
        } else {
            foreach ($violation in $violations) {
                Write-Host "`n[$($violation.Severity)] $($violation.RuleName)" -ForegroundColor Cyan
                Write-Host "Message: $($violation.Message)" -ForegroundColor White
                Write-Host "Line: $($violation.Extent.StartLineNumber)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "❌ Error running rule: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    }

    Write-Host "`n=== TESTING WITH PSSCRIPTANALYZER ===" -ForegroundColor Cyan

    # Test with actual PSScriptAnalyzer
    if (Get-Module PSScriptAnalyzer -ListAvailable) {
        Write-Host "✅ PSScriptAnalyzer module available" -ForegroundColor Green

        # Create a temporary test file
        $tempFile = "TempTestFile.ps1"
        $testCode | Out-File -FilePath $tempFile -Encoding UTF8

        try {
            Write-Host "Running PSScriptAnalyzer with custom rule..." -ForegroundColor Yellow
            $results = Invoke-ScriptAnalyzer -Path $tempFile -CustomRulePath ".\CompanyRules.psm1"

            if ($results.Count -eq 0) {
                Write-Host "❌ PSScriptAnalyzer found no violations" -ForegroundColor Red
                Write-Host "This could mean:" -ForegroundColor Yellow
                Write-Host "  1. The rule isn't being loaded properly" -ForegroundColor Yellow
                Write-Host "  2. The rule logic isn't matching the violations" -ForegroundColor Yellow
                Write-Host "  3. The test code doesn't actually violate the rules" -ForegroundColor Yellow
            } else {
                Write-Host "✅ PSScriptAnalyzer found $($results.Count) violations:" -ForegroundColor Green
                foreach ($result in $results) {
                    Write-Host "  - $($result.RuleName): $($result.Message)" -ForegroundColor White
                }
            }
        }
        catch {
            Write-Host "❌ Error running PSScriptAnalyzer: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            # Clean up temp file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    } else {
        Write-Host "❌ PSScriptAnalyzer module not available" -ForegroundColor Red
        Write-Host "Install it with: Install-Module PSScriptAnalyzer" -ForegroundColor Yellow
    }
}

# Run the debug test
Test-CompanyRuleDebug