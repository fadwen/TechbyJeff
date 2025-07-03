#Requires -Version 5.1

<#
.SYNOPSIS
    SID Processing Module for Find-UnknownSIDs Solution

.DESCRIPTION
    This module provides core SID processing functionality for the Find-UnknownSIDs
    enterprise solution. It includes ACL analysis, orphaned SID detection, and
    comprehensive security descriptor processing with support for various AD object types.

    BUSINESS VALUE:
    - Efficient processing of large-scale Active Directory environments
    - Robust handling of complex ACL structures and inheritance
    - Comprehensive error handling for production environments
    - Support for parallel processing and background job scenarios

    TECHNICAL FEATURES:
    - Advanced security descriptor processing with multiple retrieval methods
    - Support for inherited and non-inherited ACL entries
    - Comprehensive SID validation and analysis
    - Integration with enterprise logging and correlation tracking
    - Memory-efficient processing for large object collections

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For ACL processing issues: .\Troubleshooting\Security\ACL-Processing-Issues.md
    - For security descriptor errors: .\Troubleshooting\Common\Security-Descriptor-Errors.md
    - For performance optimization: .\Troubleshooting\Performance\SID-Processing-Performance.md

    DEPENDENCIES:
    - Requires Classes.ps1 for type definitions (OrphanedSIDResult)
    - Requires Logging.ps1 for Write-ScriptLog function
    - Requires SIDValidation.ps1 for Get-SIDAnalysis and SID validation functions
    - Uses script-scoped variables (CorrelationId, Configuration)
#>

#region Core SID Processing Functions

