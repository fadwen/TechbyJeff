# Enterprise Integration Guide - Find-UnknownSIDs

## Overview
This guide provides comprehensive troubleshooting and integration guidance for deploying the Find-UnknownSIDs script in enterprise environments with monitoring systems, automation platforms, and security frameworks.

## Integration Scenarios

### 1. SIEM Integration (Security Information and Event Management)

#### Splunk Integration
```powershell
# Example: Splunk Universal Forwarder integration
$LogPath = "C:\Program Files\SplunkUniversalForwarder\var\log\splunk\find-unknownsids.log"
.\Find-UnknownSIDs.ps1 -LogPath $LogPath -LogLevel Information -CorrelationId "SIEM-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

**Common Issues:**
- **Log format compatibility**: Ensure JSON structured logging is enabled
- **Correlation ID tracking**: Use consistent correlation ID format for SIEM queries
- **Log rotation**: Configure appropriate log retention policies

#### ArcSight Integration
```powershell
# Example: ArcSight CEF format logging
$CorrelationId = "ARCSIGHT-SID-AUDIT-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
.\Find-UnknownSIDs.ps1 -CorrelationId $CorrelationId -LogLevel Warning
```

**Configuration Requirements:**
- CEF format compliance for security events
- Proper categorization of security findings
- Integration with ArcSight connectors

### 2. System Center Operations Manager (SCOM)

#### Monitoring Pack Integration
```powershell
# SCOM-friendly execution with performance counters
$Results = .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -ParallelThrottleLimit 15 -MaxMemoryUsageMB 2048
if ($Results.Statistics.OrphanedSIDCount -gt 100) {
    Write-EventLog -LogName "Application" -Source "Find-UnknownSIDs" -EventID 1001 -EntryType Warning -Message "High orphaned SID count detected: $($Results.Statistics.OrphanedSIDCount)"
}
```

**SCOM Rule Configuration:**
- Monitor for specific event IDs
- Set up alerting thresholds
- Create dashboard views for security metrics

### 3. PowerShell Desired State Configuration (DSC)

#### DSC Resource Implementation
```powershell
Configuration ADSecurityMaintenance {
    param(
        [string]$SearchBase,
        [int]$MaxOrphanedSIDs = 50
    )

    Script OrphanedSIDCheck {
        SetScript = {
            $Results = .\Find-UnknownSIDs.ps1 -SearchBase $using:SearchBase
            if ($Results.Statistics.OrphanedSIDCount -gt $using:MaxOrphanedSIDs) {
                throw "Orphaned SID count exceeds threshold: $($Results.Statistics.OrphanedSIDCount)"
            }
        }
        TestScript = {
            $Results = .\Find-UnknownSIDs.ps1 -SearchBase $using:SearchBase
            return ($Results.Statistics.OrphanedSIDCount -le $using:MaxOrphanedSIDs)
        }
        GetScript = {
            $Results = .\Find-UnknownSIDs.ps1 -SearchBase $using:SearchBase
            return @{
                OrphanedSIDCount = $Results.Statistics.OrphanedSIDCount
                LastRun = Get-Date
            }
        }
    }
}
```

### 4. Azure Monitor and Log Analytics

#### Log Analytics Integration
```powershell
# Azure Monitor integration with custom logs
$WorkspaceId = "your-workspace-id"
$SharedKey = "your-shared-key"

# Execute script with JSON output
$Results = .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -OutputPath ".\results.json"

# Send to Log Analytics (using custom function)
Send-LogAnalyticsData -WorkspaceId $WorkspaceId -SharedKey $SharedKey -LogType "ADSecurityAudit" -JsonData $Results
```

### 5. Microsoft Defender for Identity Integration

#### Correlation with Defender for Identity
```powershell
# Generate correlation ID matching Defender for Identity format
$DefenderCorrelationId = "MDI-SID-AUDIT-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
.\Find-UnknownSIDs.ps1 -CorrelationId $DefenderCorrelationId -LogLevel Information
```

**Integration Benefits:**
- Correlate orphaned SIDs with security alerts
- Enhanced threat detection capabilities
- Integrated security dashboard views

## Common Integration Issues

### 1. Authentication and Authorization

#### Issue: Service Account Permissions
**Symptoms:**
- Access denied errors when running in automated scenarios
- Inconsistent results between manual and automated execution

**Resolution:**
```powershell
# Verify service account has required permissions
$ServiceAccount = "DOMAIN\SVC-ADSecurity"
$RequiredPermissions = @(
    "Read All Properties",
    "Read Permissions",
    "Modify Permissions" # Only if using -Remove
)

