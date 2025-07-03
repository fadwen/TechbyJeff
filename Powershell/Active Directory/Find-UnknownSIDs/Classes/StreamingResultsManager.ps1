#Requires -Version 5.1

class StreamingResultsManager {
    [string]$TempDirectory
    [string]$ResultsFile
    [string]$SummaryFile
    [int]$BatchSize
    [int]$CurrentBatch
    [System.Collections.Generic.List[object]]$CurrentResults
    [object]$Summary
    [bool]$Disposed

    StreamingResultsManager([string]$tempDir, [int]$batchSize = 100) {
        $this.TempDirectory = $tempDir
        $this.BatchSize = $batchSize
        $this.CurrentBatch = 0
        $this.CurrentResults = [System.Collections.Generic.List[object]]::new()
        $this.Disposed = $false

        # Create temp directory if it doesn't exist
        if (-not (Test-Path $this.TempDirectory)) {
            New-Item -Path $this.TempDirectory -ItemType Directory -Force | Out-Null
        }

        # Initialize summary
        $this.Summary = [PSCustomObject]@{
            TotalResults = 0
            BatchFiles = @()
            OrphanedSIDsFound = 0
            ObjectsProcessed = 0
            LastUpdate = Get-Date
        }

        # Set file paths
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $this.ResultsFile = Join-Path $this.TempDirectory "results_$timestamp.json"
        $this.SummaryFile = Join-Path $this.TempDirectory "summary_$timestamp.json"
    }

    [void]AddResult([object]$result) {
        if ($this.Disposed) {
            throw "StreamingResultsManager has been disposed"
        }

        $this.CurrentResults.Add($result)
        $this.Summary.TotalResults++

        # Update summary statistics
        if ($result.PSObject.Properties.Name -contains 'OrphanedSID') {
            $this.Summary.OrphanedSIDsFound++
        }
        $this.Summary.ObjectsProcessed++
        $this.Summary.LastUpdate = Get-Date

        # Flush to disk when batch is full
        if ($this.CurrentResults.Count -ge $this.BatchSize) {
            $this.FlushBatch()
        }
    }

    [void]FlushBatch() {
        if ($this.CurrentResults.Count -eq 0) {
            return
        }

        try {
            $this.CurrentBatch++
            $batchFile = Join-Path $this.TempDirectory "batch_$($this.CurrentBatch).json"

            # Convert to JSON and write to file
            $this.CurrentResults | ConvertTo-Json -Depth 10 -Compress | Out-File -FilePath $batchFile -Encoding UTF8

            # Add to summary
            $this.Summary.BatchFiles += $batchFile

            # Clear current results to free memory
            $this.CurrentResults.Clear()

            # Force garbage collection after each batch
            [System.GC]::Collect()

            Write-Verbose "Flushed batch $($this.CurrentBatch) with $($this.CurrentResults.Count) results to $batchFile"
        }
        catch {
            Write-Warning "Failed to flush batch: $($_.Exception.Message)"
        }
    }

    [void]UpdateSummary() {
        try {
            $this.Summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $this.SummaryFile -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to update summary file: $($_.Exception.Message)"
        }
    }

    [object[]]GetAllResults() {
        # Flush any remaining results
        $this.FlushBatch()

        $allResults = @()

        foreach ($batchFile in $this.Summary.BatchFiles) {
            if (Test-Path $batchFile) {
                try {
                    $batchContent = Get-Content $batchFile -Raw | ConvertFrom-Json
                    $allResults += $batchContent
                }
                catch {
                    Write-Warning "Failed to read batch file $batchFile : $($_.Exception.Message)"
                }
            }
        }

        return $allResults
    }

    [object]GetSummary() {
        $this.UpdateSummary()
        return $this.Summary
    }

    [void]ExportToCsv([string]$outputPath) {
        $allResults = $this.GetAllResults()

        if ($allResults.Count -gt 0) {
            $allResults | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
            Write-Verbose "Exported $($allResults.Count) results to $outputPath"
        }

        # Clean up memory
        $allResults = $null
        [System.GC]::Collect()
    }

    [long]GetCurrentMemoryUsage() {
        $currentProcess = Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)
        return [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
    }

    [void]Dispose() {
        if (-not $this.Disposed) {
            # Flush any remaining results
            $this.FlushBatch()

            # Update final summary
            $this.UpdateSummary()

            # Clear references
            $this.CurrentResults.Clear()
            $this.CurrentResults = $null

            $this.Disposed = $true

            # Force final cleanup
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        }
    }

    [void]Cleanup() {
        # Remove temporary files
        if (Test-Path $this.TempDirectory) {
            try {
                Remove-Item -Path $this.TempDirectory -Recurse -Force
                Write-Verbose "Cleaned up temporary directory: $($this.TempDirectory)"
            }
            catch {
                Write-Warning "Failed to clean up temporary directory: $($_.Exception.Message)"
            }
        }
    }
}
