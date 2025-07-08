function Import-SecureClasses {
    <#
    .SYNOPSIS
        Returns validated class paths for loading by the caller

    .DESCRIPTION
        Performs security validation and returns the paths that need to be
        dot-sourced by the caller at script level for proper class loading.

    .PARAMETER ClassNames
        Array of class names to validate and prepare for loading

    .PARAMETER ClassesPath
        Path to classes directory (defaults to .\Classes)

    .PARAMETER ValidateIntegrity
        Enable file integrity validation

    .PARAMETER ValidationOnly
        Only validate classes without preparing paths for loading

    .PARAMETER CorrelationId
        Correlation ID for tracking

    .EXAMPLE
        $classResult = Import-SecureClasses -ClassNames @('ScriptConfiguration', 'MemoryManager')
        if ($classResult.Success) {
            $classResult.PathsToLoad | ForEach-Object { . $_ }
        }

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For class loading issues: .\Troubleshooting\Common\Class-Loading-Issues.md
        - For validation errors: .\Troubleshooting\Security\Class-Validation-Errors.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ClassNames,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ClassesPath = ".\Classes",

        [Parameter()]
        [switch]$ValidateIntegrity,

        [Parameter()]
        [switch]$ValidationOnly,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $validatedClasses = @()
    $failedClasses = @()
    $pathsToLoad = @()

    # Get approved class list
    try {
        Write-Verbose "Getting approved class list..."
        $approvedConfig = Get-ApprovedClassList -CorrelationId $CorrelationId
        $approvedClasses = $approvedConfig.Classes
    }
    catch {
        Write-Error "Failed to get approved class list: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            ValidatedClasses = @()
            FailedClasses = $ClassNames
            PathsToLoad = @()
            TotalClasses = $ClassNames.Count
            Error = "Failed to get approved class configuration"
        }
    }

    # Validate requested classes are approved
    foreach ($className in $ClassNames) {
        $classFileName = "$className.ps1"
        if ($classFileName -notin $approvedClasses.Keys) {
            Write-Error "Unapproved class requested: $className"
            $failedClasses += $className
        }
    }

    if ($failedClasses.Count -gt 0) {
        return [PSCustomObject]@{
            Success = $false
            ValidatedClasses = @()
            FailedClasses = $failedClasses
            PathsToLoad = @()
            TotalClasses = $ClassNames.Count
            Error = "Unapproved classes requested"
        }
    }

    # Create class file names
    $classFileNames = $ClassNames | ForEach-Object { "$_.ps1" }

    # Resolve class paths
    try {
        Write-Verbose "Resolving class paths..."
        $pathResults = Resolve-ClassPath -ClassesPath $ClassesPath -ClassNames $classFileNames -CorrelationId $CorrelationId
        $validPaths = $pathResults | Where-Object { $_.IsValid }

        if ($validPaths.Count -ne $ClassNames.Count) {
            $invalidClasses = $pathResults | Where-Object { -not $_.IsValid } | ForEach-Object { $_.ClassName -replace '\.ps1$', '' }
            $failedClasses += $invalidClasses
        }
    }
    catch {
        Write-Error "Path resolution failed: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            ValidatedClasses = @()
            FailedClasses = $ClassNames
            PathsToLoad = @()
            TotalClasses = $ClassNames.Count
            Error = "Path resolution failed"
        }
    }

    if ($ValidationOnly) {
        return [PSCustomObject]@{
            Success = ($failedClasses.Count -eq 0)
            ValidatedClasses = @()
            FailedClasses = $failedClasses
            PathsToLoad = @()
            TotalClasses = $ClassNames.Count
            ValidationOnly = $true
        }
    }

    # Prepare paths for loading
    foreach ($pathResult in $validPaths) {
        $className = $pathResult.ClassName -replace '\.ps1$', ''

        try {
            Write-Verbose "Validating class path: $className from $($pathResult.FullPath)"

            # Perform security validation
            if ($ValidateIntegrity) {
                $integrityResult = Test-ClassIntegrity -ClassPath $pathResult.FullPath -CorrelationId $CorrelationId
                if (-not $integrityResult.IsValid) {
                    $failedClasses += $className
                    Write-Error "Class integrity validation failed: $className"
                    continue
                }
            }

            # Add to validated list
            $validatedClasses += $className
            $pathsToLoad += $pathResult.FullPath
            Write-Verbose "Successfully validated: $className"
        }
        catch {
            Write-Error "Failed to validate class $className : $($_.Exception.Message)"
            $failedClasses += $className
        }
    }

    return [PSCustomObject]@{
        Success = ($failedClasses.Count -eq 0)
        ValidatedClasses = $validatedClasses
        FailedClasses = $failedClasses
        PathsToLoad = $pathsToLoad
        TotalClasses = $ClassNames.Count
    }
}
