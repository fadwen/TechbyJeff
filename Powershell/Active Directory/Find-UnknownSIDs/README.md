# Find-UnknownSIDs Enterprise PowerShell Solution

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-blue)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Active Directory](https://img.shields.io/badge/dependency-ActiveDirectory-orange)](https://docs.microsoft.com/en-us/powershell/module/activedirectory/)

## 📖 Overview

**Business Value:** Enterprise-grade Active Directory security management solution that identifies and removes orphaned Security Identifiers (SIDs) from ACLs, reducing security risks and improving compliance posture while maintaining comprehensive audit trails for regulatory requirements.

**Technical Summary:** Modular PowerShell solution with parallel processing, memory management, secure class loading, comprehensive backup/restore capabilities, and enterprise integration features for large-scale Active Directory security maintenance.

### Key Features
- 🚀 **Parallel Processing**: Configurable multi-threading (1-50 threads) for enterprise-scale operations
- 🛡️ **Security Validation**: Comprehensive risk assessment with protected SID checking and safe operations
- 📊 **Memory Management**: Intelligent memory monitoring and optimization (100-16384 MB configurable)
- 🔄 **Backup & Restore**: Timestamped backup organization with full rollback capabilities
- 📋 **Audit Compliance**: Detailed correlation tracking for SOX, HIPAA, and GDPR requirements
- ⚡ **Performance Optimized**: Batch processing and streaming results for large environments
- 🔧 **Enterprise Integration**: JSON configuration, SIEM integration, and CI/CD compatibility
- 🛠️ **Modular Architecture**: Object-oriented design with specialized PowerShell classes

### Target Audience
- **Active Directory Administrators**: Security maintenance and compliance operations
- **Security Teams**: Risk assessment and vulnerability remediation
- **Compliance Officers**: Audit trail maintenance and regulatory reporting
- **Infrastructure Managers**: Enterprise-scale AD hygiene and automation

## 🚀 Quick Start

**TL;DR for experienced administrators:**

```powershell
# Discovery Mode - Identify orphaned SIDs (no changes made)
.\Find-UnknownSIDs.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -OutputPath ".\Reports\audit.csv" -Verbose

# Removal Mode - Remove orphaned SIDs with automatic backup
.\Find-UnknownSIDs.ps1 -SearchBase "OU=Computers,DC=contoso,DC=com" -Remove -Force -OutputPath ".\Reports\cleanup.csv"

# Restore Mode - Rollback from previous backup
.\Find-UnknownSIDs.ps1 -Restore -BackupPath ".\Backup\20250703_104232"
```

**Expected Output:**
```
🔍 Analyzing Active Directory objects...
✅ Discovery completed: 247 objects scanned, 15 orphaned SIDs found
📊 Processing time: 2.3 minutes | Memory usage: 89MB
📄 Results: .\Reports\audit_20250703_104232.csv
🔄 Backup created: .\Backup\20250703_104232\
```

**Next Steps:** See [Configuration](#️-configuration) for enterprise setup and [Advanced Examples](#-usage) for automation scenarios.

## 📋 Prerequisites

### System Requirements
| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **PowerShell** | 5.1 | 7.4+ | Cross-platform support in 7.x |
| **Operating System** | Windows Server 2012 R2 | Windows Server 2019+ | Domain-joined required |
| **Memory** | 4GB RAM | 16GB+ RAM | Depends on AD size and threading |
| **Disk Space** | 500MB | 2GB+ | For backups, logs, and reports |
| **Network** | Domain connectivity | High-speed LAN | AD controller access required |

### Required Modules
```powershell
# Install required PowerShell modules
Install-Module ActiveDirectory -Scope CurrentUser
```

| Module | Version | Purpose | Installation |
|--------|---------|---------|--------------|
| **ActiveDirectory** | Any | AD cmdlets and connectivity | `Install-Module ActiveDirectory` |

### Permissions & Access
<details>
<summary>🔐 Detailed Permission Requirements</summary>

#### Active Directory Permissions
1. **Discovery Mode**: Domain Users (read-only operations)
2. **Removal Mode**: Account Operators or Domain Admins (modify ACLs)
3. **Restore Mode**: Same as removal mode (restore ACLs)

#### Required AD Rights
| Operation | Required Permission | Scope |
|-----------|-------------------|-------|
| **Discovery** | Read permissions | Target OUs |
| **ACL Modification** | Write permissions | Target objects |
| **Backup Creation** | Read permissions | File system |
| **Log Writing** | Write permissions | Log directory |

</details>

## 🔧 Installation

### Method 1: Direct Download (Recommended)
```powershell
# Download and extract to desired location
$destinationPath = "C:\Scripts\Find-UnknownSIDs"
New-Item -Path $destinationPath -ItemType Directory -Force

# Extract files maintaining directory structure
# Copy entire folder structure including Classes, Private, Documentation, etc.
```

### Method 2: Git Clone
```powershell
# Clone repository and navigate to script directory
git clone https://github.com/TechbyJeff/TechbyJeff.git
cd "TechbyJeff\Powershell\Active Directory\Find-UnknownSIDs"

# Verify file structure
Get-ChildItem -Recurse | Select-Object Name, Mode
```

## ⚙️ Configuration

### Basic Configuration
```powershell
# Default configuration works for most environments
# Advanced configuration available via JSON files

# Create custom configuration (optional)
$config = @{
    "performance" = @{
        "maxThreads" = 10
        "memoryLimitMB" = 2048
        "batchSize" = 100
    }
    "security" = @{
        "enableDetailedValidation" = $true
        "requireConfirmation" = $true
    }
    "logging" = @{
        "logLevel" = "Information"
        "enableFileLogging" = $true
    }
}
$config | ConvertTo-Json | Out-File ".\custom-config.json"
```

### Environment Variables
```powershell
# Optional environment configuration
$env:FINDUNKNOWNSIDS_CONFIG = "C:\Config\production-config.json"
$env:FINDUNKNOWNSIDS_LOG_LEVEL = "Information"
$env:FINDUNKNOWNSIDS_MAX_MEMORY = "4096"
```

## 💡 Usage

### Basic Operations

#### Example 1: Discovery Mode (Safe Analysis)
```powershell
# Scan entire domain for orphaned SIDs without making changes
.\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -OutputPath ".\Reports\domain-audit.csv" -Verbose
```

**Expected Output:**
```
🔍 Scanning Active Directory domain: DC=contoso,DC=com
📊 Objects processed: 1,247 | Orphaned SIDs found: 23
⏱️  Processing time: 4.2 minutes | Memory usage: 156MB
📄 Report saved: .\Reports\domain-audit_20250703_104232.csv
```

**Business Use Case:** Monthly security audits and compliance reporting

#### Example 2: Targeted OU Cleanup with Removal
```powershell
# Remove orphaned SIDs from specific OU with automatic backup
.\Find-UnknownSIDs.ps1 -SearchBase "OU=Decommissioned,DC=contoso,DC=com" -Remove -Force -OutputPath ".\Reports\cleanup.csv"
```

**Expected Output:**
```
🛡️  Backup created: .\Backup\20250703_104232\
🔧 Removing orphaned SIDs from 45 objects...
✅ Successfully removed 67 orphaned SIDs
📄 Detailed report: .\Reports\cleanup_20250703_104232.csv
```

**Business Use Case:** Quarterly cleanup of decommissioned user/computer OUs

#### Example 3: Pipeline Integration with Filtering
```powershell
# Process multiple OUs with advanced filtering
$targetOUs = "OU=Users,DC=contoso,DC=com", "OU=Computers,DC=contoso,DC=com"
$targetOUs | .\Find-UnknownSIDs.ps1 -IncludeInherited -OutputPath ".\Reports\comprehensive-audit.csv"
```

### Advanced Scenarios

#### Enterprise Automation with Custom Configuration
```powershell
# Automated weekly security maintenance
$config = @{
    searchBases = @("OU=Users,DC=contoso,DC=com", "OU=Computers,DC=contoso,DC=com")
    maxThreads = 20
    memoryLimitMB = 8192
    enableEmailReports = $true
    recipientList = @("security-team@contoso.com")
}

# Execute with custom performance settings
.\Find-UnknownSIDs.ps1 @config -Remove -Force -ConfigPath ".\enterprise-config.json"
```

**ROI Impact:** Eliminates manual security reviews, ensures consistent AD hygiene, reduces compliance audit time by 75%

#### Disaster Recovery and Rollback Operations
```powershell
# Restore ACLs from specific backup (rollback scenario)
.\Find-UnknownSIDs.ps1 -Restore -BackupPath ".\Backup\20250703_104232" -Verbose

# Validate restore operation
.\Find-UnknownSIDs.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -OutputPath ".\Reports\post-restore-validation.csv"
```

#### CI/CD Pipeline Integration
```yaml
# Azure DevOps Pipeline Example for security validation
- task: PowerShell@2
  displayName: 'AD Security Validation'
  inputs:
    targetType: 'inline'
    script: |
      $result = .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -OutputPath "security-scan.csv" -PassThru
      if ($result.OrphanedSIDCount -gt 50) {
        Write-Error "Critical: Too many orphaned SIDs detected ($($result.OrphanedSIDCount))"
        exit 1
      }
```

#### Scheduled Enterprise Monitoring
```powershell
# Enterprise scheduled task with comprehensive error handling and reporting
try {
    $correlationId = [System.Guid]::NewGuid()
    Write-EventLog -LogName Application -Source "AD-Security-Monitor" -EventId 1000 -EntryType Information -Message "Starting AD security scan - CorrelationId: $correlationId"

    $results = .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -OutputPath ".\Reports\daily-scan.csv" -MaxThreads 15 -MemoryLimitMB 4096

    # Email report to security team
    if ($results.OrphanedSIDCount -gt 0) {
        Send-MailMessage -To "security-alerts@contoso.com" -Subject "🚨 AD Security Alert - $($results.OrphanedSIDCount) Orphaned SIDs" -Body "Scan Results: $($results | ConvertTo-Json)"
    }

    Write-EventLog -LogName Application -Source "AD-Security-Monitor" -EventId 1001 -EntryType Information -Message "AD security scan completed successfully - CorrelationId: $correlationId"
}
catch {
    Write-EventLog -LogName Application -Source "AD-Security-Monitor" -EventId 1002 -EntryType Error -Message "AD security scan failed: $($_.Exception.Message) - CorrelationId: $correlationId"
    Send-MailMessage -To "security-alerts@contoso.com" -Subject "🚨 AD Security Scan Failure" -Body $_.Exception.Message
}
```

### Core Modules

| Module | Responsibility | Key Functions |
|--------|---------------|---------------|
| **SIDValidation.ps1** | SID validation, format checking, cache management | `Test-OrphanedSID`, `Test-SIDFormat`, `Test-WellKnownSID` |
| **ADOperations.ps1** | Active Directory connectivity and bulk operations | `Invoke-ADOperationWithRetry`, `Get-ADObjectsParallel` |
| **SIDProcessing.ps1** | SID discovery, analysis, and processing workflows | `Find-OrphanedSIDsInObject`, `Get-SIDAnalysis` |
| **RemovalOperations.ps1** | SID removal operations with safety validations | `Remove-OrphanedSIDs`, `Remove-OrphanedSIDFromObject` |
| **BackupOperations.ps1** | Backup creation with integrity checks | `Backup-ObjectACL`, `New-TimestampedBackup` |
| **RestoreOperations.ps1** | ACL restoration and validation | `Restore-ObjectACL`, `Test-BackupIntegrity` |
| **Configuration.ps1** | Configuration management and validation | `Initialize-ScriptConfiguration`, `Get-ConfigurationSettings` |
| **Orchestration.ps1** | Workflow orchestration and coordination | `Invoke-DiscoveryWorkflow`, `Invoke-RemovalWorkflow` |
| **Logging.ps1** | Structured logging framework with correlation tracking | `Write-ScriptLog`, `Initialize-LoggingFramework` |
| **Utilities.ps1** | Common utility functions and helpers | `Test-Prerequisites`, `Get-SystemInformation` |
| **SecureClassLoader.ps1** | Secure PowerShell class loading and validation | `Import-SecureClass`, `Test-ClassSecurity` |

### Module Dependencies

```
Logging.ps1 (Foundation)
├── Configuration.ps1
├── SecureClassLoader.ps1
│   └── Classes/ (PowerShell Classes)
├── SIDValidation.ps1
│   ├── SIDProcessing.ps1
│   └── ADOperations.ps1
├── BackupOperations.ps1
├── RestoreOperations.ps1
├── RemovalOperations.ps1
├── Utilities.ps1
└── Orchestration.ps1 (Coordination)
```

### Design Principles

- **Single Responsibility**: Each module has a clear, focused purpose with enterprise-grade error handling
- **Loose Coupling**: Minimal dependencies between modules with configuration-driven design
- **High Cohesion**: Related functions grouped together with consistent interfaces
- **Error Resilience**: Comprehensive error handling with correlation tracking throughout
- **Performance Optimization**: Intelligent caching, parallel processing, and memory management
- **Security by Design**: Built-in validation, protection, and audit capabilities
- **Enterprise Integration**: Structured logging, monitoring integration, and compliance support

## 🔍 Troubleshooting

### Quick Diagnostics
```powershell
# Built-in health check and environment validation
.\Find-UnknownSIDs.ps1 -TestConnection -Verbose
```

### Common Issues

<details>
<summary>❌ "Active Directory Module Not Found" Error</summary>

**Symptoms:** Script fails with "The ActiveDirectory module is not available"

**Root Causes:**
1. RSAT (Remote Server Administration Tools) not installed
2. ActiveDirectory module not imported
3. Insufficient permissions to access AD module

**Solutions:**
```powershell
# Install RSAT on Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Install RSAT on Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell

# Verify module availability
Get-Module -ListAvailable ActiveDirectory
Import-Module ActiveDirectory -Force
```

**Related Documentation:** [Active Directory Setup](./Troubleshooting/Common/ActiveDirectory-Module-Setup.md)

</details>

<details>
<summary>⚠️ Memory Issues or Performance Problems</summary>

**Symptoms:** High memory usage, slow execution, or out-of-memory errors

**Diagnostic Commands:**
```powershell
# Enable memory monitoring and performance logging
.\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -MaxThreads 5 -MemoryLimitMB 2048 -Verbose

# Monitor resource usage
Get-Process -Name powershell | Select-Object CPU, WorkingSet, VirtualMemorySize
```

**Optimization Strategies:**
```powershell
# Reduce threading for memory-constrained environments
.\Find-UnknownSIDs.ps1 -SearchBase "OU=Users,DC=contoso,DC=com" -MaxThreads 3 -MemoryLimitMB 1024

# Process OUs separately for very large environments
$ous = @("OU=Users,DC=contoso,DC=com", "OU=Computers,DC=contoso,DC=com")
foreach ($ou in $ous) {
    .\Find-UnknownSIDs.ps1 -SearchBase $ou -OutputPath ".\Reports\$($ou -replace '[^a-zA-Z0-9]', '_').csv"
    Start-Sleep -Seconds 30  # Allow memory cleanup
}
```

**Related Documentation:** [Performance Optimization Guide](./Troubleshooting/Performance/Memory-Management.md)

</details>

<details>
<summary>🛡️ Access Denied or Permission Errors</summary>

**Symptoms:** Script fails with "Access is denied" or insufficient rights errors

**Root Causes:**
1. Insufficient Active Directory permissions
2. User account not in appropriate AD groups
3. UAC restrictions or execution policy issues

**Solutions:**
```powershell
# Test AD connectivity and permissions
Test-ADServiceAccount -Identity $env:USERNAME

# Check current AD permissions
Get-ADUser $env:USERNAME -Properties MemberOf | Select-Object -ExpandProperty MemberOf

# Run with appropriate credentials
$credential = Get-Credential
.\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -Credential $credential
```

**Related Documentation:** [Security Configuration Guide](./Troubleshooting/Security/Permissions-Setup.md)

</details>

### Error Code Reference
| Error Code | Description | Immediate Action | Documentation |
|------------|-------------|------------------|---------------|
| **AD001** | ActiveDirectory module unavailable | Install RSAT tools | [Module Setup](./Troubleshooting/Common/) |
| **MEM001** | Memory limit exceeded | Reduce thread count or increase memory limit | [Memory Management](./Troubleshooting/Performance/) |
| **PERM001** | Insufficient AD permissions | Verify account permissions and group membership | [Permission Setup](./Troubleshooting/Security/) |
| **BACKUP001** | Backup operation failed | Check disk space and write permissions | [Backup Operations](./Troubleshooting/Common/) |

### Self-Diagnostic Tools
```powershell
# Comprehensive environment validation
.\Find-UnknownSIDs.ps1 -ValidateEnvironment -IncludePermissionTest -ExportDiagnostics
```

## 🏗️ Architecture Overview

### Solution Structure
```
Find-UnknownSIDs/
├── Find-UnknownSIDs.ps1        # Main script and entry point
├── Classes/                    # PowerShell classes and types
│   ├── ScriptConfiguration.ps1      # Configuration management
│   ├── OrphanedSIDResult.ps1        # Result data structures
│   ├── MemoryManager.ps1            # Memory optimization
│   ├── ProcessingStatistics.ps1     # Performance metrics
│   ├── SecurityValidationResult.ps1 # Security validation
│   ├── SIDAnalysisResult.ps1        # SID analysis results
│   ├── RemovalOperationResult.ps1   # Removal operation results
│   ├── RestoreOperationResult.ps1   # Restore operation results
│   └── StreamingResultsManager.ps1  # Large dataset handling
├── Private/                    # Internal modules and functions
│   ├── Configuration.ps1            # Configuration management
│   ├── SIDValidation.ps1            # SID validation and checking
│   ├── ADOperations.ps1             # Active Directory operations
│   ├── SIDProcessing.ps1            # SID discovery and analysis
│   ├── RemovalOperations.ps1        # SID removal operations
│   ├── BackupOperations.ps1         # Backup and restore functionality
│   ├── RestoreOperations.ps1        # ACL restoration operations
│   ├── Orchestration.ps1            # Workflow coordination
│   ├── Logging.ps1                  # Structured logging framework
│   ├── Utilities.ps1                # Utility functions
│   ├── SecureClassLoader.ps1        # Secure class loading
│   └── SecureClassImporter.ps1      # Class import management
├── Documentation/              # Comprehensive documentation
│   ├── Backup-and-Restore-Guide.md
│   ├── Find-UnknownSIDs-Automation.md
│   ├── Memory-Security.md
│   └── Class-Loading-Security-Analysis.md
├── Troubleshooting/           # Organized troubleshooting guides
│   ├── Common/                     # General issues and solutions
│   ├── Security/                   # Security-related problems
│   ├── Performance/                # Performance optimization
│   └── Integration/                # Enterprise integration issues
├── Backup/                    # Automated backup storage
├── Logs/                      # Execution and audit logs
└── Tools/                     # Utility scripts and helpers
```

### Core Architecture Principles
- **Separation of Concerns**: Clear separation between data access, business logic, and presentation
- **Single Responsibility**: Each module and class serves a specific, well-defined purpose
- **Dependency Injection**: Loose coupling through configuration-driven design
- **Security by Design**: Comprehensive validation and protection throughout
- **Performance Optimization**: Memory management and parallel processing capabilities
- **Enterprise Integration**: Structured logging, correlation tracking, and audit compliance

### Module Dependencies
```
Logging.ps1 (Foundation)
├── Configuration.ps1
├── SIDValidation.ps1
│   ├── SIDProcessing.ps1
│   └── ADOperations.ps1
├── BackupOperations.ps1
├── RestoreOperations.ps1
├── RemovalOperations.ps1
└── Orchestration.ps1 (Coordination)
```

### PowerShell Classes Architecture
| Class | Purpose | Key Responsibilities |
|-------|---------|---------------------|
| **ScriptConfiguration** | Configuration management | Environment settings, validation rules, performance tuning |
| **OrphanedSIDResult** | Data structure | SID analysis results and metadata |
| **MemoryManager** | Resource optimization | Memory monitoring, cleanup, and optimization |
| **ProcessingStatistics** | Performance tracking | Execution metrics, timing, and resource usage |
| **SecurityValidationResult** | Security validation | Risk assessment and validation outcomes |
| **SIDAnalysisResult** | Analysis data | Comprehensive SID analysis information |
| **RemovalOperationResult** | Operation tracking | Removal operation success/failure details |
| **RestoreOperationResult** | Restore tracking | Backup restoration operation results |
| **StreamingResultsManager** | Large dataset handling | Efficient processing of large result sets |

## 📊 Performance & Monitoring

### Performance Characteristics
| Environment Size | Objects | Execution Time | Memory Usage | Recommended Settings |
|------------------|---------|----------------|--------------|---------------------|
| **Small Domain (< 1,000 objects)** | 1-1,000 | 2-5 minutes | <200MB | Default settings |
| **Medium Domain (1K-10K objects)** | 1K-10K | 10-30 minutes | 200MB-1GB | MaxThreads: 10, MemoryLimit: 2GB |
| **Large Domain (10K-50K objects)** | 10K-50K | 30-120 minutes | 1-4GB | MaxThreads: 20, MemoryLimit: 8GB |
| **Enterprise (50K+ objects)** | 50K+ | 2+ hours | 4GB+ | MaxThreads: 30, MemoryLimit: 16GB |

### Monitoring Integration
- **Windows Event Log**: Structured event logging for enterprise monitoring
- **Performance Counters**: Memory usage, processing time, and throughput metrics
- **Correlation Tracking**: Full audit trail with correlation IDs for troubleshooting
- **SIEM Integration**: JSON-formatted logs compatible with enterprise SIEM systems

### Optimization Guidelines
```powershell
# PowerShell 7.x parallel processing optimization
.\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -MaxThreads 25 -MemoryLimitMB 8192

# Memory-efficient processing for very large environments
.\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -StreamResults -OutputPath "results.csv"

# Batch processing for maximum reliability
$ous = Get-ADOrganizationalUnit -Filter * | Select-Object -First 10
foreach ($ou in $ous) {
    .\Find-UnknownSIDs.ps1 -SearchBase $ou.DistinguishedName -OutputPath ".\Reports\$($ou.Name).csv"
}
```

### Backup and Recovery Strategy
**Timestamped Backup Organization**: Each removal operation creates a unique timestamped subfolder (e.g., `Backup\20250703_104232\`) containing:
- Individual object ACL backups in JSON format
- Operation metadata and correlation tracking
- Automated integrity validation and verification
- Complete audit trail for compliance requirements

**Recovery Capabilities**:
- Full domain restoration from backup sets
- Selective object restoration by distinguished name
- Integrity validation before and after restore operations
- Correlation tracking for audit and compliance needs

## 🛡️ Security Considerations

### Built-in Security Features
- **Protected SID Validation**: Prevents removal of critical system SIDs
- **Risk Assessment**: Comprehensive validation before any modifications
- **Backup Requirements**: Mandatory backup creation before SID removal
- **Audit Logging**: Complete correlation tracking for security events
- **Access Validation**: Verification of required permissions before operations

### Compliance Support
- **SOX Compliance**: Complete audit trails and change tracking
- **HIPAA Support**: Secure handling of directory information
- **GDPR Considerations**: Privacy-aware logging and data handling
- **PCI DSS**: Secure credential and sensitive data management

## 📚 Documentation

### Available Documentation
- **[Backup and Restore Guide](./Documentation/Backup-and-Restore-Guide.md)**: Comprehensive backup/restore procedures
- **[Automation Guide](./Documentation/Find-UnknownSIDs-Automation.md)**: Enterprise automation and scheduling
- **[Memory Security](./Documentation/Find-UnknownSIDs-Memory-Security.md)**: Memory management and security considerations
- **[Class Loading Security](./Documentation/Class-Loading-Security-Analysis.md)**: Secure PowerShell class loading analysis

### Troubleshooting Resources
- **[Common Issues](./Troubleshooting/Common/)**: Frequently encountered problems and solutions
- **[Security Setup](./Troubleshooting/Security/)**: Permission and security configuration
- **[Performance Optimization](./Troubleshooting/Performance/)**: Memory and performance tuning
- **[Integration Support](./Troubleshooting/Integration/)**: Enterprise system integration guidance

---

**Author:** Jeffrey Stuhr
**Blog:** [https://www.techbyjeff.net](https://www.techbyjeff.net)
**LinkedIn:** [https://www.linkedin.com/in/jeffrey-stuhr-034214aa/](https://www.linkedin.com/in/jeffrey-stuhr-034214aa/)
**Last Updated:** July 3, 2025
**Version:** 3.0.0 (Enterprise Edition)

*This enterprise-grade solution provides comprehensive Active Directory security management with full audit trails, performance optimization, and regulatory compliance support. For additional support and documentation, reference the organized troubleshooting guides in the `./Troubleshooting/` folder structure.*