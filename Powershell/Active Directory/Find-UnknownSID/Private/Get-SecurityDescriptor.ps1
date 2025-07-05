#Requires -Version 5.1

<#
.SYNOPSIS
    Security Descriptor Retrieval Module for Find-UnknownSID Solution

.DESCRIPTION
    This focused module handles all security descriptor retrieval and ACL processing
    scenarios for the Find-UnknownSID enterprise solution. It implements multiple
    retrieval strategies with fallback mechanisms to ensure reliable access to
    security descriptors across various Active Directory object types and states.

    SINGLE RESPONSIBILITY:
    This module does ONE thing well: Retrieve and process security descriptors
    from Active Directory objects using multiple strategies for maximum reliability.

    BUSINESS VALUE:
    - Reliable security descriptor access across different object states
    - Robust handling of deserialized objects from background jobs
    - Comprehensive fallback mechanisms for production environments
    - Optimized processing for large-scale AD environments

    TECHNICAL FEATURES:
    - Multiple security descriptor retrieval strategies (Get-Acl, binary, fresh query)
    - Support for deserialized PowerShell objects from background jobs
    - Intelligent format detection and conversion
    - Memory-efficient processing with proper cleanup
    - Comprehensive error handling and logging

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For ACL retrieval failures: .\Troubleshooting\Security\Security-Descriptor-Issues.md
    - For binary processing errors: .\Troubleshooting\Security\Binary-Descriptor-Processing.md
    - For performance optimization: .\Troubleshooting\Performance\Security-Descriptor-Performance.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Uses script-scoped variables (CorrelationId for tracking)
#>

#region Security Descriptor Retrieval Functions

function Get-ObjectAccessRule {
    <#
    .SYNOPSIS
        Retrieves access rules from AD object security descriptors using multiple strategies

    .DESCRIPTION
        Orchestrates the retrieval of ACL access rules from Active Directory objects
        using multiple fallback methods to ensure reliable access across various
        scenarios including deserialized objects, binary descriptors, and fresh queries.

        This function coordinates three retrieval strategies:
        1. Get-Acl method (preferred for reliability)
        2. Binary security descriptor processing (handles various formats)
        3. Fresh AD query (last resort fallback)

    .PARAMETER ADObject
        Active Directory object containing security descriptor. Can be from Get-ADObject
        output, background job results, or pipeline input.

    .PARAMETER IncludeInherited
        When specified, includes inherited ACL entries in the results.
        By default, only explicit (non-inherited) ACL entries are returned.

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation across logs and audit trails.
        Generated automatically if not provided.

    .EXAMPLE
        PS> $accessRules = Get-ObjectAccessRule -ADObject $adObject

        DESCRIPTION: Basic ACL retrieval for explicit permissions only
        OUTPUT: Array of ActiveDirectoryAccessRule objects
        USE CASE: Standard security analysis of explicit permissions

    .EXAMPLE
        PS> $allRules = Get-ObjectAccessRule -ADObject $adObject -IncludeInherited

        DESCRIPTION: Comprehensive ACL retrieval including inherited permissions
        OUTPUT: Complete set of access rules including inheritance
        BUSINESS CASE: Thorough security audit requiring all permission sources

    .EXAMPLE
        PS> $jobResults | Get-ObjectAccessRule -CorrelationId $correlationId

        DESCRIPTION: Processing deserialized objects from background jobs
        OUTPUT: Access rules extracted from job results with correlation tracking
        INTEGRATION: Large-scale parallel processing scenarios

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        extracted from the security descriptor, or null if retrieval fails

    .NOTES
        RETRIEVAL STRATEGY:
        1. Get-Acl Method: Uses PowerShell's Get-Acl for standard retrieval
        2. Binary Processing: Handles binary, Base64, and deserialized formats
        3. Fresh Query: Performs new AD query as last resort

        PERFORMANCE CHARACTERISTICS:
        - Get-Acl: Fastest and most reliable for standard objects
        - Binary Processing: Handles complex scenarios (background jobs)
        - Fresh Query: Slowest but most comprehensive fallback

        ERROR HANDLING:
        - Each method includes comprehensive error handling
        - Graceful fallback between methods
        - Detailed logging for troubleshooting
        - Memory cleanup after processing

        COMPATIBILITY:
        - Supports PowerShell 5.1 and 7.x environments
        - Handles deserialized objects from background jobs
        - Works with various security descriptor formats
    #>

    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectoryAccessRule[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$ADObject,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            $objectDN = $ADObject.DistinguishedName
            Write-StructuredLog "Starting security descriptor retrieval for: $objectDN (IncludeInherited: $IncludeInherited)" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

            # Strategy 1: Try Get-Acl method (preferred for reliability)
            $accessRules = Get-SecurityDescriptorFromGetAcl -ADObject $ADObject -IncludeInherited:$IncludeInherited -CorrelationId $CorrelationId
            if ($accessRules) {
                Write-StructuredLog "Successfully retrieved access rules using Get-Acl method for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
                return $accessRules
            }

            # Strategy 2: Try binary/deserialized processing
            $accessRules = Get-SecurityDescriptorFromBinary -ADObject $ADObject -IncludeInherited:$IncludeInherited -CorrelationId $CorrelationId
            if ($accessRules) {
                Write-StructuredLog "Successfully retrieved access rules using binary processing for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
                return $accessRules
            }

            # Strategy 3: Last resort - fresh AD query
            $accessRules = Invoke-FreshADQuery -ADObject $ADObject -IncludeInherited:$IncludeInherited -CorrelationId $CorrelationId
            if ($accessRules) {
                Write-StructuredLog "Successfully retrieved access rules using fresh AD query for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
                return $accessRules
            }

            # All methods failed
            Write-StructuredLog "All security descriptor retrieval methods failed for $objectDN" -Level Warning -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }
        catch {
            Write-StructuredLog "Unexpected error retrieving access rules for $($ADObject.DistinguishedName): $($_.Exception.Message)" -Level Error -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }
    }
}

