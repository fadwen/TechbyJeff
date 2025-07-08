#Requires -Version 5.1

<#
.SYNOPSIS
    ACL retrieval module for Active Directory object security descriptors

.DESCRIPTION
    Provides focused ACL retrieval functionality with enterprise-grade retry logic
    and error handling. This module implements the "tool" pattern for reliable
    ACL retrieval operations from Active Directory objects.

    This module focuses solely on ACL retrieval, enabling independent testing
    and reuse across different removal and modification scenarios.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For ACL retrieval failures: .\Troubleshooting\Common\ACL-Retrieval-Issues.md
    - For AD connectivity issues: .\Troubleshooting\Common\AD-Connection-Issues.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Requires Operations\Invoke-ADOperationWithRetry.ps1 for retry logic
    - Active Directory PowerShell module for Get-Acl cmdlet
#>

function Get-ACLForRemoval {
    <#
    .SYNOPSIS
        Retrieves ACL from Active Directory objects with retry logic

    .DESCRIPTION
        Safely retrieves Active Directory ACL objects with comprehensive error
        handling and retry logic for enterprise reliability. This function
        implements the "tool" pattern for focused ACL retrieval operations.

        The function includes:
        - Retry logic for transient AD failures
        - Parameter validation and error handling
        - Comprehensive logging with correlation tracking
        - Optimized for removal operation workflows

    .PARAMETER ObjectDistinguishedName
        Distinguished name of the Active Directory object to retrieve ACL from.
        Object must exist and be accessible with current credentials.

    .PARAMETER CorrelationId
        Unique identifier for tracking this ACL retrieval operation
        across logs and audit trails. Generated automatically if not provided.

    .EXAMPLE
        PS> $acl = Get-ACLForRemoval -ObjectDistinguishedName "CN=TestUser,CN=Users,DC=contoso,DC=com"

        DESCRIPTION: Retrieves ACL from a user object
        OUTPUT: System.DirectoryServices.ActiveDirectorySecurity object
        USE CASE: Basic ACL retrieval for removal operations

    .EXAMPLE
        PS> $acl = Get-ACLForRemoval -ObjectDistinguishedName $dn -CorrelationId $correlationId
        if ($acl) {
            Write-Output "Retrieved ACL with $($acl.Access.Count) access rules"
        }

        DESCRIPTION: ACL retrieval with correlation tracking and validation
        OUTPUT: ACL object ready for modification operations
        USE CASE: Enterprise automation with audit trail requirements

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectorySecurity] Active Directory ACL object
        ready for modification operations, or $null if retrieval fails.

    .NOTES
        RELIABILITY FEATURES:
        - Retry logic with exponential backoff for transient failures
        - Comprehensive parameter validation
        - Detailed error handling and logging
        - Optimized for removal operation workflows

        PERFORMANCE CHARACTERISTICS:
        - Retrieval Time: 50-200ms per object typically
        - Retry Logic: Up to 3 attempts with backoff
        - Memory Usage: Minimal - direct ACL retrieval

        SECURITY CONSIDERATIONS:
        - Requires appropriate AD permissions for ACL reading
        - All operations logged with correlation IDs for audit trails
        - Validates object existence before ACL retrieval

        TROUBLESHOOTING:
        - For permission errors: Verify AD read rights
        - For connectivity issues: Check AD server availability
        - For object not found: Verify DN format and object existence
    #>

    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectorySecurity])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDistinguishedName,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Starting ACL retrieval for $ObjectDistinguishedName" -Level Debug -CorrelationId $CorrelationId

        # Validate ObjectDistinguishedName parameter
        if ([string]::IsNullOrWhiteSpace($ObjectDistinguishedName.Trim())) {
            throw "ObjectDistinguishedName parameter cannot be empty or whitespace"
        }

        # Security validation - detect path traversal attempts
        if ($ObjectDistinguishedName -match '\.\.') {
            throw "Path traversal detected in ObjectDistinguishedName: $ObjectDistinguishedName"
        }

        # Validate ObjectDistinguishedName format (basic validation for AD DN format)
        if ($ObjectDistinguishedName -match '^[A-Za-z]:\\' -and $ObjectDistinguishedName -notmatch '^CN=|^OU=|^DC=') {
            throw "Invalid ObjectDistinguishedName format. Expected AD Distinguished Name, got filesystem path: $ObjectDistinguishedName"
        }

        # Check if target object exists
        if (-not (Test-ValidDistinguishedName -DistinguishedName $ObjectDistinguishedName -CorrelationId $CorrelationId)) {
            throw "Target path not found: $ObjectDistinguishedName"
        }

        # Retrieve ACL with retry logic for reliability
        $acl = Invoke-ADOperationWithRetry -ScriptBlock {
            Get-Acl -Path "AD:\$($ObjectDistinguishedName.Trim())" -ErrorAction Stop
        } -MaxRetries 3 -OperationName 'Get-ACL' -ObjectContext $ObjectDistinguishedName

        if (-not $acl) {
            throw "Failed to retrieve ACL for $ObjectDistinguishedName"
        }

        Write-StructuredLog "Successfully retrieved ACL for $ObjectDistinguishedName (Access rules: $($acl.Access.Count))" -Level Verbose -CorrelationId $CorrelationId
        return $acl
    }
    catch {
        Write-StructuredLog "Failed to retrieve ACL for $ObjectDistinguishedName : $($_.Exception.Message)" -Level Error -CorrelationId $CorrelationId
        throw
    }
}

Write-StructuredLog "ACL retrieval module loaded successfully" -Level Debug -CorrelationId $([System.Guid]::NewGuid().ToString())


