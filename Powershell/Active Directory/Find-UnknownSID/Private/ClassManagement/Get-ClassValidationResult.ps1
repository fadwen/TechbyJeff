#Requires -Version 5.1

function Get-ClassValidationResult {
    <#
    .SYNOPSIS
        Creates structured result objects for class loading and validation operations

    .DESCRIPTION
        Factory function for creating consistent, structured result objects that combine
        data from multiple validation and loading operations. Provides a centralized way
        to create comprehensive ClassImportResult objects with proper typing and metadata.

        Core Functionality:
        - Aggregates results from path resolution, security validation, integrity checking
        - Creates properly typed result objects with comprehensive metadata
        - Handles success/failure status calculation and reporting
        - Provides consistent result structure across all class operations

    .PARAMETER LoadingResults
        Hashtable containing results from class loading operations.
        Should include loaded classes, failed classes, and loading metadata.

    .PARAMETER IntegrityResults
        Hashtable containing results from file integrity verification operations.
        Optional parameter for when integrity checking is enabled.

    .PARAMETER SecurityResults
        Hashtable containing results from security validation operations.
        Includes path traversal checks and security violations.

    .PARAMETER PathResults
        Array of resolved path objects from Resolve-ClassPath.
        Used to include path resolution information in final results.

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes. If not provided,
        a new GUID will be generated automatically.

    .EXAMPLE
        $result = Get-ClassValidationResult -LoadingResults $loadingData -SecurityResults $securityData -CorrelationId $correlationId

        DESCRIPTION: Creates a basic validation result with loading and security data
        OUTPUT: ClassImportResult object with comprehensive status and metadata
        USE CASE: Standard result creation for class import operations

    .EXAMPLE
        $result = Get-ClassValidationResult -LoadingResults $loadingData -IntegrityResults $integrityData -SecurityResults $securityData -PathResults $pathData

        DESCRIPTION: Creates comprehensive result with all validation components
        OUTPUT: Complete ClassImportResult with full validation details
        USE CASE: High-security environments requiring complete audit trails

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        ClassImportResult. Returns a structured object containing:
        - PSTypeName: 'ClassImportResult'
        - CorrelationId: Tracking identifier
        - TotalClasses: Total number of classes processed
        - LoadedClasses: Array of successfully loaded class names
        - FailedClasses: Array of failed loading attempts with details
        - Success: Boolean indicating overall operation success
        - SecurityValidation: Security check results and violations
        - IntegrityValidation: File integrity verification results (if enabled)
        - PathResolution: Path resolution results and validation
        - ProcessingMetadata: Comprehensive operation metadata

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        DESIGN PRINCIPLES:
        - Single responsibility: Only creates result objects
        - Immutable results: Result objects are read-only after creation
        - Comprehensive metadata: Includes all relevant operation details
        - Consistent structure: All results follow same format

        TROUBLESHOOTING:
        - For result object issues: .\Troubleshooting\Common\Result-Object-Issues.md
        - For data aggregation problems: .\Troubleshooting\Common\Data-Aggregation-Issues.md
    #>

    [CmdletBinding()]
    [OutputType('ClassImportResult')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$LoadingResults,

        [Parameter()]
        [hashtable]$IntegrityResults,

        [Parameter()]
        [hashtable]$SecurityResults,

        [Parameter()]
        [object[]]$PathResults,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Creating class validation result object - CorrelationId: $CorrelationId"

        # Log result creation start
        if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
            Write-StructuredLog -Level Debug -Message "Creating class validation result object" -Component 'ResultFactory' -CorrelationId $CorrelationId
        }
    }

    process {
        try {
            # Extract core loading data with PowerShell 5.1 compatibility
            $loadedClasses = if ($LoadingResults.LoadedClasses) { $LoadingResults.LoadedClasses } else { @() }
            $failedClasses = if ($LoadingResults.FailedClasses) { $LoadingResults.FailedClasses } else { @() }
            $totalClasses = if ($LoadingResults.TotalClasses) { $LoadingResults.TotalClasses } else { ($loadedClasses.Count + $failedClasses.Count) }

            # Calculate success metrics
            $successCount = $loadedClasses.Count
            $failureCount = $failedClasses.Count
            $successRate = if ($totalClasses -gt 0) {
                [math]::Round(($successCount / $totalClasses) * 100, 2)
            } else {
                0
            }

            # Process security results
            $securityValidation = @{
                Enabled = $null -ne $SecurityResults
                Violations = @()
                ViolationCount = 0
                PathTraversalChecks = $null
                SecurityPassed = $true
            }

            if ($SecurityResults) {
                $securityValidation.Violations = if ($SecurityResults.SecurityViolations) { $SecurityResults.SecurityViolations } else { @() }
                $securityValidation.ViolationCount = $securityValidation.Violations.Count
                $securityValidation.PathTraversalChecks = $SecurityResults.PathTraversalResults
                $securityValidation.SecurityPassed = $securityValidation.ViolationCount -eq 0
            }

            # Process integrity results
            $integrityValidation = @{
                Enabled = $null -ne $IntegrityResults
                VerificationResults = @()
                HashMismatches = @()
                IntegrityPassed = $true
                TotalFiles = 0
                PassedFiles = 0
            }

            if ($IntegrityResults) {
                $integrityValidation.VerificationResults = if ($IntegrityResults.IntegrityResults) { $IntegrityResults.IntegrityResults } else { @() }
                $integrityValidation.TotalFiles = $integrityValidation.VerificationResults.Count
                $integrityValidation.PassedFiles = ($integrityValidation.VerificationResults | Where-Object { $_.IntegrityValid }).Count
                $integrityValidation.HashMismatches = $integrityValidation.VerificationResults | Where-Object { $_.HashMismatch }
                $integrityValidation.IntegrityPassed = $integrityValidation.HashMismatches.Count -eq 0
            }

            # Process path resolution results
            $pathResolution = @{
                Enabled = $null -ne $PathResults
                ResolvedPaths = @()
                ValidPaths = @()
                InvalidPaths = @()
                PathResolutionPassed = $true
            }

            if ($PathResults) {
                $pathResolution.ResolvedPaths = $PathResults
                $pathResolution.ValidPaths = $PathResults | Where-Object { $_.IsValid }
                $pathResolution.InvalidPaths = $PathResults | Where-Object { -not $_.IsValid }
                $pathResolution.PathResolutionPassed = $pathResolution.InvalidPaths.Count -eq 0
            }

            # Determine overall success
            $overallSuccess = (
                $failureCount -eq 0 -and
                $securityValidation.SecurityPassed -and
                $integrityValidation.IntegrityPassed -and
                $pathResolution.PathResolutionPassed
            )

            # Create comprehensive metadata
            $processingMetadata = @{
                CorrelationId = $CorrelationId
                ProcessedAt = Get-Date
                ProcessingDuration = if ($LoadingResults.ProcessingDuration) { $LoadingResults.ProcessingDuration } else { $null }
                ClassesPath = if ($LoadingResults.ClassesPath) { $LoadingResults.ClassesPath } else { $null }
                ValidationComponents = @()
                OperationMode = if ($LoadingResults.OperationMode) { $LoadingResults.OperationMode } else { 'Standard' }
            }

            # Track which validation components were used
            if ($securityValidation.Enabled) { $processingMetadata.ValidationComponents += 'Security' }
            if ($integrityValidation.Enabled) { $processingMetadata.ValidationComponents += 'Integrity' }
            if ($pathResolution.Enabled) { $processingMetadata.ValidationComponents += 'PathResolution' }

            # Create the final result object
            $result = [PSCustomObject]@{
                PSTypeName = 'ClassImportResult'
                CorrelationId = $CorrelationId

                # Core Results
                TotalClasses = $totalClasses
                LoadedClasses = $loadedClasses
                FailedClasses = $failedClasses
                Success = $overallSuccess

                # Metrics
                LoadedCount = $successCount
                FailedCount = $failureCount
                SuccessRate = $successRate

                # Validation Results
                SecurityValidation = $securityValidation
                IntegrityValidation = $integrityValidation
                PathResolution = $pathResolution

                # Metadata
                ProcessingMetadata = $processingMetadata

                # Legacy Compatibility (for backward compatibility)
                SecurityViolations = $securityValidation.Violations
                SecurityViolationCount = $securityValidation.ViolationCount
                IntegrityVerificationEnabled = $integrityValidation.Enabled
                IntegrityResults = $integrityValidation.VerificationResults
                ClassesPath = $processingMetadata.ClassesPath
                Timestamp = $processingMetadata.ProcessedAt
            }

            Write-Verbose "Created validation result: $successCount/$totalClasses classes loaded, Success: $overallSuccess"

            # Log successful result creation
            if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog -Level Debug -Message "Successfully created class validation result" -Component 'ResultFactory' -CorrelationId $CorrelationId -Data @{
                    TotalClasses = $totalClasses
                    LoadedCount = $successCount
                    FailedCount = $failureCount
                    OverallSuccess = $overallSuccess
                    ValidationComponents = $processingMetadata.ValidationComponents
                }
            }

            return $result
        }
        catch {
            $errorMessage = "Failed to create class validation result: $($_.Exception.Message)"

            # Log error
            if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog -Level Error -Message $errorMessage -Component 'ResultFactory' -CorrelationId $CorrelationId
            }

            Write-Error $errorMessage -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed class validation result creation - CorrelationId: $CorrelationId"
    }
}
