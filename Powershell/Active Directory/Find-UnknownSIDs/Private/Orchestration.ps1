#Requires -Version 5.1

<#
.SYNOPSIS
    Initialization and orchestration functions for Find-UnknownSIDs script

.DESCRIPTION
    This module contains initialization logic, parameter validation, and
    orchestration functions that coordinate the main script execution.
    Provides enterprise-grade initialization with comprehensive validation.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-01
    Version: 2.0.0

    TROUBLESHOOTING:
    - For initialization issues: .\Troubleshooting\Common\Initialization-Issues.md
    - For parameter validation: .\Troubleshooting\Common\Parameter-Validation.md
#>


function Initialize-ScriptExecution {
    <#
    .SYNOPSIS
        Initialize script execution environment with comprehensive validation

    .DESCRIPTION
        Sets up the script execution environment including configuration loading,
        logging initialization, memory management setup, and dependency validation.
        Provides comprehensive error handling and validation for enterprise environments.

    .PARAMETER ConfigPath
        Path to configuration JSON file (optional)

    .PARAMETER LogPath
        Path for log file output

    .PARAMETER MaxMemoryUsageMB
        Maximum memory usage threshold in MB

    .PARAMETER CorrelationId
        Correlation ID for tracking this execution

    .OUTPUTS
        [hashtable] Initialization results with configuration and managers

    .EXAMPLE
        PS> Initialize-ScriptExecution -LogPath ".\Logs\script.log" -MaxMemoryUsageMB 1024

        DESCRIPTION: Initialize script with custom log path and memory limit
        OUTPUT: Hashtable with Config, MemoryManager, and Statistics objects
        USE CASE: Standard script initialization for enterprise environments

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For initialization failures: .\Troubleshooting\Common\Initialization-Issues.md
        - For configuration issues: .\Troubleshooting\Common\Configuration-Problems.md
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [ValidateRange(100, 16384)]
        [int]$MaxMemoryUsageMB = 1024,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$LogLevel = 'Information'
    )

    begin {
        Write-Verbose "Starting script initialization with CorrelationId: $CorrelationId"
    }

    process {
        try {
            # Initialize logging system first
            if ($LogPath) {
                Initialize-ScriptLogging -LogPath $LogPath -CorrelationId $CorrelationId -LogLevel $LogLevel
            } else {
                $defaultLogPath = ".\Logs\Find-UnknownSIDs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                Initialize-ScriptLogging -LogPath $defaultLogPath -CorrelationId $CorrelationId -LogLevel $LogLevel
            }

            # Initialize configuration
            Write-ScriptLog "Loading configuration..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId

            $script:Config = if ($ConfigPath -and (Test-Path $ConfigPath)) {
                Write-ScriptLog "Loading configuration from file: $ConfigPath" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
                [ScriptConfiguration]::LoadFromFile($ConfigPath)
            } else {
                Write-ScriptLog "Using default configuration" -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
                [ScriptConfiguration]::new()
            }

            # Validate configuration
            if (-not $script:Config.ValidateConfiguration()) {
                throw "Configuration validation failed"
            }

            Write-ScriptLog "Configuration loaded and validated successfully" -Level Debug -Component 'Initialization' -Color Green -CorrelationId $CorrelationId

            # Initialize memory manager
            Write-ScriptLog "Initializing memory manager (Limit: $MaxMemoryUsageMB MB)..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
            $script:MemoryManager = [MemoryManager]::new($MaxMemoryUsageMB, $script:Config.MemoryCheckInterval)

            # Initialize statistics
            Write-ScriptLog "Initializing performance statistics..." -Level Debug -Component 'Initialization' -CorrelationId $CorrelationId
            $script:Statistics = [ProcessingStatistics]::new()

            # Initialize log file path from configuration if provided
            if ($script:Config.LogFilePath) {
                $script:LogPath = $script:Config.LogFilePath
            } elseif ($LogPath) {
                $script:LogPath = $LogPath
            }

            # Perform log file rotation check
            if ($script:LogPath -and (Test-Path $script:LogPath)) {
                try {
                    $logFileInfo = Get-Item $script:LogPath
                    $fileSizeMB = [Math]::Round($logFileInfo.Length / 1MB, 2)

                    if ($script:Config.EnableLogFileRotation -and $fileSizeMB -gt $script:Config.MaxLogFileSizeMB) {
                        $rotatedPath = $script:LogPath -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                        Move-Item $script:LogPath $rotatedPath
                        Write-ScriptLog "Rotated log file to: $rotatedPath (Size: $fileSizeMB MB)" -Level Information -Component 'Initialization' -CorrelationId $CorrelationId
                    }
                } catch {
                    Write-ScriptLog "Log file rotation check failed: $($_.Exception.Message)" -Level Warning -Component 'Initialization' -CorrelationId $CorrelationId
                }
            }

            # Return initialization results
            $initResults = @{
                Config = $script:Config
                MemoryManager = $script:MemoryManager
                Statistics = $script:Statistics
                LogPath = $script:LogPath
                CorrelationId = $CorrelationId
            }

            Write-ScriptLog "Script initialization completed successfully" -Level Debug -Component 'Initialization' -Color Green -CorrelationId $CorrelationId
            return $initResults

        } catch {
            Write-ScriptLog "Script initialization failed: $($_.Exception.Message)" -Level Error -Component 'Initialization' -CorrelationId $CorrelationId
            throw
        }
    }
}


