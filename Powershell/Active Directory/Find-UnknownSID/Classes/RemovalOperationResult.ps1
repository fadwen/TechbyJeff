#Requires -Version 5.1

class RemovalOperationResult {
    [string]$ObjectDN
    [string[]]$IntendedRemovals
    [int]$ActualRemovals
    [int]$FailedRemovals
    [string[]]$RemovedSIDs
    [string[]]$FailedSIDs
    [string[]]$BlockedSIDs
    [bool]$Success
    [string]$ErrorMessage
    [System.TimeSpan]$ProcessingTime
    [string]$CorrelationId
    [object]$SecurityValidation

    RemovalOperationResult() {
        $this.IntendedRemovals = @()
        $this.ActualRemovals = 0
        $this.FailedRemovals = 0
        $this.RemovedSIDs = @()
        $this.FailedSIDs = @()
        $this.BlockedSIDs = @()
        $this.Success = $false
        $this.ErrorMessage = $null
        $this.ProcessingTime = [System.TimeSpan]::Zero
        $this.CorrelationId = [System.Guid]::NewGuid().ToString()
        $this.SecurityValidation = $null
    }
}