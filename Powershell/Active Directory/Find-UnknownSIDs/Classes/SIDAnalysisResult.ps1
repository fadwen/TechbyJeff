#Requires -Version 5.1

class SIDAnalysisResult {
    [string]$SID
    [string]$LikelySource
    [string]$Confidence
    [string]$Notes
    [string]$RiskLevel
    [DateTime]$AnalyzedAt
    [string]$DomainContext

    SIDAnalysisResult() {
        $this.AnalyzedAt = Get-Date
    }
}
