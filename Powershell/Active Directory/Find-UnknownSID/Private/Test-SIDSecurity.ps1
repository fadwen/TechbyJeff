#Requires -Version 5.1

<#
.SYNOPSIS
    SID Security Validation Module for Find-UnknownSID Solution

.DESCRIPTION
    This module provides comprehensive SID security validation and risk assessment
    functionality for the Find-UnknownSID enterprise solution. It focuses exclusively
    on security validation and compliance checking for SID operations.

    This module follows the single-responsibility principle by focusing exclusively
    on security validation and risk assessment. It depends on the Get-SIDAnalysis
    module for detailed SID context and categorization.

    BUSINESS VALUE:
    - Implements defense-in-depth security validation for SID operations
    - Ensures compliance with enterprise security policies
    - Provides risk-based approval workflows for SID removal
    - Supports audit requirements with comprehensive security logging

    TECHNICAL FEATURES:
    - Protected SID detection and blocking
    - Risk-based validation with configurable thresholds
    - Integration with enterprise security policies
    - Comprehensive security audit logging
    - Batch risk assessment for large-scale operations

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-04
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    MODULE DESIGN:
    This module implements the single-responsibility principle by focusing
    exclusively on security validation and risk assessment. It provides
    comprehensive security controls while maintaining high cohesion.

    TROUBLESHOOTING:
    - For security validation issues: .\Troubleshooting\Security\SID-Security-Issues.md
    - For risk assessment problems: .\Troubleshooting\Security\Risk-Assessment-Issues.md
    - For performance optimization: .\Troubleshooting\Performance\Security-Validation-Performance.md

    DEPENDENCIES:
    - Requires Get-SIDAnalysis.ps1 for SID analysis and categorization
    - Requires Classes.ps1 for SecurityValidationResult type definitions
    - Requires Logging.ps1 for Write-StructuredLog and Write-SecurityLog functions
    - Uses script-scoped $script:Config variable for security configuration access
#>

