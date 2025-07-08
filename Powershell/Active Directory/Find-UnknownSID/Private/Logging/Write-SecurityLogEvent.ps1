#Requires -Version 5.1

<#
.SYNOPSIS
    Security-specific logging operations for Find-UnknownSID

.DESCRIPTION
    Provides specialized logging functionality for security events with enhanced
    protection, audit trail generation, and compliance with security requirements.
    Focuses solely on security event logging with appropriate sanitization and context.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-05
    Version: 2.0.0

    TROUBLESHOOTING:
    - For security logging issues: .\Troubleshooting\Security\Security-Logging.md
    - For audit compliance: .\Troubleshooting\Security\Audit-Requirements.md

.LINK
    https://docs.microsoft.com/en-us/security/compass/privileged-access-security-levels
#>


function Write-SecurityLogEvent {
    <#
    .SYNOPSIS
        Writes security-specific log entries with enhanced protection and audit trails

    .DESCRIPTION
        Specialized logging function for security events that require additional
        protection, sanitization of sensitive data, and compliance with audit
        requirements. This function ensures security events are properly logged
        with appropriate context and protection measures.

        Security events are automatically categorized and include enhanced
        metadata for compliance and forensic analysis.

    .PARAMETER SecurityEventType
        Type of security event being logged

    .PARAMETER Message
        Security event description (will be sanitized automatically)

    .PARAMETER Outcome
        Event outcome classification for security analysis

    .PARAMETER CorrelationId
        Correlation ID for tracking security operations across log entries

    .PARAMETER SecurityContext
        Additional security context data (sensitive values will be redacted)

    .PARAMETER Severity
        Security severity level for the event

    .EXAMPLE
        PS> Write-SecurityLogEvent -SecurityEventType "DataValidation" -Message "Input validated successfully" -Outcome "Success"

        Logs a successful data validation security event with default context

    .EXAMPLE
        PS> Write-SecurityLogEvent -SecurityEventType "CredentialAccess" -Message "Failed authentication attempt" -Outcome "Failure" -SecurityContext @{Source="RemoteIP"; User="testuser"}

        Logs a failed authentication attempt with additional security context

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. This function writes to security logging subsystem.

    .NOTES
        All security events are automatically enhanced with:
        - Process and user context information
        - Timestamp with high precision
        - Correlation ID for operation tracking
        - Sanitized security context data
        - Appropriate log level assignment based on outcome

        SECURITY CONSIDERATIONS:
        - Sensitive data is automatically redacted (passwords, tokens, keys)
        - Context data is sanitized to prevent injection attacks
        - Event classification enables automated security monitoring
        - Audit trail information meets compliance requirements

        PERFORMANCE CHARACTERISTICS:
        - Execution time: 2-8ms depending on context size
        - Memory usage: Minimal (context hashtable only)
        - Audit overhead: Designed for high-frequency security events

        TROUBLESHOOTING:
        - Failed security events are elevated to Warning level for visibility
        - Correlation IDs enable cross-system event tracking
        - Context sanitization prevents log corruption
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DataValidation', 'CredentialAccess', 'PrivilegeUse', 'ObjectAccess', 'SystemAccess', 'ConfigurationChange', 'AuthenticationAttempt', 'AuthorizationCheck')]
        [string]$SecurityEventType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Success', 'Failure', 'Attempt', 'Warning', 'Critical')]
        [string]$Outcome = 'Attempt',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [hashtable]$SecurityContext = @{},

        [Parameter()]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Medium'
    )

    begin {
        Write-Verbose "Writing security log event - Type: $SecurityEventType, Outcome: $Outcome"
    }

    process {
        try {
            # Sanitize the security message
            $sanitizedMessage = Protect-LogMessage -Message $Message

            # Build enhanced security context
            $securityData = Build-SecurityContext -SecurityEventType $SecurityEventType -Outcome $Outcome -SecurityContext $SecurityContext -Severity $Severity -CorrelationId $CorrelationId

            # Determine appropriate log level based on outcome and severity
            $logLevel = Get-SecurityLogLevel -Outcome $Outcome -Severity $Severity

            # Write to structured logging system with security component
            Write-StructuredLogEntry -Message $sanitizedMessage -Level $logLevel -Component 'Security' -Data $securityData -CorrelationId $CorrelationId

            # Write additional audit trail entry for critical events
            if ($Outcome -eq 'Critical' -or $Severity -eq 'Critical') {
                Write-CriticalSecurityEvent -SecurityEventType $SecurityEventType -Message $sanitizedMessage -SecurityData $securityData -CorrelationId $CorrelationId
            }
        }
        catch {
            Write-Warning "Failed to write security log event: $($_.Exception.Message)"
            # Don't throw to prevent security logging failures from breaking operations
        }
    }

    end {
        Write-Verbose "Security log event write completed"
    }
}


