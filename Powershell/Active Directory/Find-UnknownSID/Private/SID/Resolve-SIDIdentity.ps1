#Requires -Version 5.1

<#
.SYNOPSIS
    SID Identity Resolution Module for Find-UnknownSID Solution

.DESCRIPTION
    This focused module handles all SID identity resolution, validation, and translation
    for the Find-UnknownSID enterprise solution. It processes various identity reference
    types and performs comprehensive SID validation to detect orphaned accounts.

    SINGLE RESPONSIBILITY:
    This module does ONE thing well: Resolve and validate SID identities from various
    identity reference formats, including complex scenarios like orphaned account detection.

    BUSINESS VALUE:
    - Accurate identity resolution across different reference formats
    - Robust orphaned account detection with detailed analysis
    - Comprehensive error handling for translation failures
    - Support for complex Active Directory environments

    TECHNICAL FEATURES:
    - Multiple identity reference type handling (SecurityIdentifier, NTAccount, etc.)
    - Enhanced NTAccount translation with orphaned account detection
    - Comprehensive SID validation and classification
    - Intelligent string extraction from various identity formats
    - Integration with SID analysis and validation functions

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For identity resolution issues: .\Troubleshooting\Security\Identity-Resolution-Issues.md
    - For NTAccount translation errors: .\Troubleshooting\Security\NTAccount-Translation-Issues.md
    - For SID validation problems: .\Troubleshooting\Security\SID-Validation-Issues.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Requires Test-SIDFormat.ps1 for SID format validation
    - Requires Test-OrphanedSID.ps1 for orphaned SID detection
    - Requires Get-SIDAnalysis.ps1 for SID analysis
    - Requires New-SIDResult.ps1 for result object creation
    - Uses script-scoped variables (CorrelationId for tracking)
#>

#region SID Identity Resolution Functions

