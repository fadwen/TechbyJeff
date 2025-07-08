function Write-SecurityStructuredLogEntry {
    <#
    .SYNOPSIS
        Writes security log entries directly to file with mandatory audit trail

    .DESCRIPTION
        Specialized logging function for security and audit events that bypasses
        normal log level filtering to ensure all security events are captured
        for compliance purposes. Security logs are ALWAYS written to file
        regardless of the general log level configuration.

    .PARAMETER Message
        The security log message content

    .PARAMETER Level
        Logging level (Information, Warning, Error) - Debug/Verbose not allowed for security

    .PARAMETER Component
        Component generating the security log entry

    .PARAMETER ErrorRecord
        PowerShell ErrorRecord object for security error logging

    .PARAMETER Data
        Additional structured data for security context

    .PARAMETER CorrelationId
        Correlation ID for tracking operations

    .EXAMPLE
        PS> Write-SecurityStructuredLogEntry -Message "AD object access attempt" -Level Information -Component "SecurityAudit"

        Writes security log entry directly to file, bypassing log level filtering

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        COMPLIANCE: Security logs are written regardless of log level to ensure audit trail
        PERFORMANCE: Direct file write, minimal validation for security critical path

        TROUBLESHOOTING:
        - For security logging issues: .\Troubleshooting\Security\Security-Logging-Issues.md
        - For compliance requirements: .\Troubleshooting\Security\Compliance-Guide.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information')]  # No Debug/Verbose for security
        [string]$Level = 'Information',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'SecurityAudit',

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [hashtable]$Data = @{},

        [Parameter()]
        [string]$CorrelationId
    )

    begin {
        Write-Verbose "Writing security structured log entry - Level: $Level, Component: $Component"

        # Get current logging system state
        $loggingState = Get-LoggingSystemState
        if (-not $loggingState.CorrelationId) {
            Write-Warning "Logging system not properly initialized for security logging"
        }
    }

    process {
        try {
            # Determine effective correlation ID
            $effectiveCorrelationId = if ($CorrelationId) {
                $CorrelationId
            } elseif ($loggingState.CorrelationId) {
                $loggingState.CorrelationId
            } else {
                [System.Guid]::NewGuid().ToString()
            }

            # Format the security log entry
            $additionalData = $Data
            if ($ErrorRecord) {
                $additionalData['ErrorRecord'] = @{
                    Exception = $ErrorRecord.Exception.Message
                    ScriptStackTrace = $ErrorRecord.ScriptStackTrace
                    FullyQualifiedErrorId = $ErrorRecord.FullyQualifiedErrorId
                }
            }
            
            $formattedEntry = Format-LogMessage -Message $Message -Level $Level -Component $Component -CorrelationId $effectiveCorrelationId -AdditionalData $additionalData

            # ALWAYS write to console for security events (with security prefix)
            Write-SecurityConsoleEntry -FormattedMessage $formattedEntry -Level $Level

            # ALWAYS write to file for security events - bypass log level filtering
            Write-SecurityFileEntry -FormattedMessage $formattedEntry

            # Update security metrics
            Update-SecurityLoggingMetrics -Level $Level
        }
        catch {
            # Security logging failures are critical - try multiple fallback mechanisms
            Write-Warning "CRITICAL: Security log entry failed: $($_.Exception.Message)"

            # Fallback 1: Try direct file write without formatting
            try {
                $fallbackEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [$Component] [$Level] SECURITY: $Message (CorrelationId: $effectiveCorrelationId)"
                Write-SecurityFileEntryDirect -Message $fallbackEntry
            }
            catch {
                # Fallback 2: Write to temp directory as last resort
                try {
                    $emergencyEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [SECURITY-EMERGENCY] [$Level] $Message (CorrelationId: $effectiveCorrelationId)"
                    $emergencyEntry | Out-File -FilePath "$env:TEMP\Find-UnknownSID-Security-Emergency.log" -Append -Encoding UTF8 -ErrorAction Stop
                    Write-Warning "Security log written to emergency file: $env:TEMP\Find-UnknownSID-Security-Emergency.log"
                }
                catch {
                    Write-Error "CRITICAL SECURITY LOGGING FAILURE: Unable to write security audit entry: $Message"
                }
            }
        }
    }
}


