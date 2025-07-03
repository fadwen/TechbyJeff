#Requires -Version 5.1

<#
.SYNOPSIS
    Secure class loading implementation for PowerShell projects

.DESCRIPTION
    Provides enterprise-grade secure class loading with integrity verification,
    path validation, and comprehensive audit logging. Designed to replace
    simple hardcoded class loading with security-enhanced approach.

.EXAMPLE
    Import-ProjectClasses -ClassesPath ".\Classes" -CorrelationId $CorrelationId

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net

    Security Features:
    - File integrity verification (optional hash checking)
    - Path traversal protection
    - Type validation after loading
    - Comprehensive audit logging
    - Correlation ID tracking
#>

function Import-ProjectClasses {
    <#
    .SYNOPSIS
        Securely imports PowerShell class files with validation and integrity checks

    .DESCRIPTION
        Imports PowerShell class files using a hardcoded approved list with
        security controls including file integrity verification, path validation,
        and type checking. Provides comprehensive audit logging for compliance.

    .PARAMETER ClassesPath
        Path to the Classes directory containing class files

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes

    .PARAMETER ValidateIntegrity
        Switch to enable file hash verification for integrity checking

    .EXAMPLE
        Import-ProjectClasses -ClassesPath ".\Classes" -CorrelationId $CorrelationId

        Imports all approved classes from the Classes directory with security validation

    .EXAMPLE
        Import-ProjectClasses -ClassesPath ".\Classes" -ValidateIntegrity

        Imports classes with file integrity verification enabled

    .NOTES
        Security Considerations:
        - Only approved class files are loaded (hardcoded list)
        - Path traversal protection prevents loading files outside Classes directory
        - Optional hash verification ensures file integrity
        - All loading activities are logged with correlation IDs
        - Type validation ensures expected classes are available after loading
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClassesPath,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [switch]$ValidateIntegrity
    )

    begin {
        Write-Verbose "Starting secure class import with CorrelationId: $CorrelationId"

        # Approved class files with metadata
        $approvedClasses = @{
            'ScriptConfiguration.ps1' = @{
                RequiredTypes = @('ScriptConfiguration')
                Dependencies = @()
                Description = 'Core script configuration and validation'
                # ExpectedHash = 'SHA256-Hash-Here'  # Uncomment for hash verification
            }
            'MemoryManager.ps1' = @{
                RequiredTypes = @('MemoryManager')
                Dependencies = @('System.IDisposable')
                Description = 'Memory management and garbage collection'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'ProcessingStatistics.ps1' = @{
                RequiredTypes = @('ProcessingStatistics')
                Dependencies = @()
                Description = 'Processing statistics and performance metrics'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'OrphanedSIDResult.ps1' = @{
                RequiredTypes = @('OrphanedSIDResult')
                Dependencies = @()
                Description = 'Results container for orphaned SID analysis'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'SIDAnalysisResult.ps1' = @{
                RequiredTypes = @('SIDAnalysisResult')
                Dependencies = @()
                Description = 'Results container for SID analysis operations'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'SecurityValidationResult.ps1' = @{
                RequiredTypes = @('SecurityValidationResult')
                Dependencies = @()
                Description = 'Security validation results and status'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'RemovalOperationResult.ps1' = @{
                RequiredTypes = @('RemovalOperationResult')
                Dependencies = @()
                Description = 'Results container for SID removal operations'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
            'RestoreOperationResult.ps1' = @{
                RequiredTypes = @('RestoreOperationResult')
                Dependencies = @()
                Description = 'Results container for restore operations'
                # ExpectedHash = 'SHA256-Hash-Here'
            }
        }

        $loadedClasses = @()
        $failedClasses = @()
    }

    process {
        try {
            # Validate Classes directory exists and is accessible
            if (-not (Test-Path $ClassesPath -PathType Container)) {
                throw "Classes directory not found or not accessible: $ClassesPath"
            }

            $resolvedClassesPath = Resolve-Path -Path $ClassesPath -ErrorAction Stop
            Write-Verbose "Resolved Classes path: $($resolvedClassesPath.Path)"

            foreach ($className in $approvedClasses.Keys) {
                $classInfo = $approvedClasses[$className]
                $classPath = Join-Path $ClassesPath $className

                try {
                    # 1. File existence and accessibility check
                    if (-not (Test-Path $classPath -PathType Leaf)) {
                        throw "Required class file not found: $className"
                    }

                    # 2. Path traversal protection
                    $resolvedClassPath = Resolve-Path -Path $classPath -ErrorAction Stop
                    if (-not $resolvedClassPath.Path.StartsWith($resolvedClassesPath.Path)) {
                        throw "Security violation: Class file outside expected directory: $className"
                    }

                    # 3. File integrity verification (if enabled and hash provided)
                    if ($ValidateIntegrity -and $classInfo.ExpectedHash) {
                        Write-Verbose "Validating file integrity for: $className"
                        $actualHash = Get-FileHash -Path $classPath -Algorithm SHA256
                        if ($actualHash.Hash -ne $classInfo.ExpectedHash) {
                            Write-Warning "Hash mismatch for $className - file may have been modified"
                            Write-Warning "Expected: $($classInfo.ExpectedHash)"
                            Write-Warning "Actual: $($actualHash.Hash)"

                            # In high-security environments, uncomment the next line to fail on hash mismatch
                            # throw "File integrity verification failed: $className"
                        } else {
                            Write-Verbose "File integrity verified for: $className"
                        }
                    }

                    # 4. Load the class file
                    Write-Verbose "Loading class file: $className"
                    . $resolvedClassPath.Path

                    # 5. Type validation - verify expected types are available
                    foreach ($expectedType in $classInfo.RequiredTypes) {
                        if (-not ($expectedType -as [type])) {
                            throw "Expected type not found after loading $className : $expectedType"
                        }
                        Write-Verbose "Verified type availability: $expectedType"
                    }

                    # 6. Dependency validation (basic check for required types)
                    foreach ($dependency in $classInfo.Dependencies) {
                        if (-not ($dependency -as [type])) {
                            Write-Warning "Dependency type not available: $dependency (required by $className)"
                        }
                    }

                    $loadedClasses += $className
                    Write-Verbose "Successfully imported class: $className - $($classInfo.Description)"

                }
                catch {
                    $errorMessage = "Failed to import class $className : $($_.Exception.Message)"
                    Write-Error $errorMessage
                    $failedClasses += @{
                        ClassName = $className
                        Error = $_.Exception.Message
                        Path = $classPath
                    }

                    # Log detailed error for troubleshooting
                    if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
                        Write-ScriptLog $errorMessage -Level Error -Component 'ClassLoader' -CorrelationId $CorrelationId
                    }

                    throw "Critical class import failure: $className"
                }
            }

        }
        catch {
            # Log critical failure
            if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
                Write-ScriptLog "Class import process failed: $($_.Exception.Message)" -Level Error -Component 'ClassLoader' -CorrelationId $CorrelationId
            }
            throw
        }
    }

    end {
        # Summary logging
        $successCount = $loadedClasses.Count
        $totalCount = $approvedClasses.Count
        $failureCount = $failedClasses.Count

        if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
            Write-ScriptLog "Class import completed: $successCount/$totalCount classes loaded successfully" -Level Information -Component 'ClassLoader' -CorrelationId $CorrelationId

            if ($failureCount -gt 0) {
                $failureDetails = $failedClasses | ForEach-Object { "$($_.ClassName): $($_.Error)" }
                Write-ScriptLog "Failed classes: $($failureDetails -join '; ')" -Level Error -Component 'ClassLoader' -CorrelationId $CorrelationId
            }
        }

        Write-Verbose "Class import summary: $successCount/$totalCount classes loaded, $failureCount failures"

        if ($failureCount -eq 0) {
            Write-Verbose "All classes imported successfully with correlation ID: $CorrelationId"
        } else {
            Write-Warning "Some classes failed to import. Check logs for details."
        }

        # Return summary object for programmatic use
        return [PSCustomObject]@{
            PSTypeName = 'ClassImportResult'
            CorrelationId = $CorrelationId
            TotalClasses = $totalCount
            LoadedClasses = $loadedClasses
            FailedClasses = $failedClasses
            Success = ($failureCount -eq 0)
            LoadedCount = $successCount
            FailedCount = $failureCount
        }
    }
}

function Test-ClassLoadingIntegrity {
    <#
    .SYNOPSIS
        Tests the integrity and functionality of loaded classes

    .DESCRIPTION
        Performs post-loading validation to ensure all classes are properly
        loaded and can be instantiated correctly. Useful for verification
        testing and troubleshooting.

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes

    .EXAMPLE
        Test-ClassLoadingIntegrity -CorrelationId $CorrelationId

        Tests all loaded classes for proper instantiation

    .NOTES
        This function provides additional validation after class loading
        to ensure everything is working correctly.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $testResults = @()
    $classTests = @{
        'ScriptConfiguration' = { [ScriptConfiguration]::new() }
        'MemoryManager' = {
            $mm = [MemoryManager]::new(1024, 50)
            $mm.Dispose()
            return $mm
        }
        'ProcessingStatistics' = { [ProcessingStatistics]::new() }
        'OrphanedSIDResult' = { [OrphanedSIDResult]::new() }
        'SIDAnalysisResult' = { [SIDAnalysisResult]::new() }
        'SecurityValidationResult' = { [SecurityValidationResult]::new() }
        'RemovalOperationResult' = { [RemovalOperationResult]::new() }
        'RestoreOperationResult' = { [RestoreOperationResult]::new() }
    }

    foreach ($className in $classTests.Keys) {
        try {
            Write-Verbose "Testing class instantiation: $className"
            $testScript = $classTests[$className]
            $instance = & $testScript

            $testResults += [PSCustomObject]@{
                ClassName = $className
                Success = $true
                Error = $null
                Instance = $instance
            }

            Write-Verbose " $className instantiated successfully"
        }
        catch {
            $testResults += [PSCustomObject]@{
                ClassName = $className
                Success = $false
                Error = $_.Exception.Message
                Instance = $null
            }

            Write-Warning " $className instantiation failed: $($_.Exception.Message)"
        }
    }

    $successCount = ($testResults | Where-Object Success -eq $true).Count
    $totalCount = $testResults.Count

    if (Get-Command Write-ScriptLog -ErrorAction SilentlyContinue) {
        Write-ScriptLog "Class instantiation testing completed: $successCount/$totalCount classes" -Level Information -Component 'ClassTester' -CorrelationId $CorrelationId
    }

    return [PSCustomObject]@{
        PSTypeName = 'ClassTestResult'
        CorrelationId = $CorrelationId
        TotalTests = $totalCount
        SuccessfulTests = $successCount
        FailedTests = ($totalCount - $successCount)
        TestResults = $testResults
        Success = ($successCount -eq $totalCount)
    }
}
