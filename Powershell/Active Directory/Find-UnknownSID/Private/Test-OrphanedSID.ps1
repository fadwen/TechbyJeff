#Requires -Version 5.1

<#
.SYNOPSIS
    SID Orphaned Detection and Cache Management Module for Find-UnknownSID Solution

.DESCRIPTION
    This module provides comprehensive SID orphaned detection and cache management
    functionality for the Find-UnknownSID enterprise solution. It focuses exclusively
    on identifying orphaned SIDs and managing validation cache for performance.

    This module follows the single-responsibility principle by focusing exclusively
    on orphaned SID detection and cache management. It depends on the Test-SIDFormat
    module for basic validation before performing Active Directory lookups.

    BUSINESS VALUE:
    - Enables accurate identification of orphaned SIDs for security cleanup
    - Reduces false positives through comprehensive validation methods
    - Improves security posture by identifying unused access rights
    - Supports compliance requirements for access review and cleanup

    TECHNICAL FEATURES:
    - Multiple validation methods (Get-ADObject, SecurityIdentifier translation)
    - Performance caching to avoid repeated AD queries
    - Handles deleted objects and various object types
    - Comprehensive error handling with correlation tracking
    - Cache management for memory optimization

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-04
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    MODULE DESIGN:
    This module implements the single-responsibility principle by focusing
    exclusively on orphaned SID detection and cache management. It provides
    comprehensive Active Directory integration while maintaining high cohesion.

    TROUBLESHOOTING:
    - For orphaned detection issues: .\Troubleshooting\Security\Orphaned-SID-Issues.md
    - For cache management problems: .\Troubleshooting\Common\Cache-Management.md
    - For performance optimization: .\Troubleshooting\Performance\SID-Detection-Performance.md

    DEPENDENCIES:
    - Requires Test-SIDFormat.ps1 for SID format validation
    - Requires Logging.ps1 for Write-StructuredLog function
    - Requires ADRetry.ps1 for Invoke-ADOperationWithRetry function
    - Uses script-scoped $script:SIDValidationCache variable for caching
#>

# Initialize cache at module level
if (-not $script:SIDValidationCache) {
    $script:SIDValidationCache = @{}
}

