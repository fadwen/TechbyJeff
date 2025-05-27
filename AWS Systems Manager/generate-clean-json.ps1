# Simple working fix for Unicode characters
Write-Host "Fixing Unicode characters in JSON..." -ForegroundColor Cyan

$originalFile = "ssm-document-cached-dsc.json"

if (-not (Test-Path $originalFile)) {
    Write-Host "❌ File not found: $originalFile" -ForegroundColor Red
    exit 1
}

try {
    # Read the original file
    Write-Host "Reading original file..." -ForegroundColor Yellow
    $content = Get-Content $originalFile -Raw -Encoding UTF8

    # Replace Unicode characters with ASCII equivalents
    Write-Host "Removing Unicode characters..." -ForegroundColor Yellow
    $cleanContent = $content
    $cleanContent = $cleanContent -replace '✓', '[OK]'
    $cleanContent = $cleanContent -replace '⚠️', '[WARN]'
    $cleanContent = $cleanContent -replace '️', ''  # Remove any remaining variation selectors

    # Show what we're replacing
    if ($content -ne $cleanContent) {
        Write-Host "✓ Replaced Unicode characters" -ForegroundColor Green
    } else {
        Write-Host "No Unicode characters found to replace" -ForegroundColor Gray
    }

    # Save using Out-File (simpler than WriteAllText)
    $cleanFile = "ssm-document-clean.json"
    Write-Host "Saving clean file as: $cleanFile" -ForegroundColor Yellow

    $cleanContent | Out-File -FilePath $cleanFile -Encoding UTF8 -NoNewline

    # Verify file was created
    if (Test-Path $cleanFile) {
        $fileSize = (Get-Item $cleanFile).Length
        Write-Host "✓ File created successfully: $fileSize bytes" -ForegroundColor Green
        Write-Host "File location: $(Get-Item $cleanFile | Select-Object -ExpandProperty FullName)" -ForegroundColor Gray
    } else {
        Write-Host "❌ File was not created!" -ForegroundColor Red
        exit 1
    }

    # Test with AWS CLI
    Write-Host "Testing with AWS CLI..." -ForegroundColor Yellow
    aws ssm create-document --name "DSC-Apply-With-Caching" --document-type "Command" --content "file://$cleanFile" --document-format JSON

    if ($LASTEXITCODE -eq 0) {
        Write-Host "🎉 SUCCESS! Document created successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ AWS CLI still failed. Let's check the file content..." -ForegroundColor Red

        # Show first few lines of the clean file
        Write-Host "First 5 lines of clean file:" -ForegroundColor Yellow
        Get-Content $cleanFile | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

        Write-Host ""
        Write-Host "Try the manual AWS Console approach:" -ForegroundColor Yellow
        Write-Host "1. Copy file content: Get-Content $cleanFile -Raw | Set-Clipboard" -ForegroundColor White
        Write-Host "2. Go to AWS Console > Systems Manager > Documents" -ForegroundColor White
        Write-Host "3. Create document manually" -ForegroundColor White
    }

} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Gray
    Write-Host "Files in directory:" -ForegroundColor Gray
    Get-ChildItem *.json | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Gray }
}