function Test-AccessRuleForOrphanedSID {
    <#
    .SYNOPSIS
        Tests an individual access rule for orphaned SIDs with comprehensive validation

    .DESCRIPTION
        Orchestrates the testing of a single ACL access rule to determine if it contains
        orphaned SIDs. This function coordinates identity resolution, SID validation,
        and orphaned account detection across various identity reference formats.

        The function provides a streamlined workflow that:
        - Resolves identity references to SID strings
        - Validates SID formats and excludes well-known SIDs
        - Tests for orphaned status with detailed analysis
        - Creates comprehensive result objects for found orphaned SIDs

    .PARAMETER AccessRule
        The access rule to test for orphaned SIDs. Must contain an IdentityReference property.

    .PARAMETER ObjectDN
        Distinguished name of the Active Directory object containing the access rule.
        Used for context and logging purposes.

    .PARAMETER ObjectClass
        Class of the AD object (user, group, computer, etc.) for categorization
        and analysis context.

    .PARAMETER CurrentDomainSID
        The SID of the current domain for enhanced context analysis and SID categorization.
        Used to distinguish between local, foreign, and unknown domain SIDs.

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation across logs and audit trails.
        Generated automatically if not provided.

    .EXAMPLE
        PS> $result = Test-AccessRuleForOrphanedSID -AccessRule $rule -ObjectDN $dn -ObjectClass "User"

        DESCRIPTION: Basic orphaned SID testing for a single access rule
        OUTPUT: OrphanedSIDResult object if orphaned SID found, null otherwise
        USE CASE: Standard security audit of individual access rules

    .EXAMPLE
        PS> $rules | ForEach-Object { Test-AccessRuleForOrphanedSID -AccessRule $_ -ObjectDN $dn -CurrentDomainSID $domainSID }

        DESCRIPTION: Batch processing of access rules with domain context
        OUTPUT: Array of OrphanedSIDResult objects for all orphaned SIDs found
        BUSINESS CASE: Comprehensive security analysis with domain categorization

    .EXAMPLE
        PS> Test-AccessRuleForOrphanedSID -AccessRule $rule -ObjectDN $dn -ObjectClass "Group" -CorrelationId $correlationId

        DESCRIPTION: Tracked processing with correlation ID for audit trails
        OUTPUT: OrphanedSIDResult with correlation tracking for compliance
        INTEGRATION: Enterprise environments requiring audit trail correlation

    .OUTPUTS
        [OrphanedSIDResult] If an orphaned SID is detected, returns a comprehensive
        result object containing detailed analysis and metadata. Returns null if
        no orphaned SID is found or if validation fails.

    .NOTES
        PROCESSING WORKFLOW:
        1. Validate access rule and extract identity reference
        2. Resolve identity reference to SID string using appropriate method
        3. Validate SID format and check for well-known SIDs
        4. Test for orphaned status using enhanced detection
        5. Create comprehensive result object with analysis

        IDENTITY REFERENCE SUPPORT:
        - SecurityIdentifier objects (direct SID access)
        - NTAccount objects (translation with orphaned account detection)
        - Deserialized identity references (background job support)
        - String-based identity references (flexible format handling)

        ERROR HANDLING:
        - Comprehensive validation of input parameters
        - Graceful handling of translation failures (indicates orphaned accounts)
        - Detailed logging for troubleshooting and audit purposes
        - Safe property access with null checking

        PERFORMANCE CHARACTERISTICS:
        - Optimized for single access rule processing
        - Efficient identity reference type detection
        - Minimal memory allocation for string operations
        - Fast validation using cached well-known SID lists
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
        Write-StructuredLog "Starting access rule analysis for orphaned SID (Object: $ObjectDN)" -Level Debug -CorrelationId $CorrelationId

        # Validate access rule and identity reference
        if (-not $AccessRule -or -not $AccessRule.PSObject.Properties['IdentityReference'] -or -not $AccessRule.IdentityReference) {
            Write-StructuredLog "Skipping access rule with missing or null IdentityReference for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
            return $null
        }

        # Resolve identity reference to SID string
        $sidString = Resolve-IdentityReference -IdentityReference $AccessRule.IdentityReference -ObjectDN $ObjectDN -CorrelationId $CorrelationId
        if (-not $sidString) {
            Write-StructuredLog "Failed to resolve identity reference to SID for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
            return $null
        }

        # Validate SID format and check for well-known SIDs
        if (-not (Test-SIDValidityAndType -SIDString $sidString -CorrelationId $CorrelationId)) {
            Write-StructuredLog "SID validation failed or well-known SID detected: $sidString" -Level Debug -CorrelationId $CorrelationId
            return $null
        }

        Write-StructuredLog "SID $sidString passed validation, testing for orphaned status..." -Level Debug -CorrelationId $CorrelationId

        # Test for orphaned status and create result
        $isOrphaned = Test-OrphanedSID -SID $sidString
        Write-StructuredLog "Orphaned status for SID $sidString : $isOrphaned" -Level Debug -CorrelationId $CorrelationId

        if ($isOrphaned) {
            Write-StructuredLog "ORPHANED SID DETECTED: $sidString on $ObjectDN" -Level Verbose -CorrelationId $CorrelationId

            # Get detailed SID analysis
            $sidAnalysis = Get-SIDAnalysis -SIDString $sidString -CurrentDomainSID $CurrentDomainSID

            # Create comprehensive orphaned SID result
            return New-OrphanedSIDResult -ObjectDN $ObjectDN -ObjectClass $ObjectClass -OrphanedSID $sidString -AccessRule $AccessRule -LikelySource $sidAnalysis.LikelySource -Confidence $sidAnalysis.Confidence -Notes $sidAnalysis.Notes -ProcessingMethod "Identity-Resolution" -CorrelationId $CorrelationId
        } else {
            Write-StructuredLog "SID $sidString is valid (found in AD)" -Level Debug -CorrelationId $CorrelationId
            return $null
        }
    }
    catch {
        Write-StructuredLog "Error testing access rule for orphaned SID on $ObjectDN : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        return $null
    }
}