function Test-ValidDistinguishedName {
    <#
    .SYNOPSIS
        Validates Distinguished Name format with comprehensive security checks

    .DESCRIPTION
        Performs comprehensive validation of Active Directory Distinguished Names
        including format validation, length checks, and security character filtering
        to prevent injection attacks and ensure proper AD object referencing.

    .PARAMETER DistinguishedName
        The Distinguished Name string to validate

    .OUTPUTS
        [bool] True if DN is valid and secure, false otherwise

    .EXAMPLE
        PS> Test-ValidDistinguishedName -DistinguishedName "OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Validates a standard organizational unit DN
        OUTPUT: $true for valid DN format
        USE CASE: Parameter validation for AD operations

    .EXAMPLE
        PS> Test-ValidDistinguishedName -DistinguishedName "CN=Invalid<>Name,DC=test,DC=com"

        DESCRIPTION: Tests DN with invalid characters
        OUTPUT: $false due to forbidden characters
        SECURITY: Prevents potential injection attacks through malformed DNs

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        SECURITY CONSIDERATIONS:
        - Filters dangerous characters that could be used in injection attacks
        - Enforces maximum length to prevent buffer overflow scenarios
        - Validates proper DN component structure (CN, OU, DC)
        - Ensures DN contains at least one domain component

        TROUBLESHOOTING:
        - For DN validation issues: .\Troubleshooting\Security\DN-Validation.md
        - For AD object access: .\Troubleshooting\Common\AD-Access-Issues.md
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$DistinguishedName,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            # Handle null or empty strings
            if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
                Write-ScriptLog "Distinguished Name validation failed: Empty or null value" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
                return $false
            }

            # Length validation (LDAP DN maximum length)
            if ($DistinguishedName.Length -gt 1024) {
                Write-ScriptLog "Distinguished Name validation failed: Length exceeds 1024 characters ($($DistinguishedName.Length))" -Level Warning -Component 'DNValidator' -CorrelationId $CorrelationId
                return $false
            }

            # Basic format validation - must contain DC component and proper structure
            if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                Write-ScriptLog "Distinguished Name validation failed: Invalid format structure" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
                return $false
            }

            # Security validation - check for dangerous characters
            $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
            if ($DistinguishedName -match $dangerousChars) {
                Write-ScriptLog "Distinguished Name validation failed: Contains dangerous characters" -Level Warning -Component 'DNValidator' -CorrelationId $CorrelationId
                return $false
            }

            # Validate DN components structure
            $components = ($DistinguishedName -split ',')
            foreach ($component in $components) {
                $component = $component.Trim()

                # Each component must have format: TYPE=VALUE
                if (-not ($component -match '^(CN|OU|DC)=.+$')) {
                    Write-ScriptLog "Distinguished Name validation failed: Invalid component format: $component" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
                    return $false
                }

                # Component value cannot be empty after the equals sign
                $parts = $component -split '=', 2
                if ($parts.Length -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
                    Write-ScriptLog "Distinguished Name validation failed: Empty component value: $component" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
                    return $false
                }
            }

            # Must contain at least one DC component
            $domainComponents = $components | Where-Object { $_ -match '^DC=' }
            if ($domainComponents.Count -eq 0) {
                Write-ScriptLog "Distinguished Name validation failed: No domain components (DC=) found" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
                return $false
            }

            Write-ScriptLog "Distinguished Name validation successful: $DistinguishedName" -Level Debug -Component 'DNValidator' -CorrelationId $CorrelationId
            return $true
        }
        catch {
            Write-ScriptLog "Distinguished Name validation error: $($_.Exception.Message)" -Level Warning -Component 'DNValidator' -CorrelationId $CorrelationId
            return $false
        }
    }
}


