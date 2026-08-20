function Resolve-WmicScanFile {
    <#
    .SYNOPSIS
        Expands the scan paths into the set of files a reader knows how to parse

    .DESCRIPTION
        Takes what the caller passed to -Path - files, directories, or wildcards - and returns
        one record per file worth reading, tagged with the reader that will handle it.

        Directories are walked in full, including subdirectories, with no -Recurse switch to
        remember. That is a deliberate departure from Get-ChildItem, and it is the right default
        here for one reason: the output of this tool is an inventory, and an inventory that
        silently covered only the top level of a deployment share is worse than no inventory,
        because it will be believed. Use -Exclude to cut branches out.

        Extensions with no reader are skipped without comment. .psd1 is deliberately absent -
        it is data, and a WMIC string inside one is a rule table like this module's own, not a
        call site.

    .PARAMETER Path
        [System.String[]] (Mandatory, No Pipeline Support)

        Files, directories, or wildcard patterns to scan.

    .PARAMETER Exclude
        [System.String[]] (Optional, No Pipeline Support)

        Wildcard patterns tested against each file's full path and its path relative to the scan
        root. A file matching any of them is dropped. Use it for vendor trees and build output.

    .PARAMETER Extension
        [System.String[]] (Optional, No Pipeline Support)

        Restrict the scan to these extensions, given with the leading dot. Omit to read every
        extension the module has a reader for.

    .OUTPUTS
        WmicTriage.ScanFile objects carrying Path, RelativePath and FileType.

    .EXAMPLE
        $files = Resolve-WmicScanFile -Path '\\dp01\Deploy$\Scripts' -Exclude '*\Vendor\*'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType('WmicTriage.ScanFile')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [string[]]$Extension
    )

    $wanted = $null
    if ($Extension) {
        $wanted = @{}
        foreach ($item in $Extension) {
            $normalized = $item.Trim()
            if ($normalized -and $normalized[0] -ne '.') { $normalized = ".$normalized" }
            $wanted[$normalized.ToLowerInvariant()] = $true
        }
    }

    $seen = @{}

    foreach ($entry in $Path) {
        $resolved = $null
        try {
            $resolved = Resolve-Path -Path $entry -ErrorAction Stop
        }
        catch {
            Write-Warning "Skipping '$entry': $($_.Exception.Message)"
            continue
        }

        foreach ($target in $resolved) {
            $targetPath = $target.ProviderPath
            $isContainer = Test-Path -LiteralPath $targetPath -PathType Container

            if ($isContainer) {
                $root = $targetPath
                $files = Get-ChildItem -LiteralPath $targetPath -File -Recurse -ErrorAction SilentlyContinue
            }
            else {
                $root = Split-Path -Path $targetPath -Parent
                $files = Get-Item -LiteralPath $targetPath -ErrorAction SilentlyContinue
            }

            foreach ($file in $files) {
                # Not $extension: PowerShell is case-insensitive, so that would assign to the
                # [string[]]$Extension parameter above, coercing a string into a single-element
                # array. Every ContainsKey lookup below would then miss and the scan would
                # return nothing at all, without an error to explain why.
                $fileExtension = $file.Extension.ToLowerInvariant()
                if (-not $script:FileTypeMap.ContainsKey($fileExtension)) { continue }
                if ($wanted -and -not $wanted.ContainsKey($fileExtension)) { continue }
                if ($seen.ContainsKey($file.FullName)) { continue }

                $relative = Get-WmicRelativePath -FullName $file.FullName -Root $root

                $skip = $false
                foreach ($pattern in $Exclude) {
                    if ($file.FullName -like $pattern -or $relative -like $pattern) {
                        $skip = $true
                        break
                    }
                }
                if ($skip) { continue }

                $seen[$file.FullName] = $true

                [PSCustomObject]@{
                    PSTypeName   = 'WmicTriage.ScanFile'
                    Path         = $file.FullName
                    RelativePath = $relative
                    FileType     = $script:FileTypeMap[$fileExtension]
                    Length       = $file.Length
                }
            }
        }
    }
}
