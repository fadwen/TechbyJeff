#Requires -Version 5.1

<#
.SYNOPSIS
    SID Format Validation Module for Find-UnknownSID Solution

.DESCRIPTION
    This module provides comprehensive SID format validation and well-known SID
    identification functionality for the Find-UnknownSID enterprise solution.

    This module follows the single-responsibility principle by focusing exclusively
    on SID format validation and structure checking. It serves as the foundation
    validation module for other SID processing modules.

    BUSINESS VALUE:
    - Ensures data quality by validating SID format before processing
    - Prevents processing errors from malformed SID strings
    - Identifies critical system SIDs to prevent accidental removal
    - Provides fast, lightweight validation for performance-critical operations

    TECHNICAL FEATURES:
    - Comprehensive SID format validation using .NET SecurityIdentifier
    - Well-known SID recognition with Microsoft specification compliance
    - Pipeline-optimized processing for bulk operations
    - Configuration-driven pattern matching for enterprise customization
    - Lightweight module design for selective loading

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-04
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    MODULE DESIGN:
    This module implements the single-responsibility principle by focusing
    exclusively on SID format validation. It provides the foundation for
    other SID processing modules while maintaining high cohesion and
    minimal dependencies.

    TROUBLESHOOTING:
    - For format validation issues: .\Troubleshooting\Security\SID-Format-Issues.md
    - For well-known SID issues: .\Troubleshooting\Security\Well-Known-SID-Issues.md
    - For performance optimization: .\Troubleshooting\Performance\Format-Validation-Performance.md

    DEPENDENCIES:
    - Requires Logging.ps1 for Write-StructuredLog function
    - Uses script-scoped $script:Config variable for configuration access (optional)
#>

function Test-SIDFormat {
    <#
    .SYNOPSIS
        Validates whether a string represents a properly formatted Security Identifier (SID)

    .DESCRIPTION
        Performs comprehensive validation of SID format using both pattern matching
        and .NET SecurityIdentifier object creation. This function ensures SID strings
        conform to Microsoft's SID format specifications before processing.

        BUSINESS VALUE:
        - Prevents processing errors from malformed SID strings
        - Ensures data quality in security operations
        - Reduces false positives in SID analysis
        - Supports input validation for security compliance

        TECHNICAL FEATURES:
        - Pattern-based validation for basic SID structure
        - .NET SecurityIdentifier object creation for thorough validation
        - Comprehensive error handling and logging
        - Pipeline support for bulk validation

    .PARAMETER SID
        [String] (Mandatory: Yes, Pipeline: ByValue)

        The string to validate as a SID format.

        VALIDATION RULES:
        - Must start with "S-1-" pattern
        - Must be valid according to .NET SecurityIdentifier class

        BUSINESS CONTEXT:
        Used to validate SID strings before processing in security operations.

        EXAMPLES:
        - Valid domain SID: "S-1-5-21-1234567890-1234567890-1234567890-1001"
        - Valid well-known SID: "S-1-5-32-544"
        - Invalid format: "DOMAIN\username"

    .PARAMETER CorrelationId
        [String] (Mandatory: No)

        Correlation ID for tracking this operation across logs and troubleshooting.
        Defaults to auto-generated GUID if not provided.

    .EXAMPLE
        PS> Test-SIDFormat -SID "S-1-5-21-1234567890-1234567890-1234567890-1001"

        DESCRIPTION: Basic SID format validation
        OUTPUT: $true (valid SID format)
        USE CASE: Input validation before SID processing

    .EXAMPLE
        PS> @('S-1-5-32-544', 'DOMAIN\user', 'S-1-5-21-123-456-789-1001') | Test-SIDFormat

        DESCRIPTION: Pipeline validation of multiple SID candidates
        OUTPUT: $true, $false, $true
        USE CASE: Bulk validation of SID data from various sources

    .EXAMPLE
        PS> Test-SIDFormat -SID "invalid-sid" -CorrelationId $correlationId

        DESCRIPTION: Format validation with correlation tracking
        OUTPUT: $false with detailed logging
        USE CASE: Enterprise validation operations requiring audit trails

    .INPUTS
        [String] - SID string candidates via pipeline

    .OUTPUTS
        [Boolean] - $true if valid SID format, $false otherwise

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        PERFORMANCE CHARACTERISTICS:
        - Very fast validation using .NET built-in methods
        - Typical execution time: <5ms per SID

        TROUBLESHOOTING:
        - For validation errors: .\Troubleshooting\Security\SID-Format-Issues.md
        - For format issues: .\Troubleshooting\Common\SID-Format-Problems.md

    .LINK
        Test-WellKnownSID
        .\Troubleshooting\Security\SID-Format-Issues.md
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$SID,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-StructuredLog "Validating SID format: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId

            # Basic pattern matching for performance
            if ($SID -notmatch '^S-1-\d+-\d+') {
                Write-StructuredLog "SID format invalid - does not match basic pattern: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                return $false
            }

            # Try to create SecurityIdentifier object for thorough validation
            try {
                $null = [System.Security.Principal.SecurityIdentifier]::new($SID)
                Write-StructuredLog "SID format valid: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                return $true
            }
            catch {
                Write-StructuredLog "SID format invalid - SecurityIdentifier creation failed: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                return $false
            }
        }
        catch {
            Write-StructuredLog "Error validating SID format $SID : $($_.Exception.Message)" -Level Error -Component 'SIDFormat' -CorrelationId $CorrelationId
            return $false
        }
    }
}


