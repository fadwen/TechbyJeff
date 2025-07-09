#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
. $testBootstrapper
}
# Mock external dependencies
function Write-StructuredLog { param($Level, $Message, $Details = @{}, $CorrelationId) }
function Write-Verbose { param($Message) }
function Write-Information { param($MessageData, $Tags) }
function Write-Host { param($Object, $ForegroundColor) }
# Mock file system operations
function Test-Path { param($Path, $PathType) return $true }
function Get-Content { param($Path) return @("Sample log entry 1", "Sample log entry 2") }
function Get-ChildItem { param($Path, $Filter, $Recurse) return @() }
function Get-Item { param($Path) return @{ FullName = $Path; Length = 1024; LastWriteTime = (Get-Date) } }
function Out-File { param($InputObject, $FilePath, $Append, $Encoding) }
function Export-Csv { param($InputObject, $Path, $NoTypeInformation) }
function ConvertTo-Json { param($InputObject, $Depth) return "{'test':'json'}" }
function ConvertTo-Html { param($InputObject, $Title, $Head) return "<html><body>Test Report</body></html>" }
# Mock compression operations
function Compress-Archive { param($Path, $DestinationPath, $CompressionLevel) }
# Import Reporting module functions for testing
$ReportingModulePath = Join-Path $PSScriptRoot '..\..\Private\Reporting'
Get-LogFileSummary -Path $ReportingModulePath -Filter '*.ps1' | ForEach-Object {
. #Requires -Module Pester


    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Mock external dependencies
    function Write-StructuredLog { param($Level, $Message, $Details = @{}, $CorrelationId) }
    function Write-Verbose { param($Message) }
    function Write-Information { param($MessageData, $Tags) }
    function Write-Host { param($Object, $ForegroundColor) }

    # Mock file system operations
    function Test-Path { param($Path, $PathType) return $true }
    function Get-Content { param($Path) return @("Sample log entry 1", "Sample log entry 2") }
    function Get-ChildItem { param($Path, $Filter, $Recurse) return @() }
    function Get-Item { param($Path) return @{ FullName = $Path; Length = 1024; LastWriteTime = (Get-Date) } }
    function Out-File { param($InputObject, $FilePath, $Append, $Encoding) }
    function Export-Csv { param($InputObject, $Path, $NoTypeInformation) }
    function ConvertTo-Json { param($InputObject, $Depth) return "{'test':'json'}" }
    function ConvertTo-Html { param($InputObject, $Title, $Head) return "<html><body>Test Report</body></html>" }

    # Mock compression operations
    function Compress-Archive { param($Path, $DestinationPath, $CompressionLevel) }

    # Import Reporting module functions for testing
    $ReportingModulePath = Join-Path $PSScriptRoot '..\..\Private\Reporting'
    Get-LogFileSummary -Path $ReportingModulePath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

Describe "Write-ProcessingSummary" -Tag "Unit", "Reporting", "Summary" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestStatistics = @{
            ObjectsProcessed = 150
            OrphanedSIDsFound = 25
            SIDsRemoved = 20
            ErrorsEncountered = 2
            ProcessingTimeMinutes = 15.5
            StartTime = (Get-Date).AddMinutes(-16)
            EndTime = Get-Date
        }
    }

    Context "Parameter Validation" {
        It "Should require Statistics parameter" {
            { Write-ProcessingSummary } | Should Throw "*Statistics*"
        }

        It "Should accept hashtable statistics" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics } | Should Not Throw
        }

        It "Should accept output format parameter" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Console" } | Should Not Throw
        }

        It "Should validate output format values" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "InvalidFormat" } | Should Throw "*OutputFormat*"
        }
    }

    Context "Core Functionality" {
        It "Should generate console summary" {
            Mock Write-Host { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Console"

            $result | Should Not BeNullOrEmpty
            $result.Format | Should Be "Console"
            Should Invoke Write-Host -AtLeast 1
        }

        It "Should generate file-based summary" {
            Mock Out-File { }
            $outputPath = "C:\reports\summary.txt"

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "File" -OutputPath $outputPath

            $result.OutputPath | Should Be $outputPath
            Should Invoke Out-File -ParameterFilter { $FilePath -eq $outputPath } -Exactly 1
        }

        It "Should generate JSON summary" {
            Mock ConvertTo-Json { return '{"ObjectsProcessed": 150}' }
            Mock Out-File { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "JSON"

            $result.Format | Should Be "JSON"
            Should Invoke ConvertTo-Json -Exactly 1
        }

        It "Should generate HTML summary" {
            Mock ConvertTo-Html { return "<html><body>Summary Report</body></html>" }
            Mock Out-File { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "HTML"

            $result.Format | Should Be "HTML"
            Should Invoke ConvertTo-Html -Exactly 1
        }

        It "Should calculate processing efficiency metrics" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -IncludeMetrics

            $result.Metrics | Should Not BeNullOrEmpty
            $result.Metrics.SuccessRate | Should BeGreaterThan 0
            $result.Metrics.ObjectsPerMinute | Should BeGreaterThan 0
            $result.Metrics.EfficiencyScore | Should BeGreaterThan 0
        }

        It "Should include performance statistics" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -IncludePerformance

            $result.Performance | Should Not BeNullOrEmpty
            $result.Performance.TotalProcessingTime | Should Not BeNullOrEmpty
            $result.Performance.AverageTimePerObject | Should Not BeNullOrEmpty
            $result.Performance.ThroughputRate | Should Not BeNullOrEmpty
        }

        It "Should support custom summary templates" {
            $customTemplate = @"
Processing Summary for {CorrelationId}
Objects Processed: {ObjectsProcessed}
Success Rate: {SuccessRate}%
"@

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -Template $customTemplate -CorrelationId $script:TestCorrelationId

            $result.RenderedContent | Should Match $script:TestCorrelationId
            $result.RenderedContent | Should Match "150"  # ObjectsProcessed
        }
    }

    Context "Data Analysis and Insights" {
        It "Should identify performance bottlenecks" {
            $slowStatistics = @{
                ObjectsProcessed = 10
                ProcessingTimeMinutes = 60  # Very slow
                ErrorsEncountered = 5
            }

            $result = Write-ProcessingSummary -Statistics $slowStatistics -AnalyzePerformance

            $result.Analysis.PerformanceIssues | Should Not BeNullOrEmpty
            $result.Analysis.Recommendations | Should Not BeNullOrEmpty
        }

        It "Should provide optimization recommendations" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -ProvideRecommendations

            $result.Recommendations | Should Not BeNullOrEmpty
            $result.Recommendations | Should BeOfType [array]
        }

        It "Should compare against historical baselines" {
            $historicalData = @{
                AverageObjectsPerMinute = 8
                AverageSuccessRate = 0.95
                AverageErrorRate = 0.05
            }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -HistoricalBaseline $historicalData

            $result.Comparison | Should Not BeNullOrEmpty
            $result.Comparison.PerformanceVariance | Should Not BeNullOrEmpty
        }

        It "Should detect anomalies in processing patterns" {
            $anomalousStatistics = @{
                ObjectsProcessed = 150
                OrphanedSIDsFound = 100  # Unusually high percentage
                ErrorsEncountered = 50   # Unusually high error rate
                ProcessingTimeMinutes = 5  # Unusually fast despite errors
            }

            $result = Write-ProcessingSummary -Statistics $anomalousStatistics -DetectAnomalies

            $result.Anomalies | Should Not BeNullOrEmpty
            $result.Anomalies | Should Contain "*high error rate*"
        }
    }

    Context "Multiple Output Formats" {
        It "Should support multiple simultaneous outputs" {
            Mock Write-Host { }
            Mock Out-File { }
            Mock ConvertTo-Json { return '{}' }

            $outputFormats = @("Console", "File", "JSON")
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat $outputFormats -OutputPath "C:\reports\"

            $result | Should -HaveCount 3
            Should Invoke Write-Host -AtLeast 1
            Should Invoke Out-File -AtLeast 2
        }

        It "Should generate email-ready summary" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Email"

            $result.EmailSubject | Should Not BeNullOrEmpty
            $result.EmailBody | Should Not BeNullOrEmpty
            $result.EmailBody | Should Match "150 objects"  # Should include key statistics
        }

        It "Should create dashboard-compatible output" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Dashboard"

            $result.DashboardData | Should Not BeNullOrEmpty
            $result.DashboardData.Metrics | Should Not BeNullOrEmpty
            $result.DashboardData.Charts | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle missing statistics gracefully" {
            $incompleteStats = @{ ObjectsProcessed = 10 }

            $result = Write-ProcessingSummary -Statistics $incompleteStats -ErrorAction Continue

            $result | Should Not BeNullOrEmpty
            $result.Warnings | Should Contain "*missing statistics*"
        }

        It "Should handle file write errors" {
            Mock Out-File { throw "Access denied" }

            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "File" -OutputPath "C:\restricted\summary.txt" } | Should Throw "*Access denied*"
        }

        It "Should provide fallback when template processing fails" {
            $invalidTemplate = "{InvalidPlaceholder}"

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -Template $invalidTemplate -ErrorAction Continue

            $result.RenderedContent | Should Not BeNullOrEmpty
            $result.UsedFallbackTemplate | Should Be $true
        }
    }

    Context "Security and Compliance" {
        It "Should sanitize sensitive information" {
            $sensitiveStats = @{
                ObjectsProcessed = 150
                UserName = "admin@company.com"
                ServerName = "DC01.internal.company.com"
            }

            $result = Write-ProcessingSummary -Statistics $sensitiveStats | Should Not Match "admin@company.com"
            $result.RenderedContent | Should Not Match "DC01.internal.company.com"
        }

        It "Should log summary generation with correlation ID" {
            Mock Write-StructuredLog { }

            Write-ProcessingSummary -Statistics $script:TestStatistics -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*summary generated*" }
        }
    }

