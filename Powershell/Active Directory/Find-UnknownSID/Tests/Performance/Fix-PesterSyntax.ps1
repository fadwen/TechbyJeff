# Quick fix script to convert Pester 5.x syntax to Pester 3.x syntax
param(
    [string]$FilePath = ".\Stress-Testing-ModuleIndependent.Tests.ps1"
)

$content = Get-Content -Path $FilePath -Raw

# Convert Should assertions from Pester 5.x to Pester 3.x syntax
$content = $content -replace '\| Should -Not -BeNullOrEmpty', '| Should Not BeNullOrEmpty'
$content = $content -replace '\| Should -Be \$true', '| Should Be $true'
$content = $content -replace '\| Should -Be \$false', '| Should Be $false'
$content = $content -replace '\| Should -BeGreaterThan', '| Should BeGreaterThan'
$content = $content -replace '\| Should -BeLessThan', '| Should BeLessThan'
$content = $content -replace '\| Should -Not -Be', '| Should Not Be'
$content = $content -replace '\| Should -BeNullOrEmpty', '| Should BeNullOrEmpty'

# Fix Write-Host line with PowerShell version
$content = $content -replace 'PowerShell: \$\(\$PSVersionTable', 'PS: $($PSVersionTable'

Set-Content -Path $FilePath -Value $content -Encoding UTF8
Write-Host " Fixed Pester syntax for PowerShell 5.1 compatibility" -ForegroundColor Green
