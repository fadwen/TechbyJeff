#Requires -Version 5.1

<#
.SYNOPSIS
    SID Result Factory Module for Find-UnknownSID Solution

.DESCRIPTION
    This focused module handles all result object creation and metadata management
    for the Find-UnknownSID enterprise solution. It provides comprehensive factory
    functions for creating standardized result objects with rich metadata and
    proper validation.

    SINGLE RESPONSIBILITY:
    This module does ONE thing well: Create and populate result objects with
    comprehensive metadata, ensuring consistent structure and complete information
    for all orphaned SID detection results.

    BUSINESS VALUE:
    - Standardized result object creation with consistent metadata
    - Comprehensive error handling and validation for result objects
    - Rich metadata population for audit trails and compliance
    - Extensible factory pattern for future result types

    TECHNICAL FEATURES:
    - Safe property extraction from access rules with null handling
    - Comprehensive metadata population including correlation tracking
    - Standardized result object validation and structure
    - Memory-efficient object creation with proper cleanup
    - Integration with enterprise logging and audit systems

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For result creation issues: .\Troubleshooting\Common\Result-Creation-Issues.md
    - For metadata population errors: .\Troubleshooting\Common\Metadata-Population-Issues.md
    - For object validation problems: .\Troubleshooting\Common\Result-Validation-Issues.md

    DEPENDENCIES:
    - Requires Classes.ps1 for OrphanedSIDResult class definition
    - Requires Logging.ps1 for Write-StructuredLog function
    - Uses script-scoped variables (CorrelationId for tracking)
#>

#region SID Result Factory Functions

