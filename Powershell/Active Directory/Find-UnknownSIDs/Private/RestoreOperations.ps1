#region RestoreOperations.ps1 - ACL Backup Restoration Functions
<#
.SYNOPSIS
    ACL backup restoration operations for Find-UnknownSIDs

.DESCRIPTION
    Provides comprehensive ACL restoration functionality including integrity validation,
    safety checks, and WhatIf operations. Designed for disaster recovery and rollback
    scenarios following SID removal operations.

    BUSINESS VALUE:
    - Complete rollback capability for failed SID removals
    - Disaster recovery for accidental ACL modifications
    - Compliance requirement fulfillment for change management
    - Risk mitigation for enterprise security operations

.NOTES
    Component: RestoreOperations
    Dependencies: Classes.ps1, Logging.ps1, Configuration.ps1, ADOperations.ps1
    Author: Jeffrey Stuhr
    Version: 1.0.0

    SECURITY CONSIDERATIONS:
    - Validates backup integrity before restoration
    - Confirms backup format and version compatibility
    - Logs all restoration activities for audit compliance
    - Requires appropriate AD permissions for ACL modification
#>

#region Restore Functions

function Restore-ObjectACL {
    <#
    .SYNOPSIS
        Restores Active Directory object ACLs from backup files

    .DESCRIPTION
        Restores ACLs for Active Directory objects using backup files created by
        Backup-ObjectACL. Performs comprehensive validation including integrity
        verification, backup format validation, and safety checks before restoration.

        BUSINESS VALUE:
        - Complete rollback capability for failed or problematic SID removals
        - Disaster recovery for accidental ACL modifications
        - Compliance requirement fulfillment for change management
        - Risk mitigation for enterprise security operations

        SAFETY FEATURES:
        - Backup integrity verification using SHA256 hashes
        - Backup format and version validation
        - WhatIf mode for preview before restoration
        - Comprehensive logging and correlation tracking
        - Safety confirmation for high-risk operations

    .PARAMETER ObjectDN
        Distinguished name of the object to restore ACL for.
        Must match the ObjectDN in the backup file exactly.

    .PARAMETER BackupFile
        Path to the backup file (.xml) containing the ACL to restore.
        File must be valid backup created by Backup-ObjectACL function.

    .PARAMETER BackupPath
        Directory containing backup files. If specified without BackupFile,
        will find the most recent backup for the specified ObjectDN.

    .PARAMETER WhatIfMode
        When specified, shows what would be restored without making changes.
        Useful for validation and approval workflows.

    .PARAMETER Force
        Bypasses safety confirmations for automated operations.
        Use with caution in production environments.

    .PARAMETER CorrelationId
        Unique identifier for tracking this restoration operation.

    .EXAMPLE
        PS> Restore-ObjectACL -ObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com" -BackupFile "C:\Backups\CN_TestUser_20250127_143022.xml"

        DESCRIPTION: Restores ACL from specific backup file
        OUTPUT: RestoreOperationResult with operation status and details
        USE CASE: Targeted restoration after problematic SID removal

    .EXAMPLE
        PS> Restore-ObjectACL -ObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com" -BackupPath "C:\Backups" -WhatIfMode

        DESCRIPTION: Preview restoration using most recent backup
        OUTPUT: Shows what would be restored without making changes
        BUSINESS CASE: Validation before critical restoration operations

    .EXAMPLE
        PS> Get-Content objects.txt | Restore-ObjectACL -BackupPath "C:\Backups" -Force

        DESCRIPTION: Bulk restoration from pipeline with automation mode
        OUTPUT: RestoreOperationResult objects for each processed object
        AUTOMATION: Suitable for disaster recovery automation workflows

    .OUTPUTS
        [RestoreOperationResult] Object containing:
        - ObjectDN: Distinguished name of restored object
        - CorrelationId: Unique tracking identifier
        - BackupFile: Path to backup file used for restoration
        - BackupDate: Original backup creation date
        - RestorationDate: When restoration was performed
        - Success: Overall operation success status
        - ErrorMessage: Detailed error information if applicable
        - ProcessingTime: Duration of the restoration operation
        - BackupValidation: Results of backup integrity verification
        - EntriesRestored: Number of ACL entries restored
        - WhatIfMode: Whether operation was preview-only

    .NOTES
        SECURITY CONSIDERATIONS:
        - Validates backup integrity before any restoration
        - Confirms backup format and version compatibility
        - Logs all restoration activities for audit compliance
        - Requires appropriate AD permissions for ACL modification

        RECOVERY SCENARIOS:
        - Failed SID removal operations requiring rollback
        - Accidental ACL modifications needing restoration
        - Disaster recovery for security permission corruption
        - Compliance-driven change management processes

        TROUBLESHOOTING:
        - For backup validation failures: Check backup file integrity
        - For ACL application errors: Verify AD permissions and connectivity
        - For object access issues: Confirm object existence and accessibility
        - For version compatibility: Check backup format version
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([RestoreOperationResult])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DistinguishedName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ObjectDN,

        [Parameter(ParameterSetName = 'SpecificBackup')]
        [ValidateScript({
            if (-not (Test-Path $_)) {
                throw "Backup file not found: $_"
            }
            if ([System.IO.Path]::GetExtension($_) -ne '.xml') {
                throw "Backup file must have .xml extension"
            }
            $true
        })]
        [string]$BackupFile,

        [Parameter(ParameterSetName = 'BackupDirectory')]
        [ValidateScript({
            if (-not (Test-Path $_ -PathType Container)) {
                throw "Backup directory not found: $_"
            }
            $true
        })]
        [string]$BackupPath,

        [Parameter()]
        [switch]$WhatIfMode,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-ScriptLog "Starting ACL restoration for objects: $($ObjectDN.Count)" -Level Information -Component 'RestoreOperations' -CorrelationId $CorrelationId
    }

    process {
        foreach ($dn in $ObjectDN) {
            $result = [RestoreOperationResult]::new()
            $result.ObjectDN = $dn
            $result.CorrelationId = $CorrelationId
            $result.RestorationDate = Get-Date
            $result.WhatIfMode = $WhatIfMode

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                Write-ScriptLog "Starting ACL restoration for $dn (WhatIf: $WhatIfMode)" -Level Information -Component 'RestoreOperations' -CorrelationId $CorrelationId

                # Validate DN parameter
                if ([string]::IsNullOrWhiteSpace($dn.Trim())) {
                    throw "ObjectDN parameter cannot be empty or whitespace"
                }

                # Determine backup file to use
                $backupFileToUse = $null
                if ($BackupFile) {
                    $backupFileToUse = $BackupFile
                } elseif ($BackupPath) {
                    # Find most recent backup for this object
                    $safeName = $dn.Trim() -replace '[\\/:*?"<>|,=]', '_' -replace '\s+', '_'
                    $backupPattern = "${safeName}_*.xml"
                    $backupFiles = Get-ChildItem -Path $BackupPath -Filter $backupPattern -File | Sort-Object LastWriteTime -Descending

                    if ($backupFiles.Count -eq 0) {
                        throw "No backup files found for object: $dn"
                    }

                    $backupFileToUse = $backupFiles[0].FullName
                    Write-ScriptLog "Using most recent backup: $backupFileToUse" -Level Information -Component 'RestoreOperations' -CorrelationId $CorrelationId
                } else {
                    throw "Either BackupFile or BackupPath must be specified"
                }

                $result.BackupFile = $backupFileToUse

                # Load and validate backup
                Write-ScriptLog "Loading backup file: $backupFileToUse" -Level Debug -Component 'RestoreOperations' -CorrelationId $CorrelationId
                $backupData = Import-Clixml -Path $backupFileToUse -ErrorAction Stop

                # Validate backup format and integrity
                $validationResult = Test-BackupIntegrity -BackupData $backupData -ExpectedObjectDN $dn
                $result.BackupValidation = $validationResult.IsValid
                $result.BackupDate = $backupData.BackupDate

                if (-not $validationResult.IsValid) {
                    throw "Backup validation failed: $($validationResult.ErrorMessage)"
                }

                # Convert SDDL back to ACL object
                $securityDescriptor = [System.DirectoryServices.ActiveDirectorySecurity]::new()
                $securityDescriptor.SetSecurityDescriptorSddlForm($backupData.SDDL)
                $result.EntriesRestored = $securityDescriptor.Access.Count

                # Safety confirmation for non-WhatIf operations
                if (-not $WhatIfMode -and -not $Force) {
                    $confirmMessage = "Restore ACL for '$dn' from backup dated $($backupData.BackupDate)? This will replace current permissions with $($result.EntriesRestored) entries."
                    $confirmation = Read-Host "$confirmMessage (y/N)"
                    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
                        Write-ScriptLog "Restoration cancelled by user for $dn" -Level Warning -Component 'RestoreOperations' -CorrelationId $CorrelationId
                        $result.Success = $false
                        $result.ErrorMessage = "Operation cancelled by user"
                        return $result
                    }
                }

                # Apply restoration
                if ($WhatIfMode) {
                    Write-ScriptLog "WHAT IF: Would restore ACL for $dn with $($result.EntriesRestored) entries from backup dated $($backupData.BackupDate)" -Level Information -Component 'RestoreOperations' -CorrelationId $CorrelationId
                    $result.Success = $true
                } else {
                    if ($PSCmdlet.ShouldProcess($dn, "Restore ACL from backup")) {
                        $applicationSuccess = Set-ModifiedACL -ACL $securityDescriptor -ObjectDN $dn

                        if ($applicationSuccess) {
                            # Verify restoration
                            Start-Sleep -Milliseconds 500  # Brief pause for AD replication
                            $verificationACL = Get-Acl -Path "AD:\$($dn.Trim())" -ErrorAction Stop

                            if ($verificationACL.Access.Count -eq $result.EntriesRestored) {
                                $result.Success = $true
                                Write-ScriptLog "Successfully restored ACL for $dn ($($result.EntriesRestored) entries)" -Level Information -Component 'RestoreOperations' -CorrelationId $CorrelationId
                            } else {
                                $result.Success = $false
                                $result.ErrorMessage = "Verification failed: Expected $($result.EntriesRestored) entries, found $($verificationACL.Access.Count)"
                            }
                        } else {
                            $result.Success = $false
                            $result.ErrorMessage = "Failed to apply restored ACL"
                        }
                    }
                }

                return $result
            }
            catch {
                $result.Success = $false
                $result.ErrorMessage = "Restoration failed: $($_.Exception.Message)"
                Write-ScriptLog "ACL restoration failed for $dn : $($_.Exception.Message)" -Level Error -Component 'RestoreOperations' -CorrelationId $CorrelationId
                return $result
            }
            finally {
                $stopwatch.Stop()
                $result.ProcessingTime = $stopwatch.Elapsed
            }
        }
    }
}

