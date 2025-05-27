# S3 Transfer Acceleration Setup
# Save as: Set-S3Accelerate.ps1
# Run once to enable faster S3 downloads for your DSC configurations

param(
    [Parameter(Mandatory)]
    [string]$BucketName = "systems-manager-windows-server-dsc-configurations"
)

Write-Host "Setting up S3 Transfer Acceleration for bucket: $BucketName" -ForegroundColor Cyan

try {
    # Enable S3 Transfer Acceleration
    aws s3api put-bucket-accelerate-configuration `
        --bucket $BucketName `
        --accelerate-configuration Status=Enabled

    Write-Host "✓ S3 Transfer Acceleration enabled successfully" -ForegroundColor Green

    # Verify it was enabled
    $config = aws s3api get-bucket-accelerate-configuration --bucket $BucketName --output json | ConvertFrom-Json

    if ($config.Status -eq "Enabled") {
        Write-Host "✓ Acceleration confirmed enabled" -ForegroundColor Green
        Write-Host "Your accelerated endpoint will be: https://$BucketName.s3-accelerate.amazonaws.com" -ForegroundColor White
    } else {
        Write-Host "⚠️  Acceleration may not be fully enabled yet" -ForegroundColor Yellow
    }

} catch {
    Write-Host "❌ Failed to enable S3 Transfer Acceleration: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check that:" -ForegroundColor Yellow
    Write-Host "  - You have s3:PutAccelerateConfiguration permission" -ForegroundColor Gray
    Write-Host "  - The bucket name is correct" -ForegroundColor Gray
    Write-Host "  - AWS CLI is configured properly" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "S3 Transfer Acceleration setup complete!" -ForegroundColor Green
Write-Host "This will speed up MOF file downloads globally." -ForegroundColor White