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

                    # Check if resolved path is within base path
                    $isWithinBasePath = $resolvedPath.Path.StartsWith($resolvedBasePath.Path, [System.StringComparison]::OrdinalIgnoreCase)

                    $isSafe = $isWithinBasePath -and (-not $patternFound)

                    if ($isSafe) {
                        $safePaths++
                    } else {
                        $unsafePaths++
                    }

                    $validationResults += [PSCustomObject]@{
                        OriginalPath = $currentPath
                        ResolvedPath = $resolvedPath.Path
                        BasePath = $resolvedBasePath.Path
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
