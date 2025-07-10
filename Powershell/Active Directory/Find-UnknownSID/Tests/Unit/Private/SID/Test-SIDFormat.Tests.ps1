# Test-SIDFormat.Tests.ps1 - Pester 3.4.x Compatible
# Tests for Test-SIDFormat private function

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

Describe "Test-SIDFormat Function Tests" {
    
    Context "Function Existence and Basic Functionality" {
        It "Should have Test-SIDFormat function available" {
            Get-Command Test-SIDFormat -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should accept SID parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { Test-SIDFormat -SID $testSID } | Should Not Throw
        }
        
        It "Should accept CorrelationId parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Test-SIDFormat -SID $testSID -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should return a boolean when given valid SID" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = Test-SIDFormat -SID $testSID
            $result | Should Not BeNullOrEmpty
            $result | Should BeOfType [System.Boolean]
        }
    }
    
    Context "SID Format Validation" {
        It "Should validate correct SID formats" {
            $validSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-32-544',
                'S-1-1-0',
                'S-1-5-18'
            )
            
            foreach ($sid in $validSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should reject invalid SID formats" {
            $invalidSIDs = @(
                'InvalidSID',
                'S-1-5',
                'S-X-5-21-1234567890-1234567890-1234567890-1001',
                '1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-ABC-1234567890-1234567890-1001'  # Non-numeric authority
            )
            
            foreach ($sid in $invalidSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $false
            }
        }
        
        It "Should handle null and empty inputs" {
            # Test parameter binding behavior for null/empty values
            { Test-SIDFormat -SID $null } | Should Throw
            { Test-SIDFormat -SID '' } | Should Throw
            { Test-SIDFormat -SID '   ' } | Should Not Throw
            
            # Test actual whitespace handling (should be invalid SID format)
            Test-SIDFormat -SID '   ' | Should Be $false
        }
    }
    
    Context "Well-Known SID Recognition" {
        It "Should recognize well-known SIDs" {
            $wellKnownSIDs = @(
                'S-1-1-0',           # Everyone
                'S-1-5-18',          # LocalSystem
                'S-1-5-19',          # LocalService
                'S-1-5-20',          # NetworkService
                'S-1-5-32-544',      # Administrators
                'S-1-5-32-545'       # Users
            )
            
            foreach ($sid in $wellKnownSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should handle domain SIDs correctly" {
            $domainSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-9876543210-9876543210-9876543210-500',
                'S-1-5-21-1111111111-2222222222-3333333333-1000'
            )
            
            foreach ($sid in $domainSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle correlation ID tracking" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            # Function should accept correlation ID without throwing
            { Test-SIDFormat -SID $testSID -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should handle very long invalid SIDs" {
            $longInvalidSID = 'S-1-5-21-' + ('1234567890-' * 50) + '1001'
            $result = Test-SIDFormat -SID $longInvalidSID
            $result | Should Be $false
        }
        
        It "Should handle special characters in SID" {
            $specialCharSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001!',
                'S-1-5-21-1234567890-1234567890-1234567890-1001@',
                'S-1-5-21-1234567890-1234567890-1234567890-1001#'
            )
            
            foreach ($sid in $specialCharSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $false
            }
        }
    }
    
    Context "Well-Known SID Pattern Validation" {
        It "Should validate built-in domain SID pattern (S-1-5-32-*)" {
            $builtinSIDs = @(
                'S-1-5-32-544',      # Administrators
                'S-1-5-32-545',      # Users
                'S-1-5-32-546',      # Guests
                'S-1-5-32-547',      # Power Users
                'S-1-5-32-548',      # Account Operators
                'S-1-5-32-549',      # Server Operators
                'S-1-5-32-550'       # Print Operators
            )
            
            foreach ($sid in $builtinSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
                
                # Also verify well-known detection if Test-WellKnownSID is available
                if (Get-Command Test-WellKnownSID -ErrorAction SilentlyContinue) {
                    $wellKnownResult = Test-WellKnownSID -SID $sid
                    $wellKnownResult | Should Be $true
                }
            }
        }
        
        It "Should validate service SID patterns (S-1-5-80-*, S-1-5-90-*, S-1-5-96-*)" {
            $serviceSIDs = @(
                'S-1-5-80-123456789-123456789-123456789-123456789-123456789',  # NT Service
                'S-1-5-90-123456789-123456789-123456789-123456789',            # Windows Manager
                'S-1-5-96-123456789-123456789-123456789-123456789'             # Font Driver Host
            )
            
            foreach ($sid in $serviceSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should validate domain admin group patterns ^S-1-5-21-\d+-\d+-\d+-(512|518|519)$" {
            $domainAdminGroups = @(
                'S-1-5-21-1234567890-1234567890-1234567890-512',    # Domain Admins
                'S-1-5-21-9876543210-9876543210-9876543210-518',    # Schema Admins  
                'S-1-5-21-1111111111-2222222222-3333333333-519'     # Enterprise Admins
            )
            
            foreach ($sid in $domainAdminGroups) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
                
                # These should be recognized as well-known if Test-WellKnownSID is available
                if (Get-Command Test-WellKnownSID -ErrorAction SilentlyContinue) {
                    $wellKnownResult = Test-WellKnownSID -SID $sid
                    $wellKnownResult | Should Be $true
                }
            }
        }
        
        It "Should reject invalid domain admin group RIDs" {
            # Test RIDs that don't match the domain admin pattern (512, 518, 519)
            $invalidDomainAdminSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-500',    # Built-in Administrator (not group)
                'S-1-5-21-1234567890-1234567890-1234567890-501',    # Guest account
                'S-1-5-21-1234567890-1234567890-1234567890-513',    # Domain Users (not admin)
                'S-1-5-21-1234567890-1234567890-1234567890-1001'    # Regular domain user
            )
            
            foreach ($sid in $invalidDomainAdminSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true  # Valid format
                
                # But should NOT be recognized as well-known admin groups
                if (Get-Command Test-WellKnownSID -ErrorAction SilentlyContinue) {
                    $wellKnownResult = Test-WellKnownSID -SID $sid
                    # These should be false for non-admin RIDs (except 500 which might be protected)
                    if ($sid -notmatch '-(500)$') {
                        $wellKnownResult | Should Be $false
                    }
                }
            }
        }
    }

    Context "Regex Pattern Validation Details" {
        It "Should validate basic SID pattern ^S-1-\d+-\d+" {
            # Test the core regex pattern used in Test-SIDFormat
            $validBasicPatterns = @(
                'S-1-0-0',           # Minimal valid pattern
                'S-1-1-0',           # Everyone
                'S-1-5-18',          # LocalSystem
                'S-1-5-32-544'       # Administrators
            )
            
            foreach ($sid in $validBasicPatterns) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should reject SIDs that don't match basic pattern ^S-1-\d+-\d+" {
            $invalidBasicPatterns = @(
                'S-X-5-18',          # Non-numeric revision
                '1-5-18',            # Missing S- prefix
                'S-1-A-18',          # Non-numeric identifier authority
                'S-1-5-A',           # Non-numeric subauthority
                'S-1-5',             # Incomplete basic pattern
                'S-1'                # Truncated pattern
            )
            
            foreach ($sid in $invalidBasicPatterns) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $false
            }
        }
        
        It "Should validate domain admin group pattern ^S-1-5-21-\d+-\d+-\d+-(512|518|519)$" {
            # Note: This pattern is used in Test-WellKnownSID, but impacts overall SID validation
            $domainAdminSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-512',    # Domain Admins
                'S-1-5-21-9876543210-9876543210-9876543210-518',    # Schema Admins
                'S-1-5-21-1111111111-2222222222-3333333333-519'     # Enterprise Admins
            )
            
            foreach ($sid in $domainAdminSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $true
            }
        }
        
        It "Should handle edge cases in regex pattern matching" {
            # Test edge cases that might cause regex issues
            $edgeCases = @(
                'S-1-5-21-0-0-0-1001',                              # Zero values
                'S-1-5-21-4294967295-4294967295-4294967295-1001',   # Maximum 32-bit values
                'S-1-15-2-1-2-3-4-5-6-7-8'                          # Windows Store Apps pattern
            )
            
            foreach ($sid in $edgeCases) {
                # Should not throw exceptions during regex processing
                { Test-SIDFormat -SID $sid } | Should Not Throw
            }
        }
        
        It "Should reject malformed patterns that could bypass regex" {
            $malformedPatterns = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001-EXTRA',  # Extra components
                'S-1-5-21-1234567890-1234567890-1234567890-',            # Trailing dash
                'S-1-5-21--1234567890-1234567890-1234567890-1001',       # Double dash
                'S-1-5-21-1234567890--1234567890-1234567890-1001',       # Embedded double dash
                ' S-1-5-21-1234567890-1234567890-1234567890-1001',       # Leading space
                'S-1-5-21-1234567890-1234567890-1234567890-1001 '        # Trailing space
            )
            
            foreach ($sid in $malformedPatterns) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $false
            }
        }
        
        It "Should handle case sensitivity in SID validation" {
            # SID prefix should be case-insensitive according to Microsoft specs
            $caseSensitivityTests = @(
                's-1-5-18',          # Lowercase
                'S-1-5-18',          # Uppercase
                's-1-5-21-1234567890-1234567890-1234567890-1001'  # Lowercase domain SID
            )
            
            foreach ($sid in $caseSensitivityTests) {
                # .NET SecurityIdentifier handles case insensitivity
                { Test-SIDFormat -SID $sid } | Should Not Throw
            }
        }
    }

    Context "Performance and Reliability" {
        It "Should complete validation quickly" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            $executionTime = Measure-Command {
                Test-SIDFormat -SID $testSID
            }
            
            $executionTime.TotalMilliseconds | Should BeLessThan 1000  # 1 second max
        }
        
        It "Should handle multiple validations efficiently" {
            $testSIDs = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-1234567890-1234567890-1234567890-1002',
                'S-1-5-32-544',
                'InvalidSID',
                'S-1-1-0'
            )
            
            $startTime = Get-Date
            
            $results = foreach ($sid in $testSIDs) {
                Test-SIDFormat -SID $sid
            }
            
            $duration = (Get-Date) - $startTime
            $results.Count | Should Be 5
            $duration.TotalSeconds | Should BeLessThan 5
        }
        
        It "Should handle regex performance with large inputs" {
            # Test regex performance with very long invalid SIDs
            $longSID = 'S-1-5-21-' + ('1234567890-' * 100) + '1001'
            
            $executionTime = Measure-Command {
                Test-SIDFormat -SID $longSID
            }
            
            # Should still complete quickly even with large input
            $executionTime.TotalMilliseconds | Should BeLessThan 2000  # 2 seconds max
        }
    }
}
