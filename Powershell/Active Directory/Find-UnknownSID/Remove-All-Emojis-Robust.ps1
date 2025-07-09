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
        
        # Read file as bytes to get true content
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Check if file contains Unicode characters beyond ASCII range
        $hasUnicode = $false
        for ($i = 0; $i -lt $content.Length; $i++) {
            if ([int]$content[$i] -gt 127) {
                $hasUnicode = $true
                break
            }
        }
        
        if ($hasUnicode) {
            Write-Host "  Found Unicode characters - cleaning..." -ForegroundColor Yellow
            
            # Remove all characters beyond ASCII range (0-127)
            $cleanContent = ""
            for ($i = 0; $i -lt $content.Length; $i++) {
                if ([int]$content[$i] -le 127) {
                    $cleanContent += $content[$i]
                }
            }
            
            # Write back to file
            [System.IO.File]::WriteAllText($file.FullName, $cleanContent, [System.Text.Encoding]::UTF8)
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
