# Resolve-SIDIdentity Helper Functions Tests

# Setup
$rootPath = $PSScriptRoot
while ($rootPath -and -not (Test-Path (Join-Path $rootPath 'Find-UnknownSID.ps1'))) {
    $rootPath = Split-Path $rootPath -Parent
}

if (-not $rootPath) {
    throw "Cannot find Find-UnknownSID root directory"
}

# Create Write-StructuredLog stub
if (-not (Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue)) {
    function Write-StructuredLog {
        param($Message, $Level = 'Information', $CorrelationId = [System.Guid]::NewGuid().ToString())
        Write-Verbose "[$Level] [$CorrelationId] $Message"
    }
}

# Load Classes
$ClassPath = Join-Path $rootPath 'Classes'
if (Test-Path $ClassPath) {
    Get-ChildItem -Path $ClassPath -Filter '*.ps1' | ForEach-Object { 
        try { . $_.FullName } catch { }
    }
}

# Load the target file
$targetFile = Join-Path $rootPath 'Private\SID\Resolve-SIDIdentity.ps1'
if (Test-Path $targetFile) {
    try {
        . $targetFile
    }
    catch {
        Write-Warning "Could not load target file: $($_.Exception.Message)"
    }
}

Describe "Resolve-SIDIdentity Helper Functions Tests" {
    
    Context "Basic Setup Validation" {
        It "Should be able to run basic tests" {
            $true | Should Be $true
        }
        
        It "Should have Write-StructuredLog function available" {
            Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
        
        It "Should find the root directory" {
            $rootPath | Should Not BeNullOrEmpty
            Test-Path (Join-Path $rootPath 'Find-UnknownSID.ps1') | Should Be $true
        }
        
        It "Should find the target file" {
            $targetFile | Should Not BeNullOrEmpty
            Test-Path $targetFile | Should Be $true
        }
    }
    
    Context "Function Availability Tests" {
        It "Should have Test-AccessRuleForOrphanedSID function available" {
            $func = Get-Command 'Test-AccessRuleForOrphanedSID' -ErrorAction SilentlyContinue
            $func | Should Not BeNullOrEmpty
        }
        
        It "Should have Resolve-IdentityReference function available" {
            $func = Get-Command 'Resolve-IdentityReference' -ErrorAction SilentlyContinue  
            $func | Should Not BeNullOrEmpty
        }
        
        It "Should have Convert-NTAccountToSID function available" {
            $func = Get-Command 'Convert-NTAccountToSID' -ErrorAction SilentlyContinue
            $func | Should Not BeNullOrEmpty
        }
        
        It "Should have Test-SIDValidityAndType function available" {
            $func = Get-Command 'Test-SIDValidityAndType' -ErrorAction SilentlyContinue
            $func | Should Not BeNullOrEmpty
        }
        
        It "Should have Get-StringFromIdentityReference function available" {
            $func = Get-Command 'Get-StringFromIdentityReference' -ErrorAction SilentlyContinue
            $func | Should Not BeNullOrEmpty
        }
    }
    
    Context "Function Type Validation" {
        It "Functions should be of type Function" {
            $functions = @('Test-AccessRuleForOrphanedSID', 'Resolve-IdentityReference', 'Convert-NTAccountToSID', 'Test-SIDValidityAndType', 'Get-StringFromIdentityReference')
            foreach ($funcName in $functions) {
                $func = Get-Command $funcName -ErrorAction SilentlyContinue
                if ($func) {
                    $func.CommandType | Should Be 'Function'
                }
            }
        }
    }
    
    Context "Test-SIDValidityAndType Function Tests" {
        It "Should validate well-known SID S-1-5-32-544" {
            $result = Test-SIDValidityAndType -SIDString 'S-1-5-32-544'
            $result | Should Not BeNullOrEmpty
        }
        
        It "Should handle invalid SID format gracefully" {
            { Test-SIDValidityAndType -SIDString 'InvalidSID' } | Should Not Throw
        }
        
        It "Should process domain SID format" {
            $domainSID = 'S-1-5-21-1234567890-1234567890-1234567890-1000'
            { Test-SIDValidityAndType -SIDString $domainSID } | Should Not Throw
        }
    }
    
    Context "Get-StringFromIdentityReference Function Tests" {
        It "Should require IdentityReference parameter" {
            { Get-StringFromIdentityReference -IdentityReference $null } | Should Throw
        }
        
        It "Should process string identity reference" {
            $identity = 'BUILTIN\Administrators'
            $result = Get-StringFromIdentityReference -IdentityReference $identity
            $result | Should Not BeNullOrEmpty
        }
    }
    
    Context "Parameter Validation Tests" {
        It "Test-AccessRuleForOrphanedSID should have required parameters" {
            $func = Get-Command 'Test-AccessRuleForOrphanedSID' -ErrorAction SilentlyContinue
            if ($func) {
                $params = $func.Parameters.Keys
                $params -contains 'AccessRule' | Should Be $true
            }
        }
        
        It "Resolve-IdentityReference should have IdentityReference parameter" {
            $func = Get-Command 'Resolve-IdentityReference' -ErrorAction SilentlyContinue
            if ($func) {
                $params = $func.Parameters.Keys
                $params -contains 'IdentityReference' | Should Be $true
            }
        }
        
        It "Convert-NTAccountToSID should have NTAccount parameter" {
            $func = Get-Command 'Convert-NTAccountToSID' -ErrorAction SilentlyContinue
            if ($func) {
                $params = $func.Parameters.Keys
                $params -contains 'NTAccount' | Should Be $true
            }
        }
    }
    
    Context "Error Handling Tests" {
        It "Functions should handle correlation ID parameter" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            # Test functions that support correlation ID
            { Test-SIDValidityAndType -SIDString 'S-1-5-32-544' -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should handle malformed SID inputs" {
            $malformedSIDs = @('S-1-5', 'S-1-5-32', 'NotASID')
            foreach ($sid in $malformedSIDs) {
                { Test-SIDValidityAndType -SIDString $sid } | Should Not Throw
            }
        }
    }
    
    Context "Integration and Workflow Tests" {
        It "Should work together in typical SID resolution workflow" {
            # Test a typical workflow using the helper functions
            $testSID = 'S-1-5-32-544'
            
            # Validate SID format first
            { Test-SIDValidityAndType -SIDString $testSID } | Should Not Throw
            
            # Try to get string representation
            { Get-StringFromIdentityReference -IdentityReference $testSID } | Should Not Throw
        }
        
        It "Should handle batch processing scenarios" {
            $sids = @('S-1-5-32-544', 'S-1-5-32-545', 'S-1-5-32-546')
            foreach ($sid in $sids) {
                { Test-SIDValidityAndType -SIDString $sid } | Should Not Throw
            }
        }
    }
    
    Context "Performance and Reliability" {
        It "Should complete SID validation quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Test-SIDValidityAndType -SIDString 'S-1-5-32-544'
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
        
        It "Should handle multiple calls efficiently" {
            $testSIDs = @('S-1-5-32-544', 'S-1-5-32-545', 'S-1-5-32-546', 'S-1-5-32-551', 'S-1-5-32-555')
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            foreach ($sid in $testSIDs) {
                Test-SIDValidityAndType -SIDString $sid
            }
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }
    }
}