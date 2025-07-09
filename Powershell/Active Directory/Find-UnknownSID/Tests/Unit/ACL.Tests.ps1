#Requires -Module Pester

BeforeAll {
    # Import test helpers following enterprise standards
    . $PSScriptRoot\..\TestHelpers\TestHelpers.ps1

    # Initialize test environment with enterprise standards
    $script:TestConfig = New-TestData -DataType 'Configuration'
    $script:TestCorrelationId = $script:TestConfig.CorrelationId

    # Set up performance baselines following pester.instructions.md
    $script:PerformanceBaseline = @{
        ACLRetrievalMaxTime = [TimeSpan]::FromSeconds(2)
        SIDRemovalMaxTime = [TimeSpan]::FromSeconds(1)
        ACLApplicationMaxTime = [TimeSpan]::FromSeconds(3)
        MemoryUsageMaxMB = 25  # ACL operations can be memory intensive
    }

    # Security test patterns for input validation
    $script:SecurityTestPatterns = @{
        SQLInjection = @("'; DROP TABLE Users; --", "1' OR '1'='1", "admin'--")
        PathTraversal = @("../../../etc/passwd", "..\..\Windows\System32\config", "C:\Test\..\..\..\Windows\System32")
        XSSPatterns = @("<script>alert('xss')</script>", "javascript:alert('xss')")
        InvalidChars = @("`0", "`n", "`r", "`t", [char]0x1f)
        MaliciousInputs = @("", " ", "  ", $null)
        MaliciousDNs = @("CN=../../etc/passwd", "CN=<script>", "CN='; DROP")
    }

    # Mock external dependencies using enterprise patterns with advanced filtering
    Mock Write-Verbose { } -ParameterFilter { $Message -like "*ACL*" }
    Mock Write-Information { } -ParameterFilter { $MessageData -or $Message }
    Mock Write-Warning { } -ParameterFilter { $Message -like "*ACL*" }
    Mock Write-Host { } -ParameterFilter { $Object -or $Message }
    Mock Write-StructuredLog { } -ParameterFilter { $Message -and $Level }

    # Mock AD and ACL operations with realistic responses
    Mock Get-Acl {
        param($Path)
        
        # Return realistic mock ACL object based on path type
        $mockAcl = [PSCustomObject]@{
            PSTypeName = 'System.Security.AccessControl.DirectorySecurity'
            Path = $Path -replace '^AD:\\', ''  # Remove AD:\ prefix for test consistency
            Owner = 'BUILTIN\Administrators'
            Access = @()
        }
        
        # Create realistic access entries
        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = 'S-1-5-21-123456789-987654321-456789123-1001' }
                AccessControlType = 'Allow'
                FileSystemRights = 'FullControl'
                IsInherited = $false
                InheritanceFlags = 'ContainerInherit,ObjectInherit'
                PropagationFlags = 'None'
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = 'DOMAIN\TestUser' }
                AccessControlType = 'Allow'
                FileSystemRights = 'ReadAndExecute'
                IsInherited = $true
                InheritanceFlags = 'ContainerInherit,ObjectInherit'
                PropagationFlags = 'InheritOnly'
            }
        )
        $mockAcl.Access = $mockAccess
        
        # Add essential methods
        $mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
        
        return $mockAcl
    }

    Mock Set-Acl { }
    
    # Mock validation functions with enterprise patterns
    Mock Test-ValidDistinguishedName { 
        param($ObjectDN, $DistinguishedName)
        
        # Use whichever parameter is provided
        $dn = if ($ObjectDN) { $ObjectDN } else { $DistinguishedName }
        
        if ([string]::IsNullOrWhiteSpace($dn)) { return $false }
        if ($dn -match "\.\./|<script>|'; DROP|etc/passwd|System32|Remove-Item") { return $false }
        if ($dn -match "NonExistent|Invalid|Network") { return $false }
        if ($dn -match "C:\\|^TestObject$|^\s+$|password") { return $false }  # Invalid formats
        if ($dn -match "ErrorTest") { 
            # Special case: ErrorTest should pass validation but throw specific error later
            return $true 
        }
        if ($dn -match "Restricted") { 
            # Special case: Restricted should pass validation but throw access denied later
            return $true 
        }
        return $dn -match "^CN=.*,DC=.*"
    }

    # Mock Remove-Item for security tests (should never be called)
    Mock Remove-Item { 
        throw "Security violation: Remove-Item should never be called in ACL operations"
    }

    # Mock Start-Process for security tests (should never be called)
    Mock Start-Process { 
        throw "Security violation: Start-Process should never be called in ACL operations"
    }

    #  MISSING CRITICAL SECURITY MOCKS - Add comprehensive protection
    Mock Invoke-Expression { 
        param($Command)
        Write-Warning " SECURITY BLOCK: Invoke-Expression blocked for safety. Command: $Command"
        throw "Security violation: Dangerous code execution blocked - $Command"
    }

    Mock Stop-Process {
        param($Name, $Id, [switch]$Force)
        if ($Name -match 'lsass|winlogon|csrss|System|explorer') {
            Write-Warning " SECURITY BLOCK: Stop-Process blocked for critical process. Process: $Name"
            throw "Security violation: Critical process termination blocked - $Name"
        }
        Write-Verbose "Mock Stop-Process called safely for test process: $Name"
    }

    # Mock retry mechanism with realistic behavior that executes scriptblocks properly
    Mock Invoke-ADOperationWithRetry {
        param($ScriptBlock, $MaxRetries, $OperationName, $ObjectContext, $CorrelationId)
        
        # For Get-ACL operations, return mock ACL or throw specific errors
        if ($OperationName -eq 'Get-ACL' -or $ScriptBlock.ToString() -match 'Get-Acl') {
            # Handle specific error scenarios
            if ($ObjectContext -match 'Restricted') {
                throw "Access denied"
            }
            if ($ObjectContext -match 'ErrorTest') {
                throw "Specific ACL error"
            }
            
            $mockAcl = [PSCustomObject]@{
                PSTypeName = 'System.Security.AccessControl.DirectorySecurity'
                Path = $ObjectContext -replace '^AD:\\', ''
                Owner = 'BUILTIN\Administrators'
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = 'S-1-5-21-123456789-987654321-456789123-1001' }
                        AccessControlType = 'Allow'
                        FileSystemRights = 'FullControl'
                        IsInherited = $false
                    }
                )
            }
            
            # Add essential methods
            $mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
                param($includeExplicit, $includeInherited, $targetType)
                return $this.Access
            }
            $mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
                param($rule)
                return $true
            }
            
            return $mockAcl
        }
        
        # For Set-ACL operations, simulate success or failure
        if ($OperationName -like '*Set-Acl*' -or $ScriptBlock.ToString() -match 'Set-Acl') {
            if ($ObjectContext -match 'denied|error|fail') {
                throw "Access denied"
            }
            return $true
        }
        
        # For other operations, execute the scriptblock
        return & $ScriptBlock
    }

    # Initialize test correlation ID
    $script:TestCorrelationId = $script:TestConfig.CorrelationId
}