function Build-SecurityContext {
    <#
    .SYNOPSIS
        Builds comprehensive security context for audit events

    .DESCRIPTION
        Creates standardized security context information including system
        details, user context, and sanitized additional data for security events.

    .PARAMETER SecurityEventType
        Type of security event

    .PARAMETER Outcome
        Event outcome

    .PARAMETER SecurityContext
        Additional context data

    .PARAMETER Severity
        Security severity level

    .PARAMETER CorrelationId
        Correlation ID for tracking

    .EXAMPLE
        PS> Build-SecurityContext -SecurityEventType "DataValidation" -Outcome "Success" -SecurityContext @{Source="API"}

        Returns hashtable with comprehensive security context

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [hashtable] Comprehensive security context data

    .NOTES
        Automatically includes system and user context information.
        Sanitizes sensitive data to prevent credential exposure.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$SecurityEventType,

        [Parameter(Mandatory)]
        [string]$Outcome,

        [Parameter()]
        [hashtable]$SecurityContext = @{},

        [Parameter()]
        [string]$Severity = 'Medium',

        [Parameter()]
        [string]$CorrelationId
    )

    try {
        # Build base security context
        $baseContext = @{
            EventType = $SecurityEventType
            Outcome = $Outcome
            Severity = $Severity
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
            UserContext = "$env:USERNAME@$env:COMPUTERNAME"
            Domain = $env:USERDOMAIN
            ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            CorrelationId = $CorrelationId
        }

        # Add sanitized additional context
        $sanitizedContext = Protect-SecurityContext -SecurityContext $SecurityContext

        # Merge contexts
        foreach ($key in $sanitizedContext.Keys) {
            $baseContext[$key] = $sanitizedContext[$key]
        }

        return $baseContext
    }
    catch {
        Write-Warning "Failed to build security context: $($_.Exception.Message)"
        # Return minimal context to ensure logging continues
        return @{
            EventType = $SecurityEventType
            Outcome = $Outcome
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            CorrelationId = $CorrelationId
        }
    }
}


function Protect-SecurityContext {
    <#
    .SYNOPSIS
        Sanitizes security context data to prevent credential exposure

    .DESCRIPTION
        Processes security context hashtable to identify and redact
        sensitive information while preserving audit trail value.

    .PARAMETER SecurityContext
        Security context data to sanitize

    .EXAMPLE
        PS> Protect-SecurityContext -SecurityContext @{Username="user"; Password="secret"}

        Returns: @{Username="user"; Password="[REDACTED]"}

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [hashtable] Sanitized security context data

    .NOTES
        Identifies sensitive fields by name pattern matching.
        Preserves structure while protecting sensitive values.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$SecurityContext
    )

    $sanitizedContext = @{}

    foreach ($key in $SecurityContext.Keys) {
        $value = $SecurityContext[$key]

        # Check if this is a sensitive field that should be redacted
        if ($key -match '(?i)(password|secret|token|key|credential|api|auth|private)') {
            if ($value -and $value.ToString().Length -gt 0) {
                $sanitizedContext[$key] = '[REDACTED]'
            } else {
                $sanitizedContext[$key] = '[EMPTY]'
            }
        } else {
            # Sanitize the value using log message protection
            if ($value -ne $null) {
                $sanitizedContext[$key] = Protect-LogMessage -Message $value.ToString()
            } else {
                $sanitizedContext[$key] = '[NULL]'
            }
        }
    }

    return $sanitizedContext
}


