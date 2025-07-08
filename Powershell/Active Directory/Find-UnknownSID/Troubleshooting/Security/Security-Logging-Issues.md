# Security Logging Troubleshooting Guide

## Overview

This guide provides troubleshooting steps for the enterprise security logging system that ensures compliance-grade audit trails regardless of log level configuration.

## Common Issues

### Issue 1: Security Log Entries Missing from File

**Symptoms:**
- Security events appear in console but not in log file
- `[SECURITY]` prefixed messages in console but empty log file

**Diagnosis:**
```powershell
# Check if security structured logging is loaded
Get-Command Write-SecurityStructuredLogEntry -ErrorAction SilentlyContinue

# Check logging system state
$state = Get-LoggingSystemState
Write-Host "Log Path: $($state.LogPath)"
Write-Host "Initialized: $($state.LogFileInitialized)"
```

**Solutions:**
1. **Verify Module Loading**:
   ```powershell
   # Reload logging system
   . .\Private\Import-LoggingSystem.ps1
   ```

2. **Check Log Directory Permissions**:
   ```powershell
   # Verify write access to log directory
   $logDir = Split-Path $state.LogPath -Parent
   Test-Path $logDir -IsValid
   ```

3. **Check Emergency Logging**:
   ```powershell
   # Check if emergency logs were created
   Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log"
   ```

### Issue 2: Security Logs Being Filtered by Log Level

**Symptoms:**
- Security Information entries missing when log level is Warning/Error
- Only Error/Critical security entries in log file

**Diagnosis:**
```powershell
# Check if using correct security logging functions
$content = Get-Content $logPath
$securityEntries = $content | Where-Object { $_ -match '\[SecurityAudit\]' }
$informationSecurityEntries = $securityEntries | Where-Object { $_ -match '\[Information\]' }

Write-Host "Total security entries: $($securityEntries.Count)"
Write-Host "Information-level security entries: $($informationSecurityEntries.Count)"
```

**Root Cause:** Using regular `Write-StructuredLogEntry` instead of security-specific logging

**Solution:**
```powershell
# Incorrect - subject to log level filtering
Write-StructuredLogEntry -Message "Security event" -Level Information -Component 'SecurityAudit'

# Correct - bypasses log level filtering
Write-SecurityStructuredLogEntry -Message "Security event" -Level Information -Component 'SecurityAudit'

# Or use high-level security functions
Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Security event' -Outcome 'Success'
Write-ADOperationSecurityLog -OperationName 'Get-User' -Outcome 'Success'
```

### Issue 3: Security Logging Performance Impact

**Symptoms:**
- Slow performance during security-heavy operations
- High disk I/O during AD operations

**Diagnosis:**
```powershell
# Check security logging metrics
$metrics = $script:SecurityLoggingMetrics
Write-Host "Total security entries: $($metrics.TotalSecurityEntries)"
Write-Host "Last entry time: $($metrics.LastSecurityLogTime)"
```

**Solutions:**
1. **Reduce Security Log Verbosity**:
   ```powershell
   # Use appropriate log levels for security events
   # Critical: Security breaches, data corruption
   # Error: Failed access attempts, authentication failures
   # Warning: Suspicious activity, policy violations
   # Information: Normal security events, successful access
   ```

2. **Batch Security Operations**:
   ```powershell
   # Instead of logging each object individually
   foreach ($object in $objects) {
       Write-ADOperationSecurityLog -OperationName "Process-$($object.Name)" -Outcome 'Success'
   }

   # Batch log summary operations
   Write-ADOperationSecurityLog -OperationName "Bulk-Process-Objects" -Outcome 'Success' -SecurityContext @{
       ObjectCount = $objects.Count
       ProcessingDuration = $duration
   }
   ```

### Issue 4: Emergency Security Logs in Temp Directory

**Symptoms:**
- Warning messages about emergency security logging
- Security logs in `$env:TEMP\Find-UnknownSID-Security-*.log`

**Root Cause:** Main log file unavailable or permissions issue

**Diagnosis:**
```powershell
# Check main log file status
$state = Get-LoggingSystemState
Write-Host "Main log path: $($state.LogPath)"
Write-Host "File exists: $(Test-Path $state.LogPath)"
Write-Host "Directory writable: $(Test-Path (Split-Path $state.LogPath -Parent) -PathType Container)"
```

**Solutions:**
1. **Fix Main Log Directory**:
   ```powershell
   # Recreate log directory with proper permissions
   $logDir = Split-Path $state.LogPath -Parent
   if (-not (Test-Path $logDir)) {
       New-Item -Path $logDir -ItemType Directory -Force
   }
   ```

