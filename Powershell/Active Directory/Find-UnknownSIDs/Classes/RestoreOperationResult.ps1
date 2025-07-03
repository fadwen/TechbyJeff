#Requires -Version 5.1

class RestoreOperationResult {
    [string]$ObjectDN
    [string]$CorrelationId
    [string]$BackupFile
    [DateTime]$BackupDate
    [DateTime]$RestorationDate
    [bool]$Success
    [string]$ErrorMessage
    [TimeSpan]$ProcessingTime
    [bool]$BackupValidation
    [int]$EntriesRestored
    [bool]$WhatIfMode

    RestoreOperationResult() {
        $this.RestorationDate = Get-Date
        $this.CorrelationId = [System.Guid]::NewGuid().ToString()
        $this.Success = $false
        $this.BackupValidation = $false
        $this.EntriesRestored = 0
        $this.WhatIfMode = $false
        $this.ProcessingTime = [TimeSpan]::Zero
    }
}