Describe "Export-DiagnosticData" -Tag "Unit", "Reporting", "Diagnostics" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestOutputPath = "C:\diagnostics\export.zip"
    }

    Context "Parameter Validation" {
        It "Should require OutputPath parameter" {
            { Export-DiagnosticData } | Should Throw "*OutputPath*"
        }

        It "Should accept valid output path" {
            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Not Throw
        }

        It "Should accept data sources parameter" {
            $dataSources = @("Logs", "Configuration", "Statistics")
            { Export-DiagnosticData -OutputPath $script:TestOutputPath  } | Should Not Throw
        }

        It "Should validate data source values" {
            { Export-DiagnosticData -OutputPath $script:TestOutputPath  } | Should Throw "*DataSources*"
        }
    }

    Context "Core Functionality" {
        It "Should export all diagnostic data by default" {
            Mock Get-ChildItem { return @(@{ FullName = "log1.txt" }, @{ FullName = "log2.txt" }) }
            Mock Get-Content { return @("Log entry 1", "Log entry 2") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result | Should Not BeNullOrEmpty
            $result.ExportPath | Should Be $script:TestOutputPath
            $result.DataSources | Should Contain "Logs"
            $result.DataSources | Should Contain "Configuration"
            Should Invoke Compress-Archive -Exactly 1
        }

        It "Should export selected data sources only" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            $selectedSources = @("Logs", "Statistics")

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.DataSources | Should Be $selectedSources
            $result.DataSources | Should Not Contain "Configuration"
        }

        It "Should include system information" {
            Mock Get-ComputerInfo { return @{ TotalPhysicalMemory = 8GB; ProcessorCount = 4 } }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Not BeNullOrEmpty
            $result.SystemInfo.TotalMemory | Should Not BeNullOrEmpty
            $result.SystemInfo.ProcessorCount | Should Be 4
        }

        It "Should export log files with filtering" {
            $mockLogFiles = @(
                @{ FullName = "C:\logs\info.log"; LastWriteTime = (Get-Date) },
                @{ FullName = "C:\logs\error.log"; LastWriteTime = (Get-Date).AddDays(-5) },
                @{ FullName = "C:\logs\old.log"; LastWriteTime = (Get-Date).AddDays(-10) }
            )
            Mock Get-ChildItem { return $mockLogFiles }
            Mock Get-Content { return @("Log entries") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -MaxAgeDays 7

            $result.LogFiles | Should -HaveCount 2  # Should exclude old.log
        }

        It "Should export configuration files" {
            $mockConfigFiles = @(
                @{ FullName = "C:\config\app.config"; Length = 1024 },
                @{ FullName = "C:\config\settings.json"; Length = 512 }
            )
            Mock Get-ChildItem { return $mockConfigFiles } -ParameterFilter { $Path -like "*config*" }
            Mock Get-Content { return @("Configuration data") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.ConfigurationFiles | Should -HaveCount 2
            $result.ConfigurationFiles[0].FullName | Should Be "C:\config\app.config"
        }

        It "Should export performance statistics" {
            $mockStatistics = @{
                ProcessingMetrics = @{ ObjectsPerSecond = 5.2; MemoryUsageMB = 256 }
                ErrorRates = @{ ValidationErrors = 0.02; ProcessingErrors = 0.01 }
            }
            Mock Get-PerformanceStatistics { return $mockStatistics }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.Statistics | Should Not BeNullOrEmpty
            $result.Statistics.ProcessingMetrics | Should Not BeNullOrEmpty
        }
    }

    Context "Advanced Export Features" {
        It "Should apply data compression levels" {
            Mock Get-ChildItem { return @(@{ FullName = "large_file.log" }) }
            Mock Get-Content { return (1..1000 | ForEach-Object { "Large log entry $_" }) }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            Should Invoke Compress-Archive -ParameterFilter { $CompressionLevel -eq "Optimal" } -Exactly 1
            $result.CompressionRatio | Should BeGreaterThan 0
        }

        It "Should encrypt sensitive diagnostic data" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            Mock Protect-CmsMessage { return "Encrypted data" }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -EncryptSensitive -CertificateThumbprint "ABC123"

            $result.EncryptionApplied | Should Be $true
            $result.CertificateUsed | Should Be "ABC123"
        }

        It "Should include environment variables" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            $envVars = @{ "PATH" = "C:\Windows\System32"; "TEMP" = "C:\Temp" }
            Mock Get-ChildItem { return $envVars } -ParameterFilter { $Path -eq "Env:" }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Not BeNullOrEmpty
        }

        It "Should export event logs" {
            $mockEvents = @(
                @{ TimeCreated = (Get-Date); LevelDisplayName = "Error"; Message = "Test error" },
                @{ TimeCreated = (Get-Date); LevelDisplayName = "Warning"; Message = "Test warning" }
            )
            Mock Get-WinEvent { return $mockEvents }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -IncludeEventLogs -EventLogNames @("Application", "System")

            $result.EventLogEntries | Should -HaveCount 2
        }

        It "Should support incremental exports" {
            $lastExportTime = (Get-Date).AddHours(-2)
            Mock Get-ChildItem {
                return @(
                    @{ FullName = "new_file.log"; LastWriteTime = (Get-Date) },
                    @{ FullName = "old_file.log"; LastWriteTime = (Get-Date).AddHours(-3) }
                )
            }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.FilesIncluded | Should -HaveCount 1  # Only new_file.log
            $result.FilesIncluded[0].FullName | Should Be "new_file.log"
        }
    }

    Context "Error Handling and Recovery" {
        It "Should handle missing data sources gracefully" {
            Mock Get-ChildItem { return @() }  # No files found
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -ErrorAction Continue

            $result | Should Not BeNullOrEmpty
            $result.Warnings | Should Contain "*no data found*"
        }

        It "Should handle file access errors" {
            Mock Get-ChildItem { throw "Access denied" }

            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Throw "*Access denied*"
        }

        It "Should handle compression failures" {
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return @("Test data") }
            Mock Compress-Archive { throw "Compression failed" }

            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Throw "*Compression failed*"
        }

        It "Should provide detailed error information" {
            Mock Get-ChildItem {
                if ($Path -like "*logs*") {
                    throw "Log directory access denied"
                }
                return @()
            }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -ErrorAction Continue

            $result.Errors | Should Not BeNullOrEmpty
            $result.Errors | Should Contain "*Log directory access denied*"
        }
    }

    Context "Security and Compliance" {
        It "Should sanitize sensitive information in exports" {
            $sensitiveLogContent = @(
                "User password: secret123",
                "API key: abc123xyz789",
                "Connection string: server=db.company.com;user=admin;password=pass123"
            )
            Mock Get-ChildItem { return @(@{ FullName = "sensitive.log" }) }
            Mock Get-Content { return $sensitiveLogContent }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Be $true
            $result.SensitiveItemsFound | Should BeGreaterThan 0
        }

        It "Should log export operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }

            Export-DiagnosticData -OutputPath $script:TestOutputPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*diagnostic export*" }
        }

        It "Should validate export integrity" {
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return @("Test data") }
            Mock Compress-Archive { }
            Mock Get-FileHash { return @{ Hash = "ABC123DEF456" } }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Be "ABC123DEF456"
            $result.IntegrityValidated | Should Be $true
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large diagnostic exports efficiently" {
            $largeFileSet = 1..100 | ForEach-Object { @{ FullName = "file$_.log"; Length = 1MB } }
            Mock Get-ChildItem { return $largeFileSet }
            Mock Get-Content { return @("Large file content") }
            Mock Compress-Archive { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $result.FilesProcessed | Should Be 100
        }

        It "Should support parallel processing for large exports" {
            Mock Get-ChildItem { return (1..50 | ForEach-Object { @{ FullName = "file$_.log" } }) }
            Mock Get-Content { return @("Content") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -UseParallelProcessing -MaxParallelJobs 4

            $result.ParallelProcessingUsed | Should Be $true
            $result.MaxParallelJobs | Should Be 4
        }
    }

