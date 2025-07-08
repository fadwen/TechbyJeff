#Requires -Version 5.1

<#
.SYNOPSIS
    Core logging system initialization for Find-UnknownSID operations

.DESCRIPTION
    Provides centralized logging system state management with correlation tracking
    and configuration validation. Focuses solely on logging system initialization
    without path resolution or directory creation (handled by separate modules).

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-05
    Version: 2.0.0

    TROUBLESHOOTING:
    - For logging initialization issues: .\Troubleshooting\Common\Logging-Initialization.md
    - For configuration problems: .\Troubleshooting\Common\Configuration-Issues.md

.LINK
    https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-logging
#>

# Import shared logging configuration and state management
# Script-scoped variables are defined in LoggingConfiguration.ps1
# This module uses those shared variables for state management


function Initialize-LoggingSystem {
    <#
    .SYNOPSIS
        Initializes core logging system state and configuration

    .DESCRIPTION
        Sets up the logging system state management with correlation tracking,
        log level configuration, and console output settings. This function
        focuses solely on system state initialization.

        Directory creation and path resolution are handled by separate modules
        following single responsibility principle.

    .PARAMETER CorrelationId
        Unique identifier for tracking operations across log entries

    .PARAMETER LogLevel
        Sets the minimum log level for file output (Critical, Error, Warning, Information, Debug, Verbose)
        Default: Information (excludes Debug and Verbose from file output)

    .PARAMETER SuppressConsoleOutput
        Suppresses console output for automation scenarios

    .EXAMPLE
        PS> Initialize-LoggingSystem -CorrelationId "abc-123" -LogLevel "Debug"

        Initializes logging system with specified correlation ID and debug level

    .EXAMPLE
        PS> Initialize-LoggingSystem -SuppressConsoleOutput

        Initializes logging system with console output suppressed

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. This function does not return objects to the pipeline.

    .NOTES
        This function must be called before other logging operations.
        Call Initialize-LogDirectory separately for path and directory setup.
        Uses script-scoped variables for state management across modules.

        PERFORMANCE CHARACTERISTICS:
        - Execution time: <10ms
        - Memory usage: Minimal (state variables only)
        - Dependencies: None

        TROUBLESHOOTING:
        - Correlation ID validation ensures proper tracking
        - Log level validation prevents invalid configurations
        - State variables provide consistent behavior across modules
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$LogLevel = 'Information',

        [Parameter()]
        [switch]$SuppressConsoleOutput
    )

    begin {
        Write-Verbose "Initializing logging system state - CorrelationId: $CorrelationId"
    }

    process {
        try {
            # Validate and set correlation ID
            if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
                $CorrelationId = [System.Guid]::NewGuid().ToString()
                Write-Verbose "Generated new correlation ID: $CorrelationId"
            }

            # Initialize script-scoped state variables
            $script:CorrelationId = $CorrelationId
            $script:LogLevel = $LogLevel
            $script:SuppressConsoleOutput = $SuppressConsoleOutput.IsPresent

            # Reset initialization flags
            $script:LogFileInitialized = $false
            $script:LogFileReinitAttempted = $false

            Write-Verbose "Logging system state initialized successfully"
            Write-Verbose "  - Correlation ID: $script:CorrelationId"
            Write-Verbose "  - Log Level: $script:LogLevel"
            Write-Verbose "  - Console Output Suppressed: $script:SuppressConsoleOutput"
        }
        catch {
            Write-Error "Failed to initialize logging system state: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Logging system initialization completed"
    }
}


function Get-LoggingSystemState {
    <#
    .SYNOPSIS
        Retrieves current logging system state information

    .DESCRIPTION
        Returns comprehensive information about the current logging system
        configuration and state for diagnostics and troubleshooting.

    .EXAMPLE
        PS> Get-LoggingSystemState

        Returns current logging system configuration

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [PSCustomObject] Logging system state information

    .NOTES
        Useful for debugging and system status validation.
        Returns sanitized information safe for logging and diagnostics.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return [PSCustomObject]@{
        PSTypeName = 'LoggingSystemState'
        CorrelationId = $script:CorrelationId
        LogLevel = $script:LogLevel
        LogPath = $script:LogPath
        LogFileInitialized = $script:LogFileInitialized
        LogFileReinitAttempted = $script:LogFileReinitAttempted
        SuppressConsoleOutput = $script:SuppressConsoleOutput
        AvailableLogLevels = $script:LogLevels.Keys
        Timestamp = Get-Date
    }
}


function Test-LogLevel {
    <#
    .SYNOPSIS
        Tests if a message level should be logged based on current configuration

    .DESCRIPTION
        Compares a message log level against the configured minimum log level
        to determine if the message should be written to the log file.

    .PARAMETER MessageLevel
        The log level of the message to test

    .EXAMPLE
        PS> Test-LogLevel -MessageLevel "Debug"

        Returns $true if Debug messages should be logged based on current configuration

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [bool] True if message should be logged, false otherwise

    .NOTES
        Used internally by logging functions to filter messages.
        Follows log level hierarchy: Critical(0) > Error(1) > Warning(2) > Information(3) > Debug(4) > Verbose(5)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$MessageLevel
    )

    if (-not $script:LogLevels.ContainsKey($MessageLevel) -or -not $script:LogLevels.ContainsKey($script:LogLevel)) {
        Write-Warning "Invalid log level comparison: Message='$MessageLevel', System='$script:LogLevel'"
        return $false
    }

    # Message should be logged if its priority is >= configured level (lower number = higher priority)
    return $script:LogLevels[$MessageLevel] -le $script:LogLevels[$script:LogLevel]
}
