function Test-PathTraversal {
    <#
    .SYNOPSIS
        Tests for path traversal vulnerabilities in file paths
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Path,

        [Parameter()]
        [string]$BasePath = (Get-Location).Path,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        $validationResults = @()
        $totalPaths = 0
        $safePaths = 0
        $unsafePaths = 0

        # Common traversal patterns
        $traversalPatterns = @(
            '\.\.[\\/]',
            '\.\.%2f',
            '\.\.%5c',
            '%2e%2e%2f',
            '%2e%2e%5c'
        )
    }

    process {
        # Validate base path first - throw error for invalid base paths
        try {
            $resolvedBasePath = Resolve-Path $BasePath -ErrorAction Stop
        } catch {
            throw "Invalid base path: $BasePath - $($_.Exception.Message)"
        }

        foreach ($currentPath in $Path) {
            $totalPaths++

            try {
                # Check for traversal patterns first (before path existence)
                $patternFound = $false
                foreach ($pattern in $traversalPatterns) {
                    if ($currentPath -match $pattern) {
                        $patternFound = $true
                        break
                    }
                }

                if (Test-Path $currentPath) {
                    $resolvedPath = Resolve-Path $currentPath -ErrorAction Stop
                    
                    # Check if this is a symbolic link or junction and resolve to target
                    $finalTargetPath = $resolvedPath.Path
                    $isSymbolicLink = $false
                    
                    try {
                        $item = Get-Item $currentPath -ErrorAction Stop
                        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            $isSymbolicLink = $true
                            # For symbolic links/junctions, get the actual target
                            if ($item.Target) {
                                $targetPath = $item.Target[0]  # Get first target
                                if ([System.IO.Path]::IsPathRooted($targetPath)) {
                                    $finalTargetPath = $targetPath
                                } else {
                                    # Relative target - resolve relative to link directory
                                    $linkDirectory = Split-Path $resolvedPath.Path -Parent
                                    $finalTargetPath = Join-Path $linkDirectory $targetPath
                                    $finalTargetPath = [System.IO.Path]::GetFullPath($finalTargetPath)
                                }
                            }
                        }
                    }
                    catch {
                        # If we can't determine symbolic link status, continue with original path
                        Write-Verbose "Could not determine symbolic link status for $currentPath : $($_.Exception.Message)"
                    }

                    # Check if final target path is within base path
                    $isWithinBasePath = $finalTargetPath.StartsWith($resolvedBasePath.Path, [System.StringComparison]::OrdinalIgnoreCase)

                    $isSafe = $isWithinBasePath -and (-not $patternFound)

                    if ($isSafe) {
                        $safePaths++
                    } else {
                        $unsafePaths++
                    }

                    $validationResults += [PSCustomObject]@{
                        OriginalPath = $currentPath
                        ResolvedPath = $resolvedPath.Path
                        FinalTargetPath = $finalTargetPath
                        BasePath = $resolvedBasePath.Path
                        IsSymbolicLink = $isSymbolicLink
                        IsWithinBasePath = $isWithinBasePath
                        ContainsTraversalPattern = $patternFound
                        IsSafe = $isSafe
                        CorrelationId = $CorrelationId
                    }
                } else {
                    # Path doesn't exist, but still check for traversal patterns
                    $unsafePaths++
                    
                    # Only warn in non-test environments to reduce test noise
                    if (-not $env:PESTER_TESTING) {
                        Write-Warning "Path does not exist: $currentPath"
                    }
                    
                    $validationResults += [PSCustomObject]@{
                        OriginalPath = $currentPath
                        ResolvedPath = $null
                        BasePath = $BasePath
                        IsWithinBasePath = $false
                        ContainsTraversalPattern = $patternFound
                        IsSafe = $false
                        CorrelationId = $CorrelationId
                    }
                }
            } catch {
                $unsafePaths++
                Write-Error "Error validating path $currentPath : $($_.Exception.Message)"
                
                $validationResults += [PSCustomObject]@{
                    OriginalPath = $currentPath
                    ResolvedPath = $null
                    BasePath = $BasePath
                    IsWithinBasePath = $false
                    ContainsTraversalPattern = $patternFound
                    IsSafe = $false
                    CorrelationId = $CorrelationId
                }
            }
        }
    }

    end {
        $validationPassed = ($unsafePaths -eq 0)

        $validationSummary = @{
            TotalPaths = $totalPaths
            SafePaths = $safePaths
            UnsafePaths = $unsafePaths
            ValidationPassed = $validationPassed
        }

        # Log completion summary
        if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
            $logLevel = if (-not $validationPassed) { 'Warning' } else { 'Information' }
            Write-StructuredLog -Level $logLevel -Message "Path traversal validation completed" -CorrelationId $CorrelationId -Data $validationSummary
        }

        return [PSCustomObject]@{
            PSTypeName = 'PathTraversalValidationResult'
            ValidationResults = $validationResults
            TotalPaths = $totalPaths
            SafePaths = $safePaths
            UnsafePaths = $unsafePaths
            ValidationPassed = $validationPassed
            BasePath = $BasePath
            CorrelationId = $CorrelationId
        }
    }
}
