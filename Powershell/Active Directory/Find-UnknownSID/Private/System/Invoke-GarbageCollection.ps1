#Requires -Version 5.1

<#
.SYNOPSIS
    Garbage Collection Operations Module for Find-UnknownSID Enterprise Solution

.DESCRIPTION
    Provides focused garbage collection and memory cleanup functionality including:
    - Memory cleanup operations
    - Advanced garbage collection techniques
    - Large Object Heap compaction
    - Enterprise-grade correlation tracking

    This module follows the single-responsibility principle by focusing exclusively
    on garbage collection and memory cleanup operations.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For cleanup issues: .\Troubleshooting\Performance\Garbage-Collection.md
    - For memory pressure: .\Troubleshooting\Performance\Memory-Pressure.md
    - For performance: .\Troubleshooting\Performance\Performance-Tuning.md

.COMPONENT
    Find-UnknownSID Garbage Collection System

.FUNCTIONALITY
    - Memory cleanup operations
    - Advanced garbage collection techniques
    - Large Object Heap compaction
    - Memory pressure management
#>

function Invoke-Cleanup {
    <#
    .SYNOPSIS
        Performs memory cleanup with advanced garbage collection

    .DESCRIPTION
        Executes comprehensive memory cleanup using advanced .NET garbage
        collection techniques including memory pressure manipulation and
        Large Object Heap compaction for maximum memory recovery.

    .PARAMETER CorrelationId
        Correlation identifier for tracking cleanup operation

    .PARAMETER IncludeLOHCompaction
        Enables Large Object Heap compaction for maximum memory recovery

    .EXAMPLE
        PS> Invoke-Cleanup -CorrelationId $correlationId

        Performs standard memory cleanup

    .EXAMPLE
        PS> Invoke-Cleanup -CorrelationId $correlationId -IncludeLOHCompaction

        Performs cleanup with Large Object Heap compaction

    .OUTPUTS
        [PSCustomObject] Cleanup results with memory statistics

    .NOTES
        PERFORMANCE IMPACT:
        - High: Temporarily reduces performance during cleanup
        - Benefit: Significant memory recovery in large operations
        - Use Case: Emergency memory situations or batch processing

        WHATIF BEHAVIOR:
        - Cleanup operations ALWAYS execute regardless of -WhatIf
        - Only detailed logging and reporting operations respect -WhatIf
        - This ensures critical memory operations are not skipped during simulations
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('MemoryCleanupResult')]
    param(
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [switch]$IncludeLOHCompaction
    )

    begin {
        # Ensure correlation ID is not empty
        if (-not $CorrelationId.Trim()) {
            $CorrelationId = [System.Guid]::NewGuid().ToString()
        }

        # Memory management configuration constants
        $script:MemoryManagementConfig = @{
            MemoryPressureAmountMB = 50
            GCRetryAttempts = 3
            GCRetryDelayMilliseconds = 100
            LogComponent = 'MemoryManagement'
        }
    }

    process {
        try {
            # Memory cleanup operations always execute - critical for system stability
            # Only detailed logging respects ShouldProcess
            if ($PSCmdlet.ShouldProcess("Memory", "Perform cleanup")) {
                Write-StructuredLog "Starting memory cleanup operation..." -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            } else {
                Write-Verbose "WhatIf: Would perform memory cleanup"
                Write-StructuredLog "WhatIf simulation: memory cleanup would be performed" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }

            # ALWAYS perform memory cleanup - essential for system health regardless of WhatIf
            # Capture memory before cleanup
            $memoryBefore = Get-CurrentMemoryUsage

            if ($PSCmdlet.ShouldProcess("Memory", "Log cleanup progress")) {
                Write-StructuredLog "Memory before cleanup: $([Math]::Round($memoryBefore.WorkingSetMB, 2)) MB" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }

            # Apply memory pressure to encourage cleanup
            [System.GC]::AddMemoryPressure($script:MemoryManagementConfig.MemoryPressureAmountMB * 1MB)

            try {
                # Enable LOH compaction if requested
                if ($IncludeLOHCompaction) {
                    [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
                    if ($PSCmdlet.ShouldProcess("Memory", "Log LOH compaction")) {
                        Write-StructuredLog "Large Object Heap compaction enabled" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                    }
                }

                # Perform comprehensive garbage collection
                for ($attempt = 1; $attempt -le $script:MemoryManagementConfig.GCRetryAttempts; $attempt++) {
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()

                    if ($attempt -lt $script:MemoryManagementConfig.GCRetryAttempts) {
                        Start-Sleep -Milliseconds $script:MemoryManagementConfig.GCRetryDelayMilliseconds
                    }
                }

                if ($PSCmdlet.ShouldProcess("Memory", "Log cleanup completion")) {
                    Write-StructuredLog "Garbage collection completed ($($script:MemoryManagementConfig.GCRetryAttempts) cycles)" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                }
            }
            finally {
                # Remove memory pressure - always execute
                [System.GC]::RemoveMemoryPressure($script:MemoryManagementConfig.MemoryPressureAmountMB * 1MB)
            }

            # Capture memory after cleanup
            $memoryAfter = Get-CurrentMemoryUsage
            $memoryFreedMB = [Math]::Round($memoryBefore.WorkingSetMB - $memoryAfter.WorkingSetMB, 2)

            $cleanupResult = [PSCustomObject]@{
                PSTypeName = 'MemoryCleanupResult'
                CorrelationId = $CorrelationId
                Timestamp = Get-Date
                MemoryBeforeMB = [Math]::Round($memoryBefore.WorkingSetMB, 2)
                MemoryAfterMB = [Math]::Round($memoryAfter.WorkingSetMB, 2)
                MemoryFreedMB = $memoryFreedMB
                LOHCompactionUsed = $IncludeLOHCompaction.IsPresent
                GCCycles = $script:MemoryManagementConfig.GCRetryAttempts
                Success = $memoryFreedMB -gt 0
                WhatIfMode = -not $PSCmdlet.ShouldProcess("Memory", "Log results")
            }

            if ($PSCmdlet.ShouldProcess("Memory", "Log cleanup results")) {
                Write-StructuredLog "Memory after cleanup: $([Math]::Round($memoryAfter.WorkingSetMB, 2)) MB (Freed: $memoryFreedMB MB)" -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }

            return $cleanupResult
        }
        catch {
            Write-StructuredLog "Cleanup failed: $($_.Exception.Message)" -Level Error -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            Write-Error "Memory cleanup operation failed: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-StructuredLog "Memory cleanup completed" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
    }
}

# Functions are automatically available when dot-sourced
# Note: Export-ModuleMember is only valid in .psm1 module files
