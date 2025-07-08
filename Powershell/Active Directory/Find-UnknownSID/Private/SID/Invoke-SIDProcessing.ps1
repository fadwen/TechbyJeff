#Requires -Version 5.1

<#
.SYNOPSIS
    SID Processing Orchestration Module for Find-UnknownSID Solution

.DESCRIPTION
    This focused module orchestrates the entire orphaned SID detection workflow
    for the Find-UnknownSID enterprise solution. It coordinates the interaction
    between security descriptor retrieval, identity resolution, and result creation
    while managing processing statistics and error aggregation.

    SINGLE RESPONSIBILITY:
    This module does ONE thing well: Orchestrate the complete orphaned SID detection
    process by coordinating specialized modules and managing the overall workflow.

    BUSINESS VALUE:
    - Streamlined orchestration of complex multi-module workflows
    - Comprehensive error aggregation and processing statistics
    - Memory-efficient processing for large-scale AD environments
    - Standardized pipeline processing with correlation tracking

    TECHNICAL FEATURES:
    - Pipeline processing coordination with memory management
    - Error aggregation and graceful degradation
    - Processing statistics management and reporting
    - Integration with all specialized processing modules
    - Comprehensive logging and correlation tracking

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For orchestration issues: .\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md
    - For performance problems: .\Troubleshooting\Performance\SID-Processing-Performance.md
    - For memory management: .\Troubleshooting\Performance\Memory-Management-Issues.md

    DEPENDENCIES:
    - Requires Get-SecurityDescriptor.ps1 for ACL retrieval
    - Requires Resolve-SIDIdentity.ps1 for identity resolution
    - Requires New-SIDResult.ps1 for result object creation
    - Requires Logging.ps1 for Write-StructuredLog function
    - Uses script-scoped variables (CorrelationId for tracking)
#>

#region SID Processing Orchestration Functions

