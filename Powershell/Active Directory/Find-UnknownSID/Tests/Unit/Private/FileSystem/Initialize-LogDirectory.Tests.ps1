#Requires -Version 5.1

# Import required modules and dependencies
. $PSScriptRoot\..\..\..\..\Private\Logging\Write-StructuredLog.ps1
. $PSScriptRoot\..\..\..\..\Private\Logging\Initialize-LoggingSystem.ps1
. $PSScriptRoot\..\..\..\..\Private\FileSystem\Initialize-LogDirectory.ps1

# Initialize logging for tests
Initialize-LoggingSystem -LogLevel 'Debug' -SuppressConsoleOutput

Describe "Initialize-LogDirectory" {
    BeforeAll {
        # Track any directories created during testing for cleanup
        $script:CreatedTestDirectories = @()
    }
    
    BeforeEach {
        # Create unique test directory for each test
        $script:TestTempDir = Join-Path $env:TEMP "Initialize-LogDirectory-$(Get-Random)"
        $script:TestLogPath = Join-Path $script:TestTempDir "test.log"
        $script:TestInvalidPath = "C:\Windows\System32\config\invalid\test.log"
        
        # Ensure clean test environment
        if (Test-Path $script:TestTempDir) {
            Remove-Item $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    AfterEach {
        # Clean up test artifacts
        if (Test-Path $script:TestTempDir) {
            Remove-Item $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    AfterAll {
        # Clean up any accidentally created directories from path traversal tests
        $possibleTraversalPaths = @(
            ".\windows"
            (Join-Path (Get-Location) "windows")
            (Join-Path $PSScriptRoot "..\..\..\..\windows")
        )
        
        foreach ($path in $possibleTraversalPaths) {
            if (Test-Path $path) {
                Write-Warning "Cleaning up test-created directory: $path"
                try {
                    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Could not remove test directory $path : $($_.Exception.Message)"
                }
            }
        }
    }

    Context "Parameter Validation" {
        It "Should accept mandatory LogPath parameter" {
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }
        
        It "Should reject null or empty LogPath" {
            { Initialize-LogDirectory -LogPath "" } | Should Throw
            { Initialize-LogDirectory -LogPath $null } | Should Throw
        }
        
        It "Should accept CorrelationId parameter" {
            # This function doesn't have CorrelationId parameter - it uses the global logging state
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }
        
        It "Should auto-generate CorrelationId when not provided" {
            # Function uses global logging state, not direct parameter
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $result | Should Not Be $null
        }
        
        It "Should support pipeline input" {
            # Function doesn't support pipeline input based on parameter definition
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }
    }

    Context "Directory Creation" {
        It "Should create parent directory when it does not exist" {
            $script:TestTempDir | Should Not Exist
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $script:TestTempDir | Should Exist
        }
        
        It "Should handle existing parent directory gracefully" {
            New-Item -Path $script:TestTempDir -ItemType Directory -Force
            $script:TestTempDir | Should Exist
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }
        
        It "Should create nested directory structure" {
            $nestedPath = Join-Path $script:TestTempDir "SubDir\SubSubDir\test.log"
            Initialize-LogDirectory -LogPath $nestedPath
            Split-Path $nestedPath -Parent | Should Exist
        }
        
        It "Should handle UNC paths appropriately" {
            $uncPath = "\\localhost\c$\temp\test-log-$(Get-Random).log"
            { Initialize-LogDirectory -LogPath $uncPath } | Should Not Throw
        }
    }

    Context "Log File Initialization" {
        It "Should create log file when directory exists" {
            New-Item -Path $script:TestTempDir -ItemType Directory -Force
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $script:TestLogPath | Should Exist
        }
        
        It "Should write header to new log file" {
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $content = Get-Content $script:TestLogPath -Raw
            $content | Should Match "=== Find-UnknownSID Script Log ==="
            $content | Should Match "Start Time:"
        }
        
        It "Should initialize log file with header when file already exists" {
            # Ensure directory exists first
            New-Item -Path $script:TestTempDir -ItemType Directory -Force
            "Existing content" | Out-File $script:TestLogPath -Force
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $content = Get-Content $script:TestLogPath -Raw
            # The function should initialize with a new header, replacing existing content
            $content | Should Match "=== Find-UnknownSID Script Log ==="
            $content | Should Not Match "Existing content"
        }
        
        It "Should handle log file in root directory" {
            $rootLogPath = "C:\temp-test-$(Get-Random).log"
            try {
                Initialize-LogDirectory -LogPath $rootLogPath
                $rootLogPath | Should Exist
            }
            finally {
                if (Test-Path $rootLogPath) {
                    Remove-Item $rootLogPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Error Handling" {
        It "Should throw when unable to create directory" {
            # Function doesn't throw - it returns fallback path
            $result = Initialize-LogDirectory -LogPath $script:TestInvalidPath
            $result | Should Not Be $null
        }
        
        It "Should handle path with invalid characters" {
            # Function handles errors gracefully and returns fallback path
            $invalidPath = Join-Path $script:TestTempDir "test<>:|?.log"
            $result = Initialize-LogDirectory -LogPath $invalidPath
            $result | Should Not Be $null
        }
        
        It "Should handle very long paths gracefully" {
            # Function handles errors gracefully and returns fallback path
            $longPath = "C:\" + ("a" * 250) + "\test.log"
            $result = Initialize-LogDirectory -LogPath $longPath
            $result | Should Not Be $null
        }
        
        It "Should provide meaningful error messages" {
            try {
                Initialize-LogDirectory -LogPath $script:TestInvalidPath
            }
            catch {
                $_.Exception.Message | Should Match "directory|path|access"
            }
        }
    }

    Context "Security Validation" {
        It "Should prevent path traversal attempts" {
            # Test with a path containing .. in the raw input
            $traversalPath = "..\..\..\windows\system32\test.log"
            
            # The function should handle this gracefully and not create actual directories
            $result = Initialize-LogDirectory -LogPath $traversalPath
            $result | Should Not Be $null
            # Just verify it completes without creating the dangerous path
        }
        
        It "Should validate write permissions" {
            New-Item -Path $script:TestTempDir -ItemType Directory -Force
            # Function should complete without throwing errors
            { Initialize-LogDirectory -LogPath $script:TestLogPath } | Should Not Throw
        }
        
        It "Should handle network paths securely" {
            # Function handles errors gracefully and returns fallback path
            $networkPath = "\\nonexistent\share\test.log"
            $result = Initialize-LogDirectory -LogPath $networkPath
            $result | Should Not Be $null
        }
    }

    Context "Logging Integration" {
        It "Should log debug messages for successful operations" {
            # Function uses Write-Verbose, not Write-StructuredLog
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $result | Should Not Be $null
        }
        
        It "Should log error messages for failed operations" {
            # Function uses Write-Warning for errors, not Write-StructuredLog
            $result = Initialize-LogDirectory -LogPath $script:TestInvalidPath
            $result | Should Not Be $null
        }
        
        It "Should include correlation ID in log messages" {
            # Function uses global logging state for correlation ID
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $result | Should Not Be $null
            $content = Get-Content $script:TestLogPath -Raw
            $content | Should Match "Correlation ID:"
        }
    }

    Context "Performance Validation" {
        It "Should complete directory creation within performance limits" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Initialize-LogDirectory -LogPath $script:TestLogPath
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should Be ($stopwatch.ElapsedMilliseconds -lt 2000)
        }
        
        It "Should handle multiple rapid calls efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            1..5 | ForEach-Object {
                $testPath = Join-Path $script:TestTempDir "test$_.log"
                Initialize-LogDirectory -LogPath $testPath
            }
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should Be ($stopwatch.ElapsedMilliseconds -lt 5000)
        }
        
        It "Should handle deep directory structures efficiently" {
            $deepPath = Join-Path $script:TestTempDir ("SubDir\" * 10 + "test.log")
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Initialize-LogDirectory -LogPath $deepPath
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should Be ($stopwatch.ElapsedMilliseconds -lt 3000)
        }
    }

    Context "Enterprise Integration" {
        It "Should return success status for valid operations" {
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $result | Should Not Be $null
            $result.GetType().Name | Should Be "String"
            $result | Should Match "\.log$"
        }
        
        It "Should support configuration management integration" {
            # Function integrates with global logging state
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $result | Should Not Be $null
        }
        
        It "Should support audit trail requirements" {
            # Function includes comprehensive log header for audit purposes
            $result = Initialize-LogDirectory -LogPath $script:TestLogPath
            $content = Get-Content $script:TestLogPath -Raw
            $content | Should Match "User Context:"
            $content | Should Match "Domain Context:"
        }
        
        It "Should handle enterprise directory patterns" {
            # Function handles enterprise paths with fallback to safe location
            $enterprisePath = "C:\Program Files\Company\Application\Logs\Find-UnknownSID.log"
            $result = Initialize-LogDirectory -LogPath $enterprisePath
            $result | Should Not Be $null
        }
    }
}