function Test-WellKnownSID {
    <#
    .SYNOPSIS
        Tests whether a SID is a well-known Security Identifier

    .DESCRIPTION
        Determines if a SID represents a well-known security principal by checking
        against comprehensive lists of Microsoft well-known SIDs, configuration-based
        patterns, and protected SID lists. This function is essential for preventing
        accidental removal of system-critical SIDs during cleanup operations.

        BUSINESS VALUE:
        - Prevents accidental removal of critical system SIDs
        - Ensures system stability during security cleanup operations
        - Supports compliance by protecting essential security principals
        - Reduces risk of breaking system functionality

        TECHNICAL FEATURES:
        - Comprehensive well-known SID database
        - Configuration-driven pattern matching
        - Protected SID list support
        - Domain-specific well-known SID recognition
        - Built-in domain SID detection

    .PARAMETER SID
        [String] (Mandatory: Yes, Pipeline: ByValue)

        The Security Identifier to test for well-known status.

        VALIDATION RULES:
        - Must be a valid SID string format
        - Checked against Microsoft's well-known SID specifications

        BUSINESS CONTEXT:
        Used to identify SIDs that should never be removed from ACLs due to
        their critical system importance.

        EXAMPLES:
        - System account: "S-1-5-18" (Local System)
        - Built-in group: "S-1-5-32-544" (Administrators)
        - Domain admin: "S-1-5-21-domain-512" (Domain Admins)

    .PARAMETER CorrelationId
        [String] (Mandatory: No)

        Correlation ID for tracking this operation across logs and troubleshooting.
        Defaults to auto-generated GUID if not provided.

    .EXAMPLE
        PS> Test-WellKnownSID -SID "S-1-5-18"

        DESCRIPTION: Test Local System account SID
        OUTPUT: $true (well-known system SID)
        USE CASE: Verify critical system SID protection

    .EXAMPLE
        PS> @('S-1-5-32-544', 'S-1-5-21-123-456-789-1001') | Test-WellKnownSID

        DESCRIPTION: Test multiple SIDs for well-known status
        OUTPUT: $true, $false (Administrators group vs. domain user)
        USE CASE: Bulk validation during ACL analysis

    .EXAMPLE
        PS> Test-WellKnownSID -SID "S-1-5-21-1234567890-1234567890-1234567890-512"

        DESCRIPTION: Test domain-specific well-known SID (Domain Admins)
        OUTPUT: $true (well-known domain admin group)
        USE CASE: Protect domain admin groups during cleanup

    .INPUTS
        [String] - SID string values via pipeline

    .OUTPUTS
        [Boolean] - $true if SID is well-known, $false otherwise

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
        Last Updated: 2025-07-04
        Version: 1.0.0

        PERFORMANCE CHARACTERISTICS:
        - Fast pattern matching and list lookups
        - Typical execution time: <10ms per SID

        WELL-KNOWN SID COVERAGE:
        - Universal well-known SIDs (S-1-0-*, S-1-1-*, etc.)
        - NT Authority SIDs (S-1-5-*)
        - Built-in domain SIDs (S-1-5-32-*)
        - Service SIDs (S-1-5-80-*, etc.)
        - Domain-specific admin groups (512, 518, 519)

        TROUBLESHOOTING:
        - For recognition issues: .\Troubleshooting\Security\Well-Known-SID-Issues.md
        - For configuration: .\Troubleshooting\Common\Configuration-Problems.md

    .LINK
        Test-SIDFormat
        .\Troubleshooting\Security\Well-Known-SID-Issues.md
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

    process {
        try {
            Write-StructuredLog "Testing SID for well-known status: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId

            # Check against configuration patterns if available
            if ($script:Config -and $script:Config.WellKnownSIDPatterns) {
                foreach ($pattern in $script:Config.WellKnownSIDPatterns) {
                    if ($SID -match $pattern) {
                        Write-StructuredLog "SID matches well-known pattern '$pattern': $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                        return $true
                    }
                }
            }

            # Check against protected SIDs configuration
            if ($script:Config -and $script:Config.ProtectedSIDs) {
                foreach ($protectedSID in $script:Config.ProtectedSIDs) {
                    if ($SID -eq $protectedSID) {
                        Write-StructuredLog "SID is in protected SIDs list: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                        return $true
                    }
                }
            }

            # Fallback to comprehensive well-known SIDs database
            $specificWellKnownSIDs = @(
                'S-1-0-0',        # Nobody
                'S-1-1-0',        # Everyone
                'S-1-2-0',        # Local
                'S-1-2-1',        # Console Logon
                'S-1-3-0',        # Creator Owner
                'S-1-3-1',        # Creator Group
                'S-1-3-2',        # Creator Owner Server
                'S-1-3-3',        # Creator Group Server
                'S-1-3-4',        # Owner Rights
                'S-1-5-1',        # Dialup
                'S-1-5-2',        # Network
                'S-1-5-3',        # Batch
                'S-1-5-4',        # Interactive
                'S-1-5-6',        # Service
                'S-1-5-7',        # Anonymous
                'S-1-5-8',        # Proxy
                'S-1-5-9',        # Enterprise Domain Controllers
                'S-1-5-10',       # Principal Self
                'S-1-5-11',       # Authenticated Users
                'S-1-5-12',       # Restricted Code
                'S-1-5-13',       # Terminal Server Users
                'S-1-5-14',       # Remote Interactive Logon
                'S-1-5-15',       # This Organization
                'S-1-5-17',       # This Organization Certificate
                'S-1-5-18',       # Local System
                'S-1-5-19',       # Local Service
                'S-1-5-20',       # Network Service
                'S-1-5-80',       # NT Service prefix
                'S-1-5-90',       # Windows Manager prefix
                'S-1-5-96'        # Font Driver Host prefix
            )

            # Check for Built-in domain SIDs (S-1-5-32-*)
            if ($SID.StartsWith('S-1-5-32-')) {
                Write-StructuredLog "SID is built-in domain SID: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                return $true
            }

            # Check specific well-known SIDs (use exact matching or specific patterns)
            foreach ($wellKnown in $specificWellKnownSIDs) {
                # For single-component SIDs, use exact matching
                if ($wellKnown -match '^\S+-\d+-\d+$' -and $SID -eq $wellKnown) {
                    Write-StructuredLog "SID is well-known exact match: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                    return $true
                }
                # For prefix patterns (like S-1-5-80, S-1-5-90, S-1-5-96), ensure they don't conflict with domain SIDs
                elseif ($wellKnown -match '^\S+-\d+-\d+$' -and $SID.StartsWith($wellKnown + '-')) {
                    Write-StructuredLog "SID is well-known prefix match: $SID (pattern: $wellKnown)" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                    return $true
                }
            }

            # Special handling for domain-specific well-known SIDs
            # Domain Admins (512), Enterprise Admins (519), Schema Admins (518)
            if ($SID -match '^S-1-5-21-\d+-\d+-\d+-(512|518|519)$') {
                Write-StructuredLog "SID is well-known domain admin group: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
                return $true
            }

            # Domain SIDs (S-1-5-21-*) are NOT well-known by default
            # They should be tested for orphaned status separately
            Write-StructuredLog "SID is not well-known: $SID" -Level Debug -Component 'SIDFormat' -CorrelationId $CorrelationId
            return $false
        }
        catch {
            Write-StructuredLog "Error testing well-known SID status for $SID : $($_.Exception.Message)" -Level Error -Component 'SIDFormat' -CorrelationId $CorrelationId
            return $false
        }
    }
}
