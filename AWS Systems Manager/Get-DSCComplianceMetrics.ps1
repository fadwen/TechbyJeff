# Complete DSC Monitoring Setup using JSON file method
Write-Host "Setting up complete DSC monitoring using JSON file approach..." -ForegroundColor Cyan

# Full monitoring script - no AWS CLI needed on instances, just detailed logging
$fullMonitoringScript = @'
function Write-DSCLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry

    # Write to log file for CloudWatch Logs
    $logFile = "C:\Logs\DSC\dsc-monitoring.log"
    $logDir = Split-Path $logFile
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
}

try {
    # Get instance info
    try {
        $instanceId = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -TimeoutSec 3)
    } catch {
        $instanceId = $env:COMPUTERNAME
        Write-DSCLog "Using computer name as instance ID: $instanceId" -Level "WARN"
    }

    Write-DSCLog "=== Starting DSC Compliance Check ===" -Level "INFO"
    Write-DSCLog "Instance: $instanceId" -Level "INFO"
    Write-DSCLog "Timestamp: $(Get-Date)" -Level "INFO"

    # Get DSC status
    Write-DSCLog "Running Test-DscConfiguration..." -Level "INFO"
    $dscStatus = Test-DscConfiguration -Detailed

    # Calculate compliance
    $totalResources = $dscStatus.ResourcesInDesiredState.Count + $dscStatus.ResourcesNotInDesiredState.Count
    $compliantResources = $dscStatus.ResourcesInDesiredState.Count
    $nonCompliantResources = $dscStatus.ResourcesNotInDesiredState.Count

    $compliancePercentage = if ($totalResources -gt 0) {
        [math]::Round(($compliantResources / $totalResources) * 100, 2)
    } else { 0 }

    Write-DSCLog "=== DSC Compliance Results ===" -Level "INFO"
    Write-DSCLog "Total Resources: $totalResources" -Level "INFO"
    Write-DSCLog "Compliant Resources: $compliantResources" -Level "INFO"
    Write-DSCLog "Non-Compliant Resources: $nonCompliantResources" -Level "INFO"
    Write-DSCLog "Compliance Percentage: $compliancePercentage%" -Level "INFO"

    # Log metric in parseable format for dashboard
    Write-DSCLog "METRIC|DSC_Compliance_Percentage|$compliancePercentage|Percent|InstanceId=$instanceId" -Level "INFO"
    Write-DSCLog "METRIC|DSC_Total_Resources|$totalResources|Count|InstanceId=$instanceId" -Level "INFO"
    Write-DSCLog "METRIC|DSC_NonCompliant_Resources|$nonCompliantResources|Count|InstanceId=$instanceId" -Level "INFO"

    # Log details of non-compliant resources
    if ($nonCompliantResources -gt 0) {
        Write-DSCLog "=== Non-Compliant Resource Details ===" -Level "WARN"
        $dscStatus.ResourcesNotInDesiredState | ForEach-Object {
            Write-DSCLog "Non-Compliant: $($_.ResourceId) - $($_.InDesiredState)" -Level "WARN"
        }
    } else {
        Write-DSCLog "All resources are compliant!" -Level "INFO"
    }

    Write-DSCLog "=== DSC Compliance Check Complete ===" -Level "INFO"

} catch {
    Write-DSCLog "=== DSC Compliance Check Failed ===" -Level "ERROR"
    Write-DSCLog "Error: $($_.Exception.Message)" -Level "ERROR"
    Write-DSCLog "METRIC|DSC_Check_Errors|1|Count|InstanceId=$instanceId" -Level "ERROR"
}
'@

# Create JSON file for the monitoring command
$monitoringJsonFile = "dsc-monitoring-command.json"
$monitoringCommand = @{
    DocumentName = "AWS-RunPowerShellScript"
    Targets = @(
        @{
            Key = "tag:Environment"
            Values = @("test")
        }
    )
    Parameters = @{
        commands = @($fullMonitoringScript)
    }
} | ConvertTo-Json -Depth 4

$monitoringCommand | Out-File -FilePath $monitoringJsonFile -Encoding UTF8

