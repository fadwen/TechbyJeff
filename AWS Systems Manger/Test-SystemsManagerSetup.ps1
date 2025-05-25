<#
.SYNOPSIS
    Tests AWS Systems Manager connectivity and setup on Windows instances.

.DESCRIPTION
    This script performs a comprehensive verification of AWS Systems Manager (SSM)
    prerequisites and connectivity on Windows EC2 instances, helping to diagnose
    common SSM connection issues.

.NOTES
    File Name     : Test-SystemsManagerSetup.ps1
    Author        : Jeffrey Stuhr
    Blog Reference: This is a companion script for the blog post available at:
                   https://www.techbyjeff.net/part-1-5-making-sure-systems-manager-actually-works-and-logs-are-sent-to-cloudwatch/

.LINK
    https://www.techbyjeff.net/part-1-5-making-sure-systems-manager-actually-works-and-logs-are-sent-to-cloudwatch/

.EXAMPLE
    .\Test-SystemsManagerSetup.ps1

    Runs the script with auto-detected instance ID and region.

.EXAMPLE
    .\Test-SystemsManagerSetup.ps1 -InstanceId "i-0123456789abcdef0" -Region "us-east-1"

    Runs the script with specified instance ID and region.
#>

function Test-SystemsManagerSetup {
    param(
        [string]$InstanceId = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = `
            (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} `
            -Method PUT -Uri http://169.254.169.254/latest/api/token)} `
            -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id),
        [string]$Region = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = `
            (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} `
            -Method PUT -Uri http://169.254.169.254/latest/api/token)} `
            -Method GET -Uri http://169.254.169.254/latest/meta-data/placement/region)
    )

    Write-Host "=== Systems Manager Setup Verification ===" -ForegroundColor Cyan
    Write-Host "Instance ID: $InstanceId"
    Write-Host "Region: $Region"
    Write-Host ""

    $results = @{
        InstanceId = $InstanceId
        Region = $Region
        Checks = @{}
    }

    # Check 1: SSM Agent Service
    Write-Host "[1/6] Checking SSM Agent Service..." -NoNewline
    $ssmService = Get-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    if ($ssmService -and $ssmService.Status -eq 'Running') {
        Write-Host " PASS" -ForegroundColor Green
        $results.Checks.SSMAgent = "PASS"
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $results.Checks.SSMAgent = "FAIL: Service not running"
    }

    # Check 2: IAM Role
    Write-Host "[2/6] Checking IAM Role..." -NoNewline
    try {
        $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} `
            -Method PUT -Uri http://169.254.169.254/latest/api/token
        $role = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} `
            -Method GET -Uri http://169.254.169.254/latest/meta-data/iam/security-credentials/

        if ($role) {
            Write-Host " PASS (Role: $role)" -ForegroundColor Green
            $results.Checks.IAMRole = "PASS: $role"
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $results.Checks.IAMRole = "FAIL: No role attached"
        }
    } catch {
        Write-Host " FAIL" -ForegroundColor Red
        $results.Checks.IAMRole = "FAIL: Cannot access metadata"
    }

    # Check 3: Network Connectivity
    Write-Host "[3/6] Checking Network Connectivity..."
    $endpoints = @(
        "ssm.$Region.amazonaws.com",
        "ssmmessages.$Region.amazonaws.com",
        "ec2messages.$Region.amazonaws.com",
        "s3.$Region.amazonaws.com"
    )

    $networkPass = $true
    foreach ($endpoint in $endpoints) {
        Write-Host "      Testing $endpoint..." -NoNewline
        $test = Test-NetConnection -ComputerName $endpoint -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($test) {
            Write-Host " PASS" -ForegroundColor Green
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $networkPass = $false
        }
    }
    $results.Checks.Network = if ($networkPass) { "PASS" } else { "FAIL: Some endpoints unreachable" }

    # Check 4: Time Sync
    Write-Host "[4/6] Checking Time Sync..." -NoNewline
    $w32tm = w32tm /query /status /verbose | Select-String "Last Successful Sync Time:"
    if ($w32tm) {
        Write-Host " PASS" -ForegroundColor Green
        $results.Checks.TimeSync = "PASS"
    } else {
        Write-Host " WARNING" -ForegroundColor Yellow
        $results.Checks.TimeSync = "WARNING: Could not verify"
    }

    # Check 5: AWS CLI/PowerShell
    Write-Host "[5/6] Checking AWS PowerShell Module..." -NoNewline
    if (Get-Module -ListAvailable -Name AWS.Tools.* | Where-Object {$_.Name -eq 'AWS.Tools.S3'}) {
        Write-Host " PASS" -ForegroundColor Green
        $results.Checks.AWSModule = "PASS"
    } else {
        Write-Host " WARNING (Optional)" -ForegroundColor Yellow
        $results.Checks.AWSModule = "WARNING: AWS.Tools not installed"
    }

