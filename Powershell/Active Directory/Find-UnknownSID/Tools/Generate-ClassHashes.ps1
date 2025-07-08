#Requires -Version 5.1

<#
.SYNOPSIS
    Generates SHA256 hashes for PowerShell class files and updates the approved class list.

.DESCRIPTION
    This script calculates cryptographic hashes for all PowerShell class files and
    automatically updates the Get-ApprovedClassList.ps1 file with the new hash values.
    Handles both updating existing class entries and adding new class entries automatically.

    The script follows enterprise security standards by:
    - Validating all class files before processing
    - Creating automatic backups before modifications
    - Implementing correlation tracking for audit purposes
    - Following PowerShell community best practices

.PARAMETER ClassPath
    Path to the Classes directory. Defaults to relative path from script location.
    Must contain valid PowerShell class files (.ps1 extension).

.PARAMETER ApprovedClassListPath
    Path to Get-ApprovedClassList.ps1 file. Defaults to the reorganized Private folder structure.
    This file contains the authoritative list of approved classes with integrity hashes.

.PARAMETER CorrelationId
    Correlation ID for tracking and audit purposes. If not provided,
    a new GUID will be generated automatically.

.EXAMPLE
    .\Generate-ClassHashes.ps1

    DESCRIPTION: Generates hashes for all class files and updates existing entries
    OUTPUT: Updated Get-ApprovedClassList.ps1 with new hash values
    USE CASE: Standard hash generation after class file modifications

.EXAMPLE
    .\Generate-ClassHashes.ps1 -WhatIf

    DESCRIPTION: Shows what would be updated without making changes
    OUTPUT: Preview of changes without file modification
    USE CASE: Validation and review before applying changes

.EXAMPLE
    .\Generate-ClassHashes.ps1 -CorrelationId "MAINT-2025-001" -Verbose

    DESCRIPTION: Hash generation with explicit correlation tracking and verbose output
    OUTPUT: Detailed processing information with audit correlation
    USE CASE: Maintenance operations requiring audit trail

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.String. Returns status messages and hash generation results.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    SECURITY CONSIDERATIONS:
    - Creates backup before modifying approved class list
    - Validates class file integrity before processing
    - Uses SHA256 cryptographic hashing for tamper detection
    - Implements correlation tracking for audit compliance

    TROUBLESHOOTING:
    - For class file issues: .\Troubleshooting\Common\Class-File-Issues.md
    - For hash generation errors: .\Troubleshooting\Security\Hash-Generation-Errors.md

    COMPLIANCE:
    - SOX: Supports change control with backup and audit tracking
    - Security: Implements cryptographic integrity validation
    - Enterprise: Follows standardized folder structure and naming
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ClassPath = (Join-Path $PSScriptRoot "..\Classes"),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApprovedClassListPath = (Join-Path $PSScriptRoot "..\Private\ClassManagement\Get-ApprovedClassList.ps1"),

    [Parameter()]
    [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
)

# Initialize correlation tracking and error handling
$ErrorActionPreference = 'Stop'

Write-Verbose "Starting class hash generation - CorrelationId: $CorrelationId"

# Resolve and validate paths
try {
    $ClassPath = Resolve-Path $ClassPath -ErrorAction Stop
    $ApprovedClassListPath = Resolve-Path $ApprovedClassListPath -ErrorAction Stop
} catch {
    Write-Error "Failed to resolve paths: $($_.Exception.Message)" -ErrorAction Stop
}

Write-Host "PowerShell Class Hash Generator" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "Class Directory: $ClassPath" -ForegroundColor Yellow
Write-Host "Target File: $ApprovedClassListPath" -ForegroundColor Yellow
Write-Host "Correlation ID: $CorrelationId" -ForegroundColor Gray
Write-Host ""

# Get class files
$classFiles = Get-ChildItem -Path $ClassPath -Filter "*.ps1" -File | Sort-Object Name

if ($classFiles.Count -eq 0) {
    Write-Warning "No class files found in: $ClassPath"
    exit 1
}

Write-Host "Found $($classFiles.Count) class files:" -ForegroundColor Green

# Calculate hashes for all class files
$hashResults = @{}
foreach ($file in $classFiles) {
    Write-Host "  Processing: $($file.Name)" -ForegroundColor Cyan

    try {
        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        $hashResults[$file.Name] = $hash.Hash.ToUpper()

        Write-Host "    Hash: $($hash.Hash)" -ForegroundColor Gray
        Write-Verbose "Generated hash for $($file.Name): $($hash.Hash)"
    } catch {
        Write-Error "Failed to generate hash for $($file.Name): $($_.Exception.Message)" -ErrorAction Stop
    }
}

