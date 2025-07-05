#Requires -Version 5.1

<#
.SYNOPSIS
    Enterprise logging system for Find-UnknownSID operations

.DESCRIPTION
    Provides comprehensive logging capabilities with correlation tracking,
    structured output, and enterprise-grade diagnostic support. Implements
    modern PowerShell logging patterns with security event handling.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-01
    Version: 2.0.0

    TROUBLESHOOTING:
    - For logging issues: .\Troubleshooting\Common\Logging-Issues.md
    - For file permissions: .\Troubleshooting\Security\File-Access.md

.LINK
    https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-logging
#>

# Script-scoped variables for logging state
$script:LogPath = $null
$script:LogFileInitialized = $false
$script:LogFileReinitAttempted = $false
$script:SuppressConsoleOutput = $false
$script:CorrelationId = $null
$script:LogLevel = 'Information'  # Default log level for file output

# Log level hierarchy for filtering
$script:LogLevels = @{
    'Critical' = 0
    'Error' = 1
    'Warning' = 2
    'Information' = 3
    'Debug' = 4
    'Verbose' = 5
}

function Initialize-ScriptLogging {
    <#
    .SYNOPSIS
        Initializes the enterprise logging system for Find-UnknownSID

    .DESCRIPTION
        Sets up structured logging with file output, correlation tracking,
        and proper error handling. Creates log directories and validates
        permissions before initializing the logging subsystem.

    .PARAMETER LogPath
        Absolute path to the log file. Directory will be created if it doesn't exist.

    .PARAMETER CorrelationId
        Unique identifier for tracking operations across log entries

    .PARAMETER SuppressConsoleOutput
        Suppresses console output for automation scenarios

    .PARAMETER LogLevel
        Sets the minimum log level for file output (Critical, Error, Warning, Information, Debug, Verbose)
        Default: Information (excludes Debug and Verbose from file output)

    .EXAMPLE
        PS> Initialize-ScriptLogging -LogPath "C:\Logs\script.log" -CorrelationId "abc-123"

        Initializes logging with specified path and correlation ID

    .EXAMPLE
        PS> Initialize-ScriptLogging -LogPath "C:\Logs\script.log" -LogLevel "Debug"

        Initializes logging with Debug level (includes all messages in file)

    .NOTES
        This function must be called before any Write-StructuredLog calls.
        Creates the log directory structure if it doesn't exist.
        Log level filtering reduces file size significantly in production.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$LogLevel = 'Information',

        [Parameter()]
        [switch]$SuppressConsoleOutput
    )

    try {
        # Ensure we have a valid CorrelationId
        if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
            $CorrelationId = [System.Guid]::NewGuid().ToString()
        }

        $script:CorrelationId = $CorrelationId
        $script:SuppressConsoleOutput = $SuppressConsoleOutput  # For switch parameters, use the value directly
        $script:LogLevel = $LogLevel

        # Handle empty or null LogPath
        if ([string]::IsNullOrWhiteSpace($LogPath)) {
            Write-Verbose "LogPath is empty, using default log file name"
            $LogPath = ".\Logs\Find-UnknownSID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        }

        # Ensure the path is not just whitespace
        $LogPath = $LogPath.Trim()
        if ([string]::IsNullOrWhiteSpace($LogPath)) {
            Write-Verbose "LogPath contains only whitespace, using default"
            $LogPath = ".\Logs\Find-UnknownSID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        }

        # Convert to absolute path relative to main script directory, not current working directory
        if ([System.IO.Path]::IsPathRooted($LogPath)) {
            # Already absolute path
            $script:LogPath = $LogPath
        } else {
            # Make relative paths relative to the main script directory, not the Private folder
            # Since this function is in Private subfolder, we need to go up one level to get main script directory
            $scriptRoot = if ($PSScriptRoot) {
                # If we're in the Private folder, go up one level to get the main script directory
                Split-Path -Parent $PSScriptRoot
            } else {
                # Fallback: try to get from caller's script location
                $callerScript = Get-PSCallStack | Where-Object { $_.ScriptName -and $_.ScriptName -notlike "*Logging.ps1" } | Select-Object -First 1
                if ($callerScript -and $callerScript.ScriptName) {
                    Split-Path -Parent $callerScript.ScriptName
                } else {
                    # Final fallback: use current directory
                    Get-Location
                }
            }
            $script:LogPath = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $LogPath))
        }
        Write-Verbose "Log path resolved to: $script:LogPath"

        # Ensure directory exists
        $logDirectory = Split-Path -Parent $script:LogPath
        if (-not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force -WhatIf:$false | Out-Null
            Write-Verbose "Created log directory: $logDirectory"
        }

        # Initialize log file immediately with proper error handling
        try {
            $logHeader = @"
=== Find-UnknownSID Script Log ===
Script Version: 2.0.0
Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Correlation ID: $script:CorrelationId
PowerShell Version: $($PSVersionTable.PSVersion)
User Context: $env:USERNAME@$env:COMPUTERNAME
Domain Context: $env:USERDOMAIN
Log Level: $script:LogLevel
Log File: $script:LogPath
==========================================

"@
            # Test write permissions and create log file - bypass WhatIf for log operations
            Set-Content -Path $script:LogPath -Value $logHeader -Encoding UTF8 -Force -ErrorAction Stop -WhatIf:$false
            $script:LogFileInitialized = $true
            Write-Verbose "Log file initialized successfully: $script:LogPath"
        }
        catch {
            Write-Warning "Failed to initialize log file '$script:LogPath': $($_.Exception.Message)"
            $script:LogPath = $null
            $script:LogFileInitialized = $false
        }
    }
    catch {
        Write-Warning "Failed to resolve log path '$LogPath': $($_.Exception.Message). Using current directory."
        $script:LogPath = Join-Path (Get-Location) "Find-UnknownSID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $script:LogFileInitialized = $false
    }
}
# Add this new function to c:\temp\Find-UnknownSID\Private\Logging.ps1

