# PowerShell script to find objects with RC4 only and upgrade to RC4+AES
# Requires Active Directory PowerShell module and appropriate permissions

param(
    [switch]$WhatIf,
    [string[]]$ExcludedDisplayNames = @("ServiceAccount01", "LegacyApp-Service", "SpecialKerberosAccount")
)

# Import Active Directory module
Import-Module ActiveDirectory -ErrorAction Stop

# Setup logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logSuffix = if ($WhatIf) { "_WHATIF" } else { "" }
$logPath = ".\RC4_to_RC4AES_Migration_$timestamp$logSuffix.log"

# Function to write to both console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )

    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"

    # Write to log file
    Add-Content -Path $logPath -Value $logMessage

    # Write to console with color
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

$modeText = if ($WhatIf) { "PREVIEW MODE (WhatIf)" } else { "EXECUTION MODE" }
Write-Log "=== RC4 to RC4+AES Migration Script Started - $modeText ===" "Magenta"
Write-Log "Log file: $logPath" "Gray"

if ($WhatIf) {
    Write-Log "RUNNING IN WHATIF MODE - NO CHANGES WILL BE MADE" "Yellow"
    Write-Log "This will show you exactly what would be changed without making any modifications" "Yellow"
    Write-Log ""
}

# Define exclusions by display name (can be overridden by parameter)
$exclusions = $ExcludedDisplayNames

$exclusionsList = $exclusions -join ', '
Write-Log "Exclusions configured: $exclusionsList" "Gray"

# Define the filter to find objects with RC4 encryption only (decimal 0 or missing msds-supportedencryptiontypes)
# We'll look for objects where msds-supportedencryptiontypes is either 0, null, or not set
$filter = "(msds-supportedencryptiontypes -eq 0)"
Write-Log "Filter: $filter" "Gray"