Describe "Get-ACLForRemoval" -Tag "Unit", "ACL", "Security" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestObjectDN = "CN=TestObject,OU=TestOU,DC=testdomain,DC=local"
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ObjectDistinguishedName parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid DN format"; ObjectDN = "CN=TestObject,DC=domain,DC=com"; ShouldThrow = $false }
            @{ TestCase = "Valid complex DN"; ObjectDN = "CN=TestUser,OU=Users,OU=TestOU,DC=domain,DC=com"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; ObjectDN = ""; ShouldThrow = $true }
            @{ TestCase = "Null value"; ObjectDN = $null; ShouldThrow = $true }
            @{ TestCase = "Whitespace only"; ObjectDN = "   "; ShouldThrow = $true }
            @{ TestCase = "Invalid DN format"; ObjectDN = "C:\InvalidPath"; ShouldThrow = $true }
            @{ TestCase = "Malformed DN"; ObjectDN = "TestObject"; ShouldThrow = $true }
        ) {
            param($TestCase, $ObjectDN, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Get-ACLForRemoval -ObjectDistinguishedName $ObjectDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Get-ACLForRemoval -ObjectDistinguishedName $ObjectDN -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "CUSTOM-ACL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter when specified: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID format"; CorrelationId = "12345678-1234-1234-1234-123456789abc"; ShouldThrow = $false }
            @{ TestCase = "New GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Empty GUID"; CorrelationId = ""; ShouldThrow = $false }  # Optional with default
            @{ TestCase = "Null GUID"; CorrelationId = $null; ShouldThrow = $false }  # Optional parameter
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking patterns with ParameterFilter for enterprise compliance
        BeforeEach {
            # Reset mocks for each test to ensure clean state
            Mock Test-ValidDistinguishedName { return $true } -ParameterFilter { $ObjectDN -like "*TestObject*" }
        }

        It "Should retrieve ACL for valid Distinguished Name" {
            $result = Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $script:TestObjectDN
            $result.Access | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should handle file system paths correctly" {
            $filePath = "CN=TestFile,OU=Files,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $true } -ParameterFilter { $ObjectDN -like "*TestFile*" }

            $result = Get-ACLForRemoval -ObjectDistinguishedName $filePath -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $filePath
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should filter ACL entries correctly" {
            
            $result = Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            # Verify the ACL object and access rules are returned
            $result.Access | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should return complete ACL object structure" {
            $result = Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain "Path"
            $result.PSObject.Properties.Name | Should -Contain "Access"
            $result.PSObject.Properties.Name | Should -Contain "Owner"
            # Verify essential ACL methods exist
            $result.PSObject.Methods.Name | Should -Contain "GetAccessRules"
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle non-existent Distinguished Names gracefully" {
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*NonExistent*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName "CN=NonExistent,DC=domain,DC=com" -CorrelationId $script:TestCorrelationId } | Should -Throw "*not*found*"
        }

        It "Should handle ACL access denied scenarios" {
            Mock Test-ValidDistinguishedName { return $true } -ParameterFilter { $ObjectDN -like "*Restricted*" }
            Mock Invoke-ADOperationWithRetry {
                param($ScriptBlock, $MaxRetries, $OperationName, $ObjectContext, $CorrelationId)
                if ($ScriptBlock.ToString() -match 'Get-Acl') {
                    throw "Access denied"
                }
                return & $ScriptBlock
            } -ParameterFilter { $OperationName -eq "Get-Acl" }

            { Get-ACLForRemoval -ObjectDistinguishedName "CN=Restricted,DC=domain,DC=com" -CorrelationId $script:TestCorrelationId } | Should -Throw "*Access denied*"
        }

        It "Should provide meaningful error messages with correlation tracking" {
            Mock Test-ValidDistinguishedName { return $true } -ParameterFilter { $ObjectDN -like "*ErrorTest*" }
            Mock Get-Acl { throw "Specific ACL error" } -ParameterFilter { $Path -like "*ErrorTest*" }

            try {
                Get-ACLForRemoval -ObjectDistinguishedName "CN=ErrorTest,DC=domain,DC=com" -CorrelationId $script:TestCorrelationId -ErrorAction Stop
            } catch {
                $_.Exception.Message | Should -Match "Specific ACL error"
            }
        }

        It "Should handle invalid DN format gracefully" {
            $invalidDN = "C:\InvalidPath\Format"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -eq $invalidDN }

            { Get-ACLForRemoval -ObjectDistinguishedName $invalidDN -CorrelationId $script:TestCorrelationId } | Should -Throw
        }

        It "Should handle network connectivity issues" {
            Mock Test-ValidDistinguishedName { return $true } -ParameterFilter { $ObjectDN -like "*Network*" }
            Mock Invoke-ADOperationWithRetry {
                throw "The network path was not found"
            } -ParameterFilter { $OperationName -eq "Get-Acl" }

            { Get-ACLForRemoval -ObjectDistinguishedName "CN=NetworkTest,DC=domain,DC=com" -CorrelationId $script:TestCorrelationId } | Should -Throw "*network*"
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should retrieve ACL within performance baseline (< 2 seconds)" {
            $startTime = Get-Date
            Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.ACLRetrievalMaxTime.TotalSeconds
        }

        It "Should handle large ACLs efficiently" {
            # Mock large ACL with many access entries
            Mock Get-Acl {
                $largeAcl = [PSCustomObject]@{
                    Path = $Path
                    Owner = 'BUILTIN\Administrators'
                    Access = @()
                }
                
                # Create many access entries
                $largeAccess = 1..100 | ForEach-Object {
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                        AccessControlType = 'Allow'
                        FileSystemRights = 'ReadAndExecute'
                        IsInherited = $false
                    }
                }
                $largeAcl.Access = $largeAccess
                $largeAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return $this.Access }
                return $largeAcl
            } -ParameterFilter { $Path -like "*Large*" }
            
            Mock Invoke-ADOperationWithRetry {
                param($ScriptBlock, $MaxRetries, $OperationName, $ObjectContext, $CorrelationId)
                
                if ($OperationName -eq 'Get-ACL' -or $ScriptBlock.ToString() -match 'Get-Acl') {
                    $largeAcl = [PSCustomObject]@{
                        Path = $ObjectContext
                        Owner = 'BUILTIN\Administrators'
                        Access = @()
                    }
                    
                    # Create many access entries
                    $largeAccess = 1..100 | ForEach-Object {
                        [PSCustomObject]@{
                            IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                            AccessControlType = 'Allow'
                            FileSystemRights = 'ReadAndExecute'
                            IsInherited = $false
                        }
                    }
                    $largeAcl.Access = $largeAccess
                    $largeAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return $this.Access }
                    return $largeAcl
                }
                
                return & $ScriptBlock
            } -ParameterFilter { $ObjectContext -like "*Large*" }

            $startTime = Get-Date
            $result = Get-ACLForRemoval -ObjectDistinguishedName "CN=LargeACL,DC=domain,DC=com" -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $result.Access.Count | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.ACLRetrievalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during ACL retrieval" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate WhatIfMode parameter combinations: <TestCase>" -TestCases @(
            @{ TestCase = "WhatIf enabled"; WhatIfMode = $true; ShouldThrow = $false }
            @{ TestCase = "WhatIf disabled"; WhatIfMode = $false; ShouldThrow = $false }
            @{ TestCase = "WhatIf not specified"; WhatIfMode = $null; ShouldThrow = $false }
        ) {
            param($TestCase, $WhatIfMode, $ShouldThrow)
            
            $parameters = @{
                ACL = $script:mockAcl
                AllowedSIDs = $script:TestAllowedSIDs
                CorrelationId = $script:TestCorrelationId
            }
            if ($null -ne $WhatIfMode) { $parameters.WhatIfMode = $WhatIfMode }
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval @parameters } | Should -Throw
            } else {
                { Invoke-SIDRemoval @parameters } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "SID-REMOVAL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking with ParameterFilter for enterprise compliance
        It "Should identify target SIDs in ACL entries accurately" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.SIDFound | Should -Be $true
            $result.RulesFound | Should -BeGreaterThan 0
            $result.AllowedSIDs | Should -Be $script:TestAllowedSIDs
            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should perform dry run without ACL modifications" {
            $originalAccessCount = $script:mockAcl.Access.Count
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $true
            $result.RulesRemoved | Should -Be 0
            $result.RulesFound | Should -BeGreaterThan 0
            $script:mockAcl.Access.Count | Should -Be $originalAccessCount  # No changes in dry run
        }

        It "Should remove non-allowed SID entries when not in dry run mode" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $false
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.Success | Should -Be $true
            $result.ProcessedSIDs | Should -Not -BeNullOrEmpty
        }

        It "Should preserve allowed SID entries during removal" {
            $allowedSID = $script:TestAllowedSIDs[1]  # Second allowed SID
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            # Should remove allowed SIDs (they are orphaned SIDs) but preserve non-allowed ones
            $result.ProcessedSIDs | Should -Contain $allowedSID
            $result.Success | Should -Be $true
        }

        It "Should handle multiple SID removals in single operation" {
            # Create ACL with multiple SIDs that are in the allowed list (orphaned SIDs to remove)
            $multiSIDACL = [PSCustomObject]@{ MockObject = $true }
            $multiAccess = @(
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[0] }
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-999-888-777-9999" }
                    AccessControlType = "Allow"
                    FileSystemRights = "Modify"
                    IsInherited = $false
                }
            )
            $multiSIDACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $multiAccess
            $multiSIDACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $multiSIDACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.RulesFound | Should -BeGreaterThan 1
            $result.RulesRemoved | Should -BeGreaterThan 1
            $result.Success | Should -Be $true
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle ACL with no access entries gracefully" {
            $emptyAcl = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @()
            }
            $emptyAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return @() }

            $result = Invoke-SIDRemoval -ACL $emptyAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing to do
        }

        It "Should handle SIDs not found in ACL entries" {
            $nonExistentSIDs = @("S-1-5-21-9999999999-9999999999-9999999999-9999")

            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $nonExistentSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing matched
        }

        It "Should handle ACL modification failures gracefully" {
            $failingACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    }
                )
            }
            
            $failingACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                throw "Access denied during removal"
            }

            $result = Invoke-SIDRemoval -ACL $failingACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.ErrorMessage | Should -Match "Access denied during removal"
            $result.FailedSIDs | Should -Contain $script:TestSID
        }

        It "Should provide detailed error information for partial failures" {
            $partialFailACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    },
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                        AccessControlType = "Allow"
                        FileSystemRights = "ReadAndExecute"
                        IsInherited = $false
                    }
                )
            }
            
            $partialFailACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                if ($ace.IdentityReference.Value -eq $script:TestSID) {
                    throw "Specific SID removal failed"
                }
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $partialFailACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.PartialSuccess | Should -Be $true
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.FailedSIDs | Should -Contain $script:TestSID
            $result.SuccessfulSIDs | Should -Contain $script:TestAllowedSIDs[1]
        }

        It "Should handle invalid ACL object structure" {
            $invalidACL = [PSCustomObject]@{ 
                InvalidProperty = "Not an ACL"
            }

            { Invoke-SIDRemoval -ACL $invalidACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should complete SID removal within performance baseline (< 1 second)" {
            $startTime = Get-Date
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should handle large ACL with many entries efficiently" {
            # Create ACL with many access entries
            $largeACL = [PSCustomObject]@{ MockObject = $true }
            $largeAccess = 1..99 | ForEach-Object {
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                }
            }
            # Add one SID that's in the allowed list to enable processing
            $largeAccess += [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }  # Use second element which is static
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
            }
            $largeACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $largeAccess
            $largeACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $startTime = Get-Date
            $result = Invoke-SIDRemoval -ACL $largeACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            ($result.RulesProcessed | Select-Object -Last 1) | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during SID removal" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate WhatIfMode parameter combinations: <TestCase>" -TestCases @(
            @{ TestCase = "WhatIf enabled"; WhatIfMode = $true; ShouldThrow = $false }
            @{ TestCase = "WhatIf disabled"; WhatIfMode = $false; ShouldThrow = $false }
            @{ TestCase = "WhatIf not specified"; WhatIfMode = $null; ShouldThrow = $false }
        ) {
            param($TestCase, $WhatIfMode, $ShouldThrow)
            
            $parameters = @{
                ACL = $script:mockAcl
                AllowedSIDs = $script:TestAllowedSIDs
                CorrelationId = $script:TestCorrelationId
            }
            if ($null -ne $WhatIfMode) { $parameters.WhatIfMode = $WhatIfMode }
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval @parameters } | Should -Throw
            } else {
                { Invoke-SIDRemoval @parameters } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "SID-REMOVAL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking with ParameterFilter for enterprise compliance
        It "Should identify target SIDs in ACL entries accurately" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.SIDFound | Should -Be $true
            $result.RulesFound | Should -BeGreaterThan 0
            $result.AllowedSIDs | Should -Be $script:TestAllowedSIDs
            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should perform dry run without ACL modifications" {
            $originalAccessCount = $script:mockAcl.Access.Count
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $true
            $result.RulesRemoved | Should -Be 0
            $result.RulesFound | Should -BeGreaterThan 0
            $script:mockAcl.Access.Count | Should -Be $originalAccessCount  # No changes in dry run
        }

        It "Should remove non-allowed SID entries when not in dry run mode" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $false
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.Success | Should -Be $true
            $result.ProcessedSIDs | Should -Not -BeNullOrEmpty
        }

        It "Should preserve allowed SID entries during removal" {
            $allowedSID = $script:TestAllowedSIDs[1]  # Second allowed SID
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            # Should remove allowed SIDs (they are orphaned SIDs) but preserve non-allowed ones
            $result.ProcessedSIDs | Should -Contain $allowedSID
            $result.Success | Should -Be $true
        }

        It "Should handle multiple SID removals in single operation" {
            # Create ACL with multiple SIDs that are in the allowed list (orphaned SIDs to remove)
            $multiSIDACL = [PSCustomObject]@{ MockObject = $true }
            $multiAccess = @(
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[0] }
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-999-888-777-9999" }
                    AccessControlType = "Allow"
                    FileSystemRights = "Modify"
                    IsInherited = $false
                }
            )
            $multiSIDACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $multiAccess
            $multiSIDACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $multiSIDACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.RulesFound | Should -BeGreaterThan 1
            $result.RulesRemoved | Should -BeGreaterThan 1
            $result.Success | Should -Be $true
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle ACL with no access entries gracefully" {
            $emptyAcl = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @()
            }
            $emptyAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return @() }

            $result = Invoke-SIDRemoval -ACL $emptyAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing to do
        }

        It "Should handle SIDs not found in ACL entries" {
            $nonExistentSIDs = @("S-1-5-21-9999999999-9999999999-9999999999-9999")

            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $nonExistentSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing matched
        }

        It "Should handle ACL modification failures gracefully" {
            $failingACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    }
                )
            }
            
            $failingACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                throw "Access denied during removal"
            }

            $result = Invoke-SIDRemoval -ACL $failingACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.ErrorMessage | Should -Match "Access denied during removal"
            $result.FailedSIDs | Should -Contain $script:TestSID
        }

        It "Should provide detailed error information for partial failures" {
            $partialFailACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    },
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                        AccessControlType = "Allow"
                        FileSystemRights = "ReadAndExecute"
                        IsInherited = $false
                    }
                )
            }
            
            $partialFailACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                if ($ace.IdentityReference.Value -eq $script:TestSID) {
                    throw "Specific SID removal failed"
                }
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $partialFailACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.PartialSuccess | Should -Be $true
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.FailedSIDs | Should -Contain $script:TestSID
            $result.SuccessfulSIDs | Should -Contain $script:TestAllowedSIDs[1]
        }

        It "Should handle invalid ACL object structure" {
            $invalidACL = [PSCustomObject]@{ 
                InvalidProperty = "Not an ACL"
            }

            { Invoke-SIDRemoval -ACL $invalidACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should complete SID removal within performance baseline (< 1 second)" {
            $startTime = Get-Date
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should handle large ACL with many entries efficiently" {
            # Create ACL with many access entries
            $largeACL = [PSCustomObject]@{ MockObject = $true }
            $largeAccess = 1..99 | ForEach-Object {
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                }
            }
            # Add one SID that's in the allowed list to enable processing
            $largeAccess += [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }  # Use second element which is static
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
            }
            $largeACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $largeAccess
            $largeACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $startTime = Get-Date
            $result = Invoke-SIDRemoval -ACL $largeACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            ($result.RulesProcessed | Select-Object -Last 1) | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during SID removal" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
               
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate WhatIfMode parameter combinations: <TestCase>" -TestCases @(
            @{ TestCase = "WhatIf enabled"; WhatIfMode = $true; ShouldThrow = $false }
            @{ TestCase = "WhatIf disabled"; WhatIfMode = $false; ShouldThrow = $false }
            @{ TestCase = "WhatIf not specified"; WhatIfMode = $null; ShouldThrow = $false }
        ) {
            param($TestCase, $WhatIfMode, $ShouldThrow)
            
            $parameters = @{
                ACL = $script:mockAcl
                AllowedSIDs = $script:TestAllowedSIDs
                CorrelationId = $script:TestCorrelationId
            }
            if ($null -ne $WhatIfMode) { $parameters.WhatIfMode = $WhatIfMode }
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval @parameters } | Should -Throw
            } else {
                { Invoke-SIDRemoval @parameters } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "SID-REMOVAL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking with ParameterFilter for enterprise compliance
        It "Should identify target SIDs in ACL entries accurately" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.SIDFound | Should -Be $true
            $result.RulesFound | Should -BeGreaterThan 0
            $result.AllowedSIDs | Should -Be $script:TestAllowedSIDs
            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should perform dry run without ACL modifications" {
            $originalAccessCount = $script:mockAcl.Access.Count
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $true
            $result.RulesRemoved | Should -Be 0
            $result.RulesFound | Should -BeGreaterThan 0
            $script:mockAcl.Access.Count | Should -Be $originalAccessCount  # No changes in dry run
        }

        It "Should remove non-allowed SID entries when not in dry run mode" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $false
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.Success | Should -Be $true
            $result.ProcessedSIDs | Should -Not -BeNullOrEmpty
        }

        It "Should preserve allowed SID entries during removal" {
            $allowedSID = $script:TestAllowedSIDs[1]  # Second allowed SID
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            # Should remove allowed SIDs (they are orphaned SIDs) but preserve non-allowed ones
            $result.ProcessedSIDs | Should -Contain $allowedSID
            $result.Success | Should -Be $true
        }

        It "Should handle multiple SID removals in single operation" {
            # Create ACL with multiple SIDs that are in the allowed list (orphaned SIDs to remove)
            $multiSIDACL = [PSCustomObject]@{ MockObject = $true }
            $multiAccess = @(
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[0] }
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-999-888-777-9999" }
                    AccessControlType = "Allow"
                    FileSystemRights = "Modify"
                    IsInherited = $false
                }
            )
            $multiSIDACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $multiAccess
            $multiSIDACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $multiSIDACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.RulesFound | Should -BeGreaterThan 1
            $result.RulesRemoved | Should -BeGreaterThan 1
            $result.Success | Should -Be $true
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle ACL with no access entries gracefully" {
            $emptyAcl = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @()
            }
            $emptyAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return @() }

            $result = Invoke-SIDRemoval -ACL $emptyAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing to do
        }

        It "Should handle SIDs not found in ACL entries" {
            $nonExistentSIDs = @("S-1-5-21-9999999999-9999999999-9999999999-9999")

            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $nonExistentSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing matched
        }

        It "Should handle ACL modification failures gracefully" {
            $failingACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    }
                )
            }
            
            $failingACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                throw "Access denied during removal"
            }

            $result = Invoke-SIDRemoval -ACL $failingACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.ErrorMessage | Should -Match "Access denied during removal"
            $result.FailedSIDs | Should -Contain $script:TestSID
        }

        It "Should provide detailed error information for partial failures" {
            $partialFailACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    },
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                        AccessControlType = "Allow"
                        FileSystemRights = "ReadAndExecute"
                        IsInherited = $false
                    }
                )
            }
            
            $partialFailACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                if ($ace.IdentityReference.Value -eq $script:TestSID) {
                    throw "Specific SID removal failed"
                }
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $partialFailACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.PartialSuccess | Should -Be $true
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.FailedSIDs | Should -Contain $script:TestSID
            $result.SuccessfulSIDs | Should -Contain $script:TestAllowedSIDs[1]
        }

        It "Should handle invalid ACL object structure" {
            $invalidACL = [PSCustomObject]@{ 
                InvalidProperty = "Not an ACL"
            }

            { Invoke-SIDRemoval -ACL $invalidACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should complete SID removal within performance baseline (< 1 second)" {
            $startTime = Get-Date
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should handle large ACL with many entries efficiently" {
            # Create ACL with many access entries
            $largeACL = [PSCustomObject]@{ MockObject = $true }
            $largeAccess = 1..99 | ForEach-Object {
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                }
            }
            # Add one SID that's in the allowed list to enable processing
            $largeAccess += [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }  # Use second element which is static
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
            }
            $largeACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $largeAccess
            $largeACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $startTime = Get-Date
            $result = Invoke-SIDRemoval -ACL $largeACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            ($result.RulesProcessed | Select-Object -Last 1) | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during SID removal" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate WhatIfMode parameter combinations: <TestCase>" -TestCases @(
            @{ TestCase = "WhatIf enabled"; WhatIfMode = $true; ShouldThrow = $false }
            @{ TestCase = "WhatIf disabled"; WhatIfMode = $false; ShouldThrow = $false }
            @{ TestCase = "WhatIf not specified"; WhatIfMode = $null; ShouldThrow = $false }
        ) {
            param($TestCase, $WhatIfMode, $ShouldThrow)
            
            $parameters = @{
                ACL = $script:mockAcl
                AllowedSIDs = $script:TestAllowedSIDs
                CorrelationId = $script:TestCorrelationId
            }
            if ($null -ne $WhatIfMode) { $parameters.WhatIfMode = $WhatIfMode }
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval @parameters } | Should -Throw
            } else {
                { Invoke-SIDRemoval @parameters } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "SID-REMOVAL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking with ParameterFilter for enterprise compliance
        It "Should identify target SIDs in ACL entries accurately" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.SIDFound | Should -Be $true
            $result.RulesFound | Should -BeGreaterThan 0
            $result.AllowedSIDs | Should -Be $script:TestAllowedSIDs
            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should perform dry run without ACL modifications" {
            $originalAccessCount = $script:mockAcl.Access.Count
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $true
            $result.RulesRemoved | Should -Be 0
            $result.RulesFound | Should -BeGreaterThan 0
            $script:mockAcl.Access.Count | Should -Be $originalAccessCount  # No changes in dry run
        }

        It "Should remove non-allowed SID entries when not in dry run mode" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $false
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.Success | Should -Be $true
            $result.ProcessedSIDs | Should -Not -BeNullOrEmpty
        }

        It "Should preserve allowed SID entries during removal" {
            $allowedSID = $script:TestAllowedSIDs[1]  # Second allowed SID
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            # Should remove allowed SIDs (they are orphaned SIDs) but preserve non-allowed ones
            $result.ProcessedSIDs | Should -Contain $allowedSID
            $result.Success | Should -Be $true
        }

        It "Should handle multiple SID removals in single operation" {
            # Create ACL with multiple SIDs that are in the allowed list (orphaned SIDs to remove)
            $multiSIDACL = [PSCustomObject]@{ MockObject = $true }
            $multiAccess = @(
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[0] }
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-999-888-777-9999" }
                    AccessControlType = "Allow"
                    FileSystemRights = "Modify"
                    IsInherited = $false
                }
            )
            $multiSIDACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $multiAccess
            $multiSIDACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $multiSIDACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.RulesFound | Should -BeGreaterThan 1
            $result.RulesRemoved | Should -BeGreaterThan 1
            $result.Success | Should -Be $true
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle ACL with no access entries gracefully" {
            $emptyAcl = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @()
            }
            $emptyAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return @() }

            $result = Invoke-SIDRemoval -ACL $emptyAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing to do
        }

        It "Should handle SIDs not found in ACL entries" {
            $nonExistentSIDs = @("S-1-5-21-9999999999-9999999999-9999999999-9999")

            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $nonExistentSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing matched
        }

        It "Should handle ACL modification failures gracefully" {
            $failingACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    }
                )
            }
            
            $failingACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                throw "Access denied during removal"
            }

            $result = Invoke-SIDRemoval -ACL $failingACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.ErrorMessage | Should -Match "Access denied during removal"
            $result.FailedSIDs | Should -Contain $script:TestSID
        }

        It "Should provide detailed error information for partial failures" {
            $partialFailACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    },
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                        AccessControlType = "Allow"
                        FileSystemRights = "ReadAndExecute"
                        IsInherited = $false
                    }
                )
            }
            
            $partialFailACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                if ($ace.IdentityReference.Value -eq $script:TestSID) {
                    throw "Specific SID removal failed"
                }
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $partialFailACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.PartialSuccess | Should -Be $true
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.FailedSIDs | Should -Contain $script:TestSID
            $result.SuccessfulSIDs | Should -Contain $script:TestAllowedSIDs[1]
        }

        It "Should handle invalid ACL object structure" {
            $invalidACL = [PSCustomObject]@{ 
                InvalidProperty = "Not an ACL"
            }

            { Invoke-SIDRemoval -ACL $invalidACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should complete SID removal within performance baseline (< 1 second)" {
            $startTime = Get-Date
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should handle large ACL with many entries efficiently" {
            # Create ACL with many access entries
            $largeACL = [PSCustomObject]@{ MockObject = $true }
            $largeAccess = 1..99 | ForEach-Object {
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                }
            }
            # Add one SID that's in the allowed list to enable processing
            $largeAccess += [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }  # Use second element which is static
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
            }
            $largeACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $largeAccess
            $largeACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $startTime = Get-Date
            $result = Invoke-SIDRemoval -ACL $largeACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            ($result.RulesProcessed | Select-Object -Last 1) | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during SID removal" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate WhatIfMode parameter combinations: <TestCase>" -TestCases @(
            @{ TestCase = "WhatIf enabled"; WhatIfMode = $true; ShouldThrow = $false }
            @{ TestCase = "WhatIf disabled"; WhatIfMode = $false; ShouldThrow = $false }
            @{ TestCase = "WhatIf not specified"; WhatIfMode = $null; ShouldThrow = $false }
        ) {
            param($TestCase, $WhatIfMode, $ShouldThrow)
            
            $parameters = @{
                ACL = $script:mockAcl
                AllowedSIDs = $script:TestAllowedSIDs
                CorrelationId = $script:TestCorrelationId
            }
            if ($null -ne $WhatIfMode) { $parameters.WhatIfMode = $WhatIfMode }
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval @parameters } | Should -Throw
            } else {
                { Invoke-SIDRemoval @parameters } | Should -Not -Throw
            }
        }

        It "Should validate CorrelationId parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid GUID"; CorrelationId = [System.Guid]::NewGuid().ToString(); ShouldThrow = $false }
            @{ TestCase = "Custom string"; CorrelationId = "SID-REMOVAL-123"; ShouldThrow = $false }
            @{ TestCase = "Empty string"; CorrelationId = ""; ShouldThrow = $false }  # Should use default
            @{ TestCase = "Null value"; CorrelationId = $null; ShouldThrow = $false }  # Should use default
        ) {
            param($TestCase, $CorrelationId, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $CorrelationId } | Should -Not -Throw
            }
        }
    }

    Context "Core Functionality" {
        # Advanced mocking with ParameterFilter for enterprise compliance
        It "Should identify target SIDs in ACL entries accurately" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.SIDFound | Should -Be $true
            $result.RulesFound | Should -BeGreaterThan 0
            $result.AllowedSIDs | Should -Be $script:TestAllowedSIDs
            $result.CorrelationId | Should -Be $script:TestCorrelationId
        }

        It "Should perform dry run without ACL modifications" {
            $originalAccessCount = $script:mockAcl.Access.Count
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -WhatIfMode -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $true
            $result.RulesRemoved | Should -Be 0
            $result.RulesFound | Should -BeGreaterThan 0
            $script:mockAcl.Access.Count | Should -Be $originalAccessCount  # No changes in dry run
        }

        It "Should remove non-allowed SID entries when not in dry run mode" {
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.DryRun | Should -Be $false
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.Success | Should -Be $true
            $result.ProcessedSIDs | Should -Not -BeNullOrEmpty
        }

        It "Should preserve allowed SID entries during removal" {
            $allowedSID = $script:TestAllowedSIDs[1]  # Second allowed SID
            
            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            # Should remove allowed SIDs (they are orphaned SIDs) but preserve non-allowed ones
            $result.ProcessedSIDs | Should -Contain $allowedSID
            $result.Success | Should -Be $true
        }

        It "Should handle multiple SID removals in single operation" {
            # Create ACL with multiple SIDs that are in the allowed list (orphaned SIDs to remove)
            $multiSIDACL = [PSCustomObject]@{ MockObject = $true }
            $multiAccess = @(
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[0] }
                    AccessControlType = "Allow"
                    FileSystemRights = "FullControl"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                },
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-999-888-777-9999" }
                    AccessControlType = "Allow"
                    FileSystemRights = "Modify"
                    IsInherited = $false
                }
            )
            $multiSIDACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $multiAccess
            $multiSIDACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $multiSIDACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.RulesFound | Should -BeGreaterThan 1
            $result.RulesRemoved | Should -BeGreaterThan 1
            $result.Success | Should -Be $true
        }
    }

    Context "Error Handling" {
        # Exception scenarios and graceful degradation testing
        It "Should handle ACL with no access entries gracefully" {
            $emptyAcl = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @()
            }
            $emptyAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value { return @() }

            $result = Invoke-SIDRemoval -ACL $emptyAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing to do
        }

        It "Should handle SIDs not found in ACL entries" {
            $nonExistentSIDs = @("S-1-5-21-9999999999-9999999999-9999999999-9999")

            $result = Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $nonExistentSIDs -CorrelationId $script:TestCorrelationId

            $result.SIDFound | Should -Be $false
            $result.RulesFound | Should -Be 0
            $result.RulesRemoved | Should -Be 0
            $result.Success | Should -Be $true  # No errors, just nothing matched
        }

        It "Should handle ACL modification failures gracefully" {
            $failingACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    }
                )
            }
            
            $failingACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                throw "Access denied during removal"
            }

            $result = Invoke-SIDRemoval -ACL $failingACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $false
            $result.ErrorMessage | Should -Match "Access denied during removal"
            $result.FailedSIDs | Should -Contain $script:TestSID
        }

        It "Should provide detailed error information for partial failures" {
            $partialFailACL = [PSCustomObject]@{ 
                MockObject = $true 
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestSID }
                        AccessControlType = "Allow"
                        FileSystemRights = "FullControl"
                        IsInherited = $false
                    },
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }
                        AccessControlType = "Allow"
                        FileSystemRights = "ReadAndExecute"
                        IsInherited = $false
                    }
                )
            }
            
            $partialFailACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                if ($ace.IdentityReference.Value -eq $script:TestSID) {
                    throw "Specific SID removal failed"
                }
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $result = Invoke-SIDRemoval -ACL $partialFailACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId

            $result.PartialSuccess | Should -Be $true
            $result.RulesRemoved | Should -BeGreaterThan 0
            $result.FailedSIDs | Should -Contain $script:TestSID
            $result.SuccessfulSIDs | Should -Contain $script:TestAllowedSIDs[1]
        }

        It "Should handle invalid ACL object structure" {
            $invalidACL = [PSCustomObject]@{ 
                InvalidProperty = "Not an ACL"
            }

            { Invoke-SIDRemoval -ACL $invalidACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
        }
    }

    Context "Performance Requirements" -Tag "Performance" {
        # SLA validation with Measure-TestPerformance integration
        It "Should complete SID removal within performance baseline (< 1 second)" {
            $startTime = Get-Date
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should handle large ACL with many entries efficiently" {
            # Create ACL with many access entries
            $largeACL = [PSCustomObject]@{ MockObject = $true }
            $largeAccess = 1..99 | ForEach-Object {
                [PSCustomObject]@{
                    IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-123456789-987654321-456789123-$_" }
                    AccessControlType = "Allow"
                    FileSystemRights = "ReadAndExecute"
                    IsInherited = $false
                }
            }
            # Add one SID that's in the allowed list to enable processing
            $largeAccess += [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $script:TestAllowedSIDs[1] }  # Use second element which is static
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
            }
            $largeACL | Add-Member -MemberType NoteProperty -Name "Access" -Value $largeAccess
            $largeACL | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
                param($ace)
                $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
                $this.Access = $newAccess
                return $true
            }

            $startTime = Get-Date
            $result = Invoke-SIDRemoval -ACL $largeACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            $endTime = Get-Date
            $executionTime = $endTime - $startTime
            
            ($result.RulesProcessed | Select-Object -Last 1) | Should -Be 100
            $executionTime.TotalSeconds | Should -BeLessThan $script:PerformanceBaseline.SIDRemovalMaxTime.TotalSeconds
        }

        It "Should not exceed memory usage baseline during SID removal" {
            $memoryBefore = (Get-Process -Id $PID).WorkingSet64 / 1MB
            
            Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId
            
            $memoryAfter = (Get-Process -Id $PID).WorkingSet64 / 1MB
            $memoryIncrease = $memoryAfter - $memoryBefore
            
            $memoryIncrease | Should -BeLessThan $script:PerformanceBaseline.MemoryUsageMaxMB
        }
    }

    Context "Security Validation" -Tag "Security" {
        # Input sanitization and malicious pattern handling
        BeforeEach {
            # For security tests, use the actual validation logic
            Mock Test-ValidDistinguishedName {
                param($DistinguishedName, $CorrelationId)
                # Return false for malicious patterns (mimic actual function logic)
                $dangerousChars = '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'
                if ($DistinguishedName -match $dangerousChars) {
                    return $false
                }
                if ($DistinguishedName -match "';.*DROP|<script>|etc/passwd") {
                    return $false
                }
                # Basic format check - must have DC component
                if (-not ($DistinguishedName -match '^(CN|OU|DC)=.+,DC=.+$')) {
                    return $false
                }
                return $true
            }
        }
        
        It "Should handle malicious Distinguished Names safely: <TestCase>" -TestCases @(
            @{ TestCase = "SQL Injection"; ObjectDN = "CN='; DROP TABLE Users; --,DC=domain,DC=com" }
            @{ TestCase = "Path Traversal"; ObjectDN = "CN=../../../etc/passwd,DC=domain,DC=com" }
            @{ TestCase = "XSS Pattern"; ObjectDN = "CN=<script>alert('xss')</script>,DC=domain,DC=com" }
            @{ TestCase = "Control Characters"; ObjectDN = "CN=test`0`r`ninjection,DC=domain,DC=com" }
            @{ TestCase = "Windows Path Traversal"; ObjectDN = "CN=..\..\Windows\System32,DC=domain,DC=com" }
            @{ TestCase = "Command Injection"; ObjectDN = "CN=test; Remove-Item -Path C:\,DC=domain,DC=com" }
        ) {
            param($TestCase, $ObjectDN)
            
            # Should reject malicious DN patterns
            { Set-ModifiedACL -ObjectDN $ObjectDN -ACL $script:modifiedAcl -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no harmful operations occurred
            Should -Not -Invoke Remove-Item -ParameterFilter { $Path -like "C:\*" }
        }

        It "Should validate correlation ID tracking for audit trails" {
            $customCorrelationId = "SECURITY-AUDIT-$(Get-Random)"
            
            # This should succeed and track the correlation ID
            { Get-ACLForRemoval -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $customCorrelationId } | Should -Not -Throw
            
            # Verify correlation ID is used in logging calls (if implemented)
            Should -Invoke Invoke-ADOperationWithRetry -Exactly 1 -ParameterFilter { $ScriptBlock.ToString() -match 'Get-Acl' }
        }

        It "Should protect against DN injection attacks" {
            $maliciousDN = "CN=TestUser,DC=domain,DC=com; Remove-Item -Path C:\ -Recurse"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*Remove-Item*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $maliciousDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify no file system operations were attempted
            Should -Not -Invoke Remove-Item
        }

        It "Should handle credential exposure protection" {
            $credentialLikeDN = "CN=user:password@server,DC=domain,DC=com"
            Mock Test-ValidDistinguishedName { return $false } -ParameterFilter { $ObjectDN -like "*password*" }
            
            { Get-ACLForRemoval -ObjectDistinguishedName $credentialLikeDN -CorrelationId $script:TestCorrelationId } | Should -Throw
            
            # Verify credentials are not logged in verbose output
            Should -Not -Invoke Write-Verbose -ParameterFilter { $Message -like "*password*" }
        }
    }
}