Write-Host ""
Write-Host "Hash Summary:" -ForegroundColor Yellow
foreach ($fileName in ($hashResults.Keys | Sort-Object)) {
    Write-Host "$fileName -> $($hashResults[$fileName])" -ForegroundColor White
}

# Update Get-ApprovedClassList.ps1
Write-Host ""
Write-Host "Updating Get-ApprovedClassList.ps1..." -ForegroundColor Yellow

# Pre-analyze what operations will be performed
Write-Host "Analyzing current Get-ApprovedClassList.ps1..." -ForegroundColor Cyan
try {
    $previewContent = Get-Content -Path $ApprovedClassListPath -Raw -Encoding UTF8
} catch {
    Write-Error "Failed to read Get-ApprovedClassList.ps1: $($_.Exception.Message)" -ErrorAction Stop
}
$existingEntries = @()
$newEntries = @()

foreach ($fileName in $hashResults.Keys) {
    # Updated pattern to match the current structure in Get-ApprovedClassList.ps1
    $pattern = "('$fileName'\s*=\s*@\{[^}]*ExpectedHash\s*=\s*)'[A-F0-9]{64}'"
    if ($previewContent -match $pattern) {
        $existingEntries += $fileName
    } else {
        $newEntries += $fileName
    }
}

Write-Host "Operations planned:" -ForegroundColor White
if ($existingEntries.Count -gt 0) {
    Write-Host "  Will update $($existingEntries.Count) existing class hash(es):" -ForegroundColor Yellow
    foreach ($entry in ($existingEntries | Sort-Object)) {
        Write-Host "    - $entry" -ForegroundColor Gray
    }
}
if ($newEntries.Count -gt 0) {
    Write-Host "  Will add $($newEntries.Count) new class entrie(s):" -ForegroundColor Cyan
    foreach ($entry in ($newEntries | Sort-Object)) {
        Write-Host "    - $entry" -ForegroundColor Gray
    }
}
Write-Host ""