function Invoke-MainProcessingLogic {
    <#
    .SYNOPSIS
        Execute the main SID discovery and processing logic

    .DESCRIPTION
        Orchestrates the main processing workflow including AD object discovery,
        SID analysis, and optional removal operations with comprehensive error
        handling and performance monitoring.

    .PARAMETER SearchBase
        Distinguished Name of the search base

    .PARAMETER Remove
        Whether to perform SID removal operations

    .PARAMETER IncludeInherited
        Whether to include inherited ACEs in processing

    .PARAMETER ParallelThrottleLimit
        Number of parallel threads for processing

    .PARAMETER MaxRetries
        Maximum retry attempts for failed operations

    .PARAMETER BackupPath
        Directory path for storing ACL backups before removal operations.
        If not specified for removal operations, no backups will be created.

    .PARAMETER CorrelationId
        Correlation ID for tracking this operation

    .OUTPUTS
        [hashtable] Processing results with statistics and findings

    .EXAMPLE
        PS> Invoke-MainProcessingLogic -SearchBase "OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Execute discovery mode on Users OU
        OUTPUT: Hashtable with discovered orphaned SIDs and statistics
        USE CASE: Standard orphaned SID discovery operation

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For processing failures: .\Troubleshooting\Common\Processing-Issues.md
        - For AD connectivity: .\Troubleshooting\Common\AD-Connection-Issues.md
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-ValidDistinguishedName $_ })]
        [string[]]$SearchBase,

        [Parameter()]
        [switch]$Remove,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$ParallelThrottleLimit = 10,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [string]$BackupPath,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-ScriptLog "Starting main processing logic" -Level Information -Component 'MainProcessing' -CorrelationId $CorrelationId

        # Initialize processing variables
        $script:AllResults = @()
        $script:RemovalResults = @()
    }

    process {
        try {
            # Process each search base
            foreach ($searchPath in $SearchBase) {
                Write-ScriptLog "Processing search base: $searchPath" -Level Information -Component 'MainProcessing' -CorrelationId $CorrelationId

                # Always perform discovery phase - ShouldProcess only applies to removal operations
                # Get AD objects for processing
                $adObjects = Get-ADObjectsParallel -SearchBase @($searchPath) -ThrottleLimit $ParallelThrottleLimit

                # Ensure $adObjects is always treated as an array for consistent counting
                $objectArray = @($adObjects)

                # Categorize objects for meaningful user feedback
                $objectStats = @{
                    Users = 0
                    Computers = 0
                    Groups = 0
                    OUs = 0
                    Other = 0
                }

                foreach ($obj in $objectArray) {
                    switch ($obj.ObjectClass) {
                        'user' { $objectStats.Users++ }
                        'computer' { $objectStats.Computers++ }
                        'group' { $objectStats.Groups++ }
                        'organizationalUnit' { $objectStats.OUs++ }
                        default { $objectStats.Other++ }
                    }
                }

                # Report meaningful discovery summary
                $summaryParts = @()
                if ($objectStats.Users -gt 0) { $summaryParts += "$($objectStats.Users) users" }
                if ($objectStats.Computers -gt 0) { $summaryParts += "$($objectStats.Computers) computers" }
                if ($objectStats.Groups -gt 0) { $summaryParts += "$($objectStats.Groups) groups" }
                if ($objectStats.OUs -gt 0) { $summaryParts += "$($objectStats.OUs) OUs" }
                if ($objectStats.Other -gt 0) { $summaryParts += "$($objectStats.Other) other objects" }

                $summaryText = if ($summaryParts.Count -gt 0) { $summaryParts -join ', ' } else { "0 objects" }
                Write-Host "Discovered: $summaryText (Total: $($objectArray.Count) objects)" -ForegroundColor Cyan

                Write-ScriptLog "Found $($objectArray.Count) AD objects to process" -Level Debug -Component 'MainProcessing' -CorrelationId $CorrelationId
                $script:Statistics.TotalObjects += $objectArray.Count

                # Process objects for orphaned SIDs - this always happens regardless of WhatIf
                $processedCount = 0
                $orphanedFoundCount = 0
                $results = $objectArray | ForEach-Object {
                    try {
                        $script:MemoryManager.CheckMemoryUsage()
                        $script:Statistics.ProcessedObjects++
                        $processedCount++

                        # Show progress every 50 objects or on last object
                        if (($processedCount % 50 -eq 0) -or ($processedCount -eq $objectArray.Count)) {
                            $percentComplete = [Math]::Round(($processedCount / $objectArray.Count) * 100, 1)
                            Write-Host "Processing: $processedCount/$($objectArray.Count) objects ($percentComplete%) - Orphaned SIDs found: $orphanedFoundCount" -ForegroundColor Yellow
                        }

                        $orphanedResults = Find-OrphanedSIDsInObject -ADObject $_ -IncludeInherited:$IncludeInherited

                        if ($orphanedResults -and $orphanedResults.Count -gt 0) {
                            $script:Statistics.OrphanedSIDsFound += $orphanedResults.Count
                            $orphanedFoundCount += $orphanedResults.Count

                            if ($Remove) {
                                # Apply ShouldProcess only to actual removal operations
                                foreach ($orphanedResult in $orphanedResults) {
                                    $target = "$($orphanedResult.ObjectDN) - SID: $($orphanedResult.OrphanedSID)"
                                    if ($PSCmdlet.ShouldProcess($target, "Remove Orphaned SID")) {
                                        Write-ScriptLog "Removing orphaned SID: $($orphanedResult.OrphanedSID) from $($orphanedResult.ObjectDN)" -Level Verbose -Component 'MainProcessing' -CorrelationId $CorrelationId
                                        $removalParams = @{
                                            ObjectDN = $orphanedResult.ObjectDN
                                            OrphanedSIDs = @($orphanedResult.OrphanedSID)
                                            CorrelationId = $CorrelationId
                                        }
                                        if ($BackupPath) {
                                            $removalParams.BackupPath = $BackupPath
                                        }
                                        $removalResult = Remove-OrphanedSID @removalParams
                                        $script:RemovalResults += $removalResult
                                    } else {
                                        Write-ScriptLog "WhatIf: Would remove orphaned SID: $($orphanedResult.OrphanedSID) from $($orphanedResult.ObjectDN)" -Level Verbose -Component 'MainProcessing' -CorrelationId $CorrelationId
                                        # Create a mock removal result for WhatIf mode
                                        $mockResult = [PSCustomObject]@{
                                            ObjectDN = $orphanedResult.ObjectDN
                                            OrphanedSID = $orphanedResult.OrphanedSID
                                            Success = $true
                                            ProcessingTime = [TimeSpan]::Zero
                                            ErrorMessage = $null
                                            RemovedSIDs = @($orphanedResult.OrphanedSID)
                                            FailedSIDs = @()
                                            BlockedSIDs = @()
                                            SecurityValidation = 'WhatIf - Would Remove'
                                        }
                                        $script:RemovalResults += $mockResult
                                    }
                                }
                            }

                            return $orphanedResults
                        }
                    }
                    catch {
                        $script:Statistics.ProcessingErrors++
                        Write-ScriptLog "Error processing object $($_.DistinguishedName): $($_.Exception.Message)" -Level Error -Component 'MainProcessing' -CorrelationId $CorrelationId

                        # Implement retry logic using MaxRetries parameter
                        $retryCount = 0
                        $retrySuccessful = $false

                        while ($retryCount -lt $MaxRetries -and -not $retrySuccessful) {
                            $retryCount++
                            Write-ScriptLog "Retry attempt $retryCount of $MaxRetries for object $($_.DistinguishedName)" -Level Warning -Component 'MainProcessing' -CorrelationId $CorrelationId

                            try {
                                Start-Sleep -Seconds (2 * $retryCount)  # Exponential backoff
                                $orphanedResults = Find-OrphanedSIDsInObject -ADObject $_ -IncludeInherited:$IncludeInherited
                                $retrySuccessful = $true

                                if ($orphanedResults -and $orphanedResults.Count -gt 0) {
                                    $script:Statistics.OrphanedSIDsFound += $orphanedResults.Count
                                    return $orphanedResults
                                }
                            }
                            catch {
                                Write-ScriptLog "Retry $retryCount failed for object $($_.DistinguishedName): $($_.Exception.Message)" -Level Warning -Component 'MainProcessing' -CorrelationId $CorrelationId
                                if ($retryCount -eq $MaxRetries) {
                                    Write-ScriptLog "Max retries ($MaxRetries) exceeded for object $($_.DistinguishedName)" -Level Error -Component 'MainProcessing' -CorrelationId $CorrelationId
                                }
                            }
                        }
                    }
                }

                $script:AllResults += $results | Where-Object { $_ }

                # Show completion summary for this search base
                Write-Host "Completed $searchPath - Objects: $($objectArray.Count), Orphaned SIDs: $orphanedFoundCount" -ForegroundColor Green
            }

            # Complete statistics
            $script:Statistics.Complete()

            # Generate processing summary
            $processingResults = @{
                TotalObjectsProcessed = $script:Statistics.ProcessedObjects
                OrphanedSIDsFound = $script:Statistics.OrphanedSIDsFound
                ProcessingErrors = $script:Statistics.ProcessingErrors
                ProcessingDuration = $script:Statistics.Duration
                ObjectsPerSecond = $script:Statistics.ObjectsPerSecond
                PeakMemoryUsageMB = $script:MemoryManager.GetPeakMemoryUsage()
                AllResults = $script:AllResults
                RemovalResults = $script:RemovalResults
                CorrelationId = $CorrelationId
            }

            Write-ScriptLog "Main processing completed successfully" -Level Information -Component 'MainProcessing' -Color Green -CorrelationId $CorrelationId
            return $processingResults

        }
        catch {
            $script:Statistics.CriticalErrors++
            Write-ScriptLog "Critical error in main processing: $($_.Exception.Message)" -Level Error -Component 'MainProcessing' -CorrelationId $CorrelationId
            throw
        }
    }
}