function Protect-LogMessage {
    <#
    .SYNOPSIS
        Sanitizes log messages to prevent log injection attacks

    .DESCRIPTION
        Removes or escapes potentially dangerous characters from log messages
        to prevent log injection, log forging, and other security vulnerabilities.
        Maintains readability while ensuring log integrity.

    .PARAMETER Message
        The log message to sanitize

    .PARAMETER PreserveNewlines
        Whether to preserve legitimate newlines in the message

    .EXAMPLE
        PS> Protect-LogMessage -Message "User input: `nmalicious`r`ninjection"

        Returns: "User input: malicious injection"

    .NOTES
        Implements enterprise-grade log sanitization patterns to prevent:
        - Log injection attacks via control characters
        - Log forging through line breaks
        - CRLF injection vulnerabilities
        - Terminal escape sequence injection
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [switch]$PreserveNewlines
    )

    process {
        if ([string]::IsNullOrEmpty($Message)) {
            return $Message
        }

        # Start with the original message
        $sanitizedMessage = $Message

        # Remove or replace dangerous control characters
        # CR (0x0D) and LF (0x0A) - primary log injection vectors
        if (-not $PreserveNewlines) {
            $sanitizedMessage = $sanitizedMessage -replace '[\r\n]', ' '
        }

        # Remove other control characters that could be used for injection
        $sanitizedMessage = $sanitizedMessage -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''

        # Remove ANSI escape sequences (prevent terminal manipulation)
        $sanitizedMessage = $sanitizedMessage -replace '\x1B\[[0-9;]*[mK]', ''

        # Remove Unicode control characters
        $sanitizedMessage = $sanitizedMessage -replace '[\u0000-\u001F\u007F-\u009F]', ''

        # Normalize multiple spaces to single space
        $sanitizedMessage = $sanitizedMessage -replace '\s+', ' '

        # Trim whitespace
        $sanitizedMessage = $sanitizedMessage.Trim()

        # Truncate if message is excessively long (prevent log flooding)
        if ($sanitizedMessage.Length -gt 2000) {
            $sanitizedMessage = $sanitizedMessage.Substring(0, 1997) + '...'
        }

        return $sanitizedMessage
    }
}

