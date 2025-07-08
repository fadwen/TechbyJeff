#Requires -Version 5.1

<#
.SYNOPSIS
    SAFE static analysis of test files for dangerous operations - NO EXECUTION

.DESCRIPTION
    This script performs STATIC ANALYSIS ONLY - it reads file content but does NOT
    execute any PowerShell code or load any test files. It scans for dangerous
    patterns and missing security mocks without running anything.

.NOTES
    Author: Jeffrey Stuhr
    Created: July 8, 2025
    Purpose: SAFE security validation - NO CODE EXECUTION
#>

[CmdletBinding()]
param()

Write-Host "🛡️ SAFE Static Analysis - NO CODE EXECUTION" -ForegroundColor Green
Write-Host "  Analyzing file content only - no PowerShell execution" -ForegroundColor Yellow

$testFiles = @(
    ".\Tests\Unit\Operations.Tests.ps1"
    ".\Tests\Security\Privilege-Escalation.Tests.ps1"
    ".\Tests\Security\Penetration-Testing.Tests.ps1"
    ".\Tests\Unit\ACL.Tests.ps1"
    ".\Tests\Unit\Core.Tests.ps1"
)

$dangerousPatterns = @{
    'Remove-Item.*C:\\' = 'System path deletion'
    'Remove-Item.*System32' = 'System32 deletion'
    'Remove-Item.*Windows' = 'Windows folder deletion'
    'Remove-Item.*\-Recurse.*\-Force' = 'Recursive forced deletion'
    'Invoke-Expression.*Remove-Item' = 'Dynamic removal execution'
    'Start-Process.*calc' = 'Calculator execution'
    'Stop-Process.*lsass' = 'Critical process termination'
    'net user.*add' = 'User account creation'
    'rm -rf /' = 'Unix system deletion'
}

$requiredMocks = @(
    'Mock Remove-Item'
    'Mock Invoke-Expression'
    'Mock Start-Process'
    'Mock Stop-Process'
)

$results = @{
    TotalFiles = 0
    SafeFiles = 0
    DangerousFiles = 0
    Issues = @()
}

foreach ($testFile in $testFiles) {
    Write-Host "`n📄 Analyzing: $testFile" -ForegroundColor Cyan
    $results.TotalFiles++
    
    if (-not (Test-Path $testFile)) {
        Write-Host "  ⚠️  File not found - skipping" -ForegroundColor Yellow
        continue
    }
    
    # SAFE: Read file content only - NO EXECUTION
    try {
        $content = Get-Content $testFile -Raw -ErrorAction Stop
    }
    catch {
        Write-Host "  ❌ Failed to read file: $($_.Exception.Message)" -ForegroundColor Red
        $results.Issues += "Failed to read: $testFile"
        continue
    }
    
    $fileIssues = @()
    $fileMocks = @()
    
    # Check for dangerous patterns
    foreach ($pattern in $dangerousPatterns.Keys) {
        if ($content -match $pattern) {
            $description = $dangerousPatterns[$pattern]
            Write-Host "  🚨 DANGEROUS: $description" -ForegroundColor Red
            $fileIssues += "DANGEROUS: $description found in $testFile"
        }
    }
    
    # Check for required mocks
    foreach ($mockPattern in $requiredMocks) {
        if ($content -match $mockPattern) {
            Write-Host "  ✅ Found: $mockPattern" -ForegroundColor Green
            $fileMocks += $mockPattern
        } else {
            Write-Host "  ❌ Missing: $mockPattern" -ForegroundColor Red
            $fileIssues += "MISSING MOCK: $mockPattern in $testFile"
        }
    }
    
    # File safety assessment
    if ($fileIssues.Count -eq 0) {
        Write-Host "  ✅ File appears SAFE" -ForegroundColor Green
        $results.SafeFiles++
    } else {
        Write-Host "  ❌ File has SECURITY ISSUES" -ForegroundColor Red
        $results.DangerousFiles++
        $results.Issues += $fileIssues
    }
}

# SAFE Summary - NO EXECUTION
Write-Host "`n🛡️ STATIC ANALYSIS SUMMARY (NO CODE EXECUTED):" -ForegroundColor Green
Write-Host "  Total Files Analyzed: $($results.TotalFiles)" -ForegroundColor White
Write-Host "  Safe Files: $($results.SafeFiles)" -ForegroundColor Green
Write-Host "  Dangerous Files: $($results.DangerousFiles)" -ForegroundColor Red
Write-Host "  Total Issues: $($results.Issues.Count)" -ForegroundColor $(if ($results.Issues.Count -eq 0) { 'Green' } else { 'Red' })

if ($results.Issues.Count -gt 0) {
    Write-Host "`n🚨 SECURITY ISSUES FOUND:" -ForegroundColor Red
    foreach ($issue in $results.Issues) {
        Write-Host "  • $issue" -ForegroundColor Red
    }
    
    Write-Host "`n❌ DO NOT RUN ANY TESTS - DANGEROUS OPERATIONS DETECTED" -ForegroundColor Red
    Write-Host "   Fix all security mocks before attempting test execution" -ForegroundColor Yellow
} else {
    Write-Host "`n✅ ALL FILES APPEAR SAFE FOR TESTING" -ForegroundColor Green
    Write-Host "   All dangerous operations have proper mocking" -ForegroundColor Green
}

Write-Host "`nℹ️  This analysis performed STATIC SCANNING ONLY - no PowerShell code was executed" -ForegroundColor Cyan