function New-OrphanedSIDResult {
    <#
    .SYNOPSIS
        Creates comprehensive OrphanedSIDResult objects with full metadata

    .DESCRIPTION
        Factory function that creates properly structured OrphanedSIDResult objects
        with all required properties, comprehensive metadata, and validation. This
        function ensures consistent result object creation across the entire solution.

        The function provides:
        - Complete property population with safe access rule extraction
        - Rich metadata including correlation IDs and processing timestamps
        - Comprehensive validation of input parameters and created objects
        - Support for different processing methods and analysis confidence levels
        - Integration with enterprise logging and audit systems

    .PARAMETER ObjectDN
        Distinguished name of the Active Directory object containing the orphaned SID.
        This provides context for where the orphaned SID was discovered.

    .PARAMETER ObjectClass
        Class of the AD object (user, group, computer, organizationalUnit, etc.)
        for categorization and analysis context.

    .PARAMETER OrphanedSID
        The orphaned Security Identifier string that was detected.
        Must be a valid SID format.

    .PARAMETER AccessRule
        The access rule object containing the orphaned SID. Used to extract
        detailed ACL information including rights, inheritance, and object types.

    .PARAMETER LikelySource
        Categorized source of the orphaned SID based on analysis.
        Examples: "Deleted User", "Moved Account", "Unknown Domain", etc.

    .PARAMETER Confidence
        Analysis confidence level indicating the reliability of the source categorization.
        Values: "High", "Medium", "Low"

    .PARAMETER Notes
        Detailed analysis notes providing additional context and recommendations
        for the orphaned SID.

    .PARAMETER ProcessingMethod
        Method used to detect the orphaned SID for audit and troubleshooting purposes.
        Examples: "Enhanced-ACL-Retrieval", "Identity-Resolution", "NTAccount-Translation-Failed"

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation across logs and audit trails.
        Generated automatically if not provided.

    .EXAMPLE
        PS> $result = New-OrphanedSIDResult -ObjectDN $dn -OrphanedSID $sid -AccessRule $rule

        DESCRIPTION: Basic orphaned SID result creation with minimal parameters
        OUTPUT: Complete OrphanedSIDResult object with auto-generated metadata
        USE CASE: Standard orphaned SID result creation in processing workflows

    .EXAMPLE
        PS> $result = New-OrphanedSIDResult -ObjectDN $dn -ObjectClass "User" -OrphanedSID $sid -AccessRule $rule -LikelySource "Deleted User" -Confidence "High" -Notes "Account was deleted 30 days ago"

        DESCRIPTION: Comprehensive result creation with full analysis metadata
        OUTPUT: Rich OrphanedSIDResult object with detailed analysis information
        BUSINESS CASE: Complete audit trail with high-confidence analysis

    .EXAMPLE
        PS> $result = New-OrphanedSIDResult -ObjectDN $dn -OrphanedSID $sid -AccessRule $rule -ProcessingMethod "NTAccount-Translation-Failed" -CorrelationId $correlationId

        DESCRIPTION: Result creation with specific processing method and correlation tracking
        OUTPUT: OrphanedSIDResult with audit trail correlation and processing context
        INTEGRATION: Enterprise environments requiring detailed tracking and compliance

    .OUTPUTS
        [OrphanedSIDResult] Fully populated result object containing:
        - Object identification (DN, class, timestamp)
        - Orphaned SID details (SID, source analysis, confidence)
        - ACL information (access control type, rights, inheritance)
        - Processing metadata (correlation ID, method, timestamp)
        - Analysis details (notes, recommendations, confidence level)

    .NOTES
        OBJECT CREATION PROCESS:
        1. Validate input parameters and SID format
        2. Create new OrphanedSIDResult object instance
        3. Populate core object identification properties
        4. Extract and set ACL metadata safely
        5. Add comprehensive processing metadata
        6. Validate completed object structure

        METADATA CATEGORIES:
        - Object Context: DN, class, discovery timestamp
        - SID Analysis: Orphaned SID, source, confidence level
        - ACL Details: Access rights, control type, inheritance
        - Processing Info: Method, correlation ID, action taken
        - Audit Trail: Timestamps, operator context, compliance data

        ERROR HANDLING:
        - Comprehensive input validation with detailed error messages
        - Safe property extraction with null checking
        - Graceful handling of missing or invalid access rule properties
        - Detailed logging for troubleshooting and audit purposes

        PERFORMANCE CHARACTERISTICS:
        - Efficient object creation with minimal memory allocation
        - Safe property access with error containment
        - Optimized for high-volume processing scenarios
        - Memory cleanup considerations for large result sets
    #>

    [CmdletBinding()]
    [OutputType([OrphanedSIDResult])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'This is a factory function that creates objects but does not change system state')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$ObjectClass = "Unknown",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OrphanedSID,

        [Parameter(Mandatory)]
        [PSObject]$AccessRule,

        [Parameter()]
        [string]$LikelySource = "Unknown",

        [Parameter()]
        [ValidateSet("High", "Medium", "Low")]
        [string]$Confidence = "Medium",

        [Parameter()]
        [string]$Notes = "",

        [Parameter()]
        [string]$ProcessingMethod = "Standard",

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Creating OrphanedSIDResult object for $ObjectDN" -Level Debug -CorrelationId $CorrelationId

        # Validate OrphanedSID format
        if (-not (Test-SIDFormat -SID $OrphanedSID)) {
            throw "Invalid SID format provided: $OrphanedSID"
        }

        # Create new result object instance
        $result = [OrphanedSIDResult]::new()

        # Set core object identification properties
        $result.ObjectDN = $ObjectDN.Trim()
        $result.ObjectClass = $ObjectClass
        $result.OrphanedSID = $OrphanedSID
        $result.LikelySource = $LikelySource
        $result.Confidence = $Confidence
        $result.AnalysisNotes = $Notes

        # Add processing metadata
        Add-ProcessingMetadata -Result $result -ProcessingMethod $ProcessingMethod -CorrelationId $CorrelationId

        # Extract and set ACL metadata safely
        Set-ACLMetadata -Result $result -AccessRule $AccessRule -CorrelationId $CorrelationId

        Write-StructuredLog "Successfully created OrphanedSIDResult object for $ObjectDN with SID $OrphanedSID" -Level Debug -CorrelationId $CorrelationId

        return $result
    }
    catch {
        Write-StructuredLog "Error creating OrphanedSIDResult object for $ObjectDN : $($_.Exception.Message)" -Level Error -CorrelationId $CorrelationId
        throw "Failed to create OrphanedSIDResult: $($_.Exception.Message)"
    }
}

