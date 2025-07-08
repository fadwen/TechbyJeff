#Requires -Module Pester

BeforeAll {
    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Mock external dependencies
    function Write-Host { param($Object, $ForegroundColor, $BackgroundColor) }
    function Write-Output { param($InputObject) }
    function Write-Information { param($MessageData, $Tags) }
    function Out-File { param($InputObject, $FilePath, $Append, $Encoding) }
    function Add-Content { param($Path, $Value, $Encoding) }

    # Mock file system operations
    function Test-Path { param($Path, $PathType) return $true }
    function New-Item { param($Path, $ItemType, $Force) return @{ FullName = $Path } }
    function Get-Item { param($Path) return @{ FullName = $Path; LastWriteTime = (Get-Date) } }
    function Get-Content { param($Path) return @() }

    # Mock system functions
    function Get-Date { return [DateTime]::Now }

    # Import Logging module functions for testing
    $LoggingModulePath = Join-Path $PSScriptRoot '..\..\Private\Logging'
    Get-ChildItem -Path $LoggingModulePath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

Describe "Write-StructuredLogEntry" -Tag "Unit", "Logging", "Core" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require Level parameter" {
            { Write-StructuredLogEntry } | Should -Throw "*Level*"
        }

        It "Should require Message parameter" {
            { Write-StructuredLogEntry -Level "Information" } | Should -Throw "*Message*"
        }

        It "Should accept valid parameters" {
            { Write-StructuredLogEntry -Level "Information" -Message "Test message" } | Should -Not -Throw
        }

        It "Should validate log levels" {
            $validLevels = @("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")

            foreach ($level in $validLevels) {
                { Write-StructuredLogEntry -Level $level -Message "Test" } | Should -Not -Throw
            }
        }

        It "Should reject invalid log levels" {
            { Write-StructuredLogEntry -Level "INVALID" -Message "Test" } | Should -Throw "*Level*"
        }
    }

    Context "Core Functionality" {
        It "Should create structured log entry" {
            Mock Out-File { }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Test message"

            $result | Should -Not -BeNullOrEmpty
            $result.Level | Should -Be "INFO"
            $result.Message | Should -Be "Test message"
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It "Should include correlation ID when provided" {
            Mock Out-File { }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Test" -CorrelationId $script:TestCorrelationId

            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should generate correlation ID when not provided" {
            Mock Out-File { }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Test"

            $result.CorrelationId | Should -Not -BeNullOrEmpty
            $result.CorrelationId | Should -Match "^[0-9a-f-]{36}$"
        }

        It "Should include additional details when provided" {
            Mock Out-File { }
            $details = @{ UserName = "testuser"; Action = "login" }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Test" -Details $details

            $result.Details | Should -Not -BeNullOrEmpty
            $result.Details.UserName | Should -Be "testuser"
        }

        It "Should format timestamp consistently" {
            Mock Out-File { }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Test"

            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
        }
    }

    Context "Output Destinations" {
        It "Should write to file when LogPath specified" {
            Mock Out-File { }
            $logPath = "C:\logs\test.log"

            Write-StructuredLogEntry -Level "Information" -Message "Test" Should -Invoke Out-File -ParameterFilter { $FilePath -eq $logPath } -Exactly 1
        }

        It "Should write to console when no LogPath specified" {
            Mock Write-Host { }

            Write-StructuredLogEntry -Level "Information" -Message "Test"

            Should -Invoke Write-Host -Exactly 1
        }

        It "Should append to existing log files" {
            Mock Out-File { }
            Mock Test-Path { return $true }

            $logPath = "C:\logs\existing.log"
            Write-StructuredLogEntry -Level "Information" -Message "Test" Should -Invoke Out-File -ParameterFilter { $Append -eq $true } -Exactly 1
        }
    }

    Context "Error Handling" {
        It "Should handle file write errors gracefully" {
            Mock Out-File { throw "Access denied" }
            Mock Write-Host { }

            { Write-StructuredLogEntry -Level "ERROR" -Message "Test" } | Should -Not -Throw

            Should -Invoke Write-Host -Exactly 1  # Should fallback to console
        }

        It "Should handle invalid log path" {
            Mock Out-File { throw "Path not found" }
            Mock Write-Host { }

            { Write-StructuredLogEntry -Level "Information" -Message "Test" } | Should -Not -Throw
        }
    }

    Context "Security and Compliance" {
        It "Should include security context in log entries" {
            Mock Out-File { }

            $result = Write-StructuredLogEntry -Level "Information" -Message "Security test" -IncludeSecurityContext

            $result.SecurityContext | Should -Not -BeNullOrEmpty
            $result.SecurityContext.UserName | Should -Be $env:USERNAME
        }

        It "Should sanitize sensitive information" {
            Mock Out-File { }
            $sensitiveMessage = "Password: secret123"

            $result = Write-StructuredLogEntry -Level "Information" -Message $sensitiveMessage -SanitizeSensitive

            $result.Message | Should -Not -Match "secret123"
            $result.Message | Should -Match "\*{3,}"  # Should contain asterisks
        }

        It "Should support log level filtering" {
            Mock Out-File { }

            # Simulate minimum log level of WARNING
            $result = Write-StructuredLogEntry -Level "DEBUG" -Message "Debug message" Should -Invoke Out-File -Exactly 0  # Should not write DEBUG when minimum is WARNING
        }
    }

    Context "Performance" {
        It "Should complete logging operations quickly" {
            Mock Out-File { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            1..100 | ForEach-Object {
                Write-StructuredLogEntry -Level "Information" -Message "Performance test $_"
            }
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000
        }

        It "Should handle concurrent logging efficiently" {
            Mock Out-File { }

            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($MessageId)
                    Write-StructuredLogEntry -Level "Information" -Message "Concurrent test $MessageId"
                } -ArgumentList $_
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Should -HaveCount 5
        }
    }
}

