# ADOperations.ps1 Refactoring Implementation Guide

## Overview

This document provides step-by-step implementation guidance for refactoring `ADOperations.ps1` to comply with PowerShell community standards and the "do one thing well" principle.

## Current Problems

### Problem 1: `Invoke-ADOperationWithRetry` - Multiple Responsibilities
```powershell
# ❌ Current: 95 lines doing multiple things
function Invoke-ADOperationWithRetry {
    # 1. Security logging (25+ lines)
    # 2. Retry logic (30+ lines)
    # 3. Error classification (10+ lines)
    # 4. Operation execution (mixed throughout)
    # 5. Result processing (mixed throughout)
}
```

### Problem 2: `Get-ADObjectsParallel` - Misleading Name and Mixed Concerns
```powershell
# ❌ Current: Claims parallelism but is sequential
function Get-ADObjectsParallel {
    # 1. AD object retrieval
    # 2. Result aggregation
    # 3. Security logging
    # 4. Error handling per search base
    # 5. Manual collection building (performance anti-pattern)
}
```

## Refactoring Solution

### Phase 1: Extract Core Components

#### Step 1: Create Pure Retry Mechanism

Create `c:\temp\Find-UnknownSID\Private\Retry\Invoke-OperationWithRetry.ps1`:

```powershell
function Invoke-OperationWithRetry {
    <#
    .SYNOPSIS
        Executes a script block with configurable retry logic for transient failures

    .DESCRIPTION
        Provides a reusable retry mechanism for any operation that may experience
        transient failures. Uses exponential backoff with jitter for optimal retry timing.

    .PARAMETER ScriptBlock
        The operation to execute with retry logic

    .PARAMETER MaxRetries
        Maximum number of retry attempts (default: 3)

    .PARAMETER RetryableErrorPattern
        Regex pattern to identify retryable errors

    .PARAMETER OperationName
        Descriptive name for logging purposes

    .EXAMPLE
        PS> Invoke-OperationWithRetry -ScriptBlock { Get-ADUser 'testuser' } -OperationName 'Get User'

        DESCRIPTION: Executes AD user lookup with automatic retry on transient failures
        OUTPUT: AD user object or throws on permanent failure
        USE CASE: Handling intermittent AD connectivity issues

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For retry configuration: .\Troubleshooting\Performance\Retry-Configuration.md
        - For error patterns: .\Troubleshooting\Common\Error-Classification.md
    #>

    [CmdletBinding()]
    [OutputType('OperationResult')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [string]$RetryableErrorPattern = 'timeout|network|connection|busy|unavailable|server not operational|replication|domain controller',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OperationName = 'Operation',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting retry operation: $OperationName (Max Retries: $MaxRetries)"
    }

    process {
        $attempt = 0
        $lastError = $null

        do {
            $attempt++
            try {
                Write-Verbose "Executing $OperationName (attempt $attempt/$MaxRetries)"
                $result = & $ScriptBlock

                Write-Verbose "Operation '$OperationName' succeeded on attempt $attempt"
                return $result
            }
            catch {
                $lastError = $_
                $isRetryable = $_.Exception.Message -match $RetryableErrorPattern

                if (-not $isRetryable -or $attempt -ge $MaxRetries) {
                    Write-Verbose "Operation '$OperationName' failed permanently after $attempt attempts"
                    throw $lastError
                }

                $waitTime = [Math]::Min([Math]::Pow(2, $attempt - 1) + (Get-Random -Maximum 2), 30)
                Write-Verbose "Operation '$OperationName' failed (attempt $attempt/$MaxRetries), retrying in $waitTime seconds"
                Start-Sleep -Seconds $waitTime
            }
        } while ($attempt -lt $MaxRetries)

        throw $lastError
    }
}
```

#### Step 2: Create Security Logging Component

Create `c:\temp\Find-UnknownSID\Private\Logging\Write-ADOperationSecurityLog.ps1`:

