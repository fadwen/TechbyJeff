# Find-UnknownSIDs Common Issues Troubleshooting Guide

## Overview
This guide provides solutions for the most commonly encountered issues when using the Find-UnknownSIDs script. Issues are organized by frequency and impact to help you quickly resolve problems.

## Critical Issues (Immediate Resolution Required)

### 1. Script Fails to Start

#### Issue: "Active Directory PowerShell module is not available"
**Symptoms:**
- Script terminates immediately with module import error
- Error occurs during initialization phase

**Root Cause:**
- Active Directory PowerShell module not installed
- Module not properly loaded
- Windows feature not enabled

**Resolution:**
```powershell
# For Windows Server with Desktop Experience or Windows 10/11
Enable-WindowsOptionalFeature -Online -FeatureName RSATClient-Roles-AD-Powershell

# For Windows Server Core
Add-WindowsFeature RSAT-AD-PowerShell

# Verify installation
Get-Module -ListAvailable -Name ActiveDirectory
```

**Prevention:**
- Include module availability check in deployment scripts
- Document prerequisites in deployment guides

#### Issue: "Critical class import failure"
**Symptoms:**
- Script fails during class loading phase
- Security validation errors during startup

**Root Cause:**
- Missing or corrupted class files
- File permissions preventing access
- Path resolution issues

**Resolution:**
```powershell
# Check class files exist
$ClassesPath = Join-Path $PSScriptRoot "Classes"
Get-ChildItem $ClassesPath -Filter "*.ps1" | ForEach-Object {
    Write-Host "Checking: $($_.Name)"
    if (Test-Path $_.FullName) {
        Write-Host "✓ Found" -ForegroundColor Green
    } else {
        Write-Host "✗ Missing" -ForegroundColor Red
    }
}

# Reset file permissions if needed
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
icacls "$ScriptRoot\Classes" /reset /T
```

### 2. Authentication and Authorization Failures

#### Issue: "Access denied" errors during AD operations
**Symptoms:**
- Permission errors when reading AD objects
- Inconsistent results based on user context
- Failures during ACL modification attempts

**Root Cause:**
- Insufficient Active Directory permissions
- Running under wrong user context
- Domain controller access restrictions

**Resolution:**
```powershell
# Check current user context
whoami /groups | findstr "Domain Admins"

# Test AD connectivity and permissions
try {
    $TestOU = Get-ADOrganizationalUnit -Filter "Name -eq 'Users'" -ErrorAction Stop
    Write-Host "✓ AD Read permissions verified" -ForegroundColor Green
} catch {
    Write-Host "✗ AD Read permissions failed: $($_.Exception.Message)" -ForegroundColor Red
}

# For removal operations, test write permissions
if ($TestRemovePermissions) {
    try {
        $TestObject = Get-ADUser -Filter "Name -eq 'testuser'" -Properties nTSecurityDescriptor
        if ($TestObject) {
            $ACL = Get-Acl -Path "AD:$($TestObject.DistinguishedName)"
            Write-Host "✓ ACL read permissions verified" -ForegroundColor Green
        }
    } catch {
        Write-Host "✗ ACL read permissions failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

**Required Permissions:**
- **Discovery Mode:** Read access to target OUs and objects
- **Removal Mode:** Modify Permissions on target objects
- **Restore Mode:** Modify Permissions on target objects

#### Issue: "The RPC server is unavailable"
**Symptoms:**
- Intermittent connection failures
- Timeouts during large operations
- Domain controller connectivity issues

**Resolution:**
```powershell
# Test domain controller connectivity
$DomainController = (Get-ADDomainController).HostName
Test-NetConnection $DomainController -Port 389 -InformationLevel Detailed

# Check DNS resolution
Resolve-DnsName $DomainController -Type A

# Test with specific domain controller
$env:LOGONSERVER = "\\$DomainController"
Get-ADDomain -Server $DomainController
```

## High Priority Issues

### 3. Performance and Memory Issues

#### Issue: "Out of memory" errors during processing
**Symptoms:**
- Script terminates with memory allocation errors
- Extremely slow performance with large datasets
- System becomes unresponsive

**Root Cause:**
- Insufficient memory configuration
- Memory leaks in processing loops
- Large datasets exceeding memory limits

**Resolution:**
```powershell
# Increase memory limits
.\Find-UnknownSIDs.ps1 -MaxMemoryUsageMB 4096 -ParallelThrottleLimit 5

# Monitor memory usage during execution
Get-Process -Name powershell | Select-Object ProcessName, WorkingSet, VirtualMemorySize

# Use batch processing for large environments
$AllOUs = Get-ADOrganizationalUnit -Filter * | Select-Object -First 10
.\Find-UnknownSIDs.ps1 -SearchBase $AllOUs -MaxMemoryUsageMB 2048
```

#### Issue: Script hangs or runs indefinitely
**Symptoms:**
- No progress updates for extended periods
- High CPU usage without completion
- No response to keyboard interrupts

**Root Cause:**
- Infinite loops in processing logic
- Deadlocks in parallel processing
- Unhandled exceptions causing hangs

**Resolution:**
```powershell
# Use verbose logging to identify hang point
.\Find-UnknownSIDs.ps1 -Verbose -LogLevel Debug