function Test-BackupIntegrity {
    <#
    .SYNOPSIS
        Validates backup file integrity and format

    .DESCRIPTION
        Performs comprehensive validation of backup files including
        format validation, integrity verification, and compatibility checks.

        VALIDATION CHECKS:
        - Required properties presence validation
        - Backup signature and version verification
        - ObjectDN matching (when specified)
        - SDDL integrity verification using SHA256 hash
        - SDDL format validation

        SECURITY CONSIDERATIONS:
        - Uses cryptographic hash verification for data integrity
        - Validates backup format to prevent malicious data injection
        - Confirms version compatibility for safe restoration

    .PARAMETER BackupData
        The imported backup data object to validate.
        Must be a PSCustomObject with required backup properties.

    .PARAMETER ExpectedObjectDN
        Expected object DN to validate against backup.
        When specified, confirms backup matches intended object.

    .EXAMPLE
        PS> $backup = Import-Clixml "C:\Backups\user_backup.xml"
        PS> Test-BackupIntegrity -BackupData $backup -ExpectedObjectDN "CN=TestUser,CN=Users,DC=contoso,DC=com"

        DESCRIPTION: Validates imported backup against expected object
        OUTPUT: Validation result with IsValid status and error details
        USE CASE: Pre-restoration validation for safety verification

    .OUTPUTS
        [PSCustomObject] Validation results containing:
        - IsValid: Boolean indicating overall validation success
        - ErrorMessage: Detailed error information if validation fails
        - Issues: Array of specific validation issues found

    .NOTES
        INTEGRITY VERIFICATION:
        - SHA256 hash verification prevents data corruption detection
        - Format validation ensures compatibility and safety
        - Version checking prevents incompatible restoration attempts

        TROUBLESHOOTING:
        - For hash mismatches: Backup file may be corrupted
        - For format errors: Backup may be from incompatible version
        - For property missing: Backup file may be incomplete or damaged
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$BackupData,

        [Parameter()]
        [string]$ExpectedObjectDN
    )

    try {
        $issues = @()

        # Validate required properties
        $requiredProperties = @('ObjectDN', 'BackupDate', 'SDDL', 'SDDLHash', 'ValidationSignature')
        foreach ($prop in $requiredProperties) {
            if (-not $BackupData.PSObject.Properties[$prop]) {
                $issues += "Missing required property: $prop"
            }
        }

        # Validate backup signature (support both v1.0 and v2.0 for compatibility)
        $validSignatures = @("PSSecurityBackup_v1.0", "PSSecurityBackup_v2.0")
        if ($BackupData.ValidationSignature -notin $validSignatures) {
            $issues += "Invalid backup signature: $($BackupData.ValidationSignature)"
        }

        # Validate ObjectDN if specified
        if ($ExpectedObjectDN -and $BackupData.ObjectDN -ne $ExpectedObjectDN) {
            $issues += "ObjectDN mismatch: Expected '$ExpectedObjectDN', found '$($BackupData.ObjectDN)'"
        }

        # Validate SDDL integrity
        if ($BackupData.SDDL -and $BackupData.SDDLHash) {
            $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($BackupData.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $calculatedHash = [System.Convert]::ToBase64String($sha256.ComputeHash($sddlBytes))
            $sha256.Dispose()

            if ($calculatedHash -ne $BackupData.SDDLHash) {
                $issues += "SDDL integrity check failed: Hash mismatch"
            }
        }

        # Validate SDDL format
        try {
            $testSecurityDescriptor = [System.DirectoryServices.ActiveDirectorySecurity]::new()
            $testSecurityDescriptor.SetSecurityDescriptorSddlForm($BackupData.SDDL)
        }
        catch {
            $issues += "Invalid SDDL format: $($_.Exception.Message)"
        }

        return [PSCustomObject]@{
            IsValid = $issues.Count -eq 0
            ErrorMessage = if ($issues.Count -gt 0) { $issues -join '; ' } else { $null }
            Issues = $issues
        }
    }
    catch {
        return [PSCustomObject]@{
            IsValid = $false
            ErrorMessage = "Validation error: $($_.Exception.Message)"
            Issues = @("Validation error: $($_.Exception.Message)")
        }
    }
}

#endregion

Write-ScriptLog "RestoreOperations module loaded successfully" -Level Debug -Component 'RestoreOperations' -CorrelationId $([System.Guid]::NewGuid().ToString())

#endregion
