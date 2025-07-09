#Requires -Version 5.1

<#
.SYNOPSIS
    Converts Pester 5.x test files to Pester 3.x syntax for PowerShell 5.1 compatibility

.DESCRIPTION
    Systematically converts all test files from Pester 5.x syntax to Pester 3.x syntax by:
    - Removing BeforeAll blocks and moving content to script level
    - Converting Should assertions from -Parameter format to space format
    - Handling PowerShell 5.1 compatibility issues

.EXAMPLE
    .\Convert-PesterSyntax.ps1
    Converts all test files in the current Tests directory structure
#>

[CmdletBinding()]
param(
    [string]$TestsPath = ".\Tests",
    [switch]$WhatIf
)

function Convert-PesterFile {
    param(
        [string]$FilePath,
        [switch]$WhatIf
    )
    
    Write-Host "Converting: $FilePath" -ForegroundColor Cyan
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        $originalContent = $content
        
        # Step 1: Handle BeforeAll blocks
        if ($content -match '(?s)BeforeAll\s*\{.*?\n\}') {
            Write-Host "  - Converting BeforeAll block..." -ForegroundColor Yellow
            
            # Extract the content inside BeforeAll block
            $beforeAllMatch = [regex]::Match($content, '(?s)BeforeAll\s*\{\s*(.*?)\n\}')
            if ($beforeAllMatch.Success) {
                $beforeAllContent = $beforeAllMatch.Groups[1].Value
                
                # Remove the BeforeAll wrapper
                $replacement = $beforeAllContent -replace '^\s+', '' -replace '\n\s+', "`n"
                
                # Replace the entire BeforeAll block
                $content = $content -replace '(?s)BeforeAll\s*\{.*?\n\}', $replacement
            }
        }
        
        # Step 2: Convert Should assertions
        Write-Host "  - Converting Should assertions..." -ForegroundColor Yellow
        
        # Core Should operators
        $content = $content -replace 'Should -Be ', 'Should Be '
        $content = $content -replace 'Should -Not -Be ', 'Should Not Be '
        $content = $content -replace 'Should -BeExactly ', 'Should BeExactly '
        $content = $content -replace 'Should -Not -BeExactly ', 'Should Not BeExactly '
        
        # Null/Empty checks
        $content = $content -replace 'Should -BeNullOrEmpty', 'Should BeNullOrEmpty'
        $content = $content -replace 'Should -Not -BeNullOrEmpty', 'Should Not BeNullOrEmpty'
        
        # Type checks
        $content = $content -replace 'Should -BeOfType ', 'Should BeOfType '
        $content = $content -replace 'Should -Not -BeOfType ', 'Should Not BeOfType '
        
        # Comparison operators
        $content = $content -replace 'Should -BeGreaterThan ', 'Should BeGreaterThan '
        $content = $content -replace 'Should -BeGreaterOrEqual ', 'Should BeGreaterThan '
        $content = $content -replace 'Should -BeLessThan ', 'Should BeLessThan '
        $content = $content -replace 'Should -BeLessOrEqual ', 'Should BeLessThan '
        
        # Pattern matching
        $content = $content -replace 'Should -Match ', 'Should Match '
        $content = $content -replace 'Should -Not -Match ', 'Should Not Match '
        
        # Collection operations
        $content = $content -replace 'Should -Contain ', 'Should Contain '
        $content = $content -replace 'Should -Not -Contain ', 'Should Not Contain '
        $content = $content -replace 'Should -BeIn ', 'Should BeIn '
        $content = $content -replace 'Should -Not -BeIn ', 'Should Not BeIn '
        
        # File/Path operations
        $content = $content -replace 'Should -Exist', 'Should Exist'
        $content = $content -replace 'Should -Not -Exist', 'Should Not Exist'
        
        # Exception handling
        $content = $content -replace 'Should -Throw', 'Should Throw'
        $content = $content -replace 'Should -Not -Throw', 'Should Not Throw'
        
        # Mock operations
        $content = $content -replace 'Should -Invoke ', 'Should Invoke '
        $content = $content -replace 'Should -Not -Invoke ', 'Should Not Invoke '
        
        # Step 3: Handle specific PowerShell 5.1 incompatibilities
        Write-Host "  - Fixing PowerShell 5.1 compatibility..." -ForegroundColor Yellow
        
        # Convert ternary operators if any exist
        $content = $content -replace '\$\(([^)]+)\)\s*\?\s*([^:]+)\s*:\s*([^)]+)', 'if ($1) { $2 } else { $3 }'
        
        if (-not $WhatIf) {
            Set-Content $FilePath $content -Encoding UTF8
            Write-Host "  ✅ Conversion completed" -ForegroundColor Green
        } else {
            Write-Host "  ℹ️  WhatIf: Changes would be applied" -ForegroundColor Blue
        }
        
        return @{
            FilePath = $FilePath
            Success = $true
            Changes = $content -ne $originalContent
            ErrorMessage = $null
        }
    }
    catch {
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            FilePath = $FilePath
            Success = $false
            Changes = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Main execution
Write-Host "Pester 5.x to 3.x Conversion Tool" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

if ($WhatIf) {
    Write-Host "Running in WhatIf mode - no files will be modified" -ForegroundColor Yellow
}

# Find all test files
$testFiles = Get-ChildItem -Path $TestsPath -Filter "*.Tests.ps1" -Recurse
Write-Host "Found $($testFiles.Count) test files to convert" -ForegroundColor Cyan

$results = @()
$successCount = 0
$errorCount = 0

foreach ($testFile in $testFiles) {
    $result = Convert-PesterFile -FilePath $testFile.FullName -WhatIf:$WhatIf
    $results += $result
    
    if ($result.Success) {
        $successCount++
    } else {
        $errorCount++
    }
}

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "Conversion Summary:" -ForegroundColor Green
Write-Host "  Total files: $($testFiles.Count)" -ForegroundColor White
Write-Host "  Successful: $successCount" -ForegroundColor Green
Write-Host "  Errors: $errorCount" -ForegroundColor Red

if ($errorCount -gt 0) {
    Write-Host ""
    Write-Host "Files with errors:" -ForegroundColor Red
    $results | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "  - $($_.FilePath): $($_.ErrorMessage)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Conversion completed!" -ForegroundColor Green