Describe "Get-LogFileSummary" -Tag "Unit", "Reporting", "Analysis" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestLogPath = "C:\logs"
    }

    Context "Parameter Validation" {
        It "Should work without parameters" {
            Mock Get-LoggingSystemState { return @{ LogPath = $script:TestLogPath } }
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ Length = 1024; CreationTime = (Get-Date); LastWriteTime = (Get-Date); LastAccessTime = (Get-Date) } }
            Mock Get-Content { return @("INFO: Test message") }

            { Get-LogFileSummary } | Should Not Throw
        }

        It "Should handle missing log file gracefully" {
            Mock Get-LoggingSystemState { return @{ LogPath = $script:TestLogPath } }
            Mock Test-Path { return $false }

            $result = Get-LogFileSummary
            $result | Should BeNullOrEmpty
        }
    }

    Context "Core Functionality" {
        It "Should analyze log file structure and content" {
            $mockLogFiles = @(
                @{ FullName = "C:\logs\info.log"; Length = 1024; LastWriteTime = (Get-Date) },
                @{ FullName = "C:\logs\error.log"; Length = 2048; LastWriteTime = (Get-Date).AddHours(-1) }
            )
            Mock Get-ChildItem { return $mockLogFiles }
            Mock Get-Content { return @("INFO: Test message", "ERROR: Test error", "WARNING: Test warning") }

            $result = Get-LogFileSummary

            $result | Should Not BeNullOrEmpty
            $result.TotalFiles | Should Be 2
            $result.TotalSizeBytes | Should Be 3072
            $result.LogLevelCounts | Should Not BeNullOrEmpty
        }

        It "Should categorize log entries by level" {
            $logEntries = @(
                "2025-01-24 10:00:00 INFO: Application started",
                "2025-01-24 10:01:00 ERROR: Database connection failed",
                "2025-01-24 10:02:00 WARNING: Memory usage high",
                "2025-01-24 10:03:00 INFO: Processing completed",
                "2025-01-24 10:04:00 ERROR: File not found"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $logEntries }

            $result = Get-LogFileSummary

            $result.LogLevelCounts.INFO | Should Be 2
            $result.LogLevelCounts.ERROR | Should Be 2
            $result.LogLevelCounts.WARNING | Should Be 1
        }

        It "Should identify patterns and trends" {
            $timeBasedEntries = @(
                "2025-01-24 08:00:00 ERROR: Morning error",
                "2025-01-24 14:00:00 ERROR: Afternoon error",
                "2025-01-24 20:00:00 ERROR: Evening error"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $timeBasedEntries }

            $result = Get-LogFileSummary -AnalyzePatterns

            $result.Patterns | Should Not BeNullOrEmpty
            $result.Patterns.ErrorDistribution | Should Not BeNullOrEmpty
        }

        It "Should generate timeline analysis" {
            $chronologicalEntries = @(
                "2025-01-24 10:00:00 INFO: Start",
                "2025-01-24 10:30:00 WARNING: Issue detected",
                "2025-01-24 11:00:00 ERROR: Critical failure",
                "2025-01-24 11:30:00 INFO: Recovery initiated"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $chronologicalEntries }

            $result = Get-LogFileSummary -IncludeTimeline

            $result.Timeline | Should Not BeNullOrEmpty
            $result.Timeline | Should -HaveCount 4
            $result.Timeline[0].Timestamp | Should Match "10:00:00"
        }

        It "Should detect anomalies and outliers" {
            $anomalousEntries = @(
                "2025-01-24 10:00:00 INFO: Normal operation",
                "2025-01-24 10:01:00 ERROR: Unusual error pattern XYZABC123",
                "2025-01-24 10:02:00 INFO: Normal operation",
                "2025-01-24 10:03:00 CRITICAL: System failure with stack trace..."
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $anomalousEntries }

            $result = Get-LogFileSummary -DetectAnomalies

            $result.Anomalies | Should Not BeNullOrEmpty
            $result.Anomalies | Should Contain "*CRITICAL*"
        }
    }

    Context "Advanced Analysis Features" {
        It "Should perform correlation analysis across multiple log files" {
            $logFile1 = @("2025-01-24 10:00:00 INFO: User login attempt", "2025-01-24 10:01:00 ERROR: Authentication failed")
            $logFile2 = @("2025-01-24 10:00:30 INFO: Database query", "2025-01-24 10:01:30 ERROR: Connection timeout")

            Mock Get-ChildItem { return @(@{ FullName = "app.log" }, @{ FullName = "db.log" }) }
            Mock Get-Content {
                param($Path)
                if ($Path -like "*app.log") { return $logFile1 }
                if ($Path -like "*db.log") { return $logFile2 }
            }

            $result = Get-LogFileSummary -CorrelateAcrossFiles

            $result.Correlations | Should Not BeNullOrEmpty
            $result.Correlations.TimeBasedCorrelations | Should Not BeNullOrEmpty
        }

        It "Should generate performance metrics from log data" {
            $performanceEntries = @(
                "2025-01-24 10:00:00 INFO: Operation started",
                "2025-01-24 10:00:05 INFO: Operation completed in 5000ms",
                "2025-01-24 10:01:00 INFO: Operation started",
                "2025-01-24 10:01:02 INFO: Operation completed in 2000ms"
            )
            Mock Get-ChildItem { return @(@{ FullName = "perf.log" }) }
            Mock Get-Content { return $performanceEntries }

            $result = Get-LogFileSummary -ExtractPerformanceMetrics

            $result.PerformanceMetrics | Should Not BeNullOrEmpty
            $result.PerformanceMetrics.AverageResponseTime | Should Not BeNullOrEmpty
        }

        It "Should identify security-related events" {
            $securityEntries = @(
                "2025-01-24 10:00:00 INFO: User login successful",
                "2025-01-24 10:01:00 WARNING: Multiple failed login attempts",
                "2025-01-24 10:02:00 ERROR: Unauthorized access attempt",
                "2025-01-24 10:03:00 CRITICAL: Potential security breach detected"
            )
            Mock Get-ChildItem { return @(@{ FullName = "security.log" }) }
            Mock Get-Content { return $securityEntries }

            $result = Get-LogFileSummary -IdentifySecurityEvents

            $result.SecurityEvents | Should Not BeNullOrEmpty
            $result.SecurityEvents.PotentialThreats | Should Not BeNullOrEmpty
            $result.SecurityEvents.FailedLogins | Should BeGreaterThan 0
        }

        It "Should support custom log parsing patterns" {
            $customLogEntries = @(
                "[2025-01-24 10:00:00] [INFO] [USER:john.doe] Login successful",
                "[2025-01-24 10:01:00] [ERROR] [USER:jane.smith] Access denied",
                "[2025-01-24 10:02:00] [WARNING] [SYSTEM] Memory usage: 85%"
            )
            $customPattern = @{
                TimestampPattern = '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]'
                LevelPattern = '\[(\w+)\]'
                UserPattern = '\[USER:([^\]]+)\]'
            }
            Mock Get-ChildItem { return @(@{ FullName = "custom.log" }) }
            Mock Get-Content { return $customLogEntries }

            $result = Get-LogFileSummary -CustomParsingPattern $customPattern

            $result.ParsedEntries | Should -HaveCount 3
            $result.ParsedEntries[0].User | Should Be "john.doe"
            $result.ParsedEntries[1].User | Should Be "jane.smith"
        }
    }

    Context "Error Handling and Robustness" {
        It "Should handle corrupted log files gracefully" {
            Mock Get-ChildItem { return @(@{ FullName = "corrupted.log" }) }
            Mock Get-Content { throw "File is corrupted" }

            $result = Get-LogFileSummary -ErrorAction Continue

            $result.Errors | Should Contain "*corrupted*"
            $result.FilesProcessed | Should Be 0
        }

        It "Should handle very large log files efficiently" {
            Mock Get-ChildItem { return @(@{ FullName = "large.log"; Length = 1GB }) }
            Mock Get-Content {
                # Simulate reading large file in chunks
                return (1..1000 | ForEach-Object { "Large log entry $_" })
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-LogFileSummary -UseStreamingRead
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 3000
            $result.ProcessingMethod | Should Be "Streaming"
        }

        It "Should handle empty log directories" {
            Mock Get-ChildItem { return @() }

            $result = Get-LogFileSummary

            $result.TotalFiles | Should Be 0
            $result.Summary | Should Match "*no log files found*"
        }
    }

    Context "Performance and Scalability" {
        It "Should process multiple log files efficiently" {
            $multipleLogFiles = 1..20 | ForEach-Object { @{ FullName = "log$_.txt"; Length = 1024 } }
            Mock Get-ChildItem { return $multipleLogFiles }
            Mock Get-Content { return @("INFO: Test entry") }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-LogFileSummary
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.TotalFiles | Should Be 20
        }

        It "Should support parallel processing for large log sets" {
            Mock Get-ChildItem { return (1..50 | ForEach-Object { @{ FullName = "log$_.txt" } }) }
            Mock Get-Content { return @("INFO: Parallel processing test") }

            $result = Get-LogFileSummary | Should Be "Parallel"
            $result.TotalFiles | Should Be 50
        }
    }

    Context "Audit and Compliance" {
        It "Should log analysis operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Get-LogFileSummary -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*log analysis*" }
        }

        It "Should generate compliance reports" {
            $complianceEntries = @(
                "2025-01-24 10:00:00 AUDIT: Data access by user john.doe",
                "2025-01-24 10:01:00 AUDIT: Configuration changed by admin",
                "2025-01-24 10:02:00 COMPLIANCE: GDPR data processing logged"
            )
            Mock Get-ChildItem { return @(@{ FullName = "audit.log" }) }
            Mock Get-Content { return $complianceEntries }

            $result = Get-LogFileSummary -GenerateComplianceReport -ComplianceFramework "GDPR"

            $result.ComplianceReport | Should Not BeNullOrEmpty
            $result.ComplianceReport.Framework | Should Be "GDPR"
            $result.ComplianceReport.AuditEntries | Should BeGreaterThan 0
        }
    }
}

}