# Test the full monitoring script
Write-Host "Testing full monitoring script..." -ForegroundColor Yellow
$testCommandId = aws ssm send-command --cli-input-json "file://$monitoringJsonFile" --query 'Command.CommandId' --output text

Write-Host "✓ Test command sent: $testCommandId" -ForegroundColor Green

# Wait for execution
Write-Host "Waiting 30 seconds for execution..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Check results
Write-Host "Getting results..." -ForegroundColor Yellow
$output = aws ssm get-command-invocation --command-id $testCommandId --instance-id "i-004ff505a11d64441" --query 'StandardOutputContent' --output text

Write-Host ""
Write-Host "=== Monitoring Script Output ===" -ForegroundColor Cyan
Write-Host $output -ForegroundColor White

if ($output -like "*DSC Compliance Check Complete*") {
    Write-Host ""
    Write-Host "✓ Full monitoring script works! Setting up maintenance window..." -ForegroundColor Green

    # Create maintenance window
    Write-Host "Creating maintenance window..." -ForegroundColor Yellow
    $windowId = aws ssm create-maintenance-window `
        --name "DSC-Compliance-Monitoring" `
        --description "Hourly DSC compliance monitoring with detailed logging" `
        --duration 1 `
        --cutoff 0 `
        --schedule "rate(1 hour)" `
        --allow-unassociated-targets `
        --query 'WindowId' `
        --output text

    Write-Host "✓ Maintenance window created: $windowId" -ForegroundColor Green

    # Register targets
    Write-Host "Registering targets..." -ForegroundColor Yellow
    $targetId = aws ssm register-target-with-maintenance-window `
        --window-id $windowId `
        --resource-type "INSTANCE" `
        --targets "Key=tag:Environment,Values=test" `
        --query 'WindowTargetId' `
        --output text

    Write-Host "✓ Targets registered: $targetId" -ForegroundColor Green

    # Create task parameters file
    $taskParamsFile = "dsc-task-params.json"
    $taskParams = @{
        RunCommand = @{
            Parameters = @{
                commands = @($fullMonitoringScript)
            }
        }
    } | ConvertTo-Json -Depth 4

    $taskParams | Out-File -FilePath $taskParamsFile -Encoding UTF8

    # Register the task
    Write-Host "Registering monitoring task..." -ForegroundColor Yellow
    $taskId = aws ssm register-task-with-maintenance-window `
        --window-id $windowId `
        --targets "Key=WindowTargetIds,Values=$targetId" `
        --task-type "RUN_COMMAND" `
        --task-arn "AWS-RunPowerShellScript" `
        --max-concurrency "5" `
        --max-errors "1" `
        --task-invocation-parameters "file://$taskParamsFile" `
        --query 'WindowTaskId' `
        --output text

    Write-Host "✓ Task registered: $taskId" -ForegroundColor Green

    # Clean up temp files
    Remove-Item $monitoringJsonFile -ErrorAction SilentlyContinue
    Remove-Item $taskParamsFile -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=== DSC Monitoring Setup Complete! ===" -ForegroundColor Cyan
    Write-Host "✓ Maintenance Window: $windowId" -ForegroundColor Green
    Write-Host "✓ Target ID: $targetId" -ForegroundColor Green
    Write-Host "✓ Task ID: $taskId" -ForegroundColor Green
    Write-Host "✓ Schedule: Every hour automatically" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your CloudWatch dashboard will now show:" -ForegroundColor White
    Write-Host "• Detailed DSC compliance logs in /aws/systemsmanager log groups" -ForegroundColor Gray
    Write-Host "• Structured METRIC entries you can parse for dashboard widgets" -ForegroundColor Gray
    Write-Host "• Resource-level compliance details" -ForegroundColor Gray
    Write-Host "• Hourly compliance trending data" -ForegroundColor Gray

} else {
    Write-Host "✗ Monitoring script had issues. Output:" -ForegroundColor Red
    Write-Host $output -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Monitor Your Setup ===" -ForegroundColor Yellow
Write-Host "Check maintenance window executions:" -ForegroundColor White
Write-Host "aws ssm describe-maintenance-window-executions --window-id $windowId" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs in CloudWatch Console:" -ForegroundColor White
Write-Host "CloudWatch > Logs > /aws/systemsmanager/* log groups" -ForegroundColor Gray