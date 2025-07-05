#Requires -Version 5.1

class SecurityValidationResult {
    [bool]$IsValid
    [string]$RiskLevel
    [string[]]$Issues
    [bool]$RequiresElevatedConfirmation
    [string[]]$BlockedSIDs
    [string[]]$AllowedSIDs
    [DateTime]$ValidatedAt
    [string]$ValidatorVersion

    SecurityValidationResult() {
        $this.ValidatedAt = Get-Date
        $this.ValidatorVersion = "2.0.0"
        $this.Issues = @()
        $this.BlockedSIDs = @()
        $this.AllowedSIDs = @()
        $this.IsValid = $true
        $this.RiskLevel = "Low"
        $this.RequiresElevatedConfirmation = $false
    }
}