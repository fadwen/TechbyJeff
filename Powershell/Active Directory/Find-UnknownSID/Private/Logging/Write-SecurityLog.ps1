function Write-SecurityLog {
    <#
    .SYNOPSIS
        Writes security audit log entries for compliance and monitoring

    .DESCRIPTION
        Provides standardized security event logging with proper audit trails,
        security context tracking, and correlation IDs for compliance requirements.

    .PARAMETER SecurityEventType
        Type of security event being logged (ObjectAccess, Authentication, Authorization, etc.)

    .PARAMETER Message
        Descriptive message for the security event

    .PARAMETER Outcome
        Result of the security operation (Attempt, Success, Failure)

    .PARAMETER SecurityContext
        Additional security context information for audit trail

    .PARAMETER CorrelationId
        Unique identifier for tracking related operations

    .EXAMPLE
        PS> Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message 'AD user access attempt' -Outcome 'Success'

        DESCRIPTION: Logs successful AD object access operation
        OUTPUT: Security log entry with audit trail
        USE CASE: Compliance and security monitoring

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For logging configuration: .\Troubleshooting\Security\Audit-Configuration.md
        - For compliance requirements: .\Troubleshooting\Security\Compliance-Guide.md
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecurityEventType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Attempt', 'Success', 'Failure')]
        [string]$Outcome,

        [Parameter()]
        [hashtable]$SecurityContext = @{},

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        # Build comprehensive security log entry
        $securityLogEntry = @{
            Timestamp = Get-Date
            SecurityEventType = $SecurityEventType
            Outcome = $Outcome
            Message = $Message
            UserContext = "$env:USERNAME@$env:COMPUTERNAME"
            ProcessId = $PID
            CorrelationId = $CorrelationId
            Component = 'SecurityAudit'
        }

        # Merge additional security context
        foreach ($key in $SecurityContext.Keys) {
            $securityLogEntry["Security_$key"] = $SecurityContext[$key]
        }

        # Determine log level based on outcome
        $logLevel = switch ($Outcome) {
            'Attempt' { 'Information' }
            'Success' { 'Information' }
            'Failure' { 'Warning' }
            default { 'Information' }
        }

        # Format security message with audit identifiers
        $auditMessage = "[$SecurityEventType] [$Outcome] $Message"

        try {
            # Write to security-specific structured log system (bypasses log level filtering)
            Write-SecurityStructuredLogEntry -Level $logLevel -Component 'SecurityAudit' -Message $auditMessage -CorrelationId $CorrelationId -Data $securityLogEntry

            # Also write to verbose stream for immediate visibility during security operations
            Write-Verbose "SECURITY AUDIT: $auditMessage (CorrelationId: $CorrelationId)"

        } catch {
            # Fallback logging if structured logging fails - security events must be captured
            Write-Warning "Security log entry failed: $($_.Exception.Message) - Event: $auditMessage"

            # Try direct file append as last resort for critical security events
            try {
                $fallbackEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [SecurityAudit] [$logLevel] $auditMessage (CorrelationId: $CorrelationId)"
                $fallbackEntry | Out-File -FilePath "$env:TEMP\Find-UnknownSID-Security-Fallback.log" -Append -Encoding UTF8
            } catch {
                Write-Error "Critical: Unable to write security audit log entry: $auditMessage"
            }
        }
    }
}