# Check 6: SSM Registration Status (comprehensive verification)
    Write-Host "[6/6] Checking SSM Registration..." -NoNewline
    try {
        $ssmWorking = $true
        $issues = @()

        # Check 1: Can we reach SSM endpoint?
        $ssmEndpoint = Test-NetConnection -ComputerName "ssm.$Region.amazonaws.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $ssmEndpoint) {
            $ssmWorking = $false
            $issues += "SSM endpoint unreachable"
        }

        # Check 2: Do we have IAM credentials?
        $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} `
            -Method PUT -Uri http://169.254.169.254/latest/api/token
        $roleName = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} `
            -Method GET -Uri http://169.254.169.254/latest/meta-data/iam/security-credentials/

        if (-not $roleName) {
            $ssmWorking = $false
            $issues += "No IAM role attached"
        }

        # Check 3: Is SSM agent running and healthy?
        $ssmService = Get-Service AmazonSSMAgent -ErrorAction SilentlyContinue
        if (-not $ssmService -or $ssmService.Status -ne 'Running') {
            $ssmWorking = $false
            $issues += "SSM Agent not running"
        }

        # Check 4: Any recent errors in logs?
        $ssmLogPath = "C:\ProgramData\Amazon\SSM\Logs\amazon-ssm-agent.log"
        if (Test-Path $ssmLogPath) {
            $recentErrors = Get-Content $ssmLogPath -Tail 20 | Where-Object {
                $_ -match "(error|failed|timeout)" -and
                $_ -match "(registration|ssm|connection)" -and
                $_ -notmatch "retrying|retry"
            }

            if ($recentErrors.Count -gt 2) {  # Allow for some transient errors
                $issues += "Multiple recent errors in agent logs"
            }
        }

        # Overall assessment
        if ($ssmWorking -and $issues.Count -eq 0) {
            Write-Host " PASS (All SSM prerequisites met)" -ForegroundColor Green
            $results.Checks.SSMRegistration = "PASS: All SSM registration prerequisites verified"
        } elseif ($issues.Count -le 1) {
            Write-Host " WARNING (Minor issues detected)" -ForegroundColor Yellow
            $results.Checks.SSMRegistration = "WARNING: Minor issues - $($issues -join ', ')"
        } else {
            Write-Host " FAIL (Multiple issues)" -ForegroundColor Red
            $results.Checks.SSMRegistration = "FAIL: Issues detected - $($issues -join ', ')"
        }

    } catch {
        # Fallback to log-based check if API approach fails
        Write-Host " WARNING (API test failed, checking logs)" -ForegroundColor Yellow
        $ssmLogPath = "C:\ProgramData\Amazon\SSM\Logs\amazon-ssm-agent.log"

        if (Test-Path $ssmLogPath) {
            $recentLogs = Get-Content $ssmLogPath -Tail 50 | Where-Object {
                $_ -match "(successfully registered|ping reply|health ping succeeded)"
            }

            if ($recentLogs.Count -gt 0) {
                Write-Host " -> Fallback: PASS (Logs show registration)" -ForegroundColor Green
                $results.Checks.SSMRegistration = "PASS: Log-based verification successful"
            } else {
                Write-Host " -> Fallback: WARNING (Cannot verify)" -ForegroundColor Yellow
                $results.Checks.SSMRegistration = "WARNING: Cannot verify SSM registration status"
            }
        } else {
            Write-Host " -> Fallback: SKIPPED" -ForegroundColor Yellow
            $results.Checks.SSMRegistration = "SKIPPED: $($_.Exception.Message)"
        }
    }

    # Summary
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    $passCount = ($results.Checks.Values | Where-Object {$_ -like "PASS*"}).Count
    $totalCount = $results.Checks.Count

    if ($passCount -eq $totalCount) {
        Write-Host "All checks passed! Your instance is ready for Systems Manager." -ForegroundColor Green
    } elseif ($passCount -ge 4) {
        Write-Host "Most checks passed. Review warnings above." -ForegroundColor Yellow
    } else {
        Write-Host "Multiple checks failed. Please review and fix issues above." -ForegroundColor Red
    }

    return $results
}


# Run the test
$testResults = Test-SystemsManagerSetup

# Save results
$testResults | ConvertTo-Json -Depth 10 | Out-File "SSM-Setup-Test-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