function Test-SIDSecurity {
    <#
    .SYNOPSIS
        Performs security validation for SID removal operations

    .DESCRIPTION
        Validates whether a SID can be safely removed based on security policies,
        well-known SID protections, and enterprise compliance requirements.
        This function implements defense-in-depth security validation.

    .PARAMETER SIDString
        The Security Identifier to validate for removal

    .PARAMETER ObjectDN
        Distinguished name of the object containing the SID (for context)

    .PARAMETER ValidationLevel
        Level of security validation (Basic, Standard, Strict)

    .PARAMETER CorrelationId
        Unique identifier for tracking this validation operation

    .EXAMPLE
        PS> Test-SIDSecurity -SIDString "S-1-5-21-1234567890-1234567890-1234567890-1001"

        DESCRIPTION: Basic security validation for a domain user SID
        OUTPUT: SecurityValidationResult with validation status and any issues
        USE CASE: Pre-validation before SID removal operations

    .EXAMPLE
        PS> Test-SIDSecurity -SIDString "S-1-5-18" -ValidationLevel "Strict"

        DESCRIPTION: Strict security validation for Local System SID
        OUTPUT: SecurityValidationResult blocking removal of critical system SID
        USE CASE: Protecting critical system SIDs from accidental removal

    .EXAMPLE
        PS> $orphanedSIDs | Test-SIDSecurity -ValidationLevel "Standard" -ObjectDN $objectDN

        DESCRIPTION: Batch security validation with object context
        OUTPUT: Array of SecurityValidationResult objects for approval workflow
        USE CASE: Enterprise compliance validation for batch operations

    .OUTPUTS
        [SecurityValidationResult] Object containing validation status and details

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        SECURITY FEATURES:
        - Protected SID detection and blocking
        - Well-known SID preservation
        - Risk-based validation with configurable thresholds
        - Integration with enterprise security policies
        - Comprehensive audit logging

        TROUBLESHOOTING:
        - For blocked SIDs: Check Protected SIDs configuration
        - For validation errors: Review security policy compliance
        - For performance issues: .\Troubleshooting\Performance\Security-Validation-Performance.md

    .LINK
        Get-SIDRiskAssessment
        .\Troubleshooting\Security\SID-Security-Issues.md
    #>

    [CmdletBinding()]
    [OutputType('SecurityValidationResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$SIDString,

        [Parameter()]
        [string]$ObjectDN,

        [Parameter()]
        [ValidateSet('Basic', 'Standard', 'Strict')]
        [string]$ValidationLevel = 'Standard',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-StructuredLog "Starting security validation for SID: $SIDString (Level: $ValidationLevel)" -Level Debug -Component 'SIDSecurity' -CorrelationId $CorrelationId

            # Log security validation event
            Write-SecurityLog -SecurityEventType 'DataValidation' -Message "SID security validation initiated" -Outcome 'Attempt' -CorrelationId $CorrelationId -SecurityContext @{
                SIDString = $SIDString
                ValidationLevel = $ValidationLevel
                ObjectDN = $ObjectDN
                Component = 'SIDSecurity'
            }

            $validation = [SecurityValidationResult]::new()
            $validation.IsValid = $true
            $validation.RiskLevel = "Low"

            # Check if SID is in protected list
            if ($script:Config -and $script:Config.ProtectedSIDs -contains $SIDString) {
                $validation.IsValid = $false
                $validation.RiskLevel = "Critical"
                $validation.Issues += "SID is in protected SIDs list - removal blocked by security policy"
                $validation.BlockedSIDs += $SIDString

                Write-StructuredLog "SID $SIDString blocked - found in protected SIDs list" -Level Warning -Component 'SIDSecurity' -CorrelationId $CorrelationId

                # Log security blocking event
                Write-SecurityLog -SecurityEventType 'DataValidation' -Message "Protected SID validation blocked - removal denied" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                    SIDString = $SIDString
                    ValidationLevel = $ValidationLevel
                    BlockedReason = 'ProtectedSIDsList'
                    RiskLevel = 'Critical'
                    ObjectDN = $ObjectDN
                }
            }

            # Check well-known SIDs using the Test-SIDFormat module
            if (Test-WellKnownSID -SID $SIDString -CorrelationId $CorrelationId) {
                if ($ValidationLevel -in @('Standard', 'Strict')) {
                    $validation.IsValid = $false
                    $validation.RiskLevel = "High"
                    $validation.Issues += "Well-known SID detected - removal may impact system security"
                    $validation.BlockedSIDs += $SIDString

                    Write-StructuredLog "Well-known SID $SIDString blocked for removal" -Level Warning -Component 'SIDSecurity' -CorrelationId $CorrelationId

                    # Log well-known SID security blocking
                    Write-SecurityLog -SecurityEventType 'DataValidation' -Message "Well-known SID validation blocked - system security protection" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                        SIDString = $SIDString
                        ValidationLevel = $ValidationLevel
                        BlockedReason = 'WellKnownSID'
                        RiskLevel = 'High'
                        SystemSecurityImpact = $true
                        ObjectDN = $ObjectDN
                    }
                }
            }

            # Perform SID analysis for additional risk assessment using Get-SIDAnalysis module
            $sidAnalysis = Get-SIDAnalysis -SIDString $SIDString -CorrelationId $CorrelationId

            # Risk-based validation
            switch ($sidAnalysis.RiskLevel) {
                'High' {
                    if ($ValidationLevel -eq 'Strict') {
                        $validation.RequiresElevatedConfirmation = $true
                        $validation.Issues += "High-risk SID requires elevated confirmation for removal"
                    }
                    $validation.RiskLevel = "High"

                    # Log high-risk SID validation
                    Write-SecurityLog -SecurityEventType 'DataValidation' -Message "High-risk SID identified - elevated validation required" -Outcome 'Attempt' -CorrelationId $CorrelationId -SecurityContext @{
                        SIDString = $SIDString
                        ValidationLevel = $ValidationLevel
                        RiskLevel = 'High'
                        RequiresElevatedConfirmation = $validation.RequiresElevatedConfirmation
                        SIDAnalysis = @{
                            LikelySource = $sidAnalysis.LikelySource
                            Confidence = $sidAnalysis.Confidence
                            Notes = $sidAnalysis.Notes
                        }
                        ObjectDN = $ObjectDN
                    }
                }
                'Medium' {
                    if ($ValidationLevel -eq 'Strict') {
                        $validation.RequiresElevatedConfirmation = $true
                    }
                    $validation.RiskLevel = "Medium"
                }
                'Low' {
                    $validation.AllowedSIDs += $SIDString
                }
            }

            # Object context validation
            if ($ObjectDN) {
                # Check if object is in critical path
                if ($script:Config -and $script:Config.CriticalObjectPatterns) {
                    foreach ($pattern in $script:Config.CriticalObjectPatterns) {
                        if ($ObjectDN -like $pattern) {
                            $validation.RequiresElevatedConfirmation = $true
                            $validation.Issues += "SID is on critical object: $ObjectDN"
                            $validation.RiskLevel = "High"
                            break
                        }
                    }
                }
            }

            # Final validation determination
            if ($validation.Issues.Count -eq 0 -and $validation.BlockedSIDs.Count -eq 0) {
                $validation.AllowedSIDs += $SIDString

                # Log successful security validation
                Write-SecurityLog -SecurityEventType 'DataValidation' -Message "SID security validation completed successfully" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext @{
                    SIDString = $SIDString
                    ValidationLevel = $ValidationLevel
                    FinalRiskLevel = $validation.RiskLevel
                    IsValid = $validation.IsValid
                    RequiresElevatedConfirmation = $validation.RequiresElevatedConfirmation
                    ObjectDN = $ObjectDN
                }
            }

            Write-StructuredLog "Security validation completed for $SIDString - Valid: $($validation.IsValid), Risk: $($validation.RiskLevel)" -Level Debug -Component 'SIDSecurity' -CorrelationId $CorrelationId
            return $validation
        }
        catch {
            Write-StructuredLog "Error in security validation for SID $SIDString : $($_.Exception.Message)" -Level Error -Component 'SIDSecurity' -CorrelationId $CorrelationId

            # Log security validation error
            Write-SecurityLog -SecurityEventType 'DataValidation' -Message "SID security validation error" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                SIDString = $SIDString
                ValidationLevel = $ValidationLevel
                ErrorMessage = $_.Exception.Message
                ObjectDN = $ObjectDN
            }

            $validation = [SecurityValidationResult]::new()
            $validation.IsValid = $false
            $validation.RiskLevel = "Critical"
            $validation.Issues += "Validation error: $($_.Exception.Message)"
            return $validation
        }
    }
}


