#Requires -Version 5.1

<#
.SYNOPSIS
    ACL application module for Active Directory object ACL modifications

.DESCRIPTION
    Provides focused ACL application functionality for safely applying modified
    ACLs to Active Directory objects. This module implements the "tool" pattern
    with proper error handling, retry logic, and comprehensive validation.

    This module focuses solely on ACL application to AD objects, enabling
    independent testing and reuse across different modification scenarios.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For ACL application failures: .\Troubleshooting\Common\ACL-Application-Issues.md
    - For AD connectivity issues: .\Troubleshooting\Common\AD-Connection-Issues.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Requires Operations\Invoke-ADOperationWithRetry.ps1 for retry logic
    - Active Directory PowerShell module for Set-Acl cmdlet
#>

function Set-ModifiedACL {
    <#
    .SYNOPSIS
        Safely applies modified ACL to Active Directory objects

    .DESCRIPTION
        Applies ACL changes to AD objects with comprehensive validation, retry logic,
        and proper error handling. This function implements the "tool" pattern for
        focused ACL application with enterprise-grade reliability.

        The function includes:
        - Parameter validation before AD operations
        - Retry logic for transient AD failures
        - ShouldProcess support for WhatIf scenarios
        - Comprehensive logging with correlation tracking

    .PARAMETER ACL
        The modified Active Directory security descriptor to apply.
        Must be a valid System.DirectoryServices.ActiveDirectorySecurity object
        containing the desired ACL configuration.

    .PARAMETER ObjectDN
        Distinguished name of the target Active Directory object.
        Object must exist and be accessible with current credentials.

    .PARAMETER CorrelationId
        Unique identifier for tracking this ACL application operation
        across logs and audit trails. Generated automatically if not provided.

    .EXAMPLE
        PS> Set-ModifiedACL -ACL $modifiedAcl -ObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com"

        DESCRIPTION: Applies a modified ACL to a user object
        OUTPUT: Boolean indicating success (True) or failure (False)
        USE CASE: Basic ACL application after SID removal operations

    .EXAMPLE
        PS> $success = Set-ModifiedACL -ACL $acl -ObjectDN $dn -CorrelationId $correlationId
        if ($success) {
            Write-Output "ACL applied successfully"
        }

        DESCRIPTION: Programmatic ACL application with result validation
        OUTPUT: Boolean result for conditional processing
        USE CASE: Automation workflows with error handling

    .EXAMPLE
        PS> Set-ModifiedACL -ACL $acl -ObjectDN $dn -WhatIf

        DESCRIPTION: Preview mode showing what ACL would be applied
        OUTPUT: False (no changes made) with detailed logging
        USE CASE: Validation and approval workflows

    .OUTPUTS
        [bool] True if ACL was successfully applied, False otherwise.
        Detailed status information is available through structured logging.

    .NOTES
        RELIABILITY FEATURES:
        - Parameter validation before AD operations
        - Retry logic with exponential backoff for transient failures
        - Comprehensive error handling and logging
        - ShouldProcess support for safe operations

        PERFORMANCE CHARACTERISTICS:
        - Application Time: 100-500ms per object typically
        - Retry Logic: Up to 3 attempts with backoff
        - Memory Usage: Minimal - direct ACL application

        SECURITY CONSIDERATIONS:
        - Requires appropriate AD permissions for ACL modification
        - All operations logged with correlation IDs for audit trails
        - Validates ACL structure before application

        TROUBLESHOOTING:
        - For permission errors: Verify AD modification rights
        - For connectivity issues: Check AD server availability
        - For validation failures: Ensure ACL object integrity
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.DirectoryServices.ActiveDirectorySecurity]$ACL,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Starting ACL application to $ObjectDN" -Level Verbose -Component 'ACLApplication' -CorrelationId $CorrelationId

        # Validate ACL parameter before processing
        if (-not $ACL -or $ACL.Access.Count -eq 0) {
            throw "ACL parameter must contain access rules"
        }

        # Validate ObjectDN parameter
        if ([string]::IsNullOrWhiteSpace($ObjectDN.Trim())) {
            throw "ObjectDN parameter cannot be empty or whitespace"
        }

        Write-StructuredLog "ACL contains $($ACL.Access.Count) access rules for application" -Level Debug -Component 'ACLApplication' -CorrelationId $CorrelationId

        if ($PSCmdlet.ShouldProcess($ObjectDN, "Apply modified ACL")) {
            # Use retry logic for reliable AD operations
            Invoke-ADOperationWithRetry -ScriptBlock {
                Set-Acl -Path "AD:\$($ObjectDN.Trim())" -AclObject $ACL -ErrorAction Stop
            } -MaxRetries 3 -OperationName 'Set-ACL' -ObjectContext $ObjectDN

            Write-StructuredLog "Successfully applied ACL changes to $ObjectDN" -Level Verbose -Component 'ACLApplication' -CorrelationId $CorrelationId
            return $true
        }
        else {
            Write-StructuredLog "ACL modification skipped due to WhatIf mode for $ObjectDN" -Level Verbose -Component 'ACLApplication' -CorrelationId $CorrelationId
            return $false
        }
    }
    catch {
        Write-StructuredLog "Failed to apply ACL changes to $ObjectDN : $($_.Exception.Message)" -Level Error -Component 'ACLApplication' -CorrelationId $CorrelationId
        return $false
    }
}

Write-StructuredLog "ACL application module loaded successfully" -Level Debug -Component 'ACLApplication' -CorrelationId $([System.Guid]::NewGuid().ToString())
