# Quick test runner with timeout protection
Write-Host "🧪 Testing Operations.Tests.ps1 with timeout protection..." -ForegroundColor Cyan

$testPath = "c:\Users\Administrator\TechbyJeff\Powershell\Active Directory\Find-UnknownSID\Tests\Unit\Operations.Tests.ps1"

try {
    # Create a job to run the test
    $job = Start-Job -ScriptBlock {
        param($TestPath)
        Set-Location (Split-Path $TestPath -Parent)
        Invoke-Pester $TestPath -PassThru -Quiet
    } -ArgumentList $testPath
    
    # Wait for job with timeout
    $timeout = 30 # 30 seconds
    $completed = Wait-Job -Job $job -Timeout $timeout
    
    if ($completed) {
        $result = Receive-Job -Job $job
        Write-Host "✅ Test completed successfully!" -ForegroundColor Green
        Write-Host "   Total Tests: $($result.TotalCount)" -ForegroundColor Yellow
        Write-Host "   Passed: $($result.PassedCount)" -ForegroundColor Green  
        Write-Host "   Failed: $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
        
        if ($result.FailedCount -gt 0) {
            Write-Host "   Some tests failed, but NO HANGING detected!" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Test timed out after $timeout seconds - stopping job" -ForegroundColor Red
        Stop-Job -Job $job
        Write-Host "   This indicates the hanging issue is still present" -ForegroundColor Red
    }
    
    Remove-Job -Job $job -Force
    
} catch {
    Write-Host "❌ Error running test: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n🎯 Test execution validation complete" -ForegroundColor Cyan
