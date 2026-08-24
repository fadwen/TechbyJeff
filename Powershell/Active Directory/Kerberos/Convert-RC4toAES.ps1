<#
.SYNOPSIS
    Converts Active Directory objects from RC4-only to RC4+AES Kerberos encryption

.DESCRIPTION
    This script identifies Active Directory objects that are configured for RC4-only
    Kerberos encryption and upgrades them to support both RC4 and AES encryption types.
    This enhances security while maintaining backward compatibility during migration.

    Core Functionality:
    - Searches for AD objects with RC4-only encryption (msds-supportedencryptiontypes = 0)
    - Upgrades objects to support RC4 + AES128 + AES256 (value = 28)
    - Provides exclusion capability for specific objects by display name
    - Comprehensive logging with both console output and file logging
    - WhatIf mode for safe preview of changes before execution

    Business Value:
    - Improves Kerberos security posture by enabling stronger AES encryption
    - Reduces security vulnerabilities associated with RC4-only configurations
    - Maintains backward compatibility during migration periods
    - Provides audit trail for compliance and security reviews

    Use Cases:
    - Security hardening initiatives to eliminate weak RC4 encryption
    - Compliance requirements for stronger authentication encryption
    - Gradual migration from legacy RC4 to modern AES encryption
    - Regular security assessments and remediation activities

    Dependencies:
    - Active Directory PowerShell module (automatically imported)
    - Domain Administrator or equivalent permissions to modify AD objects
    - Network connectivity to domain controllers
    - PowerShell 5.1 or later with execution policy allowing script execution

    Performance Considerations:
    - Execution time scales with number of objects requiring update
    - Typical processing rate: 10-50 objects per minute depending on domain size
    - Memory usage minimal for normal enterprise environments (<100MB)
    - Network impact minimal (single LDAP query + individual object updates)

    Side Effects:
    - Modifies msds-supportedencryptiontypes attribute on AD objects
    - May require service restarts for affected service accounts
    - Client Kerberos ticket cache may need clearing after changes
    - Authentication behavior may change for affected objects

.PARAMETER WhatIf
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    When specified, the script runs in preview mode without making any changes.
    Shows exactly what objects would be modified and what changes would be made.

    Business Context: Essential for change management and compliance processes
    where changes must be reviewed and approved before implementation.

    Examples: -WhatIf, -WhatIf:$true

.PARAMETER ExcludedDisplayNames
    [System.String[]] (Optional, No Pipeline Support)

    Array of Active Directory object display names to exclude from processing.
    Objects matching these display names will not be modified even if they
    have RC4-only encryption configured.

    Default Value: @("ServiceAccount01", "LegacyApp-Service", "SpecialKerberosAccount")

    Business Context: Allows protection of critical legacy systems that may
    require RC4-only encryption for compatibility reasons or systems undergoing
    separate maintenance windows.

    Examples:
    @("LegacyApp", "TestService")
    @("CriticalService", "PartnerIntegration", "BackupAccount")

.PARAMETER Force
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    When specified, bypasses all user prompts for fully automated execution.
    Automatically proceeds with changes (when not in WhatIf mode) and skips
    post-execution verification prompts.

    Business Context: Essential for automation scenarios including scheduled
    tasks, CI/CD pipelines, and unattended security remediation workflows.
    Enables integration with enterprise automation frameworks and reduces
    manual intervention requirements.

    Automation Use Cases:
    - Scheduled maintenance windows with predetermined approval
    - Automated security compliance remediation
    - Integration with configuration management systems
    - Bulk processing across multiple environments

    Safety Considerations:
    - Should only be used after thorough testing with -WhatIf parameter
    - Requires proper change management approval for production use
    - Consider logging and monitoring for automated executions

    Examples: -Force, -Force:$true

.EXAMPLE
    PS> .\Convert-RC4toAES.ps1 -WhatIf

    DESCRIPTION: Preview mode execution showing what changes would be made
    OUTPUT: Console and log file output showing objects that would be updated
    USE CASE: Change management review and approval process
    DURATION: 2-5 minutes for typical enterprise environment

.EXAMPLE
    PS> .\Convert-RC4toAES.ps1 -ExcludedDisplayNames @("CriticalApp", "LegacyService")

    DESCRIPTION: Execute encryption upgrade with custom exclusions
    OUTPUT: Updates all RC4-only objects except specified exclusions
    USE CASE: Production deployment with protection for specific legacy systems
    DURATION: 5-15 minutes depending on number of objects

