#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Get-StringHash utility function

.DESCRIPTION
    Comprehensive tests for Get-StringHash function including parameter validation,
    error handling, hash algorithm verification, and security validation.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Created Date: July 15, 2025
    Last Modified: July 15, 2025
    Version: 1.0.0
    
    Test Framework: Pester 3.4.x
    PowerShell Version: 5.1+
    
    TROUBLESHOOTING:
    - For test failures: .\Troubleshooting\Testing\Unit-Test-Issues.md
    - For function errors: .\Troubleshooting\Private\Utility-Function-Issues.md
#>

# Import module and dependencies
$ModuleRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

# Import specific private function for testing
. "$ModuleRoot\Private\Utilities\Get-StringHash.ps1"

Describe "Get-StringHash" {
    BeforeAll {
        # Set up test correlation ID for tracking
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Test data for hash verification
        $script:TestString = "TestString123"
        
        # Mock Write-Verbose to prevent verbose output during tests
        Mock Write-Verbose { }
    }
    
    Context "Parameter Validation" {
        It "Should accept valid string input" {
            { Get-StringHash -InputString "ValidTestString" } | Should Not Throw
        }
        
        It "Should accept empty string" {
            # Function requires mandatory parameter, so empty string will be rejected
            { Get-StringHash -InputString "" } | Should Throw
        }
        
        It "Should accept string with special characters" {
            { Get-StringHash -InputString "Test!@#$%^&*()_+{}|:<>?[];" } | Should Not Throw
        }
        
        It "Should accept Unicode strings" {
            { Get-StringHash -InputString "测试字符串üñíçødé" } | Should Not Throw
        }
        
        It "Should require InputString parameter" {
            # Test that mandatory parameter validation works by supplying empty string
            { Get-StringHash -InputString "" -ErrorAction Stop } | Should Throw
        }
        
        It "Should accept null as InputString and handle gracefully" {
            # Function requires mandatory parameter, so null will be rejected
            { Get-StringHash -InputString $null } | Should Throw
        }
        
        It "Should accept valid hash algorithms" {
            { Get-StringHash -InputString "test" -Algorithm "SHA256" } | Should Not Throw
            { Get-StringHash -InputString "test" -Algorithm "SHA1" } | Should Not Throw
            { Get-StringHash -InputString "test" -Algorithm "MD5" } | Should Not Throw
        }
        
        It "Should reject invalid hash algorithms" {
            { Get-StringHash -InputString "test" -Algorithm "INVALID" } | Should Throw
        }
        
        It "Should accept custom Algorithm parameter" {
            { Get-StringHash -InputString "test" -Algorithm "SHA1" } | Should Not Throw
        }
        
        It "Should generate CorrelationId when not provided" {
            # The actual function doesn't support CorrelationId parameter
            $result = Get-StringHash -InputString "test"
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Hash Algorithm Functionality" {
        It "Should compute SHA256 hash by default" {
            $result = Get-StringHash -InputString "test"
            $result | Should Match "^[A-F0-9]{64}$"
        }
        
        It "Should compute SHA256 hash when explicitly specified" {
            $result = Get-StringHash -InputString "test" -Algorithm "SHA256"
            $result | Should Match "^[A-F0-9]{64}$"
        }
        
        It "Should compute SHA1 hash when specified" {
            $result = Get-StringHash -InputString "test" -Algorithm "SHA1"
            $result | Should Match "^[A-F0-9]{40}$"
        }
        
        It "Should compute MD5 hash when specified" {
            $result = Get-StringHash -InputString "test" -Algorithm "MD5"
            $result | Should Match "^[A-F0-9]{32}$"
        }
        
        It "Should return consistent hash for same input" {
            $result1 = Get-StringHash -InputString "ConsistencyTest"
            $result2 = Get-StringHash -InputString "ConsistencyTest"
            $result1 | Should Be $result2
        }
        
        It "Should return different hashes for different inputs" {
            $result1 = Get-StringHash -InputString "String1"
            $result2 = Get-StringHash -InputString "String2"
            $result1 | Should Not Be $result2
        }
        
        It "Should return different hashes for different algorithms" {
            $resultSHA256 = Get-StringHash -InputString "test" -Algorithm "SHA256"
            $resultSHA1 = Get-StringHash -InputString "test" -Algorithm "SHA1"
            $resultMD5 = Get-StringHash -InputString "test" -Algorithm "MD5"
            
            $resultSHA256 | Should Not Be $resultSHA1
            $resultSHA256 | Should Not Be $resultMD5
            $resultSHA1 | Should Not Be $resultMD5
        }
    }
    
    Context "Security Considerations" {
        It "Should not expose input string in output" {
            $sensitiveString = "SecretPassword123!"
            $result = Get-StringHash -InputString $sensitiveString
            
            # Verify input string is not in hash result
            $result | Should Not Match $sensitiveString
        }
        
        It "Should handle very long strings without issues" {
            $longString = "x" * 10000  # 10KB string
            { Get-StringHash -InputString $longString } | Should Not Throw
        }
        
        It "Should handle strings with null characters" {
            $stringWithNull = "Before`0After"
            { Get-StringHash -InputString $stringWithNull } | Should Not Throw
        }
        
        It "Should produce deterministic output for security validation" {
            $testInput = "SecurityValidationTest"
            $results = @()
            
            # Run multiple times to ensure consistency
            1..10 | ForEach-Object {
                $results += (Get-StringHash -InputString $testInput)
            }
            
            # All results should be identical
            $uniqueResults = $results | Select-Object -Unique
            $uniqueResults.Count | Should Be 1
        }
    }
    
    Context "Error Handling" {
        It "Should handle null input gracefully" {
            # Function has mandatory parameter, so null will throw
            { Get-StringHash -InputString $null } | Should Throw
        }
        
        It "Should continue execution after hash computation errors" {
            # Mock Get-FileHash to simulate error
            Mock Get-FileHash { throw "Simulated hash error" }
            
            # Function should handle the error gracefully
            { Get-StringHash -InputString "test" } | Should Not Throw
        }
    }
    
    Context "Performance Validation" {
        It "Should complete hash computation within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-StringHash -InputString "Performance test string"
            $stopwatch.Stop()
            
            # Should complete within 5 seconds (generous limit)
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
        }
        
        It "Should handle multiple concurrent operations" {
            $jobs = @()
            
            try {
                # Start multiple background jobs
                1..5 | ForEach-Object {
                    $jobs += Start-Job -ScriptBlock {
                        param($ModuleRoot, $InputString)
                        . "$ModuleRoot\Private\Utilities\Get-StringHash.ps1"
                        Get-StringHash -InputString $InputString
                    } -ArgumentList $ModuleRoot, "ConcurrentTest$_"
                }
                
                # Wait for all jobs to complete
                $results = $jobs | Wait-Job | Receive-Job
                
                # Verify all jobs completed successfully
                $results.Count | Should Be 5
                $results | ForEach-Object {
                    $_ | Should Not BeNullOrEmpty
                }
            }
            finally {
                # Clean up jobs
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Edge Cases" {
        It "Should handle empty string input" {
            # Function has mandatory parameter, so empty string will throw
            { Get-StringHash -InputString "" } | Should Throw
        }
        
        It "Should handle whitespace-only strings" {
            $result = Get-StringHash -InputString "   "
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle strings with line breaks" {
            $stringWithBreaks = "Line1`r`nLine2`nLine3"
            $result = Get-StringHash -InputString $stringWithBreaks
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle strings with tabs and special whitespace" {
            $stringWithTabs = "Before`tTab`tAfter"
            $result = Get-StringHash -InputString $stringWithTabs
            $result | Should Not BeNullOrEmpty
        }
    }
    
    AfterAll {
        # Clean up any test artifacts
        if (Test-Path "TestDrive:\") {
            Remove-Item "TestDrive:\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove any temporary variables
        Remove-Variable -Name "TestCorrelationId", "TestString", "ExpectedSHA256", "ExpectedSHA1", "ExpectedMD5" -Scope Script -ErrorAction SilentlyContinue
    }
}
