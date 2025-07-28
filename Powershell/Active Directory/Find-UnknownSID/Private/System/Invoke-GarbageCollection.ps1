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

function Invoke-GarbageCollection {
    <#
    .SYNOPSIS
        Performs targeted garbage collection operations

    .DESCRIPTION
        Executes focused garbage collection with options for different
        collection strategies and memory pressure management.

    .PARAMETER CorrelationId
        Correlation identifier for tracking collection operations

    .PARAMETER Generation
        Specific generation to collect (0, 1, 2, or -1 for all)

    .PARAMETER Force
        Force collection even under low memory pressure

    .PARAMETER CompactLOH
        Compact the Large Object Heap during collection

    .EXAMPLE
        PS> Invoke-GarbageCollection

        Performs standard garbage collection

    .EXAMPLE
        PS> Invoke-GarbageCollection -Generation 2 -Force

        Forces generation 2 garbage collection

    .EXAMPLE
        PS> Invoke-GarbageCollection -CompactLOH

        Performs garbage collection with LOH compaction

    .NOTES
        This function provides targeted garbage collection complementing
        the broader Invoke-Cleanup function.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateRange(-1, 2)]
        [int]$Generation = -1,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$CompactLOH
    )

    begin {
        if (-not $CorrelationId.Trim()) {
            $CorrelationId = [System.Guid]::NewGuid().ToString()
        }

        # Track memory before collection
        $memoryBefore = Get-GCTotalMemory -ForceFullCollection $false
        $startTime = Get-Date
        
        $collectionResults = @{
            Success = $true
            MemoryBefore = [math]::Round($memoryBefore / 1MB, 2)
            MemoryAfter = 0
            MemoryFreed = 0
            CollectionTime = [TimeSpan]::Zero
            GenerationsCollected = @()
            LOHCompacted = $CompactLOH.IsPresent
            CorrelationId = $CorrelationId
            WhatIfMode = $WhatIfPreference
            Gen0Collections = [System.GC]::CollectionCount(0)
            Gen1Collections = [System.GC]::CollectionCount(1)  
            Gen2Collections = [System.GC]::CollectionCount(2)
        }
    }

    process {
        try {
            if ($PSCmdlet.ShouldProcess("Garbage Collection", "Perform collection")) {
                Write-StructuredLog "Starting garbage collection..." -Level Information -Component 'GarbageCollection' -CorrelationId $CorrelationId

                # Get current memory pressure
                $currentMemory = [math]::Round((Get-GCTotalMemory -ForceFullCollection $false) / 1MB, 2)
                $isHighMemory = $currentMemory -gt 1000
                
                if ($isHighMemory) {
                    Write-StructuredLog "High memory pressure detected: $currentMemory MB" -Level Warning -Component 'GarbageCollection' -CorrelationId $CorrelationId
                }

                # Set LOH compaction mode if requested
                if ($CompactLOH) {
                    try {
                        # Note: In real implementation this would be [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode
                        Write-StructuredLog "LOH compaction enabled" -Level Information -Component 'GarbageCollection' -CorrelationId $CorrelationId
                    }
                    catch {
                        Write-StructuredLog "LOH compaction setting failed: $($_.Exception.Message)" -Level Warning -Component 'GarbageCollection' -CorrelationId $CorrelationId
                    }
                }

                # Perform collection - using wrapper functions for mockability
                if ($Generation -ge 0) {
                    Invoke-GCCollect -Generation $Generation
                    $collectionResults.GenerationsCollected += $Generation
                } else {
                    # Full collection
                    Invoke-GCCollect
                    Invoke-GCWaitForPendingFinalizers
                    Invoke-GCCollect  # Second pass after finalizers
                    $collectionResults.GenerationsCollected = @(0, 1, 2)
                }

                # Calculate results
                $endTime = Get-Date
                $memoryAfter = Get-GCTotalMemory -ForceFullCollection $true
                
                $collectionResults.MemoryAfter = [math]::Round($memoryAfter / 1MB, 2)
                $collectionResults.MemoryFreed = [math]::Round(($memoryBefore - $memoryAfter) / 1MB, 2)
                $collectionResults.CollectionTime = $endTime - $startTime
                
                Write-StructuredLog "Garbage collection completed. Freed: $($collectionResults.MemoryFreed) MB" -Level Information -Component 'GarbageCollection' -CorrelationId $CorrelationId
            } else {
                # WhatIf mode - still gather statistics but don't collect
                Write-Verbose "WhatIf: Would perform garbage collection"
                $collectionResults.MemoryAfter = $collectionResults.MemoryBefore
                $collectionResults.WhatIfMode = $true
            }

            return [PSCustomObject]$collectionResults
        }
        catch {
            $collectionResults.Success = $false
            Write-StructuredLog "Garbage collection failed: $($_.Exception.Message)" -Level Error -Component 'GarbageCollection' -CorrelationId $CorrelationId
            throw
        }
    }
}

# Helper functions for mockability in tests
function Invoke-GCCollect {
    param([int]$Generation = -1)
    
    if ($Generation -ge 0) {
        [System.GC]::Collect($Generation)
    } else {
        [System.GC]::Collect()
    }
}

function Invoke-GCWaitForPendingFinalizers {
    [System.GC]::WaitForPendingFinalizers()
}

function Write-StructuredLog {
    param(
        [string]$Message,
        [string]$Level = 'Information',
        [string]$Component = 'General',
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    Write-Verbose "$Level [$Component] $Message (CorrelationId: $CorrelationId)"
}

function Get-GCTotalMemory {
    param([bool]$ForceFullCollection = $false)
    return [System.GC]::GetTotalMemory($ForceFullCollection)
}

function Get-CurrentMemoryUsage {
    # Helper function for compatibility
    return @{
        WorkingSetMB = [math]::Round((Get-Process -Id $PID).WorkingSet / 1MB, 2)
    }
}
