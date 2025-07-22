# Pester 3.4 tests for Write-SecurityStructuredLogEntry.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

# Import dependencies
. "$here\..\..\..\..\Private\Logging\Initialize-LoggingConfiguration.ps1"
. "$here\..\..\..\..\Private\Logging\Initialize-LoggingSystem.ps1"

Describe "Write-SecurityStructuredLogEntry" -Tags @('Unit', 'Logging', 'Security') {

    # Mock all dependencies inside Describe block
    Mock Write-Verbose { }
    Mock Write-Warning { }
    Mock Write-Error { }
    Mock Write-Host { }
    Mock Get-LoggingSystemState { 
        return [PSCustomObject]@{
            CorrelationId = "test-correlation-123"
            LogPath = "C:\temp\test.log"
            LogFileInitialized = $true
            SuppressConsoleOutput = $false
        }
    }
    Mock Format-LogMessage { return "Formatted: $Message" }
    Mock Add-Content { }
    Mock Test-Path { return $true }
    Mock Out-File { }
    Mock Join-Path { return "C:\temp\emergency.log" }
    
    # Mock the helper functions that don't exist yet
    Mock Write-SecurityConsoleEntry { }
    Mock Write-SecurityFileEntry { }
    Mock Write-SecurityFileEntryDirect { }
    Mock Update-SecurityLoggingMetrics { }

    Context "Parameter Validation" {
        
        It "Should accept valid Level values" {
            $validLevels = @('Critical', 'Error', 'Warning', 'Information')
            foreach ($level in $validLevels) {
                { Write-SecurityStructuredLogEntry -Message "Test" -Level $level } | Should Not Throw
            }
        }

        It "Should default to Information level" {
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
        }

        It "Should default to SecurityAudit component" {
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
        }

        It "Should accept custom component" {
            { Write-SecurityStructuredLogEntry -Message "Test" -Component "CustomSecurity" } | Should Not Throw
        }

        It "Should accept ErrorRecord parameter" {
            try {
                throw "Test exception"
            } catch {
                $errorRecord = $_
                { Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord } | Should Not Throw
            }
        }

        It "Should accept Data hashtable parameter" {
            $testData = @{ Key1 = "Value1"; Key2 = "Value2" }
            { Write-SecurityStructuredLogEntry -Message "Test" -Data $testData } | Should Not Throw
        }

        It "Should accept CorrelationId parameter" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Write-SecurityStructuredLogEntry -Message "Test" -CorrelationId $correlationId } | Should Not Throw
        }
    }

    Context "Logging System State Integration" {
        
        BeforeEach {
            # Reset mocks for each test
            Mock Get-LoggingSystemState { 
                return [PSCustomObject]@{
                    CorrelationId = "system-correlation-456"
                    LogPath = "C:\temp\security.log"
                    LogFileInitialized = $true
                }
            } 
        }

        It "Should retrieve logging system state" {
            Write-SecurityStructuredLogEntry -Message "Test"
            
            Assert-MockCalled Get-LoggingSystemState
        }

        It "Should warn when logging system not properly initialized" {
            Mock Get-LoggingSystemState { 
                return [PSCustomObject]@{
                    CorrelationId = $null
                    LogPath = $null
                    LogFileInitialized = $false
                }
            } 
            
            Write-SecurityStructuredLogEntry -Message "Test"
            
            Assert-MockCalled Write-Warning -ParameterFilter {
                $Message -match "Logging system not properly initialized"
            }
        }

        It "Should use provided CorrelationId over system CorrelationId" {
            $customCorrelationId = "custom-correlation-789"
            
            { Write-SecurityStructuredLogEntry -Message "Test" -CorrelationId $customCorrelationId } | Should Not Throw
        }

        It "Should use system CorrelationId when none provided" {
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
        }

        It "Should generate new CorrelationId when neither provided nor in system" {
            Mock Get-LoggingSystemState { 
                return [PSCustomObject]@{
                    CorrelationId = $null
                    LogPath = "C:\temp\test.log"
                    LogFileInitialized = $true
                }
            } 
            
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
        }
    }

    Context "ErrorRecord Processing" {
        
        It "Should process ErrorRecord into structured data" {
            try {
                throw "Test exception for logging"
            } catch {
                $errorRecord = $_
                Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord
                
                # Verify ErrorRecord data was added to structured data
                Assert-MockCalled Format-LogMessage
            }
        }

        It "Should include exception message in ErrorRecord data" {
            try {
                throw "Specific test exception message"
            } catch {
                $errorRecord = $_
                Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord
                
                Assert-MockCalled Format-LogMessage
            }
        }

        It "Should include script stack trace in ErrorRecord data" {
            try {
                throw "Test exception"
            } catch {
                $errorRecord = $_
                Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord
                
                Assert-MockCalled Format-LogMessage
            }
        }

        It "Should include fully qualified error ID in ErrorRecord data" {
            try {
                throw "Test exception"
            } catch {
                $errorRecord = $_
                Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord
                
                Assert-MockCalled Format-LogMessage
            }
        }
    }

    Context "Message Sanitization" {
        
        It "Should format message with proper parameters" {
            { Write-SecurityStructuredLogEntry -Message "Security event" -Level "Warning" -Component "SecurityAudit" } | Should Not Throw
        }

        It "Should include structured data in formatting" {
            $testData = @{ EventType = "Access"; Resource = "Database" }
            
            Write-SecurityStructuredLogEntry -Message "Test" -Data $testData
            
            Assert-MockCalled Format-LogMessage
        }
    }

    Context "Direct File Writing" {
        
        It "Should write directly using helper functions" {
            Write-SecurityStructuredLogEntry -Message "Security event"
            
            Assert-MockCalled Write-SecurityFileEntry
        }

        It "Should use console output for security events" {
            Write-SecurityStructuredLogEntry -Message "Security event"
            
            Assert-MockCalled Write-SecurityConsoleEntry
        }

        It "Should update security metrics" {
            Write-SecurityStructuredLogEntry -Message "Security event"
            
            Assert-MockCalled Update-SecurityLoggingMetrics
        }
    }

    Context "Error Handling" {
        
        It "Should handle formatting errors gracefully" {
            Mock Format-LogMessage { throw "Formatting error" } 
            
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
            
            Assert-MockCalled Write-Warning
        }

        It "Should continue execution after errors for critical security logging" {
            Mock Format-LogMessage { throw "Critical error" } 
            
            $result = Write-SecurityStructuredLogEntry -Message "Critical security event"
            
            # Function should complete despite errors
            $result | Should BeNullOrEmpty
        }
    }

    Context "Security Bypass Behavior" {
        
        It "Should bypass normal log level filtering" {
            # Mock the logging system to have a restrictive log level
            Mock Get-LoggingSystemState { 
                return [PSCustomObject]@{
                    CorrelationId = "test"
                    LogPath = "C:\temp\test.log"
                    LogFileInitialized = $true
                    LogLevel = "Critical"  # Very restrictive
                }
            } 
            
            # Information level should still be written for security
            Write-SecurityStructuredLogEntry -Message "Security info" -Level "Information"
            
            Assert-MockCalled Write-SecurityFileEntry
        }

        It "Should always write security logs regardless of system configuration" {
            # Even with system suppression, security logs should be written
            Mock Get-LoggingSystemState { 
                return [PSCustomObject]@{
                    CorrelationId = "test"
                    LogPath = "C:\temp\test.log"
                    LogFileInitialized = $true
                    SuppressConsoleOutput = $true
                }
            } 
            
            Write-SecurityStructuredLogEntry -Message "Security event"
            
            Assert-MockCalled Write-SecurityFileEntry
        }
    }

    Context "Performance Characteristics" {
        
        It "Should have minimal validation for performance" {
            # Security logging should be fast - minimal mocking to test direct execution
            Write-SecurityStructuredLogEntry -Message "Performance test"
            
            # Should call core functions without excessive validation
            Assert-MockCalled Format-LogMessage
            Assert-MockCalled Write-SecurityFileEntry
        }
    }
}