# Test permissions before execution
Test-ADPermissions -Account $ServiceAccount -Permissions $RequiredPermissions
```

#### Issue: Credential Management
**Symptoms:**
- Credential prompts in automated environments
- Authentication failures in scheduled tasks

**Resolution:**
```powershell
# Use Windows Credential Manager or Azure Key Vault
$Credential = Get-StoredCredential -Target "ADSecurityService"
if (-not $Credential) {
    throw "Service credentials not found in credential store"
}
```

### 2. Performance and Scalability

#### Issue: Memory Exhaustion in Large Environments
**Symptoms:**
- Out of memory errors
- Script termination during processing
- Slow performance with large datasets

**Resolution:**
```powershell
# Tune memory management for large environments
.\Find-UnknownSIDs.ps1 -MaxMemoryUsageMB 4096 -ParallelThrottleLimit 5 -LogLevel Warning
```

#### Issue: Network Timeout Issues
**Symptoms:**
- Intermittent connection failures
- Slow domain controller responses
- Timeout errors during processing

**Resolution:**
```powershell
# Increase retry attempts and configure timeout settings
.\Find-UnknownSIDs.ps1 -MaxRetries 5 -ConfigPath ".\config\high-latency-network.json"
```

### 3. Logging and Monitoring

#### Issue: Log File Size Growth
**Symptoms:**
- Large log files consuming disk space
- Performance degradation due to excessive logging

**Resolution:**
```powershell
# Configure appropriate log levels for production
.\Find-UnknownSIDs.ps1 -LogLevel Warning -LogPath "\\server\logs\ADSecurity\find-unknownsids.log"
```

#### Issue: Correlation ID Tracking
**Symptoms:**
- Difficulty correlating events across systems
- Inconsistent correlation ID formats

**Resolution:**
```powershell
# Use consistent correlation ID format
$CorrelationId = "ENTERPRISE-SID-AUDIT-$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$(Get-Random -Maximum 9999)"
.\Find-UnknownSIDs.ps1 -CorrelationId $CorrelationId
```

## Best Practices for Enterprise Integration

### 1. Automation Framework Integration

#### Jenkins Pipeline Integration
```groovy
pipeline {
    agent any
    parameters {
        string(name: 'SEARCH_BASE', defaultValue: 'DC=contoso,DC=com', description: 'AD Search Base')
        choice(name: 'OPERATION', choices: ['Discovery', 'Removal'], description: 'Operation Type')
    }
    stages {
        stage('AD Security Audit') {
            steps {
                powershell """
                    \$CorrelationId = "JENKINS-${env.BUILD_NUMBER}-${params.OPERATION}"
                    if ('${params.OPERATION}' -eq 'Removal') {
                        .\Find-UnknownSIDs.ps1 -Remove -SearchBase '${params.SEARCH_BASE}' -CorrelationId \$CorrelationId -Force
                    } else {
                        .\Find-UnknownSIDs.ps1 -SearchBase '${params.SEARCH_BASE}' -CorrelationId \$CorrelationId
                    }
                """
            }
        }
    }
}
```

#### Azure DevOps Integration
```yaml
trigger:
  schedules:
  - cron: "0 2 * * 1"  # Weekly on Monday at 2 AM
    displayName: Weekly AD Security Audit
    branches:
      include:
      - main

pool:
  vmImage: 'windows-latest'

steps:
- powershell: |
    $CorrelationId = "AZDO-$(Build.BuildNumber)-SID-AUDIT"
    .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -CorrelationId $CorrelationId -OutputPath "$(Build.ArtifactStagingDirectory)\sid-audit-results.csv"
  displayName: 'Execute AD Security Audit'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: '$(Build.ArtifactStagingDirectory)'
    ArtifactName: 'SID-Audit-Results'