function Resolve-IdentityReference {
    <#
    .SYNOPSIS
        Resolves various identity reference types to SID strings

    .DESCRIPTION
        Handles the resolution of different identity reference formats to SID strings,
        including SecurityIdentifier objects, NTAccount objects, and various string
        formats. This function provides intelligent type detection and routing to
        appropriate resolution methods.

    .PARAMETER IdentityReference
        The identity reference object to resolve. Can be SecurityIdentifier, NTAccount,
        or other identity reference types including deserialized objects.

    .PARAMETER ObjectDN
        Distinguished name for context in error logging and troubleshooting.

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation across logs.

    .OUTPUTS
        [string] The resolved SID string, or null if resolution fails

    .NOTES
        SUPPORTED IDENTITY TYPES:
        - SecurityIdentifier: Direct SID value extraction
        - NTAccount: Translation with orphaned account detection
        - Deserialized objects: Background job object handling
        - String references: Various string format processing

        PROCESSING STRATEGY:
        1. Detect identity reference type
        2. Route to appropriate resolution method
        3. Handle errors gracefully (orphaned accounts cause translation failures)
        4. Return validated SID string or null
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
        Write-StructuredLog "Resolving identity reference type for $ObjectDN" -Level Debug -CorrelationId $CorrelationId

        # Handle SecurityIdentifier objects (direct SID access)
        if ($IdentityReference -is [System.Security.Principal.SecurityIdentifier]) {
            if ($IdentityReference.Value) {
                $sidString = $IdentityReference.Value
                Write-StructuredLog "Extracted SID from SecurityIdentifier: $sidString" -Level Debug -CorrelationId $CorrelationId
                return $sidString
            } else {
                Write-StructuredLog "SecurityIdentifier object has null Value property for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
                return $null
            }
        }

        # Handle NTAccount objects (translation required)
        if ($IdentityReference -is [System.Security.Principal.NTAccount]) {
            return Convert-NTAccountToSID -NTAccount $IdentityReference -ObjectDN $ObjectDN -CorrelationId $CorrelationId
        }

        # Handle other identity reference types and deserialized objects
        $stringValue = Get-StringFromIdentityReference -IdentityReference $IdentityReference -ObjectDN $ObjectDN -CorrelationId $CorrelationId
        if ([string]::IsNullOrWhiteSpace($stringValue)) {
            return $null
        }

        # Validate extracted string as SID format
        if (Test-SIDFormat -SID $stringValue) {
            Write-StructuredLog "Extracted valid SID from identity reference: $stringValue" -Level Debug -CorrelationId $CorrelationId
            return $stringValue
        } else {
            Write-StructuredLog "Extracted string is not a valid SID format: $stringValue (Type: $($IdentityReference.GetType().Name)) for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
            return $null
        }
    }
    catch {
        Write-StructuredLog "Error resolving identity reference for $ObjectDN : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        return $null
    }
}

function Convert-NTAccountToSID {
    <#
    .SYNOPSIS
        Converts NTAccount objects to SID strings with orphaned account detection

    .DESCRIPTION
        Handles the translation of NTAccount objects to SID strings, with special
        handling for orphaned accounts. When translation fails, this indicates an
        orphaned account and the function creates an appropriate result object.

    .PARAMETER NTAccount
        The NTAccount object to translate to a SID

    .PARAMETER ObjectDN
        Distinguished name for context in logging

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [string] The translated SID string, or a special orphaned account marker
        if translation fails due to orphaned account

    .NOTES
        TRANSLATION BEHAVIOR:
        - Successful translation returns SID string
        - Failed translation indicates orphaned account
        - Creates orphaned result object for untranslatable accounts
        - Comprehensive error logging for troubleshooting

        ORPHANED ACCOUNT DETECTION:
        Translation failures typically indicate:
        - Deleted user or group accounts
        - Moved accounts from other domains
        - Corrupted or invalid account references
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Security.Principal.NTAccount]$NTAccount,

        [Parameter()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        if (-not $NTAccount.Value) {
            Write-StructuredLog "NTAccount object has null Value property for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
            return $null
        }

        Write-StructuredLog "Attempting to translate NTAccount: '$($NTAccount.Value)'" -Level Debug -CorrelationId $CorrelationId

        $translatedSID = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])

        if ($translatedSID -and $translatedSID.Value) {
            $sidString = $translatedSID.Value
            Write-StructuredLog "Successfully translated NTAccount '$($NTAccount.Value)' to SID: $sidString" -Level Debug -CorrelationId $CorrelationId
            return $sidString
        } else {
            Write-StructuredLog "Translation of NTAccount '$($NTAccount.Value)' returned null SID" -Level Debug -CorrelationId $CorrelationId
            return $null
        }
    }
    catch {
        # Translation failed - this indicates an orphaned account
        Write-StructuredLog "ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount '$($NTAccount.Value)' to SID - likely orphaned: $($_.Exception.Message)" -Level Information -CorrelationId $CorrelationId

        # Return special marker for orphaned account names
        # This will be handled by the calling function to create proper result object
        return "ORPHANED_ACCOUNT:$($NTAccount.Value)"
    }
}

