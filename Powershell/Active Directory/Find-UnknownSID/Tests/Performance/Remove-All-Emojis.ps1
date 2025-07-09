# Simple script to remove ALL Unicode emojis from Performance test files
# No replacements - just remove them completely

param(
    [string]$Path = "."
)

Write-Host "Removing ALL Unicode emojis from Performance test files..." -ForegroundColor Cyan

$performanceFiles = Get-ChildItem -Path $Path -Filter "*.ps1" | Where-Object { $_.Name -like "*ModuleIndependent*" -or $_.Name -like "*Performance*" -or $_.Name -like "*Tests.ps1" }

foreach ($file in $performanceFiles) {
    Write-Host "Processing: $($file.Name)" -ForegroundColor Yellow
    
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    
    # Remove all non-ASCII characters (anything outside 0-127 range)
    $cleanContent = $content -replace '[^\x00-\x7F]', ''
    
    # Write back with UTF8 encoding (no BOM)
    [System.IO.File]::WriteAllText($file.FullName, $cleanContent, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "  -> Cleaned: $($file.Name)" -ForegroundColor Green
}

Write-Host "All Unicode emojis removed from Performance test files!" -ForegroundColor Green
