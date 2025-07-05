<#
.SYNOPSIS
    Generates SHA256 hashes for PowerShell class files and updates SecureClassImporter.

.DESCRIPTION
    This script calculates cryptographic hashes for all PowerShell class files and
    automatically updates the SecureClassImporter.ps1 file with the new hash values.
    Handles both updating existing class entries and adding new class entries automatically.

.PARAMETER ClassPath
    Path to the Classes directory. Defaults to relative path from script location.

.PARAMETER SecureClassImporterPath
    Path to SecureClassImporter.ps1 file. Defaults to relative path from script location.

.EXAMPLE
    .\Generate-ClassHashes.ps1
    Generates hashes for all class files, updates existing entries and adds new ones

.EXAMPLE
    .\Generate-ClassHashes.ps1 -WhatIf
    Shows what would be updated without making changes

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ClassPath = (Join-Path $PSScriptRoot "..\Classes"),

    [Parameter()]
    [string]$SecureClassImporterPath = (Join-Path $PSScriptRoot "..\Private\SecureClassImporter.ps1")
)

# Resolve paths
$ClassPath = Resolve-Path $ClassPath -ErrorAction Stop
$SecureClassImporterPath = Resolve-Path $SecureClassImporterPath -ErrorAction Stop

Write-Host "PowerShell Class Hash Generator" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "Class Directory: $ClassPath" -ForegroundColor Yellow
Write-Host "Target File: $SecureClassImporterPath" -ForegroundColor Yellow
Write-Host ""

# Get class files
$classFiles = Get-ChildItem -Path $ClassPath -Filter "*.ps1" -File | Sort-Object Name

if ($classFiles.Count -eq 0) {
    Write-Warning "No class files found in: $ClassPath"
    exit 1
}

Write-Host "Found $($classFiles.Count) class files:" -ForegroundColor Green

# Calculate hashes
$hashResults = @{}
foreach ($file in $classFiles) {
    Write-Host "  Processing: $($file.Name)" -ForegroundColor Cyan

    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    $hashResults[$file.Name] = $hash.Hash

    Write-Host "    Hash: $($hash.Hash)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Hash Summary:" -ForegroundColor Yellow
foreach ($fileName in ($hashResults.Keys | Sort-Object)) {
    Write-Host "$fileName -> $($hashResults[$fileName])" -ForegroundColor White
}

# Update SecureClassImporter
Write-Host ""
Write-Host "Updating SecureClassImporter.ps1..." -ForegroundColor Yellow

# Pre-analyze what operations will be performed
Write-Host "Analyzing current SecureClassImporter.ps1..." -ForegroundColor Cyan
$previewContent = Get-Content -Path $SecureClassImporterPath -Raw -Encoding UTF8
$existingEntries = @()
$newEntries = @()

foreach ($fileName in $hashResults.Keys) {
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

if ($PSCmdlet.ShouldProcess($SecureClassImporterPath, "Update class hashes")) {
    try {
        # Create backup
        $backupPath = "$SecureClassImporterPath.hash-backup"
        Copy-Item -Path $SecureClassImporterPath -Destination $backupPath -Force
        Write-Host "Backup created: $backupPath" -ForegroundColor Green

        # Read current content
        $content = Get-Content -Path $SecureClassImporterPath -Raw -Encoding UTF8
        $updatedContent = $content
        $updateCount = 0
        $addCount = 0

        # Track which classes exist and which are new
        $existingClasses = @{}
        $newClasses = @{}

        # Analyze each class file
        foreach ($fileName in $hashResults.Keys) {
            $newHash = $hashResults[$fileName]

            # Check if class entry exists (find existing pattern)
            $pattern = "('$fileName'\s*=\s*@\{[^}]*ExpectedHash\s*=\s*)'[A-F0-9]{64}'"

            if ($updatedContent -match $pattern) {
                $existingClasses[$fileName] = $newHash
            } else {
                $newClasses[$fileName] = $newHash
            }
        }

        # Update existing class hashes
        foreach ($fileName in $existingClasses.Keys) {
            $newHash = $existingClasses[$fileName]
            $pattern = "('$fileName'\s*=\s*@\{[^}]*ExpectedHash\s*=\s*)'[A-F0-9]{64}'"
            $replacement = "`${1}'$newHash'"

            $updatedContent = $updatedContent -replace $pattern, $replacement
            Write-Host "  Updated: $fileName" -ForegroundColor Green
            $updateCount++
        }

        # Add new class entries
        if ($newClasses.Count -gt 0) {
            Write-Host ""
            Write-Host "Adding new class entries..." -ForegroundColor Cyan

            # Find the closing brace of the approvedClasses hashtable
            $approvedClassesEndPattern = '(\s+}\s*\n\s*\$loadedClasses\s*=\s*@\(\))'

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
            }
"@
                    $newEntries += $newEntry
                    Write-Host "  Added: $fileName -> $className" -ForegroundColor Green
                    $addCount++
                }

                # Insert new entries before the closing brace
                $replacement = $newEntries + "`r`n        }`r`n        `$loadedClasses = @()"
                $updatedContent = $updatedContent -replace $approvedClassesEndPattern, $replacement

            } else {
                Write-Warning "Could not locate approvedClasses hashtable end to add new entries"
                foreach ($fileName in $newClasses.Keys) {
                    Write-Warning "  Skipped: $fileName (new class - manual addition required)"
                }
            }
        }

        # Save updated content
        if (($updateCount + $addCount) -gt 0) {
            Set-Content -Path $SecureClassImporterPath -Value $updatedContent -Encoding UTF8 -NoNewline
            Write-Host ""
            if ($updateCount -gt 0 -and $addCount -gt 0) {
                Write-Host "Successfully updated $updateCount hash(es) and added $addCount new class(es) in SecureClassImporter.ps1!" -ForegroundColor Green
            } elseif ($updateCount -gt 0) {
                Write-Host "Successfully updated $updateCount hash(es) in SecureClassImporter.ps1!" -ForegroundColor Green
            } else {
                Write-Host "Successfully added $addCount new class(es) to SecureClassImporter.ps1!" -ForegroundColor Green
            }
        } else {
            Write-Warning "No hashes were updated or added"
        }

    } catch {
        Write-Error "Update failed: $($_.Exception.Message)"

        # Restore backup
        if (Test-Path $backupPath) {
            Copy-Item -Path $backupPath -Destination $SecureClassImporterPath -Force
            Write-Host "Restored from backup" -ForegroundColor Yellow
        }
        throw
    }
}

Write-Host ""
Write-Host "Hash generation complete!" -ForegroundColor Green
