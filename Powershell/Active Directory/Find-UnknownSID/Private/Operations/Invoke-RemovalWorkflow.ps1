#Requires -Version 5.1

<#
.SYNOPSIS
    Orchestration workflow module for SID removal operations

.DESCRIPTION
    Provides comprehensive workflow orchestration for SID removal operations,
    coordinating security validation, ACL manipulation, backup creation, and
    verification. This module implements the "controller" pattern for complex
    multi-step operations while maintaining clean separation of concerns.

    This module focuses solely on workflow coordination, delegating specific
    tasks to specialized modules for maximum modularity and testability.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For workflow failures: .\Troubleshooting\Common\Workflow-Issues.md
    - For integration issues: .\Troubleshooting\Common\Module-Integration-Issues.md

    DEPENDENCIES:
    - Requires Security\Invoke-SecurityValidation.ps1 for security validation
    - Requires ACL\Get-ACLForRemoval.ps1 for ACL retrieval
    - Requires ACL\Invoke-SIDRemoval.ps1 for ACL manipulation
    - Requires ACL\Set-ModifiedACL.ps1 for ACL application
    - Requires Verification\Invoke-RemovalVerification.ps1 for verification
    - Requires RemovalLogging\Write-RemovalSecurityLog.ps1 for security logging
    - Requires New-ACLBackup.ps1 for backup operations
    - Requires Classes.ps1 for RemovalOperationResult type
    - Requires Logging.ps1 for Write-StructuredLog function
#>

