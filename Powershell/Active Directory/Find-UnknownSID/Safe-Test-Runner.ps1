# Safe Test Runner with Timeout Protection
param(
    [string]$TestPath,
    [int]$TimeoutSeconds = 30
)

Write-Host "🧪 Running test: $TestPath with ${TimeoutSeconds}s timeout" -ForegroundColor Cyan

try {
    $job = Start-Job -ScriptBlock {
        param($path)
        Import-Module Pester -Force
        Invoke-Pester -Path $path -PassThru
    } -ArgumentList $TestPath

    if (Wait-Job $job -Timeout $TimeoutSeconds) {
        $result = Receive-Job $job
        Remove-Job $job
        
        Write-Host "✅ Test completed successfully" -ForegroundColor Green
        Write-Host "📊 Passed: $($result.PassedCount) | Failed: $($result.FailedCount) | Total: $($result.TotalCount)" -ForegroundColor White
        
        return $result
    } else {
        Remove-Job $job -Force
        Write-Host "⏰ TEST TIMEOUT: $TestPath exceeded ${TimeoutSeconds} seconds" -ForegroundColor Red
        return $null
    }
} catch {
    Write-Host "❌ Test execution error: $($_.Exception.Message)" -ForegroundColor Red
    return $null
}