```powershell
function Write-ADOperationSecurityLog {
    <#
    .SYNOPSIS
        Writes security audit logs for Active Directory operations

    .DESCRIPTION
        Provides standardized security logging for AD operations including
        object access attempts, successes, and failures with proper audit trails.

    .PARAMETER OperationName
        Name of the AD operation being performed

    .PARAMETER Outcome
        Result of the operation (Attempt, Success, Failure)

    .PARAMETER SecurityContext
        Additional security context for audit trail

    .PARAMETER CorrelationId
        Unique identifier for tracking related operations

    .EXAMPLE
        PS> Write-ADOperationSecurityLog -OperationName 'Get-ADUser' -Outcome 'Success'

        DESCRIPTION: Logs successful AD user retrieval operation
        OUTPUT: Security log entry with audit trail
        USE CASE: Compliance and security monitoring

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For logging configuration: .\Troubleshooting\Security\Audit-Configuration.md
        - For compliance requirements: .\Troubleshooting\Security\Compliance-Guide.md
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationName,

        [Parameter(Mandatory)]
        [ValidateSet('Attempt', 'Success', 'Failure')]
        [string]$Outcome,

        [Parameter()]
        [hashtable]$SecurityContext = @{},

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        # Build standardized security context
        $auditContext = @{
            OperationName = $OperationName
            Outcome = $Outcome
            Timestamp = Get-Date
            UserContext = "$env:USERNAME@$env:COMPUTERNAME"
            CorrelationId = $CorrelationId
            Component = 'ADOperations'
            SecurityEventType = 'ObjectAccess'
        }

        # Merge additional context
        foreach ($key in $SecurityContext.Keys) {
            $auditContext[$key] = $SecurityContext[$key]
        }

        # Write security log based on outcome
        switch ($Outcome) {
            'Attempt' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Attempting Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
            'Success' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Successfully completed Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
            'Failure' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Failed Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
        }
    }
}
```

#### Step 3: Create Composed AD Operation Function

Create `c:\temp\Find-UnknownSID\Private\Operations\Invoke-ADOperationWithRetry.ps1`:

```powershell
function Invoke-ADOperationWithRetry {
    <#
    .SYNOPSIS
        Executes Active Directory operations with retry logic and security logging

    .DESCRIPTION
        Orchestrates AD operations by combining retry mechanisms with proper security
        audit logging. Provides enterprise-grade reliability for AD interactions.

    .PARAMETER ScriptBlock
        The AD operation to execute

    .PARAMETER MaxRetries
        Maximum retry attempts for transient failures

    .PARAMETER OperationName
        Descriptive name for the operation

    .PARAMETER ObjectContext
        Additional context about the AD object being accessed

    .EXAMPLE
        PS> Invoke-ADOperationWithRetry -ScriptBlock { Get-ADUser 'testuser' } -OperationName 'Get User'

        DESCRIPTION: Executes AD user lookup with retry and audit logging
        OUTPUT: AD user object with full audit trail
        USE CASE: Production AD operations requiring reliability and auditing

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For operation failures: .\Troubleshooting\Common\AD-Operation-Issues.md
        - For retry configuration: .\Troubleshooting\Performance\Retry-Tuning.md
    #>

    [CmdletBinding()]
    [OutputType('ADOperationResult')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OperationName = 'AD Operation',

        [Parameter()]
        [string]$ObjectContext = 'Unknown',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting AD operation with retry: $OperationName"

        # Build security context
        $securityContext = @{
            ObjectContext = $ObjectContext
            MaxRetries = $MaxRetries
            ADAccessType = 'Sensitive'
            OperationType = 'SingleOperation'
        }
    }

    process {
        # Log operation attempt
        Write-ADOperationSecurityLog -OperationName $OperationName -Outcome 'Attempt' -SecurityContext $securityContext -CorrelationId $CorrelationId

        try {
            # Execute with retry logic
            $result = Invoke-OperationWithRetry -ScriptBlock $ScriptBlock -MaxRetries $MaxRetries -OperationName $OperationName -CorrelationId $CorrelationId

            # Log successful operation
            $successContext = $securityContext.Clone()
            $successContext['ResultType'] = if ($result) { $result.GetType().Name } else { 'NoResult' }

            Write-ADOperationSecurityLog -OperationName $OperationName -Outcome 'Success' -SecurityContext $successContext -CorrelationId $CorrelationId

            return $result
        }
        catch {
            # Log failed operation
            $failureContext = $securityContext.Clone()
            $failureContext['ErrorMessage'] = $_.Exception.Message
            $failureContext['FailureCategory'] = 'OperationFailed'

            Write-ADOperationSecurityLog -OperationName $OperationName -Outcome 'Failure' -SecurityContext $failureContext -CorrelationId $CorrelationId

            throw
        }
    }
}
```

#### Step 4: Create Core AD Object Retrieval Function

Create `c:\temp\Find-UnknownSID\Private\Operations\Get-ADObjectFromSearchBase.ps1`:

```powershell
function Get-ADObjectFromSearchBase {
    <#
    .SYNOPSIS
        Retrieves Active Directory objects from a single search base

    .DESCRIPTION
        Performs AD object retrieval from a specified search base with proper
        error handling and security descriptor inclusion. Designed for pipeline efficiency.

    .PARAMETER SearchBase
        The distinguished name of the search base

    .PARAMETER IncludeInherited
        Whether to include inherited permissions in security descriptors

    .PARAMETER Properties
        Additional properties to retrieve (nTSecurityDescriptor always included)

    .EXAMPLE
        PS> Get-ADObjectFromSearchBase -SearchBase "OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Retrieves all AD objects from the Users OU
        OUTPUT: Collection of AD objects with security descriptors
        USE CASE: Scanning specific organizational units for security analysis

    .EXAMPLE
        PS> @("OU=Users,DC=contoso,DC=com", "OU=Groups,DC=contoso,DC=com") | Get-ADObjectFromSearchBase

        DESCRIPTION: Pipeline processing of multiple search bases
        OUTPUT: Combined collection from all search bases
        USE CASE: Bulk processing of multiple organizational units

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For search base issues: .\Troubleshooting\Common\SearchBase-Problems.md
        - For permission issues: .\Troubleshooting\Security\Permission-Errors.md
    #>

    [CmdletBinding()]
    [OutputType('Microsoft.ActiveDirectory.Management.ADObject')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string[]]$Properties = @('nTSecurityDescriptor'),

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-Verbose "Retrieving AD objects from search base: $SearchBase"

            # Ensure nTSecurityDescriptor is always included
            $allProperties = @($Properties) + @('nTSecurityDescriptor') | Sort-Object -Unique

            # Execute AD query
            $objects = Get-ADObject -SearchBase $SearchBase -Filter * -Properties $allProperties -ErrorAction Stop

            # Output to pipeline for efficiency
            if ($objects) {
                foreach ($obj in @($objects)) {
                    Write-Output $obj
                }
            }

            Write-Verbose "Retrieved $(@($objects).Count) objects from search base: $SearchBase"
        }
        catch {
            Write-Warning "Failed to retrieve objects from search base '$SearchBase': $($_.Exception.Message)"

            # Don't throw - let pipeline continue with other search bases
            # Log error for troubleshooting
            Write-Verbose "Search base error details: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        }
    }
}
```

#### Step 5: Create Sequential Processing Function

Create `c:\temp\Find-UnknownSID\Private\Operations\Get-ADObjectsSequential.ps1`:

```powershell
function Get-ADObjectsSequential {
    <#
    .SYNOPSIS
        Retrieves Active Directory objects from multiple search bases sequentially

    .DESCRIPTION
        Processes multiple AD search bases in sequence with comprehensive logging
        and error handling. Optimized for reliability over speed.

    .PARAMETER SearchBase
        Array of distinguished names to search

    .PARAMETER IncludeInherited
        Whether to include inherited permissions in security descriptors

    .EXAMPLE
        PS> Get-ADObjectsSequential -SearchBase @("OU=Users,DC=contoso,DC=com", "OU=Groups,DC=contoso,DC=com")

        DESCRIPTION: Sequentially processes multiple organizational units
        OUTPUT: Combined collection of AD objects from all search bases
        USE CASE: Reliable bulk processing when parallel processing isn't required

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For performance optimization: .\Troubleshooting\Performance\Sequential-Optimization.md
        - For bulk operation issues: .\Troubleshooting\Common\Bulk-Processing.md
    #>

    [CmdletBinding()]
    [OutputType('Microsoft.ActiveDirectory.Management.ADObject')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting sequential AD object retrieval from $($SearchBase.Count) search bases"

        # Log bulk operation start
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Attempt' -SecurityContext @{
            SearchBaseCount = $SearchBase.Count
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
        } -CorrelationId $CorrelationId

        $totalObjects = 0
        $successfulBases = 0
        $failedBases = 0
    }

    process {
        # Use pipeline for efficiency - no manual collection building
        $results = $SearchBase | Get-ADObjectFromSearchBase -IncludeInherited:$IncludeInherited

        # Count results for reporting
        $resultArray = @($results)
        $totalObjects = $resultArray.Count

        # Calculate success/failure rates
        $successfulBases = ($SearchBase | ForEach-Object {
            try {
                Get-ADObject -SearchBase $_ -Filter * -Properties nTSecurityDescriptor -ErrorAction Stop | Out-Null
                return $true
            }
            catch {
                return $false
            }
        } | Where-Object { $_ }).Count

        $failedBases = $SearchBase.Count - $successfulBases

        Write-Verbose "Sequential processing completed: $totalObjects objects from $successfulBases/$($SearchBase.Count) search bases"

        # Output results to pipeline
        $resultArray | Write-Output
    }

    end {
        # Log bulk operation completion
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Success' -SecurityContext @{
            SearchBaseCount = $SearchBase.Count
            SuccessfulBases = $successfulBases
            FailedBases = $failedBases
            ObjectsRetrieved = $totalObjects
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
            ResultSummary = "Retrieved $totalObjects objects from $successfulBases/$($SearchBase.Count) search bases"
        } -CorrelationId $CorrelationId
    }
}
```

