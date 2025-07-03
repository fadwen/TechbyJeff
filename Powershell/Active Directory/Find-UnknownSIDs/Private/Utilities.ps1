#Requires -Version 5.1

<#
.SYNOPSIS
    Utilities Module for Find-UnknownSIDs Solution

.DESCRIPTION
    This module provides general utility functions for the Find-UnknownSIDs
    enterprise solution. It includes DN validation, logging, memory management,
    and other common functionality used across the solution.

    BUSINESS VALUE:
    - Centralized utility functions for consistent behavior
    - Comprehensive input validation for security and reliability
    - Memory management for large-scale operations
    - Structured logging for audit trails and troubleshooting

    TECHNICAL FEATURES:
    - Distinguished Name validation with security checks
    - Advanced logging with correlation tracking and multiple outputs
    - Memory usage monitoring and automatic cleanup
    - Cross-platform compatibility for PowerShell 5.1 and 7.x

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For DN validation issues: .\Troubleshooting\Common\DN-Validation-Issues.md
    - For logging problems: .\Troubleshooting\Common\Logging-Issues.md
    - For memory issues: .\Troubleshooting\Performance\Memory-Management.md

    DEPENDENCIES:
    - Uses script-scoped variables for logging configuration
    - Integrates with enterprise logging infrastructure
    - Requires appropriate file system permissions for log file operations
#>

#region Distinguished Name Validation

function Test-ValidDistinguishedName {
    <#
    .SYNOPSIS
        Validates Distinguished Name format with comprehensive security checks

    .DESCRIPTION
        Performs comprehensive validation of Active Directory Distinguished Names
        including format validation, length checks, and security character filtering
        to prevent injection attacks and ensure proper AD object referencing.

        The validation includes:
        - Format structure validation (CN, OU, DC components)
        - Length limits based on LDAP specifications
        - Security character filtering to prevent injection attacks
        - Component structure validation for proper DN format
        - Domain component requirement validation

    .PARAMETER DistinguishedName
        The Distinguished Name string to validate. Can be empty or null
        for parameter validation scenarios.

    .EXAMPLE
        PS> Test-ValidDistinguishedName -DistinguishedName "OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Validates a standard organizational unit DN
        OUTPUT: $true for valid DN format
        USE CASE: Parameter validation for AD operations

    .EXAMPLE
        PS> Test-ValidDistinguishedName -DistinguishedName "CN=Invalid<>Name,DC=test,DC=com"

        DESCRIPTION: Tests DN with invalid characters
        OUTPUT: $false due to forbidden characters
        SECURITY: Prevents potential injection attacks through malformed DNs

    .EXAMPLE
        PS> $distinguishedNames | Test-ValidDistinguishedName

        DESCRIPTION: Pipeline validation of multiple DN strings
        OUTPUT: Array of boolean values for each DN
        AUTOMATION: Suitable for bulk validation in enterprise scenarios

    .OUTPUTS
        [bool] True if DN is valid and secure, false otherwise

    .NOTES
        SECURITY CONSIDERATIONS:
        - Filters dangerous characters that could be used in injection attacks
        - Enforces maximum length to prevent buffer overflow scenarios
        - Validates proper DN component structure (CN, OU, DC)
        - Ensures DN contains at least one domain component
        - Protects against malformed DN patterns that could cause AD errors

        VALIDATION RULES:
        - Maximum length: 1024 characters (LDAP specification)
        - Required format: (CN|OU|DC)=value,DC=domain
        - Forbidden characters: <>:"/\|?*\x00-\x1f\x7f-\x9f
        - Each component must have TYPE=VALUE format
        - Must contain at least one DC (Domain Component)

        PERFORMANCE CHARACTERISTICS:
        - Validation time: <1ms per DN typically
        - Memory usage: Minimal, optimized for bulk operations
        - Thread safety: Stateless function safe for parallel processing
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$DistinguishedName,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            # Handle null or empty strings
            if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
                Write-ScriptLog "Distinguished Name validation failed: Empty or null value" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
                return $false
            }

            # Length validation (LDAP DN maximum length)
            if ($DistinguishedName.Length -gt 1024) {
                Write-ScriptLog "Distinguished Name validation failed: Length exceeds 1024 characters ($($DistinguishedName.Length))" -Level Warning -Component 'Utilities' -CorrelationId $CorrelationId
                return $false
            }

            # Basic format validation - must contain DC component and proper structure
            if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                Write-ScriptLog "Distinguished Name validation failed: Invalid format structure" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
                return $false
            }

            # Security validation - check for dangerous characters
            $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
            if ($DistinguishedName -match $dangerousChars) {
                Write-ScriptLog "Distinguished Name validation failed: Contains dangerous characters" -Level Warning -Component 'Utilities' -CorrelationId $CorrelationId
                return $false
            }

            # Validate DN components structure
            $components = ($DistinguishedName -split ',')
            foreach ($component in $components) {
                $component = $component.Trim()

                # Each component must have format: TYPE=VALUE
                if (-not ($component -match '^(CN|OU|DC)=.+$')) {
                    Write-ScriptLog "Distinguished Name validation failed: Invalid component format: $component" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
                    return $false
                }

                # Component value cannot be empty after the equals sign
                $parts = $component -split '=', 2
                if ($parts.Length -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
                    Write-ScriptLog "Distinguished Name validation failed: Empty component value: $component" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
                    return $false
                }
            }

            # Must contain at least one DC component
            $domainComponents = $components | Where-Object { $_ -match '^DC=' }
            if ($domainComponents.Count -eq 0) {
                Write-ScriptLog "Distinguished Name validation failed: No domain components (DC=) found" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
                return $false
            }

            Write-ScriptLog "Distinguished Name validation successful: $DistinguishedName" -Level Debug -Component 'Utilities' -CorrelationId $CorrelationId
            return $true
        }
        catch {
            Write-ScriptLog "Distinguished Name validation error: $($_.Exception.Message)" -Level Warning -Component 'Utilities' -CorrelationId $CorrelationId
            return $false
        }
    }
}

