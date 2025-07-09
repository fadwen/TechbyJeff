#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
    . $testBootstrapper
}

# Import ActiveDirectory module functions for testing
$ADModulePath = Join-Path $PSScriptRoot '..\..\Private\ActiveDirectory'
Get-ChildItem -Path $ADModulePath -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

# Import test helpers if they exist
$TestHelpersPath = Join-Path $PSScriptRoot '..\TestHelpers\TestHelpers.ps1'
if (Test-Path $TestHelpersPath) {
    . $TestHelpersPath
}

# Mock external dependencies
Mock Write-Verbose { }
Mock Write-Information { }
Mock Write-Warning { }
Mock Write-Error { }

# Mock Active Directory cmdlets
Mock Get-ADObject { return $null }
Mock Get-ADUser { return $null }
Mock Get-ADGroup { return $null }
Mock Get-ADComputer { return $null }
Mock Get-ADOrganizationalUnit { return $null }

# Mock logging function
Mock Write-StructuredLog { }

# Mock Start-Sleep for performance testing
Mock Start-Sleep { }

Describe "Get-ADObjectFromSearchBase" -Tag "Unit", "ActiveDirectory", "Core" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestSearchBase = "OU=TestOU,DC=contoso,DC=com"
        $script:TestFilter = "objectClass -eq 'user'"
    }

    Context "Parameter Validation" {
        It "Should require SearchBase parameter" {
            { Get-ADObjectFromSearchBase } | Should Throw "*SearchBase*"
        }

        It "Should require Filter parameter" {
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase } | Should Throw "*Filter*"
        }

        It "Should validate SearchBase format" {
            $invalidBases = @("", "  ", "InvalidFormat", "NotADN")
            foreach ($invalidBase in $invalidBases) {
                { Get-ADObjectFromSearchBase -SearchBase $invalidBase -Filter $script:TestFilter } | Should Throw
            }
        }

        It "Should accept valid DN format for SearchBase" {
            $validBases = @(
                "OU=TestOU,DC=contoso,DC=com",
                "CN=Users,DC=domain,DC=local",
                "DC=root,DC=domain"
            )
            foreach ($validBase in $validBases) {
                { Get-ADObjectFromSearchBase -SearchBase $validBase -Filter $script:TestFilter } | Should Not Throw
            }
        }
    }

    Context "Core Functionality" {
        It "Should call Get-ADObject with correct parameters" {
            Mock Get-ADObject { return @() }
            
            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            
            Should Invoke Get-ADObject -ParameterFilter { 
                $SearchBase -eq $script:TestSearchBase -and $Filter -eq $script:TestFilter 
            }
        }

        It "Should return empty array when no objects found" {
            Mock Get-ADObject { return @() }
            
            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            
            $result | Should BeOfType [Array]
            $result.Count | Should Be 0
        }

        It "Should return objects when found" {
            $mockObjects = @(
                [PSCustomObject]@{ Name = "User1"; DistinguishedName = "CN=User1,OU=Users,DC=contoso,DC=com" },
                [PSCustomObject]@{ Name = "User2"; DistinguishedName = "CN=User2,OU=Users,DC=contoso,DC=com" }
            )
            Mock Get-ADObject { return $mockObjects }
            
            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            
            $result.Count | Should Be 2
            $result[0].Name | Should Be "User1"
        }
    }

    Context "Error Handling" {
        It "Should handle AD service unavailable gracefully" {
            Mock Get-ADObject { throw "The server is not operational" }
            
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*server*not*operational*"
        }

        It "Should handle invalid credentials" {
            Mock Get-ADObject { throw "Logon failure: unknown user name or bad password" }
            
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Logon*failure*"
        }

        It "Should handle access denied errors" {
            Mock Get-ADObject { throw "Access is denied" }
            
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Access*denied*"
        }
    }

    Context "Performance and Logging" {
        It "Should complete within reasonable time" {
            Mock Get-ADObject { return @() }
            
            $executionTime = Measure-Command {
                Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            }
            
            $executionTime.TotalSeconds | Should BeLessThan 5
        }

        It "Should log search operation details" {
            Mock Write-StructuredLog { }
            Mock Get-ADObject { return @() }
            
            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            
            Should Invoke Write-StructuredLog -Times 1
        }

        It "Should include search parameters in audit log" {
            Mock Write-StructuredLog { }

            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$($script:TestSearchBase)*" }
        }
    }
}

