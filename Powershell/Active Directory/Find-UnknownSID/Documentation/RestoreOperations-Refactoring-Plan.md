# RestoreOperations.ps1 - Comprehensive Modular Refactoring Plan

## 📋 Executive Summary

This document provides a detailed, phase-by-phase plan for refactoring the `RestoreOperations.ps1` file to adhere to PowerShell's "do one thing well" principle. The current 419-line file with a 257-line function violates single responsibility principles and requires modular decomposition using approved PowerShell verb-noun naming conventions.

## 🎯 Refactoring Objectives

### Primary Goals
- **Single Responsibility**: Each module performs one specific function
- **Maintainability**: Smaller, focused functions easier to understand and modify
- **Testability**: Individual components can be unit tested independently
- **Reusability**: Components can be used across different contexts
- **Standards Compliance**: Align with PowerShell community best practices
- **Approved Naming**: All functions use Microsoft-approved PowerShell verbs

### Success Criteria
- ✅ No function exceeds 75 lines (PowerShell best practice)
- ✅ Each module has single, clear responsibility
- ✅ All functions use approved PowerShell verb-noun naming (`Get-Verb` compliant)
- ✅ Comprehensive comment-based help for all public functions
- ✅ Unit tests with 80%+ coverage for each module
- ✅ No regression in functionality or security controls
- ✅ Signature verification

**Implementation Steps:**
```powershell
# Phase 1 Implementation
function Test-BackupIntegrity {
    <#
    .SYNOPSIS
        Validates backup file integrity and format compatibility.

    .DESCRIPTION
        Performs comprehensive validation of backup files including:
        - Required property verification
        - Signature validation for version compatibility
        - SDDL hash integrity checking
        - Metadata completeness validation

    .PARAMETER BackupData
        PSCustomObject containing backup data to validate

    .PARAMETER ExpectedObjectDN
        Optional DN to verify backup target object

    .EXAMPLE
        Test-BackupIntegrity -BackupData $backupObject
        Validates the backup data integrity

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.1.0
        TROUBLESHOOTING: .\Troubleshooting\Common\Backup-Restore-Issues.md
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$BackupData,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedObjectDN
    )

    # Implementation extracted from current Test-BackupIntegrity
}

function Test-BackupFormat {
    <#
    .SYNOPSIS
        Validates backup file format and version compatibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$BackupData
    )

    # New focused function for format validation
}

function Get-BackupMetadata {
    <#
    .SYNOPSIS
        Extracts and validates backup metadata information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$BackupData
    )

    # New utility function for metadata extraction
}
```

### Phase 2: Extract ACL Restoration Module

#### Create: `Private/Restore/Restore-ACLOperation.ps1`
**Functions to Extract:**
- `Restore-ObjectACL` (refactored from existing function)
- `Set-ObjectPermission` (new focused function)
- `Get-RestorationTarget` (new utility function)
- `Confirm-RestorationSuccess` (new validation function)

**Responsibilities:**
- ✅ Core ACL restoration logic
- ✅ Permission application
- ✅ Target object verification
- ✅ Restoration success validation

**Implementation Steps:**
```powershell
# Phase 2 Implementation
function Restore-ObjectACL {
    <#
    .SYNOPSIS
        Restores ACL permissions to Active Directory object from backup.

    .DESCRIPTION
        Performs complete ACL restoration including:
        - Backup validation and integrity checking
        - Target object verification and access validation
        - SDDL conversion and permission application
        - Restoration verification and success confirmation
        - Comprehensive error handling and logging

    .PARAMETER ObjectDN
        Distinguished name of the target object for restoration

    .PARAMETER BackupData
        Validated backup data containing SDDL and metadata

    .PARAMETER WhatIf
        Shows what would happen without making changes

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .EXAMPLE
        Restore-ObjectACL -ObjectDN "OU=Test,DC=domain,DC=com" -BackupData $backup
        Restores ACL from backup data to the specified object

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.1.0
        TROUBLESHOOTING: .\Troubleshooting\Common\Backup-Restore-Issues.md
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDN,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$BackupData,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    # Refactored implementation focusing only on restoration logic
}

function Set-ObjectPermission {
    <#
    .SYNOPSIS
        Applies SDDL permissions to Active Directory object.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDN,

        [Parameter(Mandatory)]
        [string]$SDDL
    )

    # New focused function for permission application
}
```

### Phase 3: Extract Workflow Orchestration

#### Create: `Private/Restore/Invoke-RestoreWorkflow.ps1`
**Functions to Extract:**
- `Invoke-RestoreWorkflow` (new orchestration function)
- `Start-RestoreOperation` (new initialization function)
- `Complete-RestoreOperation` (new completion function)

**Responsibilities:**
- ✅ Restoration workflow coordination
- ✅ Progress tracking and reporting
- ✅ Error handling and recovery
- ✅ Operation lifecycle management

### Phase 4: Extract Logging Module

#### Create: `Private/Restore/Write-RestoreLog.ps1`
**Functions to Extract:**
- `Write-RestoreLog` (new structured logging function)
- `Write-RestoreProgress` (new progress logging function)
- `Export-RestoreSummary` (new summary reporting function)

**Responsibilities:**
- ✅ Structured restore operation logging
- ✅ Progress tracking and reporting
- ✅ Summary generation and export
- ✅ Correlation ID management