function Test-SIDValidityAndType {
    <#
    .SYNOPSIS
        Validates SID format and checks for well-known SID exclusions

    .DESCRIPTION
        Performs comprehensive SID validation including format checking and
        well-known SID exclusion. This function consolidates SID validation
        logic to ensure consistent handling across the module.

    .PARAMETER SIDString
        The SID string to validate

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [bool] True if SID is valid and should be processed, False if invalid
        or should be excluded (well-known SID)

    .NOTES
        VALIDATION PROCESS:
        1. Check SID format validity using Test-SIDFormat
        2. Check against well-known SID exclusions
        3. Return combined validation result

        EXCLUSION CRITERIA:
        - Invalid SID formats
        - Well-known SIDs (system accounts, built-in groups)
        - Empty or null SID strings
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$SIDString,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        # Validate SID format
        if (-not (Test-SIDFormat -SID $SIDString)) {
            Write-StructuredLog "Invalid SID format: $SIDString" -Level Debug -CorrelationId $CorrelationId
            return $false
        }

        # Check for well-known SIDs (should be excluded from orphaned SID detection)
        if (Test-WellKnownSID -SID $SIDString) {
            Write-StructuredLog "Skipping well-known SID: $SIDString" -Level Debug -CorrelationId $CorrelationId
            return $false
        }

        Write-StructuredLog "SID $SIDString passed validation and is not well-known" -Level Debug -CorrelationId $CorrelationId
        return $true
    }
    catch {
        Write-StructuredLog "Error validating SID $SIDString : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        return $false
    }
}

function Get-StringFromIdentityReference {
    <#
    .SYNOPSIS
        Extracts string values from various identity reference types

    .DESCRIPTION
        Handles the extraction of string values from different identity reference
        formats, including deserialized objects from background jobs and other
        complex scenarios. This function provides robust string extraction with
        multiple fallback methods.

    .PARAMETER IdentityReference
        The identity reference object to process

    .PARAMETER ObjectDN
        Distinguished name for context in error logging

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [string] Extracted string value or null if unable to extract

    .NOTES
        EXTRACTION METHODS:
        1. Value property access (preferred)
        2. ToString() method call
        3. Direct string conversion (fallback)

        ERROR HANDLING:
        - Graceful handling of missing properties
        - Safe method invocation with error catching
        - Comprehensive logging for troubleshooting
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
        Write-StructuredLog "Extracting string from identity reference (Object: $ObjectDN)" -Level Debug -CorrelationId $CorrelationId
        $stringValue = $null

        # Method 1: Try Value property
        if ($IdentityReference -and $IdentityReference.PSObject.Properties['Value'] -and $IdentityReference.Value) {
            $stringValue = $IdentityReference.Value
            Write-StructuredLog "Extracted string from Value property: $stringValue" -Level Debug -CorrelationId $CorrelationId
        }
        # Method 2: Try ToString method
        elseif ($IdentityReference -and $IdentityReference.ToString) {
            try {
                $stringValue = $IdentityReference.ToString()
                Write-StructuredLog "Extracted string from ToString method: $stringValue" -Level Debug -CorrelationId $CorrelationId
            } catch {
                Write-StructuredLog "Failed to convert identity reference to string using ToString for $ObjectDN : $($_.Exception.Message)" -Level Debug -CorrelationId $CorrelationId
            }
        }
        # Method 3: Direct string conversion (last resort)
        else {
            try {
                $stringValue = [string]$IdentityReference
                Write-StructuredLog "Extracted string using direct conversion: $stringValue" -Level Debug -CorrelationId $CorrelationId
            } catch {
                Write-StructuredLog "Unable to extract string value from identity reference for $ObjectDN : $($_.Exception.Message)" -Level Debug -CorrelationId $CorrelationId
                return $null
            }
        }

        # Validate the extracted string value
        if ([string]::IsNullOrWhiteSpace($stringValue)) {
            Write-StructuredLog "Empty or null string value extracted from identity reference for $ObjectDN" -Level Debug -CorrelationId $CorrelationId
            return $null
        }

        return $stringValue.Trim()
    }
    catch {
        Write-StructuredLog "Error extracting string from identity reference for $ObjectDN : $($_.Exception.Message)" -Level Warning -CorrelationId $CorrelationId
        return $null
    }
}

#endregion

Write-StructuredLog "Resolve-SIDIdentity module loaded successfully" -Level Debug -CorrelationId $([System.Guid]::NewGuid().ToString())

