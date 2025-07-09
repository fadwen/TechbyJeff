#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive test execution script for Find-UnknownSID gap resolution validation

.DESCRIPTION
    Executes all test categories (Unit, Integration, Security, Performance) to validate
    the gap resolution implementation and ensure enterprise-ready testing coverage.

.PARAMETER TestType
    Type of tests to run: Unit, Integration, Security, Performance, or All

.PARAMETER OutputPath
    Path for test results and reports

.PARAMETER CodeCoverage
    Enable code coverage analysis

.PARAMETER PassThru
    Return test results object

.EXAMPLE
    .\Invoke-GapResolutionTests.ps1 -TestType All -OutputPath ".\TestResults"

.EXAMPLE
    .\Invoke-GapResolutionTests.ps1 -TestType Integration -CodeCoverage

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    Version: 1.0.0
    PowerShell Version: 5.1+

    TROUBLESHOOTING:
    - For test execution issues: .\Troubleshooting\Testing\Test-Execution-Issues.md
    - For coverage problems: .\Troubleshooting\Testing\Coverage-Analysis.md
#>

[CmdletBinding()]
param(
    [ValidateSet('Unit', 'Integration', 'Security', 'Performance', 'All')]
    [string]$TestType = 'All',

    [string]$OutputPath = './Tests/TestResults',

    [switch]$CodeCoverage,

    [switch]$PassThru,

    [switch]$SuppressConsoleOutput,

    [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
)

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Initialize test environment with module loading
Write-Host "Initializing test environment..." -ForegroundColor Yellow
try {
    $testsPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $infrastructurePath = Split-Path -Parent $testsPath  # Get Infrastructure directory
    $testsRoot = Split-Path -Parent $infrastructurePath  # Get Tests directory
    $projectRoot = Split-Path -Parent $testsRoot  # Get project root
    $testBootstrapper = Join-Path $infrastructurePath "TestBootstrapper.ps1"

    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
        $initResult = Initialize-TestEnvironment -ProjectRoot $projectRoot -SuppressConsoleOutput:$SuppressConsoleOutput
        if ($initResult) {
            Write-Host "Test environment initialized successfully" -ForegroundColor Green

            # Display environment status  
            $envStatus = Get-TestEnvironmentStatus
            Write-Host "Test Environment Status:" -ForegroundColor Green
            Write-Host "  Correlation ID: $($envStatus.CorrelationId)" -ForegroundColor White
            Write-Host "  Critical Functions Available: $($envStatus.CriticalFunctionStatus.Values | Where-Object { $_ } | Measure-Object).Count / $($envStatus.CriticalFunctionStatus.Count)" -ForegroundColor White
            Write-Host "  Loaded Aliases: $($envStatus.LoadedAliases.Count)" -ForegroundColor White
        } else {
            Write-Warning "Test environment initialization failed, but continuing with tests"
        }
    } else {
        Write-Warning "Test module loader not found: $testModuleLoader"
    }
} catch {
    Write-Warning "Failed to initialize test environment: $($_.Exception.Message)"
    Write-Host "Continuing with basic Pester testing..." -ForegroundColor Yellow
}

# Verify Pester is available
try {
    Import-Module Pester -MinimumVersion 5.0 -Force -ErrorAction Stop
    $pesterVersion = (Get-Module Pester).Version
    Write-Host "Pester Version: $pesterVersion" -ForegroundColor Green
} catch {
    Write-Error "Pester 5.0+ is required but not available: $($_.Exception.Message)"
    throw "Missing test dependency: Pester 5.0+"
}

Write-Host "Find-UnknownSID Gap Resolution Test Execution" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Test Type: $TestType" -ForegroundColor White
Write-Host "Output Path: $OutputPath" -ForegroundColor White
Write-Host "Code Coverage: $($CodeCoverage.IsPresent)" -ForegroundColor White
Write-Host "Correlation ID: $CorrelationId" -ForegroundColor White
Write-Host ""