function Write-ProcessingSummary {
    <#
    .SYNOPSIS
        Write comprehensive processing summary with statistics and results

    .DESCRIPTION
        Generates and displays a comprehensive summary of processing results
        including performance statistics, findings, and recommendations for
        enterprise reporting and audit requirements.

    .PARAMETER ProcessingResults
        Hashtable containing processing results and statistics

    .PARAMETER OutputPath
        Optional path for CSV export of results

    .PARAMETER AutomationMode
        Whether to output structured data for automation

    .PARAMETER CorrelationId
        Correlation ID for tracking this operation

    .EXAMPLE
        PS> Write-ProcessingSummary -ProcessingResults $results -OutputPath ".\results.csv"

        DESCRIPTION: Write summary and export results to CSV
        OUTPUT: Console summary and CSV file export
        USE CASE: Standard result reporting and documentation

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For output issues: .\Troubleshooting\Common\Output-Issues.md
        - For CSV export problems: .\Troubleshooting\Common\File-Export-Issues.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ProcessingResults,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$AutomationMode,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-ScriptLog "Generating processing summary" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
    }

    process {
        try {
            # Display processing summary
            Write-ScriptLog "Processing summary details:" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
            Write-ScriptLog "=== PROCESSING SUMMARY ===" -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
            Write-ScriptLog "Total objects processed: $($ProcessingResults.TotalObjectsProcessed)" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
            Write-ScriptLog "Processing duration: $($ProcessingResults.ProcessingDuration.ToString('hh\:mm\:ss\.fff'))" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
            Write-ScriptLog "Processing rate: $([Math]::Round($ProcessingResults.ObjectsPerSecond, 2)) objects/second" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
            Write-ScriptLog "Peak memory usage: $($ProcessingResults.PeakMemoryUsageMB) MB" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
            # Check if this is a restore operation
            if ($ProcessingResults.PSObject.Properties.Name -contains 'SuccessfulRestores') {
                # Restore operation summary
                Write-ScriptLog "=== RESTORE SUMMARY ===" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
                Write-ScriptLog "Successful restores: $($ProcessingResults.SuccessfulRestores)" -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
                Write-ScriptLog "Failed restores: $($ProcessingResults.FailedRestores)" -Level Information -Component 'Summary' -Color $(if ($ProcessingResults.FailedRestores -gt 0) { 'Red' } else { 'Green' }) -CorrelationId $CorrelationId
                Write-ScriptLog "Backup source: $($ProcessingResults.BackupPath)" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
                Write-ScriptLog "WhatIf mode: $($ProcessingResults.WhatIfMode)" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId

                # Show detailed restore results
                if ($ProcessingResults.RestoreResults -and $ProcessingResults.RestoreResults.Count -gt 0) {
                    Write-ScriptLog "=== RESTORE DETAILS ===" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
                    foreach ($result in $ProcessingResults.RestoreResults) {
                        $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
                        $color = if ($result.Success) { "Green" } else { "Red" }
                        $entriesInfo = if ($result.EntriesRestored) { " ($($result.EntriesRestored) entries)" } else { "" }
                        Write-ScriptLog "  [$status] $($result.ObjectDN)$entriesInfo" -Level Information -Component 'Summary' -Color $color -CorrelationId $CorrelationId
                        if (-not $result.Success -and $result.ErrorMessage) {
                            Write-ScriptLog "    Error: $($result.ErrorMessage)" -Level Information -Component 'Summary' -Color Red -CorrelationId $CorrelationId
                        }
                    }
                }

                # Overall restore operation status
                if ($ProcessingResults.FailedRestores -eq 0) {
                    Write-ScriptLog "All restore operations completed successfully!" -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
                } else {
                    Write-ScriptLog "Some restore operations failed. Review the details above." -Level Warning -Component 'Summary' -Color Yellow -CorrelationId $CorrelationId
                }
            } else {
                # Standard discovery/removal operation summary
                Write-ScriptLog "Processing errors: $($ProcessingResults.ProcessingErrors)" -Level Information -Component 'Summary' -Color $(if ($ProcessingResults.ProcessingErrors -gt 0) { 'Yellow' } else { 'Green' }) -CorrelationId $CorrelationId
                Write-ScriptLog "Orphaned SIDs found: $($ProcessingResults.OrphanedSIDsFound)" -Level Information -Component 'Summary' -Color $(if ($ProcessingResults.OrphanedSIDsFound -gt 0) { 'Red' } else { 'Green' }) -CorrelationId $CorrelationId
            }

            # Removal summary if applicable
            if ($ProcessingResults.RemovalResults -and $ProcessingResults.RemovalResults.Count -gt 0) {
                $successfulRemovals = ($ProcessingResults.RemovalResults | Where-Object Success).Count
                $failedRemovals = ($ProcessingResults.RemovalResults | Where-Object { -not $_.Success }).Count

                Write-ScriptLog "Removal summary details:" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
                Write-ScriptLog "=== REMOVAL SUMMARY ===" -Level Information -Component 'Summary' -Color Yellow -CorrelationId $CorrelationId
                Write-ScriptLog "Removal operations attempted: $($ProcessingResults.RemovalResults.Count)" -Level Information -Component 'Summary' -Color Cyan -CorrelationId $CorrelationId
                Write-ScriptLog "Successful removals: $successfulRemovals" -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
                Write-ScriptLog "Failed removals: $failedRemovals" -Level Information -Component 'Summary' -Color $(if ($failedRemovals -gt 0) { 'Red' } else { 'Green' }) -CorrelationId $CorrelationId
            }

            # Export results to CSV if path provided
            if (($ProcessingResults.AllResults -and $ProcessingResults.AllResults.Count -gt 0) -or
                ($ProcessingResults.RestoreResults -and $ProcessingResults.RestoreResults.Count -gt 0)) {

                if ($OutputPath) {
                    try {
                        if ($ProcessingResults.AllResults) {
                            $ProcessingResults.AllResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                        } elseif ($ProcessingResults.RestoreResults) {
                            $ProcessingResults.RestoreResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                        }
                        Write-ScriptLog "Results exported to: $OutputPath" -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
                    }
                    catch {
                        Write-ScriptLog "Failed to export results to CSV: $($_.Exception.Message)" -Level Error -Component 'Summary' -CorrelationId $CorrelationId
                    }
                }

                if (-not ($ProcessingResults.PSObject.Properties.Name -contains 'SuccessfulRestores')) {
                    Write-ScriptLog "WARNING: Always test in a non-production environment first!" -Level Warning -Component 'Safety' -Color Red -CorrelationId $CorrelationId
                }
            } else {
                # Handle different operation types appropriately
                if ($ProcessingResults.PSObject.Properties.Name -contains 'SuccessfulRestores') {
                    # This is a restore operation with no results - shouldn't happen but handle gracefully
                    Write-ScriptLog "No restore operations were performed." -Level Information -Component 'Summary' -Color Yellow -CorrelationId $CorrelationId
                } else {
                    # This is a discovery/removal operation
                    if ($ProcessingResults.ProcessingErrors -gt 0) {
                        Write-ScriptLog "Consider reviewing the error log for detailed information." -Level Information -Component 'Summary' -Color Yellow -CorrelationId $CorrelationId
                    } else {
                        Write-ScriptLog "No orphaned SIDs found. Active Directory ACLs appear to be clean." -Level Information -Component 'Summary' -Color Green -CorrelationId $CorrelationId
                    }
                }
            }

            # Automation output if requested
            if ($AutomationMode) {
                $automationOutput = [PSCustomObject]@{
                    CorrelationId = $CorrelationId
                    ProcessingResults = $ProcessingResults
                    Summary = if ($ProcessingResults.PSObject.Properties.Name -contains 'SuccessfulRestores') {
                        # Restore operation summary
                        @{
                            TotalObjectsProcessed = $ProcessingResults.TotalObjectsProcessed
                            SuccessfulRestores = $ProcessingResults.SuccessfulRestores
                            FailedRestores = $ProcessingResults.FailedRestores
                            Duration = $ProcessingResults.ProcessingDuration.ToString()
                            WhatIfMode = $ProcessingResults.WhatIfMode
                            BackupPath = $ProcessingResults.BackupPath
                        }
                    } else {
                        # Discovery/removal operation summary
                        @{
                            TotalObjectsProcessed = $ProcessingResults.TotalObjectsProcessed
                            OrphanedSIDsFound = $ProcessingResults.OrphanedSIDsFound
                            ProcessingErrors = $ProcessingResults.ProcessingErrors
                            Duration = $ProcessingResults.ProcessingDuration.ToString()
                            PeakMemoryMB = $ProcessingResults.PeakMemoryUsageMB
                        }
                    }
                    Status = if ($ProcessingResults.PSObject.Properties.Name -contains 'SuccessfulRestores') {
                        if ($ProcessingResults.FailedRestores -eq 0) { "Success" } else { "Warning" }
                    } else {
                        if ($ProcessingResults.ProcessingErrors -eq 0) { "Success" } else { "Warning" }
                    }
                    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }

                Write-Information "##[section]Script Completion" -InformationAction Continue
                Write-Information ($automationOutput | ConvertTo-Json -Depth 3) -InformationAction Continue
            }

            Write-ScriptLog "Processing summary completed" -Level Information -Component 'Summary' -CorrelationId $CorrelationId

        }
        catch {
            Write-ScriptLog "Error generating processing summary: $($_.Exception.Message)" -Level Error -Component 'Summary' -CorrelationId $CorrelationId
            throw
        }
    }
}