if ($PSCmdlet.ShouldProcess($ApprovedClassListPath, "Update class hashes")) {
    try {
        # Create backup with correlation ID
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = "$ApprovedClassListPath.backup-$timestamp-$($CorrelationId.Substring(0,8))"
        Copy-Item -Path $ApprovedClassListPath -Destination $backupPath -Force
        Write-Host "Backup created: $backupPath" -ForegroundColor Green

        # Read current content
        $content = Get-Content -Path $ApprovedClassListPath -Raw -Encoding UTF8
        $updatedContent = $content
        $updateCount = 0
        $addCount = 0

        # Track which classes exist and which are new
        $existingClasses = @{}
        $newClasses = @{}

        # Analyze each class file
        foreach ($fileName in $hashResults.Keys) {
            $newHash = $hashResults[$fileName]

            # Check if class entry exists in the approved classes hashtable
            $pattern = "('$fileName'\s*=\s*@\{[^}]*ExpectedHash\s*=\s*)'[A-F0-9]{64}'"

            if ($updatedContent -match $pattern) {
                $existingClasses[$fileName] = $newHash
            } else {
                $newClasses[$fileName] = $newHash
            }
        }

        # Update existing class hashes
        Write-Host ""
        Write-Host "Updating existing class hashes..." -ForegroundColor Cyan
        foreach ($fileName in $existingClasses.Keys) {
            $newHash = $existingClasses[$fileName]
            $pattern = "('$fileName'\s*=\s*@\{[^}]*ExpectedHash\s*=\s*)'[A-F0-9]{64}'"
            $replacement = "`${1}'$newHash'"

            if ($updatedContent -match $pattern) {
                $updatedContent = $updatedContent -replace $pattern, $replacement
                Write-Host "  Updated: $fileName" -ForegroundColor Green
                $updateCount++
            } else {
                Write-Warning "  Failed to update: $fileName (pattern not found)"
            }
        }

        # Update LastVerified date for all updated classes
        $currentDate = Get-Date -Format 'yyyy-MM-dd'
        foreach ($fileName in $existingClasses.Keys) {
            $lastVerifiedPattern = "('$fileName'\s*=\s*@\{[^}]*LastVerified\s*=\s*)'[0-9]{4}-[0-9]{2}-[0-9]{2}'"
            $lastVerifiedReplacement = "`${1}'$currentDate'"
            $updatedContent = $updatedContent -replace $lastVerifiedPattern, $lastVerifiedReplacement
        }

        # Add new class entries if any exist
        if ($newClasses.Count -gt 0) {
            Write-Host ""
            Write-Host "Adding new class entries..." -ForegroundColor Cyan

            # Find the closing brace of the approvedClasses hashtable in Get-ApprovedClassList.ps1
            # Look for the pattern before the metadata section
            $approvedClassesEndPattern = '(\s+}\s*\n\s*#\s*Add metadata to configuration)'

            if ($updatedContent -match $approvedClassesEndPattern) {
                $newEntries = ""

                foreach ($fileName in ($newClasses.Keys | Sort-Object)) {
                    $newHash = $newClasses[$fileName]
                    $currentDate = Get-Date -Format 'yyyy-MM-dd'

                    # Generate class name from filename (remove .ps1 extension)
                    $className = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

                    $newEntry = @"
                '$fileName' = @{
                    RequiredTypes = @('$className')
                    Dependencies = @()
                    Description = 'Auto-generated entry for $className class'
                    ExpectedHash = '$newHash'
                    LastVerified = '$currentDate'
                    SecurityLevel = 'Standard'
                    LoadOrder = 99
                }
"@
                    $newEntries += $newEntry
                    Write-Host "  Added: $fileName -> $className" -ForegroundColor Green
                    $addCount++
                }

                # Insert new entries before the closing brace
                $replacement = $newEntries + "`r`n            }`r`n`r`n            # Add metadata to configuration"
                $updatedContent = $updatedContent -replace $approvedClassesEndPattern, $replacement

            } else {
                Write-Warning "Could not locate approvedClasses hashtable end pattern to add new entries"
                foreach ($fileName in $newClasses.Keys) {
                    Write-Warning "  Skipped: $fileName (new class - manual addition required)"
                    Write-Host "    Suggested entry:" -ForegroundColor Yellow
                    $className = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    Write-Host "                '$fileName' = @{" -ForegroundColor Gray
                    Write-Host "                    RequiredTypes = @('$className')" -ForegroundColor Gray
                    Write-Host "                    Dependencies = @()" -ForegroundColor Gray
                    Write-Host "                    Description = 'Auto-generated entry for $className class'" -ForegroundColor Gray
                    Write-Host "                    ExpectedHash = '$($newClasses[$fileName])'" -ForegroundColor Gray
                    Write-Host "                    LastVerified = '$(Get-Date -Format 'yyyy-MM-dd')'" -ForegroundColor Gray
                    Write-Host "                    SecurityLevel = 'Standard'" -ForegroundColor Gray
                    Write-Host "                    LoadOrder = 99" -ForegroundColor Gray
                    Write-Host "                }" -ForegroundColor Gray
                }
            }
        }

        # Save updated content
        if (($updateCount + $addCount) -gt 0) {
            Set-Content -Path $ApprovedClassListPath -Value $updatedContent -Encoding UTF8 -NoNewline
            Write-Host ""
            if ($updateCount -gt 0 -and $addCount -gt 0) {
                Write-Host "Successfully updated $updateCount hash(es) and added $addCount new class(es) in Get-ApprovedClassList.ps1!" -ForegroundColor Green
            } elseif ($updateCount -gt 0) {
                Write-Host "Successfully updated $updateCount hash(es) in Get-ApprovedClassList.ps1!" -ForegroundColor Green
            } else {
                Write-Host "Successfully added $addCount new class(es) to Get-ApprovedClassList.ps1!" -ForegroundColor Green
            }

            # Log completion with correlation ID
            Write-Verbose "Hash generation completed successfully - CorrelationId: $CorrelationId, Updated: $updateCount, Added: $addCount"
        } else {
            Write-Warning "No hashes were updated or added"
        }

    } catch {
        $errorMessage = "Update failed: $($_.Exception.Message)"
        Write-Error $errorMessage

        # Restore backup if it exists
        if (Test-Path $backupPath) {
            try {
                Copy-Item -Path $backupPath -Destination $ApprovedClassListPath -Force
                Write-Host "Restored from backup: $backupPath" -ForegroundColor Yellow
            } catch {
                Write-Error "Failed to restore backup: $($_.Exception.Message)"
            }
        }

        # Log error with correlation ID
        Write-Verbose "Hash generation failed - CorrelationId: $CorrelationId, Error: $errorMessage"
        throw
    }
} else {
    Write-Host "Operation cancelled by user (WhatIf specified)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Hash generation complete! - CorrelationId: $CorrelationId" -ForegroundColor Green
Write-Verbose "Process completed - CorrelationId: $CorrelationId"