function Write-StructuredLog {
    <#
    .SYNOPSIS
        Writes structured log entries with correlation tracking and enterprise formatting

    .DESCRIPTION
        Provides comprehensive logging capabilities with multiple output formats,
        correlation ID tracking, structured data for automation integration,
        and persistent file logging for audit trails and troubleshooting.

        Automatically sanitizes all log messages to prevent log injection attacks
        and ensures consistent formatting across all log outputs.

    .PARAMETER Message
        The primary log message content (will be sanitized automatically)

    .PARAMETER Level
        Logging level: Critical, Error, Warning, Information, Debug, Verbose

    .PARAMETER Component
        Component or module generating the log entry

    .PARAMETER Color
        Console color for the message (when console output is enabled)

    .PARAMETER ErrorRecord
        PowerShell ErrorRecord object for detailed error logging

    .PARAMETER Data
        Additional structured data as hashtable

    .PARAMETER CorrelationId
        Correlation ID for tracking operations (uses script-level if not provided)

    .EXAMPLE
        PS> Write-StructuredLog -Message "Operation completed" -Level Information -Component "Main"

        Writes an informational log entry with automatic message sanitization

    .EXAMPLE
        PS> Write-StructuredLog -Message "Failed to process" -Level Error -Component "SIDProcessor" -ErrorRecord $_

        Writes an error log entry with exception details and sanitized output

    .NOTES
        Automatically includes correlation ID and timestamp in all log entries.
        Supports both file and console output with appropriate formatting.
        All messages are sanitized to prevent log injection attacks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$Level = 'Information',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'General',

        [Parameter()]
        [ValidateSet('Red', 'Green', 'Yellow', 'Cyan', 'Magenta', 'White', 'Gray', 'DarkGray')]
        [string]$Color = 'White',

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [hashtable]$Data = @{},

        [Parameter()]
        [string]$CorrelationId
    )

    # Sanitize the main message to prevent log injection attacks
    $sanitizedMessage = Protect-LogMessage -Message $Message

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'

    # Use provided CorrelationId or fall back to script-level CorrelationId or 'Unknown'
    $effectiveCorrelationId = if ($CorrelationId) {
        $CorrelationId
    } elseif ($script:CorrelationId) {
        $script:CorrelationId
    } else {
        'Unknown'
    }

    # Build structured log entry with sanitized message
    $logEntry = "[$timestamp] [$Level] [$Component] [$effectiveCorrelationId] $sanitizedMessage"

    # Add error details if provided (sanitize exception messages)
    if ($ErrorRecord) {
        $sanitizedExceptionMessage = Protect-LogMessage -Message $ErrorRecord.Exception.Message
        $logEntry += "`n    Exception: $sanitizedExceptionMessage"
        $logEntry += "`n    Category: $($ErrorRecord.CategoryInfo.Category)"

        # Sanitize target object representation
        $targetObject = if ($ErrorRecord.TargetObject) {
            Protect-LogMessage -Message $ErrorRecord.TargetObject.ToString()
        } else {
            'N/A'
        }
        $logEntry += "`n    Target: $targetObject"

        if ($ErrorRecord.ScriptStackTrace) {
            # Sanitize stack trace (preserve structure but clean content)
            $sanitizedStackTrace = Protect-LogMessage -Message $ErrorRecord.ScriptStackTrace -PreserveNewlines
            $logEntry += "`n    StackTrace: $sanitizedStackTrace"
        }
    }

    # Add structured data if provided (sanitize values)
    if ($Data.Count -gt 0) {
        $sanitizedData = @{
        }
        foreach ($key in $Data.Keys) {
            $sanitizedKey = Protect-LogMessage -Message $key.ToString()
            $sanitizedValue = if ($Data[$key]) {
                Protect-LogMessage -Message $Data[$key].ToString()
            } else {
                'N/A'
            }
            $sanitizedData[$sanitizedKey] = $sanitizedValue
        }
        $dataString = ($sanitizedData.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
        $logEntry += "`n    Data: $dataString"
    }

    # Console output with color support
    if (-not $script:SuppressConsoleOutput) {
        $hostColor = switch ($Level) {
            'Critical' { 'Magenta' }
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { $Color }
            'Debug' { 'DarkGray' }
            'Verbose' { 'DarkGray' }
            default { $Color }
        }

        # Only show Debug/Verbose in console if Verbose preference allows it
        $shouldShowInConsole = switch ($Level) {
            'Debug' { $VerbosePreference -ne 'SilentlyContinue' }
            'Verbose' { $VerbosePreference -ne 'SilentlyContinue' }
            default { $true }
        }

        if ($shouldShowInConsole) {
            # Use appropriate output method based on level
            switch ($Level) {
                'Error' {
                    Write-Error $logEntry -ErrorAction Continue
                }
                'Warning' {
                    Write-Warning $logEntry
                }
                'Debug' {
                    Write-Debug $logEntry
                }
                'Verbose' {
                    Write-Verbose $logEntry
                }
                default {
                    # For Information, Critical, and other levels
                    # Use Write-Information for consistent output
                    Write-Information $logEntry -InformationAction Continue
                }
            }
        }
    }

    # Write to log file if available and initialized (with log level filtering)
    if ($script:LogPath -and $script:LogFileInitialized) {
        # Check if this log level should be written to file
        $currentLogLevel = $script:LogLevels[$Level]
        $configuredLogLevel = $script:LogLevels[$script:LogLevel]

        # Only write if current level is equal or higher priority than configured level
        if ($currentLogLevel -le $configuredLogLevel) {
            try {
                # Bypass WhatIf for log file operations
                Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop -WhatIf:$false
            }
            catch {
                # Try to reinitialize the log file once
                if (-not $script:LogFileReinitAttempted) {
                    $script:LogFileReinitAttempted = $true
                    try {
                        $logDirectory = Split-Path -Parent $script:LogPath
                        if (-not (Test-Path $logDirectory)) {
                            New-Item -Path $logDirectory -ItemType Directory -Force -WhatIf:$false | Out-Null
                        }

                        # Create fresh log file
                        "Log file reinitialized at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $script:LogPath -Encoding UTF8 -Force -WhatIf:$false
                        Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8 -WhatIf:$false
                        Write-Warning "Log file was reinitialized due to write error"
                    }
                    catch {
                        Write-Warning "Failed to reinitialize log file: $($_.Exception.Message)"
                        $script:LogFileInitialized = $false
                    }
                }
            }
        }
    }
}

