<#
.SYNOPSIS
    Generates comprehensive AWS Systems Manager compliance reports for managed instances.

.DESCRIPTION
    This script retrieves and analyzes compliance status across AWS Systems Manager managed Windows instances.
    It provides detailed reporting on all compliance items (patches, associations, custom compliance),
    execution history, and generates exportable reports for trending and analysis.
    The script uses AWS CLI for all API interactions.

.PARAMETER InstanceIds
    Optional array of specific EC2 instance IDs to check. If not provided, all online Windows managed instances will be checked.

.PARAMETER DetailedReport
    Switch parameter to include detailed information about non-compliant items in the console output.

.PARAMETER TimeoutSeconds
    Timeout value for AWS CLI operations. Default is 30 seconds.

.NOTES
    File Name     : Get-SSMCompliance.ps1
    Author        : Jeffrey Stuhr
    Prerequisites : AWS CLI must be installed and configured with appropriate IAM permissions
    Required IAM Permissions:
    - ssm:DescribeInstanceInformation
    - ssm:ListComplianceItems
    - ssm:ListCommandInvocations
    - sts:GetCallerIdentity

    Blog Reference: This script supports Systems Manager compliance monitoring as discussed at:
                   https://www.techbyjeff.net/

.LINK
    https://www.techbyjeff.net/

.EXAMPLE
    .\Get-SSMCompliance.ps1

    Generates a compliance report for all online Windows managed instances with basic output.

.EXAMPLE
    .\Get-SSMCompliance.ps1 -DetailedReport

    Generates a compliance report with detailed non-compliant items displayed in the console.

.EXAMPLE
    .\Get-SSMCompliance.ps1 -InstanceIds @("i-0123456789abcdef0", "i-0987654321fedcba0") -DetailedReport

    Generates a detailed compliance report for specific instances only.
#>