function Invoke-RestoreWorkflow {
    <#
    .SYNOPSIS
        Orchestrates the ACL restore workflow for specified objects

    .DESCRIPTION
        Coordinates the restoration of ACLs from backup files for specified
        Active Directory objects. Provides comprehensive validation, progress
        tracking, and error handling for enterprise restore operations.

        BUSINESS VALUE:
        - Complete disaster recovery capability for ACL modifications
        - Compliance-driven rollback for failed change operations
        - Enterprise-grade restore orchestration with audit trails
        - Risk mitigation for security permission corruption

        ORCHESTRATION FEATURES:
        - Batch processing with parallel execution support
        - Comprehensive progress tracking and reporting
        - Intelligent backup file discovery and validation
        - Detailed success/failure tracking with correlation
        - Integration with enterprise monitoring and alerting

    .PARAMETER SearchBase
        Distinguished names of objects to restore ACLs for.
        Can be specific object DNs or container DNs for bulk operations.

    .PARAMETER BackupPath
        Directory containing backup files for restoration.
        Will search for matching backup files for each specified object.

    .PARAMETER WhatIfMode
        Preview restore operations without making actual changes.
        Useful for validation and approval workflows.

    .PARAMETER Force
        Bypasses safety confirmations for automated operations.
        Use with caution in production environments.

    .PARAMETER CorrelationId
        Unique identifier for tracking this restore session

    .EXAMPLE
        PS> Invoke-RestoreWorkflow -SearchBase @("CN=User1,CN=Users,DC=contoso,DC=com") -BackupPath "C:\Backups"

        DESCRIPTION: Restores ACL for a specific user from backup
        OUTPUT: Comprehensive restore results with operation details
        USE CASE: Targeted restoration after problematic SID removal

    .EXAMPLE
        PS> Invoke-RestoreWorkflow -SearchBase @("CN=Users,DC=contoso,DC=com") -BackupPath "C:\Backups" -WhatIfMode

        DESCRIPTION: Preview restore operations for container objects
        OUTPUT: Shows what would be restored without making changes
        BUSINESS CASE: Validation before large-scale restore operations

    .OUTPUTS
        [PSCustomObject] Comprehensive restore results including:
        - TotalObjectsProcessed: Number of objects processed
        - SuccessfulRestores: Number of successful restorations
        - FailedRestores: Number of failed restorations
        - RestoreResults: Detailed results for each object
        - ProcessingDuration: Total time for restore operations
        - Summary: High-level summary of restore operation
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [Parameter(Mandatory)]
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
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $restoreResults = [System.Collections.Generic.List[Object]]::new()

        Write-ScriptLog "Starting ACL restore workflow (SearchBase: $($SearchBase.Count), BackupPath: $BackupPath)" -Level Information -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
    }

    process {
        try {
            # Auto-discover all backup files in the backup directory
            Write-ScriptLog "Discovering backup files in: $BackupPath" -Level Information -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
            $backupFiles = Get-ChildItem -Path $BackupPath -Filter "*.xml" -File | Sort-Object Name

            if ($backupFiles.Count -eq 0) {
                throw "No backup files found in: $BackupPath"
            }

            # Extract object DNs from backup files
            $objectsToRestore = @()
            foreach ($backupFile in $backupFiles) {
                try {
                    $backupData = Import-Clixml -Path $backupFile.FullName -ErrorAction Stop
                    if ($backupData.ObjectDN) {
                        $objectsToRestore += $backupData.ObjectDN
                    }
                }
                catch {
                    Write-ScriptLog "Failed to read backup file $($backupFile.Name): $($_.Exception.Message)" -Level Warning -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
                    continue
                }
            }

            if ($objectsToRestore.Count -eq 0) {
                throw "No valid backup objects found to restore"
            }

            Write-ScriptLog "Discovered $($objectsToRestore.Count) objects to restore from $($backupFiles.Count) backup files" -Level Information -Component 'RestoreWorkflow' -CorrelationId $CorrelationId

            $totalObjects = $objectsToRestore.Count
            $processedCount = 0
            $successCount = 0
            $failureCount = 0

            foreach ($objectDN in $objectsToRestore) {
                $processedCount++

                Write-Progress -Activity "Restoring ACLs from Backup" -Status "Processing $objectDN" -PercentComplete (($processedCount / $totalObjects) * 100)

                try {
                    Write-ScriptLog "Processing restore for object: $objectDN" -Level Debug -Component 'RestoreWorkflow' -CorrelationId $CorrelationId

                    # Attempt to restore the object
                    $result = Restore-ObjectACL -ObjectDN $objectDN -BackupPath $BackupPath -WhatIfMode:$WhatIfMode -Force:$Force -CorrelationId $CorrelationId

                    $restoreResults.Add($result)

                    if ($result.Success) {
                        $successCount++
                        Write-ScriptLog "Successfully restored ACL for $objectDN" -Level Information -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
                    } else {
                        $failureCount++
                        Write-ScriptLog "Failed to restore ACL for $objectDN : $($result.ErrorMessage)" -Level Warning -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
                    }
                }
                catch {
                    $failureCount++
                    $errorResult = [RestoreOperationResult]::new()
                    $errorResult.ObjectDN = $objectDN
                    $errorResult.CorrelationId = $CorrelationId
                    $errorResult.Success = $false
                    $errorResult.ErrorMessage = "Unexpected error: $($_.Exception.Message)"
                    $restoreResults.Add($errorResult)

                    Write-ScriptLog "Unexpected error restoring $objectDN : $($_.Exception.Message)" -Level Error -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
                }
            }

            Write-Progress -Activity "Restoring ACLs from Backup" -Completed

            # Generate summary
            $summary = if ($WhatIfMode) {
                "PREVIEW: Would restore $successCount of $totalObjects objects from backup"
            } else {
                "Restored $successCount of $totalObjects objects successfully"
            }

            $results = [PSCustomObject]@{
                TotalObjectsProcessed = $totalObjects
                SuccessfulRestores = $successCount
                FailedRestores = $failureCount
                RestoreResults = $restoreResults.ToArray()
                ProcessingDuration = $stopwatch.Elapsed
                Summary = $summary
                CorrelationId = $CorrelationId
                WhatIfMode = $WhatIfMode
                BackupPath = $BackupPath
            }

            Write-ScriptLog "Restore workflow completed: $summary" -Level Information -Component 'RestoreWorkflow' -CorrelationId $CorrelationId

            return $results
        }
        catch {
            Write-ScriptLog "Critical error in restore workflow: $($_.Exception.Message)" -Level Error -Component 'RestoreWorkflow' -CorrelationId $CorrelationId
            throw
        }
        finally {
            $stopwatch.Stop()
        }
    }
}