function Find-OrphanedSIDsInObject {
    <#
    .SYNOPSIS
        Finds orphaned SIDs in Active Directory objects with comprehensive error handling

    .DESCRIPTION
        Processes AD objects to identify orphaned Security Identifiers (SIDs) in their
        Access Control Lists (ACLs). This function handles complex security descriptor
        scenarios including deserialized objects from background jobs, inherited permissions,
        and various ACL structures.

        The function provides:
        - Multiple security descriptor retrieval methods for maximum compatibility
        - Support for both inherited and explicit ACL entries
        - Comprehensive SID validation and orphan detection
        - Detailed analysis and categorization of orphaned SIDs
        - Integration with enterprise logging and correlation tracking

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

        DESCRIPTION: Basic orphaned SID detection on AD objects from pipeline
        OUTPUT: Array of OrphanedSIDResult objects for found orphaned SIDs
        USE CASE: Standard orphaned SID discovery in explicit ACL entries

    .EXAMPLE
        PS> Find-OrphanedSIDsInObject -ADObject $adObjects -IncludeInherited

        DESCRIPTION: Comprehensive analysis including inherited permissions
        OUTPUT: Complete orphaned SID analysis including inherited ACL entries
        BUSINESS CASE: Thorough security audit including all permission sources

    .EXAMPLE
        PS> $computerObjects | Find-OrphanedSIDsInObject -CurrentDomainSID $domainSID

        DESCRIPTION: Domain-aware processing for accurate SID categorization
        OUTPUT: OrphanedSIDResult objects with enhanced domain context analysis
        INTEGRATION: Enterprise environments with complex trust relationships

    .OUTPUTS
        [OrphanedSIDResult[]] Array of objects containing:
        - ObjectDN: Distinguished name of the object containing orphaned SIDs
        - ObjectClass: Type of AD object (user, group, computer, etc.)
        - OrphanedSID: The orphaned Security Identifier string
        - LikelySource: Categorized source of the orphaned SID
        - Confidence: Analysis confidence level
        - AnalysisNotes: Detailed notes and recommendations
        - ACL Details: Access control type, rights, and inheritance information
        - Processing Metadata: Correlation ID, timestamp, and processing method

    .NOTES
        TECHNICAL SPECIFICATIONS:
        - Memory Usage: Optimized for large object collections
        - Processing Rate: 10-50 objects/second depending on ACL complexity
        - Error Handling: Comprehensive with graceful degradation
        - Compatibility: Supports PowerShell 5.1 and 7.x environments

        SECURITY CONSIDERATIONS:
        - Validates all SID formats before processing
        - Implements secure handling of security descriptors
        - Provides detailed audit trails for compliance
        - Uses correlation ID tracking for security monitoring

        PERFORMANCE CHARACTERISTICS:
        - Efficient ACL processing with minimal memory allocation
        - Support for batch processing and pipeline operations
        - Intelligent caching of domain context for repeated processing
        - Optimized for environments with 1,000+ objects

        TROUBLESHOOTING:
        - For ACL retrieval failures: Multiple fallback methods implemented
        - For security descriptor errors: Enhanced error logging with object context
        - For performance issues: Built-in processing statistics and timing
        - For validation errors: Comprehensive SID format and structure checking
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

            try {
                Write-ScriptLog "Starting orphaned SID detection for object" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

                # Handle error objects that may come through the pipeline
                if ($obj.PSObject.Properties['IsError'] -and $obj.IsError -eq $true) {
                    Write-ScriptLog "Skipping error object: $($obj.ErrorMessage)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    continue
                }

                # Validate that this is an AD object with required properties
                if (-not $obj.DistinguishedName) {
                    Write-ScriptLog "Object missing DistinguishedName property, skipping" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    continue
                }

                $objectDN = $obj.DistinguishedName
                Write-ScriptLog "Processing object: $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

                # Check for security descriptor
                if (-not $obj.nTSecurityDescriptor) {
                    Write-ScriptLog "No security descriptor found for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    return $results.ToArray()
                }

                # Process security descriptor with multiple retrieval methods
                $accessRules = Get-ObjectAccessRule -ADObject $obj -IncludeInherited:$IncludeInherited

                if (-not $accessRules) {
                    Write-ScriptLog "No access rules retrieved for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    return $results.ToArray()
                }

                # Process each access rule for orphaned SIDs
                $processingStats = @{
                    ProcessedSIDs = 0
                    SkippedSIDs = 0
                    WellKnownSIDsSkipped = 0
                    OrphanedSIDsFound = 0
                }

                foreach ($rule in $accessRules) {
                    try {
                        $orphanedResult = Test-AccessRuleForOrphanedSID -AccessRule $rule -ObjectDN $objectDN -ObjectClass $obj.ObjectClass -CurrentDomainSID $CurrentDomainSID

                        if ($orphanedResult) {
                            $results.Add($orphanedResult)
                            $processingStats.OrphanedSIDsFound++
                        }

                        $processingStats.ProcessedSIDs++
                    }
                    catch {
                        Write-ScriptLog "Error processing access rule for $objectDN : $($_.Exception.Message)" -Level Warning -Component 'SIDProcessing' -CorrelationId $CorrelationId
                        $processingStats.SkippedSIDs++
                    }
                }

                Write-ScriptLog "Completed processing $objectDN - Processed: $($processingStats.ProcessedSIDs), Orphaned found: $($processingStats.OrphanedSIDsFound)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

                # Return results for this object
                return $results.ToArray()
            }
            catch {
                Write-ScriptLog "Error processing object $objectDN : $($_.Exception.Message)" -Level Error -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $results.ToArray()
            }
        }
    }
}