function Write-SecurityConsoleEntry {
    <#
    .SYNOPSIS
        Writes security log entry to console with security indicators

    .DESCRIPTION
        Specialized console output for security logs with clear security marking
        and appropriate output streams for security event visibility.
        Security logs are only displayed to console for Critical/Error levels
        or when specifically enabled. Information level security logs are 
        written to file only to reduce console noise.

    .PARAMETER FormattedMessage
        Pre-formatted security log message

    .PARAMETER Level
        Security log level
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FormattedMessage,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information')]
        [string]$Level
    )

    # Check if console output is suppressed
    $loggingState = Get-LoggingSystemState
    if ($loggingState.SuppressConsoleOutput) {
        return
    }

    # Only show Critical and Error security events in console to reduce noise
    # Information level security events are logged to file only
    if ($Level -eq 'Information') {
        return
    }

    # Security logs for critical issues should be visible in console with security prefix
    $securityMessage = "[SECURITY] $FormattedMessage"

    # Use appropriate output method based on level
    switch ($Level) {
        'Critical' {
            Write-Host $securityMessage -ForegroundColor Red -BackgroundColor Yellow
        }
        'Error' {
            Write-Error $securityMessage -ErrorAction Continue
        }
        'Warning' {
            Write-Warning $securityMessage
        }
    }
}


function Write-SecurityFileEntry {
    <#
    .SYNOPSIS
        Writes security log entry directly to file, bypassing log level filtering

    .DESCRIPTION
        Ensures security log entries are written to the log file regardless
        of the general log level configuration for compliance requirements.

    .PARAMETER FormattedMessage
        Pre-formatted security log message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FormattedMessage
    )

    $loggingState = Get-LoggingSystemState

    if (-not $loggingState.LogPath -or -not $loggingState.LogFileInitialized) {
        Write-Verbose "Log file not available for security logging - attempting emergency logging"
        Write-SecurityFileEntryDirect -Message $FormattedMessage
        return
    }

    try {
        # BYPASS log level filtering - always write security entries
        Add-Content -Path $loggingState.LogPath -Value $FormattedMessage -Encoding UTF8 -ErrorAction Stop -WhatIf:$false
        Write-Verbose "Security log entry written successfully to: $($loggingState.LogPath)"
    }
    catch {
        Write-Warning "Security log file write failed, attempting recovery: $($_.Exception.Message)"

        # Try to reinitialize the log file for security logging
        try {
            Write-SecurityFileEntryDirect -Message $FormattedMessage
        }
        catch {
            Write-Error "CRITICAL: Security log entry could not be written: $($_.Exception.Message)"
        }
    }
}


function Write-SecurityFileEntryDirect {
    <#
    .SYNOPSIS
        Direct security log file write with minimal dependencies

    .DESCRIPTION
        Last-resort security logging that attempts to write directly
        to log file or emergency locations when normal logging fails.

    .PARAMETER Message
        Security log message to write directly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $loggingState = Get-LoggingSystemState

    # Try normal log path first
    if ($loggingState.LogPath) {
        try {
            Add-Content -Path $loggingState.LogPath -Value $Message -Encoding UTF8 -ErrorAction Stop -WhatIf:$false
            return
        }
        catch {
            Write-Verbose "Direct log path failed: $($_.Exception.Message)"
        }
    }

    # Fallback to temp directory
    try {
        $tempLogPath = Join-Path $env:TEMP "Find-UnknownSID-Security-$(Get-Date -Format 'yyyyMMdd').log"
        Add-Content -Path $tempLogPath -Value $Message -Encoding UTF8 -ErrorAction Stop
        Write-Warning "Security log written to emergency location: $tempLogPath"
    }
    catch {
        Write-Error "CRITICAL: Cannot write security log entry anywhere: $($_.Exception.Message)"
    }
}


function Update-SecurityLoggingMetrics {
    <#
    .SYNOPSIS
        Updates security-specific logging metrics

    .DESCRIPTION
        Tracks security logging events separately from general logging
        for security monitoring and compliance reporting.

    .PARAMETER Level
        Security log level that was written
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information')]
        [string]$Level
    )

    # Initialize security metrics if not exists
    if (-not $script:SecurityLoggingMetrics) {
        $script:SecurityLoggingMetrics = @{
            TotalSecurityEntries = 0
            SecurityEntriesByLevel = @{
                Critical = 0
                Error = 0
                Warning = 0
                Information = 0
            }
            LastSecurityLogTime = $null
            SecurityLoggingErrors = 0
        }
    }

    # Update metrics
    $script:SecurityLoggingMetrics.TotalSecurityEntries++
    $script:SecurityLoggingMetrics.SecurityEntriesByLevel[$Level]++
    $script:SecurityLoggingMetrics.LastSecurityLogTime = Get-Date
}