function Add-ProcessingMetadata {
    <#
    .SYNOPSIS
        Adds comprehensive processing metadata to result objects

    .DESCRIPTION
        Populates result objects with detailed processing metadata including
        correlation IDs, timestamps, processing methods, and audit information.
        This function ensures consistent metadata across all result objects.

    .PARAMETER Result
        The OrphanedSIDResult object to populate with metadata

    .PARAMETER ProcessingMethod
        Method used to detect the orphaned SID

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .NOTES
        METADATA ADDED:
        - Processing method and timestamp
        - Correlation ID for audit trails
        - Action taken and operator context
        - System and environment information
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [OrphanedSIDResult]$Result,

        [Parameter()]
        [string]$ProcessingMethod = "Standard",

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Adding processing metadata to result object" -Level Debug -CorrelationId $CorrelationId

        # Core processing metadata
        $Result.ProcessingMethod = $ProcessingMethod
        $Result.ActionTaken = "Detected"
        $Result.CorrelationId = $CorrelationId
        $Result.Timestamp = Get-Date

        # Additional context metadata
        if (-not $Result.PSObject.Properties['ProcessingContext']) {
            $Result | Add-Member -NotePropertyName 'ProcessingContext' -NotePropertyValue @{
                MachineName = $env:COMPUTERNAME
                UserName = $env:USERNAME
                ProcessId = $PID
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                ModuleVersion = "1.0.0"
            }
        }

        Write-StructuredLog "Successfully added processing metadata with correlation ID $CorrelationId" -Level Debug -CorrelationId $CorrelationId
    }
    catch {
        Write-StructuredLog "Error adding processing metadata: $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        throw
    }
}

function Set-ACLMetadata {
    <#
    .SYNOPSIS
        Safely extracts and sets ACL metadata from access rules

    .DESCRIPTION
        Performs safe extraction of ACL properties from access rule objects,
        handling missing properties and null values gracefully. This function
        ensures comprehensive ACL metadata is captured for audit and analysis.

    .PARAMETER Result
        The OrphanedSIDResult object to populate with ACL metadata

    .PARAMETER AccessRule
        The access rule object to extract metadata from

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .NOTES
        ACL METADATA EXTRACTED:
        - Access control type (Allow/Deny)
        - Active Directory rights and permissions
        - Inheritance flags and object types
        - Object GUIDs for extended rights
        - Inheritance hierarchy information

        ERROR HANDLING:
        - Safe property access with null checking
        - Graceful handling of missing properties
        - Default values for unavailable metadata
        - Comprehensive logging for troubleshooting
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [OrphanedSIDResult]$Result,

        [Parameter(Mandatory)]
        [PSObject]$AccessRule,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Extracting ACL metadata from access rule" -Level Debug -CorrelationId $CorrelationId

        # Extract access control type safely
        if ($AccessRule.PSObject.Properties['AccessControlType']) {
            $Result.AccessControlType = $AccessRule.AccessControlType
            Write-StructuredLog "Set AccessControlType: $($Result.AccessControlType)" -Level Debug -CorrelationId $CorrelationId
        } else {
            $Result.AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            Write-StructuredLog "AccessControlType property missing, set to Allow" -Level Debug -CorrelationId $CorrelationId
        }

        # Extract Active Directory rights safely
        if ($AccessRule.PSObject.Properties['ActiveDirectoryRights']) {
            $Result.ActiveDirectoryRights = $AccessRule.ActiveDirectoryRights
            Write-StructuredLog "Set ActiveDirectoryRights: $($Result.ActiveDirectoryRights)" -Level Debug -CorrelationId $CorrelationId
        } else {
            # Try alternative property names
            if ($AccessRule.PSObject.Properties['Rights']) {
                $Result.ActiveDirectoryRights = $AccessRule.Rights
                Write-StructuredLog "Set ActiveDirectoryRights from Rights property: $($Result.ActiveDirectoryRights)" -Level Debug -CorrelationId $CorrelationId
            } else {
                $Result.ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericRead
                Write-StructuredLog "ActiveDirectoryRights property missing, set to GenericRead" -Level Debug -CorrelationId $CorrelationId
            }
        }

        # Extract inheritance information safely
        if ($AccessRule.PSObject.Properties['InheritanceFlags']) {
            $Result.InheritanceType = $AccessRule.InheritanceFlags
            Write-StructuredLog "Set InheritanceType: $($Result.InheritanceType)" -Level Debug -CorrelationId $CorrelationId
        } else {
            $Result.InheritanceType = [System.Security.AccessControl.InheritanceFlags]::None
            Write-StructuredLog "InheritanceFlags property missing, set to None" -Level Debug -CorrelationId $CorrelationId
        }

        # Handle ObjectType GUID safely
        $Result.ObjectType = Get-SafeGuidProperty -Object $AccessRule -PropertyName 'ObjectType' -CorrelationId $CorrelationId

        # Handle InheritedObjectType GUID safely
        $Result.InheritedObjectType = Get-SafeGuidProperty -Object $AccessRule -PropertyName 'InheritedObjectType' -CorrelationId $CorrelationId

        # Extract inheritance status safely
        if ($AccessRule.PSObject.Properties['IsInherited']) {
            $Result.IsInherited = $AccessRule.IsInherited
            Write-StructuredLog "Set IsInherited: $($Result.IsInherited)" -Level Debug -CorrelationId $CorrelationId
        } else {
            $Result.IsInherited = $false
            Write-StructuredLog "IsInherited property missing, set to false" -Level Debug -CorrelationId $CorrelationId
        }

        Write-StructuredLog "Successfully extracted all available ACL metadata" -Level Debug -CorrelationId $CorrelationId
    }
    catch {
        Write-StructuredLog "Error extracting ACL metadata: $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        throw
    }
}

