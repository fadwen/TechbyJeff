# ADTestEnvironment

[![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-v1.0.0-blue)](https://www.powershellgallery.com/)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)

## 📖 Purpose

**ADTestEnvironment** is a comprehensive PowerShell module designed to create realistic Active Directory test environments with minimal effort. Whether you're a system administrator testing Group Policy configurations, a security engineer validating permissions, or a trainer setting up classroom labs, this module provides enterprise-grade test data that mirrors real-world AD deployments.

**Business Value:** Eliminate weeks of manual test data creation. Go from empty domain to fully populated test environment in under 2 minutes with 291 realistic users (with photos), 689 devices, 88 security groups, and 26 service accounts.

**Key Differentiators:**
- ✅ **Realistic Data**: Based on actual corporate structures with proper reporting hierarchies
- ✅ **Security First**: Optional SecretStore integration for encrypted password management
- ✅ **Performance Optimized**: Batched processing with configurable throttling for large environments
- ✅ **Enterprise Ready**: Comprehensive reporting and cleanup capabilities

## 🚀 Quick Start

### Immediate Setup (3 Commands)
```powershell
# 1. Import the module
Import-Module .\ADTestEnvironment.psd1

# 2. Create complete test environment
New-ADTestEnvironment

# 3. Generate HTML report
Get-ADTestEnvironmentReport -OutputFormat HTML -OutputPath ".\ADTestReport.html"
```

### Expected Results
```
✅ Test environment creation completed successfully
📊 Created: 291 users, 689 devices, 88 groups, 26 service accounts
📄 Report generated: .\ADTestReport.html
⏱️  Total time: 6-8 minutes
```

### Next Steps
- **For Security**: Add `-UseSecretStore` to encrypt all passwords
- **For Performance**: Adjust `-BatchSize` parameters for your environment
- **For Automation**: Use `-PassThru` to capture results for further processing

## 📋 Prerequisites

| Requirement | Minimum | Recommended | Purpose |
|-------------|---------|-------------|---------|
| **PowerShell** | 5.1 | 7.4+ | Module execution |
| **Active Directory** | 2016 FL | 2019+ FL | Target environment |
| **RSAT-AD-PowerShell** | Any | Latest | Required dependency |
| **Domain Privileges** | User Creator | Domain Admin | Object creation |
| **Memory** | 4GB | 8GB+ | Batch processing |

### Dependencies Installation
```powershell
# Required - Install RSAT Active Directory module
Install-WindowsFeature RSAT-AD-PowerShell

# Optional - Auto-installed when using -UseSecretStore
# Install-Module Microsoft.PowerShell.SecretManagement
# Install-Module Microsoft.PowerShell.SecretStore
```

## 🔧 Configuration

### Basic Setup
```powershell
# Create OU structure (recommended first step)
New-ADTestOUStructure -PassThru
```

### Secure Password Management (Recommended)
```powershell
# Enable SecretStore for encrypted password storage
New-ADTestEnvironment -UseSecretStore

# Retrieve passwords later
Get-ADTestPasswordFromVault -ServiceAccountName "svc-backup"
```

## 💡 Core Functions

### Environment Management
- **`New-ADTestEnvironment`** - Creates complete test environment
  - Parameters: `Skip[]`, `ShowProgress`, `UseSecretStore`, `VaultName`, `VaultPassword`, `GlobalVault`, `PassThru`
- **`Remove-ADTestEnvironment`** - Removes test environment with cleanup
  - Parameters: `RemoveOUs`, `VaultName`, `Force`, `ResetSecretStore`, `GlobalVault`, `PassThru`

### Individual Components
- **`New-ADTestUser`** - Creates 291 test users from CSV data
  - Parameters: `IncludePhotos`, `BatchSize (1-50, default 15)`, `ThrottleLimit (1-8, default 4)`, `PassThru`
- **`New-ADTestDevice`** - Creates 689 test computer objects
  - Parameters: `BatchSize (1-100, default 17)`, `ThrottleLimit (1-10, default 6)`
- **`New-ADTestSecurityGroups`** - Creates 88 security groups with members
  - Parameters: `SkipMemberAssignment`, `BatchSize (1-50, default 15)`, `ThrottleLimit (1-20, default 5)`, `PassThru`
- **`New-ADTestServiceAccount`** - Creates 26 service accounts
  - Parameters: `UseSecretStore`, `VaultName`, `VaultPassword`, `GlobalVault`, `PassThru`

### Reporting & Management
- **`Get-ADTestEnvironmentReport`** - Generates comprehensive reports
  - Parameters: `OutputFormat (Console/JSON/HTML/CSV, default Console)`, `OutputPath`, `PassThru`
- **`Get-ADTestPasswordFromVault`** - Retrieves stored passwords securely
  - Parameters: `ServiceAccountName`, `SecretName`, `VaultName`, `AsPlainText`, `ListSecrets`, `IncludeExpired`
- **`New-ADTestOUStructure`** - Creates organizational unit hierarchy
  - Parameters: `PassThru`

## 📊 Test Data Inventory

### Users (291 total)
- **Source**: `Data\ADUsers.csv` (realistic employee data)
- **Features**: 12 departments, proper reporting structure, contact info, employee IDs
- **Photos**: 291 individual profile images in `Data\UserImages\`
- **Departments**: Executive, Operations, Engineering, Sales, HR, IT, Finance, etc.

### Devices (689 total)
- **Source**: `Data\ADDevices.csv`
- **Types**: Workstations, laptops, servers, printers, mobile devices
- **OS Mix**: Various Windows versions and server editions

### Security Groups (88 total)
- **Source**: `Data\ADSecurityGroups.csv`
- **Types**: Department groups, functional groups, distribution lists
- **Features**: Realistic member assignments, nested structures

### Service Accounts (26 total)
- **Source**: `Data\ADServiceAccounts.csv`
- **Services**: SQL Server, IIS, backup services, applications
- **Features**: Appropriate permissions, secure password generation

## 📈 Performance Optimization

### Batch Processing Configuration
```powershell
# Conservative (slower, more reliable)
New-ADTestUser -BatchSize 10 -ThrottleLimit 2

# Balanced (default settings)
New-ADTestUser -BatchSize 15 -ThrottleLimit 4

# Aggressive (faster, requires robust DC)
New-ADTestUser -BatchSize 30 -ThrottleLimit 8
```

### Expected Performance
- **Users**: 200-300 per minute (depending on photos and batch size)
- **Devices**: 900-1200 per minute
- **Groups**: 60-80 per minute
- **Total Environment**: 1-2 minutes for complete setup

## 🛡️ Security Features

### Password Management
```powershell
# Secure password storage with SecretStore
New-ADTestServiceAccount -UseSecretStore -VaultName "ADTest"

# Retrieve as SecureString (recommended)
$securePassword = Get-ADTestPasswordFromVault -ServiceAccountName "svc-sql"

# List all stored secrets
Get-ADTestPasswordFromVault -ListSecrets
```

### Cleanup and Security
```powershell
# Complete environment removal with vault cleanup
Remove-ADTestEnvironment -ResetSecretStore -Force

# Remove specific vault
Remove-ADTestEnvironment -VaultName "CustomVault" -Force
```

## 📋 Common Usage Patterns

### Development Lab Setup
```powershell
# Quick lab with basic users and groups
New-ADTestOUStructure -Skip Devices,ServiceAccounts

```

### Security Testing Environment
```powershell
# Full environment with encrypted passwords
New-ADTestEnvironment -UseSecretStore
Get-ADTestEnvironmentReport -OutputFormat JSON -OutputPath ".\security-audit.json"
```

### Training Classroom
```powershell
# Complete environment with visual elements
New-ADTestEnvironment -ShowProgress
Get-ADTestEnvironmentReport -OutputFormat HTML -OutputPath ".\class-environment.html"
```

### Performance Testing
```powershell
# High-speed creation for large environments
New-ADTestUser -BatchSize 50 -ThrottleLimit 8
New-ADTestDevice -BatchSize 100 -ThrottleLimit 10
New-ADTestSecurityGroups -BatchSize 25 -ThrottleLimit 8
```

## 🔍 Troubleshooting

### Common Issues

**Active Directory Module Missing**
```powershell
# Solution: Install RSAT
Install-WindowsFeature RSAT-AD-PowerShell
```

**Performance Issues**
```powershell
# Solution: Reduce batch sizes
New-ADTestUser -BatchSize 5 -ThrottleLimit 2
```

**SecretStore Problems**
```powershell
# Solution: Reset and recreate
Remove-ADTestEnvironment -ResetSecretStore -Force
New-ADTestServiceAccount -UseSecretStore
```

For detailed troubleshooting guides, see the `Troubleshooting/` folder in the module directory.

## 📊 Module Information

- **Version**: 1.0.0
- **Author**: Jeffrey Stuhr (EntraVantage LLC)
- **PowerShell**: 5.1+ (Desktop/Core compatible)
- **Dependencies**: ActiveDirectory module (required), SecretManagement/SecretStore (optional)
- **Module GUID**: b5e8c4a2-1d3f-4e7a-9b2c-6f8d4e1a5c7b

## 📞 Support & Contact

- **Author**: Jeffrey Stuhr
- **Company**: EntraVantage LLC
- **Blog**: https://www.techbyjeff.net
- **LinkedIn**: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For issues, feature requests, or contributions, please use the repository's issue tracker.
