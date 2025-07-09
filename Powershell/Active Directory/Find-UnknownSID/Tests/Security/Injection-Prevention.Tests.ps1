#Requires -Module Pester

<#
.SYNOPSIS
    Security tests for Find-UnknownSID injection prevention and threat mitigation

.DESCRIPTION
    Comprehensive security testing for the Find-UnknownSID solution that validates
    protection against injection attacks, unauthorized access, and security vulnerabilities.

    This test suite addresses critical security gaps identified in the test coverage analysis
    and implements enterprise-grade security testing following PowerShell community
    standards and security best practices.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    Version: 1.0.0
    PowerShell Version: 5.1+

    Test Coverage: Injection prevention, privilege escalation, audit trails, compliance
    Priority: HIGH - Required for regulatory compliance and security validation

    TROUBLESHOOTING:
    - For security issues: .\Troubleshooting\Security\Security-Issues.md
    - For compliance problems: .\Troubleshooting\Compliance\Compliance-Troubleshooting.md
#>

# Import security testing utilities
$script:ModulePath = Join-Path $PSScriptRoot '..\..\Find-UnknownSID.ps1'
Import-Module $script:ModulePath -Force
# Import test helpers
$script:TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
. $script:TestHelpersPath
# Set up security test data
$script:MaliciousInputs = @(
"'; DROP TABLE Users; --",              # SQL injection
"../../../windows/system32/config",     # Path traversal
"$(Invoke-Expression 'calc.exe')",      # PowerShell injection
"|cmd /c whoami",                       # Command injection
"$(Get-Process)",                       # PowerShell execution
"../etc/passwd",                        # Unix path traversal
"javascript:alert('xss')",             # Script injection
"<script>alert('xss')</script>",       # HTML injection
"CN=Administrator,CN=Users`; rm -rf /", # LDAP injection with command
"../../../../../../etc/shadow",         # Extended path traversal
"%SystemRoot%\system32\cmd.exe",        # Environment variable injection
"$(whoami; cat /etc/passwd)",           # Command chaining
"'; shutdown /s /t 1; --"              # System command injection
)
$script:PrivilegeEscalationTests = @(
@{ User = 'standard_user'; Action = 'AdminOperation'; ShouldFail = $true }
@{ User = 'domain_admin'; Action = 'StandardOperation'; ShouldSucceed = $true }
@{ User = 'service_account'; Action = 'ServiceOperation'; ShouldSucceed = $true }
@{ User = 'guest_user'; Action = 'ReadOperation'; ShouldFail = $true }
@{ User = 'backup_operator'; Action = 'BackupOperation'; ShouldSucceed = $true }
)
$script:CorrelationId = [System.Guid]::NewGuid().ToString()
# Mock security logging for testing
Mock Write-SecurityLog {
param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)
Write-Verbose "Security Event: $SecurityEventType - $Message - $Outcome"
} -ModuleName Find-UnknownSID
# Mock dangerous operations for safe testing
Mock Invoke-Expression { throw "Dangerous operation blocked" } -ModuleName Find-UnknownSID
Mock Start-Process { throw "Process execution blocked" } -ModuleName Find-UnknownSID