function Get-SafeGuidProperty {
    <#
    .SYNOPSIS
        Safely extracts GUID properties from objects with proper null handling

    .DESCRIPTION
        Handles the safe extraction of GUID properties from various object types,
        including proper handling of null values, empty GUIDs, and missing properties.

    .PARAMETER Object
        The object to extract the GUID property from

    .PARAMETER PropertyName
        Name of the GUID property to extract

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.Guid] The extracted GUID or Empty GUID if not available

    .NOTES
        GUID HANDLING:
        - Returns actual GUID if property exists and has value
        - Returns Empty GUID for null or missing properties
        - Handles various GUID string formats
        - Provides comprehensive error handling
    #>

    [CmdletBinding()]
    [OutputType([System.Guid])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Object,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        if ($Object.PSObject.Properties[$PropertyName] -and $Object.$PropertyName) {
            $guidValue = $Object.$PropertyName

            # Handle different GUID formats
            if ($guidValue -is [System.Guid]) {
                if ($guidValue -eq [System.Guid]::Empty) {
                    Write-StructuredLog "GUID property $PropertyName is empty GUID" -Level Debug -CorrelationId $CorrelationId
                    return [System.Guid]::Empty
                } else {
                    Write-StructuredLog "Set $PropertyName to GUID: $guidValue" -Level Debug -CorrelationId $CorrelationId
                    return $guidValue
                }
            } elseif ($guidValue -is [string]) {
                if ([string]::IsNullOrWhiteSpace($guidValue) -or $guidValue -eq "00000000-0000-0000-0000-000000000000") {
                    Write-StructuredLog "GUID property $PropertyName is empty string or zero GUID" -Level Debug -CorrelationId $CorrelationId
                    return [System.Guid]::Empty
                } else {
                    try {
                        $parsedGuid = [System.Guid]::Parse($guidValue)
                        Write-StructuredLog "Set $PropertyName to parsed GUID: $parsedGuid" -Level Debug -CorrelationId $CorrelationId
                        return $parsedGuid
                    } catch {
                        Write-StructuredLog "Failed to parse GUID string for $PropertyName : $guidValue" -Level Debug -CorrelationId $CorrelationId
                        return [System.Guid]::Empty
                    }
                }
            } else {
                Write-StructuredLog "GUID property $PropertyName has unexpected type: $($guidValue.GetType().Name)" -Level Debug -CorrelationId $CorrelationId
                return [System.Guid]::Empty
            }
        } else {
            Write-StructuredLog "GUID property $PropertyName missing or null, set to Empty" -Level Debug -CorrelationId $CorrelationId
            return [System.Guid]::Empty
        }
    }
    catch {
        Write-StructuredLog "Error extracting GUID property $PropertyName : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        return [System.Guid]::Empty
    }
}