.FullName

Describe "Write-ProcessingSummary" -Tag "Unit", "Reporting", "Summary" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestStatistics = @{
            ObjectsProcessed = 150
            OrphanedSIDsFound = 25
            SIDsRemoved = 20
            ErrorsEncountered = 2
            ProcessingTimeMinutes = 15.5
            StartTime = (Get-Date).AddMinutes(-16)
            EndTime = Get-Date
        }
    }

    Context "Parameter Validation" {
        It "Should require Statistics parameter" {
            { Write-ProcessingSummary } | Should Throw "*Statistics*"
        }

        It "Should accept hashtable statistics" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics } | Should Not Throw
        }

        It "Should accept output format parameter" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Console" } | Should Not Throw
        }

        It "Should validate output format values" {
            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "InvalidFormat" } | Should Throw "*OutputFormat*"
        }
    }

    Context "Core Functionality" {
        It "Should generate console summary" {
            Mock Write-Host { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Console"

            $result | Should Not BeNullOrEmpty
            $result.Format | Should Be "Console"
            Should Invoke Write-Host -AtLeast 1
        }

        It "Should generate file-based summary" {
            Mock Out-File { }
            $outputPath = "C:\reports\summary.txt"

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "File" -OutputPath $outputPath

            $result.OutputPath | Should Be $outputPath
            Should Invoke Out-File -ParameterFilter { $FilePath -eq $outputPath } -Exactly 1
        }

        It "Should generate JSON summary" {
            Mock ConvertTo-Json { return '{"ObjectsProcessed": 150}' }
            Mock Out-File { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "JSON"

            $result.Format | Should Be "JSON"
            Should Invoke ConvertTo-Json -Exactly 1
        }

        It "Should generate HTML summary" {
            Mock ConvertTo-Html { return "<html><body>Summary Report</body></html>" }
            Mock Out-File { }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "HTML"

            $result.Format | Should Be "HTML"
            Should Invoke ConvertTo-Html -Exactly 1
        }

        It "Should calculate processing efficiency metrics" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -IncludeMetrics

            $result.Metrics | Should Not BeNullOrEmpty
            $result.Metrics.SuccessRate | Should BeGreaterThan 0
            $result.Metrics.ObjectsPerMinute | Should BeGreaterThan 0
            $result.Metrics.EfficiencyScore | Should BeGreaterThan 0
        }

        It "Should include performance statistics" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -IncludePerformance

            $result.Performance | Should Not BeNullOrEmpty
            $result.Performance.TotalProcessingTime | Should Not BeNullOrEmpty
            $result.Performance.AverageTimePerObject | Should Not BeNullOrEmpty
            $result.Performance.ThroughputRate | Should Not BeNullOrEmpty
        }

        It "Should support custom summary templates" {
            $customTemplate = @"
Processing Summary for {CorrelationId}
Objects Processed: {ObjectsProcessed}
Success Rate: {SuccessRate}%
"@

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -Template $customTemplate -CorrelationId $script:TestCorrelationId

            $result.RenderedContent | Should Match $script:TestCorrelationId
            $result.RenderedContent | Should Match "150"  # ObjectsProcessed
        }
    }

    Context "Data Analysis and Insights" {
        It "Should identify performance bottlenecks" {
            $slowStatistics = @{
                ObjectsProcessed = 10
                ProcessingTimeMinutes = 60  # Very slow
                ErrorsEncountered = 5
            }

            $result = Write-ProcessingSummary -Statistics $slowStatistics -AnalyzePerformance

            $result.Analysis.PerformanceIssues | Should Not BeNullOrEmpty
            $result.Analysis.Recommendations | Should Not BeNullOrEmpty
        }

        It "Should provide optimization recommendations" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -ProvideRecommendations

            $result.Recommendations | Should Not BeNullOrEmpty
            $result.Recommendations | Should BeOfType [array]
        }

        It "Should compare against historical baselines" {
            $historicalData = @{
                AverageObjectsPerMinute = 8
                AverageSuccessRate = 0.95
                AverageErrorRate = 0.05
            }

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -HistoricalBaseline $historicalData

            $result.Comparison | Should Not BeNullOrEmpty
            $result.Comparison.PerformanceVariance | Should Not BeNullOrEmpty
        }

        It "Should detect anomalies in processing patterns" {
            $anomalousStatistics = @{
                ObjectsProcessed = 150
                OrphanedSIDsFound = 100  # Unusually high percentage
                ErrorsEncountered = 50   # Unusually high error rate
                ProcessingTimeMinutes = 5  # Unusually fast despite errors
            }

            $result = Write-ProcessingSummary -Statistics $anomalousStatistics -DetectAnomalies

            $result.Anomalies | Should Not BeNullOrEmpty
            $result.Anomalies | Should Contain "*high error rate*"
        }
    }

    Context "Multiple Output Formats" {
        It "Should support multiple simultaneous outputs" {
            Mock Write-Host { }
            Mock Out-File { }
            Mock ConvertTo-Json { return '{}' }

            $outputFormats = @("Console", "File", "JSON")
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat $outputFormats -OutputPath "C:\reports\"

            $result | Should -HaveCount 3
            Should Invoke Write-Host -AtLeast 1
            Should Invoke Out-File -AtLeast 2
        }

        It "Should generate email-ready summary" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Email"

            $result.EmailSubject | Should Not BeNullOrEmpty
            $result.EmailBody | Should Not BeNullOrEmpty
            $result.EmailBody | Should Match "150 objects"  # Should include key statistics
        }

        It "Should create dashboard-compatible output" {
            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "Dashboard"

            $result.DashboardData | Should Not BeNullOrEmpty
            $result.DashboardData.Metrics | Should Not BeNullOrEmpty
            $result.DashboardData.Charts | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle missing statistics gracefully" {
            $incompleteStats = @{ ObjectsProcessed = 10 }

            $result = Write-ProcessingSummary -Statistics $incompleteStats -ErrorAction Continue

            $result | Should Not BeNullOrEmpty
            $result.Warnings | Should Contain "*missing statistics*"
        }

        It "Should handle file write errors" {
            Mock Out-File { throw "Access denied" }

            { Write-ProcessingSummary -Statistics $script:TestStatistics -OutputFormat "File" -OutputPath "C:\restricted\summary.txt" } | Should Throw "*Access denied*"
        }

        It "Should provide fallback when template processing fails" {
            $invalidTemplate = "{InvalidPlaceholder}"

            $result = Write-ProcessingSummary -Statistics $script:TestStatistics -Template $invalidTemplate -ErrorAction Continue

            $result.RenderedContent | Should Not BeNullOrEmpty
            $result.UsedFallbackTemplate | Should Be $true
        }
    }

    Context "Security and Compliance" {
        It "Should sanitize sensitive information" {
            $sensitiveStats = @{
                ObjectsProcessed = 150
                UserName = "admin@company.com"
                ServerName = "DC01.internal.company.com"
            }

            $result = Write-ProcessingSummary -Statistics $sensitiveStats | Should Not Match "admin@company.com"
            $result.RenderedContent | Should Not Match "DC01.internal.company.com"
        }

        It "Should log summary generation with correlation ID" {
            Mock Write-StructuredLog { }

            Write-ProcessingSummary -Statistics $script:TestStatistics -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*summary generated*" }
        }
    }

