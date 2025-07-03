# Find-UnknownSIDs PowerShell Scripts

## Overview & Purpose

This directory contains PowerShell scripts for Find-UnknownSIDs related tasks with enterprise-grade backup and restore capabilities.

## Available Scripts

| Script Name | Description |
|-------------|-------------|
| [Find-UnknownSIDs](./Find-UnknownSIDs.ps1) | Script for finding and removing orphaned SIDs in Active Directory with enterprise-grade features |

## Find-UnknownSIDs

### Overview & Purpose

Script for finding and removing orphaned SIDs in Active Directory with enterprise-grade features

This version provides comprehensive Active Directory security management with enterprise-grade
capabilities for identifying and removing orphaned Security Identifiers (SIDs) from ACLs.

### Enhanced Backup Organization

**NEW**: Timestamped backup subfolders organize backups by script execution:
- Each removal operation creates a unique timestamped subfolder (e.g., `Backup\20250702_104232\`)
- All backup files for a single script run are grouped together
- Enables precise audit trails and simplified rollback procedures
- Maintains backward compatibility with existing backup files

### Key Features

- **Modular Architecture**: Specialized components for discovery, removal, and backup operations
- **Enterprise Security**: Comprehensive validation and risk assessment with protected SID checking
- **Organized Backups**: Timestamped subfolders for each script execution with full audit trails
- **Performance Optimized**: Parallel processing for large environments with configurable throttling
- **Compliance Ready**: Detailed audit trails and correlation tracking for regulatory requirements

## Module Architecture

The solution follows enterprise PowerShell best practices with a modular architecture for maintainability and scalability:

### Core Modules

| Module | Responsibility | Key Functions |
|--------|---------------|---------------|
| **SIDValidation.ps1** | SID validation, format checking, cache management | `Test-OrphanedSID`, `Test-SIDFormat`, `Test-WellKnownSID` |
| **ADOperations.ps1** | Active Directory connectivity and bulk operations | `Invoke-ADOperationWithRetry`, `Get-ADObjectsParallel` |
| **SIDProcessing.ps1** | SID discovery, analysis, and processing workflows | `Find-OrphanedSIDsInObject`, `Get-SIDAnalysis` |
| **RemovalOperations.ps1** | SID removal operations with safety validations | `Remove-OrphanedSIDs`, `Remove-OrphanedSIDFromObject` |
| **BackupOperations.ps1** | Backup and restore functionality with integrity checks | `Backup-ObjectACL`, `Restore-ObjectACL` |
| **Configuration.ps1** | Configuration management and validation | `Initialize-ScriptConfiguration` |
| **Orchestration.ps1** | Workflow orchestration and coordination | `Invoke-DiscoveryWorkflow`, `Invoke-RemovalWorkflow` |
| **Logging.ps1** | Structured logging framework with correlation tracking | `Write-ScriptLog`, `Initialize-LoggingFramework` |

### Module Dependencies

```
Logging.ps1
├── Configuration.ps1
├── SIDValidation.ps1
│   ├── SIDProcessing.ps1
│   └── ADOperations.ps1
├── BackupOperations.ps1
├── RemovalOperations.ps1
└── Orchestration.ps1
```

### Design Principles

- **Single Responsibility**: Each module has a clear, focused purpose
- **Loose Coupling**: Minimal dependencies between modules
- **High Cohesion**: Related functions grouped together
- **Error Resilience**: Comprehensive error handling throughout
- **Performance Optimization**: Caching and parallel processing where appropriate