### Phase 2: Update Main ADOperations.ps1

Replace the existing `ADOperations.ps1` content:

```powershell
#Requires -Module ActiveDirectory
#Requires -Version 5.1

<#
.SYNOPSIS
    Modular Active Directory operations with enterprise standards compliance

.DESCRIPTION
    This module provides decomposed AD operations following PowerShell community
    best practices. Each function has a single responsibility and is independently testable.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    Architecture: Follows "do one thing well" principle with separated concerns
    Components:
    - Retry logic: Invoke-OperationWithRetry
    - Security logging: Write-ADOperationSecurityLog
    - AD operations: Invoke-ADOperationWithRetry
    - Object retrieval: Get-ADObjectFromSearchBase, Get-ADObjectsSequential

    TROUBLESHOOTING:
    - For module issues: .\Troubleshooting\Common\ADOperations-Module.md
    - For component interaction: .\Troubleshooting\Integration\Component-Issues.md
#>

# Import required components (dot-sourcing for performance)
. $PSScriptRoot\Retry\Invoke-OperationWithRetry.ps1
. $PSScriptRoot\Logging\Write-ADOperationSecurityLog.ps1
. $PSScriptRoot\Operations\Invoke-ADOperationWithRetry.ps1
. $PSScriptRoot\Operations\Get-ADObjectFromSearchBase.ps1
. $PSScriptRoot\Operations\Get-ADObjectsSequential.ps1

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-ADOperationWithRetry',
    'Get-ADObjectsSequential',
    'Get-ADObjectFromSearchBase'
)
```

## Implementation Steps

### Step 1: Create Directory Structure
```powershell
# Create new modular structure
New-Item -Path "c:\temp\Find-UnknownSID\Private\Retry" -ItemType Directory -Force
New-Item -Path "c:\temp\Find-UnknownSID\Private\Logging" -ItemType Directory -Force
New-Item -Path "c:\temp\Find-UnknownSID\Private\Operations" -ItemType Directory -Force
```

### Step 2: Implement Components
Create each component file as specified above.

### Step 3: Update Tests
Create comprehensive unit tests for each component:

```powershell
# Example test structure
c:\temp\Find-UnknownSID\Tests\Unit\
├── Retry\
│   └── Invoke-OperationWithRetry.Tests.ps1
├── Logging\
│   └── Write-ADOperationSecurityLog.Tests.ps1
└── Operations\
    ├── Invoke-ADOperationWithRetry.Tests.ps1
    ├── Get-ADObjectFromSearchBase.Tests.ps1
    └── Get-ADObjectsSequential.Tests.ps1
```

### Step 4: Update Calling Code
Update any code that calls the old functions to use the new modular approach.

## Benefits After Refactoring

### ✅ PowerShell Standards Compliance
- **Single Responsibility**: Each function does one thing well
- **Testability**: Independent functions are easily unit tested
- **Reusability**: Retry logic can be used for any operation
- **Performance**: Pipeline-based processing eliminates manual collection building

### ✅ Enterprise Benefits
- **Maintainability**: Clear separation of concerns
- **Debugging**: Isolated components are easier to troubleshoot
- **Extensibility**: New functionality can be added without modifying existing components
- **Documentation**: Each component has focused, accurate documentation

### ✅ Security and Compliance
- **Audit Trail**: Dedicated security logging component
- **Consistency**: Standardized logging across all AD operations
- **Traceability**: Correlation IDs track operations across components

## Migration Strategy

### Option 1: Gradual Migration
1. Create new modular components
2. Update ADOperations.ps1 to use new components internally
3. Keep existing function signatures for backward compatibility
4. Gradually update calling code

### Option 2: Clean Break
1. Create new modular structure
2. Rename old functions (Add `-Legacy` suffix)
3. Update all calling code simultaneously
4. Remove legacy functions after validation

**Recommendation**: Use **Option 1** for lower risk and easier rollback.

---

**Document Version**: 1.0
**Implementation Date**: 2025-01-27
**Status**: Ready for Implementation
**Review Required**: Yes - before Phase 1 execution