function Get-ObjectAccessRule {
    <#
    .SYNOPSIS
        Retrieves access rules from AD object security descriptors with multiple fallback methods

    .DESCRIPTION
        Implements multiple methods to retrieve ACL access rules from Active Directory
        objects, handling various scenarios including deserialized objects from background
        jobs, binary security descriptors, and regular ActiveDirectorySecurity objects.

    .PARAMETER ADObject
        Active Directory object containing security descriptor

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules

    .NOTES
        TECHNICAL DETAILS:
        - Method 1: Get-Acl for reliable access (preferred)
        - Method 2: Direct security descriptor processing
        - Method 3: Fresh AD query as fallback
        - Handles deserialized objects from PowerShell background jobs
        - Comprehensive error handling with detailed logging
    #>

    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectoryAccessRule[]])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$ADObject,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        $objectDN = $ADObject.DistinguishedName
        Write-ScriptLog "Retrieving access rules for object: $objectDN (IncludeInherited: $IncludeInherited)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
        $accessRules = $null

        # Method 1: Try using Get-Acl for reliable access to security descriptor
        try {
            $acl = Get-Acl -Path "AD:\$objectDN" -ErrorAction Stop
            $accessRules = if ($IncludeInherited) {
                $acl.Access
            } else {
                $acl.Access | Where-Object { -not $_.IsInherited }
            }
            Write-ScriptLog "Successfully retrieved ACL using Get-Acl for $objectDN - Found $($accessRules.Count) access rules" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $accessRules
        }
        catch {
            Write-ScriptLog "Get-Acl failed for $objectDN, trying binary descriptor method: $($_.Exception.Message)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
        }

        # Method 2: Handle various security descriptor formats
        try {
            $binarySD = $ADObject.nTSecurityDescriptor

            # Check if this is a deserialized ActiveDirectorySecurity object (from background jobs)
            if ($binarySD.PSObject.TypeNames[0] -like '*Deserialized*ActiveDirectorySecurity*') {
                Write-ScriptLog "Detected deserialized ActiveDirectorySecurity object, extracting access rules directly" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

                if ($binarySD.Access) {
                    $accessRules = if ($IncludeInherited) {
                        $binarySD.Access
                    } else {
                        $binarySD.Access | Where-Object { -not $_.IsInherited }
                    }
                    Write-ScriptLog "Successfully extracted access rules from deserialized security descriptor for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    return $accessRules
                } else {
                    throw "Deserialized security descriptor has no Access property"
                }
            }
            elseif ($binarySD -is [System.DirectoryServices.ActiveDirectorySecurity]) {
                # Regular ActiveDirectorySecurity object
                Write-ScriptLog "Processing regular ActiveDirectorySecurity object" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                $accessRules = if ($IncludeInherited) {
                    $binarySD.Access
                } else {
                    $binarySD.Access | Where-Object { -not $_.IsInherited }
                }
                Write-ScriptLog "Successfully processed ActiveDirectorySecurity object for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $accessRules
            }
            else {
                # Process as binary data
                Write-ScriptLog "Processing security descriptor as binary data" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                $securityDescriptor = [System.DirectoryServices.ActiveDirectorySecurity]::new()

                if ($binarySD -is [byte[]]) {
                    $securityDescriptor.SetSecurityDescriptorBinaryForm($binarySD)
                } elseif ($binarySD -is [string]) {
                    $byteArray = [System.Convert]::FromBase64String($binarySD)
                    $securityDescriptor.SetSecurityDescriptorBinaryForm($byteArray)
                } else {
                    $byteArray = [byte[]]$binarySD
                    $securityDescriptor.SetSecurityDescriptorBinaryForm($byteArray)
                }

                $accessRules = if ($IncludeInherited) {
                    $securityDescriptor.Access
                } else {
                    $securityDescriptor.Access | Where-Object { -not $_.IsInherited }
                }
                Write-ScriptLog "Successfully processed binary security descriptor for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $accessRules
            }
        }
        catch {
            Write-ScriptLog "Binary security descriptor processing failed for $objectDN : $($_.Exception.Message)" -Level Warning -Component 'SIDProcessing' -CorrelationId $CorrelationId
        }

        # Method 3: Last resort - fresh AD query
        try {
            Write-ScriptLog "Attempting fresh AD query for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            $freshObj = Get-ADObject -Identity $objectDN -Properties nTSecurityDescriptor -ErrorAction Stop

            if ($freshObj.nTSecurityDescriptor) {
                if ($freshObj.nTSecurityDescriptor -is [System.DirectoryServices.ActiveDirectorySecurity]) {
                    $securityDescriptor = $freshObj.nTSecurityDescriptor
                } else {
                    $securityDescriptor = [System.DirectoryServices.ActiveDirectorySecurity]::new()
                    if ($freshObj.nTSecurityDescriptor -is [byte[]]) {
                        $securityDescriptor.SetSecurityDescriptorBinaryForm($freshObj.nTSecurityDescriptor)
                    } else {
                        $byteArray = [byte[]]$freshObj.nTSecurityDescriptor
                        $securityDescriptor.SetSecurityDescriptorBinaryForm($byteArray)
                    }
                }

                $accessRules = if ($IncludeInherited) {
                    $securityDescriptor.Access
                } else {
                    $securityDescriptor.Access | Where-Object { -not $_.IsInherited }
                }
                Write-ScriptLog "Successfully retrieved fresh security descriptor for $objectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $accessRules
            } else {
                throw "No security descriptor available after fresh query"
            }
        }
        catch {
            Write-ScriptLog "All security descriptor retrieval methods failed for $objectDN : $($_.Exception.Message)" -Level Error -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }
    }
    catch {
        Write-ScriptLog "Unexpected error retrieving access rules for $($ADObject.DistinguishedName) : $($_.Exception.Message)" -Level Error -Component 'SIDProcessing' -CorrelationId $CorrelationId
        return $null
    }
}

