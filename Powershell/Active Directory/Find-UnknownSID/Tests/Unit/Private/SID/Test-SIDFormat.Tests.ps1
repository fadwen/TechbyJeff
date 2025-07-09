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
                'S-1-5-21-1234567890-1234567890-1234567890'
            )
            
            foreach ($sid in $invalidSIDs) {
                $result = Test-SIDFormat -SID $sid
                $result | Should Be $false
            }
        }
        
        It "Should handle null and empty inputs" {
            Test-SIDFormat -SID $null | Should Be $false
            Test-SIDFormat -SID '' | Should Be $false
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
    }
}