function Get-SecurityDescriptorFromGetAcl {
    <#
    .SYNOPSIS
        Retrieves security descriptor using PowerShell's Get-Acl cmdlet

    .DESCRIPTION
        Uses the Get-Acl cmdlet to retrieve security descriptors from AD objects.
        This is the preferred method for standard objects as it's the most reliable
        and performant approach.

    .PARAMETER ADObject
        Active Directory object containing security descriptor

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        or null if Get-Acl fails

    .NOTES
        METHOD CHARACTERISTICS:
        - Fastest and most reliable for standard AD objects
        - Direct PowerShell cmdlet approach
        - Automatic handling of AD provider context
        - Best error handling and logging support
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
        Write-StructuredLog "Attempting Get-Acl retrieval for: $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        $acl = Get-Acl -Path "AD:\$objectDN" -ErrorAction Stop

        if (-not $acl -or -not $acl.Access) {
            Write-StructuredLog "Get-Acl returned null or empty access list for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }

        $accessRules = if ($IncludeInherited) {
            $acl.Access
        } else {
            $acl.Access | Where-Object { -not $_.IsInherited }
        }

        Write-StructuredLog "Get-Acl successfully retrieved $($accessRules.Count) access rules for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $accessRules
    }
    catch {
        Write-StructuredLog "Get-Acl failed for $($ADObject.DistinguishedName): $($_.Exception.Message)" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $null
    }
}

function Get-SecurityDescriptorFromBinary {
    <#
    .SYNOPSIS
        Processes security descriptors from binary data and deserialized objects

    .DESCRIPTION
        Handles various security descriptor formats including binary data, Base64 strings,
        and deserialized objects from PowerShell background jobs. This method provides
        robust processing for complex scenarios.

    .PARAMETER ADObject
        Active Directory object containing security descriptor

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        or null if binary processing fails

    .NOTES
        SUPPORTED FORMATS:
        - Deserialized ActiveDirectorySecurity objects (from background jobs)
        - Regular ActiveDirectorySecurity objects
        - Binary byte arrays
        - Base64 encoded strings
        - Generic byte collections

        PROCESSING STRATEGY:
        1. Detect format of security descriptor
        2. Route to appropriate processing function
        3. Extract and filter access rules
        4. Clean up references for memory management
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
        $binarySD = $ADObject.nTSecurityDescriptor

        if (-not $binarySD) {
            Write-StructuredLog "No nTSecurityDescriptor property found for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }

        Write-StructuredLog "Processing binary security descriptor for: $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        # Check for deserialized ActiveDirectorySecurity object (from background jobs)
        if ($binarySD.PSObject.TypeNames[0] -like '*Deserialized*ActiveDirectorySecurity*') {
            return Get-SecurityDescriptorFromDeserialized -SecurityDescriptor $binarySD -IncludeInherited:$IncludeInherited -ObjectDN $objectDN -CorrelationId $CorrelationId
        }

        # Check for regular ActiveDirectorySecurity object
        if ($binarySD -is [System.DirectoryServices.ActiveDirectorySecurity]) {
            Write-StructuredLog "Processing regular ActiveDirectorySecurity object for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

            $accessRules = if ($IncludeInherited) {
                $binarySD.Access
            } else {
                $binarySD.Access | Where-Object { -not $_.IsInherited }
            }

            Write-StructuredLog "Successfully processed ActiveDirectorySecurity object for $objectDN - Found $($accessRules.Count) rules" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $accessRules
        }

        # Process as binary data
        return ConvertTo-SecurityDescriptor -BinaryData $binarySD -IncludeInherited:$IncludeInherited -ObjectDN $objectDN -CorrelationId $CorrelationId
    }
    catch {
        Write-StructuredLog "Binary security descriptor processing failed for $($ADObject.DistinguishedName): $($_.Exception.Message)" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $null
    }
}