```

### 2. Configuration Management

#### Centralized Configuration
```json
{
  "Enterprise": {
    "DefaultSearchBase": "DC=contoso,DC=com",
    "MaxMemoryUsageMB": 2048,
    "ParallelThrottleLimit": 20,
    "LogLevel": "Information",
    "CorrelationIdPrefix": "ENTERPRISE-SID-AUDIT",
    "BackupRetentionDays": 90,
    "AlertThresholds": {
      "OrphanedSIDCount": 100,
      "ProcessingTimeMinutes": 60,
      "MemoryUsagePercent": 80
    }
  }
}
```

### 3. Monitoring and Alerting

#### PowerShell-Based Monitoring
```powershell
function Send-SecurityAlert {
    param(
        [string]$AlertType,
        [string]$Message,
        [string]$CorrelationId
    )

    $AlertData = @{
        AlertType = $AlertType
        Message = $Message
        CorrelationId = $CorrelationId
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Source = 'Find-UnknownSIDs'
    }

    # Send to monitoring system
    Invoke-RestMethod -Uri "https://monitoring.contoso.com/api/alerts" -Method POST -Body ($AlertData | ConvertTo-Json) -ContentType "application/json"
}

# Usage in script execution
$Results = .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com"
if ($Results.Statistics.OrphanedSIDCount -gt 100) {
    Send-SecurityAlert -AlertType "HighOrphanedSIDCount" -Message "Found $($Results.Statistics.OrphanedSIDCount) orphaned SIDs" -CorrelationId $Results.CorrelationId
}
```

## Troubleshooting Integration Issues

### 1. Diagnostic Information Collection

#### Enterprise Diagnostic Script
```powershell
function Get-IntegrationDiagnostics {
    param(
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $Diagnostics = @{
        CorrelationId = $CorrelationId
        SystemInfo = @{
            PowerShellVersion = $PSVersionTable.PSVersion
            OperatingSystem = (Get-CimInstance Win32_OperatingSystem).Caption
            AvailableMemory = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
        }
        ADConnectivity = @{
            DomainController = (Get-ADDomainController).HostName
            DomainFunctionalLevel = (Get-ADDomain).DomainMode
            ForestFunctionalLevel = (Get-ADForest).ForestMode
        }
        NetworkDiagnostics = @{
            DNSResolution = (Resolve-DnsName (Get-ADDomain).PDCEmulator -ErrorAction SilentlyContinue).IPAddress
            Connectivity = Test-NetConnection (Get-ADDomainController).HostName -Port 389 -InformationLevel Quiet
        }
    }

    return $Diagnostics
}
```

### 2. Common Error Patterns

#### Error: "Access to the registry key 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa' is denied"
**Cause:** Insufficient permissions for security operations
**Resolution:** Run with appropriate service account or elevated privileges

#### Error: "The RPC server is unavailable"
**Cause:** Network connectivity issues or domain controller unavailability
**Resolution:** Check network connectivity and domain controller availability

#### Error: "Not enough storage is available to process this command"
**Cause:** Memory exhaustion during large-scale operations
**Resolution:** Reduce parallel processing or increase memory limits

### 3. Performance Optimization

#### Load Balancing Across Domain Controllers
```powershell
$DomainControllers = Get-ADDomainController -Filter *
$SelectedDC = $DomainControllers | Get-Random
$env:LOGONSERVER = "\\$($SelectedDC.HostName)"
```

#### Batch Processing for Large Environments
```powershell
$AllOUs = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName
$BatchSize = 10

for ($i = 0; $i -lt $AllOUs.Count; $i += $BatchSize) {
    $Batch = $AllOUs[$i..($i + $BatchSize - 1)]
    .\Find-UnknownSIDs.ps1 -SearchBase $Batch -CorrelationId "BATCH-$($i / $BatchSize + 1)"
}
```

## Support and Escalation

### 1. Support Contacts
- **Primary Support:** IT Security Team (security@contoso.com)
- **Secondary Support:** PowerShell Development Team (powershell@contoso.com)
- **Escalation:** CISO Office (ciso@contoso.com)

### 2. Documentation References
- **Enterprise Architecture:** .\Documentation\Enterprise-Architecture.md
- **Security Procedures:** .\Documentation\Security-Procedures.md
- **Change Management:** .\Documentation\Change-Management.md

### 3. Knowledge Base Articles
- **KB001:** Troubleshooting Active Directory Connectivity
- **KB002:** PowerShell Script Performance Optimization
- **KB003:** Enterprise Security Audit Procedures

---

*Last Updated: 2025-07-02*
*Version: 2.0.0*
*Author: Jeffrey Stuhr*
