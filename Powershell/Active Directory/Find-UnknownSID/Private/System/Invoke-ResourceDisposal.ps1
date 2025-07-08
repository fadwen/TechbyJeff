#Requires -Version 5.1

<#
.SYNOPSIS
    Resource Disposal and Cleanup Module for Find-UnknownSID Enterprise Solution

.DESCRIPTION
    Provides focused resource disposal and cleanup functionality including:
    - Comprehensive resource cleanup operations
    - IDisposable pattern implementation
    - Memory manager disposal
    - Enterprise-grade correlation tracking

    This module follows the single-responsibility principle by focusing exclusively
    on resource disposal and cleanup operations.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For disposal issues: .\Troubleshooting\Performance\Resource-Disposal.md
    - For cleanup problems: .\Troubleshooting\Performance\Resource-Cleanup.md
    - For performance: .\Troubleshooting\Performance\Performance-Tuning.md

.COMPONENT
    Find-UnknownSID Resource Disposal System

.FUNCTIONALITY
    - Comprehensive resource cleanup
    - IDisposable pattern implementation
    - Memory manager disposal
    - Final garbage collection
#>

function Invoke-ResourceCleanup {
    <#
    .SYNOPSIS
        Performs comprehensive resource cleanup and disposal

    .DESCRIPTION
        Executes enterprise-grade resource cleanup including object disposal,
        memory cleanup, and resource finalization following community
        best practices for PowerShell resource management.

    .PARAMETER MemoryManager
        MemoryManager instance to dispose

    .PARAMETER AdditionalResources
        Additional IDisposable resources to dispose

    .PARAMETER CorrelationId
        Correlation identifier for tracking cleanup operations

    .EXAMPLE
        PS> Invoke-ResourceCleanup -MemoryManager $memoryManager

        Disposes memory manager and performs cleanup

    .EXAMPLE
        PS> Invoke-ResourceCleanup -MemoryManager $memoryManager -AdditionalResources @($resource1, $resource2)

        Disposes multiple resources safely

    .NOTES
        ENTERPRISE COMPLIANCE:
        - Follows PowerShell community disposal patterns
        - Implements defense-in-depth cleanup strategy
        - Provides comprehensive error handling
        - Supports correlation tracking for audit trails

        WHATIF BEHAVIOR:
        - Resource disposal operations ALWAYS execute regardless of -WhatIf
        - Only detailed logging operations respect -WhatIf
        - This ensures critical cleanup is not skipped during simulations
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [AllowNull()]
        [MemoryManager]$MemoryManager,

        [Parameter()]
        [AllowNull()]
        [System.IDisposable[]]$AdditionalResources,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Ensure correlation ID is not empty
        if (-not $CorrelationId.Trim()) {
            $CorrelationId = [System.Guid]::NewGuid().ToString()
        }

        # Memory management configuration constants
        $script:MemoryManagementConfig = @{
            LogComponent = 'MemoryManagement'
        }
    }

    process {
        try {
            # Resource disposal operations always execute - critical for system stability
            # Only detailed logging respects ShouldProcess
            if ($PSCmdlet.ShouldProcess("Resources", "Dispose and cleanup")) {
                Write-StructuredLog "Starting resource cleanup and disposal..." -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            } else {
                Write-Verbose "WhatIf: Would dispose and cleanup resources"
                Write-StructuredLog "WhatIf simulation: resource disposal would be performed" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }

            # ALWAYS dispose resources - essential for system stability regardless of WhatIf
            # Dispose additional resources first
            if ($AdditionalResources) {
                foreach ($resource in $AdditionalResources) {
                    if ($resource -and $resource -is [System.IDisposable]) {
                        try {
                            $resource.Dispose()
                            if ($PSCmdlet.ShouldProcess("Resources", "Log additional resource disposal")) {
                                Write-StructuredLog "Additional resource disposed successfully" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                            }
                        }
                        catch {
                            Write-StructuredLog "Failed to dispose additional resource: $($_.Exception.Message)" -Level Warning -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                        }
                    }
                }
            }

            # Dispose memory manager
            if ($MemoryManager -and (-not $MemoryManager.Disposed)) {
                try {
                    $MemoryManager.Dispose()
                    if ($PSCmdlet.ShouldProcess("Resources", "Log memory manager disposal")) {
                        Write-StructuredLog "Memory manager disposed successfully" -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                    }
                }
                catch {
                    Write-StructuredLog "Failed to dispose memory manager: $($_.Exception.Message)" -Level Warning -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                }
            }

            # Perform final memory cleanup - always execute
            try {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
                if ($PSCmdlet.ShouldProcess("Resources", "Log final garbage collection")) {
                    Write-StructuredLog "Final garbage collection completed" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                }
            }
            catch {
                Write-StructuredLog "Final garbage collection failed: $($_.Exception.Message)" -Level Warning -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }
        }
        catch {
            Write-StructuredLog "Resource cleanup operation failed: $($_.Exception.Message)" -Level Error -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            Write-Error "Resource cleanup failed: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-StructuredLog "Resource cleanup completed" -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
    }
}

# Functions are automatically available when dot-sourced
# Note: Export-ModuleMember is only valid in .psm1 module files