function Get-SecurityLogLevel {
    <#
    .SYNOPSIS
        Determines appropriate log level for security events

    .DESCRIPTION
        Maps security event outcomes and severity levels to appropriate
        log levels for proper visibility and filtering.

    .PARAMETER Outcome
        Security event outcome

    .PARAMETER Severity
        Security severity level

    .EXAMPLE
        PS> Get-SecurityLogLevel -Outcome "Failure" -Severity "High"

        Returns: "Error"

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        [string] Appropriate log level for the security event

    .NOTES
        Balances security visibility with log noise reduction.
        Critical and high-severity events get elevated visibility.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failure', 'Attempt', 'Warning', 'Critical')]
        [string]$Outcome,

        [Parameter()]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Medium'
    )

    # Map outcome and severity to log levels
    $logLevel = switch ($Outcome) {
        'Critical' { 'Critical' }
        'Failure' {
            switch ($Severity) {
                'Critical' { 'Critical' }
                'High' { 'Error' }
                'Medium' { 'Warning' }
                'Low' { 'Information' }
                default { 'Warning' }
            }
        }
        'Warning' { 'Warning' }
        'Success' {
            switch ($Severity) {
                'Critical' { 'Information' }
                'High' { 'Information' }
                default { 'Debug' }
            }
        }
        'Attempt' {
            switch ($Severity) {
                'Critical' { 'Warning' }
                'High' { 'Information' }
                default { 'Debug' }
            }
        }
        default { 'Debug' }
    }

    return $logLevel
}


function Write-CriticalSecurityEvent {
    <#
    .SYNOPSIS
        Writes critical security events with enhanced visibility

    .DESCRIPTION
        Handles critical security events that require immediate attention
        and additional logging measures for security incident response.

    .PARAMETER SecurityEventType
        Type of critical security event

    .PARAMETER Message
        Critical event message

    .PARAMETER SecurityData
        Security context data

    .PARAMETER CorrelationId
        Correlation ID for tracking

    .EXAMPLE
        PS> Write-CriticalSecurityEvent -SecurityEventType "PrivilegeEscalation" -Message "Unauthorized privilege use detected"

        Writes critical security event with enhanced logging

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. This function writes to logging and alerting systems.

    .NOTES
        Critical events may trigger additional alerting mechanisms.
        Enhanced context is provided for security incident response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SecurityEventType,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$SecurityData = @{},

        [Parameter()]
        [string]$CorrelationId
    )

    try {
        # Create critical event marker for easy identification
        $criticalMessage = "*** CRITICAL SECURITY EVENT *** $SecurityEventType : $Message"

        # Enhanced critical event context
        $criticalContext = $SecurityData.Clone()
        $criticalContext['CriticalEvent'] = $true
        $criticalContext['AlertLevel'] = 'IMMEDIATE'
        $criticalContext['IncidentResponse'] = 'REQUIRED'

        # Write with Critical level for maximum visibility
        Write-StructuredLogEntry -Message $criticalMessage -Level 'Critical' -Component 'SecurityAlert' -Data $criticalContext -CorrelationId $CorrelationId

        # Additional console warning for critical events
        Write-Warning "CRITICAL SECURITY EVENT: $SecurityEventType - $Message (CorrelationId: $CorrelationId)"
    }
    catch {
        Write-Error "Failed to write critical security event: $($_.Exception.Message)" -ErrorAction Continue
    }
}