# Test execution configuration
$testConfig = @{
    Unit = @{
        Path = "..\Unit\"
        Description = "Unit Tests - Foundation validation"
        TimeoutMinutes = 5
        ExpectedTests = 656
        Files = @(
            'ACL.Tests.ps1', 'ActiveDirectory.Tests.ps1', 'Backup.Tests.ps1',
            'ClassManagement.Tests.ps1', 'Core.Tests.ps1', 'FileSystem.Tests.ps1',
            'Logging.Tests.ps1', 'Operations.Tests.ps1', 'Reporting.Tests.ps1',
            'Security.Tests.ps1', 'SID.Tests.ps1', 'System.Tests.ps1',
            'Test-BackupValidation.Tests.ps1', 'SIDValidation.Tests.ps1', 'SimpleValidation.Tests.ps1'
        )
    }
    Integration = @{
        Path = "..\Integration\"
        Description = "Integration Tests - End-to-end workflow validation"
        TimeoutMinutes = 10
        ExpectedTests = 55
        Files = @(
            'Integration.Tests.ps1',
            'ActiveDirectory-Integration.Tests.ps1',
            'FileSystem-Integration.Tests.ps1',
            'Batch-Operations.Tests.ps1'
        )
    }
    Security = @{
        Path = "..\Security\"
        Description = "Security Tests - Injection prevention and compliance"
        TimeoutMinutes = 18
        ExpectedTests = 85
        Files = @(
            'Injection-Prevention.Tests.ps1',
            'Privilege-Escalation.Tests.ps1',
            'Compliance-Validation.Tests.ps1',
            'Penetration-Testing.Tests.ps1'
        )
    }
    Performance = @{
        Path = "..\Performance\"
        Description = "Performance Tests - Large-scale and optimization"
        TimeoutMinutes = 45
        ExpectedTests = 185
        Files = @(
            'Large-Scale.Tests.ps1',
            'Memory-Profiling.Tests.ps1',
            'Concurrent-Operations.Tests.ps1',
            'Stress-Testing.Tests.ps1',
            'PowerShell-Versions.Tests.ps1',
            'Cloud-Platforms.Tests.ps1',
            'Business-Intelligence.Tests.ps1',
            'CI-CD-Integration.Tests.ps1'
        )
    }
}

# Summary tracking
$executionSummary = @{
    StartTime = Get-Date
    TestsExecuted = @()
    TotalTests = 0
    TotalPassed = 0
    TotalFailed = 0
    TotalDuration = [TimeSpan]::Zero
    CorrelationId = $CorrelationId
}