function Write-SecurityLog {
    <#
    .SYNOPSIS
        Writes security-specific log entries with enhanced protection and audit trails

    .DESCRIPTION
        Specialized logging for security events that require additional protection,
        sanitization of sensitive data, and compliance with audit requirements.

    .PARAMETER SecurityEventType
        Type of security event (Authentication, Authorization, DataAccess, etc.)

    .PARAMETER Message
        Security event description

    .PARAMETER Outcome
        Event outcome: Success, Failure, Attempt

    .PARAMETER CorrelationId
        Correlation ID for tracking security operations

    .PARAMETER SecurityContext
        Additional security context data (will be sanitized)

    .EXAMPLE
        PS> Write-SecurityLog -SecurityEventType "DataValidation" -Message "Input validated" -Outcome "Success"

        Logs a successful data validation security event

    .NOTES
        Automatically sanitizes sensitive data and includes security-specific metadata.
        All security logs include enhanced audit trail information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DataValidation', 'CredentialAccess', 'PrivilegeUse', 'ObjectAccess', 'SystemAccess')]
        [string]$SecurityEventType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Success', 'Failure', 'Attempt')]
        [string]$Outcome = 'Attempt',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [hashtable]$SecurityContext = @{}
    )

    # Build security context (sanitize sensitive data)
    Write-StructuredLog "Security event: $SecurityEventType - $Message (Outcome: $Outcome)" -Level Debug -Component 'Security' -CorrelationId $CorrelationId

    $sanitizedContext = @{
        EventType = $SecurityEventType
        Outcome = $Outcome
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        UserContext = "$env:USERNAME@$env:COMPUTERNAME"
        ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        CorrelationId = $CorrelationId
    }

    # Add sanitized security context
    foreach ($key in $SecurityContext.Keys) {
        # Sanitize potentially sensitive values
        $value = $SecurityContext[$key]
        if ($key -match 'password|secret|token|key|credential' -and $value) {
            $sanitizedContext[$key] = '[REDACTED]'
        } else {
            $sanitizedContext[$key] = $value
        }
    }

    # Determine log level based on outcome and event type
    # Security events should generally be logged but not displayed to terminal
    $logLevel = switch ($Outcome) {
        'Success' { 'Debug' }      # Log to file only - success events don't need terminal display
        'Failure' { 'Warning' }   # Display to terminal - failures need immediate attention
        'Attempt' { 'Debug' }     # Log to file only - attempt events are audit trail only
        default { 'Debug' }       # Default to debug level for security events
    }

    Write-StructuredLog -Level $logLevel -Message $Message -Component 'Security' -Data $sanitizedContext -CorrelationId $CorrelationId
}

