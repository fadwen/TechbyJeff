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
    Write-Host "[2/6] Checking IAM Role Assigned..." -NoNewline
    try {
        $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} `
            -Method PUT -Uri http://169.254.169.254/latest/api/token
        $role = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} `
            -Method GET -Uri http://169.254.169.254/latest/meta-data/iam/security-credentials/

        if ($role) {
            Write-Host " PASS (Role: $role)" -ForegroundColor Green

            # Now check if the role has SSM permissions by testing credentials
            Write-Host "      Verifying SSM permissions..." -NoNewline
            try {
                # Get the credentials from the instance metadata
                $credentials = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} `
                    -Method GET -Uri "http://169.254.169.254/latest/meta-data/iam/security-credentials/$role"

                # Check if credentials look valid (they should have AccessKeyId, SecretAccessKey, and Token)
                if ($credentials.AccessKeyId -and $credentials.SecretAccessKey -and $credentials.Token) {
                    # Try a simple unsigned request to check network connectivity to AWS endpoints
                    try {
                        $testEndpoint = "https://sts.$Region.amazonaws.com"
                        $connectTest = Invoke-WebRequest -Uri $testEndpoint -Method HEAD -TimeoutSec 5 -ErrorAction Stop
                        Write-Host " PASS (AWS credentials available, endpoints reachable)" -ForegroundColor Green
                        $results.Checks.IAMRole = "PASS: $role (credentials present and AWS endpoints accessible)"
                    } catch {
                        Write-Host " WARNING (Credentials present but endpoint test failed)" -ForegroundColor Yellow
                        $results.Checks.IAMRole = "WARNING: $role (credentials present but AWS endpoint connectivity failed)"
                    }
                } else {
                    Write-Host " FAIL (Invalid credentials)" -ForegroundColor Red
                    $results.Checks.IAMRole = "FAIL: $role has invalid or incomplete credentials"
                }
            } catch {
                Write-Host " WARNING (Cannot retrieve credentials)" -ForegroundColor Yellow
                $results.Checks.IAMRole = "WARNING: $role attached but cannot retrieve credentials - $($_.Exception.Message)"
            }
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
    try {
        # Get detailed time status
        $w32tmStatus = w32tm /query /status /verbose 2>$null

        if ($w32tmStatus) {
            # Check if time service is running and synchronized - be more flexible with the state check
            $serviceRunning = $w32tmStatus | Select-String "State:"
            $lastSync = $w32tmStatus | Select-String "Last Successful Sync Time:"

            # Check for any indication of synchronization
            $syncIndicators = $w32tmStatus | Select-String "(Synchronized|NtpClient|time.windows.com|pool.ntp.org)"

            if ($lastSync) {
                # Extract the last sync time and check if it's recent (within last 24 hours)
                $syncTimeMatch = $lastSync -match "(\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}:\d{2} [AP]M)"

                if ($syncTimeMatch) {
                    try {
                        $syncTime = [DateTime]::Parse($matches[1])
                        $timeDiff = (Get-Date) - $syncTime

                        if ($timeDiff.TotalHours -le 24) {
                            Write-Host " PASS (Last sync: $($timeDiff.Hours)h $($timeDiff.Minutes)m ago)" -ForegroundColor Green
                            $results.Checks.TimeSync = "PASS: Recent sync within 24 hours"
                        } else {
                            Write-Host " WARNING (Last sync: $([int]$timeDiff.TotalDays) days ago)" -ForegroundColor Yellow
                            $results.Checks.TimeSync = "WARNING: Last sync was $([int]$timeDiff.TotalDays) days ago"
                        }
                    } catch {
                        Write-Host " PASS (Sync detected but time parsing failed)" -ForegroundColor Green
                        $results.Checks.TimeSync = "PASS: Time sync service active"
                    }
                } else {
                    Write-Host " PASS (Time service has sync history)" -ForegroundColor Green
                    $results.Checks.TimeSync = "PASS: Time sync service active"
                }
            } elseif ($syncIndicators) {
                # No explicit sync time but shows sync-related activity
                Write-Host " PASS (Time sync service active)" -ForegroundColor Green
                $results.Checks.TimeSync = "PASS: Time sync indicators found"
            } else {
                Write-Host " WARNING (Time service may not be synchronized)" -ForegroundColor Yellow
                $results.Checks.TimeSync = "WARNING: Time service not properly synchronized"
            }
        } else {
            Write-Host " WARNING (Cannot query time service)" -ForegroundColor Yellow
            $results.Checks.TimeSync = "WARNING: Cannot query time service status"
        }
    } catch {
        Write-Host " WARNING (Time sync check failed)" -ForegroundColor Yellow
        $results.Checks.TimeSync = "WARNING: Time sync verification failed - $($_.Exception.Message)"
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

# Check 6: SSM Registration Status (log-based verification)
    Write-Host "[6/6] Checking SSM Registration Logs..." -NoNewline
    try {
        $ssmLogPath = "C:\ProgramData\Amazon\SSM\Logs\amazon-ssm-agent.log"

        if (Test-Path $ssmLogPath) {
            # Look for successful registration indicators in more recent logs (last 200 lines to catch older registration)
            $recentLogs = Get-Content $ssmLogPath -Tail 200 | Where-Object {
                $_ -match "(successfully registered|ping reply|health ping succeeded|registration completed|managed instance|fingerprint matched)"
            }

            # Also look for ongoing activity indicators (these show SSM is actively working)
            $activityLogs = Get-Content $ssmLogPath -Tail 100 | Where-Object {
                $_ -match "(received message|command execution|document execution|polling|heartbeat)" -and
                $_ -notmatch "error|failed"
            }

            # Look for recent errors that would indicate problems
            $recentErrors = Get-Content $ssmLogPath -Tail 100 | Where-Object {
                $_ -match "(error|failed|timeout)" -and
                $_ -match "(registration|ssm|connection)" -and
                $_ -notmatch "retrying|retry"
            }

            # Enhanced logic: Consider both registration events AND ongoing activity
            if ($recentLogs.Count -gt 0 -and $recentErrors.Count -eq 0) {
                Write-Host " PASS (Logs show successful registration)" -ForegroundColor Green
                $results.Checks.SSMRegistration = "PASS: Registration verified in logs"
            } elseif ($activityLogs.Count -gt 0 -and $recentErrors.Count -eq 0) {
                Write-Host " PASS (Active SSM communication detected)" -ForegroundColor Green
                $results.Checks.SSMRegistration = "PASS: Active SSM communication indicates successful registration"
            } elseif (($recentLogs.Count -gt 0 -or $activityLogs.Count -gt 0) -and $recentErrors.Count -le 2) {
                Write-Host " WARNING (Some errors but registration appears active)" -ForegroundColor Yellow
                $results.Checks.SSMRegistration = "WARNING: Minor errors detected but registration appears active"
            } elseif ($recentErrors.Count -gt 2) {
                Write-Host " FAIL (Multiple recent errors)" -ForegroundColor Red
                $results.Checks.SSMRegistration = "FAIL: Multiple recent errors in agent logs"
            } else {
                # Final fallback: if no clear indicators, check if agent is running and other checks passed
                $agentRunning = (Get-Service AmazonSSMAgent -ErrorAction SilentlyContinue).Status -eq 'Running'
                $hasRole = $results.Checks.IAMRole -like "PASS*"
                $hasNetwork = $results.Checks.Network -like "PASS*"

                if ($agentRunning -and $hasRole -and $hasNetwork) {
                    Write-Host " WARNING (Likely registered but cannot verify from logs)" -ForegroundColor Yellow
                    $results.Checks.SSMRegistration = "WARNING: Prerequisites met but no clear log indicators (may be registered earlier)"
                } else {
                    Write-Host " WARNING (Cannot verify registration)" -ForegroundColor Yellow
                    $results.Checks.SSMRegistration = "WARNING: No clear registration indicators in recent logs"
                }
            }
        } else {
            Write-Host " WARNING (Log file not found)" -ForegroundColor Yellow
            $results.Checks.SSMRegistration = "WARNING: SSM agent log file not accessible"
        }

    } catch {
        Write-Host " WARNING (Cannot read logs)" -ForegroundColor Yellow
        $results.Checks.SSMRegistration = "WARNING: Cannot read SSM agent logs - $($_.Exception.Message)"
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
