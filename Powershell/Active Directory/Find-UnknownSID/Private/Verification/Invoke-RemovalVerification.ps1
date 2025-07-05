#Requires -Version 5.1

<#
.SYNOPSIS
    Post-operation verification module for SID removal operations

.DESCRIPTION
    Provides focused verification functionality to confirm that SID removal
    operations were successful. This module implements the "tool" pattern
    for reliable post-operation validation with comprehensive error handling.

    This module focuses solely on verification logic, enabling independent
    testing and reuse across different removal and validation scenarios.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For verification failures: .\Troubleshooting\Common\Verification-Issues.md
    - For AD replication delays: .\Troubleshooting\Common\AD-Replication-Issues.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Requires Operations\Invoke-ADOperationWithRetry.ps1 for retry logic
    - Active Directory PowerShell module for Get-Acl cmdlet
#>

function Invoke-RemovalVerification {
    <#
    .SYNOPSIS
        Verifies successful completion of SID removal operations

    .DESCRIPTION
        Performs comprehensive post-removal verification by checking that specified
        SIDs are no longer present in the Active Directory object's ACL. This function
        implements the "tool" pattern for focused verification with enterprise reliability.

        The verification process includes:
        - AD replication delay accommodation
        - Retry logic for transient failures
        - Comprehensive result reporting
        - Detailed logging with correlation tracking

    .PARAMETER ObjectDN
        Distinguished name of the Active Directory object to verify.
        Object must exist and be accessible with current credentials.

    .PARAMETER AllowedSIDs
        Array of Security Identifiers that should have been removed.
        Verification checks that none of these SIDs remain in the ACL.

    .PARAMETER CorrelationId
        Unique identifier for tracking this verification operation
        across logs and audit trails. Generated automatically if not provided.

    .EXAMPLE
        PS> $result = Invoke-RemovalVerification -ObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com" -AllowedSIDs @("S-1-5-21-1234567890-1001")

        DESCRIPTION: Verifies that a single SID was successfully removed
        OUTPUT: PSCustomObject with Success status and verification details
        USE CASE: Basic verification after targeted SID removal

    .EXAMPLE
        PS> $verification = Invoke-RemovalVerification -ObjectDN $dn -AllowedSIDs $removedSIDs -CorrelationId $id
        if ($verification.Success) {
            Write-Output "All SIDs successfully removed"
        } else {
            Write-Warning "Verification failed: $($verification.ErrorMessage)"
        }

        DESCRIPTION: Comprehensive verification with result handling
        OUTPUT: Structured verification results for automation
        USE CASE: Enterprise automation with conditional processing

    .OUTPUTS
        [PSCustomObject] Object containing:
        - Success: Boolean indicating overall verification success
        - ErrorMessage: Detailed error information if verification fails
        - RemainingOrphanedSIDs: Array of SIDs that remain in the ACL

    .NOTES
        RELIABILITY FEATURES:
        - AD replication delay accommodation (500ms pause)
        - Retry logic for transient AD failures
        - Comprehensive error handling and logging
        - Detailed result reporting for troubleshooting

        PERFORMANCE CHARACTERISTICS:
        - Verification Time: 500ms+ per object (includes replication delay)
        - Retry Logic: Up to 3 attempts with backoff
        - Memory Usage: Minimal - focused ACL analysis

        VERIFICATION PROCESS:
        - Brief pause for AD replication consistency
        - Retrieve current ACL state from AD
        - Compare against expected removal list
        - Report any remaining orphaned SIDs

        TROUBLESHOOTING:
        - For remaining SIDs: Check AD replication and timing
        - For ACL access errors: Verify appropriate permissions
        - For verification timeouts: Consider network and AD performance
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDN,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AllowedSIDs,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Starting removal verification for $ObjectDN (Verifying $($AllowedSIDs.Count) SIDs)" -Level Debug -Component 'RemovalVerification' -CorrelationId $CorrelationId

        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($ObjectDN.Trim())) {
            throw "ObjectDN parameter cannot be empty or whitespace"
        }

        # Brief pause for AD replication consistency
        Start-Sleep -Milliseconds 500

        # Get current ACL for verification with retry logic
        $verificationACL = Invoke-ADOperationWithRetry -ScriptBlock {
            Get-Acl -Path "AD:\$($ObjectDN.Trim())" -ErrorAction Stop
        } -MaxRetries 3 -OperationName 'Get-ACL-Verification' -ObjectContext $ObjectDN

        # Check for remaining orphaned SIDs
        $remainingOrphanedSIDs = @()
        foreach ($ace in $verificationACL.Access) {
            if ($AllowedSIDs -contains $ace.IdentityReference.Value) {
                $remainingOrphanedSIDs += $ace.IdentityReference.Value
            }
        }

        # Prepare verification results
        if ($remainingOrphanedSIDs.Count -eq 0) {
            Write-StructuredLog "Verification successful: All $($AllowedSIDs.Count) SIDs removed from $ObjectDN" -Level Verbose -Component 'RemovalVerification' -CorrelationId $CorrelationId
            return [PSCustomObject]@{
                Success = $true
                ErrorMessage = $null
                RemainingOrphanedSIDs = @()
            }
        } else {
            $errorMessage = "Verification failed: $($remainingOrphanedSIDs.Count) of $($AllowedSIDs.Count) SIDs still present"
            Write-StructuredLog "Verification failed for $ObjectDN : $errorMessage" -Level Warning -Component 'RemovalVerification' -CorrelationId $CorrelationId
            return [PSCustomObject]@{
                Success = $false
                ErrorMessage = $errorMessage
                RemainingOrphanedSIDs = $remainingOrphanedSIDs
            }
        }
    }
    catch {
        $errorMessage = "Verification error: $($_.Exception.Message)"
        Write-StructuredLog "Verification error for $ObjectDN : $errorMessage" -Level Error -Component 'RemovalVerification' -CorrelationId $CorrelationId
        return [PSCustomObject]@{
            Success = $false
            ErrorMessage = $errorMessage
            RemainingOrphanedSIDs = @()
        }
    }
}

Write-StructuredLog "Removal verification module loaded successfully" -Level Debug -Component 'RemovalVerification' -CorrelationId $([System.Guid]::NewGuid().ToString())
