#Requires -Version 5.1

function Resolve-ClassPath {
    <#
    .SYNOPSIS
        Resolves and validates PowerShell class file paths for secure loading

    .DESCRIPTION
        Handles path resolution, existence checking, and basic accessibility validation
        for PowerShell class files. This module focuses solely on path operations and
        does not perform security validation - that's handled by dedicated security modules.

    .PARAMETER ClassesPath
        Base directory path containing class files. Must be a valid directory
        path accessible by the current user.

    .PARAMETER ClassNames
        Array of class file names to resolve. Should include the .ps1 extension.

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes. If not provided,
        a new GUID will be generated automatically.

    .EXAMPLE
        Resolve-ClassPath -ClassesPath ".\Classes" -ClassNames @("ScriptConfiguration.ps1", "MemoryManager.ps1")

        DESCRIPTION: Resolves paths for multiple class files
        OUTPUT: Array of resolved path objects with validation status

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For path resolution issues: .\Troubleshooting\Common\Path-Resolution-Issues.md
        - For file access problems: .\Troubleshooting\Common\File-Access-Issues.md
    #>

    [CmdletBinding()]
    [OutputType('ResolvedClassPath')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClassesPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ClassNames,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting class path resolution - CorrelationId: $CorrelationId"
        $resolvedPaths = @()
    }

    process {
        try {
            # First, validate and resolve the base Classes directory
            Write-Verbose "Resolving base classes directory: $ClassesPath"

            if (-not (Test-Path $ClassesPath -PathType Container)) {
                throw "Classes directory not found or not accessible: $ClassesPath"
            }

            $resolvedClassesPath = Resolve-Path -Path $ClassesPath -ErrorAction Stop
            Write-Verbose "Resolved base classes path: $($resolvedClassesPath.Path)"

            # Process each class file
            foreach ($className in $ClassNames) {
                try {
                    Write-Verbose "Resolving path for class: $className"

                    # Construct full path to class file
                    $classFilePath = Join-Path $ClassesPath $className

                    # Initialize result object
                    $pathResult = [PSCustomObject]@{
                        PSTypeName = 'ResolvedClassPath'
                        ClassName = $className
                        RequestedPath = $classFilePath
                        FullPath = $null
                        BaseDirectory = $resolvedClassesPath.Path
                        IsValid = $false
                        Exists = $false
                        IsAccessible = $false
                        Error = $null
                        ResolvedAt = Get-Date
                        CorrelationId = $CorrelationId
                    }

                    # Check file existence
                    if (Test-Path $classFilePath -PathType Leaf) {
                        $pathResult.Exists = $true

                        # Resolve to full path
                        $resolvedPath = Resolve-Path -Path $classFilePath -ErrorAction Stop
                        $pathResult.FullPath = $resolvedPath.Path

                        # Test basic accessibility (read permissions)
                        try {
                            $null = Get-Item -Path $resolvedPath.Path -ErrorAction Stop
                            $pathResult.IsAccessible = $true
                            $pathResult.IsValid = $true

                            Write-Verbose "Successfully resolved: $className -> $($resolvedPath.Path)"
                        }
                        catch {
                            $pathResult.Error = "File exists but is not accessible: $($_.Exception.Message)"
                            $pathResult.IsAccessible = $false
                            Write-Warning "File accessibility issue for $className : $($pathResult.Error)"
                        }
                    }
                    else {
                        $pathResult.Error = "Class file not found: $classFilePath"
                        Write-Warning "Class file not found: $className"
                    }

                    $resolvedPaths += $pathResult
                }
                catch {
                    # Handle individual class resolution errors
                    $errorResult = [PSCustomObject]@{
                        PSTypeName = 'ResolvedClassPath'
                        ClassName = $className
                        RequestedPath = $classFilePath
                        FullPath = $null
                        BaseDirectory = $resolvedClassesPath.Path
                        IsValid = $false
                        Exists = $false
                        IsAccessible = $false
                        Error = "Path resolution failed: $($_.Exception.Message)"
                        ResolvedAt = Get-Date
                        CorrelationId = $CorrelationId
                    }

                    $resolvedPaths += $errorResult
                    Write-Warning "Failed to resolve path for class $className : $($_.Exception.Message)"
                }
            }
        }
        catch {
            $errorMessage = "Base directory resolution failed: $($_.Exception.Message)"
            Write-Error $errorMessage -ErrorAction Stop
        }
    }

    end {
        $validCount = ($resolvedPaths | Where-Object { $_.IsValid }).Count
        $totalCount = $resolvedPaths.Count

        Write-Verbose "Path resolution completed: $validCount/$totalCount paths resolved successfully"

        # Return resolved paths
        return $resolvedPaths
    }
}
