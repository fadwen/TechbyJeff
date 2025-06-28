# Convert-RC4toAES.ps1

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Active Directory](https://img.shields.io/badge/AD-Required-orange.svg)](https://docs.microsoft.com/en-us/powershell/module/activedirectory/)

## 📖 Overview

**Convert-RC4toAES.ps1** is an enterprise-grade PowerShell script designed to enhance Active Directory Kerberos security by upgrading objects from RC4-only encryption to support both RC4 and AES encryption types. This script provides a safe, auditable method for strengthening authentication security while maintaining backward compatibility during migration periods.

### 🎯 Business Value

- **Improves Security Posture**: Eliminates weak RC4-only Kerberos encryption configurations
- **Maintains Compatibility**: Preserves RC4 support during migration for legacy system compatibility
- **Enables Compliance**: Supports security compliance requirements for stronger authentication encryption
- **Provides Audit Trail**: Comprehensive logging for security reviews and compliance documentation

### 🔐 Security Enhancement

The script upgrades Kerberos encryption from:
- **Before**: RC4-only encryption (weak, deprecated)
- **After**: RC4 + AES128 + AES256 (strong, future-ready)

## 🚀 Quick Start

### Basic Usage
```powershell
# Preview changes without making modifications
.\Convert-RC4toAES.ps1 -WhatIf

# Execute changes with default exclusions
.\Convert-RC4toAES.ps1

# Automated execution for CI/CD pipelines
.\Convert-RC4toAES.ps1 -Force
```

### Advanced Examples
```powershell
# Custom exclusions for legacy systems
.\Convert-RC4toAES.ps1 -ExcludedDisplayNames @("LegacyApp", "CriticalService")

# Automation with custom exclusions and preview
.\Convert-RC4toAES.ps1 -Force -WhatIf -ExcludedDisplayNames @("SpecialAccount")
```

## 📋 Prerequisites

### Required Components
- **PowerShell**: Version 5.1 or later
- **Active Directory Module**: RSAT tools or Windows Server with AD role
- **Permissions**: Domain Administrator or equivalent AD modification rights
- **Network**: Connectivity to domain controllers

### System Requirements
- **Memory**: <100MB for typical enterprise environments
- **Network**: Minimal impact (single LDAP query + individual object updates)
- **Execution Policy**: Must allow script execution

### Installation
```powershell
# Verify Active Directory module availability
Get-Module -Name ActiveDirectory -ListAvailable

# Import the module (done automatically by script)
Import-Module ActiveDirectory
```

## 🔧 Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `WhatIf` | Switch | No | False | Preview mode - shows changes without executing |
| `ExcludedDisplayNames` | String[] | No | See below | Objects to exclude from processing |
| `Force` | Switch | No | False | Bypasses user prompts for automation |

### Default Exclusions
```powershell
@("ServiceAccount01", "LegacyApp-Service", "SpecialKerberosAccount")
```

## 💡 Usage Examples

### 1. Safe Preview (Recommended First Step)
```powershell
.\Convert-RC4toAES.ps1 -WhatIf
```
**Purpose**: Preview all changes before execution
**Duration**: 2-5 minutes for analysis
**Use Case**: Change management review and approval process

### 2. Production Execution with Protection
```powershell
.\Convert-RC4toAES.ps1 -ExcludedDisplayNames @("CriticalApp", "LegacyService")
```
**Purpose**: Execute with protection for specific legacy systems
**Duration**: 5-15 minutes depending on object count
**Use Case**: Production deployment with custom exclusions

### 3. Automated Deployment
```powershell
.\Convert-RC4toAES.ps1 -Force
```
**Purpose**: Unattended execution for automation scenarios
**Duration**: 5-15 minutes depending on object count
**Use Case**: Scheduled maintenance or CI/CD pipeline integration

### 4. Comprehensive Assessment
```powershell
.\Convert-RC4toAES.ps1 -WhatIf -ExcludedDisplayNames @()
```
**Purpose**: Preview all objects without any exclusions
**Duration**: 2-5 minutes for analysis
**Use Case**: Complete security assessment and planning

## 📊 Script Workflow

```mermaid
graph TD
    A[Start Script] --> B[Import AD Module]
    B --> C[Query RC4-Only Objects]
    C --> D[Apply Exclusion Filter]
    D --> E{WhatIf Mode?}
    E -->|Yes| F[Preview Changes]
    E -->|No| G{Force Parameter?}
    G -->|Yes| H[Skip Confirmation]
    G -->|No| I[Request User Confirmation]
    I --> J{User Confirms?}
    J -->|No| K[Exit Script]
    J -->|Yes| L[Process Objects]
    H --> L
    F --> M[Show Summary]
    L --> N[Update AD Objects]
    N --> O{Force Parameter?}
    O -->|Yes| P[Skip Verification]
    O -->|No| Q[Optional Verification]
    P --> R[Generate Report]
    Q --> R
    M --> R
    R --> S[Complete]
```

## 🔍 Technical Details

### Kerberos Encryption Types
The script configures the following encryption support:

| Encryption Type | Value | Description |
|----------------|-------|-------------|
| RC4_HMAC | 4 (0x4) | Legacy RC4 encryption (backward compatibility) |
| AES128_CTS_HMAC_SHA1_96 | 8 (0x8) | Modern AES-128 encryption |
| AES256_CTS_HMAC_SHA1_96 | 16 (0x10) | Strong AES-256 encryption |
| **Combined Total** | **28 (0x1C)** | **RC4 + AES128 + AES256** |

### Active Directory Impact
- **Attribute Modified**: `msds-supportedencryptiontypes`
- **Change**: From `0` (RC4-only) to `28` (RC4+AES128+AES256)
- **Scope**: Computer accounts, service accounts, and user accounts with RC4-only configuration

### Performance Characteristics
- **Processing Rate**: 10-50 objects per minute
- **Memory Usage**: <100MB for typical environments
- **Network Impact**: Minimal (efficient LDAP operations)
- **Scalability**: Tested with domains containing 10,000+ objects

## 📝 Logging and Audit Trail

### Log File Location
```
.\Convert-RC4toAES-YYYY-MM-DD-HH-mm-ss.log
```

### Log Content Includes
- ✅ **Timestamp**: Precise execution timing
- ✅ **Object Details**: Names and distinguished names of modified objects
- ✅ **Before/After Values**: Encryption type changes
- ✅ **Exclusions**: Objects protected from modification
- ✅ **Errors**: Detailed error information with correlation
- ✅ **Summary**: Success/failure counts and totals

### Sample Log Output
```
2025-06-27 10:30:15 - [INFO] Starting RC4 to AES conversion...
2025-06-27 10:30:16 - [INFO] Found 25 objects with RC4-only encryption
2025-06-27 10:30:16 - [INFO] Excluded 3 objects from processing
2025-06-27 10:30:17 - [SUCCESS] Updated SERVER01$ - Encryption types: 28 (RC4+AES)
2025-06-27 10:30:18 - [SUCCESS] Updated SVC-Account - Encryption types: 28 (RC4+AES)
2025-06-27 10:30:45 - [INFO] Successfully processed: 22 objects
```

## ⚠️ Important Considerations

### Before Execution
- [ ] **Test in Lab Environment**: Always test with `-WhatIf` first
- [ ] **Change Management**: Obtain proper approvals for production changes
- [ ] **Backup Strategy**: Ensure AD backup is current
- [ ] **Legacy Assessment**: Identify systems requiring RC4-only encryption
- [ ] **Service Dependencies**: Review service accounts and applications

### After Execution
- [ ] **Service Validation**: Test affected services for authentication issues
- [ ] **Client Connectivity**: Verify client authentication to modified objects
- [ ] **Ticket Cache**: Consider clearing Kerberos ticket cache on clients
- [ ] **Monitoring**: Watch for authentication failures in event logs

### Potential Impacts
- **Service Accounts**: May require service restarts
- **Legacy Applications**: Older applications might need Kerberos ticket cache clearing
- **Client Behavior**: Authentication methods may change for affected objects
- **Network Traffic**: Minimal increase during execution period

## 🔄 Automation Integration

### Scheduled Tasks
```powershell
# Example scheduled task command
schtasks /create /tn "RC4-to-AES-Conversion" /tr "powershell.exe -File 'C:\Scripts\Convert-RC4toAES.ps1' -Force" /sc monthly
```

### CI/CD Pipeline Integration
```yaml
# Azure DevOps Pipeline Example
- task: PowerShell@2
  displayName: 'Convert RC4 to AES Encryption'
  inputs:
    filePath: 'Scripts/Convert-RC4toAES.ps1'
    arguments: '-Force -ExcludedDisplayNames @("LegacyApp1", "CriticalService")'
    errorActionPreference: 'stop'
```

### Configuration Management
```powershell
# PowerShell DSC Integration
Configuration SecureKerberos {
    Script RC4ToAESConversion {
        SetScript = {
            & "C:\Scripts\Convert-RC4toAES.ps1" -Force
        }
        TestScript = {
            # Test if RC4-only objects exist
            $rc4Objects = Get-ADObject -Filter "(msds-supportedencryptiontypes -eq 0)"
            return ($rc4Objects.Count -eq 0)
        }
        GetScript = { @{ Result = "RC4 to AES conversion status" } }
    }
}
```

## 🛠️ Troubleshooting

### Common Issues

#### Permission Errors
```
Error: Access is denied
Solution: Ensure running as Domain Administrator or equivalent
```

#### Module Not Found
```
Error: Module 'ActiveDirectory' not found
Solution: Install RSAT tools or run on domain controller
```

#### Object Access Denied
```
Error: Cannot update specific object
Solution: Check object permissions and delegation
```

#### Network Connectivity
```
Error: Cannot contact domain controller
Solution: Verify network connectivity and DNS resolution
```

### Validation Commands
```powershell
# Check current encryption types
Get-ADObject -Filter "(msds-supportedencryptiontypes -eq 0)" -Properties msds-supportedencryptiontypes

# Verify changes were applied
Get-ADObject -Filter "(msds-supportedencryptiontypes -eq 28)" -Properties msds-supportedencryptiontypes

# Test specific object
Get-ADObject -Identity "CN=ObjectName,OU=Computers,DC=domain,DC=com" -Properties msds-supportedencryptiontypes
```

## 📚 Additional Resources

### Microsoft Documentation
- [Kerberos Encryption Types](https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/network-security-configure-encryption-types-allowed-for-kerberos)
- [Active Directory PowerShell Module](https://docs.microsoft.com/en-us/powershell/module/activedirectory/)
- [Kerberos Authentication](https://docs.microsoft.com/en-us/windows-server/security/kerberos/kerberos-authentication-overview)

### Security Best Practices
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Controls](https://www.cisecurity.org/controls/)
- [Microsoft Security Baseline](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-security-baselines)

### Related Tools
- **PSScriptAnalyzer**: PowerShell script quality analysis
- **Pester**: PowerShell testing framework
- **Active Directory Administrative Center**: GUI management tool

## 🤝 Contributing

### Development Guidelines
1. **Follow PowerShell Best Practices**: Use approved verbs and proper formatting
2. **Comprehensive Testing**: Test in lab environments before production
3. **Documentation**: Update README.md and inline comments
4. **Security Focus**: Maintain enterprise security standards

### Reporting Issues
- **GitHub Issues**: Use the issue tracker for bug reports and feature requests
- **Security Issues**: Report security concerns through secure channels
- **Enhancement Requests**: Provide detailed use cases and business justification

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Jeffrey Stuhr**
- Blog: [https://www.techbyjeff.net](https://www.techbyjeff.net)
- LinkedIn: [jeffrey-stuhr-034214aa](https://www.linkedin.com/in/jeffrey-stuhr-034214aa/)
- GitHub: [@TechbyJeff](https://github.com/TechbyJeff)

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-06-27 | Initial release with enterprise features |
| | | - RC4 to AES encryption conversion |
| | | - WhatIf mode for safe preview |
| | | - Exclusion capability for legacy systems |
| | | - Comprehensive logging and audit trail |
| | | - Force parameter for automation scenarios |

---

### ⭐ Support This Project

If this script has helped improve your organization's security posture, please consider:
- ⭐ **Starring this repository**
- 🐛 **Reporting issues or bugs**
- 💡 **Suggesting enhancements**
- 📖 **Contributing to documentation**

---

*This script is maintained and updated regularly. Check back for new features and security enhancements.*
