#Requires -Version 5.1

<#
.SYNOPSIS
    Test-DirectoryAccess - File system utilities for Find-UnknownSID Solution

.DESCRIPTION
    This module provides focused file system operations and validation functions
    for the Find-UnknownSID enterprise solution. Specialized in secure file
    system access validation and directory management.

    BUSINESS VALUE:
    - Reliable directory access validation for backup operations
    - Secure file system operations with proper error handling
    - Automated directory creation with permission validation
    - Cross-platform file system compatibility

    TECHNICAL FEATURES:
    - Directory existence and access validation
    - Automatic directory creation with error handling
    - Write permission testing through temporary files
    - Comprehensive logging for audit requirements

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-01-27
    Version: 1.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)

    TROUBLESHOOTING:
    - For directory access issues: .\Troubleshooting\Common\Directory-Access-Issues.md
    - For permission problems: .\Troubleshooting\Security\File-Permissions.md

    DEPENDENCIES:
    - Integrates with enterprise logging infrastructure
    - Requires appropriate file system permissions for directory operations
    - Uses temporary file creation for write access validation
#>

function Test-DirectoryAccess {
    <#
    .SYNOPSIS
        Tests directory access with automatic creation and validation

    .DESCRIPTION
        Validates that a directory exists and is writable, creating it if necessary
        with comprehensive error handling and security validation. Performs actual
        write testing to ensure operational readiness.

        BUSINESS VALUE:
        - Prevents backup operation failures through pre-validation
        - Ensures reliable log file creation and management
        - Supports automated directory provisioning
        - Provides early detection of permission issues

        SECURITY FEATURES:
        - Validates directory path for security compliance
        - Tests actual write permissions through file operations
        - Logs security-relevant access attempts
        - Prevents operations on invalid or dangerous paths

    .PARAMETER Path
        [String] (Mandatory) Directory path to test and create if needed.
        Must be a valid file system path.

    .PARAMETER CorrelationId
        [String] (Optional) Correlation ID for audit trail tracking.
        Auto-generated if not provided.

    .EXAMPLE
        PS> Test-DirectoryAccess -Path "C:\Backups"

        DESCRIPTION: Ensures backup directory exists and is writable
        OUTPUT: $true if accessible, $false otherwise
        USE CASE: Pre-validation before file operations

    .EXAMPLE
        PS> Test-DirectoryAccess -Path "\\server\share\logs"

        DESCRIPTION: Tests network share access and creates directory
        OUTPUT: $true if UNC path is accessible and writable
        NETWORK: Validates network drive access for centralized logging

    .EXAMPLE
        PS> $backupPaths | Test-DirectoryAccess

        DESCRIPTION: Pipeline validation of multiple directory paths
        OUTPUT: Array of boolean values for each path
        AUTOMATION: Bulk validation for multiple backup locations

    .OUTPUTS
        [Bool] True if directory is accessible and writable, false otherwise

    .NOTES
        SECURITY CONSIDERATIONS:
        - Validates path format to prevent traversal attacks
        - Tests actual write permissions through temporary file creation
        - Logs all directory creation and access attempts
        - Fails safely if permissions are insufficient
        - Cleans up test files to prevent information disclosure

        VALIDATION PROCESS:
        1. Path format and security validation
        2. Directory existence check
        3. Directory creation if needed (with error handling)
        4. Write access test through temporary file creation
        5. Cleanup of test files
        6. Comprehensive logging of all operations

        PERFORMANCE CHARACTERISTICS:
        - Validation time: <100ms per directory typically
        - Memory usage: Minimal, no persistent state
        - Thread safety: Stateless function safe for parallel processing
        - Network-aware: Handles UNC paths and mapped drives
        - Cross-platform: Compatible with Windows, Linux, macOS paths
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            # Basic path validation
            if ([string]::IsNullOrWhiteSpace($Path)) {
                Write-StructuredLog "Directory access test failed: Path parameter was empty or null" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                return $false
            }

            # Security validation - basic path traversal protection
            if ($Path.Contains('..') -or $Path.Contains('\\.\') -or $Path.Contains('/./')) {
                Write-StructuredLog "Directory access test failed: Path contains potential traversal elements: $Path" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                return $false
            }

            Write-StructuredLog "Testing directory access for path: $Path" -Level Debug -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId

            # Test if directory exists
            if (-not (Test-Path $Path -PathType Container)) {
                Write-StructuredLog "Directory does not exist, attempting to create: $Path" -Level Information -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId

                try {
                    # Try to create the directory
                    $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
                    Write-StructuredLog "Successfully created directory: $Path" -Level Information -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                }
                catch {
                    Write-StructuredLog "Failed to create directory '$Path': $($_.Exception.Message)" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                    return $false
                }
            }

            # Test write access by creating a temporary file
            $testFileName = "access_test_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
            $testFilePath = Join-Path $Path $testFileName

            try {
                # Attempt to write a test file
                "Directory access test - $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))" | Out-File -FilePath $testFilePath -ErrorAction Stop

                # Verify file was created and is readable
                if (Test-Path $testFilePath) {
                    Write-StructuredLog "Write access test successful for directory: $Path" -Level Debug -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                    $writeAccessSuccessful = $true
                } else {
                    Write-StructuredLog "Write access test failed: File was not created in directory: $Path" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                    $writeAccessSuccessful = $false
                }
            }
            catch {
                Write-StructuredLog "Write access test failed for directory '$Path': $($_.Exception.Message)" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                $writeAccessSuccessful = $false
            }
            finally {
                # Clean up test file
                if (Test-Path $testFilePath) {
                    try {
                        Remove-Item $testFilePath -Force -ErrorAction SilentlyContinue
                        Write-StructuredLog "Cleaned up test file: $testFilePath" -Level Debug -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                    }
                    catch {
                        Write-StructuredLog "Warning: Could not clean up test file '$testFilePath': $($_.Exception.Message)" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                    }
                }
            }

            if ($writeAccessSuccessful) {
                Write-StructuredLog "Directory access validation successful: $Path" -Level Debug -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                return $true
            } else {
                Write-StructuredLog "Directory access validation failed: $Path" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
                return $false
            }
        }
        catch {
            Write-StructuredLog "Directory access test error for '$Path': $($_.Exception.Message)" -Level Warning -Component 'FileSystem-Utilities' -CorrelationId $CorrelationId
            return $false
        }
    }
}

Write-StructuredLog "FileSystem-Utilities module loaded successfully" -Level Debug -Component 'FileSystem-Utilities' -CorrelationId ([System.Guid]::NewGuid().ToString())