Describe "Get-ADObjectsSequential" -Tag "Unit", "ActiveDirectory", "Performance" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestObjectList = @("CN=User1,OU=Users,DC=contoso,DC=com", "CN=User2,OU=Users,DC=contoso,DC=com")
    }

    Context "Parameter Validation" {
        It "Should require ObjectList parameter" {
            { Get-ADObjectsSequential } | Should Throw "*ObjectList*"
        }

        It "Should accept array of distinguished names" {
            Mock Get-ADObject { return $null }
            
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList } | Should Not Throw
        }

        It "Should handle empty array gracefully" {
            $result = Get-ADObjectsSequential -ObjectList @()
            
            $result | Should BeOfType [Array]
            $result.Count | Should Be 0
        }
    }

    Context "Sequential Processing" {
        It "Should process each object individually" {
            Mock Get-ADObject { return [PSCustomObject]@{ Name = "TestObject" } }
            
            Get-ADObjectsSequential -ObjectList $script:TestObjectList
            
            Should Invoke Get-ADObject -Times $script:TestObjectList.Count
        }

        It "Should continue processing if one object fails" {
            Mock Get-ADObject { 
                if ($Identity -eq $script:TestObjectList[0]) { throw "Object not found" }
                return [PSCustomObject]@{ Name = "TestObject" }
            }
            
            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction SilentlyContinue
            
            $result.Count | Should Be 1
        }

        It "Should maintain processing order" {
            $processedOrder = @()
            Mock Get-ADObject { 
                $processedOrder += $Identity
                return [PSCustomObject]@{ Name = $Identity; DistinguishedName = $Identity }
            }
            
            Get-ADObjectsSequential -ObjectList $script:TestObjectList
            
            $processedOrder[0] | Should Be $script:TestObjectList[0]
            $processedOrder[1] | Should Be $script:TestObjectList[1]
        }
    }

    Context "Performance Optimization" {
        It "Should have minimal delay between operations" {
            Mock Get-ADObject { return [PSCustomObject]@{ Name = "TestObject" } }
            
            $executionTime = Measure-Command {
                Get-ADObjectsSequential -ObjectList $script:TestObjectList
            }
            
            # Should complete quickly for small datasets
            $executionTime.TotalSeconds | Should BeLessThan 2
        }

        It "Should handle large object lists efficiently" {
            $largeObjectList = 1..50 | ForEach-Object { "CN=User$_,OU=Users,DC=contoso,DC=com" }
            Mock Get-ADObject { return [PSCustomObject]@{ Name = "TestObject" } }
            
            $executionTime = Measure-Command {
                Get-ADObjectsSequential -ObjectList $largeObjectList
            }
            
            # Should scale reasonably with larger datasets
            $executionTime.TotalSeconds | Should BeLessThan 10
        }
    }

    Context "Error Handling and Logging" {
        It "Should log processing progress" {
            Mock Write-StructuredLog { }
            Mock Get-ADObject { return [PSCustomObject]@{ Name = "TestObject" } }
            
            Get-ADObjectsSequential -ObjectList $script:TestObjectList
            
            Should Invoke Write-StructuredLog -AtLeast 1
        }

        It "Should handle partial failures gracefully" {
            Mock Get-ADObject { 
                if ($Identity -like "*User1*") { throw "Access denied" }
                return [PSCustomObject]@{ Name = "TestObject" }
            }
            Mock Write-StructuredLog { }
            
            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction SilentlyContinue
            
            $result.Count | Should Be 1
            Should Invoke Write-StructuredLog -ParameterFilter { $Level -eq "Error" } -AtLeast 1
        }
    }
}

Describe "Invoke-ADOperationWithRetry" -Tag "Unit", "ActiveDirectory", "Reliability" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestOperation = { Get-ADObject -Identity "CN=TestUser,DC=contoso,DC=com" }
        $script:RetryCount = 3
    }

    Context "Parameter Validation" {
        It "Should require Operation parameter" {
            { Invoke-ADOperationWithRetry } | Should Throw "*Operation*"
        }

        It "Should accept valid retry count" {
            Mock Start-Sleep { }
            
            { Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 5 } | Should Not Throw
        }

        It "Should handle zero retry count" {
            { Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 0 } | Should Not Throw
        }
    }

    Context "Retry Logic" {
        It "Should succeed on first attempt when operation succeeds" {
            Mock Invoke-Command { return "Success" }
            
            $result = Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries $script:RetryCount
            
            $result | Should Be "Success"
        }

        It "Should retry on transient failures" {
            $attemptCount = 0
            Mock Invoke-Command { 
                $attemptCount++
                if ($attemptCount -lt 2) { throw "The server is busy" }
                return "Success"
            }
            Mock Start-Sleep { }
            
            $result = Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries $script:RetryCount
            
            $result | Should Be "Success"
        }

        It "Should fail after max retries exceeded" {
            Mock Invoke-Command { throw "The server is busy" }
            Mock Start-Sleep { }
            
            { Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 2 } | Should Throw "*server*busy*"
        }

        It "Should wait between retry attempts" {
            Mock Invoke-Command { throw "The server is busy" }
            Mock Start-Sleep { }
            
            try {
                Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 2
            } catch { }
            
            Should Invoke Start-Sleep -Times 2
        }
    }

    Context "Error Classification" {
        It "Should not retry on non-transient errors" {
            Mock Invoke-Command { throw "Object not found" }
            
            { Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries $script:RetryCount } | Should Throw "*Object*not*found*"
        }

        It "Should retry on network-related errors" {
            $transientErrors = @(
                "The server is busy",
                "A connection timeout occurred",
                "The server is not operational"
            )
            
            foreach ($error in $transientErrors) {
                Mock Invoke-Command { throw $error }
                Mock Start-Sleep { }
                
                { Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 1 } | Should Throw
                Should Invoke Start-Sleep -Times 1
            }
        }
    }

    Context "Performance and Logging" {
        It "Should log retry attempts" {
            Mock Invoke-Command { throw "The server is busy" }
            Mock Start-Sleep { }
            Mock Write-StructuredLog { }
            
            try {
                Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 2
            } catch { }
            
            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*retry*" } -AtLeast 1
        }

        It "Should include correlation ID in retry logs" {
            Mock Invoke-Command { throw "The server is busy" }
            Mock Start-Sleep { }
            Mock Write-StructuredLog { }
            
            try {
                Invoke-ADOperationWithRetry -Operation $script:TestOperation -MaxRetries 1 -CorrelationId $script:TestCorrelationId
            } catch { }
            
            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }
    }
}