# Reduce parallel processing
.\Find-UnknownSIDs.ps1 -ParallelThrottleLimit 1

# Monitor with timeout
$Job = Start-Job -ScriptBlock { .\Find-UnknownSIDs.ps1 -SearchBase "OU=Test,DC=contoso,DC=com" }
Wait-Job $Job -Timeout 300
if ($Job.State -eq "Running") {
    Stop-Job $Job
    Write-Warning "Script timed out after 5 minutes"
}
```

### 4. Configuration and Parameter Issues

#### Issue: "Configuration file not found" or JSON parsing errors
**Symptoms:**
- ConfigPath parameter validation fails
- JSON deserialization errors
- Unexpected default values used

**Root Cause:**
- Incorrect file path specification
- Malformed JSON in configuration file
- File permissions preventing access

**Resolution:**
```powershell
# Verify configuration file exists and is valid
$ConfigPath = ".\config.json"
if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content $ConfigPath | ConvertFrom-Json
        Write-Host "✓ Configuration file valid" -ForegroundColor Green
    } catch {
        Write-Host "✗ Configuration file invalid: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "✗ Configuration file not found: $ConfigPath" -ForegroundColor Red
}

# Create default configuration if missing
$DefaultConfig = @{
    Processing = @{
        DefaultParallelThrottleLimit = 10
        DefaultMaxMemoryUsageMB = 1024
        DefaultMaxRetries = 3
    }
    Logging = @{
        DefaultLogLevel = "Information"
        EnableVerboseLogging = $false
    }
}
$DefaultConfig | ConvertTo-Json -Depth 3 | Out-File ".\config-default.json"
```

## Medium Priority Issues

### 5. Output and Reporting Issues

#### Issue: CSV export fails or produces empty files
**Symptoms:**
- OutputPath parameter validation fails
- CSV files created but contain no data
- Formatting issues in exported data

**Root Cause:**
- Directory permissions issues
- File path resolution problems
- Data formatting or encoding issues

**Resolution:**
```powershell
# Test output directory permissions
$OutputDir = Split-Path ".\reports\output.csv"
try {
    New-Item -Path "$OutputDir\test.txt" -ItemType File -Force
    Remove-Item "$OutputDir\test.txt" -Force
    Write-Host "✓ Output directory writable" -ForegroundColor Green
} catch {
    Write-Host "✗ Output directory not writable: $($_.Exception.Message)" -ForegroundColor Red
}

# Verify data export manually
$Results = .\Find-UnknownSIDs.ps1 -SearchBase "OU=Test,DC=contoso,DC=com"
if ($Results.OrphanedSIDs.Count -gt 0) {
    $Results.OrphanedSIDs | Export-Csv -Path ".\manual-export.csv" -NoTypeInformation
    Write-Host "Manual export completed with $($Results.OrphanedSIDs.Count) records"
}
```

#### Issue: Inconsistent or missing correlation IDs
**Symptoms:**
- Logs show empty or null correlation IDs
- Difficulty tracking operations across systems
- Missing correlation context in error messages

**Resolution:**
```powershell
# Always specify correlation ID explicitly
$CorrelationId = "MANUAL-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Maximum 9999)"
.\Find-UnknownSIDs.ps1 -CorrelationId $CorrelationId

# Verify correlation ID in logs
Get-Content ".\Logs\Find-UnknownSIDs_*.log" | Select-String $CorrelationId
```

### 6. Backup and Restore Issues

#### Issue: Backup creation fails during removal operations
**Symptoms:**
- Removal operations fail with backup errors
- Backup directory creation issues
- Insufficient disk space for backups

**Root Cause:**
- Disk space limitations
- Directory permission problems
- Path length limitations on Windows

**Resolution:**
```powershell
# Check available disk space
$BackupPath = ".\Backup"
$Drive = (Get-Item $BackupPath).PSDrive
$FreeSpace = (Get-PSDrive $Drive.Name).Free / 1GB
Write-Host "Available space: $([math]::Round($FreeSpace, 2)) GB"

# Test backup directory creation
try {
    $TestBackupPath = Join-Path $BackupPath "test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -Path $TestBackupPath -ItemType Directory -Force
    Remove-Item $TestBackupPath -Force
    Write-Host "✓ Backup directory creation successful" -ForegroundColor Green
} catch {
    Write-Host "✗ Backup directory creation failed: $($_.Exception.Message)" -ForegroundColor Red
}
```

## Low Priority Issues

### 7. Logging and Verbose Output Issues

#### Issue: Log files grow too large or fill disk space
**Symptoms:**
- Large log files consuming disk space
- Performance degradation due to excessive logging
- Disk space warnings or errors

**Resolution:**
```powershell
# Use appropriate log level for production
.\Find-UnknownSIDs.ps1 -LogLevel Warning

