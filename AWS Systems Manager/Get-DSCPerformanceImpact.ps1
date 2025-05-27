<#
.SYNOPSIS
    Aggregates DSC performance results from multiple AWS Systems Manager managed instances.

.DESCRIPTION
    This script collects and analyzes DSC performance data across multiple EC2 instances,
    providing aggregate statistics, scaling recommendations, and detailed performance breakdowns.

.PARAMETER CommandId
    The AWS Systems Manager command ID to retrieve results from.

.PARAMETER TagKey
    The EC2 tag key to filter instances (default: "Environment").

.PARAMETER TagValue
    The EC2 tag value to filter instances (default: "test").

.NOTES
    File Name     : Get-DSCPerformanceImpact.ps1
    Author        : Jeffrey Stuhr
    Prerequisites : AWS CLI must be installed and configured
    Required IAM Permissions:
    - ec2:DescribeInstances
    - ssm:GetCommandInvocation

.EXAMPLE
    # Collect results from all instances with Environment=test tag
    $results = Get-AggregatedDSCPerformance -CommandId "e0dbc320-9812-44ad-821a-1f93d2100113"

.EXAMPLE
    # Analyze the aggregated data
    Analyze-AggregatedResults -Results $results

.EXAMPLE
    # Run both collection and analysis in one line
    Analyze-AggregatedResults -Results (Get-AggregatedDSCPerformance -CommandId "e0dbc320-9812-44ad-821a-1f93d2100113")

.EXAMPLE
    # Use custom tag filtering
    $results = Get-AggregatedDSCPerformance -CommandId "your-command-id" -TagKey "Project" -TagValue "production"
    Analyze-AggregatedResults -Results $results

.FUNCTIONALITY
    This script will:
    - Find all instances with specified EC2 tags
    - Collect performance data from each instance
    - Calculate aggregate statistics (avg, min, max)
    - Provide scaling recommendations
    - Export results to JSON file
    - Show instance-by-instance breakdown
#>

# Aggregate DSC Performance Results at Scale
Write-Host "Aggregating DSC performance results from multiple instances..." -ForegroundColor Cyan

# Function to parse text-based performance output
function Parse-TextPerformanceData {
    param(
        [string]$Output,
        [string]$InstanceId
    )

    # Extract key metrics from text output
    $duration = if ($Output -match "Operation Duration: ([\d.]+) seconds") { [decimal]$matches[1] } else { $null }
    $cpuBaseline = if ($Output -match "Baseline CPU: ([\d.]+)%") { [decimal]$matches[1] } else { $null }
    $cpuPeak = if ($Output -match "CPU Impact: [\d.]+% -> ([\d.]+)%") { [decimal]$matches[1] } else { $null }
    $cpuChange = if ($Output -match "Change: \+([\d.]+)%") { [decimal]$matches[1] } else { $null }
    $memoryUsed = if ($Output -match "Memory Impact: Used ([\d.]+) MB") { [decimal]$matches[1] } else { $null }
    $totalResources = if ($Output -match "DSC Resources: (\d+) total") { [int]$matches[1] } else { $null }
    $complianceRate = if ($Output -match "Compliance: ([\d.]+)%") { [decimal]$matches[1] } else { $null }
    $resourcesPerSec = if ($Output -match "\(([\d.]+) resources/second\)") { [decimal]$matches[1] } else { $null }
    $baselineMemory = if ($Output -match "Baseline Free Memory: ([\d.]+) MB") { [decimal]$matches[1] } else { $null }

    return [PSCustomObject]@{
        InstanceId = $InstanceId
        OperationType = "Compliance Check"
        Duration = $duration
        BaselineCPU = $cpuBaseline
        PeakCPU = $cpuPeak
        CPUImpact = $cpuChange
        BaselineMemoryMB = $baselineMemory
        MemoryUsedMB = $memoryUsed
        TotalResources = $totalResources
        ComplianceRate = $complianceRate
        ResourcesPerSecond = $resourcesPerSec
        Status = "Success"
        Timestamp = Get-Date
    }
}

