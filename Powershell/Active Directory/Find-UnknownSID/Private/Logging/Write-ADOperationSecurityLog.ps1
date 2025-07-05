function Write-ADOperationSecurityLog {
    <#
    .SYNOPSIS
        Writes security audit logs for Active Directory operations

    .DESCRIPTION
        Provides standardized security logging for AD operations including
        object access attempts, successes, and failures with proper audit trails.

    .PARAMETER OperationName
        Name of the AD operation being performed

    .PARAMETER Outcome
        Result of the operation (Attempt, Success, Failure)

    .PARAMETER SecurityContext
        Additional security context for audit trail

    .PARAMETER CorrelationId
        Unique identifier for tracking related operations

    .EXAMPLE
        PS> Write-ADOperationSecurityLog -OperationName 'Get-ADUser' -Outcome 'Success'

        DESCRIPTION: Logs successful AD user retrieval operation
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
        [string]$OperationName,

        [Parameter(Mandatory)]
        [ValidateSet('Attempt', 'Success', 'Failure')]
        [string]$Outcome,

        [Parameter()]
        [hashtable]$SecurityContext = @{},

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        # Build standardized security context
        $auditContext = @{
            OperationName = $OperationName
            Outcome = $Outcome
            Timestamp = Get-Date
            UserContext = "$env:USERNAME@$env:COMPUTERNAME"
            CorrelationId = $CorrelationId
            Component = 'ADOperations'
            SecurityEventType = 'ObjectAccess'
        }

        # Merge additional context
        foreach ($key in $SecurityContext.Keys) {
            $auditContext[$key] = $SecurityContext[$key]
        }

        # Write security log based on outcome
        switch ($Outcome) {
            'Attempt' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Attempting Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
            'Success' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Successfully completed Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
            'Failure' {
                Write-SecurityLog -SecurityEventType 'ObjectAccess' -Message "Failed Active Directory operation: $OperationName" -Outcome $Outcome -CorrelationId $CorrelationId -SecurityContext $auditContext
            }
        }
    }
}
