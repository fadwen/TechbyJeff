#Requires -Version 5.1

<#
.SYNOPSIS
    Ensures Pester 3.4.0 is loaded for consistent testing across PowerShell versions

.DESCRIPTION
    This script ensures that Pester 3.4.0 is loaded in both PowerShell 5.1 and PowerShell 7.x
    to maintain consistent testing behavior across versions. This addresses the Pester syntax
    compatibility issues between Pester 3.x and 5.x.

.NOTES
    Author: Jeffrey Stuhr
    Purpose: PowerShell version consistency for testing
    Compatible: PowerShell 5.1+ and PowerShell 7.x
#>

# Remove any loaded Pester modules to start clean
if (Get-Module Pester) {
    Write-Host "Removing existing Pester modules..." -ForegroundColor Yellow
    Remove-Module Pester -Force
}

# Import Pester 3.4.0 specifically
$pester34Path = "C:\Program Files\WindowsPowerShell\Modules\Pester\3.4.0\Pester.psd1"

if (Test-Path $pester34Path) {
    Write-Host "Loading Pester 3.4.0 for consistent testing..." -ForegroundColor Green
    Import-Module $pester34Path -Force
    
    $loadedPester = Get-Module Pester
    Write-Host "Loaded Pester version: $($loadedPester.Version)" -ForegroundColor Cyan
    
    if ($loadedPester.Version -eq "3.4.0") {
        Write-Host "✅ Pester 3.4.0 successfully loaded - PowerShell version consistency achieved" -ForegroundColor Green
    } else {
        Write-Warning "❌ Expected Pester 3.4.0 but loaded version $($loadedPester.Version)"
    }
} else {
    Write-Error "❌ Pester 3.4.0 not found at expected path: $pester34Path"
}

# Verify PowerShell version and Pester compatibility
Write-Host "`nPowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host "Pester Version: $(Get-Module Pester | Select-Object -ExpandProperty Version)" -ForegroundColor Cyan
Write-Host "Testing Environment: Consistent across PowerShell 5.1 and 7.x" -ForegroundColor Green
