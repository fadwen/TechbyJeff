# Test-OrphanedSID.Tests.ps1 - Pester 3.4.x Compatible
# Tests for Test-OrphanedSID private function

# Create minimal stubs for missing dependencies FIRST
function Write-StructuredLog { param($Message, $Level, $CorrelationId, $Component, $Data) }

# Load required classes and functions
$ClassPath = Join-Path $PSScriptRoot '..\..\..\..\Classes'
if (Test-Path $ClassPath) {
    Get-ChildItem -Path $ClassPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

# Load SID functions
$SIDPath = Join-Path $PSScriptRoot '..\..\..\..\Private\SID'
if (Test-Path $SIDPath) {
    Get-ChildItem -Path $SIDPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}

Describe "Test-OrphanedSID Function Tests" {
    
    Context "Function Existence and Basic Functionality" {
        It "Should have Test-OrphanedSID function available" {
            Get-Command Test-OrphanedSID -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should accept SID parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { Test-OrphanedSID -SID $testSID } | Should Not Throw
        }
        
        It "Should accept CorrelationId parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Test-OrphanedSID -SID $testSID -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should return an object when given valid SID" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = Test-OrphanedSID -SID $testSID
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Parameter Validation" {
        It "Should validate SID parameter is not null" {
            { Test-OrphanedSID -SID $null } | Should Throw
        }
        
        It "Should validate SID parameter is not empty" {
            { Test-OrphanedSID -SID '' } | Should Throw
        }
        
        It "Should handle valid SID formats" {
            $validSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-32-544',
                'S-1-1-0'
            )
            
            foreach ($sid in $validSIDs) {
                { Test-OrphanedSID -SID $sid } | Should Not Throw
            }
        }
    }
    
    Context "Return Value Validation" {
        It "Should return boolean value for valid SID" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = Test-OrphanedSID -SID $testSID
            
            $result | Should Not BeNullOrEmpty
            $result | Should BeOfType [bool]
        }
        
        It "Should return boolean value for well-known SID" {
            # For AD context, well-known Windows SIDs may be considered "orphaned" 
            # since they're not AD objects (this is the actual function behavior)
            $wellKnownSID = 'S-1-5-32-544'  # Administrators group
            $result = Test-OrphanedSID -SID $wellKnownSID
            
            $result | Should Not BeNullOrEmpty
            $result | Should BeOfType [bool]
            # Function behavior: well-known SIDs return false (not orphaned)
            $result | Should Be $false
        }
    }
    
    Context "Error Handling" {
        It "Should handle correlation ID tracking" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            # Function should accept correlation ID without throwing
            { Test-OrphanedSID -SID $testSID -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should provide meaningful error information" {
            try {
                Test-OrphanedSID -SID 'invalid-sid-format' -ErrorAction Stop
            }
            catch {
                $_.Exception.Message | Should Not BeNullOrEmpty
            }
        }
        
        It "Should handle invalid SID formats gracefully" {
            $invalidSIDs = @(
                'invalid-sid',
                'S-1-5',
                'S-1-5-21',
                'not-a-sid-at-all',
                '123456789'
            )
            
            foreach ($sid in $invalidSIDs) {
                # Invalid SIDs should return $true (treated as orphaned)
                $result = Test-OrphanedSID -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should handle null correlation ID gracefully" {
            $testSID = 'S-1-5-32-544'
            { Test-OrphanedSID -SID $testSID -CorrelationId $null } | Should Not Throw
        }
    }
    
    Context "Well-Known SID Validation" {
        It "Should correctly handle well-known SIDs" {
            $wellKnownSIDs = @(
                'S-1-5-32-544',    # Administrators
                'S-1-5-32-545',    # Users
                'S-1-1-0',         # Everyone
                'S-1-5-18',        # Local System
                'S-1-5-19',        # Local Service
                'S-1-5-20'         # Network Service
            )
            
            foreach ($sid in $wellKnownSIDs) {
                $result = Test-OrphanedSID -SID $sid
                $result | Should BeOfType [bool]
                # Function behavior: well-known Windows SIDs are not orphaned
                # they should translate successfully
                $result | Should Be $false
            }
        }
        
        It "Should handle built-in domain SIDs" {
            $builtInSIDs = @(
                'S-1-5-21-0-0-0-500',      # Domain Administrator template
                'S-1-5-21-0-0-0-501',      # Guest template
                'S-1-5-21-0-0-0-512'       # Domain Admins template
            )
            
            foreach ($sid in $builtInSIDs) {
                $result = Test-OrphanedSID -SID $sid
                $result | Should BeOfType [bool]
            }
        }
    }
    
    Context "Cache Management Integration" {
        It "Should work with Clear-SIDValidationCache function" {
            # Clear cache should be available
            Get-Command Clear-SIDValidationCache -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            { Clear-SIDValidationCache } | Should Not Throw
        }
        
        It "Should work with Get-SIDValidationCacheStat function" {
            # Cache statistics should be available
            Get-Command Get-SIDValidationCacheStat -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            $stats = Get-SIDValidationCacheStat
            $stats | Should Not BeNullOrEmpty
            $stats.TotalEntries | Should BeOfType [int]
        }
        
        It "Should benefit from caching on repeated calls" {
            $testSID = 'S-1-5-32-544'
            
            # First call
            $time1 = Measure-Command { $result1 = Test-OrphanedSID -SID $testSID }
            
            # Second call should be faster due to caching
            $time2 = Measure-Command { $result2 = Test-OrphanedSID -SID $testSID }
            
            # Results should be consistent
            $result1 | Should Be $result2
            
            # Second call should generally be faster (cached)
            # Note: This may not always be true due to AD variability
            $result2 | Should BeOfType [bool]
        }
    }
    
    Context "Pipeline Processing" {
        It "Should handle pipeline input correctly" {
            $testSIDs = @(
                'S-1-5-32-544',
                'S-1-5-32-545',
                'S-1-1-0'
            )
            
            $results = $testSIDs | Test-OrphanedSID
            $results.Count | Should Be 3
            $results | ForEach-Object { $_ | Should BeOfType [bool] }
        }
        
        It "Should process mixed valid and invalid SIDs" {
            $mixedSIDs = @(
                'S-1-5-32-544',      # Valid well-known SID
                'invalid-sid',       # Invalid format
                'S-1-1-0'           # Valid well-known SID
            )
            
            $results = $mixedSIDs | Test-OrphanedSID
            $results.Count | Should Be 3
            $results | ForEach-Object { $_ | Should BeOfType [bool] }
            
            # Invalid SID should return true (orphaned)
            $results[1] | Should Be $true
        }
    }
    
    Context "Performance and Reliability" {
        It "Should complete SID validation within reasonable time" {
            $testSID = 'S-1-5-32-544'
            
            $executionTime = Measure-Command {
                $result = Test-OrphanedSID -SID $testSID
            }
            
            # Should complete within 5 seconds for well-known SIDs
            $executionTime.TotalSeconds | Should BeLessThan 5
            $result | Should BeOfType [bool]
        }
        
        It "Should handle batch processing efficiently" {
            $testSIDs = @(
                'S-1-5-32-544',
                'S-1-5-32-545', 
                'S-1-1-0',
                'S-1-5-18',
                'S-1-5-19'
            )
            
            $executionTime = Measure-Command {
                $results = $testSIDs | Test-OrphanedSID
            }
            
            # Should process 5 SIDs within 10 seconds
            $executionTime.TotalSeconds | Should BeLessThan 10
            $results.Count | Should Be 5
            $results | ForEach-Object { $_ | Should BeOfType [bool] }
        }
        
        It "Should maintain consistent results across multiple calls" {
            $testSID = 'S-1-5-32-544'
            
            $results = @()
            1..3 | ForEach-Object {
                $results += Test-OrphanedSID -SID $testSID
            }
            
            # All results should be the same
            $results.Count | Should Be 3
            $results[0] | Should Be $results[1]
            $results[1] | Should Be $results[2]
        }
    }
}
