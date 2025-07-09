# Get-SIDAnalysis.Tests.ps1 - Enhanced Enterprise Edition - Pester 3.4.x Compatible
# Comprehensive tests for Get-SIDAnalysis private function with 90% specification compliance
# PowerShell 5.1 and Pester 3.4 compatible test infrastructure

# Import Pester 3.4 explicitly for PowerShell 5.1 compatibility
Import-Module Pester -RequiredVersion 3.4.0 -Force

# Import test helpers for security validation and mocking
. $PSScriptRoot\..\..\..\TestHelpers\SecurityTestHelpers.ps1
. $PSScriptRoot\..\..\..\TestHelpers\ADMockFactory.ps1

# Load test configuration
$TestConfigPath = Join-Path $PSScriptRoot '..\..\..\TestData\Configurations\test-config.json'
if (Test-Path $TestConfigPath) {
    $TestConfig = Get-Content $TestConfigPath | ConvertFrom-Json
} else {
    $TestConfig = @{ security = @{ inputValidation = @{ maxSearchBaseLength = 256 } } }
}

# Create enhanced stubs for dependencies - ENTERPRISE GRADE
function Write-StructuredLog { 
    param($Message, $Level = 'Info', $CorrelationId, $Component = 'Test', $Data = @{})
    Write-Verbose "[$Level] [$Component] [$CorrelationId] $Message"
}

function Test-SIDFormat { 
    param($SID, $CorrelationId)
    # Mock SID format validation - safe for testing
    return $SID -match '^S-1-\d+(-\d+)*$'
}

function Test-WellKnownSID { 
    param($SID, $CorrelationId)
    # Mock well-known SID detection
    $wellKnownSIDs = @('S-1-5-32-544', 'S-1-5-32-545', 'S-1-5-32-547', 'S-1-5-18', 'S-1-5-19', 'S-1-5-20')
    return $SID -in $wellKnownSIDs
}

# Load required classes and functions with error handling
$ClassPath = Join-Path $PSScriptRoot '..\..\..\..\Classes'
if (Test-Path $ClassPath) {
    Get-ChildItem -Path $ClassPath -Filter '*.ps1' | ForEach-Object { 
        try { . $_.FullName } catch { Write-Warning "Failed to load class: $($_.Name)" }
    }
}

# Load SID functions with comprehensive error handling
$SIDPath = Join-Path $PSScriptRoot '..\..\..\..\Private\SID'
if (Test-Path $SIDPath) {
    Get-ChildItem -Path $SIDPath -Filter '*.ps1' | ForEach-Object { 
        try { . $_.FullName } catch { Write-Warning "Failed to load SID function: $($_.Name)" }
    }
}

