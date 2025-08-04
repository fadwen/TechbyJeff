# ADTestEnvironment PowerShell Module

An enterprise-grade PowerShell module for generating, managing, and maintaining comprehensive Active Directory test environments. Designed for system administrators, test engineers, and DevOps teams who need realistic, scalable, and secure test data for AD-dependent applications and infrastructure.

## 🚀 Key Features

### Enterprise Architecture
- **Modular Design**: Professional PowerShell module with proper Public/Private function separation
- **Secure Password Management**: Cryptographically secure password generation with export documentation
- **Service Account Support**: Dedicated service account creation with realistic manager assignments
- **Dynamic Path Resolution**: Intelligent data file location with multiple fallback strategies
- **Cross-Platform Ready**: Compatible with Windows PowerShell 5.1 and PowerShell 7.x

### Advanced Test Data Management
- **Realistic Data Sets**: 150+ sample users with authentic names, departments, and organizational structure
- **Device Lifecycle**: Complete device management including workstations, servers, laptops, and mobile devices
- **Security Group Hierarchy**: Comprehensive group structure with automatic membership and role-based access
- **Manager Relationships**: Realistic organizational hierarchy with proper reporting structures
- **Photo Integration**: Automatic user photo import from standardized image files

### Enterprise-Grade Operations
- **WhatIf Support**: Complete preview capability for all destructive operations
- **Progress Reporting**: Real-time progress tracking with correlation ID tracing
- **Error Resilience**: Comprehensive error handling with detailed logging and recovery
- **Multiple Output Formats**: Professional reports in Console, JSON, HTML, and CSV formats
- **Safe Environment Management**: Controlled creation and removal with built-in safety mechanisms

### CI/CD and Automation Ready
- **Skip Logic**: Flexible component selection with ValidateSet parameters
- **Batch Operations**: Optimized for large-scale test environment creation
- **Pipeline Integration**: Designed for automated testing and deployment scenarios
- **Audit Trail**: Complete operation logging with correlation ID tracking
- **Validation Framework**: Built-in environment validation and completeness checking

## 🚀 Quick Start

### 1. Import the Module
```powershell
# Import from the current directory
Import-Module .\ADTestEnvironment.psd1

# Or install to a module path and import by name
Import-Module ADTestEnvironment
```

### 2. Create the Complete Test Environment
```powershell
# Create everything (OUs, Users, Devices, Service Accounts, Security Groups)
New-ADTestEnvironment

# Preview what would be created without making changes
New-ADTestEnvironment -WhatIf

# Skip specific components using flexible parameters
New-ADTestEnvironment -Skip @('ServiceAccounts', 'SecurityGroups') -Verbose

# Create with password documentation export
New-ADTestEnvironment -Verbose
# Password documentation automatically exported to timestamped ServiceAccountPW.txt
```

### 3. Generate Comprehensive Reports
```powershell
# Executive summary with environment overview
Get-ADTestEnvironmentReport

# Detailed HTML report with group memberships and statistics
Get-ADTestEnvironmentReport -OutputFormat HTML -OutputPath "C:\Reports\ADTestReport.html"

# Data analysis exports with complete object details
Get-ADTestEnvironmentReport -OutputFormat CSV -OutputPath "C:\Reports\"

# Machine-readable format for automation integration
Get-ADTestEnvironmentReport -OutputFormat JSON -OutputPath "C:\Reports\ADTestReport.json"
```

### 4. Environment Management and Cleanup
```powershell
# Preview removal impact (always preview first!)
Remove-ADTestEnvironment -WhatIf

# Standard cleanup (removes objects, preserves OU structure for reuse)
Remove-ADTestEnvironment

# Complete environment reset (removes everything including OUs)
Remove-ADTestEnvironment -RemoveOUs -Force
```

