#Requires -Version 5.1

<#
.SYNOPSIS
    Script execution initialization module for Find-UnknownSID

.DESCRIPTION
    Provides comprehensive script initialization capabilities including configuration
    loading, logging setup, memory management initialization, and dependency validation.
    Focused solely on environment setup and preparation for script execution.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-04
    Version: 2.0.0

    TROUBLESHOOTING:
    - For initialization issues: .\Troubleshooting\Common\Initialization-Issues.md
    - For configuration problems: .\Troubleshooting\Common\Configuration-Problems.md
#>


function Initialize-ScriptExecution {
    <#
    .SYNOPSIS
        Initialize script execution environment with comprehensive validation

    .DESCRIPTION
        Sets up the script execution environment including configuration loading,
        logging initialization, memory management setup, and dependency validation.
        Provides comprehensive error handling and validation for enterprise environments.

        BUSINESS VALUE:
        - Ensures consistent environment setup across all script executions
        - Provides comprehensive logging and monitoring capabilities
        - Implements memory management to prevent resource exhaustion
        - Enables enterprise-grade configuration management
        - Supports correlation tracking for audit and troubleshooting

        INITIALIZATION FEATURES:
        - Automatic log file rotation based on size limits
        - Memory usage monitoring and management
        - Configuration validation and error handling
        - Performance statistics initialization
        - Correlation ID tracking for enterprise compliance

    .PARAMETER ConfigPath
        [String] (Optional) Path to configuration JSON file for custom settings.
        If not provided, default configuration will be used.

        VALIDATION RULES:
        - Must be a valid file path if specified
        - File must exist and be readable
        - Must contain valid JSON configuration structure

        BUSINESS CONTEXT:
        Allows customization of script behavior for different environments
        (development, staging, production) while maintaining consistency.

    .PARAMETER LogPath
        [String] (Optional) Path for log file output.
        If not provided, default timestamped log file will be created.

        VALIDATION RULES:
        - Directory must exist or be creatable
        - Must have write permissions to the specified location
        - File extension should be .log for consistency

        BUSINESS CONTEXT:
        Enables centralized logging for enterprise monitoring and compliance
        requirements. Supports integration with log aggregation systems.

    .PARAMETER MaxMemoryUsageMB
        [Int] (Optional) Maximum memory usage threshold in MB (Default: 1024).
        Controls memory management and prevents system resource exhaustion.

        VALIDATION RULES:
        - Must be between 100 and 16384 MB

    .PARAMETER CorrelationId
        [String] (Optional) Unique identifier for tracking operations across log entries.
        If not provided, a new GUID will be generated automatically.

        VALIDATION RULES:
        - Must be a valid non-empty string if provided
        - Should follow GUID format for consistency

        BUSINESS CONTEXT:
        Enables tracking of operations across multiple systems and log files
        for comprehensive audit trails and troubleshooting support.

    .PARAMETER LogLevel
        [String] (Optional) Sets the minimum log level for file output (Default: Information).
        Controls the verbosity of log file output while maintaining performance.

        VALIDATION RULES:
        - Must be one of: Critical, Error, Warning, Information, Debug, Verbose
        - Higher levels include all lower level messages

        BUSINESS CONTEXT:
        Enables fine-tuned control of log file size and performance impact
        while maintaining necessary audit and troubleshooting information.

    .PARAMETER SuppressConsoleOutput
        [Switch] (Optional) Suppresses console output for automation scenarios.
        Logs are still written to file, but console output is disabled.

        VALIDATION RULES:
        - Switch parameter (present/absent)
        - Does not affect file logging

        BUSINESS CONTEXT:
        Enables clean automation scenarios where console output would interfere
        with script integration or scheduled task execution.
        - Should be appropriate for system resources
        - Consider dataset size when setting limits

        PERFORMANCE IMPACT:
        Lower values trigger more frequent memory checks and cleanup.
        Higher values allow larger datasets but risk system instability.

    .PARAMETER CorrelationId
        [String] (Optional) Correlation ID for tracking this execution.
        Auto-generated if not provided for enterprise audit requirements.

    .PARAMETER LogLevel
        [String] (Optional) Logging level for output control (Default: Information).
        Controls verbosity of logging output for different environments.

    .OUTPUTS
        [Hashtable] Initialization results containing:
        - Config: Loaded and validated configuration object
        - MemoryManager: Initialized memory management system
        - Statistics: Performance tracking object
        - LogPath: Resolved log file path
        - CorrelationId: Tracking identifier for this session

    .EXAMPLE
        PS> Initialize-ScriptExecution -LogPath ".\Logs\script.log" -MaxMemoryUsageMB 1024

        DESCRIPTION: Initialize with custom log path and memory limit
        OUTPUT: Hashtable with initialized components
        USE CASE: Standard production environment setup
        DURATION: Typically 1-3 seconds depending on configuration complexity

    .EXAMPLE
        PS> Initialize-ScriptExecution -ConfigPath ".\Config\prod.json" -LogLevel Debug

        DESCRIPTION: Initialize with production configuration and debug logging
        OUTPUT: Hashtable with configuration loaded from file
        BUSINESS CASE: Production deployment with enhanced monitoring
        COMPLIANCE: Supports SOX and GDPR audit requirements

    .EXAMPLE
        PS> $init = Initialize-ScriptExecution; $init.Statistics.StartTime

        DESCRIPTION: Access initialization results for monitoring
        OUTPUT: Returns initialization timestamp
        INTEGRATION: Enables integration with monitoring dashboards

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        SECURITY CONSIDERATIONS:
        - Configuration files may contain sensitive settings
        - Log files should be protected with appropriate file permissions
        - Memory management prevents denial-of-service scenarios
        - Correlation IDs enable security event tracking

        PERFORMANCE CHARACTERISTICS:
        - Initialization typically completes in 1-3 seconds
        - Memory overhead: ~50MB for management structures
        - Configuration loading scales with complexity
        - Log rotation occurs automatically based on size limits

        TROUBLESHOOTING:
        - For initialization failures: .\Troubleshooting\Common\Initialization-Issues.md
        - For configuration issues: .\Troubleshooting\Common\Configuration-Problems.md
        - For memory management: .\Troubleshooting\Performance\Memory-Management.md
        - For logging problems: .\Troubleshooting\Common\Logging-Issues.md

        KNOWN LIMITATIONS:
        - Configuration changes require script restart
        - Log file rotation may briefly interrupt logging
        - Memory limits are advisory, not enforced by OS
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [ValidateRange(100, 16384)]
        [int]$MaxMemoryUsageMB = 1024,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$LogLevel = 'Information',

        [Parameter()]
        [switch]$SuppressConsoleOutput
    )

    begin {
        Write-Verbose "Starting script initialization with CorrelationId: $CorrelationId"
    }

    process {
        try {
            # Verify required classes are available (they should be loaded by the main script)
            Write-Verbose "Verifying required classes are available..."
            $requiredTypes = @('ScriptConfiguration', 'ProcessingStatistics', 'MemoryManager')
            $missingTypes = @()

            foreach ($typeName in $requiredTypes) {
                try {
                    $null = $typeName -as [type]
                    if (-not ($typeName -as [type])) {
                        $missingTypes += $typeName
                    }
                }
                catch {
                    $missingTypes += $typeName
                }
            }

            if ($missingTypes.Count -gt 0) {
                throw "Required types not available: $($missingTypes -join ', '). Classes should be loaded by the main script before calling Initialize-ScriptExecution."
            }

            Write-Verbose "All required classes are available: $($requiredTypes -join ', ')"

            # Initialize logging system first with new modular approach
            if ($LogPath) {
                Initialize-LoggingSystem -CorrelationId $CorrelationId -LogLevel $LogLevel -SuppressConsoleOutput:$SuppressConsoleOutput
                Initialize-LogDirectory -LogPath $LogPath
            } else {
                $defaultLogPath = ".\Logs\Find-UnknownSID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                Initialize-LoggingSystem -CorrelationId $CorrelationId -LogLevel $LogLevel -SuppressConsoleOutput:$SuppressConsoleOutput
                Initialize-LogDirectory -LogPath $defaultLogPath
            }

            # Initialize configuration
            Write-StructuredLog "Loading configuration..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId

            $script:Config = if ($ConfigPath -and (Test-Path $ConfigPath)) {
                Write-StructuredLog "Loading configuration from file: $ConfigPath" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
                [ScriptConfiguration]::LoadFromFile($ConfigPath)
            } else {
                Write-StructuredLog "Using default configuration" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
                [ScriptConfiguration]::new()
            }

            # Validate configuration
            if (-not $script:Config.ValidateConfiguration()) {
                throw "Configuration validation failed"
            }

            Write-StructuredLog "Configuration loaded and validated successfully" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId

            # Initialize memory manager using centralized memory management module
            Write-StructuredLog "Initializing memory manager (Limit: $MaxMemoryUsageMB MB)..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
            $script:MemoryManager = Initialize-MemoryManager -MaxMemoryMB $MaxMemoryUsageMB -CheckInterval $script:Config.MemoryCheckInterval -CorrelationId $CorrelationId

            # Initialize statistics
            Write-StructuredLog "Initializing performance statistics..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
            $script:Statistics = [ProcessingStatistics]::new()

            # Initialize log file path from configuration if provided
            if ($script:Config.LogFilePath) {
                $script:LogPath = $script:Config.LogFilePath
            } elseif ($LogPath) {
                $script:LogPath = $LogPath
            }

            # Perform log file rotation check
            if ($script:LogPath -and (Test-Path $script:LogPath)) {
                try {
                    $logFileInfo = Get-Item $script:LogPath
                    $fileSizeMB = [Math]::Round($logFileInfo.Length / 1MB, 2)

                    if ($script:Config.EnableLogFileRotation -and $fileSizeMB -gt $script:Config.MaxLogFileSizeMB) {
                        $rotatedPath = $script:LogPath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                        Move-Item $script:LogPath $rotatedPath
                        Write-StructuredLog "Rotated log file to: $rotatedPath (Size: $fileSizeMB MB)" -Level Information -Component 'Initialization' -CorrelationId $CorrelationId
                    }
                } catch {
                    Write-StructuredLog "Log file rotation check failed: $($_.Exception.Message)" -Level Warning -Component 'Initialization' -CorrelationId $CorrelationId
                }
            }

            # Return initialization results
            $initResults = @{
                Config = $script:Config
                MemoryManager = $script:MemoryManager
                Statistics = $script:Statistics
                LogPath = $script:LogPath
                CorrelationId = $CorrelationId
            }

            Write-StructuredLog "Script initialization completed successfully" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
            return $initResults

        } catch {
            Write-StructuredLog "Script initialization failed: $($_.Exception.Message)" -Level Error -Component 'Initialization' -CorrelationId $CorrelationId
            throw
        }
    }
}
