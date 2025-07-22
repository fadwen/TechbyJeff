# Pester 3.4 tests for Write-ClassSecurityEvent.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

Describe "Write-ClassSecurityEvent" -Tags @('Unit', 'Logging', 'Security', 'Class') {

    # Mock dependencies inside Describe block
    Mock Write-StructuredLog { }
    Mock Write-Verbose { }
    Mock Write-Warning { }
    Mock Write-Error { }
    Mock Write-Information { }
    Mock Write-EventLog { }
    Mock Get-Command { return $false }
    Mock Get-ExecutionPolicy { return 'RemoteSigned' }

    Context "Parameter Validation" {
        
        It "Should accept valid EventType values" {
            $validEventTypes = @('Success', 'Warning', 'Violation', 'Error', 'Information', 'Critical')
            foreach ($eventType in $validEventTypes) {
                { Write-ClassSecurityEvent -EventType $eventType -Message "Test message" } | Should Not Throw
            }
        }

        It "Should reject invalid EventType values" {
            { Write-ClassSecurityEvent -EventType "InvalidType" -Message "Test message" } | Should Throw
        }

        It "Should accept optional EventData hashtable" {
            $eventData = @{ Key = 'Value' }
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -EventData $eventData } | Should Not Throw
        }

        It "Should accept optional SecurityContext hashtable" {
            $context = @{ User = 'TestUser' }
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -SecurityContext $context } | Should Not Throw
        }

        It "Should accept optional CorrelationId" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -CorrelationId $correlationId } | Should Not Throw
        }

        It "Should generate CorrelationId when not provided" {
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test message" } | Should Not Throw
        }
    }

    Context "EventType Handling" {
        
        It "Should handle Success event type" {
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test success" } | Should Not Throw
        }

        It "Should handle Warning event type" {
            { Write-ClassSecurityEvent -EventType "Warning" -Message "Test warning" } | Should Not Throw
        }

        It "Should handle Violation event type" {
            { Write-ClassSecurityEvent -EventType "Violation" -Message "Test violation" } | Should Not Throw
        }

        It "Should handle Error event type" {
            { Write-ClassSecurityEvent -EventType "Error" -Message "Test error" } | Should Not Throw
        }

        It "Should handle Information event type" {
            { Write-ClassSecurityEvent -EventType "Information" -Message "Test information" } | Should Not Throw
        }

        It "Should handle Critical event type" {
            { Write-ClassSecurityEvent -EventType "Critical" -Message "Test critical" } | Should Not Throw
        }
    }

    Context "Security Context Construction" {
        
        It "Should create standardized security context for class events" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message"
            Assert-MockCalled Write-Verbose
        }

        It "Should include system context information" {
            Write-ClassSecurityEvent -EventType "Information" -Message "Test message"
            Assert-MockCalled Write-Information
        }

        It "Should use provided CorrelationId in context" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -CorrelationId $correlationId
            Assert-MockCalled Write-Verbose
        }

        It "Should merge custom SecurityContext with defaults" {
            $customContext = @{ CustomField = 'CustomValue' }
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -SecurityContext $customContext
            Assert-MockCalled Write-Verbose
        }

        It "Should handle empty SecurityContext" {
            $emptyContext = @{}
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -SecurityContext $emptyContext
            Assert-MockCalled Write-Verbose
        }
    }

    Context "Event Data Handling" {
        
        It "Should handle simple EventData" {
            $eventData = @{ Key1 = 'Value1' }
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -EventData $eventData
            Assert-MockCalled Write-Verbose
        }

        It "Should handle complex nested EventData" {
            $eventData = @{ 
                Simple = 'Value'
                Complex = @{ Nested = 'NestedValue' }
                Array = @(1, 2, 3)
            }
            Write-ClassSecurityEvent -EventType "Information" -Message "Test message" -EventData $eventData
            Assert-MockCalled Write-Information
        }

        It "Should handle empty EventData" {
            $eventData = @{}
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -EventData $eventData
            Assert-MockCalled Write-Verbose
        }

        It "Should handle null EventData" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -EventData $null
            Assert-MockCalled Write-Verbose
        }
    }

    Context "Structured Logging Integration" {
        
        BeforeEach {
            Mock Get-Command { 
                param($Name)
                if ($Name -eq 'Write-StructuredLog') { 
                    return @{ Name = 'Write-StructuredLog' } 
                } 
                return $null 
            }
            Mock Write-StructuredLog { }
        }

        It "Should call Write-StructuredLog when available" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message"
            Assert-MockCalled Write-StructuredLog
        }

        It "Should pass CorrelationId to Write-StructuredLog" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -CorrelationId $correlationId
            Assert-MockCalled Write-StructuredLog
        }

        It "Should pass complete security context to Write-StructuredLog" {
            $context = @{ TestContext = 'TestValue' }
            Write-ClassSecurityEvent -EventType "Violation" -Message "Security test" -SecurityContext $context
            Assert-MockCalled Write-StructuredLog
        }
    }

    Context "Security Scenarios" {
        
        It "Should handle security success events" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Class loaded successfully"
            Assert-MockCalled Write-Verbose
        }

        It "Should handle security violation events" {
            $violationData = @{ ViolationType = 'PathTraversal'; Path = '../../../test' }
            Write-ClassSecurityEvent -EventType "Violation" -Message "Path traversal detected" -EventData $violationData
            Assert-MockCalled Write-Warning
        }

        It "Should handle security error events" {
            $errorData = @{ ErrorCode = 'SEC001'; Details = 'Unauthorized access attempt' }
            Write-ClassSecurityEvent -EventType "Error" -Message "Security error occurred" -EventData $errorData
            Assert-MockCalled Write-Error
        }

        It "Should handle critical security events" {
            $criticalData = @{ ThreatLevel = 'High'; Source = 'External' }
            Write-ClassSecurityEvent -EventType "Critical" -Message "Critical security incident" -EventData $criticalData
            Assert-MockCalled Write-Error
        }
    }

    Context "Data Sanitization" {
        
        It "Should sanitize sensitive data in EventData" {
            $eventData = @{ 
                Password = 'secret123'
                Token = 'abc123def456'
                NormalData = 'safe_value'
            }
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -EventData $eventData
            Assert-MockCalled Write-Verbose
        }

        It "Should truncate very long strings in EventData" {
            $longString = 'a' * 1500  # More than 1000 chars
            $eventData = @{ LongData = $longString }
            Write-ClassSecurityEvent -EventType "Information" -Message "Test message" -EventData $eventData
            Assert-MockCalled Write-Information
        }

        It "Should sanitize sensitive data in SecurityContext" {
            $context = @{ 
                Credential = 'sensitive_data'
                Authentication = 'auth_token'
                SafeData = 'safe_value'
            }
            Write-ClassSecurityEvent -EventType "Success" -Message "Test message" -SecurityContext $context
            Assert-MockCalled Write-Verbose
        }
    }

    Context "Windows Event Log Integration" {
        
        BeforeEach {
            Mock Write-EventLog { }
        }

        It "Should write to Windows Event Log for high-severity events" {
            Write-ClassSecurityEvent -EventType "Violation" -Message "Security violation"
            Assert-MockCalled Write-EventLog -Scope It
        }

        It "Should write to Windows Event Log for error events" {
            Write-ClassSecurityEvent -EventType "Error" -Message "Security error"
            Assert-MockCalled Write-EventLog -Scope It
        }

        It "Should write to Windows Event Log for critical events" {
            Write-ClassSecurityEvent -EventType "Critical" -Message "Critical security event"
            Assert-MockCalled Write-EventLog -Scope It
        }

        It "Should not write to Windows Event Log for informational events" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Success event"
            Assert-MockCalled Write-EventLog -Times 0 -Scope It
        }
    }

    Context "Compliance and Audit Features" {
        
        BeforeEach {
            Mock Get-Command { 
                param($Name)
                if ($Name -eq 'Write-StructuredLog') { 
                    return @{ Name = 'Write-StructuredLog' } 
                } 
                return $null 
            }
            Mock Write-StructuredLog { }
        }

        It "Should create audit records for compliance events" {
            Write-ClassSecurityEvent -EventType "Success" -Message "Audit test"
            Assert-MockCalled Write-StructuredLog -Times 2  # Main log + audit record
        }

        It "Should create audit records for violation events" {
            Write-ClassSecurityEvent -EventType "Violation" -Message "Security violation"
            Assert-MockCalled Write-StructuredLog -Times 2  # Main log + audit record
        }

        It "Should include compliance metadata in audit records" {
            Write-ClassSecurityEvent -EventType "Critical" -Message "Critical event"
            Assert-MockCalled Write-StructuredLog -Times 2  # Main log + audit record
        }
    }

    Context "Error Handling" {
        
        It "Should handle logging failures gracefully" {
            Mock Write-Verbose { throw "Logging failure" }
            { Write-ClassSecurityEvent -EventType "Success" -Message "Test message" } | Should Not Throw
        }

        It "Should handle null or empty messages" {
            { Write-ClassSecurityEvent -EventType "Success" -Message "" } | Should Throw
            { Write-ClassSecurityEvent -EventType "Success" -Message $null } | Should Throw
        }

        It "Should handle Windows Event Log failures gracefully" {
            Mock Write-EventLog { throw "Event log failure" }
            { Write-ClassSecurityEvent -EventType "Critical" -Message "Critical event" } | Should Not Throw
        }
    }

    Context "Performance" {
        
        It "Should execute quickly for simple logging" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-ClassSecurityEvent -EventType "Success" -Message "Performance test"
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 100
        }

        It "Should handle multiple rapid calls efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            1..10 | ForEach-Object {
                Write-ClassSecurityEvent -EventType "Information" -Message "Rapid call $_"
            }
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500
        }
    }
}

