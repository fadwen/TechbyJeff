#Requires -Version 5.1
#Requires -Modules Pester

# Write-RemovalSecurityLog.Tests.ps1 - Unit Tests for Write-RemovalSecurityLog Function
# Tests security audit logging for SID removal operations with comprehensive validation

# Import the function under test and its dependencies directly
$functionPath = "$PSScriptRoot\..\..\..\..\Private\Logging\Write-RemovalSecurityLog.ps1"
if (Test-Path $functionPath) {
    . $functionPath
} else {
    throw "Could not find Write-RemovalSecurityLog.ps1 at $functionPath"
}

# Import dependencies
$dependencies = @(
    "$PSScriptRoot\..\..\..\..\Private\Logging\Write-SecurityLog.ps1"
)

foreach ($dep in $dependencies) {
    if (Test-Path $dep) {
        . $dep
    }
}

Describe "Write-RemovalSecurityLog" -Tags @('Unit', 'Logging', 'Security') {
    BeforeEach {
        # Override the problematic global Write-StructuredLog mock
        Mock Write-StructuredLog {
            param([string]$Level, [string]$Message, [string]$Component, [hashtable]$Data = @{})
            # Silent mock - just return success
        }
        
        # Mock the dependency on Write-SecurityLog  
        Mock Write-SecurityLog { }
    }

    Context "Parameter Validation" {
        It "Should accept valid SecurityEventType values" {
            $validEventTypes = @('PrivilegeUse', 'ObjectAccess', 'SecurityValidation', 'AuditTrail')
            foreach ($eventType in $validEventTypes) {
                { Write-RemovalSecurityLog -SecurityEventType $eventType -Message "Test message" -Outcome "Success" } | Should Not Throw
            }
        }

        It "Should accept valid Outcome values" {
            $validOutcomes = @('Attempt', 'Success', 'Failure')
            foreach ($outcome in $validOutcomes) {
                { Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test message" -Outcome $outcome } | Should Not Throw
            }
        }

        It "Should accept optional CorrelationId parameter" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            { Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test message" -Outcome "Success" -CorrelationId $correlationId } | Should Not Throw
        }

        It "Should accept optional SecurityContext parameter" {
            $securityContext = @{ TestKey = 'TestValue' }
            { Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test message" -Outcome "Success" -SecurityContext $securityContext } | Should Not Throw
        }
    }

    Context "Security Event Generation" {
        It "Should call Write-SecurityLog with correct parameters" {
            Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test removal operation" -Outcome "Success"

            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityEventType -eq "PrivilegeUse" -and
                $Message -eq "Test removal operation" -and
                $Outcome -eq "Success"
            }
        }

        It "Should include enhanced security context in logging" {
            $customContext = @{ SIDType = 'User'; Domain = 'TestDomain' }
            Write-RemovalSecurityLog -SecurityEventType "ObjectAccess" -Message "SID removal" -Outcome "Success" -SecurityContext $customContext

            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $SecurityContext.Operation -eq 'SIDRemoval' -and
                $SecurityContext.Component -eq 'RemovalSecurityLogging' -and
                $SecurityContext.SIDType -eq 'User' -and
                $SecurityContext.Domain -eq 'TestDomain'
            }
        }

        It "Should generate correlation ID if not provided" {
            Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test message" -Outcome "Success"

            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $CorrelationId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            }
        }

        It "Should use provided correlation ID" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            Write-RemovalSecurityLog -SecurityEventType "PrivilegeUse" -Message "Test message" -Outcome "Success" -CorrelationId $testCorrelationId

            Assert-MockCalled Write-SecurityLog -ParameterFilter {
                $CorrelationId -eq $testCorrelationId
            }
        }
    }

}
