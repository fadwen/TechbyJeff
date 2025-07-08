#Requires -Version 5.1

<#
.SYNOPSIS
    Memory Statistics and Reporting Module for Find-UnknownSID Enterprise Solution

.DESCRIPTION
    Provides focused memory statistics collection and reporting functionality including:
    - Current memory usage collection
    - Detailed memory usage reporting with performance recommendations
    - Memory statistics analysis and trend identification
    - Enterprise-grade correlation tracking

    This module follows the single-responsibility principle by focusing exclusively
    on memory statistics and reporting operations.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For memory issues: .\Troubleshooting\Performance\Memory-Management.md
    - For performance: .\Troubleshooting\Performance\Performance-Tuning.md
    - For reporting issues: .\Troubleshooting\Performance\Memory-Statistics.md

.COMPONENT
    Find-UnknownSID Memory Statistics System

.FUNCTIONALITY
    - Memory usage statistics collection
    - Comprehensive memory reporting
    - Performance recommendations
    - Memory trend analysis
#>

function Get-CurrentMemoryUsage {
    <#
    .SYNOPSIS
        Retrieves current memory usage statistics

    .DESCRIPTION
        Provides comprehensive memory usage information including
        working set, private memory, virtual memory, and garbage
        collection statistics for performance monitoring.

    .EXAMPLE
        PS> Get-CurrentMemoryUsage

        Returns current memory usage statistics

    .OUTPUTS
        [PSCustomObject] Memory usage statistics

    .NOTES
        MONITORING PURPOSE:
        Essential for memory baseline establishment and
        performance trending in enterprise environments.
    #>

    [CmdletBinding()]
    [OutputType('MemoryUsageStatistics')]
    param()

    try {
        $process = Get-Process -Id $PID -ErrorAction Stop

        $memoryStats = [PSCustomObject]@{
            PSTypeName = 'MemoryUsageStatistics'
            Timestamp = Get-Date
            ProcessId = $PID
            WorkingSetMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
            PrivateMemoryMB = [Math]::Round($process.PrivateMemorySize64 / 1MB, 2)
            VirtualMemoryMB = [Math]::Round($process.VirtualMemorySize64 / 1MB, 2)
            GCTotalMemoryMB = [Math]::Round([System.GC]::GetTotalMemory($false) / 1MB, 2)
            Gen0Collections = [System.GC]::CollectionCount(0)
            Gen1Collections = [System.GC]::CollectionCount(1)
            Gen2Collections = [System.GC]::CollectionCount(2)
        }

        return $memoryStats
    }
    catch {
        Write-Warning "Failed to retrieve memory usage: $($_.Exception.Message)"
        return $null
    }
}


function Get-MemoryUsageReport {
    <#
    .SYNOPSIS
        Generates detailed memory usage report

    .DESCRIPTION
        Creates comprehensive memory usage report including current usage,
        peak usage tracking, garbage collection statistics, and performance
        recommendations for enterprise memory management.

    .PARAMETER MemoryManager
        MemoryManager instance to generate report for

    .PARAMETER IncludeRecommendations
        Include performance recommendations in report

    .EXAMPLE
        PS> Get-MemoryUsageReport -MemoryManager $memoryManager

        Generates basic memory usage report

    .EXAMPLE
        PS> Get-MemoryUsageReport -MemoryManager $memoryManager -IncludeRecommendations

        Generates detailed report with performance recommendations

    .OUTPUTS
        [PSCustomObject] Comprehensive memory usage report

    .NOTES
        ENTERPRISE VALUE:
        - Performance baseline establishment
        - Capacity planning support
        - Troubleshooting documentation
        - Compliance reporting
    #>

    [CmdletBinding()]
    [OutputType('MemoryUsageReport')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [MemoryManager]$MemoryManager,

        [Parameter()]
        [switch]$IncludeRecommendations
    )

    try {
        $currentUsage = Get-CurrentMemoryUsage
        $peakUsage = $MemoryManager.GetPeakMemoryUsage()

        $report = [PSCustomObject]@{
            PSTypeName = 'MemoryUsageReport'
            CorrelationId = $MemoryManager.CorrelationId
            GeneratedAt = Get-Date
            Configuration = @{
                MaxMemoryThresholdMB = $MemoryManager.MaxMemoryMB
                CheckInterval = $MemoryManager.CheckInterval
            }
            CurrentUsage = $currentUsage
            PeakUsageMB = $peakUsage
            ThresholdUtilization = [Math]::Round(($currentUsage.WorkingSetMB / $MemoryManager.MaxMemoryMB) * 100, 1)
            PerformanceStatus = if ($currentUsage.WorkingSetMB -lt ($MemoryManager.MaxMemoryMB * 0.8)) {
                "Excellent"
            } elseif ($currentUsage.WorkingSetMB -lt ($MemoryManager.MaxMemoryMB * 0.9)) {
                "Good"
            } elseif ($currentUsage.WorkingSetMB -lt $MemoryManager.MaxMemoryMB) {
                "Acceptable"
            } else {
                "Concerning"
            }
        }

        if ($IncludeRecommendations) {
            $recommendations = @()

            if ($report.ThresholdUtilization -gt 90) {
                $recommendations += "Consider increasing memory threshold to $($MemoryManager.MaxMemoryMB * 1.5) MB"
            }

            if ($currentUsage.Gen2Collections -gt 10) {
                $recommendations += "High Gen2 collections detected - review object lifecycle management"
            }

            if ($peakUsage -gt ($MemoryManager.MaxMemoryMB * 1.2)) {
                $recommendations += "Peak usage exceeded threshold - consider more frequent memory checks"
            }

            if ($recommendations.Count -eq 0) {
                $recommendations += "Memory usage is within optimal parameters"
            }

            $report | Add-Member -NotePropertyName 'Recommendations' -NotePropertyValue $recommendations
        }

        return $report
    }
    catch {
        Write-Error "Failed to generate memory usage report: $($_.Exception.Message)" -ErrorAction Stop
    }
}

# Functions are automatically available when dot-sourced
# Note: Export-ModuleMember is only valid in .psm1 module files