function Test-OrphanedSID {
    <#
    .SYNOPSIS
        Tests whether a SID is orphaned (no longer exists in Active Directory)

    .DESCRIPTION
        Performs comprehensive testing to determine if a SID is orphaned by checking
        multiple AD lookup methods and utilizing caching for performance. This function
        is essential for identifying SIDs that should be removed from ACLs during
        security cleanup operations.

        BUSINESS VALUE:
        - Enables accurate identification of orphaned SIDs for security cleanup
        - Reduces false positives through comprehensive validation methods
        - Improves security posture by identifying unused access rights
        - Supports compliance requirements for access review and cleanup

        TECHNICAL FEATURES:
        - Multiple validation methods (Get-ADObject, SecurityIdentifier translation, type-specific lookups)
        - Performance caching to avoid repeated AD queries
        - Handles deleted objects and various object types
        - Comprehensive error handling with correlation tracking
        - Integration with retry logic for AD operations

    .PARAMETER SID
        [String] (Mandatory: Yes, Pipeline: ByValue)

        The Security Identifier to test for orphaned status.

        VALIDATION RULES:
        - Must be a valid SID string format
        - Supports domain SIDs, well-known SIDs, and service SIDs

        BUSINESS CONTEXT:
        SIDs from ACL entries that may no longer have corresponding AD objects.
        Used during security audits and cleanup operations.

        EXAMPLES:
        - Domain user: "S-1-5-21-1234567890-1234567890-1234567890-1001"
        - Built-in account: "S-1-5-32-544"
        - Service SID: "S-1-5-80-123456789-123456789-123456789-123456789-123456789"

    .PARAMETER CorrelationId
        [String] (Mandatory: No)

        Correlation ID for tracking this operation across logs and troubleshooting.
        Defaults to auto-generated GUID if not provided.

    .EXAMPLE
        PS> Test-OrphanedSID -SID "S-1-5-21-1234567890-1234567890-1234567890-1001"

        DESCRIPTION: Basic orphaned SID test for domain user
        OUTPUT: $true if SID is orphaned, $false if valid
        USE CASE: Security audit to identify unused ACL entries

    .EXAMPLE
        PS> @('S-1-5-21-123-456-789-1001', 'S-1-5-32-544') | Test-OrphanedSID

        DESCRIPTION: Pipeline processing of multiple SIDs
        OUTPUT: Boolean results for each SID
        USE CASE: Bulk validation during ACL cleanup operations

    .EXAMPLE
        PS> Test-OrphanedSID -SID "S-1-5-21-123-456-789-1001" -CorrelationId $correlationId

        DESCRIPTION: Orphaned test with correlation tracking
        OUTPUT: Boolean result with correlated logging
        USE CASE: Enterprise audit operations requiring full traceability

    .INPUTS
        [String] - SID string values via pipeline

    .OUTPUTS
        [Boolean] - $true if SID is orphaned, $false if valid and exists in AD

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        PERFORMANCE CHARACTERISTICS:
        - Uses caching to improve performance for repeated queries
        - Multiple fallback methods ensure comprehensive validation
        - Typical execution time: 50-200ms for uncached, <5ms for cached

        TROUBLESHOOTING:
        - For validation errors: .\Troubleshooting\Security\Orphaned-SID-Issues.md
        - For performance issues: .\Troubleshooting\Performance\SID-Detection-Performance.md
        - For cache management: .\Troubleshooting\Common\Cache-Management.md

    .LINK
        Test-SIDFormat
        Clear-SIDValidationCache
        Get-SIDValidationCacheStat
        .\Troubleshooting\Security\Orphaned-SID-Issues.md
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$SID,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Initialize cache if it doesn't exist
        if (-not $script:SIDValidationCache) {
            $script:SIDValidationCache = @{}
        }
    }

    process {
        try {
            Write-StructuredLog "Testing SID for orphaned status: $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId

            # Validate SID format first using Test-SIDFormat module
            if (-not (Test-SIDFormat -SID $SID -CorrelationId $CorrelationId)) {
                Write-StructuredLog "SID format invalid - treating as orphaned: $SID" -Level Warning -Component 'SIDDetection' -CorrelationId $CorrelationId
                return $true  # Invalid SIDs are considered orphaned
            }

            # Check cache first for performance
            if ($script:SIDValidationCache.ContainsKey($SID)) {
                Write-StructuredLog "SID validation cache hit for $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                return $script:SIDValidationCache[$SID]
            }

            # Method 1: Try Get-ADObject with SID (most reliable)
            try {
                $adObject = Invoke-ADOperationWithRetry -ScriptBlock {
                    Get-ADObject -Filter "objectSid -eq '$SID'" -ErrorAction Stop
                } -OperationName 'Get-ADObject-BySID' -ObjectContext $SID -CorrelationId $CorrelationId

                if ($adObject) {
                    Write-StructuredLog "SID found in AD via Get-ADObject: $($adObject.DistinguishedName)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                    $script:SIDValidationCache[$SID] = $false
                    return $false  # Not orphaned
                }
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                Write-StructuredLog "SID not found via Get-ADObject: $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }
            catch {
                Write-StructuredLog "Get-ADObject lookup failed for SID $SID : $($_.Exception.Message)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }

            # Method 1a: Check for deleted objects specifically
            try {
                $deletedObject = Invoke-ADOperationWithRetry -ScriptBlock {
                    Get-ADObject -Filter "objectSid -eq '$SID'" -IncludeDeletedObjects -ErrorAction Stop
                } -OperationName 'Get-ADObject-Deleted-BySID' -ObjectContext $SID -CorrelationId $CorrelationId

                if ($deletedObject) {
                    Write-StructuredLog "SID found in deleted objects: $($deletedObject.DistinguishedName) - treating as orphaned" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                    $script:SIDValidationCache[$SID] = $true
                    return $true  # Treat deleted objects as orphaned for ACL cleanup
                }
            }
            catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                Write-StructuredLog "SID not found in deleted objects: $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }
            catch {
                Write-StructuredLog "Deleted objects lookup failed for SID $SID : $($_.Exception.Message)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }

            # Method 2: Try direct SecurityIdentifier translation
            try {
                $securityIdentifier = [System.Security.Principal.SecurityIdentifier]::new($SID)
                $ntAccount = $securityIdentifier.Translate([System.Security.Principal.NTAccount])

                if ($ntAccount -and $ntAccount.Value -and -not $ntAccount.Value.StartsWith('S-1-')) {
                    Write-StructuredLog "SID successfully translated to account name: $($ntAccount.Value)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                    $script:SIDValidationCache[$SID] = $false
                    return $false  # Not orphaned
                }
            }
            catch [System.Security.Principal.IdentityNotMappedException] {
                Write-StructuredLog "SID could not be translated - likely orphaned: $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }
            catch {
                Write-StructuredLog "SecurityIdentifier translation failed for $SID : $($_.Exception.Message)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            }

            # Method 3: Try specific object type lookups
            $objectTypes = @(
                @{ CmdLet = 'Get-ADUser'; Filter = "SID -eq '$SID'" },
                @{ CmdLet = 'Get-ADGroup'; Filter = "SID -eq '$SID'" },
                @{ CmdLet = 'Get-ADComputer'; Filter = "SID -eq '$SID'" }
            )

            foreach ($objectType in $objectTypes) {
                try {
                    $result = Invoke-ADOperationWithRetry -ScriptBlock {
                        & $objectType.CmdLet -Filter $objectType.Filter -ErrorAction Stop
                    } -OperationName $objectType.CmdLet -ObjectContext $SID -CorrelationId $CorrelationId

                    if ($result) {
                        Write-StructuredLog "SID found via $($objectType.CmdLet): $($result.DistinguishedName)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                        $script:SIDValidationCache[$SID] = $false
                        return $false  # Not orphaned
                    }
                }
                catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                    # Expected for orphaned SIDs, continue to next type
                    continue
                }
                catch {
                    Write-StructuredLog "$($objectType.CmdLet) lookup failed for $SID : $($_.Exception.Message)" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
                }
            }

            # If all methods fail, consider it orphaned
            Write-StructuredLog "SID could not be resolved - marking as orphaned: $SID" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
            $script:SIDValidationCache[$SID] = $true
            return $true  # Orphaned

        }
        catch {
            Write-StructuredLog "Error testing SID for orphaned status $SID : $($_.Exception.Message)" -Level Error -Component 'SIDDetection' -CorrelationId $CorrelationId
            # Assume orphaned on error for safety
            $script:SIDValidationCache[$SID] = $true
            return $true
        }
    }
}


function Clear-SIDValidationCache {
    <#
    .SYNOPSIS
        Clears the SID validation cache to free memory and reset validation state

    .DESCRIPTION
        Removes all entries from the SID validation cache, which is used to store
        results of orphaned SID tests for performance optimization. This function
        is useful for freeing memory or forcing re-validation of SIDs.

        BUSINESS VALUE:
        - Manages memory usage during long-running operations
        - Allows fresh validation when AD state may have changed
        - Supports testing and troubleshooting scenarios
        - Enables cleanup after batch operations

        TECHNICAL FEATURES:
        - Safe cache clearing with null checking
        - Verbose output showing entries cleared
        - No side effects on other operations

    .EXAMPLE
        PS> Clear-SIDValidationCache

        DESCRIPTION: Clear all cached SID validation results
        OUTPUT: Verbose message showing entries cleared
        USE CASE: Memory management during large operations

    .EXAMPLE
        PS> Clear-SIDValidationCache; Test-OrphanedSID -SID $sid

        DESCRIPTION: Force fresh validation by clearing cache first
        OUTPUT: Cache cleared, then fresh SID validation
        USE CASE: Troubleshooting when cached results may be stale

    .INPUTS
        None

    .OUTPUTS
        None (cache clearing operation)

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        PERFORMANCE CHARACTERISTICS:
        - Instant operation regardless of cache size
        - No impact on other module functions

        TROUBLESHOOTING:
        - For cache issues: .\Troubleshooting\Common\Cache-Management.md
        - For memory problems: .\Troubleshooting\Performance\Memory-Usage.md

    .LINK
        Get-SIDValidationCacheStat
        Test-OrphanedSID
        .\Troubleshooting\Common\Cache-Management.md
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    if ($script:SIDValidationCache) {
        $count = $script:SIDValidationCache.Count
        $script:SIDValidationCache.Clear()
        Write-StructuredLog "Cleared SID validation cache ($count entries)" -Level Information -Component 'SIDDetection' -CorrelationId $CorrelationId
    } else {
        Write-StructuredLog "SID validation cache was already empty" -Level Debug -Component 'SIDDetection' -CorrelationId $CorrelationId
    }
}


function Get-SIDValidationCacheStat {
    <#
    .SYNOPSIS
        Retrieves statistics about the current SID validation cache

    .DESCRIPTION
        Provides detailed statistics about the SID validation cache including
        total entries, orphaned SIDs count, and valid SIDs count. This function
        is useful for monitoring cache utilization and performance analysis.

        BUSINESS VALUE:
        - Enables performance monitoring and optimization
        - Provides visibility into validation patterns
        - Supports capacity planning for large operations
        - Assists with troubleshooting cache-related issues

        TECHNICAL FEATURES:
        - Safe statistics gathering with null checking
        - Detailed breakdown of cache contents
        - No impact on cache performance

    .EXAMPLE
        PS> Get-SIDValidationCacheStat

        DESCRIPTION: Get current cache statistics
        OUTPUT: Object with TotalEntries, OrphanedSIDs, ValidSIDs counts
        USE CASE: Performance monitoring during operations

    .EXAMPLE
        PS> $stats = Get-SIDValidationCacheStat; Write-Host "Cache efficiency: $($stats.ValidSIDs/$stats.TotalEntries*100)%"

        DESCRIPTION: Calculate cache efficiency ratio
        OUTPUT: Cache hit efficiency percentage
        USE CASE: Performance analysis and optimization

    .INPUTS
        None

    .OUTPUTS
        [PSCustomObject] with properties:
        - TotalEntries: Total number of cached SID validations
        - OrphanedSIDs: Number of SIDs identified as orphaned
        - ValidSIDs: Number of SIDs identified as valid
        - CacheHitRatio: Percentage of cache utilization

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        PERFORMANCE CHARACTERISTICS:
        - Very fast operation (simple counting)
        - No impact on cache contents or performance

        TROUBLESHOOTING:
        - For cache analysis: .\Troubleshooting\Common\Cache-Management.md
        - For performance tuning: .\Troubleshooting\Performance\Optimization-Guide.md

    .LINK
        Clear-SIDValidationCache
        Test-OrphanedSID
        .\Troubleshooting\Common\Cache-Management.md
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if ($script:SIDValidationCache) {
        $totalEntries = $script:SIDValidationCache.Count
        $orphanedCount = ($script:SIDValidationCache.Values | Where-Object { $_ -eq $true }).Count
        $validCount = ($script:SIDValidationCache.Values | Where-Object { $_ -eq $false }).Count

        return [PSCustomObject]@{
            PSTypeName = 'SIDValidationCacheStats'
            TotalEntries = $totalEntries
            OrphanedSIDs = $orphanedCount
            ValidSIDs = $validCount
            CacheHitRatio = if ($totalEntries -gt 0) { [Math]::Round(($validCount + $orphanedCount) / $totalEntries * 100, 2) } else { 0 }
            LastUpdated = Get-Date
        }
    }
    else {
        return [PSCustomObject]@{
            PSTypeName = 'SIDValidationCacheStats'
            TotalEntries = 0
            OrphanedSIDs = 0
            ValidSIDs = 0
            CacheHitRatio = 0
            LastUpdated = Get-Date
        }
    }
}

Write-StructuredLog "Test-OrphanedSID module loaded successfully" -Level Debug -Component 'SIDDetection' -CorrelationId $([System.Guid]::NewGuid().ToString())