function Get-LogFileSummary {
    <#
    .SYNOPSIS
        Generates a summary of the current log file

    .DESCRIPTION
        Provides statistics and metadata about the current log file,
        including size, entry count, and error analysis.

    .EXAMPLE
        PS> Get-LogFileSummary

        Returns summary information about the current log file

    .NOTES
        Returns null if no log file is currently active.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not $script:LogPath -or -not (Test-Path $script:LogPath)) {
        return $null
    }

    try {
        $logFile = Get-Item $script:LogPath
        $logContent = Get-Content $script:LogPath -ErrorAction SilentlyContinue

        $summary = [PSCustomObject]@{
            LogPath = $script:LogPath
            SizeMB = [Math]::Round($logFile.Length / 1MB, 2)
            LineCount = $logContent.Count
            ErrorCount = ($logContent | Where-Object { $_ -match '\[Error\]' }).Count
            WarningCount = ($logContent | Where-Object { $_ -match '\[Warning\]' }).Count
            CreatedTime = $logFile.CreationTime
            LastWriteTime = $logFile.LastWriteTime
            CorrelationId = $script:CorrelationId
        }

        return $summary
    }
    catch {
        Write-Warning "Failed to get log file summary: $($_.Exception.Message)"
        return $null
    }
}

function Export-DiagnosticData {
    <#
    .SYNOPSIS
        Exports comprehensive diagnostic information for troubleshooting

    .DESCRIPTION
        Collects and exports detailed diagnostic information including
        system state, log files, configuration, and runtime metrics.

    .PARAMETER OutputPath
        Directory path where diagnostic data will be exported

    .PARAMETER CorrelationId
        Correlation ID for the diagnostic export operation

    .EXAMPLE
        PS> Export-DiagnosticData -OutputPath "C:\Diagnostics" -CorrelationId "abc-123"

        Exports diagnostic data to the specified directory

    .NOTES
        Creates a timestamped directory with comprehensive diagnostic information.
        Includes sanitized configuration and log data for support analysis.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        # Create diagnostic package
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $diagnosticPath = Join-Path $OutputPath "Diagnostic-$timestamp"
        New-Item -Path $diagnosticPath -ItemType Directory -Force | Out-Null

        # Collect system information
        $diagnosticData = @{
            Timestamp = Get-Date
            CorrelationId = $CorrelationId
            SystemInfo = @{
                PSVersion = $PSVersionTable.PSVersion.ToString()
                OSVersion = [System.Environment]::OSVersion.ToString()
                MachineName = $env:COMPUTERNAME
                UserName = $env:USERNAME
                Domain = $env:USERDOMAIN
                ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
            }
            LogInfo = Get-LogFileSummary
            MemoryUsage = @{
                WorkingSetMB = [Math]::Round((Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)).WorkingSet64 / 1MB, 2)
                PrivateMemoryMB = [Math]::Round((Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)).PrivateMemorySize64 / 1MB, 2)
            }
        }

        # Export diagnostic data
        $diagnosticData | ConvertTo-Json -Depth 10 | Out-File "$diagnosticPath\diagnostic-data.json"

        # Copy log file if it exists
        if ($script:LogPath -and (Test-Path $script:LogPath)) {
            Copy-Item $script:LogPath "$diagnosticPath\current-log.log" -ErrorAction SilentlyContinue
        }

        # Export PowerShell session info
        $PSVersionTable | ConvertTo-Json | Out-File "$diagnosticPath\powershell-info.json"

        Write-StructuredLog -Level Information -Message "Diagnostic data exported" -Component 'Diagnostics' -Data @{
            ExportPath = $diagnosticPath
            FilesExported = (Get-ChildItem $diagnosticPath).Count
        } -CorrelationId $CorrelationId

        return $diagnosticPath
    }
    catch {
        Write-StructuredLog -Level Error -Message "Failed to export diagnostic data" -Component 'Diagnostics' -ErrorRecord $_ -CorrelationId $CorrelationId
        throw
    }
}