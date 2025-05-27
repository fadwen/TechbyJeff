<#
.SYNOPSIS
    Deploys DSC configurations at scale across multiple AWS EC2 instances using intelligent batching.

.DESCRIPTION
    This script provides intelligent batch deployment of DSC configurations across large numbers of EC2 instances.
    It wraps existing AWS Systems Manager documents with advanced features including rate limiting,
    progress monitoring, automatic retry logic, and comprehensive reporting.

.PARAMETER DocumentName
    The name of the AWS Systems Manager document to execute (typically your DSC application document).

.PARAMETER ConfigurationS3Bucket
    The S3 bucket containing the DSC MOF configuration file.

.PARAMETER ConfigurationS3Key
    The S3 key (path) to the DSC MOF configuration file.

.PARAMETER TagKey
    The EC2 tag key used to identify target instances. Default: "Environment"

.PARAMETER TagValue
    The EC2 tag value used to identify target instances. Default: "Production"

.PARAMETER ConfigurationName
    The name identifier for this DSC configuration. Default: "CISLevel1Production"

.PARAMETER RequiredModules
    Comma-separated list of required PowerShell DSC modules.
    Default: "CisDsc,SecurityPolicyDsc,AuditPolicyDsc,NetworkingDsc,ComputerManagementDsc"

.PARAMETER BatchSize
    Number of instances to process in each batch. Automatically adjusted for large configurations. Default: 20

.PARAMETER DelayBetweenBatchesMinutes
    Minutes to wait between batches to prevent AWS API rate limiting. Default: 3

.PARAMETER TimeoutMinutes
    Timeout in minutes for each batch execution. Default: 45

.PARAMETER MaxRetryAttempts
    Maximum number of retry attempts for failed batches. Default: 2

.PARAMETER TestMode
    Run in test mode (validation only, no changes applied). Default: $false

.PARAMETER ComplianceCheck
    Run compliance validation after applying configuration. Default: $true

.PARAMETER EnableVerboseLogging
    Enable verbose logging for troubleshooting. Default: $false

.PARAMETER EnableDebugLogging
    Enable debug logging for detailed troubleshooting. Default: $false

.PARAMETER ProxyUri
    Optional proxy server URI for network access.

.PARAMETER RebootBehavior
    Reboot behavior after configuration application. Valid values: "Never", "IfRequired", "Immediately". Default: "Never"

.NOTES
    File Name     : Deploy-DSCAtScale.ps1
    Author        : Jeffrey Stuhr
    Prerequisites : AWS CLI must be installed and configured with appropriate IAM permissions
    Required IAM Permissions:
    - ec2:DescribeInstances
    - ssm:SendCommand
    - ssm:ListCommandInvocations
    - ssm:DescribeInstanceInformation
    - s3:HeadObject (for configuration validation)

.EXAMPLE
    # Basic deployment to production instances
    $result = Deploy-CISConfigurationAtScale -DocumentName "Apply-CIS-Level1-Baseline" -ConfigurationS3Bucket "my-dsc-configs" -ConfigurationS3Key "CIS/Production/localhost.mof"

.EXAMPLE
    # Custom deployment with specific batching
    $result = Deploy-CISConfigurationAtScale -DocumentName "Apply-CIS-Level1-Baseline" -ConfigurationS3Bucket "my-dsc-configs" -ConfigurationS3Key "CIS/Production/localhost.mof" -TagKey "Project" -TagValue "WebServers" -BatchSize 10 -DelayBetweenBatchesMinutes 5

.EXAMPLE
    # Test mode deployment for validation
    $result = Deploy-CISConfigurationAtScale -DocumentName "Apply-CIS-Level1-Baseline" -ConfigurationS3Bucket "my-dsc-configs" -ConfigurationS3Key "CIS/Test/localhost.mof" -TestMode $true -EnableVerboseLogging $true

.OUTPUTS
    PSCustomObject containing deployment summary with batch results, timing, and success metrics.

