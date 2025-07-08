# Shared logging state and configuration variables
# These script-scoped variables maintain the logging system state across all logging modules

<#
.SYNOPSIS
    Shared logging configuration and state management

.DESCRIPTION
    This module provides centralized management of logging system state variables
    that are shared across all logging modules. It maintains the logging configuration,
    state tracking, and level hierarchies used throughout the logging system.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    SCOPE: Script-level variables are shared across all logging modules
    THREAD-SAFETY: PowerShell script variables are not thread-safe by default
    PERSISTENCE: Variables are reset when PowerShell session ends

    TROUBLESHOOTING:
    - For state issues: .\Troubleshooting\Logging\State-Management.md
    - For configuration: .\Troubleshooting\Common\Logging-Issues.md
#>

# Primary logging configuration
$script:LogPath = $null                    # Full path to the active log file
$script:LogFileInitialized = $false        # Whether log file has been created and initialized
$script:LogFileReinitAttempted = $false    # Whether reinitialization has been attempted (prevents loops)
$script:SuppressConsoleOutput = $false     # Whether to suppress console output for logging
$script:CorrelationId = $null              # Current correlation ID for operation tracking
$script:LogLevel = 'Information'           # Default log level for file output filtering

# Log level hierarchy for filtering and priority determination
# Lower numbers indicate higher priority/severity
$script:LogLevels = @{
    'Critical'    = 0    # System failures, data corruption, security breaches
    'Error'       = 1    # Operation failures, exceptions, recoverable errors
    'Warning'     = 2    # Potential issues, deprecated usage, performance concerns
    'Information' = 3    # Normal operations, business events, state changes
    'Debug'       = 4    # Detailed tracing, variable values, flow control
    'Verbose'     = 5    # Comprehensive tracing, internal operations, diagnostics
}

# Logging system metadata
$script:LoggingSystemInfo = @{
    Version = '2.0.0'
    InitializedAt = $null
    LastConfigurationChange = $null
    ModulesLoaded = @()
    ConfigurationSource = 'Default'
}

# Performance tracking for logging operations
$script:LoggingMetrics = @{
    TotalLogEntries = 0
    LogEntriesByLevel = @{
        Critical = 0
        Error = 0
        Warning = 0
        Information = 0
        Debug = 0
        Verbose = 0
    }
    LastLogEntryTime = $null
    AverageLogTimeMs = 0
    TotalLogTimeMs = 0
}

# Configuration validation patterns
$script:LoggingValidation = @{
    ValidLogLevels = @('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')
    MaxLogFileSizeMB = 100
    MaxRetentionDays = 30
    RequiredPathCharacters = '^[a-zA-Z]:\\(?:[^<>:"|?*\r\n]+\\)*[^<>:"|?*\r\n]+\.log$'
}

# Export configuration access functions for external modules
function Get-LoggingState {
    <#
    .SYNOPSIS
        Gets the current logging system state

    .DESCRIPTION
        Returns a read-only view of the current logging system configuration
        and state for diagnostic and monitoring purposes.

    .OUTPUTS
        PSCustomObject containing current logging state
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return [PSCustomObject]@{
        LogPath = $script:LogPath
        LogFileInitialized = $script:LogFileInitialized
        LogFileReinitAttempted = $script:LogFileReinitAttempted
        SuppressConsoleOutput = $script:SuppressConsoleOutput
        CorrelationId = $script:CorrelationId
        LogLevel = $script:LogLevel
        LogLevels = $script:LogLevels.Clone()
        SystemInfo = $script:LoggingSystemInfo.Clone()
        Metrics = $script:LoggingMetrics.Clone()
        ValidationRules = $script:LoggingValidation.Clone()
    }
}

function Test-LogLevel {
    <#
    .SYNOPSIS
        Tests if a log level should be written based on current configuration

    .DESCRIPTION
        Compares the provided log level against the current logging threshold
        to determine if the message should be written to the log file.

    .PARAMETER Level
        The log level to test

    .OUTPUTS
        Boolean indicating whether the level should be logged
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$Level
    )

    $currentLevelValue = $script:LogLevels[$script:LogLevel]
    $testLevelValue = $script:LogLevels[$Level]

    return $testLevelValue -le $currentLevelValue
}

function Update-LoggingMetrics {
    <#
    .SYNOPSIS
        Updates logging performance and usage metrics

    .DESCRIPTION
        Tracks logging system usage for performance monitoring and diagnostics.

    .PARAMETER Level
        The log level that was written

    .PARAMETER ProcessingTimeMs
        Time taken to process the log entry in milliseconds
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$Level,

        [Parameter()]
        [double]$ProcessingTimeMs = 0
    )

    $script:LoggingMetrics.TotalLogEntries++
    $script:LoggingMetrics.LogEntriesByLevel[$Level]++
    $script:LoggingMetrics.LastLogEntryTime = Get-Date

    if ($ProcessingTimeMs -gt 0) {
        $script:LoggingMetrics.TotalLogTimeMs += $ProcessingTimeMs
        $script:LoggingMetrics.AverageLogTimeMs = $script:LoggingMetrics.TotalLogTimeMs / $script:LoggingMetrics.TotalLogEntries
    }
}

function Set-LogLevel {
    <#
    .SYNOPSIS
        Sets the minimum log level for file output

    .DESCRIPTION
        Updates the logging system configuration to filter log entries
        based on the specified minimum level. Security logs bypass this filtering.

    .PARAMETER Level
        The minimum log level to write to file

    .EXAMPLE
        PS> Set-LogLevel -Level Warning

        Only Critical, Error, and Warning messages will be written to file

    .NOTES
        Security audit logs always bypass log level filtering for compliance
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$Level
    )

    $oldLevel = $script:LogLevel
    $script:LogLevel = $Level
    $script:LoggingSystemInfo.LastConfigurationChange = Get-Date

    Write-Verbose "Log level changed from '$oldLevel' to '$Level'"
}

function Get-LogLevel {
    <#
    .SYNOPSIS
        Gets the current minimum log level

    .DESCRIPTION
        Returns the current logging level configuration

    .OUTPUTS
        String representing the current log level
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:LogLevel
}

# Module initialization
$script:LoggingSystemInfo.InitializedAt = Get-Date
$script:LoggingSystemInfo.ModulesLoaded += 'Initialize-LoggingConfiguration'