# Implement log rotation
$LogFiles = Get-ChildItem ".\Logs" -Filter "*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
$LogFiles | Remove-Item -Force
Write-Host "Removed $($LogFiles.Count) old log files"
```

#### Issue: Console output formatting issues or encoding problems
**Symptoms:**
- Garbled characters in console output
- Inconsistent formatting across different hosts
- Missing color formatting

**Resolution:**
```powershell
# Set console encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Test color support
if ($Host.UI.SupportsVirtualTerminal) {
    Write-Host "✓ Color output supported" -ForegroundColor Green
} else {
    Write-Host "! Color output not supported - using plain text" -ForegroundColor Yellow
}
```

## Diagnostic Commands

### Quick Health Check
```powershell
function Test-FindUnknownSIDsHealth {
    Write-Host "=== Find-UnknownSIDs Health Check ===" -ForegroundColor Cyan

    # Check PowerShell version
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green

    # Check Active Directory module
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Write-Host "✓ Active Directory module available" -ForegroundColor Green
    } else {
        Write-Host "✗ Active Directory module missing" -ForegroundColor Red
    }

    # Check script files
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RequiredFiles = @(
        "Find-UnknownSIDs.ps1",
        "Private\Configuration.ps1",
        "Private\Logging.ps1",
        "Classes\ScriptConfiguration.ps1"
    )

    foreach ($File in $RequiredFiles) {
        $FullPath = Join-Path $ScriptPath $File
        if (Test-Path $FullPath) {
            Write-Host "✓ $File" -ForegroundColor Green
        } else {
            Write-Host "✗ $File" -ForegroundColor Red
        }
    }

    # Check AD connectivity
    try {
        $Domain = Get-ADDomain -ErrorAction Stop
        Write-Host "✓ AD connectivity: $($Domain.DNSRoot)" -ForegroundColor Green
    } catch {
        Write-Host "✗ AD connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Check permissions
    try {
        $TestOU = Get-ADOrganizationalUnit -Filter "Name -eq 'Users'" -ErrorAction Stop
        Write-Host "✓ AD read permissions" -ForegroundColor Green
    } catch {
        Write-Host "✗ AD read permissions failed" -ForegroundColor Red
    }
}
```

### Performance Baseline Test
```powershell
function Test-FindUnknownSIDsPerformance {
    param(
        [string]$TestOU = "CN=Users,DC=contoso,DC=com"
    )

    Write-Host "=== Performance Baseline Test ===" -ForegroundColor Cyan

    $StartTime = Get-Date
    $StartMemory = [System.GC]::GetTotalMemory($false) / 1MB

    try {
        $Results = .\Find-UnknownSIDs.ps1 -SearchBase $TestOU -LogLevel Warning

        $EndTime = Get-Date
        $EndMemory = [System.GC]::GetTotalMemory($false) / 1MB
        $Duration = $EndTime - $StartTime
        $MemoryUsed = $EndMemory - $StartMemory

        Write-Host "✓ Test completed successfully" -ForegroundColor Green
        Write-Host "  Duration: $($Duration.TotalSeconds) seconds" -ForegroundColor Yellow
        Write-Host "  Memory used: $([math]::Round($MemoryUsed, 2)) MB" -ForegroundColor Yellow
        Write-Host "  Objects processed: $($Results.Statistics.ObjectsProcessed)" -ForegroundColor Yellow
        Write-Host "  Orphaned SIDs found: $($Results.Statistics.OrphanedSIDCount)" -ForegroundColor Yellow

    } catch {
        Write-Host "✗ Performance test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

## Getting Additional Help

### 1. Enable Debug Logging
```powershell
.\Find-UnknownSIDs.ps1 -LogLevel Debug -Verbose
```

### 2. Collect Diagnostic Information
```powershell
# Create diagnostic package
$DiagnosticPath = ".\Diagnostics\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -Path $DiagnosticPath -ItemType Directory -Force

# System information
Get-ComputerInfo | Out-File "$DiagnosticPath\system-info.txt"
$PSVersionTable | Out-File "$DiagnosticPath\powershell-version.txt"

# Active Directory information
Get-ADDomain | Out-File "$DiagnosticPath\ad-domain.txt"
Get-ADForest | Out-File "$DiagnosticPath\ad-forest.txt"

# Script configuration
if (Test-Path ".\config.json") {
    Copy-Item ".\config.json" "$DiagnosticPath\config.json"
}

# Recent logs
Get-ChildItem ".\Logs" -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
    Copy-Item $_.FullName "$DiagnosticPath\$($_.Name)"
}

Write-Host "Diagnostic package created: $DiagnosticPath" -ForegroundColor Green
```

### 3. Contact Support
When contacting support, please provide:
- **Correlation ID** from the failed operation
- **Diagnostic package** created above
- **Exact error messages** and symptoms
- **Environment information** (domain size, PowerShell version, etc.)

---

*Last Updated: 2025-07-02*
*Version: 2.0.0*
*Author: Jeffrey Stuhr*