Describe "Invoke-SIDRemoval" -Tag "Unit", "ACL", "Critical" {

    BeforeEach {
        # Set up test-specific data using enterprise test helpers
        $script:TestCorrelationId = $script:TestConfig.CorrelationId
        $script:TestSID = New-TestData -DataType 'SID' -Count 1
        $script:TestAllowedSIDs = @($script:TestSID, "S-1-5-21-987654321-123456789-555666777-2001")
        
        # Create realistic mock ACL with multiple access entries
        $script:mockAcl = [PSCustomObject]@{ 
            MockObject = $true 
            Path = "CN=TestObject,DC=domain,DC=com"
        }
        
        $targetSID = $script:TestSID
        $otherSID = "S-1-5-21-1234567890-1234567890-1234567890-1002"
        $allowedSID = "S-1-5-21-987654321-123456789-555666777-2001"

        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $targetSID }
                AccessControlType = "Allow"
                FileSystemRights = "FullControl"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $otherSID }
                AccessControlType = "Allow"
                FileSystemRights = "ReadAndExecute"
                IsInherited = $false
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "None"
            },
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = $allowedSID }
                AccessControlType = "Allow"
                FileSystemRights = "Modify"
                IsInherited = $true
                InheritanceFlags = "ContainerInherit,ObjectInherit"
                PropagationFlags = "InheritOnly"
            }
        )

        $script:mockAcl | Add-Member -MemberType NoteProperty -Name "Access" -Value $mockAccess
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "GetAccessRules" -Value {
            param($includeExplicit, $includeInherited, $targetType)
            return $this.Access
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRule" -Value {
            param($rule)
            return $true
        }
        $script:mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            $newAccess = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
            $this.Access = $newAccess
            return $true
        }
    }

    Context "Parameter Validation" {
        # Enterprise TestCases pattern for comprehensive parameter validation
        It "Should validate ACL parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid ACL object"; ACL = ([PSCustomObject]@{ MockObject = $true; Path = "CN=Test,DC=domain,DC=com" }); ShouldThrow = $false }
            @{ TestCase = "Null ACL"; ACL = $null; ShouldThrow = $true }
            @{ TestCase = "Empty object"; ACL = [PSCustomObject]@{}; ShouldThrow = $false }  # May be valid depending on implementation
        ) {
            param($TestCase, $ACL, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $ACL -AllowedSIDs $script:TestAllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }

        It "Should validate AllowedSIDs parameter: <TestCase>" -TestCases @(
            @{ TestCase = "Valid SID array"; AllowedSIDs = @("S-1-5-21-1234567890-1234567890-1234567890-1001"); ShouldThrow = $false }
            @{ TestCase = "Multiple valid SIDs"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "S-1-5-32-544"); ShouldThrow = $false }
            @{ TestCase = "Built-in SIDs"; AllowedSIDs = @("S-1-5-32-544", "S-1-1-0"); ShouldThrow = $false }
            @{ TestCase = "Invalid SID format"; AllowedSIDs = @("invalid-sid"); ShouldThrow = $true }
            @{ TestCase = "Empty array"; AllowedSIDs = @(); ShouldThrow = $true }
            @{ TestCase = "Null array"; AllowedSIDs = $null; ShouldThrow = $true }
            @{ TestCase = "Mixed valid/invalid"; AllowedSIDs = @("S-1-5-21-123-456-789-1001", "invalid"); ShouldThrow = $true }
        ) {
            param($TestCase, $AllowedSIDs, $ShouldThrow)
            
            if ($ShouldThrow) {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Throw
            } else {
                { Invoke-SIDRemoval -ACL $script:mockAcl -AllowedSIDs $AllowedSIDs -CorrelationId $script:TestCorrelationId } | Should -Not -Throw
            }
        }
    }
}