function Invoke-TestCategory {
    param(
        [string]$Category,
        [hashtable]$Config,
        [string]$OutputPath,
        [switch]$CodeCoverage,
        [string]$CorrelationId
    )

    # Resolve the test path correctly using script-level variables
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Config.Path)) {
        $Config.Path
    } else {
        # Convert relative path to absolute based on testsRoot 
        $relativePath = $Config.Path -replace '^\.\.[/\\]', ''  # Remove ../ or ..\ prefix
        Join-Path $testsRoot $relativePath
    }
    
    Write-Host " Executing $Category Tests..." -ForegroundColor Yellow
    Write-Host "   $($Config.Description)" -ForegroundColor Gray
    Write-Host "   Path: $resolvedPath" -ForegroundColor Gray
    Write-Host "   Timeout: $($Config.TimeoutMinutes) minutes" -ForegroundColor Gray
    Write-Host ""

    # Check if test path exists
    if (-not (Test-Path $resolvedPath)) {
        Write-Warning "Test path not found: $resolvedPath"
        return @{
            Category = $Category
            Status = 'Skipped'
            Reason = 'Path not found'
            Tests = @{ Total = 0; Passed = 0; Failed = 0 }
            Duration = [TimeSpan]::Zero
        }
    }

    # Check for test files
    $testFiles = Get-ChildItem -Path $resolvedPath -Filter "*.Tests.ps1" -Recurse
    if ($testFiles.Count -eq 0) {
        Write-Warning "No test files found in: $($Config.Path)"
        return @{
            Category = $Category
            Status = 'Skipped'
            Reason = 'No test files'
            Tests = @{ Total = 0; Passed = 0; Failed = 0 }
            Duration = [TimeSpan]::Zero
        }
    }

    Write-Host "   Found $($testFiles.Count) test file(s)" -ForegroundColor Gray

    try {
        # Configure Pester
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = $resolvedPath
        $pesterConfig.Output.Verbosity = 'Detailed'
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputPath = Join-Path $OutputPath "TestResults-$Category-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"

        if ($CodeCoverage) {
            $pesterConfig.CodeCoverage.Enabled = $true
            $pesterConfig.CodeCoverage.Path = "..\..\Private\**\*.ps1"
            $pesterConfig.CodeCoverage.OutputPath = Join-Path $OutputPath "Coverage-$Category-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
        }

        # Execute tests with timeout
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-Pester -Configuration $pesterConfig
        $stopwatch.Stop()

        # Calculate results
        $testSummary = @{
            Category = $Category
            Status = if ($result.Failed.Count -eq 0) { 'Passed' } else { 'Failed' }
            Tests = @{
                Total = $result.Tests.Count
                Passed = $result.Tests.Passed.Count
                Failed = $result.Tests.Failed.Count
                Skipped = $result.Tests.Skipped.Count
            }
            Duration = $stopwatch.Elapsed
            Coverage = if ($CodeCoverage -and $result.CodeCoverage) {
                [math]::Round($result.CodeCoverage.CoveredPercent, 2)
            } else {
                $null
            }
            FailedTests = $result.Tests.Failed | ForEach-Object {
                @{
                    Name = $_.Name
                    ErrorRecord = $_.ErrorRecord.Exception.Message
                }
            }
        }

        # Display results
        Write-Host "   Tests: $($testSummary.Tests.Passed)/$($testSummary.Tests.Total)" -ForegroundColor Green
        if ($testSummary.Tests.Failed -gt 0) {
            Write-Host "   Failed: $($testSummary.Tests.Failed)" -ForegroundColor Red
        }
        if ($testSummary.Tests.Skipped -gt 0) {
            Write-Host "   Skipped: $($testSummary.Tests.Skipped)" -ForegroundColor Yellow
        }
        Write-Host "   Duration: $($testSummary.Duration.ToString('mm\:ss'))" -ForegroundColor Gray

        if ($testSummary.Coverage) {
            $coverageColor = if ($testSummary.Coverage -ge 80) { 'Green' } elseif ($testSummary.Coverage -ge 60) { 'Yellow' } else { 'Red' }
            Write-Host "   Coverage: $($testSummary.Coverage)%" -ForegroundColor $coverageColor
        }

        return $testSummary

    } catch {
        Write-Error "Failed to execute $Category tests: $($_.Exception.Message)"
        return @{
            Category = $Category
            Status = 'Error'
            Error = $_.Exception.Message
            Tests = @{ Total = 0; Passed = 0; Failed = 0 }
            Duration = [TimeSpan]::Zero
        }
    }

    Write-Host ""
}

# Execute tests based on type
$categoriesToRun = if ($TestType -eq 'All') {
    @('Unit', 'Integration', 'Security', 'Performance')
} else {
    @($TestType)
}

foreach ($category in $categoriesToRun) {
    if ($testConfig.ContainsKey($category)) {
        $result = Invoke-TestCategory -Category $category -Config $testConfig[$category] -OutputPath $OutputPath -CodeCoverage:$CodeCoverage -CorrelationId $CorrelationId
        $executionSummary.TestsExecuted += $result
        $executionSummary.TotalTests += $result.Tests.Total
        $executionSummary.TotalPassed += $result.Tests.Passed
        $executionSummary.TotalFailed += $result.Tests.Failed
        $executionSummary.TotalDuration = $executionSummary.TotalDuration.Add($result.Duration)
    }
}

$executionSummary.EndTime = Get-Date

# Generate comprehensive summary report
Write-Host "Test Execution Summary" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host "Start Time: $($executionSummary.StartTime)" -ForegroundColor White
Write-Host "End Time: $($executionSummary.EndTime)" -ForegroundColor White
Write-Host "Total Duration: $($executionSummary.TotalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Correlation ID: $($executionSummary.CorrelationId)" -ForegroundColor White
Write-Host ""