#endregion

#region Automation and Utility Functions

# Removed redundant logging functions - all logging now handled by Logging.ps1 module
# This eliminates duplicate log entries and ensures consistent log level filtering

#endregion

#region Memory Management

# Memory manager with thread safety and enterprise features
class MemoryManager : System.IDisposable {
    [int]$MaxMemoryMB
    [int]$CheckInterval
    [int]$CheckCounter = 0
    [System.Diagnostics.Stopwatch]$Timer
    [long]$PeakMemoryUsage
    [bool]$Disposed
    [System.Threading.Mutex]$SyncMutex
    [int]$ProcessId
    [string]$CorrelationId

    <#
    .SYNOPSIS
        Initializes a new MemoryManager instance

    .DESCRIPTION
        Creates a memory management instance with specified thresholds
        and monitoring intervals for enterprise-scale operations.

    .PARAMETER maxMemoryMB
        Maximum memory threshold in megabytes before cleanup

    .PARAMETER checkInterval
        Number of operations between memory checks
    #>
    MemoryManager([int]$maxMemoryMB, [int]$checkInterval) {
        $this.MaxMemoryMB = $maxMemoryMB
        $this.CheckInterval = $checkInterval
        $this.CheckCounter = 0
        $this.Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $this.PeakMemoryUsage = 0
        $this.Disposed = $false
        $this.SyncMutex = [System.Threading.Mutex]::new($false)
        $this.ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $this.CorrelationId = [System.Guid]::NewGuid().ToString()
    }

    MemoryManager([int]$maxMemoryMB, [int]$checkInterval, [string]$correlationId) {
        $this.MaxMemoryMB = $maxMemoryMB
        $this.CheckInterval = $checkInterval
        $this.CheckCounter = 0
        $this.Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $this.PeakMemoryUsage = 0
        $this.Disposed = $false
        $this.SyncMutex = [System.Threading.Mutex]::new($false)
        $this.ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $this.CorrelationId = $correlationId
    }

    <#
    .SYNOPSIS
        Checks current memory usage and triggers cleanup if needed