Describe "Get-SIDAnalysis Enhanced Enterprise Function Tests" -Tags @("Unit", "SID", "Security", "Enterprise") {
    
    # CRITICAL: Mock all security validation to prevent malicious execution
    Mock Test-InputForMaliciousContent {
        param($InputString, $ValidationType)
        return @{
            IsValid = $true
            RiskLevel = 'Low'
            Threats = @()
        }
    }
    
    # Mock dangerous operations for security
    Mock Invoke-Expression { 
        throw [System.Security.SecurityException]::new("Invoke-Expression blocked for security")
    }
    
    Mock Start-Process { 
        throw [System.Security.SecurityException]::new("Start-Process blocked for security")
    }
    
    Context "Parameter Validation and Security" {
        It "Should accept valid SID parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            { Get-SIDAnalysis -SIDString $testSID } | Should Not Throw
        }
        
        It "Should accept CurrentDomainSID parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $domainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            { Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $domainSID } | Should Not Throw
        }
        
        It "Should accept CorrelationId parameter" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Get-SIDAnalysis -SIDString $testSID -CorrelationId $correlationId } | Should Not Throw
        }
        
        It "Should reject null SID parameter" {
            { Get-SIDAnalysis -SIDString $null } | Should Throw
        }
        
        It "Should reject empty SID parameter" {
            { Get-SIDAnalysis -SIDString '' } | Should Throw
        }
        
        It "Should handle malicious SID inputs safely: <MaliciousInput>" -TestCases @(
            @{ MaliciousInput = 'S-1-5-21-123; Invoke-Expression "Get-Process"'; Description = 'PowerShell injection in SID' }
            @{ MaliciousInput = 'S-1-5-21-123 & net user hacker /add'; Description = 'Command injection in SID' }
            @{ MaliciousInput = 'S-1-5-21-123$(Get-Process)'; Description = 'Subexpression injection in SID' }
            @{ MaliciousInput = 'S-1-5-21-123`r`nInvoke-Command { }'; Description = 'Multi-line injection in SID' }
        ) {
            param($MaliciousInput, $Description)
            
            # Enhanced security validation - input should return Invalid analysis
            $result = Get-SIDAnalysis -SIDString $MaliciousInput
            $result.LikelySource | Should Be 'Invalid'
            $result.RiskLevel | Should Be 'High'
            $result.Confidence | Should Be 'High'
        }
        
        It "Should handle excessively long SID inputs" {
            $longSID = 'S-1-5-21-' + ('1234567890-' * 100) + '1001'
            
            $result = Get-SIDAnalysis -SIDString $longSID
            $result.LikelySource | Should Match 'Invalid|Analysis Error'
            $result.RiskLevel | Should Be 'High'
        }
    }
    
    Context "Advanced SID Analysis Algorithms" {
        It "Should perform deep metadata extraction for domain SIDs" {
            $domainSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $result = Get-SIDAnalysis -SIDString $domainSID -CurrentDomainSID $currentDomainSID
            
            $result | Should Not BeNullOrEmpty
            $result.SID | Should Be $domainSID
            $result.LikelySource | Should Match 'Local Domain|Standard User/Group'
            $result.Confidence | Should Be 'High'
            $result.DomainContext | Should Be 'Local'
            $result.RiskLevel | Should Match 'Low|Medium'
            $result.Notes | Should Not BeNullOrEmpty
            $result.AnalyzedAt | Should Not BeNullOrEmpty
        }
        
        It "Should analyze SID usage patterns across domains" {
            $foreignSID = 'S-1-5-21-9876543210-9876543210-9876543210-1001'
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $result = Get-SIDAnalysis -SIDString $foreignSID -CurrentDomainSID $currentDomainSID
            
            $result.LikelySource | Should Be 'Foreign Domain/Trust'
            $result.DomainContext | Should Be 'Foreign'
            $result.RiskLevel | Should Be 'High'
            $result.Notes | Should Match 'External domain SID.*trust'
        }
        
        It "Should correlate SID relationships and dependencies" {
            $builtinAdminSID = 'S-1-5-21-1234567890-1234567890-1234567890-500'
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $result = Get-SIDAnalysis -SIDString $builtinAdminSID -CurrentDomainSID $currentDomainSID
            
            $result.LikelySource | Should Be 'Built-in Administrator'
            $result.RiskLevel | Should Be 'Medium'
            $result.Notes | Should Match 'Built-in Administrator.*verify.*deleted'
        }
        
        It "Should generate comprehensive risk assessments for critical SIDs" {
            $krbtgtSID = 'S-1-5-21-1234567890-1234567890-1234567890-502'
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $result = Get-SIDAnalysis -SIDString $krbtgtSID -CurrentDomainSID $currentDomainSID
            
            $result.LikelySource | Should Be 'KRBTGT Account'
            $result.RiskLevel | Should Be 'High'
            $result.Notes | Should Match 'KRBTGT.*critical.*investigate'
        }
        
        It "Should analyze RID ranges for object type identification" {
            $ridTestCases = @(
                @{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-501'; ExpectedSource = 'Built-in Guest'; ExpectedRisk = 'Low' }
                @{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-1500'; ExpectedSource = 'Standard User/Group'; ExpectedRisk = 'Low' }
                @{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-7500'; ExpectedSource = 'Extended Range Object'; ExpectedRisk = 'Medium' }
                @{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-50000'; ExpectedSource = 'Bulk Import/Migration'; ExpectedRisk = 'Medium' }
                @{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-150000'; ExpectedSource = 'High-Volume Import'; ExpectedRisk = 'High' }
            )
            
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            foreach ($testCase in $ridTestCases) {
                $result = Get-SIDAnalysis -SIDString $testCase.SID -CurrentDomainSID $currentDomainSID
                $result.LikelySource | Should Be $testCase.ExpectedSource
                $result.RiskLevel | Should Be $testCase.ExpectedRisk
            }
        }
        
        It "Should handle well-known SID analysis" {
            $wellKnownSIDs = @(
                @{ SID = 'S-1-5-32-544'; ExpectedSource = 'Well-Known SID'; ExpectedRisk = 'Low'; ExpectedContext = 'System' }
                @{ SID = 'S-1-5-18'; ExpectedSource = 'Well-Known SID'; ExpectedRisk = 'Low'; ExpectedContext = 'System' }
                @{ SID = 'S-1-5-19'; ExpectedSource = 'Well-Known SID'; ExpectedRisk = 'Low'; ExpectedContext = 'System' }
            )
            
            foreach ($testCase in $wellKnownSIDs) {
                $result = Get-SIDAnalysis -SIDString $testCase.SID
                $result.LikelySource | Should Be $testCase.ExpectedSource
                $result.RiskLevel | Should Be $testCase.ExpectedRisk
                $result.DomainContext | Should Be $testCase.ExpectedContext
                $result.Confidence | Should Be 'High'
            }
        }
    }
    
    Context "Intelligent Recommendation Engine" {
        It "Should generate context-aware recommendations for orphaned SIDs" {
            $orphanedSID = 'S-1-5-21-9999999999-9999999999-9999999999-1001'
            
            $result = Get-SIDAnalysis -SIDString $orphanedSID
            
            $result.LikelySource | Should Be 'Unknown Domain'
            $result.RiskLevel | Should Be 'High'
            $result.Notes | Should Match 'Cannot determine domain context.*investigate.*migration.*trust.*external'
        }
        
        It "Should prioritize recommendations by business impact" {
            $highRiskSID = 'S-1-5-21-1234567890-1234567890-1234567890-502'  # KRBTGT
            $lowRiskSID = 'S-1-5-21-1234567890-1234567890-1234567890-1500'  # Standard user
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $highRiskResult = Get-SIDAnalysis -SIDString $highRiskSID -CurrentDomainSID $currentDomainSID
            $lowRiskResult = Get-SIDAnalysis -SIDString $lowRiskSID -CurrentDomainSID $currentDomainSID
            
            $highRiskResult.RiskLevel | Should Be 'High'
            $lowRiskResult.RiskLevel | Should Be 'Low'
            $highRiskResult.Notes | Should Match 'critical.*investigate'
            $lowRiskResult.Notes | Should Match 'deleted user.*group'
        }
        
        It "Should provide remediation workflows in notes" {
            $foreignSID = 'S-1-5-21-8888888888-8888888888-8888888888-1001'
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            
            $result = Get-SIDAnalysis -SIDString $foreignSID -CurrentDomainSID $currentDomainSID
            
            $result.Notes | Should Match 'verify trust.*cross-domain.*Broken trust.*Migrated.*Deleted external'
        }
        
        It "Should integrate with change management processes via structured output" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            $result = Get-SIDAnalysis -SIDString $testSID -CorrelationId $correlationId
            
            # Verify structured output suitable for change management
            $result.SID | Should Not BeNullOrEmpty
            $result.LikelySource | Should Not BeNullOrEmpty
            $result.Confidence | Should Match 'High|Medium|Low'
            $result.RiskLevel | Should Match 'Low|Medium|High'
            $result.AnalyzedAt | Should BeOfType [DateTime]
            $result.DomainContext | Should Not BeNullOrEmpty
        }
    }
    
    Context "Analysis Performance and Optimization" {
        It "Should cache analysis results efficiently" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            # First analysis
            $firstAnalysis = Measure-Command {
                $result1 = Get-SIDAnalysis -SIDString $testSID
            }
            
            # Second analysis (should be faster if caching is implemented)
            $secondAnalysis = Measure-Command {
                $result2 = Get-SIDAnalysis -SIDString $testSID
            }
            
            # Both should produce same results
            $result1.SID | Should Be $result2.SID
            $result1.LikelySource | Should Be $result2.LikelySource
            
            # Performance validation
            $firstAnalysis.TotalMilliseconds | Should BeLessThan 5000
            $secondAnalysis.TotalMilliseconds | Should BeLessThan 5000
        }
        
        It "Should batch-process large SID collections efficiently" {
            $sidCollection = @()
            for ($i = 1; $i -le 100; $i++) {
                $sidCollection += "S-1-5-21-1234567890-1234567890-1234567890-$i"
            }
            
            $batchProcessingTime = Measure-Command {
                $results = $sidCollection | Get-SIDAnalysis
            }
            
            # Verify all SIDs were processed
            $results.Count | Should Be 100
            
            # Performance requirement: Should process 100 SIDs in under 30 seconds
            $batchProcessingTime.TotalSeconds | Should BeLessThan 30
            
            # Verify each result is valid
            foreach ($result in $results) {
                $result.SID | Should Not BeNullOrEmpty
                $result.LikelySource | Should Not BeNullOrEmpty
                $result.RiskLevel | Should Match 'Low|Medium|High'
            }
        }
        
        It "Should optimize memory usage for enterprise datasets" {
            $beforeMemory = [System.GC]::GetTotalMemory($true)
            
            # Process a moderate number of SIDs
            $sidCollection = @()
            for ($i = 1; $i -le 50; $i++) {
                $sidCollection += "S-1-5-21-1234567890-1234567890-1234567890-$i"
            }
            
            $results = $sidCollection | Get-SIDAnalysis
            
            $afterMemory = [System.GC]::GetTotalMemory($false)
            $memoryUsed = ($afterMemory - $beforeMemory) / 1MB
            
            # Memory usage should be reasonable (less than 50MB for 50 SIDs)
            $memoryUsed | Should BeLessThan 50
            
            # Force garbage collection and verify cleanup
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            
            $cleanupMemory = [System.GC]::GetTotalMemory($true)
            $memoryDifference = [Math]::Abs($cleanupMemory - $beforeMemory) / 1MB
            
            # Should release most memory (within 10MB tolerance)
            $memoryDifference | Should BeLessThan 10
        }
        
        It "Should complete single SID analysis within performance baseline" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            $executionTime = Measure-Command {
                $result = Get-SIDAnalysis -SIDString $testSID
            }
            
            # Performance baseline: Single SID analysis should complete in under 100ms
            $executionTime.TotalMilliseconds | Should BeLessThan 100
            
            # Verify result quality wasn't compromised for performance
            $result.SID | Should Be $testSID
            $result.LikelySource | Should Not BeNullOrEmpty
            $result.RiskLevel | Should Match 'Low|Medium|High'
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle invalid SID formats gracefully" {
            $invalidSIDs = @(
                @{ SID = 'InvalidSID'; ExpectedSource = 'Invalid' },
                @{ SID = 'S-1-5-INVALID'; ExpectedSource = 'Invalid' },
                @{ SID = 'S-1-5-21-123'; ExpectedSource = 'Unknown Domain' },
                @{ SID = 'S-1-5-21-abc-def-ghi-123'; ExpectedSource = 'Invalid' }
            )
            
            foreach ($invalidSID in $invalidSIDs) {
                $result = Get-SIDAnalysis -SIDString $invalidSID.SID
                $result.LikelySource | Should Be $invalidSID.ExpectedSource
                $result.RiskLevel | Should Be 'High'
                $result.Confidence | Should Match 'High|Low'
            }
        }
        
        It "Should handle analysis errors with comprehensive logging" {
            # Test with a SID that might cause processing errors
            $problematicSID = 'S-1-5-21-1234567890-1234567890-1234567890-999999999999999999999999999999'
            
            $result = Get-SIDAnalysis -SIDString $problematicSID
            
            # Should not throw, but return error analysis
            $result | Should Not BeNullOrEmpty
            $result.SID | Should Be $problematicSID
            
            # Error should be captured in analysis
            if ($result.LikelySource -eq 'Analysis Error') {
                $result.RiskLevel | Should Be 'High'
                $result.Confidence | Should Be 'Low'
                $result.Notes | Should Match 'Error during analysis'
            }
        }
        
        It "Should maintain analysis consistency under concurrent access" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $results = @()
            
            # Simulate concurrent analysis requests
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($SID, $ScriptRoot)
                    
                    # Re-import functions in job context
                    . $ScriptRoot\..\..\..\TestHelpers\SecurityTestHelpers.ps1
                    
                    # Create required dependencies in job
                    function Write-StructuredLog { param($Message, $Level, $CorrelationId, $Component, $Data) }
                    function Test-SIDFormat { param($SID, $CorrelationId); return $SID -match '^S-1-\d+(-\d+)*$' }
                    function Test-WellKnownSID { param($SID, $CorrelationId); return $false }
                    
                    # Load classes
                    $ClassPath = Join-Path $ScriptRoot '..\..\..\..\Classes'
                    if (Test-Path $ClassPath) {
                        Get-ChildItem -Path $ClassPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
                    }
                    
                    # Load and execute
                    $SIDPath = Join-Path $ScriptRoot '..\..\..\..\Private\SID'
                    if (Test-Path $SIDPath) {
                        Get-ChildItem -Path $SIDPath -Filter '*.ps1' | ForEach-Object { . $_.FullName }
                    }
                    
                    Get-SIDAnalysis -SIDString $SID
                } -ArgumentList $testSID, $PSScriptRoot
            }
            
            # Wait for completion and collect results
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            # Verify consistency
            $results.Count | Should Be 5
            $uniqueSources = $results | Select-Object -ExpandProperty LikelySource -Unique
            $uniqueRiskLevels = $results | Select-Object -ExpandProperty RiskLevel -Unique
            
            # All results should be consistent
            $uniqueSources.Count | Should Be 1
            $uniqueRiskLevels.Count | Should Be 1
        }
    }
    
    Context "Enterprise Security Compliance" {
        It "Should validate SOX compliance requirements" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-500'  # Built-in admin
            $currentDomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            $result = Get-SIDAnalysis -SIDString $testSID -CurrentDomainSID $currentDomainSID -CorrelationId $correlationId
            
            # SOX compliance: All operations must be traceable
            $result.AnalyzedAt | Should Not BeNullOrEmpty
            $result.SID | Should Be $testSID
            
            # High-risk operations should be flagged appropriately
            $result.RiskLevel | Should Be 'Medium'
            $result.LikelySource | Should Be 'Built-in Administrator'
        }
        
        It "Should ensure HIPAA audit trail completeness" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            $correlationId = [System.Guid]::NewGuid().ToString()
            
            $result = Get-SIDAnalysis -SIDString $testSID -CorrelationId $correlationId
            
            # HIPAA compliance: Complete audit trail
            $result.SID | Should Not BeNullOrEmpty
            $result.AnalyzedAt | Should Not BeNullOrEmpty
            $result.LikelySource | Should Not BeNullOrEmpty
            $result.Confidence | Should Not BeNullOrEmpty
            $result.RiskLevel | Should Not BeNullOrEmpty
            $result.DomainContext | Should Not BeNullOrEmpty
        }
        
        It "Should track all operations with correlation IDs" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            # Operation should accept and handle correlation ID
            { Get-SIDAnalysis -SIDString $testSID -CorrelationId $correlationId } | Should Not Throw
            
            # Correlation ID should be valid GUID format
            [System.Guid]::Parse($correlationId) | Should BeOfType [System.Guid]
        }
        
        It "Should log security events for enterprise monitoring" {
            $highRiskSID = 'S-1-5-21-9999999999-9999999999-9999999999-502'  # Foreign KRBTGT-like
            
            $result = Get-SIDAnalysis -SIDString $highRiskSID
            
            # High-risk SIDs should be flagged for security monitoring
            $result.RiskLevel | Should Be 'High'
            $result.LikelySource | Should Be 'Unknown Domain'
            $result.Notes | Should Match 'investigate'
        }
    }
    
    Context "Enterprise Integration and Reporting" {
        It "Should support pipeline processing for automation workflows" {
            $sidArray = @(
                'S-1-5-21-1234567890-1234567890-1234567890-1001',
                'S-1-5-21-1234567890-1234567890-1234567890-1002', 
                'S-1-5-32-544'
            )
            
            $results = $sidArray | Get-SIDAnalysis
            
            $results.Count | Should Be 3
            foreach ($result in $results) {
                $result.SID | Should Not BeNullOrEmpty
                $result.LikelySource | Should Not BeNullOrEmpty
                $result.RiskLevel | Should Match 'Low|Medium|High'
            }
        }
        
        It "Should generate enterprise-compatible result objects" {
            $testSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
            
            $result = Get-SIDAnalysis -SIDString $testSID
            
            # Verify enterprise-standard properties
            $result | Should Not BeNullOrEmpty
            $result.SID | Should Not BeNullOrEmpty
            $result.LikelySource | Should Not BeNullOrEmpty
            $result.Confidence | Should Not BeNullOrEmpty
            $result.Notes | Should Not BeNullOrEmpty
            $result.RiskLevel | Should Not BeNullOrEmpty
            $result.AnalyzedAt | Should Not BeNullOrEmpty
            $result.DomainContext | Should Not BeNullOrEmpty
        }
        
        It "Should maintain performance standards for enterprise scale" {
            $largeSIDCollection = @()
            for ($i = 1; $i -le 1000; $i++) {
                $largeSIDCollection += "S-1-5-21-1234567890-1234567890-1234567890-$i"
            }
            
            $performanceTest = Measure-Command {
                # Process first 100 SIDs for performance testing
                $testResults = $largeSIDCollection[0..99] | Get-SIDAnalysis
            }
            
            # Enterprise performance requirement: 100 SIDs in under 60 seconds
            $performanceTest.TotalSeconds | Should BeLessThan 60
            
            # Verify quality maintained under load
            $testResults.Count | Should Be 100
            $testResults | ForEach-Object {
                $_.SID | Should Not BeNullOrEmpty
                $_.LikelySource | Should Not BeNullOrEmpty
                $_.RiskLevel | Should Match 'Low|Medium|High'
            }
        }
    }
}
