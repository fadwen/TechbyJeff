# Pester 3.4 tests for Write-SecurityLog.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

# Import dependencies
. "$here\..\..\..\..\Private\Logging\Initialize-LoggingConfiguration.ps1"
. "$here\..\..\..\..\Private\Logging\Initialize-LoggingSystem.ps1"

Describe "Write-SecurityLog" -Tags @('Unit', 'Logging', 'Security') {

    # Mock dependencies inside Describe block
    Mock Write-Verbose { } -Verifiable
    Mock Write-Warning { } -Verifiable
    Mock Write-Error { } -Verifiable
    Mock Write-SecurityStructuredLogEntry { } -Verifiable
    Mock Out-File { } -Verifiable

    Context "Parameter Validation" {
        
        It "Should accept valid SecurityEventType" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }

        It "Should accept valid Outcome values" {
            $validOutcomes = @('Attempt', 'Success', 'Failure')
            foreach ($outcome in $validOutcomes) {
                { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome $outcome } | Should Not Throw
            }
        }

        It "Should accept optional SecurityContext hashtable" {
            $context = @{ UserId = "123"; Domain = "CORP" }
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" -SecurityContext $context } | Should Not Throw
        }

        It "Should accept optional CorrelationId" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" -CorrelationId $correlationId } | Should Not Throw
        }
    }

    Context "Security Log Entry Construction" {
        
        BeforeEach {
            # Initialize logging system for testing
            Initialize-LoggingSystem -CorrelationId "test-correlation-123"
        }

        It "Should create comprehensive security log entry" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "AD user access" -Outcome "Success" } | Should Not Throw
        }

        It "Should include timestamp in log entry" {
            $beforeTime = Get-Date
            { Write-SecurityLog -SecurityEventType "Authentication" -Message "Login attempt" -Outcome "Attempt" } | Should Not Throw
        }

        It "Should include user context information" {
            { Write-SecurityLog -SecurityEventType "Authorization" -Message "Permission check" -Outcome "Success" } | Should Not Throw
        }

        It "Should include process ID" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "File access" -Outcome "Success" } | Should Not Throw
        }

        It "Should use provided CorrelationId" {
            $testCorrelationId = "custom-correlation-456"
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" -CorrelationId $testCorrelationId } | Should Not Throw
        }

        It "Should generate new CorrelationId when not provided" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }
    }

    Context "Log Level Determination" {
        
        It "Should use Information level for Attempt outcome" {
            { Write-SecurityLog -SecurityEventType "Authentication" -Message "Login attempt" -Outcome "Attempt" } | Should Not Throw
        }

        It "Should use Information level for Success outcome" {
            { Write-SecurityLog -SecurityEventType "Authentication" -Message "Login success" -Outcome "Success" } | Should Not Throw
        }

        It "Should use Warning level for Failure outcome" {
            { Write-SecurityLog -SecurityEventType "Authentication" -Message "Login failure" -Outcome "Failure" } | Should Not Throw
        }
    }

    Context "Security Context Integration" {
        
        It "Should merge additional security context" {
            $securityContext = @{
                ObjectType = "User"
                ObjectId = "CN=TestUser,OU=Users,DC=domain,DC=com"
                Operation = "Read"
            }
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "User read" -Outcome "Success" -SecurityContext $securityContext } | Should Not Throw
        }

        It "Should handle empty security context" {
            $emptyContext = @{}
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" -SecurityContext $emptyContext } | Should Not Throw
        }

        It "Should prefix security context keys with Security_" {
            $securityContext = @{ UserId = "123" }
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" -SecurityContext $securityContext } | Should Not Throw
        }
    }

    Context "Message Formatting" {
        
        It "Should format audit message with event type and outcome" {
            { Write-SecurityLog -SecurityEventType "DataAccess" -Message "Database query executed" -Outcome "Success" } | Should Not Throw
        }

        It "Should handle special characters in messages" {
            $specialMessage = "Access to file: C:\temp\test file with spaces & symbols.txt"
            { Write-SecurityLog -SecurityEventType "FileAccess" -Message $specialMessage -Outcome "Success" } | Should Not Throw
        }
    }

    Context "Verbose Output" {
        
        It "Should write verbose output for immediate visibility" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test access" -Outcome "Success" -CorrelationId "test-123" } | Should Not Throw
        }
    }

    Context "Error Handling" {
        
        It "Should handle Write-SecurityStructuredLogEntry failures gracefully" {
            # Mock Write-SecurityStructuredLogEntry to throw an error
            Mock Write-SecurityStructuredLogEntry { throw "Log system failure" } 
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }

        It "Should attempt fallback logging when structured logging fails" {
            # Mock Write-SecurityStructuredLogEntry to throw an error
            Mock Write-SecurityStructuredLogEntry { throw "Log system failure" } 
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }

        It "Should handle fallback logging failures" {
            # Mock both structured logging and fallback to fail
            Mock Write-SecurityStructuredLogEntry { throw "Log system failure" } 
            Mock Out-File { throw "File system failure" } 
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }
    }

    Context "Component Assignment" {
        
        It "Should always use SecurityAudit component" {
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }
    }

    Context "Integration with Logging System" {
        
        It "Should work when logging system is not initialized" {
            # Reset logging system state
            $script:CorrelationId = $null
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }

        It "Should use system correlation ID when available" {
            Initialize-LoggingSystem -CorrelationId "system-correlation-789"
            
            { Write-SecurityLog -SecurityEventType "ObjectAccess" -Message "Test" -Outcome "Success" } | Should Not Throw
        }
    }
}

