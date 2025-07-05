#Requires -Version 5.1

class StreamingResultsManager : System.IDisposable {
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

        # Ensure temp directory exists before creating any files
        try {
            if (-not (Test-Path $this.TempDirectory)) {
                New-Item -Path $this.TempDirectory -ItemType Directory -Force | Out-Null
            }

            # Verify directory was created and is writable
            if (-not (Test-Path $this.TempDirectory -PathType Container)) {
                throw "Failed to create or access temporary directory: $($this.TempDirectory)"
            }
        }
        catch {
            throw "StreamingResultsManager initialization failed - cannot create temporary directory '$($this.TempDirectory)': $($_.Exception.Message)"
        }

        # Initialize summary
        $this.Summary = [PSCustomObject]@{
            TotalResults = 0
            BatchFiles = @()
            OrphanedSIDsFound = 0
            ObjectsProcessed = 0
            LastUpdate = Get-Date
        }

        # Set file paths with enhanced error checking
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $this.ResultsFile = Join-Path $this.TempDirectory "results_$timestamp.json"
        $this.SummaryFile = Join-Path $this.TempDirectory "summary_$timestamp.json"

        # Test write access by creating a placeholder file
        try {
            $testContent = @{ initialized = $true; timestamp = Get-Date } | ConvertTo-Json
            $testContent | Out-File -FilePath $this.SummaryFile -Encoding UTF8 -Force
        }
        catch {
            throw "StreamingResultsManager initialization failed - cannot write to temporary directory '$($this.TempDirectory)': $($_.Exception.Message)"
        }
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
            # Ensure directory still exists before writing batch files
            if (-not (Test-Path $this.TempDirectory -PathType Container)) {
                # Only recreate directory if not explicitly cleaned up
                if (-not $this.Disposed) {
                    Write-Warning "Temporary directory no longer exists, recreating: $($this.TempDirectory)"
                    New-Item -Path $this.TempDirectory -ItemType Directory -Force | Out-Null
                } else {
                    Write-Verbose "Skipping batch flush - object is disposed and temp directory was cleaned up"
                    return
                }
            }

            $this.CurrentBatch++
            $batchFile = Join-Path $this.TempDirectory "batch_$($this.CurrentBatch).json"

            # Convert to JSON and write to file with enhanced error handling
            $this.CurrentResults | ConvertTo-Json -Depth 10 -Compress | Out-File -FilePath $batchFile -Encoding UTF8 -Force

            # Add to summary
            $this.Summary.BatchFiles += $batchFile

            # Clear current results to free memory
            $this.CurrentResults.Clear()

            # Force garbage collection after each batch
            [System.GC]::Collect()

            Write-Verbose "Flushed batch $($this.CurrentBatch) with $($this.CurrentResults.Count) results to $batchFile"
        }
        catch {
            Write-Warning "Failed to flush batch $($this.CurrentBatch): $($_.Exception.Message)"

            # Provide diagnostic information for troubleshooting
            $diagnosticInfo = @{
                TempDirectory = $this.TempDirectory
                CurrentBatch = $this.CurrentBatch
                ResultsCount = $this.CurrentResults.Count
                DirectoryExists = (Test-Path $this.TempDirectory -PathType Container)
                IsDisposed = $this.Disposed
                ErrorMessage = $_.Exception.Message
                Timestamp = Get-Date
            }
            Write-Verbose "Batch flush diagnostic info: $($diagnosticInfo | ConvertTo-Json -Compress)"
        }
    }

    [void]UpdateSummary() {
        try {
            # Skip summary update if object is disposed and directory was cleaned up
            if ($this.Disposed -and (-not (Test-Path $this.TempDirectory -PathType Container))) {
                Write-Verbose "Skipping summary update - object is disposed and temp directory was cleaned up"
                return
            }

            # Ensure directory still exists before writing
            if (-not (Test-Path $this.TempDirectory -PathType Container)) {
                # Only recreate directory if not explicitly disposed
                if (-not $this.Disposed) {
                    Write-Warning "Temporary directory no longer exists, recreating: $($this.TempDirectory)"
                    New-Item -Path $this.TempDirectory -ItemType Directory -Force | Out-Null
                } else {
                    Write-Verbose "Cannot recreate temp directory - object is disposed"
                    return
                }
            }

            # Write summary with enhanced error handling
            $this.Summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $this.SummaryFile -Encoding UTF8 -Force
        }
        catch {
            # Log the error but don't throw - summary updates are not critical for core functionality
            Write-Warning "Failed to update summary file '$($this.SummaryFile)': $($_.Exception.Message)"

            # Try to create a diagnostic message for troubleshooting
            $diagnosticInfo = @{
                TempDirectory = $this.TempDirectory
                SummaryFile = $this.SummaryFile
                DirectoryExists = (Test-Path $this.TempDirectory -PathType Container)
                ParentDirectoryExists = (Test-Path (Split-Path $this.TempDirectory -Parent) -PathType Container)
                IsDisposed = $this.Disposed
                ErrorMessage = $_.Exception.Message
                Timestamp = Get-Date
            }
            Write-Verbose "Summary update diagnostic info: $($diagnosticInfo | ConvertTo-Json -Compress)"
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
        # Only update summary if object is not disposed and directory exists
        if (-not $this.Disposed -and (Test-Path $this.TempDirectory -PathType Container)) {
            $this.UpdateSummary()
        }
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

            # Update final summary only if temp directory still exists
            if (Test-Path $this.TempDirectory -PathType Container) {
                $this.UpdateSummary()
            } else {
                Write-Verbose "Skipping final summary update - temp directory no longer exists: $($this.TempDirectory)"
            }

            # Clean up temporary files during disposal
            $this.Cleanup()

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