.EXAMPLE
    PS> .\Convert-RC4toAES.ps1 -WhatIf -ExcludedDisplayNames @()

    DESCRIPTION: Preview all objects including defaults, with no exclusions
    OUTPUT: Shows all RC4-only objects that would be updated
    USE CASE: Comprehensive security assessment without exclusions
    DURATION: 2-5 minutes for analysis

.EXAMPLE
    PS> .\Convert-RC4toAES.ps1 -Force

    DESCRIPTION: Automated execution without user prompts
    OUTPUT: Proceeds automatically with RC4 to AES conversion
    USE CASE: Scheduled maintenance or CI/CD pipeline integration
    DURATION: 5-15 minutes depending on number of objects

.EXAMPLE
    PS> .\Convert-RC4toAES.ps1 -Force -ExcludedDisplayNames @("CriticalLegacyApp") -WhatIf

    DESCRIPTION: Automated preview mode with custom exclusions
    OUTPUT: Shows what would be changed in automation scenario
    USE CASE: Testing automation configuration before deployment
    DURATION: 2-5 minutes for analysis

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. This script outputs log information to console and file but does not
    return objects to the pipeline. Creates log file with timestamp for audit trail.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-06-27
    Version: 2.0.0

    Security Considerations:
    - Requires elevated AD permissions (Domain Admin or equivalent)
    - Script creates detailed logs that may contain sensitive object information
    - Changes affect Kerberos authentication security for modified objects
    - Should be executed during maintenance windows for service accounts

    Performance Characteristics:
    - Lightweight operation with minimal system resource usage
    - Scales linearly with number of objects requiring modification
    - Single-threaded processing ensures consistent logging and error handling
    - Optimized LDAP queries minimize domain controller impact

    Known Limitations:
    - Does not validate that AES encryption is supported by all clients
    - Cannot predict application compatibility issues with AES encryption
    - Requires manual verification of changes if automatic verification is skipped
    - Does not handle cross-domain trusts or forest-level considerations

.LINK
    https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/network-security-configure-encryption-types-allowed-for-kerberos
    https://docs.microsoft.com/en-us/windows-server/security/kerberos/kerberos-authentication-overview
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,

    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [string[]]$ExcludedDisplayNames = @("ServiceAccount01", "LegacyApp-Service", "SpecialKerberosAccount"),

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Import required modules with error handling
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Verbose "Successfully imported Active Directory module"
} catch {
    Write-Error "Failed to import Active Directory module. Ensure RSAT tools are installed. Error: $($_.Exception.Message)"
    exit 1
}

# Initialize logging configuration with timestamp and mode detection
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logSuffix = if ($WhatIf) { "_WHATIF" } else { "" }
$logPath = ".\RC4_to_RC4AES_Migration_$timestamp$logSuffix.log"


function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped messages to both console and log file simultaneously

    .DESCRIPTION
        Centralized logging function that ensures consistent message formatting
        and dual output to both console (with color support) and persistent log file.
        Automatically adds timestamps and handles various output scenarios.

    .PARAMETER Message
        [System.String] (Mandatory, No Pipeline Support)
        The message text to write to both console and log file.

    .PARAMETER Color
        [System.String] (Optional, No Pipeline Support)
        Console text color for the message. Default is "White".
        Valid colors: Black, Blue, Cyan, DarkBlue, DarkCyan, DarkGray,
        DarkGreen, DarkMagenta, DarkRed, DarkYellow, Gray, Green,
        Magenta, Red, White, Yellow

    .PARAMETER NoNewline
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)
        When specified, does not add a newline after the message output.
        Useful for prompts or status indicators.

    .EXAMPLE
        PS> Write-Log "Operation completed successfully" "Green"
        Writes a success message in green to console and timestamped to log file

    .EXAMPLE
        PS> Write-Log "Enter your choice: " "Cyan" -NoNewline
        Writes a prompt without newline for user input
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Black", "Blue", "Cyan", "DarkBlue", "DarkCyan", "DarkGray",
                    "DarkGreen", "DarkMagenta", "DarkRed", "DarkYellow", "Gray",
                    "Green", "Magenta", "Red", "White", "Yellow")]
        [string]$Color = "White",

        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )

    # Create timestamped log entry for file
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"

    # Write to log file with error handling
    try {
        Add-Content -Path $logPath -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file '$logPath': $($_.Exception.Message)"
    }

    # Write to console with color support
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Initialize script execution with mode detection and user notification
$modeText = if ($WhatIf) { "PREVIEW MODE (WhatIf)" } else { "EXECUTION MODE" }
Write-Log "=== RC4 to RC4+AES Migration Script Started - $modeText ===" "Magenta"
Write-Log "Log file: $logPath" "Gray"

