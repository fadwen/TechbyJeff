# New-SIDResult.Tests.ps1 - Pester 3.4.x Compatible
# Tests for New-SIDResult private function

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

Describe "New-SIDResult Function Tests" {
    
    Context "Function Existence and Basic Functionality" {
        It "Should have New-SIDResult function available" {
            Get-Command New-SIDResult -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should accept SID parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { New-SIDResult -SID $testSID } | Should Not Throw
        }
        
        It "Should accept ResolvedName parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { New-SIDResult -SID $testSID -ResolvedName 'TestUser' } | Should Not Throw
        }
        
        It "Should return result object" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = New-SIDResult -SID $testSID
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Result Object Properties" {
        It "Should include SID in result" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = New-SIDResult -SID $testSID
            
            $result.SID | Should Be $testSID
        }
        
        It "Should include ResolvedName when provided" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $resolvedName = 'TestUser'
            $result = New-SIDResult -SID $testSID -ResolvedName $resolvedName
            
            $result.ResolvedName | Should Be $resolvedName
        }
        
        It "Should include IsOrphaned status" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = New-SIDResult -SID $testSID
            
            $result.PSObject.Properties.Name -contains 'IsOrphaned' | Should Be $true
        }
        
        It "Should include Type information" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = New-SIDResult -SID $testSID
            
            $result.PSObject.Properties.Name -contains 'Type' | Should Be $true
        }
    }
    
    Context "Parameter Validation" {
        It "Should validate SID parameter" {
            { New-SIDResult -SID $null } | Should Throw
        }
        
        It "Should handle empty ResolvedName" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { New-SIDResult -SID $testSID -ResolvedName '' } | Should Not Throw
        }
        
        It "Should handle correlation ID" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            { New-SIDResult -SID $testSID -CorrelationId $correlationId } | Should Not Throw
        }
    }
    
    Context "Result Object Consistency" {
        It "Should create consistent result objects" {
            $testSID1 = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $testSID2 = 'S-1-5-21-1234567890-1234567890-1234567890-1002'
            
            $result1 = New-SIDResult -SID $testSID1
            $result2 = New-SIDResult -SID $testSID2
            
            # Both should have same property structure
            $result1.PSObject.Properties.Name.Count | Should Be $result2.PSObject.Properties.Name.Count
        }
        
        It "Should maintain SID data integrity" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $result = New-SIDResult -SID $testSID
            
            $result.SID | Should Be $testSID
            $result.SID | Should Not BeNullOrEmpty
        }
    }
    
    Context "Performance and Reliability" {
        It "Should create result objects quickly" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            $executionTime = Measure-Command {
                1..10 | ForEach-Object { New-SIDResult -SID $testSID }
            }
            
            $executionTime.TotalMilliseconds | Should BeLessThan 1000  # 1 second for 10 objects
        }
    }
}