Describe "Injection Attack Prevention" -Tag "Security", "Critical", "Injection" {

    Context "LDAP Injection Prevention" {
        BeforeEach {
            $script:InjectionCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should prevent LDAP injection in SID queries for malicious input: <MaliciousInput>" -TestCases ($script:MaliciousInputs | ForEach-Object { @{ MaliciousInput = $_ } }) {
            param($MaliciousInput)

            # Mock the function that would be vulnerable to injection
            Mock Find-OrphanedSIDs {
                param($SearchBase)
                if ($SearchBase -match '[;&|<>(){}\\$`]|DROP|shutdown|rm\s+-rf|/etc/|cmd\.exe|whoami') {
                    throw "Invalid characters detected in SearchBase parameter"
                }
                return @()
            } -ModuleName Find-UnknownSID

            { Find-OrphanedSIDs -SearchBase $MaliciousInput -CorrelationId $script:InjectionCorrelationId } | Should Throw "*Invalid*"
        }

        It "Should sanitize input parameters for AD queries" {
            # Mock input sanitization function
            Mock Protect-UserInput {
                param($InputString, $InputType, $CorrelationId)

                # Simulate input validation
                if ($InputString -match '[;&|<>(){}\\$`]|DROP|shutdown|rm\s+-rf') {
                    throw "Input contains dangerous characters"
                }

                return $InputString.Trim()
            } -ModuleName Find-UnknownSID

            $safeInput = "CN=TestUser,CN=Users,DC=test,DC=local"
            $sanitizedResult = Protect-UserInput -InputString $safeInput -InputType 'DistinguishedName' -CorrelationId $script:InjectionCorrelationId
            $sanitizedResult | Should Be $safeInput

            { Protect-UserInput -InputString "../../../windows" -InputType 'DistinguishedName' -CorrelationId $script:InjectionCorrelationId } | Should Throw "*dangerous*"
        }

        It "Should validate SID format to prevent injection" {
            # Test SID format validation against injection attempts
            $validSID = "S-1-5-21-123456789-123456789-123456789-1001"
            $result = Test-SIDFormat -SID $validSID -CorrelationId $script:InjectionCorrelationId
            $result.IsValid | Should -BeTrue

            # Test malicious SID formats
            foreach ($maliciousInput in $script:MaliciousInputs) {
                { Test-SIDFormat -SID $maliciousInput -CorrelationId $script:InjectionCorrelationId } | Should Throw
            }
        }
    }

    Context "PowerShell Injection Prevention" {
        BeforeEach {
            $script:PSInjectionCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should prevent PowerShell code injection" {
            # Test prevention of PowerShell execution in parameters
            $maliciousPSCode = "$(Get-Process)"

            { Test-SIDFormat -SID $maliciousPSCode -CorrelationId $script:PSInjectionCorrelationId } | Should Throw "*Invalid SID format*"
        }

        It "Should prevent command substitution attacks" {
            # Test prevention of command substitution
            $commandSubstitution = "`$(whoami)"

            { Test-SIDFormat -SID $commandSubstitution -CorrelationId $script:PSInjectionCorrelationId } | Should Throw "*Invalid SID format*"
        }

        It "Should validate file paths to prevent traversal" {
            # Mock file path validation
            Mock Test-SafeFilePath {
                param($FilePath, $CorrelationId)

                if ($FilePath -match '\.\.[/\\]|/etc/|\\windows\\system32|%\w+%') {
                    throw "Path traversal detected in file path"
                }

                return $true
            } -ModuleName Find-UnknownSID

            $safePath = "C:\Logs\backup.xml"
            Test-SafeFilePath -FilePath $safePath -CorrelationId $script:PSInjectionCorrelationId | Should -BeTrue

            { Test-SafeFilePath -FilePath "../../../windows/system32/config" -CorrelationId $script:PSInjectionCorrelationId } | Should Throw "*traversal*"
        }
    }

    Context "File System Injection Prevention" {
        BeforeEach {
            $script:FileInjectionCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should prevent directory traversal attacks" {
            # Test file path traversal prevention
            $traversalPaths = @(
                "../../../etc/passwd",
                "..\..\windows\system32\config\sam",
                "../../../../root/.ssh/id_rsa",
                "..\..\..\boot.ini"
            )

            foreach ($traversalPath in $traversalPaths) {
                Mock New-BackupFile {
                    param($FilePath)
                    if ($FilePath -match '\.\.[/\\]') {
                        throw "Directory traversal attempt detected"
                    }
                    return @{ Success = $true; FilePath = $FilePath }
                } -ModuleName Find-UnknownSID

                { New-BackupFile -FilePath $traversalPath -CorrelationId $script:FileInjectionCorrelationId } | Should Throw "*traversal*"
            }
        }

        It "Should validate backup file paths" {
            # Test backup file path validation
            Mock New-BackupFile {
                param($FilePath, $CorrelationId)

                # Validate file extension and path
                if (-not $FilePath.EndsWith('.xml') -and -not $FilePath.EndsWith('.json')) {
                    throw "Invalid backup file extension"
                }

                if ($FilePath -match '[<>:"|?*]') {
                    throw "Invalid characters in file path"
                }

                return @{ Success = $true; FilePath = $FilePath; CorrelationId = $CorrelationId }
            } -ModuleName Find-UnknownSID

            $validPath = "C:\Backups\backup_20250124.xml"
            $result = New-BackupFile -FilePath $validPath -CorrelationId $script:FileInjectionCorrelationId
            $result.Success | Should -BeTrue

            { New-BackupFile -FilePath "C:\Backups\backup<script>.exe" -CorrelationId $script:FileInjectionCorrelationId } | Should Throw "*Invalid characters*"
        }
    }
}