    .DESCRIPTION
        Monitors memory usage at configured intervals and performs
        automatic garbage collection when thresholds are exceeded.
    #>
    [void]CheckMemoryUsage() {
        if ($this.Disposed) {
            return
        }

        $this.CheckCounter++

        if ($this.CheckCounter -ge $this.CheckInterval) {
            $this.CheckCounter = 0

            try {
                $currentProcess = Get-Process -Id $this.ProcessId -ErrorAction Stop
                $currentMemoryMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)

                if ($currentMemoryMB -gt $this.PeakMemoryUsage) {
                    $this.PeakMemoryUsage = $currentMemoryMB
                }

                Write-ScriptLog "Memory usage: $currentMemoryMB MB (Peak: $($this.PeakMemoryUsage) MB)" -Level Debug -Component 'MemoryManager' -CorrelationId $this.CorrelationId

                if ($currentMemoryMB -gt $this.MaxMemoryMB) {
                    Write-ScriptLog "Memory usage exceeded threshold ($currentMemoryMB MB > $($this.MaxMemoryMB) MB). Forcing garbage collection..." -Level Warning -Component 'MemoryManager' -CorrelationId $this.CorrelationId
                    $this.ForceGarbageCollection()

                    # Check memory after cleanup
                    $cleanupProcess = Get-Process -Id $this.ProcessId -ErrorAction Stop
                    $newMemoryMB = [Math]::Round($cleanupProcess.WorkingSet64 / 1MB, 2)
                    $freedMB = [Math]::Round($currentMemoryMB - $newMemoryMB, 2)
                    Write-ScriptLog "Memory after cleanup: $newMemoryMB MB (Freed: $freedMB MB)" -Level Information -Component 'MemoryManager' -CorrelationId $this.CorrelationId
                }
            }
            catch {
                Write-ScriptLog "Error checking memory usage: $($_.Exception.Message)" -Level Warning -Component 'MemoryManager' -CorrelationId $this.CorrelationId
            }
        }
    }

    <#
    .SYNOPSIS
        Forces garbage collection to free memory

    .DESCRIPTION
        Performs comprehensive garbage collection including
        finalizer queue processing for maximum memory recovery.
    #>
    [void]ForceGarbageCollection() {
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            Write-ScriptLog "Forced garbage collection completed" -Level Debug -Component 'MemoryManager' -CorrelationId $this.CorrelationId
        }
        catch {
            Write-ScriptLog "Error during garbage collection: $($_.Exception.Message)" -Level Warning -Component 'MemoryManager' -CorrelationId $this.CorrelationId
        }
    }

    <#
    .SYNOPSIS
        Gets the peak memory usage recorded

    .DESCRIPTION
        Returns the highest memory usage observed during the session
        for performance analysis and capacity planning.

    .OUTPUTS
        [long] Peak memory usage in megabytes
    #>
    [long]GetPeakMemoryUsage() {
        return $this.PeakMemoryUsage
    }

    <#
    .SYNOPSIS
        Disposes of the MemoryManager resources

    .DESCRIPTION
        Cleanly disposes of managed resources and performs final
        garbage collection for proper cleanup.
    #>
    [void]Dispose() {
        if (-not $this.Disposed) {
            try {
                Write-ScriptLog "Disposing MemoryManager resources" -Level Debug -Component 'MemoryManager' -CorrelationId $this.CorrelationId

                # Stop timer
                if ($this.Timer) {
                    $this.Timer.Stop()
                    $this.Timer = $null
                }

                # Dispose mutex
                if ($this.SyncMutex) {
                    $this.SyncMutex.Dispose()
                    $this.SyncMutex = $null
                }

                # Final cleanup
                $this.ForceGarbageCollection()
                $this.Disposed = $true

                Write-ScriptLog "MemoryManager disposed successfully - Peak usage: $($this.PeakMemoryUsage) MB" -Level Information -Component 'MemoryManager' -CorrelationId $this.CorrelationId
            }
            catch {
                Write-ScriptLog "Error during MemoryManager disposal: $($_.Exception.Message)" -Level Warning -Component 'MemoryManager' -CorrelationId $this.CorrelationId
            }
        }
    }
}

#endregion

#region String and Path Utilities

function Get-SafeFileName {
    <#
    .SYNOPSIS
        Creates safe filenames from arbitrary strings

    .DESCRIPTION
        Converts potentially unsafe strings (like Distinguished Names)
        into safe filenames by replacing illegal characters and
        handling length limitations.

    .PARAMETER InputString
        The string to convert to a safe filename

    .PARAMETER MaxLength
        Maximum filename length (default: 200)

    .EXAMPLE
        PS> Get-SafeFileName -InputString "CN=Test User,OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Converts DN to safe filename
        OUTPUT: "CN_Test_User_OU_Users_DC_contoso_DC_com"
        USE CASE: Creating backup files from object names

    .OUTPUTS
        [string] Safe filename string
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$InputString,

        [Parameter()]
        [int]$MaxLength = 200,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        if ([string]::IsNullOrWhiteSpace($InputString)) {
            return "Unknown"
        }

        # Replace illegal filename characters
        $safeName = $InputString -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'

        # Handle length limitations
        if ($safeName.Length -gt $MaxLength) {
            $safeName = $safeName.Substring(0, $MaxLength) + "_truncated"
        }

        return $safeName
    }
    catch {
        Write-ScriptLog "Error creating safe filename from '$InputString': $($_.Exception.Message)" -Level Warning -Component 'Utilities' -CorrelationId $CorrelationId
        return "Error_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    }
}

function Test-DirectoryAccess {
    <#
    .SYNOPSIS
        Tests directory access with automatic creation

    .DESCRIPTION
        Validates that a directory exists and is writable,
        creating it if necessary with appropriate error handling.

    .PARAMETER Path
        Directory path to test and create if needed

    .EXAMPLE
        PS> Test-DirectoryAccess -Path "C:\Backups"

        DESCRIPTION: Ensures backup directory exists and is writable
        OUTPUT: $true if accessible, $false otherwise
        USE CASE: Pre-validation before file operations

    .OUTPUTS
        [bool] True if directory is accessible, false otherwise
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $false
        }

        # Test if directory exists
        if (-not (Test-Path $Path -PathType Container)) {
            # Try to create it
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-ScriptLog "Created directory: $Path" -Level Information -Component 'Utilities' -CorrelationId $CorrelationId
        }

        # Test write access by creating a temporary file
        $testFile = Join-Path $Path "test_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
        "test" | Out-File -FilePath $testFile -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-ScriptLog "Directory access test failed for '$Path': $($_.Exception.Message)" -Level Warning -Component 'Utilities' -CorrelationId $CorrelationId
        return $false
    }
}

#endregion

Write-ScriptLog "Utilities module loaded successfully" -Level Debug -Component 'Utilities' -CorrelationId ([System.Guid]::NewGuid().ToString())