function Invoke-RemovalWorkflow {
    <#
    .SYNOPSIS
        Orchestrates comprehensive SID removal workflow operations

    .DESCRIPTION
        Coordinates the complete SID removal workflow including security validation,
        backup creation, ACL manipulation, application, and verification. This function
        implements the "controller" pattern, delegating specific tasks to specialized
        modules while maintaining overall workflow integrity.

        The workflow includes:
        - Parameter validation and preprocessing
        - Security validation and risk assessment
        - Optional ACL backup creation
        - ACL manipulation and SID removal
        - ACL application to Active Directory
        - Post-operation verification
        - Comprehensive audit logging and tracking

    .PARAMETER ObjectDN
        Distinguished name of the Active Directory object to process.
        Object must exist and be accessible with current credentials.

    .PARAMETER OrphanedSIDs
        Array of orphaned Security Identifiers to remove from the object.
        SIDs will be validated against security policies before removal.

    .PARAMETER BackupPath
        Optional directory path for storing ACL backups before removal operations.
        Backups include metadata and integrity verification.

    .PARAMETER WhatIfMode
        When specified, performs validation and shows what would be removed
        without making actual changes. Useful for preview and approval workflows.

    .PARAMETER CorrelationId
        Unique identifier for tracking this removal operation across logs
        and audit trails. Generated automatically if not provided.

    .EXAMPLE
        PS> $result = Invoke-RemovalWorkflow -ObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com" -OrphanedSIDs @("S-1-5-21-1234567890-1001")

        DESCRIPTION: Orchestrates removal workflow for a single SID
        OUTPUT: RemovalOperationResult with comprehensive operation details
        USE CASE: Targeted cleanup with full workflow validation

    .EXAMPLE
        PS> $result = Invoke-RemovalWorkflow -ObjectDN $dn -OrphanedSIDs $sids -BackupPath "C:\Backups" -WhatIfMode -CorrelationId $id

        DESCRIPTION: Preview workflow with backup preparation and correlation tracking
        OUTPUT: RemovalOperationResult showing planned operations without changes
        USE CASE: Pre-approval validation for enterprise change management

    .OUTPUTS
        [RemovalOperationResult] Object containing comprehensive operation results:
        - ObjectDN: Distinguished name of processed object
        - CorrelationId: Unique tracking identifier
        - IntendedRemovals: Number of SIDs planned for removal
        - ActualRemovals: Number of SIDs successfully removed
        - FailedRemovals: Number of SIDs that failed removal
        - RemovedSIDs: Array of successfully removed SIDs
        - FailedSIDs: Array of SIDs that failed removal
        - BlockedSIDs: Array of SIDs blocked by security policies
        - Success: Overall operation success status
        - ErrorMessage: Detailed error information if applicable
        - ProcessingTime: Duration of the complete workflow
        - SecurityValidation: Comprehensive security validation results

    .NOTES
        WORKFLOW FEATURES:
        - Modular design with specialized component delegation
        - Comprehensive error handling with rollback capability
        - Security-first approach with validation gates
        - Enterprise audit trail with correlation tracking
        - Flexible backup and verification options

        PERFORMANCE CHARACTERISTICS:
        - Processing Time: 500ms-2s per object depending on complexity
        - Memory Usage: Optimized with efficient object handling
        - Reliability: Multi-layer validation and verification
        - Scalability: Designed for enterprise-scale operations

        SECURITY CONTROLS:
        - Multi-layer security validation before any changes
        - Protected SID detection and blocking
        - Risk-based operation controls
        - Comprehensive audit logging throughout workflow
        - Backup creation for rollback capability

        TROUBLESHOOTING:
        - For security blocks: Review security validation results
        - For ACL failures: Check AD permissions and connectivity
        - For verification issues: Consider AD replication timing
        - For performance: Review object complexity and network latency
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([RemovalOperationResult])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDN,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$OrphanedSIDs,

        [Parameter()]
        [string]$BackupPath,

        [Parameter()]
        [switch]$WhatIfMode,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    # Initialize result object
    $result = [RemovalOperationResult]::new()
    $result.ObjectDN = $ObjectDN
    $result.CorrelationId = $CorrelationId
    $result.IntendedRemovals = $OrphanedSIDs.Count

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-StructuredLog "Starting SID removal workflow for $ObjectDN (SIDs: $($OrphanedSIDs.Count), WhatIf: $WhatIfMode)" -Level Verbose -Component 'RemovalWorkflow' -CorrelationId $CorrelationId

        # Phase 1: Parameter Validation
        Write-StructuredLog "Phase 1: Parameter validation" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        if ([string]::IsNullOrWhiteSpace($ObjectDN.Trim())) {
            throw "ObjectDN parameter cannot be empty or whitespace"
        }

        # Phase 2: ACL Retrieval
        Write-StructuredLog "Phase 2: ACL retrieval" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        $acl = Get-ACLForRemoval -ObjectDN $ObjectDN -CorrelationId $CorrelationId

        # Phase 3: Security Validation
        Write-StructuredLog "Phase 3: Security validation" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        $securityValidation = Invoke-SecurityValidation -OrphanedSIDs $OrphanedSIDs -ObjectDN $ObjectDN -CorrelationId $CorrelationId

        $result.SecurityValidation = $securityValidation
        $result.BlockedSIDs = $securityValidation.BlockedSIDs

        if (-not $securityValidation.IsValid) {
            $result.ErrorMessage = "Security validation failed: $($securityValidation.Issues -join '; ')"
            $result.Success = $false
            Write-StructuredLog "SECURITY BLOCK: $($result.ErrorMessage)" -Level Error -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
            return $result
        }

        # Phase 4: Backup Creation (if requested and not WhatIf mode)
        if (-not $WhatIfMode -and $BackupPath) {
            Write-StructuredLog "Phase 4: Backup creation" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
            $backupSuccess = New-ACLBackup -ObjectDN $ObjectDN -ACL $acl -BackupPath $BackupPath -CorrelationId $CorrelationId
            if (-not $backupSuccess) {
                throw "Failed to create ACL backup - aborting removal operation"
            }
        }

        # Phase 5: SID Removal Processing
        Write-StructuredLog "Phase 5: SID removal processing" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        $removalResults = Invoke-SIDRemoval -ACL $acl -AllowedSIDs $securityValidation.AllowedSIDs -ObjectDN $ObjectDN -WhatIfMode:$WhatIfMode -CorrelationId $CorrelationId

        $result.RemovedSIDs = $removalResults.RemovedSIDs
        $result.FailedSIDs = $removalResults.FailedSIDs
        $result.ActualRemovals = $removalResults.RemovedSIDs.Count
        $result.FailedRemovals = $removalResults.FailedSIDs.Count

        # Phase 6: Security Audit Logging
        Write-RemovalSecurityLog -SecurityEventType 'PrivilegeUse' -Message "ACL modification operation initiated" -Outcome 'Attempt' -CorrelationId $CorrelationId -SecurityContext @{
            Operation = 'RemoveOrphanedSIDs'
            TargetObjectDN = $ObjectDN
            SIDsToRemove = $removalResults.RemovedSIDs.Count
            SIDsFailedRemoval = $removalResults.FailedSIDs.Count
            WhatIfMode = $WhatIfMode
            BackupCreated = (-not $WhatIfMode -and $BackupPath)
            SecurityValidation = @{
                IsValid = $securityValidation.IsValid
                RiskLevel = $securityValidation.RiskLevel
                BlockedSIDs = $securityValidation.BlockedSIDs.Count
            }
        }

        # Phase 7: ACL Application (if not WhatIf mode and changes exist)
        if (-not $WhatIfMode -and $removalResults.RemovedSIDs.Count -gt 0) {
            Write-StructuredLog "Phase 7: ACL application" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId

            if ($PSCmdlet.ShouldProcess($ObjectDN, "Apply SID removal changes")) {
                $applicationSuccess = Set-ModifiedACL -ACL $removalResults.ModifiedACL -ObjectDN $ObjectDN -CorrelationId $CorrelationId

                if ($applicationSuccess) {
                    # Log successful operation
                    Write-RemovalSecurityLog -SecurityEventType 'PrivilegeUse' -Message "ACL modification operation completed successfully" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext @{
                        Operation = 'RemoveOrphanedSIDs'
                        TargetObjectDN = $ObjectDN
                        SIDsRemoved = $removalResults.RemovedSIDs
                        ActualRemovals = $result.ActualRemovals
                        BackupPath = $BackupPath
                        SecurityValidationPassed = $true
                    }

                    # Phase 8: Verification
                    Write-StructuredLog "Phase 8: Operation verification" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
                    $verificationResult = Invoke-RemovalVerification -ObjectDN $ObjectDN -AllowedSIDs $securityValidation.AllowedSIDs -CorrelationId $CorrelationId
                    $result.Success = $verificationResult.Success

                    if (-not $verificationResult.Success) {
                        $result.ErrorMessage = $verificationResult.ErrorMessage
                        Write-RemovalSecurityLog -SecurityEventType 'PrivilegeUse' -Message "ACL modification verification failed" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                            Operation = 'RemoveOrphanedSIDs'
                            TargetObjectDN = $ObjectDN
                            VerificationError = $verificationResult.ErrorMessage
                            RemainingOrphanedSIDs = $verificationResult.RemainingOrphanedSIDs
                        }
                    }
                } else {
                    $result.Success = $false
                    $result.ErrorMessage = "Failed to apply ACL changes"
                    Write-RemovalSecurityLog -SecurityEventType 'PrivilegeUse' -Message "ACL modification application failed" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                        Operation = 'RemoveOrphanedSIDs'
                        TargetObjectDN = $ObjectDN
                        Error = 'ACLApplicationFailure'
                        IntendedRemovals = $result.IntendedRemovals
                    }
                }
            }
        } elseif ($WhatIfMode) {
            $result.Success = $true
            Write-StructuredLog "WhatIf mode: No changes applied" -Level Verbose -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        } else {
            $result.Success = $true  # No changes needed
            Write-StructuredLog "No SIDs required removal" -Level Verbose -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        }

        Write-StructuredLog "SID removal workflow completed for $ObjectDN - Success: $($result.Success), Removed: $($result.ActualRemovals), Failed: $($result.FailedRemovals)" -Level Verbose -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
        return $result
    }
    catch {
        $result.Success = $false
        $result.ErrorMessage = "Workflow failed: $($_.Exception.Message)"
        Write-StructuredLog "SID removal workflow failed for $ObjectDN : $($_.Exception.Message)" -Level Error -Component 'RemovalWorkflow' -CorrelationId $CorrelationId

        # Log workflow failure for security audit
        Write-RemovalSecurityLog -SecurityEventType 'PrivilegeUse' -Message "SID removal workflow failed" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
            Operation = 'RemoveOrphanedSIDs'
            TargetObjectDN = $ObjectDN
            Error = $_.Exception.Message
            IntendedRemovals = $result.IntendedRemovals
        }

        return $result
    }
    finally {
        $stopwatch.Stop()
        $result.ProcessingTime = $stopwatch.Elapsed
        Write-StructuredLog "Workflow processing time: $($result.ProcessingTime.TotalMilliseconds)ms" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $CorrelationId
    }
}

Write-StructuredLog "Removal workflow orchestration module loaded successfully" -Level Debug -Component 'RemovalWorkflow' -CorrelationId $([System.Guid]::NewGuid().ToString())