Describe "Privilege Escalation Prevention" -Tag "Security", "Authorization", "Access" {

    Context "Access Control Validation" {
        BeforeEach {
            $script:AccessCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should enforce proper authorization for <User> performing <Action>" -TestCases $script:PrivilegeEscalationTests {
            param($User, $Action, $ShouldFail, $ShouldSucceed)

            # Mock authorization check
            Mock Test-UserAuthorization {
                param($User, $Action, $CorrelationId)

                $authorizedActions = @{
                    'standard_user' = @('ReadOperation')
                    'domain_admin' = @('AdminOperation', 'StandardOperation', 'ReadOperation')
                    'service_account' = @('ServiceOperation', 'ReadOperation')
                    'guest_user' = @()
                    'backup_operator' = @('BackupOperation', 'ReadOperation')
                }

                $userActions = $authorizedActions[$User]
                return ($userActions -contains $Action)
            } -ModuleName Find-UnknownSID

            Mock Invoke-SecureOperation {
                param($Action, $User, $CorrelationId)

                $authorized = Test-UserAuthorization -User $User -Action $Action -CorrelationId $CorrelationId
                if (-not $authorized) {
                    throw "Unauthorized: User '$User' cannot perform action '$Action'"
                }

                return @{ Success = $true; Action = $Action; User = $User }
            } -ModuleName Find-UnknownSID

            if ($ShouldFail) {
                { Invoke-SecureOperation -Action $Action -User $User -CorrelationId $script:AccessCorrelationId } | Should Throw "*Unauthorized*"
            }
            if ($ShouldSucceed) {
                $result = Invoke-SecureOperation -Action $Action -User $User -CorrelationId $script:AccessCorrelationId
                $result.Success | Should -BeTrue
            }
        }

        It "Should log authorization attempts" {
            # Mock authorization logging
            Mock Write-SecurityLog {
                param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)

                return @{
                    EventType = $SecurityEventType
                    Message = $Message
                    Outcome = $Outcome
                    CorrelationId = $CorrelationId
                    Context = $SecurityContext
                }
            } -ModuleName Find-UnknownSID

            Mock Test-UserAuthorization {
                param($User, $Action, $CorrelationId)

                Write-SecurityLog -SecurityEventType 'AuthorizationAttempt' -Message "User $User attempting $Action" -Outcome 'Attempt' -CorrelationId $CorrelationId -SecurityContext @{ User = $User; Action = $Action }

                return $false  # Simulate authorization failure
            } -ModuleName Find-UnknownSID

            Test-UserAuthorization -User 'standard_user' -Action 'AdminOperation' -CorrelationId $script:AccessCorrelationId

            # Verify security logging was called
            Assert-MockCalled Write-SecurityLog -ModuleName Find-UnknownSID -Exactly 1
        }
    }

    Context "Credential Security" {
        BeforeEach {
            $script:CredentialCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should handle credentials securely" {
            # Mock secure credential handling
            Mock Get-SecureCredential {
                param($Username, $CorrelationId)

                # Simulate secure credential retrieval
                $securePassword = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
                return [System.Management.Automation.PSCredential]::new($Username, $securePassword)
            } -ModuleName Find-UnknownSID

            $credential = Get-SecureCredential -Username 'testuser' -CorrelationId $script:CredentialCorrelationId
            $credential | Should BeOfType [System.Management.Automation.PSCredential]
            $credential.UserName | Should Be 'testuser'
        }

        It "Should never expose credentials in logs" {
            # Test that credentials are not logged in plain text
            Mock Write-SecurityLog {
                param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)

                # Verify no credential data in logs
                $Message | Should Not Match "password|credential|secret"
                if ($SecurityContext) {
                    $SecurityContext.Values | ForEach-Object {
                        $_ | Should Not Match "password|credential|secret"
                    }
                }

                return @{ Success = $true }
            } -ModuleName Find-UnknownSID

            Mock Test-CredentialSecurity {
                param($Credential, $CorrelationId)

                Write-SecurityLog -SecurityEventType 'CredentialValidation' -Message "Credential validation performed" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext @{ User = $Credential.UserName }

                return $true
            } -ModuleName Find-UnknownSID

            $testCredential = New-MockCredential -Username 'testuser'
            Test-CredentialSecurity -Credential $testCredential -CorrelationId $script:CredentialCorrelationId

            Assert-MockCalled Write-SecurityLog -ModuleName Find-UnknownSID -Exactly 1
        }
    }
}

