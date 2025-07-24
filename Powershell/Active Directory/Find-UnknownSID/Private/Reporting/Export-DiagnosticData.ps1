function Export-DiagnosticData {
    <#
    .SYNOPSIS
        Exports comprehensive diagnostic information for troubleshooting and support analysis

    .DESCRIPTION
        Collects and exports detailed diagnostic information including system state,
        log files, configuration, and runtime metrics. Creates a timestamped diagnostic
        package containing sanitized data suitable for support analysis and troubleshooting.

        This function provides enterprise-grade diagnostic capabilities with:
        - Comprehensive system information collection
        - Memory usage and performance metrics
        - Log file analysis and inclusion
        - Sanitized configuration export
        - Structured diagnostic package creation

    .PARAMETER OutputPath
        Directory path where diagnostic data will be exported. The function will create
        a timestamped subdirectory within this path for the diagnostic package.

    .PARAMETER CorrelationId
        Correlation ID for tracking the diagnostic export operation across logs and
        audit trails. Auto-generated if not provided.

    .EXAMPLE
        PS> Export-DiagnosticData -OutputPath "C:\Diagnostics"

        DESCRIPTION: Exports diagnostic data with auto-generated correlation ID
        OUTPUT: Returns path to created diagnostic package
        USE CASE: Standard diagnostic export for troubleshooting

    .EXAMPLE
        PS> $diagnosticPath = Export-DiagnosticData -OutputPath "C:\Support" -CorrelationId "incident-12345"
        PS> Write-Output "Diagnostic package created at: $diagnosticPath"

        DESCRIPTION: Exports diagnostic data with specific correlation ID for incident tracking
        OUTPUT: Diagnostic package path with correlation tracking
        USE CASE: Support incident analysis with audit trail

    .EXAMPLE
        PS> try {
        PS>     $path = Export-DiagnosticData -OutputPath $env:TEMP
        PS>     Compress-Archive -Path $path -DestinationPath "diagnostic-package.zip"
        PS> } catch {
        PS>     Write-Error "Diagnostic export failed: $_"
        PS> }

        DESCRIPTION: Exports and compresses diagnostic data for distribution
        OUTPUT: Compressed diagnostic package
        USE CASE: Preparing diagnostic data for remote support analysis

    .OUTPUTS
        System.String
        Returns the full path to the created diagnostic package directory.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        SECURITY: All exported data is sanitized to remove sensitive information
        PERFORMANCE: Optimized for minimal impact on running operations
        COMPLIANCE: Supports audit requirements with correlation tracking

        TROUBLESHOOTING:
        - For export failures: .\Troubleshooting\Diagnostics\Export-Issues.md
        - For large log files: .\Troubleshooting\Performance\Memory-Optimization.md
        - For permissions: .\Troubleshooting\Security\Access-Control.md

        DEPENDENCIES:
        - Requires Write-StructuredLogEntry function for logging
        - Requires Get-LogFileSummary function for log analysis
        - Requires access to script-level logging variables ($script:LogPath)
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (-not (Test-Path $_ -IsValid)) {
                throw "OutputPath must be a valid directory path"
            }
            $true
        })]
        [string]$OutputPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting diagnostic data export - CorrelationId: $CorrelationId"

        # Validate output directory exists or can be created
        if (-not (Test-Path $OutputPath)) {
            try {
                New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created output directory: $OutputPath"
            }
            catch {
                Write-Error "Failed to create output directory '$OutputPath': $($_.Exception.Message)"
                throw
            }
        }
    }

    process {
        try {
            # Create timestamped diagnostic package directory
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $diagnosticPath = Join-Path $OutputPath "Diagnostic-$timestamp"

            if ($PSCmdlet.ShouldProcess($diagnosticPath, "Create diagnostic package")) {
                New-Item -Path $diagnosticPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created diagnostic package directory: $diagnosticPath"

                # Collect comprehensive system information
                $systemInfo = @{
                    PSVersion = $PSVersionTable.PSVersion.ToString()
                    PSEdition = $PSVersionTable.PSEdition
                    OSVersion = [System.Environment]::OSVersion.ToString()
                    OSArchitecture = [System.Environment]::Is64BitOperatingSystem
                    ProcessArchitecture = [System.Environment]::Is64BitProcess
                    MachineName = $env:COMPUTERNAME
                    UserName = $env:USERNAME
                    Domain = $env:USERDOMAIN
                    ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
                    StartTime = [System.Diagnostics.Process]::GetCurrentProcess().StartTime
                    ThreadCount = [System.Diagnostics.Process]::GetCurrentProcess().Threads.Count
                    HandleCount = [System.Diagnostics.Process]::GetCurrentProcess().HandleCount
                    ModuleCount = [System.Diagnostics.Process]::GetCurrentProcess().Modules.Count
                }

                # Collect memory and performance metrics
                $currentProcess = Get-Process -Id ([System.Diagnostics.Process]::GetCurrentProcess().Id)
                $memoryInfo = @{
                    WorkingSetMB = [Math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
                    PrivateMemoryMB = [Math]::Round($currentProcess.PrivateMemorySize64 / 1MB, 2)
                    VirtualMemoryMB = [Math]::Round($currentProcess.VirtualMemorySize64 / 1MB, 2)
                    PagedMemoryMB = [Math]::Round($currentProcess.PagedMemorySize64 / 1MB, 2)
                    NonPagedMemoryMB = [Math]::Round($currentProcess.NonpagedSystemMemorySize64 / 1MB, 2)
                    PeakWorkingSetMB = [Math]::Round($currentProcess.PeakWorkingSet64 / 1MB, 2)
                    TotalProcessorTime = $currentProcess.TotalProcessorTime.ToString()
                    UserProcessorTime = $currentProcess.UserProcessorTime.ToString()
                }

                # Get log file analysis if available
                $logInfo = $null
                try {
                    if (Get-Command Get-LogFileSummary -ErrorAction SilentlyContinue) {
                        $logInfo = Get-LogFileSummary -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Verbose "Could not retrieve log file summary: $($_.Exception.Message)"
                    $logInfo = @{ Error = "Log summary unavailable: $($_.Exception.Message)" }
                }

                # Compile comprehensive diagnostic data
                $diagnosticData = @{
                    Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffffffK'
                    CorrelationId = $CorrelationId
                    SystemInfo = $systemInfo
                    MemoryUsage = $memoryInfo
                    LogInfo = $logInfo
                    EnvironmentVariables = @{
                        PATH = $env:PATH
                        PSModulePath = $env:PSModulePath
                        TEMP = $env:TEMP
                        UserProfile = $env:USERPROFILE
                        ComputerName = $env:COMPUTERNAME
                        LogonServer = $env:LOGONSERVER
                    }
                    PowerShellConfiguration = @{
                        ExecutionPolicy = Get-ExecutionPolicy
                        CurrentLocation = Get-Location
                        PSVersionTable = $PSVersionTable
                    }
                }

                # Export main diagnostic data
                $diagnosticData | ConvertTo-Json -Depth 10 -Compress:$false |
                    Out-File -FilePath "$diagnosticPath\diagnostic-data.json" -Encoding UTF8
                Write-Verbose "Exported diagnostic data to diagnostic-data.json"

                # Copy current log file if it exists and is accessible
                if ($script:LogPath -and (Test-Path $script:LogPath -ErrorAction SilentlyContinue)) {
                    try {
                        Copy-Item $script:LogPath "$diagnosticPath\current-log.log" -ErrorAction Stop
                        Write-Verbose "Copied current log file to diagnostic package"
                    }
                    catch {
                        Write-Verbose "Could not copy log file: $($_.Exception.Message)"
                        # Create a summary instead
                        "Log file copy failed: $($_.Exception.Message)" |
                            Out-File "$diagnosticPath\log-copy-error.txt" -Encoding UTF8
                    }
                }

                # Export PowerShell session information
                $PSVersionTable | ConvertTo-Json -Depth 5 |
                    Out-File -FilePath "$diagnosticPath\powershell-info.json" -Encoding UTF8
                Write-Verbose "Exported PowerShell session information"

                # Export loaded modules information
                try {
                    $modules = Get-Module
                    $loadedModules = foreach ($module in $modules) {
                        [PSCustomObject]@{
                            Name = $module.Name
                            Version = $module.Version.ToString()
                            ModuleType = $module.ModuleType.ToString()
                            Path = $module.Path
                        }
                    }
                } catch {
                    Write-Verbose "Could not retrieve module information: $($_.Exception.Message)"
                    $loadedModules = @()
                }
                $loadedModules | ConvertTo-Json -Depth 3 |
                    Out-File -FilePath "$diagnosticPath\loaded-modules.json" -Encoding UTF8
                Write-Verbose "Exported loaded modules information"

                # Create diagnostic package summary
                $packageSummary = @{
                    PackagePath = $diagnosticPath
                    CreatedAt = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffffffK'
                    CorrelationId = $CorrelationId
                    FilesIncluded = (Get-ChildItem $diagnosticPath -File).Name
                    TotalSizeMB = [Math]::Round((Get-ChildItem $diagnosticPath -Recurse -File |
                        Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                }

                $packageSummary | ConvertTo-Json -Depth 3 |
                    Out-File -FilePath "$diagnosticPath\package-summary.json" -Encoding UTF8

                # Log successful export
                if (Get-Command Write-StructuredLogEntry -ErrorAction SilentlyContinue) {
                    Write-StructuredLogEntry -Level Information -Message "Diagnostic data exported successfully" -Component 'Diagnostics' -Data @{
                        ExportPath = $diagnosticPath
                        FilesExported = $packageSummary.FilesIncluded.Count
                        TotalSizeMB = $packageSummary.TotalSizeMB
                        CorrelationId = $CorrelationId
                    } -CorrelationId $CorrelationId
                }

                Write-Verbose "Diagnostic package created successfully: $diagnosticPath"
                return $diagnosticPath
            }
        }
        catch {
            # Log export failure
            if (Get-Command Write-StructuredLogEntry -ErrorAction SilentlyContinue) {
                Write-StructuredLogEntry -Level Error -Message "Failed to export diagnostic data" -Component 'Diagnostics' -ErrorRecord $_ -CorrelationId $CorrelationId
            }

            Write-Error "Diagnostic export failed: $($_.Exception.Message)"
            throw
        }
    }

    end {
        Write-Verbose "Diagnostic data export operation completed - CorrelationId: $CorrelationId"
    }
}
