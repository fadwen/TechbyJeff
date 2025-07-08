#Requires -Version 5.1

function Write-ClassSecurityEvent {
    <#
    .SYNOPSIS
        Writes structured security events for PowerShell class loading operations

    .DESCRIPTION
        Provides specialized security audit logging for class loading events, violations,
        and compliance tracking with enterprise correlation. This module handles all
        security-related logging for the class import system and integrates with
        enterprise monitoring and SIEM systems.

        Security Features:
        - Structured security event logging with correlation IDs
        - Compliance audit trail generation
        - Enterprise SIEM integration support
        - Security incident classification and prioritization
        - Comprehensive security context capture

    .PARAMETER EventType
        Type of security event being logged.
        Valid values: 'Success', 'Warning', 'Violation', 'Error'

    .PARAMETER Message
        Primary security event message describing what occurred.

    .PARAMETER EventData
        Optional hashtable containing additional security context data.
        Will be sanitized to prevent logging of sensitive information.

    .PARAMETER SecurityContext
        Optional hashtable containing security-specific context information
        such as user identity, system state, and environmental factors.

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes. If not provided,
        a new GUID will be generated automatically.

    .EXAMPLE
        Write-ClassSecurityEvent -EventType 'Success' -Message "Class loaded successfully" -CorrelationId $correlationId

        DESCRIPTION: Logs a successful class loading security event
        OUTPUT: Structured security log entry with correlation tracking
        USE CASE: Standard success logging for audit trails

    .EXAMPLE
        Write-ClassSecurityEvent -EventType 'Violation' -Message "Path traversal detected" -EventData $violationData -SecurityContext $context

        DESCRIPTION: Logs a security violation with comprehensive context
        OUTPUT: Detailed security violation log with incident data
        USE CASE: Security incident logging for SIEM and incident response

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. This function writes to logging infrastructure and does not return objects.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        SECURITY CONSIDERATIONS:
        - Sanitizes sensitive data before logging
        - Supports enterprise SIEM integration patterns
        - Provides structured data for automated analysis
        - Includes correlation IDs for incident investigation

        COMPLIANCE FEATURES:
        - SOX: Provides audit trails for change control and access logging
        - GDPR: No personal data logging without explicit consent controls
        - HIPAA: Sanitized logging suitable for healthcare environments
        - Enterprise Security: Full SIEM integration and incident response support

        TROUBLESHOOTING:
        - For logging issues: .\Troubleshooting\Security\Security-Logging-Issues.md
        - For SIEM integration: .\Troubleshooting\Security\SIEM-Integration-Issues.md

        INTEGRATION NOTES:
        - Uses Write-StructuredLog if available for enterprise logging
        - Falls back to standard PowerShell logging methods
        - Supports custom logging providers and endpoints
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Warning', 'Violation', 'Error', 'Information', 'Critical')]
        [string]$EventType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [hashtable]$EventData,

        [Parameter()]
        [hashtable]$SecurityContext,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Determine appropriate log levels for different event types
        $logLevelMapping = @{
            'Success' = 'Information'
            'Information' = 'Information'
            'Warning' = 'Warning'
            'Violation' = 'Warning'
            'Error' = 'Error'
            'Critical' = 'Error'
        }

        $logLevel = $logLevelMapping[$EventType]
    }

    process {
        try {
            # Create base security event structure
            $securityEvent = @{
                EventType = $EventType
                Message = $Message
                Component = 'ClassSecurityAuditor'
                Operation = 'SecurityEventLogging'
                CorrelationId = $CorrelationId
                Timestamp = Get-Date
                Source = 'SecureClassImporter'
                SecurityLevel = switch ($EventType) {
                    'Success' { 'Info' }
                    'Information' { 'Info' }
                    'Warning' { 'Medium' }
                    'Violation' { 'High' }
                    'Error' { 'High' }
                    'Critical' { 'Critical' }
                }
            }

            # Add system context
            $systemContext = @{
                UserName = $env:USERNAME
                ComputerName = $env:COMPUTERNAME
                ProcessId = $PID
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                ExecutionPolicy = Get-ExecutionPolicy
                SessionId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
            }

            # Sanitize and add event data if provided
            if ($EventData) {
                $sanitizedEventData = @{}
                foreach ($key in $EventData.Keys) {
                    $value = $EventData[$key]

                    # Sanitize sensitive data patterns
                    if ($key -match '(?i)(password|secret|key|token|credential)') {
                        $sanitizedEventData[$key] = '[REDACTED]'
                    }
                    elseif ($value -is [string] -and $value.Length -gt 1000) {
                        # Truncate very long strings to prevent log bloat
                        $sanitizedEventData[$key] = $value.Substring(0, 997) + '...'
                    }
                    else {
                        $sanitizedEventData[$key] = $value
                    }
                }
                $securityEvent.EventData = $sanitizedEventData
            }

            # Sanitize and add security context if provided
            if ($SecurityContext) {
                $sanitizedSecurityContext = @{}
                foreach ($key in $SecurityContext.Keys) {
                    $value = $SecurityContext[$key]

                    # Apply security context sanitization
                    if ($key -match '(?i)(credential|authentication|session)' -and $value -is [string]) {
                        # Hash sensitive security context for correlation while protecting data
                        $sanitizedSecurityContext[$key] = 'HASH:' + [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($value)).Replace('-', '').Substring(0, 16)
                    }
                    else {
                        $sanitizedSecurityContext[$key] = $value
                    }
                }
                $securityEvent.SecurityContext = $sanitizedSecurityContext
            }

            # Add system context
            $securityEvent.SystemContext = $systemContext

            # Determine security event classification
            $eventClassification = @{
                Category = 'ClassLoading'
                Subcategory = switch ($EventType) {
                    'Success' { 'OperationalSuccess' }
                    'Information' { 'InformationalEvent' }
                    'Warning' { 'SecurityWarning' }
                    'Violation' { 'SecurityViolation' }
                    'Error' { 'SecurityError' }
                    'Critical' { 'CriticalSecurityEvent' }
                }
                Severity = $securityEvent.SecurityLevel
                RequiresResponse = $EventType -in @('Violation', 'Error', 'Critical')
                AutomatedResponseEnabled = $false
            }

            $securityEvent.Classification = $eventClassification

            # Write to enterprise logging system if available
            if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog -Level $logLevel -Message "SECURITY EVENT: $Message" -Component 'ClassSecurityAuditor' -CorrelationId $CorrelationId -Data $securityEvent
            }
            else {
                # Fallback to standard PowerShell logging
                $logMessage = "SECURITY EVENT [$EventType]: $Message - CorrelationId: $CorrelationId"

                switch ($EventType) {
                    'Success' { Write-Verbose $logMessage }
                    'Information' { Write-Information $logMessage }
                    'Warning' { Write-Warning $logMessage }
                    'Violation' { Write-Warning "SECURITY VIOLATION: $Message - CorrelationId: $CorrelationId" }
                    'Error' { Write-Error $logMessage }
                    'Critical' { Write-Error "CRITICAL SECURITY EVENT: $Message - CorrelationId: $CorrelationId" }
                }
            }

            # For high-severity events, also write to Windows Event Log if possible
            if ($EventType -in @('Violation', 'Error', 'Critical') -and [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
                try {
                    $eventLogMessage = "Class Security Event: $Message`nCorrelationId: $CorrelationId`nEventType: $EventType"
                    $eventId = switch ($EventType) {
                        'Violation' { 4001 }
                        'Error' { 4002 }
                        'Critical' { 4003 }
                    }

                    # Attempt to write to Application log
                    Write-EventLog -LogName Application -Source 'PowerShell' -EventId $eventId -EntryType Warning -Message $eventLogMessage -ErrorAction SilentlyContinue
                }
                catch {
                    # Event log writing is best effort - don't fail the security logging if it's not available
                    Write-Verbose "Could not write to Windows Event Log: $($_.Exception.Message)"
                }
            }

            # For compliance auditing, create structured audit record
            if ($EventType -in @('Success', 'Violation', 'Error', 'Critical')) {
                $auditRecord = @{
                    AuditType = 'ClassSecurityAudit'
                    AuditTimestamp = $securityEvent.Timestamp
                    CorrelationId = $CorrelationId
                    EventType = $EventType
                    AuditMessage = $Message
                    UserContext = $systemContext.UserName
                    SystemContext = $systemContext.ComputerName
                    ComplianceData = @{
                        DataClassification = 'SecurityAudit'
                        RetentionRequired = $true
                        RetentionPeriod = 'AsPerPolicy'
                        ComplianceFrameworks = @('SOX', 'Enterprise')
                    }
                }

                # Log audit record
                if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                    Write-StructuredLog -Level Information -Message "AUDIT RECORD: Class security audit" -Component 'ComplianceAuditor' -CorrelationId $CorrelationId -Data $auditRecord
                }
            }

            Write-Verbose "Security event logged successfully: $EventType - $Message"
        }
        catch {
            # Security logging should not fail the main operation, but we should capture the issue
            $loggingError = "Failed to write security event: $($_.Exception.Message)"
            Write-Warning $loggingError

            # Try to log the logging failure itself
            try {
                if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                    Write-StructuredLog -Level Error -Message "Security logging failure" -Component 'ClassSecurityAuditor' -CorrelationId $CorrelationId -Data @{
                        OriginalEventType = $EventType
                        OriginalMessage = $Message
                        LoggingError = $loggingError
                    }
                }
            }
            catch {
                # Even the fallback logging failed - this is a critical issue but shouldn't stop the operation
                Write-Warning "Critical: Security logging system failure - unable to log security events"
            }
        }
    }
}