# Display clear warning for WhatIf mode to set user expectations
if ($WhatIf) {
    Write-Log "RUNNING IN WHATIF MODE - NO CHANGES WILL BE MADE" "Yellow"
    Write-Log "This will show you exactly what would be changed without making any modifications" "Yellow"
    Write-Log ""
}

# Configure object exclusions for protected systems
# These objects will be skipped even if they have RC4-only encryption
$exclusions = $ExcludedDisplayNames
$exclusionsList = $exclusions -join ', '
Write-Log "Exclusions configured: $exclusionsList" "Gray"

# Define LDAP filter for RC4-only objects
# msds-supportedencryptiontypes = 0 indicates default RC4-only encryption
# This attribute controls which Kerberos encryption types are supported
$filter = "(msds-supportedencryptiontypes -eq 0)"
Write-Log "Filter: $filter" "Gray"

try {
    Write-Log "Searching for AD objects with RC4-only encryption..." "Yellow"

    # Query Active Directory for objects with RC4-only encryption configuration
    # Properties retrieved: Name, DistinguishedName, DisplayName for identification
    # useraccountcontrol for account status, msds-supportedencryptiontypes for encryption config
    $allRC4Objects = Get-ADObject -Filter $filter -Properties Name, DistinguishedName, DisplayName, useraccountcontrol, 'msds-supportedencryptiontypes'
    $totalCount = $allRC4Objects.Count
    Write-Log "Found $totalCount total objects matching filter" "Gray"

    # Apply exclusion filtering to protect specified objects from modification
    # Exclusions are based on DisplayName property for user-friendly identification
    $excludedObjects = $allRC4Objects | Where-Object { $_.DisplayName -in $exclusions }
    $rc4Objects = $allRC4Objects | Where-Object { $_.DisplayName -notin $exclusions }

    # Report excluded objects for transparency and audit purposes
    if ($excludedObjects.Count -gt 0) {
        $excludedCount = $excludedObjects.Count
        Write-Log "Found $excludedCount objects that will be EXCLUDED from processing:" "Yellow"
        foreach ($obj in $excludedObjects) {
            $objDisplayName = $obj.DisplayName
            $objName = $obj.Name
            Write-Log "  - EXCLUDED: $objDisplayName ($objName)" "Yellow"
        }
        Write-Log ""
    }

    # Handle scenario where no objects need processing after exclusions
    if ($rc4Objects.Count -eq 0) {
        Write-Log "No objects found with RC4-only encryption that need processing (after exclusions)." "Green"
        if ($excludedObjects.Count -gt 0) {
            $excludedCount = $excludedObjects.Count
            Write-Log "Note: $excludedCount objects were excluded based on display name." "Yellow"
        }
        $completionText = if ($WhatIf) { "WhatIf analysis completed - No changes needed" } else { "Script completed - No changes needed" }
        Write-Log "=== $completionText ===" "Magenta"
        exit 0
    }

    # Display preview of objects that will be modified for user review
    $actionText = if ($WhatIf) { "would be upgraded" } else { "need upgrading" }
    $rc4Count = $rc4Objects.Count
    Write-Log "Found $rc4Count objects that $actionText from RC4 to RC4+AES:" "Cyan"

    # Show detailed information about each object to be modified
    # Including current encryption type and planned new encryption configuration
    foreach ($obj in $rc4Objects) {
        $displayInfo = if ($obj.DisplayName) { "$($obj.DisplayName) ($($obj.Name))" } else { $obj.Name }
        $currentEncTypes = if ($obj.'msds-supportedencryptiontypes') { $obj.'msds-supportedencryptiontypes' } else { "0 (RC4 default)" }
        $changeText = if ($WhatIf) { "WOULD CHANGE" } else { "WILL CHANGE" }
        Write-Log "  - $changeText : $displayInfo - Current: $currentEncTypes -> New: 28 (RC4+AES)" "White"
    }

    # Require explicit user confirmation before making changes in execution mode
    # This provides additional safety against accidental modifications
    # Skip prompts when Force parameter is specified for automation scenarios
    if (-not $WhatIf) {
        if ($Force) {
            Write-Log "Force parameter specified - proceeding with automatic execution" "Yellow"
            Write-Log "Bypassing user confirmation for automation compatibility" "Gray"
        } else {
            Write-Log "`nDo you want to proceed with upgrading RC4 to RC4+AES encryption? (Y/N): " "Cyan" -NoNewline
            $confirm = Read-Host
            Write-Log "User response: $confirm" "Gray"

            if ($confirm -notmatch "^[Yy]$") {
                Write-Log "Operation cancelled by user." "Yellow"
                Write-Log "=== Script completed - Cancelled by user ===" "Magenta"
                exit 0
            }
        }
    } else {
        # Provide clear guidance for WhatIf mode users
        Write-Log "`nWhatIf Mode: Showing what would be changed without making modifications" "Yellow"
        Write-Log "To execute these changes, run the script without the -WhatIf parameter" "Yellow"
    }

    # Begin processing objects with comprehensive error tracking
    $actionText = if ($WhatIf) { "Analyzing objects (WhatIf mode)..." } else { "Processing objects..." }
    Write-Log "`n$actionText" "Yellow"
    $successCount = 0
    $errorCount = 0

    # Process each object individually to ensure granular error handling and logging
    foreach ($object in $rc4Objects) {
        try {
            $displayInfo = if ($object.DisplayName) { "$($object.DisplayName) ($($object.Name))" } else { $object.Name }
            $processText = if ($WhatIf) { "Would process" } else { "Processing" }
            Write-Log "$processText : $displayInfo" "Cyan"

            # Retrieve and display current encryption configuration for audit trail
            $currentEncTypes = $object.'msds-supportedencryptiontypes'
            if (-not $currentEncTypes) { $currentEncTypes = 0 }
            Write-Log "  Current supported encryption types: $currentEncTypes (RC4 only)" "Gray"

            # Configure new encryption types to support RC4 + AES128 + AES256
            # Kerberos encryption type values (RFC 3961):
            # RC4_HMAC = 4 (0x4) - Legacy RC4 encryption for backward compatibility
            # AES128_CTS_HMAC_SHA1_96 = 8 (0x8) - Modern AES-128 encryption
            # AES256_CTS_HMAC_SHA1_96 = 16 (0x10) - Strong AES-256 encryption
            # Combined value: RC4 + AES128 + AES256 = 4 + 8 + 16 = 28 (0x1C)
            $rc4AesEncryptionTypes = 28

            if ($WhatIf) {
                # WhatIf mode: Preview changes without modification
                Write-Log "  WHATIF: Would set msds-supportedencryptiontypes to $rc4AesEncryptionTypes" "Yellow"
                Write-Log "  WHATIF: Would change from RC4-only to RC4+AES128+AES256" "Yellow"
                $successCount++
            } else {
                # Execution mode: Apply encryption type changes to Active Directory
                $updateParams = @{
                    Identity = $object.DistinguishedName
                    Replace = @{
                        'msds-supportedencryptiontypes' = $rc4AesEncryptionTypes
                    }
                }

                Set-ADObject @updateParams

                Write-Log "  Successfully updated encryption settings to RC4+AES" "Green"
                Write-Log "  New supported encryption types: $rc4AesEncryptionTypes (RC4 + AES128 + AES256)" "Gray"
                $successCount++
            }
        }
        catch {
            # Handle individual object processing errors without stopping overall operation
            $errorMsg = "Failed to update $($object.Name): $($_.Exception.Message)"
            if ($WhatIf) {
                Write-Log "  WHATIF ERROR: Would fail to update - $errorMsg" "Red"
            } else {
                Write-Log "  ERROR: $errorMsg" "Red"
            }
            $errorCount++
        }

        Write-Log "" # Add blank line for improved readability between objects
    }

    # Generate comprehensive summary report for audit and compliance purposes
    Write-Log "=== SUMMARY ===" "Magenta"
    if ($WhatIf) {
        Write-Log "WHATIF MODE - No actual changes were made" "Yellow"
        Write-Log "Objects that would be successfully processed: $successCount" "Green"
        Write-Log "Objects that would encounter errors: $errorCount" "Red"
    } else {
        Write-Log "Successfully processed: $successCount objects" "Green"
        Write-Log "Errors encountered: $errorCount objects" "Red"
    }
    Write-Log "Total objects analyzed: $rc4Count" "Cyan"
    if ($excludedObjects.Count -gt 0) {
        $excludedCount = $excludedObjects.Count
        Write-Log "Objects excluded: $excludedCount" "Yellow"
    }

    # Provide post-execution guidance for successful changes
    if ($successCount -gt 0 -and -not $WhatIf) {
        Write-Log "`nIMPORTANT: Changes have been made to Kerberos encryption settings." "Yellow"
        Write-Log "Objects now support: RC4 + AES128 + AES256 encryption" "Yellow"
        Write-Log "You may need to:" "Yellow"
        Write-Log "1. Restart affected services to pick up new encryption settings" "Yellow"
        Write-Log "2. Clear Kerberos ticket cache on client machines: klist purge" "Yellow"
        Write-Log "3. Test authentication for affected accounts to verify compatibility" "Yellow"
    } elseif ($successCount -gt 0 -and $WhatIf) {
        Write-Log "`nWhatIf Analysis Complete:" "Yellow"
        Write-Log "$successCount objects would be updated to support RC4 + AES128 + AES256" "Yellow"
        Write-Log "To make these changes, run the script again without -WhatIf" "Yellow"
    }
}
catch {
    # Handle critical script-level errors with detailed logging for troubleshooting
    $errorMsg = "CRITICAL ERROR: $($_.Exception.Message)"
    Write-Log $errorMsg "Red"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "Red"
    Write-Log "=== Script completed with errors ===" "Magenta"
    exit 1
}

