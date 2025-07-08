# Invoke-Tests.ps1
# Enterprise test runner following pester.instructions.md standards

[CmdletBinding()]
param(
    [ValidateSet('Unit', 'Integration', 'Performance', 'Security', 'All')]
    [string]$TestType = 'All',
    
    [string]$OutputPath = './Tests/Results',
    
    [switch]$CodeCoverage,
    
    [switch]$CI,
    
    [int]$CoverageThreshold = 80,
    
    [switch]$ShowSummary,
    
    [string[]]$Tag = @(),
    
    [string[]]$ExcludeTag = @(),
    
    [switch]$PassThru
)

Write-Host "🚀 Enterprise Test Runner Started" -ForegroundColor Green
Write-Host "TestType: $TestType, ShowSummary: $ShowSummary" -ForegroundColor Gray

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Determine test paths based on test type
$basePath = Split-Path -Parent $PSScriptRoot
$testPaths = @()

switch ($TestType) {
    'Unit' {
        $testPaths = @(Join-Path $basePath "Tests\Unit")
        if (-not $Tag) { $Tag = @('Unit') }
        Write-Host "🧪 Executing Unit Tests..." -ForegroundColor Cyan
    }
    'Integration' {
        $testPaths = @(Join-Path $basePath "Tests\Integration")
        if (-not $Tag) { $Tag = @('Integration') }
        Write-Host "🔗 Executing Integration Tests..." -ForegroundColor Cyan
    }
    'Performance' {
        $testPaths = @(Join-Path $basePath "Tests\Performance")
        if (-not $Tag) { $Tag = @('Performance') }
        Write-Host "🚀 Executing Performance Tests..." -ForegroundColor Cyan
    }
    'Security' {
        $testPaths = @(Join-Path $basePath "Tests\Security")
        if (-not $Tag) { $Tag = @('Security') }
        Write-Host "🔒 Executing Security Tests..." -ForegroundColor Cyan
    }
    'All' {
        $testPaths = @(
            (Join-Path $basePath "Tests\Unit"),
            (Join-Path $basePath "Tests\Integration"),
            (Join-Path $basePath "Tests\Performance"), 
            (Join-Path $basePath "Tests\Security")
        )
        Write-Host "🎯 Executing All Tests..." -ForegroundColor Blue
    }
}

# Filter to existing paths only
$testPaths = $testPaths | Where-Object { Test-Path $_ }

if ($testPaths.Count -eq 0) {
    Write-Warning "No test paths found for test type: $TestType"
    if (-not $PassThru) {
        exit 1
    }
    return $null
}

# Configure Pester parameters
$pesterParams = @{
    Path = $testPaths
    PassThru = $true
    Output = if ($ShowSummary) { 'Minimal' } else { 'Detailed' }
}

# Add tag filters if specified
if ($Tag -and $Tag.Count -gt 0) {
    $pesterParams.Tag = $Tag
    Write-Host "Tag filter: $($Tag -join ', ')" -ForegroundColor Gray
}

if ($ExcludeTag -and $ExcludeTag.Count -gt 0) {
    $pesterParams.ExcludeTag = $ExcludeTag
    Write-Host "Exclude tags: $($ExcludeTag -join ', ')" -ForegroundColor Gray
}

# Configure code coverage if requested
if ($CodeCoverage) {
    $coveragePaths = @(
        Join-Path $basePath "Public\*.ps1"
        Join-Path $basePath "Private\*.ps1"
        Join-Path $basePath "Classes\*.ps1"
    )
    $pesterParams.CodeCoverage = $coveragePaths
    $pesterParams.CodeCoverageOutputFile = Join-Path $OutputPath "Coverage-$TestType-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
    Write-Host "📊 Code coverage enabled with $CoverageThreshold% threshold" -ForegroundColor Yellow
}

# Execute tests
$startTime = Get-Date
Write-Host "Starting test execution at $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host "Test paths: $($testPaths -join ', ')" -ForegroundColor Gray

# Set output verbosity for CI/CD environments
if ($env:CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS) {
    $pesterParams.Output = 'Normal'
    Write-Host "🤖 CI/CD environment detected, adjusting output format" -ForegroundColor Blue
}

$result = Invoke-Pester @pesterParams

$endTime = Get-Date
$duration = $endTime - $startTime

# Force output buffer flush
[Console]::Out.Flush()

# Always show summary when requested - using echo for reliability
if ($ShowSummary -eq $true) {
    Write-Output ""
    Write-Output "================================================================================"
    Write-Output "📊 FIND-UNKNOWNSID TEST EXECUTION SUMMARY"
    Write-Output "================================================================================"
    Write-Output "Test Type: $TestType"
    Write-Output "Execution Time: $($duration.ToString('hh\:mm\:ss\.fff'))"
    Write-Output "Total Tests: $($result.TotalCount)"
    Write-Output "Passed: $($result.PassedCount)" 
    Write-Output "Failed: $($result.FailedCount)"
    Write-Output "Skipped: $($result.SkippedCount)"
    
    if ($result.TotalCount -gt 0) {
        $passRate = [math]::Round(($result.PassedCount / $result.TotalCount) * 100, 2)
        Write-Output "Pass Rate: $passRate%"
    }

    if ($CodeCoverage -and $result.CodeCoverage) {
        $coveragePercent = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
        Write-Output "Code Coverage: $coveragePercent%"
    }

    Write-Output "================================================================================"
}

# Handle test failures with quality gate enforcement
if ($result.FailedCount -gt 0) {
    Write-Host "`n❌ FAILED TESTS DETECTED:" -ForegroundColor Red
    Write-Host "-" * 50 -ForegroundColor Red
    
    foreach ($test in $result.Failed) {
        Write-Host "• $($test.ExpandedPath)" -ForegroundColor White
        if ($test.ErrorRecord) {
            Write-Host "  Error: $($test.ErrorRecord.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Quality gate enforcement following enterprise standards
    if ($result.TotalCount -gt 0) {
        $passRate = ($result.PassedCount / $result.TotalCount) * 100
        if ($passRate -lt 80) {
            Write-Host "🚫 Quality Gate Failed: Pass rate ($([math]::Round($passRate, 2))%) below minimum threshold (80%)" -ForegroundColor Red
            if (-not $PassThru) {
                exit 1
            }
        }
    }
    
    if (-not $PassThru) {
        exit 1
    }
} else {
    Write-Host "`n✅ All tests passed successfully!" -ForegroundColor Green
    
    # Validate quality gates for successful runs
    if ($result.TotalCount -gt 0) {
        $passRate = ($result.PassedCount / $result.TotalCount) * 100
        if ($passRate -ge 95) {
            Write-Host "🏆 Excellence achieved: $([math]::Round($passRate, 2))% pass rate exceeds enterprise standards!" -ForegroundColor Green
        } elseif ($passRate -ge 80) {
            Write-Host "✅ Quality gate passed: $([math]::Round($passRate, 2))% pass rate meets enterprise standards" -ForegroundColor Yellow
        }
    }
}

if ($PassThru) {
    return $result
}

Write-Host "`n🎉 Test execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')!" -ForegroundColor Green