Describe "Export-DiagnosticData" -Tag "Unit", "Reporting", "Diagnostics" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestOutputPath = "C:\diagnostics\export.zip"
    }

    Context "Parameter Validation" {
        It "Should require OutputPath parameter" {
            { Export-DiagnosticData } | Should Throw "*OutputPath*"
        }

        It "Should accept valid output path" {
            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Not Throw
        }

        It "Should accept data sources parameter" {
            $dataSources = @("Logs", "Configuration", "Statistics")
            { Export-DiagnosticData -OutputPath $script:TestOutputPath  } | Should Not Throw
        }

        It "Should validate data source values" {
            { Export-DiagnosticData -OutputPath $script:TestOutputPath  } | Should Throw "*DataSources*"
        }
    }

    Context "Core Functionality" {
        It "Should export all diagnostic data by default" {
            Mock Get-ChildItem { return @(@{ FullName = "log1.txt" }, @{ FullName = "log2.txt" }) }
            Mock Get-Content { return @("Log entry 1", "Log entry 2") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result | Should Not BeNullOrEmpty
            $result.ExportPath | Should Be $script:TestOutputPath
            $result.DataSources | Should Contain "Logs"
            $result.DataSources | Should Contain "Configuration"
            Should Invoke Compress-Archive -Exactly 1
        }

        It "Should export selected data sources only" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            $selectedSources = @("Logs", "Statistics")

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.DataSources | Should Be $selectedSources
            $result.DataSources | Should Not Contain "Configuration"
        }

        It "Should include system information" {
            Mock Get-ComputerInfo { return @{ TotalPhysicalMemory = 8GB; ProcessorCount = 4 } }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Not BeNullOrEmpty
            $result.SystemInfo.TotalMemory | Should Not BeNullOrEmpty
            $result.SystemInfo.ProcessorCount | Should Be 4
        }

        It "Should export log files with filtering" {
            $mockLogFiles = @(
                @{ FullName = "C:\logs\info.log"; LastWriteTime = (Get-Date) },
                @{ FullName = "C:\logs\error.log"; LastWriteTime = (Get-Date).AddDays(-5) },
                @{ FullName = "C:\logs\old.log"; LastWriteTime = (Get-Date).AddDays(-10) }
            )
            Mock Get-ChildItem { return $mockLogFiles }
            Mock Get-Content { return @("Log entries") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -MaxAgeDays 7

            $result.LogFiles | Should -HaveCount 2  # Should exclude old.log
        }

        It "Should export configuration files" {
            $mockConfigFiles = @(
                @{ FullName = "C:\config\app.config"; Length = 1024 },
                @{ FullName = "C:\config\settings.json"; Length = 512 }
            )
            Mock Get-ChildItem { return $mockConfigFiles } -ParameterFilter { $Path -like "*config*" }
            Mock Get-Content { return @("Configuration data") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.ConfigurationFiles | Should -HaveCount 2
            $result.ConfigurationFiles[0].FullName | Should Be "C:\config\app.config"
        }

        It "Should export performance statistics" {
            $mockStatistics = @{
                ProcessingMetrics = @{ ObjectsPerSecond = 5.2; MemoryUsageMB = 256 }
                ErrorRates = @{ ValidationErrors = 0.02; ProcessingErrors = 0.01 }
            }
            Mock Get-PerformanceStatistics { return $mockStatistics }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.Statistics | Should Not BeNullOrEmpty
            $result.Statistics.ProcessingMetrics | Should Not BeNullOrEmpty
        }
    }

    Context "Advanced Export Features" {
        It "Should apply data compression levels" {
            Mock Get-ChildItem { return @(@{ FullName = "large_file.log" }) }
            Mock Get-Content { return (1..1000 | ForEach-Object { "Large log entry $_" }) }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            Should Invoke Compress-Archive -ParameterFilter { $CompressionLevel -eq "Optimal" } -Exactly 1
            $result.CompressionRatio | Should BeGreaterThan 0
        }

        It "Should encrypt sensitive diagnostic data" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            Mock Protect-CmsMessage { return "Encrypted data" }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -EncryptSensitive -CertificateThumbprint "ABC123"

            $result.EncryptionApplied | Should Be $true
            $result.CertificateUsed | Should Be "ABC123"
        }

        It "Should include environment variables" {
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }
            $envVars = @{ "PATH" = "C:\Windows\System32"; "TEMP" = "C:\Temp" }
            Mock Get-ChildItem { return $envVars } -ParameterFilter { $Path -eq "Env:" }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Not BeNullOrEmpty
        }

        It "Should export event logs" {
            $mockEvents = @(
                @{ TimeCreated = (Get-Date); LevelDisplayName = "Error"; Message = "Test error" },
                @{ TimeCreated = (Get-Date); LevelDisplayName = "Warning"; Message = "Test warning" }
            )
            Mock Get-WinEvent { return $mockEvents }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -IncludeEventLogs -EventLogNames @("Application", "System")

            $result.EventLogEntries | Should -HaveCount 2
        }

        It "Should support incremental exports" {
            $lastExportTime = (Get-Date).AddHours(-2)
            Mock Get-ChildItem {
                return @(
                    @{ FullName = "new_file.log"; LastWriteTime = (Get-Date) },
                    @{ FullName = "old_file.log"; LastWriteTime = (Get-Date).AddHours(-3) }
                )
            }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath

            $result.FilesIncluded | Should -HaveCount 1  # Only new_file.log
            $result.FilesIncluded[0].FullName | Should Be "new_file.log"
        }
    }

    Context "Error Handling and Recovery" {
        It "Should handle missing data sources gracefully" {
            Mock Get-ChildItem { return @() }  # No files found
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -ErrorAction Continue

            $result | Should Not BeNullOrEmpty
            $result.Warnings | Should Contain "*no data found*"
        }

        It "Should handle file access errors" {
            Mock Get-ChildItem { throw "Access denied" }

            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Throw "*Access denied*"
        }

        It "Should handle compression failures" {
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return @("Test data") }
            Mock Compress-Archive { throw "Compression failed" }

            { Export-DiagnosticData -OutputPath $script:TestOutputPath } | Should Throw "*Compression failed*"
        }

        It "Should provide detailed error information" {
            Mock Get-ChildItem {
                if ($Path -like "*logs*") {
                    throw "Log directory access denied"
                }
                return @()
            }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -ErrorAction Continue

            $result.Errors | Should Not BeNullOrEmpty
            $result.Errors | Should Contain "*Log directory access denied*"
        }
    }

    Context "Security and Compliance" {
        It "Should sanitize sensitive information in exports" {
            $sensitiveLogContent = @(
                "User password: secret123",
                "API key: abc123xyz789",
                "Connection string: server=db.company.com;user=admin;password=pass123"
            )
            Mock Get-ChildItem { return @(@{ FullName = "sensitive.log" }) }
            Mock Get-Content { return $sensitiveLogContent }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Be $true
            $result.SensitiveItemsFound | Should BeGreaterThan 0
        }

        It "Should log export operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }
            Mock Compress-Archive { }

            Export-DiagnosticData -OutputPath $script:TestOutputPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*diagnostic export*" }
        }

        It "Should validate export integrity" {
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return @("Test data") }
            Mock Compress-Archive { }
            Mock Get-FileHash { return @{ Hash = "ABC123DEF456" } }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath | Should Be "ABC123DEF456"
            $result.IntegrityValidated | Should Be $true
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large diagnostic exports efficiently" {
            $largeFileSet = 1..100 | ForEach-Object { @{ FullName = "file$_.log"; Length = 1MB } }
            Mock Get-ChildItem { return $largeFileSet }
            Mock Get-Content { return @("Large file content") }
            Mock Compress-Archive { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $result.FilesProcessed | Should Be 100
        }

        It "Should support parallel processing for large exports" {
            Mock Get-ChildItem { return (1..50 | ForEach-Object { @{ FullName = "file$_.log" } }) }
            Mock Get-Content { return @("Content") }
            Mock Compress-Archive { }

            $result = Export-DiagnosticData -OutputPath $script:TestOutputPath -UseParallelProcessing -MaxParallelJobs 4

            $result.ParallelProcessingUsed | Should Be $true
            $result.MaxParallelJobs | Should Be 4
        }
    }