### Phase 5: Extract Utilities Module

#### Create: `Private/Restore/Get-RestoreUtility.ps1`
**Functions to Extract:**
- `Get-RestoreConfiguration` (new configuration function)
- `Test-RestorePermission` (new permission validation function)
- `Get-CorrelationContext` (new correlation management function)

**Responsibilities:**
- ✅ Shared utility functions
- ✅ Configuration management
- ✅ Permission validation
- ✅ Correlation context management

## 🔄 Refactored Main File

### Updated: `RestoreOperations.ps1`
```powershell
#Requires -Version 5.1

<#
.SYNOPSIS
    Main entry point for restore operations orchestration.

.DESCRIPTION
    Orchestrates restore operations by coordinating specialized modules:
    - Backup validation through Test-BackupValidation module
    - ACL restoration through Restore-ACLOperation module
    - Workflow management through Invoke-RestoreWorkflow module
    - Logging through Write-RestoreLog module
#>

# Import specialized modules
. "$PSScriptRoot\Restore\Test-BackupValidation.ps1"
. "$PSScriptRoot\Restore\Restore-ACLOperation.ps1"
. "$PSScriptRoot\Restore\Invoke-RestoreWorkflow.ps1"
. "$PSScriptRoot\Restore\Write-RestoreLog.ps1"
. "$PSScriptRoot\Restore\Get-RestoreUtility.ps1"

function Restore-ObjectACLFromBackup {
    <#
    .SYNOPSIS
        Orchestrates complete restore operation using specialized modules.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDN,

        [Parameter(Mandatory)]
        [PSCustomObject]$BackupData,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        # Phase 1: Validate backup (Test-BackupValidation module)
        $validationResult = Test-BackupIntegrity -BackupData $BackupData -ExpectedObjectDN $ObjectDN
        if (-not $validationResult.IsValid) {
            throw "Backup validation failed: $($validationResult.Issues -join '; ')"
        }

        # Phase 2: Execute restoration (Restore-ACLOperation module)
        $restoreResult = Restore-ObjectACL -ObjectDN $ObjectDN -BackupData $BackupData -CorrelationId $CorrelationId

        # Phase 3: Log results (Write-RestoreLog module)
        Write-RestoreLog -Operation "Restore" -Result $restoreResult -CorrelationId $CorrelationId

        return $restoreResult

    } catch {
        Write-RestoreLog -Operation "Restore" -Error $_ -CorrelationId $CorrelationId
        throw
    }
}
```

## 📈 Benefits of Modular Refactoring

### 🎯 Single Responsibility Achievement
- ✅ **Test-BackupValidation.ps1**: Only validates backup integrity
- ✅ **Restore-ACLOperation.ps1**: Only handles ACL restoration
- ✅ **Invoke-RestoreWorkflow.ps1**: Only orchestrates workflow
- ✅ **Write-RestoreLog.ps1**: Only handles logging

### 🧪 Improved Testability
- ✅ **Unit Testing**: Each module can be tested independently
- ✅ **Mock Integration**: Easy to mock dependencies between modules
- ✅ **Focused Tests**: Tests target specific functionality without side effects

### 🔧 Enhanced Maintainability
- ✅ **Smaller Functions**: Average 50-75 lines per function
- ✅ **Clear Dependencies**: Explicit module relationships
- ✅ **Easier Debugging**: Isolated functionality for troubleshooting

### 📚 Better Documentation
- ✅ **Comprehensive Help**: Each module has complete comment-based help
- ✅ **Focused Examples**: Examples specific to module functionality
- ✅ **Troubleshooting Links**: Direct links to relevant troubleshooting guides

## 🛠️ Implementation Timeline

### Week 1: Phase 1-2 (Core Extraction)
- Extract backup validation module
- Extract ACL restoration module
- Update unit tests

### Week 2: Phase 3-4 (Workflow & Logging)
- Extract workflow orchestration
- Extract logging module
- Integration testing

### Week 3: Phase 5-6 (Utilities & Finalization)
- Extract utilities module
- Update main RestoreOperations.ps1
- Comprehensive testing and documentation

## ✅ Success Criteria

### Code Quality Metrics
- ✅ **Function Length**: All functions ≤ 75 lines
- ✅ **Single Responsibility**: Each module has one clear purpose
- ✅ **Approved Verbs**: All functions use PowerShell approved verbs
- ✅ **Documentation**: 100% comment-based help coverage

### Testing Requirements
- ✅ **Unit Tests**: 90%+ code coverage per module
- ✅ **Integration Tests**: End-to-end workflow validation
- ✅ **Performance Tests**: No degradation from current implementation

### Standards Compliance
- ✅ **PowerShell Standards**: 100% compliance with community standards
- ✅ **Naming Conventions**: Proper verb-noun naming throughout
- ✅ **Error Handling**: Comprehensive error handling with correlation IDs
- ✅ **Troubleshooting**: Complete troubleshooting documentation

---

*This refactoring plan ensures the RestoreOperations.ps1 file adheres to PowerShell best practices while maintaining all existing functionality through a properly modularized architecture.*

**Status**: Ready for Implementation
**Priority**: High - Addresses Single Responsibility Principle violations
**Impact**: Improved maintainability, testability, and standards compliance
**Framework**: PowerShell Community Standards with Approved Verb-Noun Naming