# Optional verification process to confirm changes were applied correctly
# This provides additional confidence in the modification results
# Skip verification prompts when Force parameter is specified for automation
if (-not $WhatIf) {
    if ($Force) {
        Write-Log "`nForce parameter specified - skipping interactive verification" "Yellow"
        Write-Log "For automation scenarios, consider separate validation scripts" "Gray"
    } else {
        Write-Log "`nWould you like to verify the changes? (Y/N): " "Cyan" -NoNewline
        $verify = Read-Host
        Write-Log "User verification response: $verify" "Gray"

        if ($verify -match "^[Yy]$") {
            Write-Log "`nVerifying changes..." "Yellow"

            # Validate encryption type changes on sample of modified objects
            # Checks first 5 objects to balance verification coverage with performance
            Write-Log "Checking updated objects for RC4+AES support..." "Yellow"

            $verifyCount = [Math]::Min(5, $rc4Objects.Count)
            for ($i = 0; $i -lt $verifyCount; $i++) {
                $object = $rc4Objects[$i]
                try {
                    # Re-query object from AD to get current encryption type configuration
                    $updatedObject = Get-ADObject -Identity $object.DistinguishedName -Properties 'msds-supportedencryptiontypes'
                    $encTypes = $updatedObject.'msds-supportedencryptiontypes'
                    $displayInfo = if ($object.DisplayName) { "$($object.DisplayName) ($($object.Name))" } else { $object.Name }

                    # Verify encryption type was set to expected value (28 = RC4+AES128+AES256)
                    if ($encTypes -eq 28) {
                        Write-Log "  ✓ $displayInfo - Encryption types: $encTypes (RC4+AES)" "Green"
                    } else {
                        Write-Log "  ✗ $displayInfo - Encryption types: $encTypes (Unexpected value)" "Red"
                    }
                }
                catch {
                    $errorMsg = "Failed to verify $($object.Name): $($_.Exception.Message)"
                    Write-Log "  ✗ $errorMsg" "Red"
                }
            }

            if ($rc4Objects.Count -gt 5) {
                Write-Log "  ... (showing first 5 objects only)" "Gray"
            }

            # Perform comprehensive scan to identify any remaining RC4-only objects
            # This helps identify any objects that may have been missed or failed to update
            Write-Log "Checking for remaining RC4-only objects..." "Yellow"
            $remainingRC4 = Get-ADObject -Filter $filter -Properties Name, 'msds-supportedencryptiontypes' | Where-Object { $_.DisplayName -notin $exclusions }

            if ($remainingRC4.Count -eq 0) {
                Write-Log "`nSUCCESS: No objects found with RC4-only encryption!" "Green"
            } else {
                $remainingCount = $remainingRC4.Count
                Write-Log "`nWARNING: $remainingCount objects still have RC4-only encryption:" "Yellow"
                $showCount = [Math]::Min(10, $remainingRC4.Count)
                for ($i = 0; $i -lt $showCount; $i++) {
                    $objName = $remainingRC4[$i].Name
                    Write-Log "  - $objName" "White"
                }
                if ($remainingRC4.Count -gt 10) {
                    $additionalCount = $remainingRC4.Count - 10
                    Write-Log "  ... and $additionalCount more" "Gray"
                }
            }
        }
    }
} else {
    # Provide guidance for WhatIf mode completion
    Write-Log "`nWhatIf mode complete. No verification needed as no changes were made." "Yellow"
    Write-Log "To execute the changes shown above, run:" "Cyan"
    $exclusionList = $exclusions -join "', '"
    Write-Log ".\Convert-RC4toAES.ps1 -ExcludedDisplayNames @('$exclusionList')" "White"
}

# Script completion with appropriate success messaging and log file reference
$completionText = if ($WhatIf) { "WhatIf analysis completed successfully" } else { "Script completed successfully" }
Write-Log "`n=== $completionText ===" "Magenta"
Write-Log "Complete log saved to: $logPath" "Gray"

# Exit with success code for automation and monitoring integration
exit 0