try {
    Write-Log "Searching for AD objects with RC4-only encryption..." "Yellow"

    # Get AD objects matching the filter
    $allRC4Objects = Get-ADObject -Filter $filter -Properties Name, DistinguishedName, DisplayName, useraccountcontrol, 'msds-supportedencryptiontypes'
    $totalCount = $allRC4Objects.Count
    Write-Log "Found $totalCount total objects matching filter" "Gray"

    # Filter out exclusions based on display name
    $excludedObjects = $allRC4Objects | Where-Object { $_.DisplayName -in $exclusions }
    $rc4Objects = $allRC4Objects | Where-Object { $_.DisplayName -notin $exclusions }

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

    $actionText = if ($WhatIf) { "would be upgraded" } else { "need upgrading" }
    $rc4Count = $rc4Objects.Count
    Write-Log "Found $rc4Count objects that $actionText from RC4 to RC4+AES:" "Cyan"

    # Display objects that will be modified
    foreach ($obj in $rc4Objects) {
        $displayInfo = if ($obj.DisplayName) { "$($obj.DisplayName) ($($obj.Name))" } else { $obj.Name }
        $currentEncTypes = if ($obj.'msds-supportedencryptiontypes') { $obj.'msds-supportedencryptiontypes' } else { "0 (RC4 default)" }
        $changeText = if ($WhatIf) { "WOULD CHANGE" } else { "WILL CHANGE" }
        Write-Log "  - $changeText : $displayInfo - Current: $currentEncTypes -> New: 28 (RC4+AES)" "White"
    }

    if (-not $WhatIf) {
        # Confirm before proceeding (only in execution mode)
        Write-Log "`nDo you want to proceed with upgrading RC4 to RC4+AES encryption? (Y/N): " "Cyan" -NoNewline
        $confirm = Read-Host
        Write-Log "User response: $confirm" "Gray"

        if ($confirm -notmatch "^[Yy]$") {
            Write-Log "Operation cancelled by user." "Yellow"
            Write-Log "=== Script completed - Cancelled by user ===" "Magenta"
            exit 0
        }
    } else {
        Write-Log "`nWhatIf Mode: Showing what would be changed without making modifications" "Yellow"
        Write-Log "To execute these changes, run the script without the -WhatIf parameter" "Yellow"
    }

    $actionText = if ($WhatIf) { "Analyzing objects (WhatIf mode)..." } else { "Processing objects..." }
    Write-Log "`n$actionText" "Yellow"
    $successCount = 0
    $errorCount = 0

    foreach ($object in $rc4Objects) {
        try {
            $displayInfo = if ($object.DisplayName) { "$($object.DisplayName) ($($object.Name))" } else { $object.Name }
            $processText = if ($WhatIf) { "Would process" } else { "Processing" }
            Write-Log "$processText : $displayInfo" "Cyan"

            # Get current encryption types value
            $currentEncTypes = $object.'msds-supportedencryptiontypes'
            if (-not $currentEncTypes) { $currentEncTypes = 0 }

            Write-Log "  Current supported encryption types: $currentEncTypes (RC4 only)" "Gray"

            # Set supported encryption types to RC4 + AES
            # RC4_HMAC = 4 (0x4)
            # AES128_CTS_HMAC_SHA1_96 = 8 (0x8)
            # AES256_CTS_HMAC_SHA1_96 = 16 (0x10)
            # RC4 + AES128 + AES256 = 4 + 8 + 16 = 28 (0x1C)
            $rc4AesEncryptionTypes = 28

            if ($WhatIf) {
                # WhatIf mode - just show what would be done
                Write-Log "  WHATIF: Would set msds-supportedencryptiontypes to $rc4AesEncryptionTypes" "Yellow"
                Write-Log "  WHATIF: Would change from RC4-only to RC4+AES128+AES256" "Yellow"
                $successCount++
            } else {
                # Execution mode - actually make the changes
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
            $errorMsg = "Failed to update $($object.Name): $($_.Exception.Message)"
            if ($WhatIf) {
                Write-Log "  WHATIF ERROR: Would fail to update - $errorMsg" "Red"
            } else {
                Write-Log "  ERROR: $errorMsg" "Red"
            }
            $errorCount++
        }

        Write-Log "" # Empty line for readability
    }

    # Summary
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

    if ($successCount -gt 0 -and -not $WhatIf) {
        Write-Log "`nIMPORTANT: Changes have been made to Kerberos encryption settings." "Yellow"
        Write-Log "Objects now support: RC4 + AES128 + AES256 encryption" "Yellow"
        Write-Log "You may need to:" "Yellow"
        Write-Log "1. Restart affected services" "Yellow"
        Write-Log "2. Clear Kerberos ticket cache on client machines" "Yellow"
        Write-Log "3. Test authentication for affected accounts" "Yellow"
    } elseif ($successCount -gt 0 -and $WhatIf) {
        Write-Log "`nWhatIf Analysis Complete:" "Yellow"
        Write-Log "$successCount objects would be updated to support RC4 + AES128 + AES256" "Yellow"
        Write-Log "To make these changes, run the script again without -WhatIf" "Yellow"
    }
}
catch {
    $errorMsg = "CRITICAL ERROR: $($_.Exception.Message)"
    Write-Log $errorMsg "Red"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "Red"
    Write-Log "=== Script completed with errors ===" "Magenta"
    exit 1
}

# Optional: Verify changes (only in execution mode)
if (-not $WhatIf) {
    Write-Log "`nWould you like to verify the changes? (Y/N): " "Cyan" -NoNewline
    $verify = Read-Host
    Write-Log "User verification response: $verify" "Gray"

    if ($verify -match "^[Yy]$") {
        Write-Log "`nVerifying changes..." "Yellow"

        # Check objects that should now have RC4+AES encryption
        Write-Log "Checking updated objects for RC4+AES support..." "Yellow"

        $verifyCount = [Math]::Min(5, $rc4Objects.Count)
        for ($i = 0; $i -lt $verifyCount; $i++) {
            $object = $rc4Objects[$i]
            try {
                $updatedObject = Get-ADObject -Identity $object.DistinguishedName -Properties 'msds-supportedencryptiontypes'
                $encTypes = $updatedObject.'msds-supportedencryptiontypes'
                $displayInfo = if ($object.DisplayName) { "$($object.DisplayName) ($($object.Name))" } else { $object.Name }

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

        # Re-run the original query to see if any objects still have RC4-only
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
} else {
    Write-Log "`nWhatIf mode complete. No verification needed as no changes were made." "Yellow"
    Write-Log "To execute the changes shown above, run:" "Cyan"
    $exclusionList = $exclusions -join "', '"
    Write-Log ".\Convert-RC4toAES.ps1 -ExcludedDisplayNames @('$exclusionList')" "White"
}

$completionText = if ($WhatIf) { "WhatIf analysis completed successfully" } else { "Script completed successfully" }
Write-Log "`n=== $completionText ===" "Magenta"
Write-Log "Complete log saved to: $logPath" "Gray"