**Expected Output Examples:**
```

=========================================
   Active Directory Test Environment Creation
=========================================
Step 1: Creating OU Structure

=========================================
   Active Directory TestData OU Structure Creation
=========================================
Creating main TestData OU...
Creating Groups category sub-OUs...
Creating Device type sub-OUs...
Analyzing departments from ADUsers.csv...                                                                                               Creating department sub-OUs...                                                                                                          OU Creation Summary                                                                                                                       OUs Created: 0                                                                                                                          OUs Skipped: 33                                                                                                                       
Organizational structure creation complete!                                                                                             
Step 2: Creating User Accounts                                                                                                          

=========================================
   Creating Active Directory Test Users
=========================================
Loading user data from CSV...
Processing 290 users in batches of 15...
Setting manager relationships...
User Creation Summary (Batch Mode)                                                                                                        Total Batches: 20                                                                                                                       Batch Size: 15                                                                                                                          Users Created: 230                                                                                                                    
  Users Skipped: 0                                                                                                                        Managers Set: 289                                                                                                                     
Step 3: Creating Device Objects                                                                                                         

=========================================
   Creating Active Directory Test Devices
=========================================
Loading device data from CSV...
Processing 688 devices in batches of 18...                                                                                              Device Creation Summary (Batch Mode)                                                                                                      Total Batches: 39                                                                                                                       Batch Size: 18                                                                                                                        
  Devices Created: 634                                                                                                                  
  Devices Skipped: 0
Step 4: Creating Service Accounts

=========================================
   Creating Active Directory Test Service Accounts
=========================================
Loading service account data from CSV...
Processing 25 service accounts...                                                                                                       Service Account Creation Summary                                                                                                          Accounts Created: 25                                                                                                                    Accounts Skipped: 0                                                                                                                     Password File: C:\Temp\ADTestEnvironment\ServiceAccountPW-20250804-134953.txt                                                           WARNING: Store password file securely and delete after use!                                                                           Step 5: Creating Security Groups                                                                                                                                                                                                                                                =========================================                                                                                                  Creating Active Directory Test Security Groups                                                                                       =========================================                                                                                               
Loading security group data from CSV...                                                                                                 
Processing 87 security groups...                                                                                                        
Preparing group membership assignments...
Processing membership for 87 groups using batch processing...
  Batch Size: 15
  Throttle Limit: 5
  Total Batches: 6
Waiting for membership assignment jobs to complete...
Membership assignment completed using batch processing
Security Group Creation Summary
  Groups Created: 45
  Groups Skipped: 42
  Members Added: 5966

=========================================
   Environment Creation Summary
=========================================
Operations Completed: 5/5
Duration: 00:01:03
Test environment creation complete!
```

## 📋 Module Components

### 🎯 Public Functions (User-Facing API)

| Function | Purpose | Key Features |
|----------|---------|--------------|
| **New-ADTestEnvironment** | Complete environment orchestration | Skip logic, WhatIf support, correlation tracking |
| **New-ADTestOUStructure** | Standardized OU hierarchy creation | Department-based organization, protection settings |
| **New-ADTestUsers** | Realistic user account creation | Photo import, manager relationships, department assignment |
| **New-ADTestDevices** | Computer object management | Device categories, realistic naming, OS assignment |
| **New-ADTestServiceAccounts** | Service account provisioning | Secure passwords, manager assignment, documentation export |
| **New-ADTestSecurityGroups** | Security group automation | Automatic membership, role-based access, group hierarchy |
| **Get-ADTestEnvironmentReport** | Comprehensive environment reporting | Multiple formats, detailed analytics, audit trail |
| **Remove-ADTestEnvironment** | Safe environment cleanup | Hierarchical removal, confirmation prompts, completeness validation |

### 🔧 Private Functions (Internal Architecture)

| Function | Purpose | Usage |
|----------|---------|-------|
| **Export-PasswordDocumentation** | Secure password documentation export | Called automatically by service account creation |
| **Get-ADTestDataPath** | Intelligent data file location | Multiple fallback strategies for CSV data files |
| **Get-ADTestDomain** | Domain context detection | Provides DNS and DN information for operations |
| **New-ADTestOU** | Individual OU creation with error handling | Used by structure creation with WhatIf support |
| **New-CSVReport** | CSV format report generation | Called by Get-ADTestEnvironmentReport for CSV output |
| **New-HTMLReport** | HTML format report generation | Called by Get-ADTestEnvironmentReport for HTML output |
| **New-JSONReport** | JSON format report generation | Called by Get-ADTestEnvironmentReport for JSON output |
| **New-SecureRandomPassword** | Cryptographically secure password generation | Complexity requirements, entropy validation |
| **Test-ADTestPrerequisites** | Environment validation | Checks permissions, module availability, domain connectivity |
| **Write-ADTestProgress** | Standardized progress reporting | Consistent messaging with correlation ID tracking |