function ConvertTo-ResultSummary {
    <#
    .SYNOPSIS
        Creates summary objects from collections of OrphanedSIDResult objects

    .DESCRIPTION
        Generates comprehensive summary reports from collections of orphaned SID
        results, providing aggregate statistics and categorized analysis for
        reporting and dashboard purposes.

    .PARAMETER OrphanedSIDResults
        Collection of OrphanedSIDResult objects to summarize

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [PSCustomObject] Summary object containing aggregate statistics and analysis

    .NOTES
        SUMMARY CATEGORIES:
        - Total counts and percentages
        - Source categorization analysis
        - Confidence level distribution
        - Object class analysis
        - Processing method statistics
        - Temporal analysis and trends

        BUSINESS VALUE:
        - Executive reporting capabilities
        - Trend analysis for security improvements
        - Resource allocation guidance
        - Compliance reporting support
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [OrphanedSIDResult[]]$OrphanedSIDResults,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Accumulate pipeline input for proper array processing
        $allResults = @()
    }

    process {
        # Add each pipeline input to accumulator
        $allResults += $OrphanedSIDResults
    }

    end {
        try {
            Write-StructuredLog "Creating result summary for $($allResults.Count) orphaned SID results" -Level Debug -CorrelationId $CorrelationId

            $summary = [PSCustomObject]@{
                # Basic statistics
                TotalOrphanedSIDs = $allResults.Count
                UniqueObjects = ($allResults | Select-Object -Property ObjectDN -Unique).Count
                UniqueOrphanedSIDs = ($allResults | Select-Object -Property OrphanedSID -Unique).Count

                # Source analysis
                SourceCategories = $allResults | Group-Object -Property LikelySource | ForEach-Object {
                    [PSCustomObject]@{
                        Source = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $allResults.Count) * 100, 2)
                    }
                } | Sort-Object -Property Count -Descending

                # Confidence distribution
                ConfidenceDistribution = $allResults | Group-Object -Property Confidence | ForEach-Object {
                    [PSCustomObject]@{
                        Confidence = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $allResults.Count) * 100, 2)
                    }
                }

                # Object class analysis
                ObjectClassAnalysis = $allResults | Group-Object -Property ObjectClass | ForEach-Object {
                    [PSCustomObject]@{
                        ObjectClass = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $allResults.Count) * 100, 2)
                    }
                } | Sort-Object -Property Count -Descending

                # Processing method statistics
                ProcessingMethods = $allResults | Group-Object -Property ProcessingMethod | ForEach-Object {
                    [PSCustomObject]@{
                        Method = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $allResults.Count) * 100, 2)
                    }
                }

                # Temporal analysis
                ProcessingTimespan = @{
                    Earliest = ($allResults | Measure-Object -Property Timestamp -Minimum).Minimum
                    Latest = ($allResults | Measure-Object -Property Timestamp -Maximum).Maximum
                }

                # Access rights analysis
                AccessRightsAnalysis = $allResults | Group-Object -Property ActiveDirectoryRights | ForEach-Object {
                    [PSCustomObject]@{
                        Rights = $_.Name
                        Count = $_.Count
                        Percentage = [Math]::Round(($_.Count / $allResults.Count) * 100, 2)
                    }
                } | Sort-Object -Property Count -Descending | Select-Object -First 10

                # Summary metadata
                SummaryMetadata = @{
                    GeneratedAt = Get-Date
                    CorrelationId = $CorrelationId
                    GeneratedBy = $env:USERNAME
                    MachineName = $env:COMPUTERNAME
                }
            }

            Write-StructuredLog "Successfully created result summary with $($summary.TotalOrphanedSIDs) total orphaned SIDs" -Level Debug -CorrelationId $CorrelationId

            return $summary
        }
        catch {
            Write-StructuredLog "Error creating result summary: $($_.Exception.Message)" -Level Error -CorrelationId $CorrelationId
            throw
        }
    }
}

#endregion

Write-StructuredLog "New-SIDResult module loaded successfully" -Level Debug -CorrelationId $([System.Guid]::NewGuid().ToString())

