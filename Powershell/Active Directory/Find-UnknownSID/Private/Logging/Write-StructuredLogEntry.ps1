function Write-StructuredLogEntry {
    <#
    .SYNOPSIS
        Writes structured log entries with consistent formatting
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose', 'INFO')]
        [string]$Level,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'General',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [hashtable]$Details = @{}
    )

    # Normalize INFO to Information
    if ($Level -eq 'INFO') {
        $Level = 'Information'
    }

    try {
        # Create structured log entry
        $logEntry = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"
            Level = $Level
            Component = $Component
            CorrelationId = $CorrelationId
            Message = $Message
        }

        # Add additional details
        if ($Details.Count -gt 0) {
            foreach ($key in $Details.Keys) {
                $logEntry | Add-Member -MemberType NoteProperty -Name $key -Value $Details[$key]
            }
        }

        # Format the entry - create simple formatted strings
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff"
        $formattedEntryForFile = "[$timestamp] [$Level] [$Component] [$CorrelationId] $Message"
        if ($Details.Count -gt 0) {
            $detailsJson = $Details | ConvertTo-Json -Compress
            $formattedEntryForFile += " | Details: $detailsJson"
        }
        
        $formattedEntryForConsole = "[$Level] [$Component] $Message"

        # Determine the log path - use parameter if provided, otherwise try to get from logging system state
        $effectiveLogPath = $LogPath
        if (-not $effectiveLogPath) {
            try {
                if (Get-Command Get-LoggingSystemState -ErrorAction SilentlyContinue) {
                    $loggingState = Get-LoggingSystemState
                    $effectiveLogPath = $loggingState.LogPath
                }
            } catch {
                # If we can't get logging state, just use console output
                Write-Verbose "Could not retrieve logging system state: $($_.Exception.Message)"
            }
        }

        # Write to appropriate destination
        # Always write to console for user feedback
        Write-ConsoleLogEntry -FormattedMessage $formattedEntryForConsole -Level $Level
        
        # Also write to file if log path is available
        if ($effectiveLogPath) {
            try {
                Add-Content -Path $effectiveLogPath -Value $formattedEntryForFile -Encoding UTF8
            } catch {
                Write-Warning "Failed to write log entry to file: $($_.Exception.Message)"
            }
        }

        # Don't return to pipeline - just write to void to prevent output contamination
        $null = $logEntry
    } catch {
        Write-Warning "Failed to write structured log entry: $($_.Exception.Message)"
    }
}

function Write-ConsoleLogEntry {
    [CmdletBinding()]
    param(
        [string]$FormattedMessage,
        [string]$Level
    )

    switch ($Level) {
        'Critical' { Write-Error $FormattedMessage }
        'Error' { Write-Error $FormattedMessage }
        'Warning' { Write-Warning $FormattedMessage }
        'Information' { Write-Information $FormattedMessage -InformationAction Continue }
        'Debug' { Write-Debug $FormattedMessage }
        'Verbose' { Write-Verbose $FormattedMessage }
        default { Write-Host $FormattedMessage }
    }
}
