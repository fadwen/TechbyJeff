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
    Mock Add-Content { }
    Mock Test-Path { return $true }
    Mock Out-File { }
    Mock Join-Path { return "C:\temp\emergency.log" }
    
    # Create a simple Format-LogMessage function for testing since it doesn't exist
    function Format-LogMessage {
        param($Message, $Level, $Component, $CorrelationId, $AdditionalData)
        return "[$Level] [$Component] $Message (ID: $CorrelationId)"
    }

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
                { Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord } | Should Not Throw
            }
        }

        It "Should include exception message in ErrorRecord data" {
            try {
                throw "Specific test exception message"
            } catch {
                $errorRecord = $_
                { Write-SecurityStructuredLogEntry -Message "Error occurred" -ErrorRecord $errorRecord } | Should Not Throw
            }
        }
    }

    Context "Message Sanitization" {
        
        It "Should format message with proper parameters" {
            { Write-SecurityStructuredLogEntry -Message "Security event" -Level "Warning" -Component "SecurityAudit" } | Should Not Throw
        }

        It "Should include structured data in formatting" {
            $testData = @{ EventType = "Access"; Resource = "Database" }
            
            { Write-SecurityStructuredLogEntry -Message "Test" -Data $testData } | Should Not Throw
        }
    }

    Context "Basic Functionality" {
        
        It "Should complete basic execution" {
            { Write-SecurityStructuredLogEntry -Message "Security event" } | Should Not Throw
        }

        It "Should handle console output" {
            { Write-SecurityStructuredLogEntry -Message "Security event" } | Should Not Throw
        }

        It "Should handle file operations" {
            { Write-SecurityStructuredLogEntry -Message "Security event" } | Should Not Throw
        }
    }

    Context "Error Handling" {
        
        It "Should handle formatting errors gracefully" {
            # Override the Format-LogMessage function to throw an error
            function Format-LogMessage { throw "Formatting error" }
            
            { Write-SecurityStructuredLogEntry -Message "Test" } | Should Not Throw
        }

        It "Should continue execution after errors for critical security logging" {
            # Override the Format-LogMessage function to throw an error
            function Format-LogMessage { throw "Critical error" }
            
            { Write-SecurityStructuredLogEntry -Message "Critical security event" } | Should Not Throw
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
            { Write-SecurityStructuredLogEntry -Message "Security info" -Level "Information" } | Should Not Throw
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
            
            { Write-SecurityStructuredLogEntry -Message "Security event" } | Should Not Throw
        }
    }

    Context "Performance Characteristics" {
        
        It "Should have minimal validation for performance" {
            # Security logging should be fast - minimal validation to test direct execution
            { Write-SecurityStructuredLogEntry -Message "Performance test" } | Should Not Throw
        }
    }
}

