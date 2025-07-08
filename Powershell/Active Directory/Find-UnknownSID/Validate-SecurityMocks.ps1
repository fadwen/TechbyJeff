#Requires -Module Pester

<#
.SYNOPSIS
    Validates that all security mocks are properly in place before running tests

.DESCRIPTION
    This script verifies that dangerous operations like Remove-Item, Invoke-Expression,
    and process operations are properly mocked in all test files to prevent any actual
    system modifications during test execution.

.NOTES
    Author: Jeffrey Stuhr
    Created: July 8, 2025
    Purpose: Security validation before test execution
#>

[CmdletBinding()]
param()

Write-Host "🛡️ Validating Security Mocks in Test Files..." -ForegroundColor Cyan

$testFiles = @(
    ".\Tests\Unit\Operations.Tests.ps1"
    ".\Tests\Security\Privilege-Escalation.Tests.ps1" 
    ".\Tests\Security\Penetration-Testing.Tests.ps1"
)

$securityValidation = @{
    TotalFiles = $testFiles.Count
    ValidatedFiles = 0
    SecurityIssues = @()
    ValidationResults = @()
}

foreach ($testFile in $testFiles) {
    Write-Host "  Checking: $testFile" -ForegroundColor Yellow
    
    if (-not (Test-Path $testFile)) {
        $securityValidation.SecurityIssues += "❌ File not found: $testFile"
        continue
    }
    
    $content = Get-Content $testFile -Raw
    $fileValidation = @{
        File = $testFile
        HasRemoveItemMock = $content -match 'Mock Remove-Item'
        HasInvokeExpressionMock = $content -match 'Mock Invoke-Expression'
        HasDangerousOperations = $content -match 'Remove-Item.*C:\\|Remove-Item.*System32|Remove-Item.*Windows'
        SecurityScore = 0
    }
    
    # Check for required security mocks
    if ($fileValidation.HasRemoveItemMock) {
        $fileValidation.SecurityScore += 1
        Write-Host "    ✅ Remove-Item mock found" -ForegroundColor Green
    } else {
        Write-Host "    ❌ Remove-Item mock MISSING" -ForegroundColor Red
        $securityValidation.SecurityIssues += "Missing Remove-Item mock in $testFile"
    }
    
    if ($fileValidation.HasInvokeExpressionMock) {
        $fileValidation.SecurityScore += 1
        Write-Host "    ✅ Invoke-Expression mock found" -ForegroundColor Green
    } else {
        Write-Host "    ❌ Invoke-Expression mock MISSING" -ForegroundColor Red
        $securityValidation.SecurityIssues += "Missing Invoke-Expression mock in $testFile"
    }
    
    # Check for dangerous operations
    if ($fileValidation.HasDangerousOperations) {
        Write-Host "    ⚠️  Contains dangerous operations (should be mocked)" -ForegroundColor Yellow
        if ($fileValidation.SecurityScore -lt 2) {
            $securityValidation.SecurityIssues += "Contains dangerous operations without proper mocking in $testFile"
        }
    }
    
    $securityValidation.ValidationResults += $fileValidation
    
    if ($fileValidation.SecurityScore -eq 2) {
        $securityValidation.ValidatedFiles++
        Write-Host "    ✅ Security validation PASSED" -ForegroundColor Green
    } else {
        Write-Host "    ❌ Security validation FAILED" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n🛡️ Security Validation Summary:" -ForegroundColor Cyan
Write-Host "  Total Files Checked: $($securityValidation.TotalFiles)" -ForegroundColor White
Write-Host "  Files Validated: $($securityValidation.ValidatedFiles)" -ForegroundColor Green
Write-Host "  Security Issues: $($securityValidation.SecurityIssues.Count)" -ForegroundColor $(if ($securityValidation.SecurityIssues.Count -eq 0) { 'Green' } else { 'Red' })

if ($securityValidation.SecurityIssues.Count -gt 0) {
    Write-Host "`n🚨 Security Issues Found:" -ForegroundColor Red
    foreach ($issue in $securityValidation.SecurityIssues) {
        Write-Host "  $issue" -ForegroundColor Red
    }
    Write-Host "`n❌ SECURITY VALIDATION FAILED - DO NOT RUN TESTS" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n✅ SECURITY VALIDATION PASSED - Tests are safe to run" -ForegroundColor Green
    exit 0
}