Describe "Get-LogFileSummary" -Tag "Unit", "Reporting", "Analysis" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestLogPath = "C:\logs"
    }

    Context "Parameter Validation" {
        It "Should work without parameters" {
            Mock Get-LoggingSystemState { return @{ LogPath = $script:TestLogPath } }
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ Length = 1024; CreationTime = (Get-Date); LastWriteTime = (Get-Date); LastAccessTime = (Get-Date) } }
            Mock Get-Content { return @("INFO: Test message") }

            { Get-LogFileSummary } | Should Not Throw
        }

        It "Should handle missing log file gracefully" {
            Mock Get-LoggingSystemState { return @{ LogPath = $script:TestLogPath } }
            Mock Test-Path { return $false }

            $result = Get-LogFileSummary
            $result | Should BeNullOrEmpty
        }
    }

    Context "Core Functionality" {
        It "Should analyze log file structure and content" {
            $mockLogFiles = @(
                @{ FullName = "C:\logs\info.log"; Length = 1024; LastWriteTime = (Get-Date) },
                @{ FullName = "C:\logs\error.log"; Length = 2048; LastWriteTime = (Get-Date).AddHours(-1) }
            )
            Mock Get-ChildItem { return $mockLogFiles }
            Mock Get-Content { return @("INFO: Test message", "ERROR: Test error", "WARNING: Test warning") }

            $result = Get-LogFileSummary

            $result | Should Not BeNullOrEmpty
            $result.TotalFiles | Should Be 2
            $result.TotalSizeBytes | Should Be 3072
            $result.LogLevelCounts | Should Not BeNullOrEmpty
        }

        It "Should categorize log entries by level" {
            $logEntries = @(
                "2025-01-24 10:00:00 INFO: Application started",
                "2025-01-24 10:01:00 ERROR: Database connection failed",
                "2025-01-24 10:02:00 WARNING: Memory usage high",
                "2025-01-24 10:03:00 INFO: Processing completed",
                "2025-01-24 10:04:00 ERROR: File not found"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $logEntries }

            $result = Get-LogFileSummary

            $result.LogLevelCounts.INFO | Should Be 2
            $result.LogLevelCounts.ERROR | Should Be 2
            $result.LogLevelCounts.WARNING | Should Be 1
        }

        It "Should identify patterns and trends" {
            $timeBasedEntries = @(
                "2025-01-24 08:00:00 ERROR: Morning error",
                "2025-01-24 14:00:00 ERROR: Afternoon error",
                "2025-01-24 20:00:00 ERROR: Evening error"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $timeBasedEntries }

            $result = Get-LogFileSummary -AnalyzePatterns

            $result.Patterns | Should Not BeNullOrEmpty
            $result.Patterns.ErrorDistribution | Should Not BeNullOrEmpty
        }

        It "Should generate timeline analysis" {
            $chronologicalEntries = @(
                "2025-01-24 10:00:00 INFO: Start",
                "2025-01-24 10:30:00 WARNING: Issue detected",
                "2025-01-24 11:00:00 ERROR: Critical failure",
                "2025-01-24 11:30:00 INFO: Recovery initiated"
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $chronologicalEntries }

            $result = Get-LogFileSummary -IncludeTimeline

            $result.Timeline | Should Not BeNullOrEmpty
            $result.Timeline | Should -HaveCount 4
            $result.Timeline[0].Timestamp | Should Match "10:00:00"
        }

        It "Should detect anomalies and outliers" {
            $anomalousEntries = @(
                "2025-01-24 10:00:00 INFO: Normal operation",
                "2025-01-24 10:01:00 ERROR: Unusual error pattern XYZABC123",
                "2025-01-24 10:02:00 INFO: Normal operation",
                "2025-01-24 10:03:00 CRITICAL: System failure with stack trace..."
            )
            Mock Get-ChildItem { return @(@{ FullName = "test.log" }) }
            Mock Get-Content { return $anomalousEntries }

            $result = Get-LogFileSummary -DetectAnomalies

            $result.Anomalies | Should Not BeNullOrEmpty
            $result.Anomalies | Should Contain "*CRITICAL*"
        }
    }

    Context "Advanced Analysis Features" {
        It "Should perform correlation analysis across multiple log files" {
            $logFile1 = @("2025-01-24 10:00:00 INFO: User login attempt", "2025-01-24 10:01:00 ERROR: Authentication failed")
            $logFile2 = @("2025-01-24 10:00:30 INFO: Database query", "2025-01-24 10:01:30 ERROR: Connection timeout")

            Mock Get-ChildItem { return @(@{ FullName = "app.log" }, @{ FullName = "db.log" }) }
            Mock Get-Content {
                param($Path)
                if ($Path -like "*app.log") { return $logFile1 }
                if ($Path -like "*db.log") { return $logFile2 }
            }

            $result = Get-LogFileSummary -CorrelateAcrossFiles

            $result.Correlations | Should Not BeNullOrEmpty
            $result.Correlations.TimeBasedCorrelations | Should Not BeNullOrEmpty
        }

        It "Should generate performance metrics from log data" {
            $performanceEntries = @(
                "2025-01-24 10:00:00 INFO: Operation started",
                "2025-01-24 10:00:05 INFO: Operation completed in 5000ms",
                "2025-01-24 10:01:00 INFO: Operation started",
                "2025-01-24 10:01:02 INFO: Operation completed in 2000ms"
            )
            Mock Get-ChildItem { return @(@{ FullName = "perf.log" }) }
            Mock Get-Content { return $performanceEntries }

            $result = Get-LogFileSummary -ExtractPerformanceMetrics

            $result.PerformanceMetrics | Should Not BeNullOrEmpty
            $result.PerformanceMetrics.AverageResponseTime | Should Not BeNullOrEmpty
        }

        It "Should identify security-related events" {
            $securityEntries = @(
                "2025-01-24 10:00:00 INFO: User login successful",
                "2025-01-24 10:01:00 WARNING: Multiple failed login attempts",
                "2025-01-24 10:02:00 ERROR: Unauthorized access attempt",
                "2025-01-24 10:03:00 CRITICAL: Potential security breach detected"
            )
            Mock Get-ChildItem { return @(@{ FullName = "security.log" }) }
            Mock Get-Content { return $securityEntries }

            $result = Get-LogFileSummary -IdentifySecurityEvents

            $result.SecurityEvents | Should Not BeNullOrEmpty
            $result.SecurityEvents.PotentialThreats | Should Not BeNullOrEmpty
            $result.SecurityEvents.FailedLogins | Should BeGreaterThan 0
        }

        It "Should support custom log parsing patterns" {
            $customLogEntries = @(
                "[2025-01-24 10:00:00] [INFO] [USER:john.doe] Login successful",
                "[2025-01-24 10:01:00] [ERROR] [USER:jane.smith] Access denied",
                "[2025-01-24 10:02:00] [WARNING] [SYSTEM] Memory usage: 85%"
            )
            $customPattern = @{
                TimestampPattern = '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]'
                LevelPattern = '\[(\w+)\]'
                UserPattern = '\[USER:([^\]]+)\]'
            }
            Mock Get-ChildItem { return @(@{ FullName = "custom.log" }) }
            Mock Get-Content { return $customLogEntries }

            $result = Get-LogFileSummary -CustomParsingPattern $customPattern

            $result.ParsedEntries | Should -HaveCount 3
            $result.ParsedEntries[0].User | Should Be "john.doe"
            $result.ParsedEntries[1].User | Should Be "jane.smith"
        }
    }

    Context "Error Handling and Robustness" {
        It "Should handle corrupted log files gracefully" {
            Mock Get-ChildItem { return @(@{ FullName = "corrupted.log" }) }
            Mock Get-Content { throw "File is corrupted" }

            $result = Get-LogFileSummary -ErrorAction Continue

            $result.Errors | Should Contain "*corrupted*"
            $result.FilesProcessed | Should Be 0
        }

        It "Should handle very large log files efficiently" {
            Mock Get-ChildItem { return @(@{ FullName = "large.log"; Length = 1GB }) }
            Mock Get-Content {
                # Simulate reading large file in chunks
                return (1..1000 | ForEach-Object { "Large log entry $_" })
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-LogFileSummary -UseStreamingRead
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 3000
            $result.ProcessingMethod | Should Be "Streaming"
        }

        It "Should handle empty log directories" {
            Mock Get-ChildItem { return @() }

            $result = Get-LogFileSummary

            $result.TotalFiles | Should Be 0
            $result.Summary | Should Match "*no log files found*"
        }
    }

    Context "Performance and Scalability" {
        It "Should process multiple log files efficiently" {
            $multipleLogFiles = 1..20 | ForEach-Object { @{ FullName = "log$_.txt"; Length = 1024 } }
            Mock Get-ChildItem { return $multipleLogFiles }
            Mock Get-Content { return @("INFO: Test entry") }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-LogFileSummary
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.TotalFiles | Should Be 20
        }

        It "Should support parallel processing for large log sets" {
            Mock Get-ChildItem { return (1..50 | ForEach-Object { @{ FullName = "log$_.txt" } }) }
            Mock Get-Content { return @("INFO: Parallel processing test") }

            $result = Get-LogFileSummary | Should Be "Parallel"
            $result.TotalFiles | Should Be 50
        }
    }

    Context "Audit and Compliance" {
        It "Should log analysis operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ChildItem { return @() }

            Get-LogFileSummary -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*log analysis*" }
        }

        It "Should generate compliance reports" {
            $complianceEntries = @(
                "2025-01-24 10:00:00 AUDIT: Data access by user john.doe",
                "2025-01-24 10:01:00 AUDIT: Configuration changed by admin",
                "2025-01-24 10:02:00 COMPLIANCE: GDPR data processing logged"
            )
            Mock Get-ChildItem { return @(@{ FullName = "audit.log" }) }
            Mock Get-Content { return $complianceEntries }

            $result = Get-LogFileSummary -GenerateComplianceReport -ComplianceFramework "GDPR"

            $result.ComplianceReport | Should Not BeNullOrEmpty
            $result.ComplianceReport.Framework | Should Be "GDPR"
            $result.ComplianceReport.AuditEntries | Should BeGreaterThan 0
        }
    }
}

}



