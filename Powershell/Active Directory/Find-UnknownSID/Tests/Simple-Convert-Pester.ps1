# Simple Pester 5.x to 3.x conversion script
param(
    [string]$TestsPath = ".\Tests"
)

Write-Host "Converting Pester 5.x to 3.x syntax..." -ForegroundColor Green

# Find all test files
$testFiles = Get-ChildItem -Path $TestsPath -Filter "*.Tests.ps1" -Recurse
Write-Host "Found $($testFiles.Count) test files to convert"

$convertedCount = 0

foreach ($testFile in $testFiles) {
    Write-Host "Converting: $($testFile.Name)" -ForegroundColor Cyan
    
    try {
        $content = Get-Content $testFile.FullName -Raw -Encoding UTF8
        $originalLength = $content.Length
        
        # Remove BeforeAll blocks - simplified approach
        $content = $content -replace '(?s)BeforeAll\s*\{\s*', ''
        $content = $content -replace '(?m)^\s*\}\s*$(?=\s*Describe)', ''
        
        # Convert Should assertions
        $content = $content -replace 'Should -Be ', 'Should Be '
        $content = $content -replace 'Should -Not -Be ', 'Should Not Be '
        $content = $content -replace 'Should -BeExactly ', 'Should BeExactly '
        $content = $content -replace 'Should -Not -BeExactly ', 'Should Not BeExactly '
        $content = $content -replace 'Should -BeNullOrEmpty', 'Should BeNullOrEmpty'
        $content = $content -replace 'Should -Not -BeNullOrEmpty', 'Should Not BeNullOrEmpty'
        $content = $content -replace 'Should -BeOfType ', 'Should BeOfType '
        $content = $content -replace 'Should -Not -BeOfType ', 'Should Not BeOfType '
        $content = $content -replace 'Should -BeGreaterThan ', 'Should BeGreaterThan '
        $content = $content -replace 'Should -BeGreaterOrEqual ', 'Should BeGreaterThan '
        $content = $content -replace 'Should -BeLessThan ', 'Should BeLessThan '
        $content = $content -replace 'Should -BeLessOrEqual ', 'Should BeLessThan '
        $content = $content -replace 'Should -Match ', 'Should Match '
        $content = $content -replace 'Should -Not -Match ', 'Should Not Match '
        $content = $content -replace 'Should -Contain ', 'Should Contain '
        $content = $content -replace 'Should -Not -Contain ', 'Should Not Contain '
        $content = $content -replace 'Should -BeIn ', 'Should BeIn '
        $content = $content -replace 'Should -Not -BeIn ', 'Should Not BeIn '
        $content = $content -replace 'Should -Exist', 'Should Exist'
        $content = $content -replace 'Should -Not -Exist', 'Should Not Exist'
        $content = $content -replace 'Should -Throw', 'Should Throw'
        $content = $content -replace 'Should -Not -Throw', 'Should Not Throw'
        $content = $content -replace 'Should -Invoke ', 'Should Invoke '
        $content = $content -replace 'Should -Not -Invoke ', 'Should Not Invoke '
        
        if ($content.Length -ne $originalLength) {
            Set-Content $testFile.FullName $content -Encoding UTF8
            $convertedCount++
            Write-Host "  ✓ Converted" -ForegroundColor Green
        } else {
            Write-Host "  - No changes needed" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Conversion completed! Converted $convertedCount files." -ForegroundColor Green