function Find-OrphanedSIDsInObject {
    <#
    .SYNOPSIS
        Orchestrates orphaned SID detection in Active Directory objects

    .DESCRIPTION
        Main orchestration function that coordinates the complete orphaned SID detection
        workflow across multiple specialized modules. This function manages the entire
        process from security descriptor retrieval through result object creation,
        providing comprehensive error handling and processing statistics.

        The orchestration workflow includes:
        - Input validation and error object filtering
        - Security descriptor retrieval using multiple strategies
        - Access rule processing and identity resolution
        - Orphaned SID detection and analysis
        - Result object creation and metadata population
        - Processing statistics and memory management

    .PARAMETER ADObject
        Active Directory objects to process. Can be from Get-ADObject output,
        background job results, or pipeline input. Objects must have
        DistinguishedName and nTSecurityDescriptor properties.

    .PARAMETER IncludeInherited
        When specified, includes inherited ACL entries in the orphaned SID analysis.
        By default, only explicit (non-inherited) ACL entries are processed.

    .PARAMETER CurrentDomainSID
        The SID of the current domain for context analysis. Used to categorize
        SIDs as local, foreign, or unknown domain objects.

    .PARAMETER CorrelationId
        Unique identifier for tracking this processing operation across logs
        and audit trails. Generated automatically if not provided.

    .EXAMPLE
        PS> $adObjects | Find-OrphanedSIDsInObject

        DESCRIPTION: Basic orphaned SID detection using pipeline processing
        OUTPUT: Array of OrphanedSIDResult objects for all orphaned SIDs found
        USE CASE: Standard security audit of AD objects from Get-ADObject

    .EXAMPLE
        PS> Find-OrphanedSIDsInObject -ADObject $adObjects -IncludeInherited -CurrentDomainSID $domainSID

        DESCRIPTION: Comprehensive analysis including inherited permissions and domain context
        OUTPUT: Complete orphaned SID analysis with enhanced categorization
        BUSINESS CASE: Thorough security audit including all permission sources

    .EXAMPLE
        PS> $jobResults | Find-OrphanedSIDsInObject -CorrelationId $correlationId

        DESCRIPTION: Processing background job results with correlation tracking
        OUTPUT: Orphaned SID results with full audit trail correlation
        INTEGRATION: Large-scale parallel processing with enterprise tracking

    .OUTPUTS
        [OrphanedSIDResult[]] Array of comprehensive result objects containing
        detailed information about discovered orphaned SIDs, including object
        context, analysis metadata, and processing information.

    .NOTES
        ORCHESTRATION WORKFLOW:
        1. Input validation and error object filtering
        2. Security descriptor retrieval (delegated to Get-SecurityDescriptor module)
        3. Access rule iteration and processing
        4. Identity resolution and orphaned SID testing (delegated to Resolve-SIDIdentity module)
        5. Result object creation (delegated to New-SIDResult module)
        6. Processing statistics compilation and memory cleanup

        PROCESSING STATISTICS:
        - Total objects processed and skipped
        - Access rules processed and orphaned SIDs found
        - Error counts and success rates
        - Processing timing and performance metrics
        - Memory usage and cleanup statistics

        ERROR HANDLING:
        - Graceful handling of error objects from pipeline
        - Individual access rule error containment
        - Comprehensive logging with correlation tracking
        - Processing statistics for troubleshooting
        - Memory cleanup for large datasets

        PERFORMANCE CHARACTERISTICS:
        - Optimized for pipeline processing of large object collections
        - Memory-efficient with periodic cleanup
        - Per-object processing isolation for error containment
        - Detailed performance metrics and timing
        - Scalable architecture for enterprise environments

        INTEGRATION POINTS:
        - Get-ObjectAccessRule for security descriptor processing
        - Test-AccessRuleForOrphanedSID for identity resolution
        - Correlation tracking across all processing modules
        - Enterprise logging and audit trail integration
    #>

    [CmdletBinding()]
    [OutputType([OrphanedSIDResult[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject[]]$ADObject,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CurrentDomainSID,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        foreach ($obj in $ADObject) {
            $results = [System.Collections.Generic.List[OrphanedSIDResult]]::new()

            # Initialize processing statistics for this object
            $processingStats = @{
                ObjectDN = "Unknown"
                StartTime = Get-Date
                ProcessedSIDs = 0
                SkippedSIDs = 0
                WellKnownSIDsSkipped = 0
                OrphanedSIDsFound = 0
                ErrorsEncountered = 0
                AccessRulesRetrieved = 0
                ProcessingMethod = "Orchestrated-Workflow"
            }

            try {
                Write-StructuredLog "Starting orchestrated orphaned SID detection for object" -Level Debug -CorrelationId $CorrelationId

                # Handle error objects that may come through the pipeline
                if ($obj.PSObject.Properties['IsError'] -and $obj.IsError -eq $true) {
                    Write-StructuredLog "Skipping error object: $($obj.ErrorMessage)" -Level Debug -CorrelationId $CorrelationId
                    $processingStats.ErrorsEncountered++
                    continue
                }

                # Validate that this is an AD object with required properties
                if (-not $obj.DistinguishedName) {
                    Write-StructuredLog "Object missing DistinguishedName property, skipping" -Level Debug -CorrelationId $CorrelationId
                    $processingStats.SkippedSIDs++
                    continue
                }

                $objectDN = $obj.DistinguishedName
                $processingStats.ObjectDN = $objectDN
                Write-StructuredLog "Processing object: $objectDN" -Level Debug -CorrelationId $CorrelationId

                # Check for security descriptor
                if (-not $obj.nTSecurityDescriptor) {
                    Write-StructuredLog "No security descriptor found for $objectDN" -Level Debug -CorrelationId $CorrelationId
                    $processingStats.SkippedSIDs++
                    return $results.ToArray()
                }

                # Delegate security descriptor processing to specialized module
                $accessRules = Get-ObjectAccessRule -ADObject $obj -IncludeInherited:$IncludeInherited -CorrelationId $CorrelationId

                if (-not $accessRules) {
                    Write-StructuredLog "No access rules retrieved for $objectDN" -Level Debug -CorrelationId $CorrelationId
                    $processingStats.SkippedSIDs++
                    return $results.ToArray()
                }

                $processingStats.AccessRulesRetrieved = $accessRules.Count
                Write-StructuredLog "Retrieved $($accessRules.Count) access rules for processing" -Level Debug -CorrelationId $CorrelationId

                # Process each access rule for orphaned SIDs using specialized identity resolution
                foreach ($rule in $accessRules) {
                    try {
                        # Delegate identity resolution and orphaned SID testing to specialized module
                        $orphanedResult = Test-AccessRuleForOrphanedSID -AccessRule $rule -ObjectDN $objectDN -ObjectClass $obj.ObjectClass -CurrentDomainSID $CurrentDomainSID -CorrelationId $CorrelationId

                        if ($orphanedResult) {
                            $results.Add($orphanedResult)
                            $processingStats.OrphanedSIDsFound++
                            Write-StructuredLog "Orphaned SID detected and result object created for $objectDN" -Level Verbose -CorrelationId $CorrelationId
                        }

                        $processingStats.ProcessedSIDs++
                    }
                    catch {
                        Write-StructuredLog "Error processing access rule for $objectDN : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
                        $processingStats.SkippedSIDs++
                        $processingStats.ErrorsEncountered++
                    }
                }

                # Calculate processing duration and log statistics
                $processingStats.EndTime = Get-Date
                $processingStats.Duration = ($processingStats.EndTime - $processingStats.StartTime).TotalMilliseconds

                Write-StructuredLog "Completed processing $objectDN - Processed: $($processingStats.ProcessedSIDs), Orphaned found: $($processingStats.OrphanedSIDsFound), Duration: $($processingStats.Duration)ms" -Level Debug -CorrelationId $CorrelationId

                # Add processing statistics to results if any orphaned SIDs were found
                if ($results.Count -gt 0) {
                    foreach ($result in $results) {
                        if (-not $result.PSObject.Properties['ProcessingStatistics']) {
                            $result | Add-Member -NotePropertyName 'ProcessingStatistics' -NotePropertyValue $processingStats
                        }
                    }
                }

                # Clean up access rules reference to help with memory management
                $accessRules = $null

                # Periodic garbage collection for large processing runs
                if ($processingStats.ProcessedSIDs -gt 0 -and $processingStats.ProcessedSIDs % 100 -eq 0) {
                    Write-StructuredLog "Performing periodic garbage collection after processing $($processingStats.ProcessedSIDs) SIDs" -Level Debug -CorrelationId $CorrelationId
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                }

                # Return results for this object
                return $results.ToArray()
            }
            catch {
                $processingStats.ErrorsEncountered++
                $processingStats.EndTime = Get-Date
                Write-StructuredLog "Error in orchestrated processing for object $($processingStats.ObjectDN) : $($_.Exception.Message)" -Level Error -CorrelationId $CorrelationId

                # Log final processing statistics even on error
                Write-StructuredLog "Processing statistics for $($processingStats.ObjectDN) : Processed: $($processingStats.ProcessedSIDs), Errors: $($processingStats.ErrorsEncountered), Orphaned found: $($processingStats.OrphanedSIDsFound)" -Level Debug -CorrelationId $CorrelationId

                return $results.ToArray()
            }
        }
    }
}

function Get-SIDProcessingStatistics {
    <#
    .SYNOPSIS
        Generates comprehensive processing statistics from orphaned SID results

    .DESCRIPTION
        Analyzes collections of OrphanedSIDResult objects to generate detailed
        processing statistics and performance metrics for reporting and optimization.

    .PARAMETER OrphanedSIDResults
        Collection of OrphanedSIDResult objects to analyze

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [PSCustomObject] Comprehensive processing statistics and performance metrics

    .NOTES
        STATISTICS GENERATED:
        - Processing counts and success rates
        - Performance timing and throughput metrics
        - Error analysis and categorization
        - Memory usage and efficiency metrics
        - Module performance breakdown
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [OrphanedSIDResult[]]$OrphanedSIDResults,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-StructuredLog "Generating processing statistics for $($OrphanedSIDResults.Count) results" -Level Debug -CorrelationId $CorrelationId

            # Extract processing statistics from results
            $allStats = $OrphanedSIDResults | Where-Object { $_.PSObject.Properties['ProcessingStatistics'] } | ForEach-Object { $_.ProcessingStatistics }

            if (-not $allStats) {
                Write-StructuredLog "No processing statistics found in results" -Level Warning -CorrelationId $CorrelationId
                return $null
            }

            # Calculate aggregate statistics
            $statistics = [PSCustomObject]@{
                # Basic counts
                TotalObjectsProcessed = $allStats.Count
                TotalSIDsProcessed = ($allStats | Measure-Object -Property ProcessedSIDs -Sum).Sum
                TotalOrphanedSIDsFound = ($allStats | Measure-Object -Property OrphanedSIDsFound -Sum).Sum
                TotalErrorsEncountered = ($allStats | Measure-Object -Property ErrorsEncountered -Sum).Sum
                TotalSIDsSkipped = ($allStats | Measure-Object -Property SkippedSIDs -Sum).Sum

                # Performance metrics
                AverageProcessingTimeMS = ($allStats | Measure-Object -Property Duration -Average).Average
                TotalProcessingTimeMS = ($allStats | Measure-Object -Property Duration -Sum).Sum
                MaxProcessingTimeMS = ($allStats | Measure-Object -Property Duration -Maximum).Maximum
                MinProcessingTimeMS = ($allStats | Measure-Object -Property Duration -Minimum).Minimum

                # Success rates
                SuccessRate = if ($allStats.Count -gt 0) {
                    [Math]::Round((($allStats.Count - ($allStats | Measure-Object -Property ErrorsEncountered -Sum).Sum) / $allStats.Count) * 100, 2)
                } else { 0 }

                OrphanedSIDDetectionRate = if (($allStats | Measure-Object -Property ProcessedSIDs -Sum).Sum -gt 0) {
                    [Math]::Round((($allStats | Measure-Object -Property OrphanedSIDsFound -Sum).Sum) / (($allStats | Measure-Object -Property ProcessedSIDs -Sum).Sum) * 100, 2)
                } else { 0 }

                # Processing method analysis
                ProcessingMethods = $OrphanedSIDResults | Group-Object -Property ProcessingMethod | ForEach-Object {
                    [PSCustomObject]@{
                        Method = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $OrphanedSIDResults.Count) * 100, 2)
                    }
                }

                # Performance per object analysis
                PerformanceAnalysis = @{
                    AverageSIDsPerObject = if ($allStats.Count -gt 0) {
                        [Math]::Round((($allStats | Measure-Object -Property ProcessedSIDs -Sum).Sum) / $allStats.Count, 2)
                    } else { 0 }

                    AverageOrphanedSIDsPerObject = if ($allStats.Count -gt 0) {
                        [Math]::Round((($allStats | Measure-Object -Property OrphanedSIDsFound -Sum).Sum) / $allStats.Count, 2)
                    } else { 0 }

                    ProcessingThroughput = if (($allStats | Measure-Object -Property Duration -Sum).Sum -gt 0) {
                        [Math]::Round((($allStats | Measure-Object -Property ProcessedSIDs -Sum).Sum) / (($allStats | Measure-Object -Property Duration -Sum).Sum / 1000), 2)
                    } else { 0 }
                }

                # Timing analysis
                TimingAnalysis = @{
                    EarliestProcessing = ($allStats | Where-Object StartTime | Measure-Object -Property StartTime -Minimum).Minimum
                    LatestProcessing = ($allStats | Where-Object EndTime | Measure-Object -Property EndTime -Maximum).Maximum
                    TotalDurationSeconds = if (($allStats | Measure-Object -Property Duration -Sum).Sum -gt 0) {
                        [Math]::Round((($allStats | Measure-Object -Property Duration -Sum).Sum) / 1000, 2)
                    } else { 0 }
                }

                # Error analysis
                ErrorAnalysis = @{
                    ObjectsWithErrors = ($allStats | Where-Object { $_.ErrorsEncountered -gt 0 }).Count
                    ErrorRate = if ($allStats.Count -gt 0) {
                        [Math]::Round((($allStats | Where-Object { $_.ErrorsEncountered -gt 0 }).Count / $allStats.Count) * 100, 2)
                    } else { 0 }
                    AverageErrorsPerFailedObject = if (($allStats | Where-Object { $_.ErrorsEncountered -gt 0 }).Count -gt 0) {
                        [Math]::Round((($allStats | Measure-Object -Property ErrorsEncountered -Sum).Sum) / (($allStats | Where-Object { $_.ErrorsEncountered -gt 0 }).Count), 2)
                    } else { 0 }
                }

                # Metadata
                GeneratedAt = Get-Date
                CorrelationId = $CorrelationId
                GeneratedBy = $env:USERNAME
                MachineName = $env:COMPUTERNAME
            }

            Write-StructuredLog "Generated comprehensive processing statistics: $($statistics.TotalObjectsProcessed) objects, $($statistics.TotalSIDsProcessed) SIDs, $($statistics.TotalOrphanedSIDsFound) orphaned" -Level Debug -CorrelationId $CorrelationId

            return $statistics
        }
        catch {
            Write-StructuredLog "Error generating processing statistics: $($_.Exception.Message)" -Level Error -CorrelationId $CorrelationId
            throw
        }
    }
}

#endregion

Write-StructuredLog "Invoke-SIDProcessing module loaded successfully" -Level Debug -CorrelationId $([System.Guid]::NewGuid().ToString())