# Function to collect results from all instances
function Get-AggregatedDSCPerformance {
    param(
        [string]$CommandId,
        [string]$TagKey = "Environment",
        [string]$TagValue = "test"
    )

    Write-Host "Getting all instances with tag $TagKey=$TagValue..." -ForegroundColor Yellow

    # Get all instance IDs with the specified tag
    $instanceIds = aws ec2 describe-instances `
        --filters "Name=tag:$TagKey,Values=$TagValue" "Name=instance-state-name,Values=running" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text

    if (!$instanceIds) {
        Write-Host "No instances found with tag $TagKey=$TagValue" -ForegroundColor Red
        return
    }

    $instanceList = $instanceIds -split "`s+"
    Write-Host "Found $($instanceList.Count) instances: $($instanceList -join ', ')" -ForegroundColor Green

    # Collect results from each instance
    $allResults = @()

    foreach ($instanceId in $instanceList) {
        Write-Host "Getting results from instance: $instanceId" -ForegroundColor Yellow

        try {
            # Get command invocation status
            $invocation = aws ssm get-command-invocation `
                --command-id $CommandId `
                --instance-id $instanceId `
                --output json | ConvertFrom-Json

            if ($invocation.Status -eq "Success") {
                Write-Host "✓ $instanceId - Command completed successfully" -ForegroundColor Green

                # Extract performance data from text output (fallback parsing)
                $output = $invocation.StandardOutputContent

                # Try to parse JSON performance data first
                if ($output -match '\{.*"InstanceId".*\}') {
                    try {
                        $perfData = ($matches[0] | ConvertFrom-Json)
                        $allResults += $perfData
                        Write-Host "  Parsed JSON performance data successfully" -ForegroundColor Gray
                    } catch {
                        Write-Host "  JSON parse failed, using text parsing" -ForegroundColor Yellow
                        $perfData = Parse-TextPerformanceData -Output $output -InstanceId $instanceId
                        $allResults += $perfData
                    }
                } else {
                    Write-Host "  No JSON found, parsing text output" -ForegroundColor Gray
                    $perfData = Parse-TextPerformanceData -Output $output -InstanceId $instanceId
                    $allResults += $perfData
                }

            } elseif ($invocation.Status -eq "InProgress") {
                Write-Host "⏳ $instanceId - Command still running" -ForegroundColor Yellow
                $allResults += [PSCustomObject]@{
                    InstanceId = $instanceId
                    Status = "InProgress"
                }

            } else {
                Write-Host "✗ $instanceId - Command failed: $($invocation.Status)" -ForegroundColor Red
                $allResults += [PSCustomObject]@{
                    InstanceId = $instanceId
                    Status = $invocation.Status
                    ErrorOutput = $invocation.StandardErrorContent
                }
            }

        } catch {
            Write-Host "✗ $instanceId - Error getting results: $($_.Exception.Message)" -ForegroundColor Red
            $allResults += [PSCustomObject]@{
                InstanceId = $instanceId
                Status = "QueryError"
                Error = $_.Exception.Message
            }
        }
    }

    return $allResults
}

# Function to analyze aggregated results
function Analyze-AggregatedResults {
    param($Results)

    Write-Host ""
    Write-Host "=== AGGREGATED PERFORMANCE ANALYSIS ===" -ForegroundColor Cyan

    # Separate successful vs failed results
    $successfulResults = $Results | Where-Object { $_.Duration -ne $null }
    $failedResults = $Results | Where-Object { $_.Status -ne "Success" -and $_.Duration -eq $null }

    Write-Host "Total Instances: $($Results.Count)" -ForegroundColor White
    Write-Host "Successful: $($successfulResults.Count)" -ForegroundColor Green
    Write-Host "Failed/Incomplete: $($failedResults.Count)" -ForegroundColor Red

    if ($successfulResults.Count -gt 0) {
        Write-Host ""
        Write-Host "=== PERFORMANCE STATISTICS ===" -ForegroundColor Yellow

        # Calculate aggregate statistics
        $durations = $successfulResults.Duration
        $cpuImpacts = $successfulResults.CPUImpact
        $memoryUsage = $successfulResults.MemoryUsedMB
        $resourceCounts = $successfulResults.TotalResources

        Write-Host "Execution Time:" -ForegroundColor White
        Write-Host "  Average: $([math]::Round(($durations | Measure-Object -Average).Average, 2)) seconds" -ForegroundColor Gray
        Write-Host "  Min: $([math]::Round(($durations | Measure-Object -Minimum).Minimum, 2)) seconds" -ForegroundColor Gray
        Write-Host "  Max: $([math]::Round(($durations | Measure-Object -Maximum).Maximum, 2)) seconds" -ForegroundColor Gray

        Write-Host "CPU Impact:" -ForegroundColor White
        Write-Host "  Average: $([math]::Round(($cpuImpacts | Measure-Object -Average).Average, 2))%" -ForegroundColor Gray
        Write-Host "  Max: $([math]::Round(($cpuImpacts | Measure-Object -Maximum).Maximum, 2))%" -ForegroundColor Gray

        Write-Host "Memory Usage:" -ForegroundColor White
        Write-Host "  Average: $([math]::Round(($memoryUsage | Measure-Object -Average).Average, 2)) MB" -ForegroundColor Gray
        Write-Host "  Max: $([math]::Round(($memoryUsage | Measure-Object -Maximum).Maximum, 2)) MB" -ForegroundColor Gray

        if ($resourceCounts -and ($resourceCounts | Where-Object { $_ -gt 0 }).Count -gt 0) {
            Write-Host "DSC Resources:" -ForegroundColor White
            Write-Host "  Average: $([math]::Round(($resourceCounts | Measure-Object -Average).Average, 0)) resources" -ForegroundColor Gray
            Write-Host "  Total across all instances: $(($resourceCounts | Measure-Object -Sum).Sum) resources" -ForegroundColor Gray
        }

        # Scaling recommendations
        Write-Host ""
        Write-Host "=== SCALING RECOMMENDATIONS ===" -ForegroundColor Yellow

        $maxDuration = ($durations | Measure-Object -Maximum).Maximum
        $avgDuration = ($durations | Measure-Object -Average).Average

        if ($maxDuration -gt 60) {
            Write-Host "⚠️  CRITICAL: Max execution time $maxDuration seconds - stagger deployment windows" -ForegroundColor Red
        } elseif ($avgDuration -gt 30) {
            Write-Host "⚠️  WARNING: Average $avgDuration seconds - consider optimization" -ForegroundColor Yellow
        } else {
            Write-Host "✅ GOOD: Execution times acceptable for scale" -ForegroundColor Green
        }

        $maxCPU = ($cpuImpacts | Measure-Object -Maximum).Maximum
        if ($maxCPU -gt 50) {
            Write-Host "⚠️  HIGH CPU: Peak $maxCPU% impact - limit concurrent executions" -ForegroundColor Red
        } else {
            Write-Host "✅ CPU impact manageable for concurrent execution" -ForegroundColor Green
        }

        # Instance-by-instance breakdown
        Write-Host ""
        Write-Host "=== INSTANCE BREAKDOWN ===" -ForegroundColor Yellow
        $successfulResults | Sort-Object Duration -Descending | ForEach-Object {
            $complianceInfo = if ($_.ComplianceRate) { " ($($_.ComplianceRate)% compliant)" } else { "" }
            Write-Host "$($_.InstanceId): $($_.Duration)s, CPU +$($_.CPUImpact)%, Memory $($_.MemoryUsedMB)MB$complianceInfo" -ForegroundColor Gray
        }
    }

    # Show failures
    if ($failedResults.Count -gt 0) {
        Write-Host ""
        Write-Host "=== FAILED INSTANCES ===" -ForegroundColor Red
        $failedResults | ForEach-Object {
            Write-Host "$($_.InstanceId): $($_.Status)" -ForegroundColor Red
            if ($_.Error) { Write-Host "  Error: $($_.Error)" -ForegroundColor Gray }
        }
    }

    # Export results
    Write-Host ""
    Write-Host "=== EXPORTING RESULTS ===" -ForegroundColor Yellow
    $exportFile = "dsc-performance-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $Results | ConvertTo-Json -Depth 5 | Out-File -FilePath $exportFile -Encoding UTF8
    Write-Host "Results exported to: $exportFile" -ForegroundColor Green
}

# Actually run it automatically for demonstration
Write-Host ""
Write-Host "=== RUNNING AGGREGATION NOW ===" -ForegroundColor Cyan

$results = Get-AggregatedDSCPerformance -CommandId "e0dbc320-9812-44ad-821a-1f93d2100113"
Analyze-AggregatedResults -Results $results

Write-Host ""
Write-Host "=== AGGREGATION COMPLETE ===" -ForegroundColor Green