## 📊 Test Data Overview

The module creates realistic, enterprise-scale test environments using carefully curated data sets:

### 👥 User Accounts (267+ Total)
- **Authentic Names**: Diverse, realistic first and last names representing global workforce
- **Organizational Structure**: 17 departments with realistic titles and reporting hierarchies
- **Contact Information**: Professional email addresses and phone number formatting
- **Manager Relationships**: Realistic supervisory chains with appropriate span of control
- **Account Attributes**: Proper account settings, password policies, and security configurations
- **Photo Integration**: Automatic profile photo assignment from standardized image files

### 💻 Device Objects (419+ Total)
- **Workstations**: Department-assigned user workstations with realistic naming conventions (382 devices)
- **Servers**: Infrastructure servers including domain controllers, file servers, and application servers (23 devices)
- **Printers**: Network printing devices distributed across locations (14 devices)
- **Mobile Devices**: Tablets and smartphones for modern workplace scenarios (varies)
- **Network Equipment**: Access points and network infrastructure devices
- **Operating Systems**: Realistic OS distribution reflecting modern enterprise environments

### 👤 Service Accounts (25 Total)
- **Application Services**: Dedicated accounts for application pools and services
- **Infrastructure Services**: Accounts for backup, monitoring, and maintenance operations
- **Integration Accounts**: Service accounts for system-to-system communication
- **Secure Password Management**: Cryptographically secure passwords with automatic documentation
- **Manager Assignment**: Realistic assignment to appropriate IT staff members
- **Password Documentation**: Timestamped export files with security warnings and restrictive permissions

### 🔐 Security Groups (79+ Total)
- **Department Groups**: Finance, HR, Engineering, Sales, Marketing, and Operations (15 groups)
- **Role-Based Groups**: Job function and responsibility-based access control (10 groups)
- **Location Groups**: Geographic and facility-based access management (12 groups)
- **Device Groups**: Computer management and policy application groups (6 groups)
- **Resource Groups**: Application and system resource access control (36 groups)

### 📁 Organizational Structure
```
TestData (Root OU)
├── Users/
│   ├── 1099 Contractor/                    (29 users)
│   ├── Accounting/                         (9 users)
│   ├── Content Management Consulting/      (20 users)
│   ├── Creative/                           (0 users)
│   ├── CRM Strategy/                       (9 users)
│   ├── CVP of IT/                          (0 users)
│   ├── Engineering Operations/             (20 users)
│   ├── Engineering/                        (5 users)
│   ├── Executive/                          (7 users)
│   ├── Human Resources/                    (5 users)
│   ├── IT Support/                         (2 users)
│   ├── Marketing/                          (13 users)
│   ├── Operations/                         (25 users)
│   ├── Project Management/                 (31 users)
│   ├── Sales/                              (46 users)
│   ├── Sales Engagement Management/        (18 users)
│   ├── Senior Management/                  (8 users)
│   └── Strategy Consulting/                (varies)
├── Devices/
│   ├── Workstations/                       (382 devices)
│   ├── Servers/                            (23 devices)
│   ├── Printers/                           (14 devices)
│   └── Mobile/                             (varies)
├── ServiceAccounts/                        (25 accounts)
└── Groups/
    ├── Department/                         (15 groups)
    ├── Role/                               (10 groups)
    ├── Location/                           (12 groups)
    ├── Device/                             (6 groups)
    └── Resource/                           (36 groups)
```

## Prerequisites

- **PowerShell 5.1** or later
- **Active Directory PowerShell Module**
- **Domain Administrator** or equivalent permissions
- **Windows Server** with Active Directory Domain Services
- **.NET Framework 4.5** or later

### Installing Prerequisites

```powershell
# Install AD PowerShell module (Windows 10/Server 2016+)
Install-WindowsFeature -Name RSAT-AD-PowerShell

# For older versions, install RSAT tools manually
# Download from Microsoft website
```

## 📁 Module Structure

