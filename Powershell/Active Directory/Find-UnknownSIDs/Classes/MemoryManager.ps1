#Requires -Version 5.1

class MemoryManager {
    [int]$MaxMemoryMB
    [int]$CheckInterval
    [int]$CheckCounter
    [System.Diagnostics.Stopwatch]$Timer
    [long]$PeakMemoryUsage
    [bool]$Disposed

    MemoryManager([int]$maxMemoryMB, [int]$checkInterval) {
        $this.MaxMemoryMB = $maxMemoryMB
        $this.CheckInterval = $checkInterval
        $this.CheckCounter = 0
        $this.Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $this.PeakMemoryUsage = 0
        $this.Disposed = $false
    }

    [void]CheckMemoryUsage() {
        if ($this.Disposed) {
            return
        }

        $this.CheckCounter++

        if ($this.CheckCounter -ge $this.CheckInterval) {
            $this.CheckCounter = 0

            try {
                $currentProcess = Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)
                $currentMemoryMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)

                if ($currentMemoryMB -gt $this.PeakMemoryUsage) {
                    $this.PeakMemoryUsage = $currentMemoryMB
                }

                if ($currentMemoryMB -gt $this.MaxMemoryMB) {
                    Write-Warning "Memory usage threshold exceeded: $currentMemoryMB MB (Limit: $($this.MaxMemoryMB) MB)"

                    # Force garbage collection
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()

                    # Check memory again after GC
                    $postGCProcess = Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)
                    $postGCMemoryMB = [Math]::Round($postGCProcess.WorkingSet64 / 1MB, 2)
                    Write-Verbose "Memory after garbage collection: $postGCMemoryMB MB"

                    if ($postGCMemoryMB -gt $this.MaxMemoryMB) {
                        throw "Memory usage still exceeds limit after garbage collection: $postGCMemoryMB MB"
                    }
                }

                Write-Verbose "Current memory usage: $currentMemoryMB MB (Peak: $($this.PeakMemoryUsage) MB)"

            } catch {
                Write-Warning "Failed to check memory usage: $($_.Exception.Message)"
            }
        }
    }

    [long] GetPeakMemoryUsage() {
        return $this.PeakMemoryUsage
    }

    [void] Dispose() {
        if (-not $this.Disposed) {
            if ($this.Timer) {
                $this.Timer.Stop()
                $this.Timer = $null
            }
            $this.Disposed = $true
        }
    }
}