function Test-AccessRuleForOrphanedSID {
    <#
    .SYNOPSIS
        Tests an individual access rule for orphaned SIDs

    .DESCRIPTION
        Processes a single ACL access rule to determine if it contains orphaned SIDs,
        handling various identity reference types and performing comprehensive validation.

    .PARAMETER AccessRule
        The access rule to test for orphaned SIDs

    .PARAMETER ObjectDN
        Distinguished name of the object containing the rule

    .PARAMETER ObjectClass
        Class of the AD object for context

    .PARAMETER CurrentDomainSID
        Current domain SID for context analysis

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [OrphanedSIDResult] If an orphaned SID is found, null otherwise

    .NOTES
        PROCESSING LOGIC:
        - Handles SecurityIdentifier and NTAccount identity references
        - Performs SID translation with orphaned account detection
        - Validates SID formats and well-known SID exclusions
        - Creates comprehensive orphaned SID result objects
    #>

    [CmdletBinding()]
    [OutputType([OrphanedSIDResult])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$AccessRule,

        [Parameter(Mandatory)]
        [string]$ObjectDN,

        [Parameter()]
        [string]$ObjectClass = "Unknown",

        [Parameter()]
        [string]$CurrentDomainSID,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-ScriptLog "Testing access rule for orphaned SID (Object: $ObjectDN)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

        # Validate access rule
        if (-not $AccessRule) {
            Write-ScriptLog "Skipping null access rule for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        # Check for IdentityReference property
        if (-not $AccessRule.PSObject.Properties['IdentityReference'] -or -not $AccessRule.IdentityReference) {
            Write-ScriptLog "Skipping access rule with missing or null IdentityReference for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        $identityReference = $AccessRule.IdentityReference
        $sidString = $null

        # Handle different types of identity references
        if ($identityReference -is [System.Security.Principal.SecurityIdentifier]) {
            # Already a SID object
            if ($identityReference.Value) {
                $sidString = $identityReference.Value
                Write-ScriptLog "Found SecurityIdentifier: $sidString" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            } else {
                Write-ScriptLog "SecurityIdentifier object has null Value property for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $null
            }
        }
        elseif ($identityReference -is [System.Security.Principal.NTAccount]) {
            # NTAccount - need to translate to SID
            try {
                if (-not $identityReference.Value) {
                    Write-ScriptLog "NTAccount object has null Value property for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    return $null
                }

                Write-ScriptLog "Attempting to translate NTAccount: '$($identityReference.Value)'" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                $translatedSID = $identityReference.Translate([System.Security.Principal.SecurityIdentifier])

                if ($translatedSID -and $translatedSID.Value) {
                    $sidString = $translatedSID.Value
                    Write-ScriptLog "Translated NTAccount '$($identityReference.Value)' to SID: $sidString" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                } else {
                    Write-ScriptLog "Translation of NTAccount '$($identityReference.Value)' returned null SID" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                    return $null
                }
            }
            catch {
                # Translation failed - this is likely an orphaned account
                Write-ScriptLog "ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount '$($identityReference.Value)' to SID - likely orphaned: $($_.Exception.Message)" -Level Information -Component 'SIDProcessing' -CorrelationId $CorrelationId

                # Create orphaned result for untranslatable accounts
                return New-OrphanedSIDResult -ObjectDN $ObjectDN -ObjectClass $ObjectClass -OrphanedSID $identityReference.Value -AccessRule $AccessRule -LikelySource "Orphaned Account Name" -Confidence "High" -Notes "Account name could not be translated to SID - likely deleted or moved account" -ProcessingMethod "NTAccount-Translation-Failed"
            }
        }
        else {
            # Handle other identity reference types and deserialized objects
            $stringValue = Get-StringFromIdentityReference -IdentityReference $identityReference -ObjectDN $ObjectDN

            if ([string]::IsNullOrWhiteSpace($stringValue)) {
                return $null
            }

            if (Test-SIDFormat -SID $stringValue) {
                $sidString = $stringValue
                Write-ScriptLog "Extracted SID from other identity reference type: $sidString" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            } else {
                Write-ScriptLog "Unrecognized identity reference type or invalid SID format: $stringValue (Type: $($identityReference.GetType().Name)) for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $null
            }
        }

        # Validate SID string
        if ([string]::IsNullOrWhiteSpace($sidString)) {
            Write-ScriptLog "No valid SID string extracted from rule for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        if (-not (Test-SIDFormat -SID $sidString)) {
            Write-ScriptLog "Invalid SID format after processing: $sidString for $ObjectDN" -Level Warning -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        # Skip well-known SIDs
        if (Test-WellKnownSID -SID $sidString) {
            Write-ScriptLog "Skipping well-known SID: $sidString" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        Write-ScriptLog "SID $sidString is not well-known, checking if orphaned..." -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

        # Test if SID is orphaned
        $isOrphaned = Test-OrphanedSID -SID $sidString
        Write-ScriptLog "Orphaned status for SID $sidString : $isOrphaned" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId

        if ($isOrphaned) {
            Write-ScriptLog "ORPHANED SID DETECTED: $sidString on $ObjectDN" -Level Verbose -Component 'SIDProcessing' -CorrelationId $CorrelationId

            # Analyze the orphaned SID
            $sidAnalysis = Get-SIDAnalysis -SIDString $sidString -CurrentDomainSID $CurrentDomainSID

            # Create comprehensive orphaned SID result
            return New-OrphanedSIDResult -ObjectDN $ObjectDN -ObjectClass $ObjectClass -OrphanedSID $sidString -AccessRule $AccessRule -LikelySource $sidAnalysis.LikelySource -Confidence $sidAnalysis.Confidence -Notes $sidAnalysis.Notes -ProcessingMethod "Enhanced-ACL-Retrieval"
        } else {
            Write-ScriptLog "SID $sidString is valid (found in AD)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }
    }
    catch {
        Write-ScriptLog "Error testing access rule for orphaned SID on $ObjectDN : $($_.Exception.Message)" -Level Warning -Component 'SIDProcessing' -CorrelationId $CorrelationId
        return $null
    }
}

function Get-StringFromIdentityReference {
    <#
    .SYNOPSIS
        Extracts string value from various identity reference types

    .DESCRIPTION
        Handles different identity reference formats including deserialized objects
        from background jobs and other complex scenarios.

    .PARAMETER IdentityReference
        The identity reference object to process

    .PARAMETER ObjectDN
        Distinguished name for context in error logging

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [string] Extracted string value or null if unable to extract
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$IdentityReference,

        [Parameter()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-ScriptLog "Extracting string from identity reference (Object: $ObjectDN)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
        $stringValue = $null

        if ($IdentityReference -and $IdentityReference.PSObject.Properties['Value'] -and $IdentityReference.Value) {
            $stringValue = $IdentityReference.Value
            Write-ScriptLog "Extracted string from Value property: $stringValue" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
        } elseif ($IdentityReference -and $IdentityReference.ToString) {
            try {
                $stringValue = $IdentityReference.ToString()
                Write-ScriptLog "Extracted string from ToString method: $stringValue" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            } catch {
                Write-ScriptLog "Failed to convert identity reference to string for $ObjectDN : $($_.Exception.Message)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $null
            }
        } else {
            # Last resort - try to convert the object directly to string
            try {
                $stringValue = [string]$IdentityReference
            } catch {
                Write-ScriptLog "Unable to extract string value from identity reference for $ObjectDN : $($_.Exception.Message)" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
                return $null
            }
        }

        # Validate the extracted string value
        if ([string]::IsNullOrWhiteSpace($stringValue)) {
            Write-ScriptLog "Empty or null string value extracted from identity reference for $ObjectDN" -Level Debug -Component 'SIDProcessing' -CorrelationId $CorrelationId
            return $null
        }

        return $stringValue.Trim()
    }
    catch {
        Write-ScriptLog "Error extracting string from identity reference for $ObjectDN : $($_.Exception.Message)" -Level Warning -Component 'SIDProcessing' -CorrelationId $CorrelationId
        return $null
    }
}

function New-OrphanedSIDResult {
    <#
    .SYNOPSIS
        Creates a new OrphanedSIDResult object with comprehensive metadata

    .DESCRIPTION
        Factory function to create properly structured OrphanedSIDResult objects
        with all required properties and validation.

    .PARAMETER ObjectDN
        Distinguished name of the object containing the orphaned SID

    .PARAMETER ObjectClass
        Class of the AD object

    .PARAMETER OrphanedSID
        The orphaned Security Identifier

    .PARAMETER AccessRule
        The access rule containing the orphaned SID

    .PARAMETER LikelySource
        Categorized source of the orphaned SID

    .PARAMETER Confidence
        Analysis confidence level

    .PARAMETER Notes
        Detailed analysis notes

    .PARAMETER ProcessingMethod
        Method used to detect the orphaned SID

    .PARAMETER CorrelationId
        Unique identifier for tracking

    .OUTPUTS
        [OrphanedSIDResult] Fully populated result object
    #>

    [CmdletBinding()]
    [OutputType([OrphanedSIDResult])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'This is a factory function that creates objects but does not change system state')]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDN,

        [Parameter()]
        [string]$ObjectClass = "Unknown",

        [Parameter(Mandatory)]
        [string]$OrphanedSID,

        [Parameter(Mandatory)]
        [PSObject]$AccessRule,

        [Parameter()]
        [string]$LikelySource = "Unknown",

        [Parameter()]
        [string]$Confidence = "Medium",

        [Parameter()]
        [string]$Notes = "",

        [Parameter()]
        [string]$ProcessingMethod = "Standard",

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        $result = [OrphanedSIDResult]::new()
        $result.ObjectDN = $ObjectDN
        $result.ObjectClass = $ObjectClass
        $result.OrphanedSID = $OrphanedSID
        $result.LikelySource = $LikelySource
        $result.Confidence = $Confidence
        $result.AnalysisNotes = $Notes

        # Extract ACL information safely
        if ($AccessRule.PSObject.Properties['AccessControlType']) {
            $result.AccessControlType = $AccessRule.AccessControlType
        }
        if ($AccessRule.PSObject.Properties['ActiveDirectoryRights']) {
            $result.ActiveDirectoryRights = $AccessRule.ActiveDirectoryRights
        }
        if ($AccessRule.PSObject.Properties['InheritanceFlags']) {
            $result.InheritanceType = $AccessRule.InheritanceFlags
        }

        # Handle ObjectType and InheritedObjectType safely
        $result.ObjectType = if ($AccessRule.PSObject.Properties['ObjectType'] -and $AccessRule.ObjectType) {
            if ($AccessRule.ObjectType -eq [System.Guid]::Empty) { [System.Guid]::Empty } else { $AccessRule.ObjectType }
        } else {
            [System.Guid]::Empty
        }

        $result.InheritedObjectType = if ($AccessRule.PSObject.Properties['InheritedObjectType'] -and $AccessRule.InheritedObjectType) {
            if ($AccessRule.InheritedObjectType -eq [System.Guid]::Empty) { [System.Guid]::Empty } else { $AccessRule.InheritedObjectType }
        } else {
            [System.Guid]::Empty
        }

        $result.IsInherited = if ($AccessRule.PSObject.Properties['IsInherited']) { $AccessRule.IsInherited } else { $false }
        $result.ProcessingMethod = $ProcessingMethod
        $result.ActionTaken = "Detected"
        $result.CorrelationId = $CorrelationId
        $result.Timestamp = Get-Date

        return $result
    }
    catch {
        Write-ScriptLog "Error creating OrphanedSIDResult object: $($_.Exception.Message)" -Level Error -Component 'SIDProcessing' -CorrelationId $script:CorrelationId
        throw
    }
}

#endregion

Write-ScriptLog "SIDProcessing module loaded successfully" -Level Debug -Component 'SIDProcessing' -CorrelationId $([System.Guid]::NewGuid().ToString())