2. **Consolidate Emergency Logs**:
   ```powershell
   # Merge emergency logs into main log file
   $emergencyLogs = Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log"
   foreach ($log in $emergencyLogs) {
       $content = Get-Content $log.FullName
       Add-Content -Path $state.LogPath -Value $content
       Remove-Item $log.FullName
   }
   ```

### Issue 5: Security Log Format Issues

**Symptoms:**
- Malformed security log entries
- Missing correlation IDs or security context

**Diagnosis:**
```powershell
# Analyze security log format
$securityEntries = Get-Content $logPath | Where-Object { $_ -match '\[SecurityAudit\]' }
$malformedEntries = $securityEntries | Where-Object { $_ -notmatch '\[[\w-]+\]' }
Write-Host "Malformed entries: $($malformedEntries.Count)"
```

**Solutions:**
1. **Verify Correlation ID Usage**:
   ```powershell
   # Always provide correlation ID for security events
   $correlationId = [System.Guid]::NewGuid().ToString()
   Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Test' -Outcome 'Success' -CorrelationId $correlationId
   ```

2. **Include Security Context**:
   ```powershell
   # Provide comprehensive security context
   $securityContext = @{
       OperationType = 'BulkRetrieval'
       ObjectCount = $objects.Count
       SearchBase = $searchBase
       IncludeInherited = $includeInherited
   }
   Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'AD bulk operation' -Outcome 'Success' -SecurityContext $securityContext
   ```

## Validation Procedures

### Test Security Logging Bypass

```powershell
# Test script to validate security logging compliance
cd c:\temp\Find-UnknownSID

# Set restrictive log level
Set-LogLevel -Level Error

# Test security logging (should appear in file)
Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'Compliance test entry' -Outcome 'Success'

# Test regular logging (should NOT appear in file)
Write-StructuredLogEntry -Message 'Regular test entry' -Level Information -Component 'Test'

# Verify results
$logPath = (Get-LoggingSystemState).LogPath
$content = Get-Content $logPath
$securityEntries = $content | Where-Object { $_ -match '\[SecurityAudit\]' }
$regularEntries = $content | Where-Object { $_ -notmatch '\[SecurityAudit\]' }

Write-Host "Security entries (should be > 0): $($securityEntries.Count)" -ForegroundColor Green
Write-Host "Regular Information entries (should be 0): $($regularEntries | Where-Object { $_ -match '\[Information\]' }).Count" -ForegroundColor Yellow
```

### Test Main Script Security Logging

```powershell
# Run main script with restrictive logging
.\Find-UnknownSID.ps1 -SearchBase "DC=domain,DC=com" -LogLevel Error -WhatIf

# Check that security audit entries appear in log file
$logFile = Get-ChildItem ".\Logs\Find-UnknownSID_*.log" | Sort-Object LastWriteTime | Select-Object -Last 1
$securityEntries = Get-Content $logFile.FullName | Where-Object { $_ -match '\[SecurityAudit\]' }

if ($securityEntries.Count -gt 0) {
    Write-Host "✅ Security logging compliance verified" -ForegroundColor Green
} else {
    Write-Host "❌ Security logging compliance failed" -ForegroundColor Red
}
```

## Monitoring and Alerting

### Security Log Monitoring

```powershell
# Monitor for security logging failures
function Test-SecurityLoggingHealth {
    param([string]$LogPath)

    $lastHour = (Get-Date).AddHours(-1)
    $recentEntries = Get-Content $LogPath | Where-Object {
        $_ -match '\[SecurityAudit\]' -and
        [DateTime]::Parse(($_ -split '\]')[0].TrimStart('[')) -gt $lastHour
    }

    if ($recentEntries.Count -eq 0) {
        Write-Warning "No security log entries in the last hour - potential compliance issue"
        return $false
    }

    return $true
}
```

### Emergency Log Alerting

```powershell
# Alert on emergency security logging
function Test-EmergencySecurityLogs {
    $emergencyLogs = Get-ChildItem "$env:TEMP\Find-UnknownSID-Security-*.log" -ErrorAction SilentlyContinue

    if ($emergencyLogs.Count -gt 0) {
        Write-Warning "Emergency security logs detected - main logging system may have issues"
        foreach ($log in $emergencyLogs) {
            Write-Host "Emergency log: $($log.FullName) (Size: $($log.Length) bytes)" -ForegroundColor Yellow
        }
        return $false
    }

    return $true
}
```

## Support Contacts

- **Technical Issues**: IT Security Team
- **Compliance Questions**: Audit & Compliance Team
- **Emergency Logging**: Infrastructure Team
- **Development Support**: PowerShell Team

## Related Documentation

- [Security Logging Compliance Implementation](./Security-Logging-Compliance.md)
- [PowerShell Best Practices](./PowerShell-Best-Practices.md)
- [Logging System Architecture](./Logging-System-Architecture.md)
- [Compliance Framework Mapping](./Compliance-Framework-Mapping.md)