# Get comprehensive compliance status
function Get-SSMComplianceReport {
    <#
    .SYNOPSIS
        Core function that retrieves Systems Manager compliance data from AWS.

    .DESCRIPTION
        This function queries AWS Systems Manager for all compliance information across managed instances,
        including patch compliance, association compliance, and custom compliance items.
        Processes the data and returns a structured report object containing compliance metrics.
    #>
    param(
        [Parameter(Mandatory=$false, HelpMessage="Array of EC2 instance IDs to check for compliance")]
        [string[]]$InstanceIds = @(),

        [Parameter(Mandatory=$false, HelpMessage="Include detailed non-compliant items in console output")]
        [switch]$DetailedReport,

        [Parameter(Mandatory=$false, HelpMessage="Timeout for AWS CLI operations in seconds")]
        [int]$TimeoutSeconds = 30
    )

    # Verify AWS CLI availability and authentication
    Write-Host "Verifying AWS CLI prerequisites..." -ForegroundColor Green

    # Check if AWS CLI is available in the system PATH
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI is not installed or not in PATH. Please install AWS CLI first."
    }

    # Test AWS CLI connectivity and authentication
    Write-Host "Testing AWS CLI connectivity..." -ForegroundColor Green
    try {
        # Attempt to get caller identity to verify authentication
        $testResult = aws sts get-caller-identity --output json 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "AWS CLI authentication failed. Please run 'aws configure' first."
        }
        Write-Host "AWS CLI connectivity confirmed." -ForegroundColor Green
    }
    catch {
        throw "AWS CLI test failed: $_"
    }

    # Retrieve target instances if none specified
    if ($InstanceIds.Count -eq 0) {
        Write-Host "Retrieving managed instances..." -ForegroundColor Green

        # Query for all online Windows instances managed by Systems Manager
        # Uses JMESPath query to filter for online Windows instances only
        $instancesJson = aws ssm describe-instance-information --query "InstanceInformationList[?PingStatus=='Online' && PlatformType=='Windows'].InstanceId" --output json 2>$null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve instance information from AWS"
        }

        # Parse JSON response and convert to PowerShell array
        $InstanceIds = $instancesJson | ConvertFrom-Json
        Write-Host "Found $($InstanceIds.Count) managed instances." -ForegroundColor Green
    }

    # Initialize data collection array
    $complianceData = @()
    $instanceCount = 0

    # Process each instance for compliance data
    foreach ($instanceId in $InstanceIds) {
        $instanceCount++

        # Update progress bar with current status
        Write-Progress -Activity "Checking compliance" -Status "$instanceId ($instanceCount of $($InstanceIds.Count))" -PercentComplete (($instanceCount / $InstanceIds.Count) * 100)
        Write-Host "Processing instance: $instanceId" -ForegroundColor Cyan

        try {
            # Retrieve instance metadata
            Write-Host "  Getting instance details..." -ForegroundColor Gray

            # Query specific instance information using instance ID filter
            $instanceJson = aws ssm describe-instance-information --instance-information-filter-list "key=InstanceIds,valueSet=$instanceId" --output json 2>$null

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to get instance information for $instanceId"
                continue
            }

            # Parse and validate instance response
            $instanceResult = $instanceJson | ConvertFrom-Json
            if (-not $instanceResult.InstanceInformationList -or $instanceResult.InstanceInformationList.Count -eq 0) {
                Write-Warning "No instance information found for $instanceId"
                continue
            }
            $instance = $instanceResult.InstanceInformationList[0]

            # Retrieve compliance items for this instance
            Write-Host "  Getting compliance items..." -ForegroundColor Gray

            # Query all compliance items for the managed instance
            # This includes patch compliance, association compliance, and any custom compliance items
            $complianceJson = aws ssm list-compliance-items --resource-id $instanceId --resource-type "ManagedInstance" --output json 2>$null
            $compliance = @()

            if ($LASTEXITCODE -eq 0) {
                $complianceResult = $complianceJson | ConvertFrom-Json
                if ($complianceResult.ComplianceItems) {
                    $compliance = $complianceResult.ComplianceItems
                }
            }

            # Retrieve command execution history to find recent document executions
            Write-Host "  Getting command history..." -ForegroundColor Gray

            # Query recent command invocations to find DSC or other document executions
            $commandsJson = aws ssm list-command-invocations --instance-id $instanceId --max-items 5 --output json 2>$null
            $lastExecution = $null

            if ($LASTEXITCODE -eq 0) {
                $commandsResult = $commandsJson | ConvertFrom-Json
                if ($commandsResult.CommandInvocations) {
                    # Get the most recent command execution (prioritize DSC if available)
                    $dscExecution = $commandsResult.CommandInvocations | Where-Object {$_.DocumentName -like "*DSC*"} | Select-Object -First 1
                    $lastExecution = if ($dscExecution) { $dscExecution } else { $commandsResult.CommandInvocations | Select-Object -First 1 }
                }
            }

            # Build compliance data object for this instance
            $complianceData += [PSCustomObject]@{
                InstanceId = $instanceId
                Name = if ($instance.ComputerName) { $instance.ComputerName } else { "Unknown" }
                LastExecution = if ($lastExecution) { $lastExecution.RequestedDateTime } else { $null }
                Status = if ($lastExecution) { $lastExecution.Status } else { "Unknown" }
                CompliantItems = ($compliance | Where-Object {$_.Status -eq "COMPLIANT"}).Count
                NonCompliantItems = ($compliance | Where-Object {$_.Status -eq "NON_COMPLIANT"}).Count
                CompliancePercentage = if ($compliance.Count -gt 0) {
                    # Calculate compliance percentage rounded to 2 decimal places
                    [math]::Round((($compliance | Where-Object {$_.Status -eq "COMPLIANT"}).Count / $compliance.Count) * 100, 2)
                } else { 0 }
            }

            # Display detailed non-compliant items if requested
            if ($DetailedReport -and ($compliance | Where-Object {$_.Status -eq "NON_COMPLIANT"})) {
                Write-Host "`nNon-compliant items for $($instance.ComputerName):" -ForegroundColor Yellow
                $compliance | Where-Object {$_.Status -eq "NON_COMPLIANT"} |
                    Select-Object Title, Severity |
                    Format-Table -AutoSize
            }
        }
        catch {
            # Log any errors encountered during instance processing
            Write-Warning "Error processing instance $instanceId : $_"
            continue
        }
    }

    # Clear progress bar
    Write-Progress -Activity "Checking compliance" -Completed
    return $complianceData
}

# Main execution block
Write-Host "Starting Systems Manager Compliance Report..." -ForegroundColor Green

# Generate the compliance report
$report = Get-SSMComplianceReport -DetailedReport

# Display results in formatted table
$report | Format-Table -AutoSize

# Export results to CSV file with timestamp
$csvPath = ".\SSM-Compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Report exported to: $csvPath" -ForegroundColor Green