function Get-SecurityDescriptorFromDeserialized {
    <#
    .SYNOPSIS
        Processes deserialized ActiveDirectorySecurity objects from background jobs

    .DESCRIPTION
        Handles the specific case of deserialized ActiveDirectorySecurity objects
        that result from PowerShell background job processing. These objects require
        special handling due to their serialized nature.

    .PARAMETER SecurityDescriptor
        Deserialized ActiveDirectorySecurity object

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER ObjectDN
        Distinguished name for logging context

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        or null if deserialized processing fails
    #>

    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectoryAccessRule[]])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$SecurityDescriptor,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Processing deserialized ActiveDirectorySecurity object for $ObjectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        if (-not $SecurityDescriptor.Access) {
            Write-StructuredLog "Deserialized security descriptor has no Access property for $ObjectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }

        $accessRules = if ($IncludeInherited) {
            $SecurityDescriptor.Access
        } else {
            $SecurityDescriptor.Access | Where-Object { -not $_.IsInherited }
        }

        Write-StructuredLog "Successfully extracted $($accessRules.Count) access rules from deserialized security descriptor for $ObjectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $accessRules
    }
    catch {
        Write-StructuredLog "Failed to process deserialized security descriptor for $ObjectDN : $($_.Exception.Message)" -Level Warning -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $null
    }
}

function ConvertTo-SecurityDescriptor {
    <#
    .SYNOPSIS
        Converts binary data to ActiveDirectorySecurity objects

    .DESCRIPTION
        Handles conversion of various binary formats (byte arrays, Base64 strings)
        to ActiveDirectorySecurity objects for ACL processing.

    .PARAMETER BinaryData
        Binary security descriptor data in various formats

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER ObjectDN
        Distinguished name for logging context

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        or null if conversion fails
    #>

    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectoryAccessRule[]])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$BinaryData,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$ObjectDN,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog "Converting binary data to security descriptor for $ObjectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        $securityDescriptor = [System.DirectoryServices.ActiveDirectorySecurity]::new()

        # Handle different binary data formats
        if ($BinaryData -is [byte[]]) {
            Write-StructuredLog "Processing byte array security descriptor" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            $securityDescriptor.SetSecurityDescriptorBinaryForm($BinaryData)
        }
        elseif ($BinaryData -is [string]) {
            Write-StructuredLog "Processing Base64 string security descriptor" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            $byteArray = [System.Convert]::FromBase64String($BinaryData)
            $securityDescriptor.SetSecurityDescriptorBinaryForm($byteArray)
        }
        else {
            Write-StructuredLog "Converting generic binary data to byte array" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            $byteArray = [byte[]]$BinaryData
            $securityDescriptor.SetSecurityDescriptorBinaryForm($byteArray)
        }

        $accessRules = if ($IncludeInherited) {
            $securityDescriptor.Access
        } else {
            $securityDescriptor.Access | Where-Object { -not $_.IsInherited }
        }

        Write-StructuredLog "Successfully converted binary security descriptor for $ObjectDN - Found $($accessRules.Count) rules" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        # Clean up security descriptor reference
        $securityDescriptor = $null

        return $accessRules
    }
    catch {
        Write-StructuredLog "Failed to convert binary security descriptor for $ObjectDN : $($_.Exception.Message)" -Level Warning -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $null
    }
}

function Invoke-FreshADQuery {
    <#
    .SYNOPSIS
        Performs fresh Active Directory query as last resort for security descriptor retrieval

    .DESCRIPTION
        When other methods fail, this function performs a fresh query to Active Directory
        to retrieve the security descriptor. This is the most comprehensive but slowest
        method and should only be used as a last resort.

    .PARAMETER ADObject
        Active Directory object for fresh query

    .PARAMETER IncludeInherited
        Whether to include inherited ACL entries

    .PARAMETER CorrelationId
        Unique identifier for tracking this operation

    .OUTPUTS
        [System.DirectoryServices.ActiveDirectoryAccessRule[]] Array of access rules
        or null if fresh query fails

    .NOTES
        PERFORMANCE IMPACT:
        - This method is the slowest as it performs a new AD query
        - Should only be used when other methods fail
        - Includes comprehensive error handling
        - Implements proper resource cleanup
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
        Write-StructuredLog "Attempting fresh AD query for security descriptor: $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        $freshObj = Get-ADObject -Identity $objectDN -Properties nTSecurityDescriptor -ErrorAction Stop

        if (-not $freshObj.nTSecurityDescriptor) {
            Write-StructuredLog "Fresh AD query returned no security descriptor for $objectDN" -Level Warning -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
            return $null
        }

        # Process the fresh security descriptor
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

        Write-StructuredLog "Fresh AD query successfully retrieved $($accessRules.Count) access rules for $objectDN" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $CorrelationId

        # Clean up security descriptor reference
        $securityDescriptor = $null

        return $accessRules
    }
    catch {
        Write-StructuredLog "Fresh AD query failed for $($ADObject.DistinguishedName): $($_.Exception.Message)" -Level Warning -Component 'SecurityDescriptor' -CorrelationId $CorrelationId
        return $null
    }
}

#endregion

Write-StructuredLog "Get-SecurityDescriptor module loaded successfully" -Level Debug -Component 'SecurityDescriptor' -CorrelationId $([System.Guid]::NewGuid().ToString())