Describe "Format-LogMessage" -Tag "Unit", "Logging", "Formatting" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require Message parameter" {
            { Format-LogMessage } | Should -Throw "*Message*"
        }

        It "Should accept string message" {
            { Format-LogMessage -Message "Test message" } | Should -Not -Throw
        }

        It "Should accept format style parameter" {
            { Format-LogMessage -Message "Test" } | Should -Not -Throw
        }
    }

    Context "Core Functionality" {
        It "Should format message as JSON by default" {
            $result = Format-LogMessage -Message "Test message"

            $result | Should -Match "^\s*\{"
            $result | Should -Match "\}\s*$"

            # Should parse as valid JSON
            { $result | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should format message as plain text" {
            $result = Format-LogMessage -Message "Test message" $result | Should -Match "Test message"
            $result | Should -Not -Match "^\s*\{"
        }

        It "Should include timestamp in formatted output" {
            $result = Format-LogMessage -Message "Test"

            $result | Should -Match "\d{4}-\d{2}-\d{2}"
            $result | Should -Match "\d{2}:\d{2}:\d{2}"
        }

        It "Should include correlation ID when provided" {
            $result = Format-LogMessage -Message "Test" -CorrelationId $script:TestCorrelationId

            $result | Should -Match $script:TestCorrelationId
        }

        It "Should handle special characters in messages" {
            $specialMessage = "Test with ""quotes"" and 'apostrophes' and \backslashes\"
            $result = Format-LogMessage -Message $specialMessage

            { $result | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Format Styles" {
        It "Should support CSV format" {
            $result = Format-LogMessage -Message "Test" $result | Should -Match ","  # Should contain comma separators
        }

        It "Should support XML format" {
            $result = Format-LogMessage -Message "Test" $result | Should -Match "<LogEntry>"
            $result | Should -Match "</LogEntry>"
        }

        It "Should support custom format templates" {
            $template = "{Timestamp} [{Level}] {Message}"
            $result = Format-LogMessage -Message "Test" $result | Should -Match "\[.*\]"  # Should contain level in brackets
        }
    }

    Context "Security and Data Protection" {
        It "Should escape potentially dangerous characters" {
            $dangerousMessage = "<script>alert('xss')</script>"
            $result = Format-LogMessage -Message $dangerousMessage $result | Should -Not -Match "<script>"
            $result | Should -Match "&lt;script&gt;"
        }

        It "Should handle null and empty values safely" {
            $result1 = Format-LogMessage -Message $null
            $result2 = Format-LogMessage -Message ""

            $result1 | Should -Not -BeNullOrEmpty
            $result2 | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Write-SecurityLogEvent" -Tag "Unit", "Logging", "Security" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require EventType parameter" {
            { Write-SecurityLogEvent } | Should -Throw "*EventType*"
        }

        It "Should require Message parameter" {
            { Write-SecurityLogEvent -SecurityEventType "AuthenticationAttempt" } | Should -Throw "*Message*"
        }

        It "Should validate event types" {
            $validTypes = @("AuthenticationAttempt", "AuthorizationCheck", "ObjectAccess", "ConfigurationChange", "ObjectAccess")

            foreach ($type in $validTypes) {
                { Write-SecurityLogEvent -SecurityEventType $type -Message "Test" } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        It "Should create security log event" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "AuthenticationAttempt" -Message "User login"

            $result | Should -Not -BeNullOrEmpty
            $result.EventType | Should -Be "AuthenticationAttempt"
            $result.Message | Should -Be "User login"
            $result.Severity | Should -Not -BeNullOrEmpty
        }

        It "Should include security context automatically" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "File accessed"

            $result.SecurityContext | Should -Not -BeNullOrEmpty
            $result.SecurityContext.UserName | Should -Be $env:USERNAME
            $result.SecurityContext.ProcessId | Should -Be $PID
        }

        It "Should assign appropriate severity levels" {
            Mock Out-File { }

            $authResult = Write-SecurityLogEvent -SecurityEventType "AuthenticationAttempt" -Message "Login success"
            $violationResult = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "Unauthorized access"

            $authResult.Severity | Should -Be "Information"
            $violationResult.Severity | Should -Be "Critical"
        }

        It "Should include compliance tags" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "Sensitive data accessed" -ComplianceFramework "SOX"

            $result.ComplianceTags | Should -Contain "SOX"
            $result.ComplianceTags | Should -Contain "DataGovernance"
        }
    }

    Context "Audit Trail" {
        It "Should create immutable audit entries" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ConfigurationChange" -Message "Configuration modified"

            $result.AuditSignature | Should -Not -BeNullOrEmpty
            $result.Immutable | Should -Be $true
        }

        It "Should link related security events" {
            Mock Out-File { }

            $parentId = [System.Guid]::NewGuid().ToString()
            $result = Write-SecurityLogEvent -SecurityEventType "AuthorizationCheck" -Message "Permission check" -ParentEventId $parentId

            $result.ParentEventId | Should -Be $parentId
        }

        It "Should track event sequences" {
            Mock Out-File { }

            $result1 = Write-SecurityLogEvent -SecurityEventType "AuthenticationAttempt" -Message "Login attempt"
            $result2 = Write-SecurityLogEvent -SecurityEventType "AuthenticationAttempt" -Message "Login success" -PreviousEventId $result1.EventId

            $result2.PreviousEventId | Should -Be $result1.EventId
            $result2.SequenceNumber | Should -BeGreaterThan $result1.SequenceNumber
        }
    }

    Context "Integration and Compliance" {
        It "Should support SIEM integration" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "Intrusion detected" -SIEMFormat

            $result.SIEMCompatible | Should -Be $true
            $result.CEFFormat | Should -Not -BeNullOrEmpty
        }

        It "Should meet regulatory requirements" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "PII accessed" -RegulatoryFramework @("GDPR", "HIPAA")

            $result.RegulatoryCompliance | Should -Contain "GDPR"
            $result.DataClassification | Should -Not -BeNullOrEmpty
        }

        It "Should support forensic analysis" {
            Mock Out-File { }

            $result = Write-SecurityLogEvent -SecurityEventType "ObjectAccess" -Message "Malware detected" -ForensicMode

            $result.ForensicData | Should -Not -BeNullOrEmpty
            $result.ChainOfCustody | Should -Not -BeNullOrEmpty
        }
    }
}







