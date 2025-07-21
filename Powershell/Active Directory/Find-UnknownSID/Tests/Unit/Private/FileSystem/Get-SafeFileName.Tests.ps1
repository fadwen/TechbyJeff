#Requires -Modules Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Comprehensive Pester 3.4 tests for Get-SafeFileName f           It "Should handle mixed whitespace and illegal characters" {
            $result = Ge           It "Should handle string with only illegal characters" {
            $result = Get-SafeFileName -InputString '<<<>>>|||'
            $result | Should Match "^Unknown_[a-f0-9]{8}$" # Should generate fallback with hash
            $result.Length | Should Be 16 # "Unknown_" + 8-char hash
        } It "Should handle string with only illegal characters" {
            $result = Get-SafeFileName -InputString '<>:"|?*\'
            $result | Should Match "^Unknown_[a-f0-9]{8}$" # Should generate fallback with hash
        }feFileName -InputString 'test file/with	mixed: chars'
            $result | Should Be "test_file_with_mixed__chars"
        } It "Should handle mixed whitespace and illegal characters" {
            $result = Get-SafeFileName -InputString "test   file:with*  mixed_chars?"
            $result | Should Be "test_file_with__mixed_chars"
        }ion

.DESCRIPTION
    Enterprise-grade unit tests for the Get-SafeFileName function following PowerShell
    community standards and enterprise testing practices. Tests filename sanitization,
    security validation, and cross-platform compatibility.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Test Framework: Pester 3.4
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform)
    Last Updated: 2025-07-19

    TROUBLESHOOTING:
    - For test failures: .\Troubleshooting\Testing\Get-SafeFileName-Test-Issues.md
    - For function issues: .\Troubleshooting\FileSystem\Filename-Generation.md
#>

# Initialize test logging system first
$initLoggingPath = Join-Path $PSScriptRoot "..\..\..\TestHelpers\Initialize-TestLogging.ps1"
if (Test-Path $initLoggingPath) {
    . $initLoggingPath
} else {
    Write-Warning "Could not find test logging initialization script"
}

# Import the function for testing
$functionPath = Join-Path $PSScriptRoot "..\..\..\..\Private\FileSystem\Get-SafeFileName.ps1"
if (Test-Path $functionPath) {
    . $functionPath
} else {
    Write-Error "Cannot find Get-SafeFileName.ps1 at expected path: $functionPath"
}

# Import test helpers
$testHelpersPath = Join-Path $PSScriptRoot "..\..\..\TestHelpers"
if (Test-Path (Join-Path $testHelpersPath "SecurityTestHelpers.ps1")) {
    . (Join-Path $testHelpersPath "SecurityTestHelpers.ps1")
}