```
Generate-TestData/
├── Public/                               # Main exported functions
│   ├── Get-ADTestEnvironmentReport.ps1   # Environment reporting
│   ├── New-ADTestDevices.ps1             # Device creation
│   ├── New-ADTestEnvironment.ps1         # Full environment orchestration
│   ├── New-ADTestOUStructure.ps1         # OU structure creation
│   ├── New-ADTestSecurityGroups.ps1      # Security group management
│   ├── New-ADTestServiceAccounts.ps1     # Service account creation
│   ├── New-ADTestUsers.ps1               # User account creation
│   └── Remove-ADTestEnvironment.ps1      # Environment cleanup
├── Private/                              # Internal helper functions
│   ├── Export-PasswordDocumentation.ps1  # Password export logic
│   ├── Get-ADTestDataPath.ps1            # Data path resolution
│   ├── Get-ADTestDomain.ps1              # Domain detection
│   ├── New-ADTestOU.ps1                  # OU creation helper
│   ├── New-SecureRandomPassword.ps1      # Password generation
│   ├── Test-ADTestPrerequisites.ps1      # Prerequisite validation
│   └── Write-ADTestProgress.ps1          # Progress messaging
├── Data/                                 # Test data definitions
│   ├── ADUsers.csv                       # User account data
│   ├── ADDevices.csv                     # Device object data
│   ├── ADSecurityGroups.csv              # Security group data
│   └── ADServiceAccounts.csv             # Service account data
├── UserImages/                           # Profile photos (150+ files)
├── Generate-TestData.psd1                # Module manifest
├── Generate-TestData.psm1                # Module loader
└── README.md                             # This file
```

### Key Components

- **Public Functions**: Eight primary functions for creating and managing test environments
- **Private Helpers**: Ten internal utilities for common operations and security
- **CSV Data Files**: Structured test data for realistic environment creation
- **Profile Photos**: 150+ standardized user photos for authentic directory services
- **Documentation**: Comprehensive per-function documentation for maintenance and extension

## Advanced Usage

### Custom Data Files
You can modify the CSV files to customize your test environment:

```powershell
# Edit user data
notepad .\Data\ADUsers.csv

# Recreate just the users
New-ADTestUsers
```

### Modular Creation
Create specific components independently:

```powershell
# Create just the OU structure
New-ADTestOUStructure

# Add users to existing structure  
New-ADTestUsers

# Create security groups with automatic membership
New-ADTestSecurityGroups
```

### Progress Monitoring
All functions support detailed progress reporting:

```powershell
# Enable verbose output for detailed progress
New-ADTestEnvironment -Verbose

# Use WhatIf to preview all changes
New-ADTestEnvironment -WhatIf
```

### Correlation Tracking
Each operation generates a correlation ID for tracking:

```powershell
$result = New-ADTestUsers
Write-Host "Operation ID: $($result.CorrelationId)"
```

## Troubleshooting

### Common Issues

**"Access Denied" Errors**
- Verify you have Domain Administrator privileges
- Check if the AD PowerShell module is installed
- Ensure you're running PowerShell as an administrator

**"OU Already Exists" Warnings**
- This is normal if you've run the scripts before
- The functions will skip existing OUs and continue
- Use `-WhatIf` to preview what will be created

**"Cannot Find Path" Errors**
- Verify CSV files are in the `Data/` directory
- Check that file names match exactly (case sensitive on some systems)
- Ensure the module is imported from the correct location

**Performance Issues**
- Large datasets may take time to process
- Monitor progress with `-Verbose` parameter
- Consider creating objects in smaller batches

### Diagnostic Commands

```powershell
# Test module import
Get-Module ADTestEnvironment

# Verify AD connectivity
Get-ADDomain

# Check available functions
Get-Command -Module ADTestEnvironment

# Test data file access
Test-Path .\Data\ADUsers.csv

# View detailed help
Get-Help New-ADTestEnvironment -Full
```

### Log Analysis

Check Windows Event Logs for detailed information:
- **Active Directory Web Services** log
- **Directory Service** log  
- **PowerShell Operational** log

## 📚 Additional Resources

### Support and Maintenance
- **Module Architecture**: Modular design supports easy extension and customization
- **Error Handling**: Comprehensive error reporting with correlation ID tracking
- **Logging Integration**: Compatible with enterprise logging and monitoring systems
- **Version Control**: Git-friendly structure with proper .gitignore for sensitive files

## License

This module is provided as-is for educational and testing purposes. Use in production environments is not recommended without thorough testing.

---

**Author**: Jeffrey Stuhr  
**Version**: 1.0.0  
**Last Updated**: August 2025

For questions or support, please create an issue in the repository.