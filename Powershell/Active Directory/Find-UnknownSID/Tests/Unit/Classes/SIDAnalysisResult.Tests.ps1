#Requires -Version 5.1

# Import the class definition
. "$PSScriptRoot\..\..\..\Classes\SIDAnalysisResult.ps1"

Describe "SIDAnalysisResult Class Tests" -Tag "Unit", "Classes", "SIDAnalysisResult" {
    
    Context "Constructor Tests" {
        It "Should create instance with default constructor" {
            $result = [SIDAnalysisResult]::new()
            
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "SIDAnalysisResult"
        }

        It "Should set AnalyzedAt to current time" {
            $beforeCreation = Get-Date
            Start-Sleep -Milliseconds 10
            $result = [SIDAnalysisResult]::new()
            Start-Sleep -Milliseconds 10
            $afterCreation = Get-Date
            
            $result.AnalyzedAt | Should BeGreaterThan $beforeCreation
            $result.AnalyzedAt | Should BeLessThan $afterCreation
        }

        It "Should initialize string properties as null" {
            $result = [SIDAnalysisResult]::new()
            
            $result.SID | Should BeNullOrEmpty
            $result.LikelySource | Should BeNullOrEmpty
            $result.Confidence | Should BeNullOrEmpty
            $result.Notes | Should BeNullOrEmpty
            $result.RiskLevel | Should BeNullOrEmpty
            $result.DomainContext | Should BeNullOrEmpty
        }
    }

    Context "Property Assignment Tests" {
        BeforeEach {
            $script:testResult = [SIDAnalysisResult]::new()
        }

        It "Should allow setting SID property" {
            $testSID = "S-1-5-21-1234567890-987654321-555444333-1001"
            $script:testResult.SID = $testSID
            
            $script:testResult.SID | Should Be $testSID
        }

        It "Should allow setting LikelySource property" {
            $testSource = "Domain User Account"
            $script:testResult.LikelySource = $testSource
            
            $script:testResult.LikelySource | Should Be $testSource
        }

        It "Should allow setting Confidence property" {
            $testConfidence = "High"
            $script:testResult.Confidence = $testConfidence
            
            $script:testResult.Confidence | Should Be $testConfidence
        }

        It "Should allow setting Notes property" {
            $testNotes = "Analysis notes and findings"
            $script:testResult.Notes = $testNotes
            
            $script:testResult.Notes | Should Be $testNotes
        }

        It "Should allow setting RiskLevel property" {
            $testRiskLevel = "Medium"
            $script:testResult.RiskLevel = $testRiskLevel
            
            $script:testResult.RiskLevel | Should Be $testRiskLevel
        }

        It "Should allow setting DomainContext property" {
            $testContext = "CONTOSO.COM"
            $script:testResult.DomainContext = $testContext
            
            $script:testResult.DomainContext | Should Be $testContext
        }

        It "Should allow setting AnalyzedAt property" {
            $testDate = Get-Date "2024-01-15 10:30:00"
            $script:testResult.AnalyzedAt = $testDate
            
            $script:testResult.AnalyzedAt | Should Be $testDate
        }
    }

    Context "Performance Tests" {
        It "Should create instances quickly" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            1..100 | ForEach-Object {
                $result = [SIDAnalysisResult]::new()
            }
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }
    }
}