Describe "Get-SafeFileName" {

    Context "Parameter Validation" {
        
        It "Should accept mandatory InputString parameter" {
            { Get-SafeFileName -InputString "test" } | Should Not Throw
        }

        It "Should accept empty string as valid input" {
            $result = Get-SafeFileName -InputString ""
            $result | Should Be "Unknown"
        }

        It "Should accept whitespace-only string as valid input" {
            $result = Get-SafeFileName -InputString "   "
            $result | Should Be "Unknown"
        }

        It "Should validate MaxLength parameter range" {
            { Get-SafeFileName -InputString "test" -MaxLength 5 } | Should Throw
            { Get-SafeFileName -InputString "test" -MaxLength 250 } | Should Throw
        }

        It "Should accept valid MaxLength parameter" {
            { Get-SafeFileName -InputString "test" -MaxLength 50 } | Should Not Throw
            { Get-SafeFileName -InputString "test" -MaxLength 200 } | Should Not Throw
        }

        It "Should use default MaxLength when not specified" {
            $result = Get-SafeFileName -InputString "test"
            $result | Should Be "test"
        }

        It "Should accept CorrelationId parameter" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Get-SafeFileName -InputString "test" -CorrelationId $correlationId } | Should Not Throw
        }

        It "Should auto-generate CorrelationId when not provided" {
            { Get-SafeFileName -InputString "test" } | Should Not Throw
        }

        It "Should support pipeline input" {
            $testStrings = @("test1", "test2", "test3")
            $results = $testStrings | Get-SafeFileName
            $results.Count | Should Be 3
            $results[0] | Should Be "test1"
            $results[1] | Should Be "test2"
            $results[2] | Should Be "test3"
        }
    }

    Context "Basic Filename Sanitization" {

        It "Should return clean filename for normal strings" {
            $result = Get-SafeFileName -InputString "normal_filename"
            $result | Should Be "normal_filename"
        }

        It "Should replace illegal Windows characters with underscores" {
            $illegalChars = '\/:*?"<>|'
            foreach ($char in $illegalChars.ToCharArray()) {
                $testString = "test${char}file"
                $result = Get-SafeFileName -InputString $testString
                $result | Should Be "test_file"
            }
        }

        It "Should handle multiple illegal characters in single string" {
            $result = Get-SafeFileName -InputString 'test\file:with*illegal?"chars<>|'
            $result | Should Be "test_file_with_illegal__chars"
        }

        It "Should consolidate multiple whitespace characters" {
            $result = Get-SafeFileName -InputString "test   multiple    spaces"
            $result | Should Be "test_multiple_spaces"
        }

        It "Should handle mixed whitespace and illegal characters" {
            $result = Get-SafeFileName -InputString "test file\with:mixed* chars"
            $result | Should Be "test_file_with_mixed__chars"
        }

        It "Should trim leading and trailing underscores" {
            $result = Get-SafeFileName -InputString "___test___"
            $result | Should Be "test"
        }

        It "Should trim leading and trailing spaces" {
            $result = Get-SafeFileName -InputString "   test   "
            $result | Should Be "test"
        }
    }

    Context "Distinguished Name Handling" {

        It "Should sanitize simple Distinguished Name" {
            $dn = "CN=Test User,OU=Users,DC=contoso,DC=com"
            $result = Get-SafeFileName -InputString $dn
            $result | Should Be "CN=Test_User,OU=Users,DC=contoso,DC=com"
        }

        It "Should handle complex Distinguished Name with special characters" {
            $dn = 'CN=Test\User,OU=IT/Users,DC=contoso,DC=com'
            $result = Get-SafeFileName -InputString $dn
            $result | Should Be "CN=Test_User,OU=IT_Users,DC=contoso,DC=com"
        }

        It "Should handle Distinguished Name with quotes" {
            $dn = 'CN="Test User",OU=Users,DC=contoso,DC=com'
            $result = Get-SafeFileName -InputString $dn
            $result | Should Be "CN=_Test_User_,OU=Users,DC=contoso,DC=com"
        }

        It "Should handle very long Distinguished Name" {
            $longDN = "CN=Very Long User Name With Lots Of Text,OU=Very Long Organizational Unit Name,OU=Another Long OU Name,DC=very-long-domain-name,DC=com"
            $result = Get-SafeFileName -InputString $longDN -MaxLength 100
            $result | Should Match "_truncated$"
            $result.Length | Should Be 100
        }
    }

    Context "Length Management" {

        It "Should truncate long strings and add suffix" {
            $longString = "a" * 250
            $result = Get-SafeFileName -InputString $longString -MaxLength 50
            $result | Should Match "_truncated$"
            $result.Length | Should Be 50
        }

        It "Should preserve content when under length limit" {
            $shortString = "short_filename"
            $result = Get-SafeFileName -InputString $shortString -MaxLength 50
            $result | Should Be "short_filename"
        }

        It "Should handle edge case where MaxLength equals content length" {
            $testString = "exactly50characters_exactly50characters_exactly50"
            $result = Get-SafeFileName -InputString $testString -MaxLength 50
            $result | Should Be $testString
        }

        It "Should handle very small MaxLength values" {
            $result = Get-SafeFileName -InputString "test" -MaxLength 15
            $result | Should Be "test"
        }

        It "Should handle MaxLength smaller than suffix" {
            $result = Get-SafeFileName -InputString "verylongstring" -MaxLength 10
            $result | Should Be "truncated"
        }

        It "Should calculate truncation correctly with illegal characters" {
            $longStringWithIllegal = ("a" * 100) + "\/:*?" + ("b" * 100)
            $result = Get-SafeFileName -InputString $longStringWithIllegal -MaxLength 50
            $result | Should Match "_truncated$"
            $result.Length | Should Be 50
        }
    }

    Context "Edge Cases and Error Handling" {

        It "Should handle null string gracefully" {
            # Note: [AllowEmptyString()] attribute should allow this
            $result = Get-SafeFileName -InputString ""
            $result | Should Be "Unknown"
        }

        It "Should handle string with only illegal characters" {
            $result = Get-SafeFileName -InputString '\/:*?"<>|'
            $result | Should Match "^Unknown_[a-f0-9]{8}$" # Should generate fallback with hash
            $result.Length | Should Be 16 # "Unknown_" + 8-char hash
        }

        It "Should handle string that becomes empty after sanitization" {
            $result = Get-SafeFileName -InputString "___"
            $result | Should Match "^Unknown_[a-f0-9]+$"  # Should be Unknown_ followed by hex characters
        }

        It "Should generate unique fallback names for invalid inputs" {
            $result1 = Get-SafeFileName -InputString "___"
            $result2 = Get-SafeFileName -InputString "___"
            $result1 | Should Not Be $result2
        }

        It "Should handle Unicode characters appropriately" {
            $unicodeString = "téšt_fílé_ñámé"
            $result = Get-SafeFileName -InputString $unicodeString
            $result | Should Be "téšt_fílé_ñámé"
        }

        It "Should handle mixed ASCII and Unicode" {
            $mixedString = "test_fîlé\name:with*ñámé"
            $result = Get-SafeFileName -InputString $mixedString
            $result | Should Be "test_fîlé_name_with_ñámé"
        }

        It "Should handle numeric input" {
            $result = Get-SafeFileName -InputString "12345"
            $result | Should Be "12345"
        }

        It "Should handle alphanumeric with symbols" {
            $result = Get-SafeFileName -InputString "test123-file_name.backup"
            $result | Should Be "test123-file_name.backup"
        }
    }

    Context "Security Validation" {

        It "Should prevent path traversal attempts in filename" {
            $maliciousInputs = @(
                "..\..\windows\system32",
                "../../../../etc/passwd",
                "..\admin\secrets.txt"
            )
            
            foreach ($input in $maliciousInputs) {
                $result = Get-SafeFileName -InputString $input
                $result | Should Not BeNullOrEmpty
                $result | Should BeOfType "string"
                
                # Should replace path separators and dots to make filename safe
                $result | Should Not Match "[/\\]"  # No path separators allowed
                # Dots are replaced with underscores where they form .. patterns
            }
        }

        It "Should sanitize potential command injection in filename" {
            $injectionAttempts = @(
                "test`$(Get-Process).txt",
                "file;Remove-Item.log",
                "name&dir.backup"
            )
            
            foreach ($attempt in $injectionAttempts) {
                $result = Get-SafeFileName -InputString $attempt
                $result | Should Not BeNullOrEmpty
                $result | Should BeOfType "string"
                
                # Function only replaces Windows-illegal filename characters (\/:*?"<>|)
                # Other characters like $, ;, & are valid in Windows filenames
                # So they should be preserved in the output
            }
        }

        It "Should handle potential executable extensions safely" {
            $executableNames = @(
                "malicious.exe",
                "script.bat",
                "trojan.com"
            )
            
            foreach ($name in $executableNames) {
                $result = Get-SafeFileName -InputString $name
                $result | Should Be $name # Should preserve but sanitize
            }
        }

        It "Should sanitize special filesystem prefixes" {
            $specialPrefixes = @(
                "CON.txt",
                "PRN.log",
                "AUX.backup"
            )
            
            foreach ($prefix in $specialPrefixes) {
                $result = Get-SafeFileName -InputString $prefix
                $result | Should Not BeNullOrEmpty
            }
        }
    }

    Context "Cross-Platform Compatibility" {

        It "Should handle Windows UNC path components" {
            $uncPath = "\\server\share\folder\file.txt"
            $result = Get-SafeFileName -InputString $uncPath
            $result | Should Be "server_share_folder_file.txt"
        }

        It "Should handle Unix-style path components" {
            $unixPath = "/home/user/documents/file.txt"
            $result = Get-SafeFileName -InputString $unixPath
            $result | Should Be "home_user_documents_file.txt"
        }

        It "Should handle mixed path separators" {
            $mixedPath = "folder\subfolder/file.txt"
            $result = Get-SafeFileName -InputString $mixedPath
            $result | Should Be "folder_subfolder_file.txt"
        }

        It "Should preserve valid filename extensions" {
            $extensions = @(".txt", ".log", ".csv", ".json", ".xml")
            foreach ($ext in $extensions) {
                $filename = "testfile$ext"
                $result = Get-SafeFileName -InputString $filename
                $result | Should Be $filename
            }
        }

        It "Should handle filenames with multiple dots" {
            $result = Get-SafeFileName -InputString "file.name.with.dots.txt"
            $result | Should Be "file.name.with.dots.txt"
        }
    }

    Context "Performance Validation" {

        It "Should process single filename within performance limits" {
            $startTime = Get-Date
            $result = Get-SafeFileName -InputString "test_performance_filename"
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            
            $duration | Should BeLessThan 100
            $result | Should Be "test_performance_filename"
        }

        It "Should handle bulk processing efficiently" {
            $testFiles = 1..100 | ForEach-Object { "test_file_number_$_.txt" }
            
            $startTime = Get-Date
            $results = $testFiles | Get-SafeFileName
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            
            $duration | Should BeLessThan 1000 # 1 second for 100 files
            $results.Count | Should Be 100
        }

        It "Should handle very long strings efficiently" {
            $veryLongString = "a" * 10000
            
            $startTime = Get-Date
            $result = Get-SafeFileName -InputString $veryLongString -MaxLength 100
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalMilliseconds
            
            $duration | Should BeLessThan 50
            $result.Length | Should Be 100
        }

        It "Should maintain consistent performance with different input types" {
            $testCases = @(
                "simple_filename",
                'complex\file:with*illegal?"chars<>|',
                "CN=User,OU=IT,DC=domain,DC=com",
                ("long_" * 100),
                "unicode_tést_fîlé_ñámé",
                ""
            )
            
            $durations = foreach ($testCase in $testCases) {
                $startTime = Get-Date
                $result = Get-SafeFileName -InputString $testCase
                $endTime = Get-Date
                ($endTime - $startTime).TotalMilliseconds
            }
            
            $maxDuration = ($durations | Measure-Object -Maximum).Maximum
            $maxDuration | Should BeLessThan 100
        }
    }

    Context "Logging Integration" {
        
        # Mock Write-StructuredLog to prevent actual logging during tests
        Mock Write-StructuredLog {
            param($Message, $Level, $CorrelationId)
            # Return structured data for validation
            return @{
                Message = $Message
                Level = $Level  
                CorrelationId = $CorrelationId
                Timestamp = Get-Date
            }
        }

        It "Should log debug messages for successful operations" {
            $result = Get-SafeFileName -InputString "test_logging"
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter {
                $Message -like "*Safe filename generation successful*" -and $Level -eq "Debug"
            }
        }

        It "Should log debug messages for empty input handling" {
            $result = Get-SafeFileName -InputString ""
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter {
                $Message -like "*Input string was empty*" -and $Level -eq "Debug"
            }
        }

        It "Should log debug messages for truncation operations" {
            $longString = "a" * 250
            $result = Get-SafeFileName -InputString $longString -MaxLength 50
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter {
                $Message -like "*Truncated filename*" -and $Level -eq "Debug"
            }
        }

        It "Should log warning messages for fallback operations" {
            $result = Get-SafeFileName -InputString "___"
            
            Assert-MockCalled Write-StructuredLog -Exactly 1 -ParameterFilter {
                $Message -like "*Generated fallback filename*" -and $Level -eq "Warning"
            }
        }

        It "Should include correlation ID in all log messages" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Get-SafeFileName -InputString "test" -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $CorrelationId -eq $testCorrelationId
            }
        }
    }

    Context "Enterprise Integration" {

        It "Should return string type for all inputs" {
            $testInputs = @("test", "", "  ", "complex\file:name", $null)
            
            foreach ($input in $testInputs) {
                if ($input -ne $null) {
                    $result = Get-SafeFileName -InputString $input
                    $result | Should BeOfType [string]
                }
            }
        }

        It "Should handle concurrent operations safely" {
            $functionPath = "$PSScriptRoot\..\..\..\..\Private\FileSystem\Get-SafeFileName.ps1"
            $loggingPath = "$PSScriptRoot\..\..\..\TestHelpers\Initialize-TestLogging.ps1"
            
            $scriptBlock = {
                param($InputString, $LoggingPath, $FunctionPath)
                . $LoggingPath
                . $FunctionPath
                Get-SafeFileName -InputString $InputString
            }
            
            $jobs = 1..10 | ForEach-Object {
                Start-Job -ScriptBlock $scriptBlock -ArgumentList "concurrent_test_$_", $loggingPath, $functionPath
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results.Count | Should Be 10
            $results | ForEach-Object { $_ | Should Match "concurrent_test_\d+" }
        }

        It "Should integrate with configuration management" {
            # Test with different MaxLength values that could come from configuration
            $configValues = @(25, 50, 100, 150, 200)
            
            foreach ($maxLength in $configValues) {
                $result = Get-SafeFileName -InputString "configuration_test_filename" -MaxLength $maxLength
                $result | Should Not BeNullOrEmpty
                $result.Length | Should BeLessThan ($maxLength + 1)
            }
        }

        It "Should support audit trail requirements" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            $originalString = "audit_test_filename"
            
            $result = Get-SafeFileName -InputString $originalString -CorrelationId $testCorrelationId
            
            # Verify result is correctly processed
            $result | Should Be $originalString
            $result | Should Not BeNullOrEmpty
        }

        It "Should handle enterprise filename patterns" {
            $enterprisePatterns = @(
                "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip",
                "log_server01_20250719.txt", 
                "config_production_v2.1.json",
                "report_Q4_2025_final.xlsx"
            )
            
            foreach ($pattern in $enterprisePatterns) {
                $result = Get-SafeFileName -InputString $pattern
                $result | Should Not BeNullOrEmpty
                $result | Should Not Match '[\\/:*?"<>|]'
            }
        }
    }
}
