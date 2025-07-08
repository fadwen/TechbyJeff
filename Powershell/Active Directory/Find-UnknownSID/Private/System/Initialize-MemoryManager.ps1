#Requires -Version 5.1

<#
.SYNOPSIS
    Memory Manager Instance Management Module for Find-UnknownSID Enterprise Solution

.DESCRIPTION
    Provides focused memory manager instance creation and configuration functionality including:
    - Memory manager instance initialization
    - Configuration validation and setup
    - Enterprise-grade correlation tracking
    - Configuration constants management

    This module follows the single-responsibility principle by focusing exclusively
    on memory manager instance creation and configuration operations.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For memory issues: .\Troubleshooting\Performance\Memory-Management.md
    - For configuration: .\Troubleshooting\Performance\Memory-Configuration.md
    - For initialization issues: .\Troubleshooting\Common\Initialization-Problems.md

.COMPONENT
    Find-UnknownSID Memory Manager Initialization System

.FUNCTIONALITY
    - Memory manager instance creation
    - Configuration validation and setup
    - Correlation tracking initialization
    - Memory management configuration constants
#>

# Memory management configuration constants
$script:MemoryManagementConfig = @{
    DefaultMemoryThresholdMB = 1024
    DefaultCheckInterval = 25
    CleanupThresholdRatio = 0.9
    EmergencyCleanupThresholdRatio = 0.95
    MemoryPressureAmountMB = 50
    GCRetryAttempts = 3
    GCRetryDelayMilliseconds = 100
    LogComponent = 'MemoryManagement'
}


function Initialize-MemoryManager {
    <#
    .SYNOPSIS
        Creates and initializes a new MemoryManager instance

    .DESCRIPTION
        Initializes a memory management system with specified thresholds
        and monitoring intervals. Provides enterprise-grade memory monitoring
        with correlation tracking for troubleshooting and performance analysis.

    .PARAMETER MaxMemoryMB
        Maximum memory threshold in megabytes before triggering cleanup

    .PARAMETER CheckInterval
        Number of operations between memory usage checks

    .PARAMETER CorrelationId
        Unique correlation identifier for tracking operations

    .EXAMPLE
        PS> Initialize-MemoryManager -MaxMemoryMB 2048 -CheckInterval 25

        Creates memory manager with 2GB threshold, checking every 25 operations

    .EXAMPLE
        PS> Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 50 -CorrelationId $correlationId

        Creates memory manager with custom correlation ID for tracking

    .OUTPUTS
        [MemoryManager] Configured memory management instance

    .NOTES
        BUSINESS VALUE:
        - Prevents memory exhaustion in large-scale environments
        - Enables predictable memory usage patterns
        - Provides enterprise-grade monitoring and logging
        - Supports correlation tracking for troubleshooting

        PERFORMANCE CONSIDERATIONS:
        - Lower thresholds: More frequent cleanup, better memory control
        - Higher thresholds: Less cleanup overhead, faster processing
        - Optimal range: 1024-4096 MB for most enterprise environments

        WHATIF BEHAVIOR:
        - Memory manager creation ALWAYS executes regardless of -WhatIf
        - Only logging and reporting operations respect -WhatIf
        - This ensures system stability is maintained during simulations
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('MemoryManager')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(256, 16384)]
        [int]$MaxMemoryMB,

        [Parameter(Mandatory)]
        [ValidateRange(5, 100)]
        [int]$CheckInterval,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Ensure correlation ID is not empty
        if (-not $CorrelationId.Trim()) {
            $CorrelationId = [System.Guid]::NewGuid().ToString()
        }
    }

    process {
        try {
            # Memory manager creation always executes - critical for system health
            # Only the reporting respects ShouldProcess
            if ($PSCmdlet.ShouldProcess("MemoryManager", "Initialize with threshold $MaxMemoryMB MB")) {
                Write-StructuredLog "Initializing memory manager with threshold $MaxMemoryMB MB" -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            } else {
                Write-Verbose "WhatIf: Would initialize memory manager with threshold $MaxMemoryMB MB"
            }

            # ALWAYS create memory manager - essential for system stability
            $memoryManager = [MemoryManager]::new($MaxMemoryMB, $CheckInterval, $CorrelationId)

            if ($PSCmdlet.ShouldProcess("MemoryManager", "Log initialization completion")) {
                Write-StructuredLog "Memory manager initialized successfully" -Level Information -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
                Write-StructuredLog "Configuration: Threshold=$MaxMemoryMB MB, CheckInterval=$CheckInterval operations" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            } else {
                Write-StructuredLog "Memory manager created for WhatIf simulation" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            }

            return $memoryManager
        }
        catch {
            Write-StructuredLog "Failed to initialize memory manager: $($_.Exception.Message)" -Level Error -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
            Write-Error "Memory manager initialization failed: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-StructuredLog "Memory manager initialization completed" -Level Debug -Component $script:MemoryManagementConfig.LogComponent -CorrelationId $CorrelationId
    }
}

# Functions are automatically available when dot-sourced
# Note: Export-ModuleMember is only valid in .psm1 module files
