[CmdletBinding()]
param(
    [string]$TargetPath = "Tests"
)

Write-Host "Starting Unicode emoji removal from: $TargetPath" -ForegroundColor Green

$processedFiles = 0

if (Test-Path $TargetPath) {
    if ((Get-Item $TargetPath).PSIsContainer) {
        # It's a directory
        $files = Get-ChildItem -Path $TargetPath -Recurse -Filter "*.ps1"
    } else {
        # It's a single file
        $files = @(Get-Item $TargetPath)
    }
    
    foreach ($file in $files) {
        Write-Host "Processing: $($file.FullName)" -ForegroundColor Cyan
        
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        
        # Check if file contains Unicode characters
        if ($content -match '[^\x00-\x7F]') {
            Write-Host "  Found Unicode characters - cleaning..." -ForegroundColor Yellow
            
            # Remove all non-ASCII characters (including emojis)
            $cleanContent = $content -replace '[^\x00-\x7F]', ''
            
            # Write back to file
            Set-Content -Path $file.FullName -Value $cleanContent -Encoding UTF8 -NoNewline
            $processedFiles++
            
            Write-Host "  Cleaned successfully" -ForegroundColor Green
        } else {
            Write-Host "  No Unicode characters found" -ForegroundColor Gray
        }
    }
} else {
    Write-Error "Path not found: $TargetPath"
}

Write-Host "`nProcessing complete. Files modified: $processedFiles" -ForegroundColor Green
