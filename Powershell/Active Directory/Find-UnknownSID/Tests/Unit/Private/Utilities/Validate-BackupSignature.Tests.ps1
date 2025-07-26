#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Validate-BackupSignature utility function

.DESCRIPTION
    Comprehensive tests for Validate-BackupSignature function including parameter validation,
    signature verification, security validation, and error handling.

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
    - For signature issues: .\Troubleshooting\Security\Signature-Validation-Issues.md
    - For security errors: .\Troubleshooting\Security\Backup-Security-Issues.md
#>

# Import module and dependencies
$ModuleRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName

# Import specific private function for testing
. "$ModuleRoot\Private\Utilities\Validate-BackupSignature.ps1"

Describe "Validate-BackupSignature" {
    BeforeAll {
        # Set up test correlation ID for tracking
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        
        # Define valid signatures for testing
        $script:ValidSignatures = @(
            "PSSecurityBackup_v2.1",
            "PSSecurityBackup_v2.0",
            "PowerShellSecurityBackup"
        )
        
        # Define invalid signatures for testing
        $script:InvalidSignatures = @(
            "InvalidSignature",
            "PSSecurityBackup_v1.0",
            "MaliciousBackup_v1.0",
            "UnknownBackupFormat",
            "   ",
            "PSSecurityBackup_v3.0",  # Future version not yet valid
            "BadSignature"
        )
        
        # Mock Write-Verbose to prevent verbose output during tests
        Mock Write-Verbose { }
        Mock Write-Warning { }
    }
    
    Context "Parameter Validation" {
        It "Should require Signature parameter" {
            # Use timeout approach since PowerShell prompts for mandatory parameters
            $job = Start-Job -ScriptBlock {
                $ModuleRoot = $args[0]
                . "$ModuleRoot\Private\Utilities\Validate-BackupSignature.ps1"
                Validate-BackupSignature
            } -ArgumentList $ModuleRoot
            
            # Wait briefly then check if job is waiting for input
            Start-Sleep -Seconds 1
            $job.State | Should Be "Blocked"  # Should be waiting for parameter input
            
            # Clean up
            $job | Stop-Job | Remove-Job
        }
        
        It "Should accept valid signature string" {
            { Validate-BackupSignature -Signature "PSSecurityBackup_v2.1" } | Should Not Throw
        }
        
        It "Should reject empty signature string via parameter validation" {
            # Function rejects empty strings via parameter validation
            { Validate-BackupSignature -Signature "" } | Should Throw "Cannot bind argument to parameter 'Signature' because it is an empty string"
        }
        
        It "Should reject null signature via parameter validation" {
            # Function rejects null via parameter validation
            { Validate-BackupSignature -Signature $null } | Should Throw "Cannot bind argument to parameter 'Signature' because it is an empty string"
        }
        
        It "Should accept whitespace-only signature" {
            { Validate-BackupSignature -Signature "   " } | Should Not Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            { Validate-BackupSignature -Signature "PSSecurityBackup_v2.1" -CorrelationId $customCorrelationId } | Should Not Throw
        }
        
        It "Should generate CorrelationId when not provided" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }
        
        It "Should accept very long signature strings" {
            $longSignature = "A" * 1000
            { Validate-BackupSignature -Signature $longSignature } | Should Not Throw
        }
        
        It "Should accept signature with special characters" {
            $specialSignature = "Test!@#$%^&*()_+{}|:<>?[];"
            { Validate-BackupSignature -Signature $specialSignature } | Should Not Throw
        }
    }
    
    Context "Valid Signature Recognition" {
        It "Should validate PSSecurityBackup_v2.1 signature" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result.Valid | Should Be $true
            $result.SecurityRisk | Should Be $false
        }
        
        It "Should validate PSSecurityBackup_v2.0 signature" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.0"
            $result.Valid | Should Be $true
            $result.SecurityRisk | Should Be $false
        }
        
        It "Should validate PowerShellSecurityBackup signature" {
            $result = Validate-BackupSignature -Signature "PowerShellSecurityBackup"
            $result.Valid | Should Be $true
            $result.SecurityRisk | Should Be $false
        }
        
        It "Should validate all known valid signatures" {
            foreach ($signature in $script:ValidSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.Valid | Should Be $true
                $result.SecurityRisk | Should Be $false
            }
        }
        
        It "Should be case insensitive for signatures" {
            # PowerShell -contains is case-insensitive by default
            $result = Validate-BackupSignature -Signature "psSecurityBackup_v2.1"
            $result.Valid | Should Be $true
            $result.SecurityRisk | Should Be $false
        }
        
        It "Should not accept signatures with extra whitespace" {
            $result = Validate-BackupSignature -Signature " PSSecurityBackup_v2.1 "
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
    }
    
    Context "Invalid Signature Detection" {
        It "Should reject empty signature via parameter validation" {
            { Validate-BackupSignature -Signature "" } | Should Throw "Cannot bind argument to parameter 'Signature' because it is an empty string"
        }
        
        It "Should reject null signature via parameter validation" {
            { Validate-BackupSignature -Signature $null } | Should Throw "Cannot bind argument to parameter 'Signature' because it is an empty string"
        }
        
        It "Should reject whitespace-only signature" {
            $result = Validate-BackupSignature -Signature "   "
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should reject unknown signature formats" {
            foreach ($signature in $script:InvalidSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.Valid | Should Be $false
                $result.SecurityRisk | Should Be $true
            }
        }
        
        It "Should reject potentially malicious signatures" {
            $maliciousSignatures = @(
                "MaliciousBackup_v1.0",
                "EvilBackup",
                "HackerBackup_v2.1",
                "PSSecurityBackup_v999.0"
            )
            
            foreach ($signature in $maliciousSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.Valid | Should Be $false
                $result.SecurityRisk | Should Be $true
            }
        }
        
        It "Should reject signature with SQL injection attempts" {
            $sqlInjectionSignature = "PSSecurityBackup'; DROP TABLE Backups; --"
            $result = Validate-BackupSignature -Signature $sqlInjectionSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should reject signature with script injection attempts" {
            $scriptInjectionSignature = "PSSecurityBackup`$(Get-Process)"
            $result = Validate-BackupSignature -Signature $scriptInjectionSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should reject signature with path traversal attempts" {
            $pathTraversalSignature = "PSSecurityBackup../../etc/passwd"
            $result = Validate-BackupSignature -Signature $pathTraversalSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
    }
    
    Context "Return Object Structure" {
        It "Should return PSCustomObject with required properties" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            
            $result | Should BeOfType [PSCustomObject]
            $result.Valid | Should Not BeNullOrEmpty
            $result.SecurityRisk | Should Not BeNullOrEmpty  
            $result.CorrelationId | Should Not BeNullOrEmpty
        }
        
        It "Should return boolean for Valid property" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result.Valid | Should BeOfType [bool]
        }
        
        It "Should return boolean for SecurityRisk property" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result.SecurityRisk | Should BeOfType [bool]
        }
        
        It "Should preserve custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1" -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should generate unique CorrelationId for each call" {
            $result1 = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result2 = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            
            $result1.CorrelationId | Should Not Be $result2.CorrelationId
        }
    }
    
    Context "Security Risk Assessment" {
        It "Should not flag security risk for valid signatures" {
            foreach ($signature in $script:ValidSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.SecurityRisk | Should Be $false
            }
        }
        
        It "Should flag security risk for invalid signatures" {
            foreach ($signature in $script:InvalidSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.SecurityRisk | Should Be $true
            }
        }
        
        It "Should have inverse relationship between Valid and SecurityRisk" {
            $testSignatures = $script:ValidSignatures + $script:InvalidSignatures
            
            foreach ($signature in $testSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                
                if ($result.Valid -eq $true) {
                    $result.SecurityRisk | Should Be $false
                } else {
                    $result.SecurityRisk | Should Be $true
                }
            }
        }
        
        It "Should flag security risk for potentially dangerous patterns" {
            $dangerousPatterns = @(
                "PSSecurityBackup_v2.1; rm -rf /",
                "PSSecurityBackup_v2.1 && format c:",
                "PSSecurityBackup_v2.1 | cmd.exe",
                "PSSecurityBackup_v2.1`nGet-Process"
            )
            
            foreach ($pattern in $dangerousPatterns) {
                $result = Validate-BackupSignature -Signature $pattern
                $result.Valid | Should Be $false
                $result.SecurityRisk | Should Be $true
            }
        }
    }
    
    Context "Edge Cases and Boundary Conditions" {
        It "Should handle signature exactly matching valid signature" {
            $exactSignature = "PSSecurityBackup_v2.1"
            $result = Validate-BackupSignature -Signature $exactSignature
            $result.Valid | Should Be $true
        }
        
        It "Should handle signature with Unicode characters" {
            $unicodeSignature = "PSSecurityBackup_v2.1üñíçødé"
            $result = Validate-BackupSignature -Signature $unicodeSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should handle signature with control characters" {
            $controlCharSignature = "PSSecurityBackup_v2.1`t`r`n"
            $result = Validate-BackupSignature -Signature $controlCharSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should handle very long invalid signatures" {
            $longInvalidSignature = "InvalidSignature" + ("X" * 10000)
            $result = Validate-BackupSignature -Signature $longInvalidSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
        
        It "Should handle signature containing null characters" {
            # PowerShell treats null characters as string terminators, so this effectively becomes "PSSecurityBackup_v2.1"
            $nullCharSignature = "PSSecurityBackup`0_v2.1"
            $result = Validate-BackupSignature -Signature $nullCharSignature
            $result.Valid | Should Be $true  # Null char causes string truncation, resulting in valid signature
            $result.SecurityRisk | Should Be $false
        }
        
        It "Should handle signature with embedded quotes" {
            $quotedSignature = 'PSSecurityBackup"_v2.1'
            $result = Validate-BackupSignature -Signature $quotedSignature
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
        }
    }
    
    Context "Performance and Reliability" {
        It "Should complete validation quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $stopwatch.Stop()
            
            # Should complete within 1 second
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should handle multiple rapid calls efficiently" {
            $results = @()
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            1..100 | ForEach-Object {
                $results += Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            }
            
            $stopwatch.Stop()
            
            # 100 calls should complete within 5 seconds
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $results.Count | Should Be 100
            $results | ForEach-Object { $_.Valid | Should Be $true }
        }
        
        It "Should handle concurrent validation calls" {
            $jobs = @()
            
            try {
                # Start multiple background jobs
                1..10 | ForEach-Object {
                    $jobs += Start-Job -ScriptBlock {
                        param($ModuleRoot, $Signature)
                        . "$ModuleRoot\Private\Utilities\Validate-BackupSignature.ps1"
                        Validate-BackupSignature -Signature $Signature
                    } -ArgumentList $ModuleRoot, "PSSecurityBackup_v2.1"
                }
                
                # Wait for all jobs to complete
                $results = $jobs | Wait-Job | Receive-Job
                
                # Verify all jobs completed successfully
                $results.Count | Should Be 10
                $results | ForEach-Object {
                    $_.Valid | Should Be $true
                    $_.SecurityRisk | Should Be $false
                }
            }
            finally {
                # Clean up jobs
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should be consistent across multiple calls" {
            $signature = "PSSecurityBackup_v2.1"
            $results = @()
            
            # Run same validation multiple times
            1..50 | ForEach-Object {
                $results += Validate-BackupSignature -Signature $signature
            }
            
            # All results should be identical (except CorrelationId)
            $validResults = $results | Where-Object { $_.Valid -eq $true }
            $securityRiskResults = $results | Where-Object { $_.SecurityRisk -eq $false }
            
            $validResults.Count | Should Be 50
            $securityRiskResults.Count | Should Be 50
        }
    }
    
    Context "Error Handling" {
        It "Should handle signature validation without throwing exceptions for valid input types" {
            $problemSignatures = @(
                123,  # Non-string type (will be converted to string)
                "ValidSignature"
            )
            
            foreach ($signature in $problemSignatures) {
                { Validate-BackupSignature -Signature $signature } | Should Not Throw
            }
        }
        
        It "Should gracefully handle type conversion issues" {
            # Test with various types that need string conversion
            $result1 = Validate-BackupSignature -Signature 123
            $result2 = Validate-BackupSignature -Signature $true
            $result3 = Validate-BackupSignature -Signature (Get-Date)
            
            $result1.Valid | Should Be $false
            $result2.Valid | Should Be $false
            $result3.Valid | Should Be $false
        }
    }
    
    Context "Integration and Correlation" {
        It "Should maintain correlation ID throughout validation process" {
            $testCorrelationId = "TEST-CORRELATION-ID-12345"
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1" -CorrelationId $testCorrelationId
            $result.CorrelationId | Should Be $testCorrelationId
        }
        
        It "Should work with Get-StringHash correlation pattern" {
            # Test that correlation ID format is compatible with other utilities
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            
            # Should be valid GUID format
            { [System.Guid]::Parse($result.CorrelationId) } | Should Not Throw
        }
        
        It "Should support logging integration scenarios" {
            $result = Validate-BackupSignature -Signature "InvalidSignature"
            
            # Result should contain all necessary information for logging
            $result.Valid | Should Be $false
            $result.SecurityRisk | Should Be $true
            $result.CorrelationId | Should Not BeNullOrEmpty
        }
    }
    
    Context "Signature Format Specifications" {
        It "Should accept PSSecurityBackup_v2.1 as current version" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.1"
            $result.Valid | Should Be $true
        }
        
        It "Should accept PSSecurityBackup_v2.0 as legacy version" {
            $result = Validate-BackupSignature -Signature "PSSecurityBackup_v2.0"
            $result.Valid | Should Be $true
        }
        
        It "Should accept PowerShellSecurityBackup as generic version" {
            $result = Validate-BackupSignature -Signature "PowerShellSecurityBackup"
            $result.Valid | Should Be $true
        }
        
        It "Should reject version numbers not in whitelist" {
            $invalidVersions = @(
                "PSSecurityBackup_v1.9",
                "PSSecurityBackup_v2.2",
                "PSSecurityBackup_v3.0",
                "PSSecurityBackup_v10.0"
            )
            
            foreach ($version in $invalidVersions) {
                $result = Validate-BackupSignature -Signature $version
                $result.Valid | Should Be $false
                $result.SecurityRisk | Should Be $true
            }
        }
        
        It "Should reject signatures with similar but incorrect naming" {
            $similarSignatures = @(
                "PSSecurityBackups_v2.1",  # Plural
                "PSSecurityBackup v2.1",   # Space instead of underscore
                "PS-SecurityBackup_v2.1",  # Hyphen
                "PSSecurityBackup_2.1"     # Missing 'v'
                # Note: PSSecurityBackup_V2.1 is valid due to case-insensitive matching
            )
            
            foreach ($signature in $similarSignatures) {
                $result = Validate-BackupSignature -Signature $signature
                $result.Valid | Should Be $false
                $result.SecurityRisk | Should Be $true
            }
        }
    }
    
    AfterAll {
        # Clean up any test artifacts
        if (Test-Path "TestDrive:\") {
            Remove-Item "TestDrive:\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove any temporary variables
        Remove-Variable -Name "TestCorrelationId", "ValidSignatures", "InvalidSignatures" -Scope Script -ErrorAction SilentlyContinue
    }
}