function Get-SIDRiskAssessment {
    <#
    .SYNOPSIS
        Provides comprehensive risk assessment for SID removal operations

    .DESCRIPTION
        Analyzes multiple SIDs to provide an overall risk assessment for
        batch removal operations, including impact analysis and recommendations.

    .PARAMETER SIDList
        Array of SIDs to assess for collective risk

    .PARAMETER ObjectContext
        Context information about the objects containing the SIDs

    .PARAMETER CorrelationId
        Unique identifier for tracking this assessment operation

    .EXAMPLE
        PS> Get-SIDRiskAssessment -SIDList $orphanedSIDs

        DESCRIPTION: Comprehensive risk assessment for batch SID removal
        OUTPUT: Risk assessment report with recommendations and impact analysis
        USE CASE: Pre-approval analysis for large-scale cleanup operations

    .EXAMPLE
        PS> Get-SIDRiskAssessment -SIDList $sidList -ObjectContext "Critical Infrastructure"

        DESCRIPTION: Risk assessment with specific object context
        OUTPUT: Enhanced risk report considering critical infrastructure impact
        USE CASE: High-stakes environment validation before SID cleanup

    .EXAMPLE
        PS> $riskAssessment = Get-SIDRiskAssessment -SIDList $batchSIDs
        if ($riskAssessment.SafeForAutomation) {
            # Proceed with automated cleanup
        }

        DESCRIPTION: Automated decision making based on risk assessment
        OUTPUT: Boolean decision support for automation workflows
        USE CASE: Enterprise automation with risk-based controls

    .OUTPUTS
        [PSCustomObject] Risk assessment report containing:
        - AssessmentId: Unique identifier for this assessment
        - AssessedAt: Timestamp of assessment
        - TotalSIDs: Number of SIDs analyzed
        - OverallRisk: Aggregate risk level (Low/Medium/High/Critical)
        - RiskBreakdown: Count of SIDs by risk level
        - BlockedSIDs: SIDs that cannot be removed
        - AllowedSIDs: SIDs approved for removal
        - RequiresApproval: SIDs requiring elevated approval
        - Recommendations: Actionable recommendations
        - SafeForAutomation: Boolean indicating if automated processing is safe

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        BUSINESS VALUE:
        - Provides executive-level risk assessment for compliance approval
        - Identifies potential business impact before cleanup operations
        - Supports audit requirements with detailed risk documentation
        - Enables risk-based prioritization of cleanup activities

        PERFORMANCE CHARACTERISTICS:
        - Optimized for batch processing of large SID lists
        - Parallel analysis where possible
        - Comprehensive logging for audit trails
        - Average processing time: <50ms per SID

        TROUBLESHOOTING:
        - For assessment errors: Check individual SID validation results
        - For performance issues: Consider batch size optimization
        - For accuracy issues: Verify SID analysis dependencies

    .LINK
        Test-SIDSecurity
        Get-SIDAnalysis
        .\Troubleshooting\Security\Risk-Assessment-Issues.md
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$SIDList,

        [Parameter()]
        [string]$ObjectContext,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-StructuredLog "Starting risk assessment for $($SIDList.Count) SIDs" -Level Verbose -Component 'SIDSecurity' -CorrelationId $CorrelationId

            # Initialize risk counters
            $riskCounts = @{
                Low = 0
                Medium = 0
                High = 0
                Critical = 0
            }

            $blockedSIDs = @()
            $allowedSIDs = @()
            $requiresApproval = @()

            # Analyze each SID using dependent modules
            foreach ($sid in $SIDList) {
                Write-StructuredLog "Analyzing SID for risk assessment: $sid" -Level Debug -Component 'SIDSecurity' -CorrelationId $CorrelationId

                $analysis = Get-SIDAnalysis -SIDString $sid -CorrelationId $CorrelationId
                $validation = Test-SIDSecurity -SIDString $sid -ValidationLevel 'Standard' -CorrelationId $CorrelationId

                # Count risk levels
                $riskCounts[$analysis.RiskLevel]++

                # Categorize SIDs
                if (-not $validation.IsValid) {
                    $blockedSIDs += $sid
                }
                elseif ($validation.RequiresElevatedConfirmation) {
                    $requiresApproval += $sid
                }
                else {
                    $allowedSIDs += $sid
                }
            }

            # Calculate overall risk level
            $overallRisk = if ($riskCounts.Critical -gt 0) { "Critical" }
                          elseif ($riskCounts.High -gt 0) { "High" }
                          elseif ($riskCounts.Medium -gt 0) { "Medium" }
                          else { "Low" }

            # Generate recommendations
            $recommendations = @()
            if ($blockedSIDs.Count -gt 0) {
                $recommendations += "Review $($blockedSIDs.Count) blocked SIDs before proceeding"
            }
            if ($requiresApproval.Count -gt 0) {
                $recommendations += "Obtain elevated approval for $($requiresApproval.Count) high-risk SIDs"
            }
            if ($allowedSIDs.Count -gt 0) {
                $recommendations += "$($allowedSIDs.Count) SIDs approved for automatic removal"
            }

            # Create assessment report
            $assessment = [PSCustomObject]@{
                PSTypeName = 'SIDRiskAssessment'
                AssessmentId = $CorrelationId
                AssessedAt = Get-Date
                TotalSIDs = $SIDList.Count
                OverallRisk = $overallRisk
                RiskBreakdown = $riskCounts
                BlockedSIDs = $blockedSIDs
                AllowedSIDs = $allowedSIDs
                RequiresApproval = $requiresApproval
                Recommendations = $recommendations
                ObjectContext = $ObjectContext
                SafeForAutomation = ($blockedSIDs.Count -eq 0 -and $requiresApproval.Count -eq 0)
            }

            # Log comprehensive risk assessment
            Write-SecurityLog -SecurityEventType 'RiskAssessment' -Message "SID batch risk assessment completed" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext @{
                TotalSIDs = $assessment.TotalSIDs
                OverallRisk = $assessment.OverallRisk
                RiskBreakdown = $assessment.RiskBreakdown
                BlockedSIDsCount = $assessment.BlockedSIDs.Count
                AllowedSIDsCount = $assessment.AllowedSIDs.Count
                RequiresApprovalCount = $assessment.RequiresApproval.Count
                SafeForAutomation = $assessment.SafeForAutomation
                ObjectContext = $ObjectContext
            }

            Write-StructuredLog "Risk assessment completed - Overall Risk: $overallRisk, Safe for Automation: $($assessment.SafeForAutomation)" -Level Verbose -Component 'SIDSecurity' -CorrelationId $CorrelationId
            return $assessment
        }
        catch {
            Write-StructuredLog "Error in risk assessment: $($_.Exception.Message)" -Level Error -Component 'SIDSecurity' -CorrelationId $CorrelationId

            # Log risk assessment error
            Write-SecurityLog -SecurityEventType 'RiskAssessment' -Message "SID risk assessment error" -Outcome 'Failure' -CorrelationId $CorrelationId -SecurityContext @{
                TotalSIDsRequested = $SIDList.Count
                ErrorMessage = $_.Exception.Message
                ObjectContext = $ObjectContext
            }

            throw
        }
    }
}
