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
        foreach ($currentPath in $Path) {
            $totalPaths++

            try {
                if (Test-Path $currentPath) {
                    $resolvedPath = Resolve-Path $currentPath -ErrorAction Stop
                    $resolvedBasePath = Resolve-Path $BasePath -ErrorAction Stop

                    # Check if resolved path is within base path
                    $isWithinBasePath = $resolvedPath.Path.StartsWith($resolvedBasePath.Path, [System.StringComparison]::OrdinalIgnoreCase)

                    # Check for traversal patterns
                    $patternFound = $false
                    foreach ($pattern in $traversalPatterns) {
                        if ($currentPath -match $pattern) {
                            $patternFound = $true
                            break
                        }
                    }

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
                    $unsafePaths++
                    Write-Warning "Path does not exist: $currentPath"
                }
            } catch {
                $unsafePaths++
                Write-Error "Error validating path $currentPath : $($_.Exception.Message)"
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
            CorrelationId = $CorrelationId
        }
    }
}