Describe "Test-ValidDistinguishedName" -Tag "Unit", "ActiveDirectory", "Validation" {

    Context "Valid DN Formats" {
        It "Should accept standard user DN" {
            $validDNs = @(
                "CN=John Doe,OU=Users,DC=contoso,DC=com",
                "CN=Jane Smith,OU=Marketing,OU=Departments,DC=company,DC=local",
                "CN=Administrator,CN=Users,DC=domain,DC=internal"
            )
            
            foreach ($dn in $validDNs) {
                Test-ValidDistinguishedName -DistinguishedName $dn | Should Be $true
            }
        }

        It "Should accept organizational unit DN" {
            $validOUs = @(
                "OU=Users,DC=contoso,DC=com",
                "OU=IT,OU=Departments,DC=company,DC=local",
                "OU=Servers,DC=domain,DC=internal"
            )
            
            foreach ($ou in $validOUs) {
                Test-ValidDistinguishedName -DistinguishedName $ou | Should Be $true
            }
        }

        It "Should accept domain DN" {
            $validDomains = @(
                "DC=contoso,DC=com",
                "DC=subdomain,DC=company,DC=local",
                "DC=root"
            )
            
            foreach ($domain in $validDomains) {
                Test-ValidDistinguishedName -DistinguishedName $domain | Should Be $true
            }
        }
    }

    Context "Invalid DN Formats" {
        It "Should reject malformed DNs" {
            $invalidDNs = @(
                "",
                "  ",
                "NotADN",
                "CN=",
                "=John Doe",
                "CN=John,Doe,OU=Users",
                "CN=User;OU=Test",
                "../../../etc/passwd",
                "<script>alert('xss')</script>"
            )
            
            foreach ($dn in $invalidDNs) {
                Test-ValidDistinguishedName -DistinguishedName $dn | Should Be $false
            }
        }

        It "Should reject null or empty input" {
            Test-ValidDistinguishedName -DistinguishedName $null | Should Be $false
            Test-ValidDistinguishedName -DistinguishedName "" | Should Be $false
            Test-ValidDistinguishedName -DistinguishedName "   " | Should Be $false
        }

        It "Should reject DNs with invalid characters" {
            $invalidCharDNs = @(
                "CN=User<script>,OU=Users,DC=test,DC=com",
                "CN=User`0,OU=Users,DC=test,DC=com",
                "CN=User;DROP TABLE,OU=Users,DC=test,DC=com"
            )
            
            foreach ($dn in $invalidCharDNs) {
                Test-ValidDistinguishedName -DistinguishedName $dn | Should Be $false
            }
        }
    }

    Context "Security Validation" {
        It "Should reject injection attempts" {
            $injectionAttempts = @(
                "CN='; DROP TABLE Users; --,OU=Users,DC=test,DC=com",
                "CN=User' OR '1'='1,OU=Users,DC=test,DC=com",
                "CN=User<script>alert('xss')</script>,OU=Users,DC=test,DC=com"
            )
            
            foreach ($attempt in $injectionAttempts) {
                Test-ValidDistinguishedName -DistinguishedName $attempt | Should Be $false
            }
        }

        It "Should log validation results for audit trail" {
            Mock Write-StructuredLog { }

            Test-ValidDistinguishedName -DistinguishedName "Invalid DN"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*validation*" }
        }
    }
}
