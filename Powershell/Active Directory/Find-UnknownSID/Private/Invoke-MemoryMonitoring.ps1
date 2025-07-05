#Requires -Version 5.1

<#
.SYNOPSIS
    Memory Monitoring and Threshold Management Module for Find-UnknownSID Enterprise Solution

.DESCRIPTION
    Provides focused memory monitoring and threshold checking functionality including:
    - Memory usage monitoring and checks
    - Threshold testing and evaluation
    - Automated monitoring triggers
    - Enterprise-grade correlation tracking

    This module follows the single-responsibility principle by focusing exclusively
    on memory monitoring and threshold management operations.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For monitoring issues: .\Troubleshooting\Performance\Memory-Monitoring.md
    - For threshold problems: .\Troubleshooting\Performance\Memory-Thresholds.md
    - For performance: .\Troubleshooting\Performance\Performance-Tuning.md

.COMPONENT
    Find-UnknownSID Memory Monitoring System

.FUNCTIONALITY
    - Memory usage monitoring
    - Threshold testing and evaluation
    - Automated monitoring triggers
    - Memory pressure detection
#>

function Invoke-MemoryCheck {
    <#
    .SYNOPSIS
        Performs memory usage check and triggers cleanup if needed

    .DESCRIPTION
        Checks current memory usage against configured thresholds and
        triggers appropriate cleanup actions. Provides detailed logging
        and correlation tracking for enterprise troubleshooting.

    .PARAMETER MemoryManager
        MemoryManager instance to perform check on

    .PARAMETER Force
        Forces memory check regardless of interval counter

    .EXAMPLE
        PS> Invoke-MemoryCheck -MemoryManager $memoryManager

        Performs standard memory check based on configured interval

    .EXAMPLE
        PS> Invoke-MemoryCheck -MemoryManager $memoryManager -Force

        Forces immediate memory check and cleanup if needed

    .NOTES
        BUSINESS CONTEXT:
        Critical for maintaining system stability during long-running
        operations in enterprise environments with large datasets.

        PERFORMANCE IMPACT:
        - Minimal overhead during normal operations
        - Automatic cleanup prevents memory exhaustion
        - Detailed logging supports troubleshooting

        WHATIF BEHAVIOR:
        - Memory checking and cleanup operations ALWAYS execute regardless of -WhatIf
        - Only detailed logging operations respect -WhatIf
        - This ensures system health is maintained during simulations
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [MemoryManager]$MemoryManager,

        [Parameter()]
        [switch]$Force
    )

    process {
        try {
            # Memory checks always execute - critical for system stability
            # Only logging respects ShouldProcess
            if ($PSCmdlet.ShouldProcess("Memory", "Check usage and cleanup if needed")) {
                Write-StructuredLog "Performing memory check..." -Level Debug -Component 'MemoryManagement' -CorrelationId $MemoryManager.CorrelationId
            } else {
                Write-Verbose "WhatIf: Would check memory usage and cleanup if needed"
            }

            # ALWAYS perform memory operations - essential for system health
            if ($Force) {
                # Reset counter to force check
                $MemoryManager.CheckCounter = $MemoryManager.CheckInterval
            }

            $MemoryManager.CheckMemoryUsage()
        }
        catch {
            Write-StructuredLog "Memory check operation failed: $($_.Exception.Message)" -Level Warning -Component 'MemoryManagement' -CorrelationId $MemoryManager.CorrelationId
        }
    }
}


function Test-MemoryThreshold {
    <#
    .SYNOPSIS
        Tests if current memory usage exceeds specified threshold

    .DESCRIPTION
        Evaluates current memory usage against threshold values and
        returns detailed analysis for automated decision making in
        enterprise memory management scenarios.

    .PARAMETER ThresholdMB
        Memory threshold in megabytes to test against

    .PARAMETER ThresholdType
        Type of threshold test (Warning, Critical, Emergency)

    .EXAMPLE
        PS> Test-MemoryThreshold -ThresholdMB 1024

        Tests if current memory exceeds 1024 MB

    .EXAMPLE
        PS> Test-MemoryThreshold -ThresholdMB 2048 -ThresholdType Critical

        Tests critical threshold with enhanced analysis

    .OUTPUTS
        [PSCustomObject] Threshold test results with recommendations

    .NOTES
        AUTOMATION SUPPORT:
        Enables automated memory management decisions
        based on enterprise threshold policies.
    #>

    [CmdletBinding()]
    [OutputType('MemoryThresholdResult')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(128, 32768)]
        [int]$ThresholdMB,

        [Parameter()]
        [ValidateSet('Warning', 'Critical', 'Emergency')]
        [string]$ThresholdType = 'Warning'
    )

    try {
        $currentUsage = Get-CurrentMemoryUsage
        $exceeded = $currentUsage.WorkingSetMB -gt $ThresholdMB
        $utilizationPercent = [Math]::Round(($currentUsage.WorkingSetMB / $ThresholdMB) * 100, 1)

        $result = [PSCustomObject]@{
            PSTypeName = 'MemoryThresholdResult'
            Timestamp = Get-Date
            ThresholdMB = $ThresholdMB
            ThresholdType = $ThresholdType
            CurrentMemoryMB = $currentUsage.WorkingSetMB
            ThresholdExceeded = $exceeded
            UtilizationPercent = $utilizationPercent
            Severity = if ($exceeded) {
                switch ($ThresholdType) {
                    'Warning' { 'Medium' }
                    'Critical' { 'High' }
                    'Emergency' { 'Critical' }
                }
            } else { 'Low' }
            RecommendedAction = if ($exceeded) {
                switch ($ThresholdType) {
                    'Warning' { 'Monitor and consider cleanup' }
                    'Critical' { 'Immediate garbage collection recommended' }
                    'Emergency' { 'Aggressive cleanup required immediately' }
                }
            } else { 'No action required' }
        }

        return $result
    }
    catch {
        Write-Error "Memory threshold test failed: $($_.Exception.Message)" -ErrorAction Stop
    }
}

# Functions are automatically available when dot-sourced
# Note: Export-ModuleMember is only valid in .psm1 module files