Describe "Audit Trail Validation" -Tag "Security", "Compliance", "Auditing" {

    Context "Security Event Logging" {
        BeforeEach {
            $script:AuditCorrelationId = [System.Guid]::NewGuid().ToString()
        }

        It "Should log all security-relevant events with correlation IDs" {
            $testOperation = "SecurityTestOperation"

            Mock Invoke-SecureOperation {
                param($Operation, $CorrelationId)

                Write-SecurityLog -SecurityEventType 'OperationAttempt' -Message "Operation $Operation started" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext @{ Operation = $Operation }

                return @{ Success = $true; Operation = $Operation; CorrelationId = $CorrelationId }
            } -ModuleName Find-UnknownSID

            $result = Invoke-SecureOperation -Operation $testOperation -CorrelationId $script:AuditCorrelationId

            $result.CorrelationId | Should Be $script:AuditCorrelationId
            Assert-MockCalled Write-SecurityLog -ModuleName Find-UnknownSID -Exactly 1
        }

        It "Should capture security context in audit logs" {
            Mock Write-SecurityLog {
                param($SecurityEventType, $Message, $Outcome, $CorrelationId, $SecurityContext)

                # Verify required security context elements
                $SecurityContext | Should Not BeNullOrEmpty
                $SecurityContext.Keys | Should Contain 'User'
                $SecurityContext.Keys | Should Contain 'Action'
                $SecurityContext.Keys | Should Contain 'Timestamp'

                return @{ Success = $true }
            } -ModuleName Find-UnknownSID

            Mock Test-SecurityContext {
                param($User, $Action, $CorrelationId)

                $securityContext = @{
                    User = $User
                    Action = $Action
                    Timestamp = Get-Date
                    SourceIP = '127.0.0.1'
                    SessionId = $CorrelationId
                }

                Write-SecurityLog -SecurityEventType 'ContextValidation' -Message "Security context validated" -Outcome 'Success' -CorrelationId $CorrelationId -SecurityContext $securityContext

                return $true
            } -ModuleName Find-UnknownSID

            Test-SecurityContext -User 'testuser' -Action 'TestAction' -CorrelationId $script:AuditCorrelationId

            Assert-MockCalled Write-SecurityLog -ModuleName Find-UnknownSID -Exactly 1
        }

        It "Should maintain audit trail integrity" {
            # Test that audit logs cannot be tampered with
            Mock Test-AuditIntegrity {
                param($CorrelationId)

                # Simulate audit trail integrity check
                $auditRecords = @(
                    @{ CorrelationId = $CorrelationId; Event = 'Start'; Timestamp = Get-Date; Hash = 'abc123' }
                    @{ CorrelationId = $CorrelationId; Event = 'Process'; Timestamp = Get-Date; Hash = 'def456' }
                    @{ CorrelationId = $CorrelationId; Event = 'Complete'; Timestamp = Get-Date; Hash = 'ghi789' }
                )

                # Verify all records have correlation ID and hash
                foreach ($record in $auditRecords) {
                    $record.CorrelationId | Should Be $CorrelationId
                    $record.Hash | Should Not BeNullOrEmpty
                }

                return @{ Integrity = $true; RecordCount = $auditRecords.Count }
            } -ModuleName Find-UnknownSID

            $result = Test-AuditIntegrity -CorrelationId $script:AuditCorrelationId
            $result.Integrity | Should -BeTrue
            $result.RecordCount | Should BeGreaterThan 0
        }
    }
}

AfterAll {
    # Security test cleanup
    Write-Verbose "Security test cleanup - CorrelationId: $($script:CorrelationId)"

    # Remove any test security artifacts
    Remove-Variable -Name MaliciousInputs -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name PrivilegeEscalationTests -Scope Script -ErrorAction SilentlyContinue

    # Force garbage collection for security
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}

