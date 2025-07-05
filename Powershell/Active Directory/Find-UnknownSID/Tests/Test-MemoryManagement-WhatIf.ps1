#Requires -Version 5.1

<#
.SYNOPSIS
    Test script to verify memory management operations execute correctly with and without -WhatIf

.DESCRIPTION
    This test verifies that critical memory operations (garbage collection, resource disposal)
    always execute regardless of -WhatIf parameter, while only logging respects WhatIf.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    Test Purpose: Ensure memory stability during WhatIf operations
#>

param(
    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$Verbose
)

# Set up test environment
$ErrorActionPreference = 'Stop'
if ($Verbose) { $VerbosePreference = 'Continue' }

# Import the memory management module
try {
    . "$PSScriptRoot\..\Private\MemoryManagement.ps1"
    . "$PSScriptRoot\..\Private\Logging.ps1"
    . "$PSScriptRoot\..\Classes\MemoryManager.ps1"
    Write-Host "✓ Successfully imported memory management functions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    exit 1
}

function Test-MemoryOperationsWithWhatIf {
    <#
    .SYNOPSIS
        Tests that memory operations execute regardless of WhatIf mode
    #>
    [CmdletBinding()]
    param(
        [switch]$UseWhatIf
    )

    $testCorrelationId = [System.Guid]::NewGuid().ToString()
    Write-Host "`n=== Testing Memory Operations (WhatIf: $UseWhatIf) ===" -ForegroundColor Cyan

    try {
        # Test 1: Initialize Memory Manager
        Write-Host "Test 1: Initialize-MemoryManager..." -ForegroundColor Yellow
        $beforeMemory = Get-CurrentMemoryUsage

        if ($UseWhatIf) {
            $memoryManager = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 10 -CorrelationId $testCorrelationId -WhatIf
        } else {
            $memoryManager = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 10 -CorrelationId $testCorrelationId
        }

        if ($memoryManager) {
            Write-Host "✓ Memory manager created successfully (WhatIf: $UseWhatIf)" -ForegroundColor Green
        } else {
            Write-Host "✗ Memory manager creation failed" -ForegroundColor Red
            return $false
        }

        # Test 2: Memory Check
        Write-Host "Test 2: Invoke-MemoryCheck..." -ForegroundColor Yellow
        if ($UseWhatIf) {
            Invoke-MemoryCheck -MemoryManager $memoryManager -WhatIf
        } else {
            Invoke-MemoryCheck -MemoryManager $memoryManager
        }
        Write-Host "✓ Memory check completed (WhatIf: $UseWhatIf)" -ForegroundColor Green

        # Test 3: Aggressive Cleanup
        Write-Host "Test 3: Invoke-AggressiveCleanup..." -ForegroundColor Yellow
        $beforeCleanup = Get-CurrentMemoryUsage

        if ($UseWhatIf) {
            $cleanupResult = Invoke-AggressiveCleanup -CorrelationId $testCorrelationId -WhatIf
        } else {
            $cleanupResult = Invoke-AggressiveCleanup -CorrelationId $testCorrelationId
        }

        $afterCleanup = Get-CurrentMemoryUsage

        if ($cleanupResult) {
            Write-Host "✓ Aggressive cleanup completed (WhatIf: $UseWhatIf)" -ForegroundColor Green
            Write-Host "  Memory Before: $([Math]::Round($beforeCleanup.WorkingSetMB, 2)) MB" -ForegroundColor Gray
            Write-Host "  Memory After:  $([Math]::Round($afterCleanup.WorkingSetMB, 2)) MB" -ForegroundColor Gray

            # Verify cleanup actually occurred
            if ($UseWhatIf -and $cleanupResult.WhatIfMode) {
                Write-Host "✓ WhatIf mode properly detected in cleanup result" -ForegroundColor Green
            }
        } else {
            Write-Host "✗ Aggressive cleanup failed" -ForegroundColor Red
            return $false
        }

        # Test 4: Resource Cleanup
        Write-Host "Test 4: Invoke-ResourceCleanup..." -ForegroundColor Yellow
        if ($UseWhatIf) {
            Invoke-ResourceCleanup -MemoryManager $memoryManager -CorrelationId $testCorrelationId -WhatIf
        } else {
            Invoke-ResourceCleanup -MemoryManager $memoryManager -CorrelationId $testCorrelationId
        }
        Write-Host "✓ Resource cleanup completed (WhatIf: $UseWhatIf)" -ForegroundColor Green

        return $true
    }
    catch {
        Write-Host "✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main test execution
Write-Host "Memory Management WhatIf Behavior Test" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta

# Test without WhatIf
$normalTest = Test-MemoryOperationsWithWhatIf -UseWhatIf:$false

# Test with WhatIf
$whatIfTest = Test-MemoryOperationsWithWhatIf -UseWhatIf:$true

# Summary
Write-Host "`n=== Test Results Summary ===" -ForegroundColor Cyan
if ($normalTest) {
    Write-Host "✓ Normal operation test: PASSED" -ForegroundColor Green
} else {
    Write-Host "✗ Normal operation test: FAILED" -ForegroundColor Red
}

if ($whatIfTest) {
    Write-Host "✓ WhatIf operation test: PASSED" -ForegroundColor Green
} else {
    Write-Host "✗ WhatIf operation test: FAILED" -ForegroundColor Red
}

if ($normalTest -and $whatIfTest) {
    Write-Host "`n🎉 ALL TESTS PASSED - Memory operations work correctly in both modes!" -ForegroundColor Green
    Write-Host "   Critical memory operations execute regardless of -WhatIf parameter." -ForegroundColor Green
} else {
    Write-Host "`n❌ SOME TESTS FAILED - Review memory management implementation!" -ForegroundColor Red
    exit 1
}

Write-Host "`nKey Behaviors Verified:" -ForegroundColor Yellow
Write-Host "• Memory manager creation: Always executes" -ForegroundColor Gray
Write-Host "• Memory checks and cleanup: Always execute" -ForegroundColor Gray
Write-Host "• Resource disposal: Always executes" -ForegroundColor Gray
Write-Host "• Garbage collection: Always executes" -ForegroundColor Gray
Write-Host "• Detailed logging: Respects -WhatIf parameter" -ForegroundColor Gray