Write-Host "Overall Results:" -ForegroundColor White
Write-Host "   Total Tests: $($executionSummary.TotalTests)" -ForegroundColor White
$passedColor = if ($executionSummary.TotalPassed -eq $executionSummary.TotalTests) { 'Green' } else { 'Yellow' }
Write-Host "   Passed: $($executionSummary.TotalPassed)" -ForegroundColor $passedColor
if ($executionSummary.TotalFailed -gt 0) {
    Write-Host "   Failed: $($executionSummary.TotalFailed)" -ForegroundColor Red
}

# Category breakdown
Write-Host ""
Write-Host "Category Breakdown:" -ForegroundColor White
foreach ($result in $executionSummary.TestsExecuted) {
    $statusIcon = switch ($result.Status) {
        'Passed' { '[PASS]' }
        'Failed' { '[FAIL]' }
        'Skipped' { '[SKIP]' }
        'Error' { '[ERROR]' }
        default { '[UNKNOWN]' }
    }

    Write-Host "   $statusIcon $($result.Category): $($result.Tests.Passed)/$($result.Tests.Total)" -ForegroundColor White

    if ($result.Tests.Failed -gt 0 -and $result.FailedTests) {
        foreach ($failedTest in $result.FailedTests) {
            Write-Host "      [FAIL] $($failedTest.Name)" -ForegroundColor Red
            Write-Host "         $($failedTest.ErrorRecord)" -ForegroundColor DarkRed
        }
    }
}

# Gap resolution progress
Write-Host ""
Write-Host "Gap Resolution Progress:" -ForegroundColor Cyan

$gapProgress = @{
    Integration = @{
        Target = 80
        Current = if ($executionSummary.TestsExecuted | Where-Object Category -eq 'Integration') {
            $integrationResult = $executionSummary.TestsExecuted | Where-Object Category -eq 'Integration'
            if ($integrationResult.Tests.Total -gt 0) {
                [math]::Round(($integrationResult.Tests.Passed / $integrationResult.Tests.Total) * 100, 1)
            } else { 0 }
        } else { 0 }
    }
    Security = @{
        Target = 85
        Current = if ($executionSummary.TestsExecuted | Where-Object Category -eq 'Security') {
            $securityResult = $executionSummary.TestsExecuted | Where-Object Category -eq 'Security'
            if ($securityResult.Tests.Total -gt 0) {
                [math]::Round(($securityResult.Tests.Passed / $securityResult.Tests.Total) * 100, 1)
            } else { 0 }
        } else { 0 }
    }
    Performance = @{
        Target = 75
        Current = if ($executionSummary.TestsExecuted | Where-Object Category -eq 'Performance') {
            $performanceResult = $executionSummary.TestsExecuted | Where-Object Category -eq 'Performance'
            if ($performanceResult.Tests.Total -gt 0) {
                [math]::Round(($performanceResult.Tests.Passed / $performanceResult.Tests.Total) * 100, 1)
            } else { 0 }
        } else { 0 }
    }
}

foreach ($gap in $gapProgress.GetEnumerator()) {
    $progressColor = if ($gap.Value.Current -ge $gap.Value.Target) { 'Green' } elseif ($gap.Value.Current -ge ($gap.Value.Target * 0.7)) { 'Yellow' } else { 'Red' }
    Write-Host "   $($gap.Key): $($gap.Value.Current)% (Target: $($gap.Value.Target)%)" -ForegroundColor $progressColor
}

# Save detailed results
$summaryPath = Join-Path $OutputPath "Gap-Resolution-Summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$executionSummary | ConvertTo-Json -Depth 10 | Out-File $summaryPath

Write-Host ""
Write-Host "Detailed results saved to: $summaryPath" -ForegroundColor Gray

# Final status
if ($executionSummary.TotalFailed -eq 0 -and $executionSummary.TotalTests -gt 0) {
    Write-Host ""
    Write-Host " All tests passed! Gap resolution implementation validated." -ForegroundColor Green
    $exitCode = 0
} elseif ($executionSummary.TotalTests -eq 0) {
    Write-Host ""
    Write-Warning "No tests were executed. Please check test paths and files."
    $exitCode = 1
} else {
    Write-Host ""
    Write-Host " Some tests failed. Gap resolution implementation needs attention." -ForegroundColor Red
    $exitCode = 1
}

if ($PassThru) {
    return $executionSummary
} else {
    exit $exitCode
}