.FUNCTIONALITY
    Key Features:
    - Intelligent batch sizing based on configuration complexity
    - AWS API rate limiting with configurable delays
    - Instance validation (SSM connectivity, Windows platform)
    - S3 configuration validation before deployment
    - Real-time progress monitoring with detailed status
    - Comprehensive error handling and retry logic
    - Detailed reporting and export capabilities
    - Automatic batch size adjustment for large configurations
#>

# Scale Deployment Function Using Existing SSM Document
# This wraps DSC documents with intelligent batching for AWS rate limits and large-scale deployments

function Deploy-CISConfigurationAtScale {
    <#
    .SYNOPSIS
        Main function for deploying DSC configurations at scale with intelligent batching.

    .DESCRIPTION
        Coordinates the entire scale deployment process including instance discovery,
        validation, batching strategy, execution monitoring, and results reporting.
    #>
    param(
        [Parameter(Mandatory, HelpMessage="AWS Systems Manager document name for DSC deployment")]
        [string]$DocumentName,

        [Parameter(Mandatory, HelpMessage="S3 bucket containing the DSC configuration MOF file")]
        [string]$ConfigurationS3Bucket,

        [Parameter(Mandatory, HelpMessage="S3 key path to the DSC configuration MOF file")]
        [string]$ConfigurationS3Key,

        [string]$TagKey = "Environment",
        [string]$TagValue = "Production",
        [string]$ConfigurationName = "CISLevel1Production",
        [string]$RequiredModules = "CisDsc,SecurityPolicyDsc,AuditPolicyDsc,NetworkingDsc,ComputerManagementDsc",

        # Batching and Rate Limiting Parameters
        [int]$BatchSize = 20,                    # AWS SSM concurrent limit consideration
        [int]$DelayBetweenBatchesMinutes = 3,    # Rate limiting delay
        [int]$TimeoutMinutes = 45,               # Per-batch timeout
        [int]$MaxRetryAttempts = 2,              # Retry failed batches

        # DSC Parameters
        [bool]$TestMode = $false,
        [bool]$ComplianceCheck = $true,
        [bool]$EnableVerboseLogging = $false,
        [bool]$EnableDebugLogging = $false,
        [string]$ProxyUri = "",
        [ValidateSet("Never", "IfRequired", "Immediately")]
        [string]$RebootBehavior = "Never"
    )

    Write-Host "=== CIS DSC Scale Deployment Starting ===" -ForegroundColor Cyan
    Write-Host "Document: $DocumentName" -ForegroundColor White
    Write-Host "Target: $TagKey=$TagValue" -ForegroundColor White
    Write-Host "Batch Size: $BatchSize instances" -ForegroundColor White
    Write-Host "S3 Configuration: s3://$ConfigurationS3Bucket/$ConfigurationS3Key" -ForegroundColor White

    try {
        # Step 1: Discover and validate target instances
        Write-Host ""
        Write-Host "=== STEP 1: Instance Discovery ===" -ForegroundColor Yellow

        $instancesJson = aws ec2 describe-instances `
            --filters "Name=tag:$TagKey,Values=$TagValue" "Name=instance-state-name,Values=running" `
            --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0],InstanceType,LaunchTime]" `
            --output json

        if (!$instancesJson) {
            throw "No instances found with tag $TagKey=$TagValue"
        }

        $instances = $instancesJson | ConvertFrom-Json
        $instanceIds = $instances | ForEach-Object { $_[0] }

        Write-Host "Found $($instanceIds.Count) target instances:" -ForegroundColor Green
        $instances | ForEach-Object {
            $id = $_[0]; $name = $_[1]; $type = $_[2]; $launch = $_[3]
            Write-Host "  $id - $name ($type) - Launched: $launch" -ForegroundColor Gray
        }

        # Step 2: Validate SSM connectivity and platform compatibility
        Write-Host ""
        Write-Host "=== STEP 2: SSM Validation ===" -ForegroundColor Yellow

        $ssmInstancesJson = aws ssm describe-instance-information `
            --query "InstanceInformationList[?PingStatus=='Online' && PlatformType=='Windows'].[InstanceId,PlatformName,PlatformVersion,LastPingDateTime]" `
            --output json

        $ssmInstances = ($ssmInstancesJson | ConvertFrom-Json)
        $onlineInstanceIds = $ssmInstances | ForEach-Object { $_[0] }

        $validInstances = $instanceIds | Where-Object { $_ -in $onlineInstanceIds }
        $offlineInstances = $instanceIds | Where-Object { $_ -notin $onlineInstanceIds }

        Write-Host "SSM Online & Windows: $($validInstances.Count)" -ForegroundColor Green
        if ($offlineInstances.Count -gt 0) {
            Write-Host "SSM Offline/Unavailable: $($offlineInstances.Count)" -ForegroundColor Red
            $offlineInstances | ForEach-Object {
                Write-Host "  Offline: $_" -ForegroundColor Red
            }
        }

        if ($validInstances.Count -eq 0) {
            throw "No instances are online and SSM-managed for Windows!"
        }

        # Step 3: Validate S3 configuration exists
        Write-Host ""
        Write-Host "=== STEP 3: S3 Configuration Validation ===" -ForegroundColor Yellow

        try {
            $s3ObjectInfo = aws s3api head-object --bucket $ConfigurationS3Bucket --key $ConfigurationS3Key --output json | ConvertFrom-Json
            $configSizeKB = [math]::Round($s3ObjectInfo.ContentLength / 1024, 2)
            Write-Host "✓ Configuration found: $configSizeKB KB, Last Modified: $($s3ObjectInfo.LastModified)" -ForegroundColor Green

            # Adjust batch size based on configuration size
            if ($configSizeKB -gt 4096) {  # 4MB threshold
                $originalBatchSize = $BatchSize
                $BatchSize = [math]::Max([math]::Floor($BatchSize / 2), 5)  # Reduce batch size for large configs
                Write-Host "⚠️  Large configuration detected ($configSizeKB KB) - reducing batch size from $originalBatchSize to $BatchSize" -ForegroundColor Yellow
            }
        } catch {
            throw "S3 configuration validation failed: Cannot access s3://$ConfigurationS3Bucket/$ConfigurationS3Key - $($_.Exception.Message)"
        }

        # Step 4: Create batches with intelligent sizing
        Write-Host ""
        Write-Host "=== STEP 4: Batch Creation ===" -ForegroundColor Yellow

        # Sort instances by launch time (older instances first - more stable)
        $sortedInstances = $validInstances | ForEach-Object {
            $instanceId = $_
            $instanceInfo = $instances | Where-Object { $_[0] -eq $instanceId }
            [PSCustomObject]@{
                InstanceId = $instanceId
                Name = $instanceInfo[1]
                Type = $instanceInfo[2]
                LaunchTime = [DateTime]$instanceInfo[3]
            }
        } | Sort-Object LaunchTime

        $batches = @()
        for ($i = 0; $i -lt $sortedInstances.Count; $i += $BatchSize) {
            $batchEnd = [Math]::Min($i + $BatchSize - 1, $sortedInstances.Count - 1)
            $batchInstances = $sortedInstances[$i..$batchEnd]
            $batches += ,[PSCustomObject]@{
                Number = ($batches.Count + 1)
                Instances = $batchInstances
                InstanceIds = $batchInstances.InstanceId
                Size = $batchInstances.Count
            }
        }

        Write-Host "Created $($batches.Count) batches for deployment" -ForegroundColor Green
        $batches | ForEach-Object {
            Write-Host "  Batch $($_.Number): $($_.Size) instances - $($_.InstanceIds -join ', ')" -ForegroundColor Gray
        }

        # Step 5: Execute batched deployment
        Write-Host ""
        Write-Host "=== STEP 5: Batched Deployment Execution ===" -ForegroundColor Yellow

        $deploymentResults = @()
        $startTime = Get-Date

        for ($batchIndex = 0; $batchIndex -lt $batches.Count; $batchIndex++) {
            $batch = $batches[$batchIndex]
            $batchStartTime = Get-Date

            Write-Host ""
            Write-Host "--- Batch $($batch.Number) of $($batches.Count) ---" -ForegroundColor Cyan
            Write-Host "Instances: $($batch.Size)" -ForegroundColor White
            Write-Host "Target IDs: $($batch.InstanceIds -join ', ')" -ForegroundColor Gray

            # Construct parameters for your SSM document
            $documentParameters = @{
                configurationName = $ConfigurationName
                configurationS3Bucket = $ConfigurationS3Bucket
                configurationS3Key = $ConfigurationS3Key
                requiredModules = $RequiredModules
                testMode = $TestMode.ToString().ToLower()
                complianceCheck = $ComplianceCheck.ToString().ToLower()
                EnableVerboseLogging = $EnableVerboseLogging.ToString().ToLower()
                EnableDebugLogging = $EnableDebugLogging.ToString().ToLower()
                ProxyUri = $ProxyUri
                RebootBehavior = $RebootBehavior
                MaxRetryAttempts = $MaxRetryAttempts.ToString()
            }

            # Convert parameters to JSON format for AWS CLI
            $parametersJson = $documentParameters.GetEnumerator() | ForEach-Object {
                '"' + $_.Key + '":"' + $_.Value + '"'
            }
            $parametersString = '{' + ($parametersJson -join ',') + '}'

            Write-Host "Executing SSM document with parameters..." -ForegroundColor Yellow
            Write-Host "Document: $DocumentName" -ForegroundColor Gray
            Write-Host "Parameters: $parametersString" -ForegroundColor Gray

            # Execute the SSM document for this batch
            $batchAttempts = 0
            $batchSuccess = $false
            $commandId = $null

            while ($batchAttempts -lt $MaxRetryAttempts -and -not $batchSuccess) {
                $batchAttempts++

                try {
                    Write-Host "Batch attempt $batchAttempts of $MaxRetryAttempts" -ForegroundColor Gray

                    # Send command to batch instances
                    $commandId = aws ssm send-command `
                        --document-name $DocumentName `
                        --instance-ids $batch.InstanceIds `
                        --parameters $parametersString `
                        --timeout-seconds $(($TimeoutMinutes * 60)) `
                        --query 'Command.CommandId' `
                        --output text

                    if (!$commandId -or $commandId -eq "None") {
                        throw "Failed to send command - no command ID returned"
                    }

                    Write-Host "✓ Command sent successfully: $commandId" -ForegroundColor Green
                    $batchSuccess = $true

                } catch {
                    Write-Host "✗ Batch attempt $batchAttempts failed: $($_.Exception.Message)" -ForegroundColor Red

                    if ($batchAttempts -lt $MaxRetryAttempts) {
                        $retryDelay = 30 * $batchAttempts
                        Write-Host "Waiting $retryDelay seconds before retry..." -ForegroundColor Yellow
                        Start-Sleep -Seconds $retryDelay
                    }
                }
            }

            if (-not $batchSuccess) {
                Write-Host "✗ Batch $($batch.Number) failed after $MaxRetryAttempts attempts" -ForegroundColor Red
                $deploymentResults += [PSCustomObject]@{
                    BatchNumber = $batch.Number
                    CommandId = $null
                    Status = "Failed"
                    InstanceCount = $batch.Size
                    FailedInstances = $batch.InstanceIds
                    Duration = 0
                    Error = "Failed to send command after $MaxRetryAttempts attempts"
                }
                continue
            }

            # Monitor batch execution with progress tracking
            Write-Host "Monitoring batch execution..." -ForegroundColor Yellow
            $monitoringStartTime = Get-Date
            $batchComplete = $false

            while (-not $batchComplete) {
                $elapsed = ((Get-Date) - $monitoringStartTime).TotalMinutes

                if ($elapsed -gt $TimeoutMinutes) {
                    Write-Host "⏰ Batch $($batch.Number) timed out after $TimeoutMinutes minutes" -ForegroundColor Red
                    break
                }

                # Check command status for all instances in batch
                $invocationsJson = aws ssm list-command-invocations `
                    --command-id $commandId `
                    --query 'CommandInvocations[*].[InstanceId,Status,StatusDetails]' `
                    --output json

                $invocations = $invocationsJson | ConvertFrom-Json
                $inProgress = $invocations | Where-Object { $_[1] -eq "InProgress" }
                $succeeded = $invocations | Where-Object { $_[1] -eq "Success" }
                $failed = $invocations | Where-Object { $_[1] -eq "Failed" }
                $cancelled = $invocations | Where-Object { $_[1] -eq "Cancelled" }
                $timedOut = $invocations | Where-Object { $_[1] -eq "TimedOut" }

                $completed = $succeeded.Count + $failed.Count + $cancelled.Count + $timedOut.Count
                $total = $invocations.Count

                if ($completed -eq $total) {
                    $batchComplete = $true
                    $batchDuration = ((Get-Date) - $batchStartTime).TotalMinutes

                    Write-Host "✓ Batch $($batch.Number) completed in $([math]::Round($batchDuration, 1)) minutes!" -ForegroundColor Green
                    Write-Host "  Succeeded: $($succeeded.Count)" -ForegroundColor Green
                    Write-Host "  Failed: $($failed.Count)" -ForegroundColor Red
                    Write-Host "  Cancelled: $($cancelled.Count)" -ForegroundColor Yellow
                    Write-Host "  Timed Out: $($timedOut.Count)" -ForegroundColor Red

                    # Show failed instances
                    if ($failed.Count -gt 0) {
                        Write-Host "  Failed instances:" -ForegroundColor Red
                        $failed | ForEach-Object {
                            Write-Host "    - $($_[0]): $($_[2])" -ForegroundColor Red
                        }
                    }

                    # Show timed out instances
                    if ($timedOut.Count -gt 0) {
                        Write-Host "  Timed out instances:" -ForegroundColor Red
                        $timedOut | ForEach-Object {
                            Write-Host "    - $($_[0]): $($_[2])" -ForegroundColor Red
                        }
                    }

                } else {
                    $percentComplete = [math]::Round(($completed / $total) * 100, 1)
                    Write-Host "Progress: $completed/$total ($percentComplete%) - $($inProgress.Count) in progress - Elapsed: $([math]::Round($elapsed, 1))min" -ForegroundColor Gray
                    Start-Sleep -Seconds 30  # Check every 30 seconds
                }
            }

            # Store batch results
            $batchResult = [PSCustomObject]@{
                BatchNumber = $batch.Number
                CommandId = $commandId
                Status = if ($succeeded.Count -eq $total) { "Success" } elseif ($succeeded.Count -gt 0) { "PartialSuccess" } else { "Failed" }
                InstanceCount = $batch.Size
                Succeeded = $succeeded.Count
                Failed = $failed.Count
                Cancelled = $cancelled.Count
                TimedOut = $timedOut.Count
                Duration = [math]::Round(((Get-Date) - $batchStartTime).TotalMinutes, 2)
                SucceededInstances = $succeeded | ForEach-Object { $_[0] }
                FailedInstances = ($failed + $timedOut + $cancelled) | ForEach-Object { $_[0] }
            }

            $deploymentResults += $batchResult

            # Rate limiting delay between batches (except for last batch)
            if ($batchIndex -lt $batches.Count - 1) {
                Write-Host ""
                Write-Host "⏸️  Rate limiting: Waiting $DelayBetweenBatchesMinutes minutes before next batch..." -ForegroundColor Yellow
                Write-Host "   This prevents AWS API throttling and reduces system load" -ForegroundColor Gray
                Start-Sleep -Seconds ($DelayBetweenBatchesMinutes * 60)
            }
        }

        # Step 6: Final deployment summary and analysis
        Write-Host ""
        Write-Host "=== DEPLOYMENT SUMMARY ===" -ForegroundColor Cyan

        $totalDuration = ((Get-Date) - $startTime).TotalMinutes
        $totalSucceeded = ($deploymentResults | Measure-Object -Property Succeeded -Sum).Sum
        $totalFailed = ($deploymentResults | Measure-Object -Property Failed -Sum).Sum
        $totalTimedOut = ($deploymentResults | Measure-Object -Property TimedOut -Sum).Sum
        $totalCancelled = ($deploymentResults | Measure-Object -Property Cancelled -Sum).Sum
        $avgBatchDuration = ($deploymentResults | Measure-Object -Property Duration -Average).Average

        Write-Host "Total Duration: $([math]::Round($totalDuration, 1)) minutes" -ForegroundColor White
        Write-Host "Total Instances: $($validInstances.Count)" -ForegroundColor White
        Write-Host "Succeeded: $totalSucceeded" -ForegroundColor Green
        Write-Host "Failed: $totalFailed" -ForegroundColor Red
        Write-Host "Timed Out: $totalTimedOut" -ForegroundColor Red
        Write-Host "Cancelled: $totalCancelled" -ForegroundColor Yellow
        Write-Host "Success Rate: $([math]::Round(($totalSucceeded / $validInstances.Count) * 100, 1))%" -ForegroundColor White
        Write-Host "Average Batch Duration: $([math]::Round($avgBatchDuration, 1)) minutes" -ForegroundColor White

        # Batch-by-batch breakdown
        Write-Host ""
        Write-Host "=== BATCH BREAKDOWN ===" -ForegroundColor Yellow
        $deploymentResults | ForEach-Object {
            $status = switch ($_.Status) {
                "Success" { "✓" }
                "PartialSuccess" { "⚠" }
                "Failed" { "✗" }
                default { "?" }
            }
            Write-Host "$status Batch $($_.BatchNumber): $($_.Succeeded)/$($_.InstanceCount) succeeded in $($_.Duration)min [Command: $($_.CommandId)]" -ForegroundColor Gray
        }

        # Export detailed results
        $exportFile = "cis-dsc-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $deploymentSummary = [PSCustomObject]@{
            DeploymentStartTime = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
            DeploymentEndTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            TotalDurationMinutes = [math]::Round($totalDuration, 2)
            Configuration = @{
                DocumentName = $DocumentName
                S3Bucket = $ConfigurationS3Bucket
                S3Key = $ConfigurationS3Key
                ConfigurationName = $ConfigurationName
            }
            TargetCriteria = @{
                TagKey = $TagKey
                TagValue = $TagValue
            }
            BatchingStrategy = @{
                BatchSize = $BatchSize
                DelayBetweenBatchesMinutes = $DelayBetweenBatchesMinutes
                TimeoutMinutes = $TimeoutMinutes
            }
            Results = @{
                TotalInstances = $validInstances.Count
                Succeeded = $totalSucceeded
                Failed = $totalFailed
                TimedOut = $totalTimedOut
                Cancelled = $totalCancelled
                SuccessRate = [math]::Round(($totalSucceeded / $validInstances.Count) * 100, 2)
            }
            BatchResults = $deploymentResults
        }

        $deploymentSummary | ConvertTo-Json -Depth 5 | Out-File -FilePath $exportFile -Encoding UTF8
        Write-Host ""
        Write-Host "📊 Detailed results exported to: $exportFile" -ForegroundColor Green

        return $deploymentSummary

    } catch {
        Write-Host ""
        Write-Host "❌ Scale deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        return $null
    }
}