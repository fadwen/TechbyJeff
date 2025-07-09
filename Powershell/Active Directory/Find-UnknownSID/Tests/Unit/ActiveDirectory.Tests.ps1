#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
. $testBootstrapper
}
# Import ActiveDirectory module functions for testing
$ADModulePath = Join-Path $PSScriptRoot '..\..\Private\ActiveDirectory'
Get-ChildItem -Path $ADModulePath -Filter '*.ps1' | ForEach-Object {
. #Requires -Module Pester


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

        It "Should accept valid parameters" {
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Not Throw
        }

        It "Should validate DistinguishedName format for SearchBase" {
            { Get-ADObjectFromSearchBase -SearchBase "InvalidDN" -Filter $script:TestFilter } | Should Throw "*DistinguishedName*"
        }

        It "Should accept correlation ID parameter" {
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should call Get-ADObject with correct parameters" {
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = "CN=TestUser,OU=Users,DC=contoso,DC=com" } }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            Should Invoke Get-ADObject -Exactly 1 -Scope It
            $result | Should Not BeNullOrEmpty
        }

        It "Should handle empty search results gracefully" {
            Mock Get-ADObject { return $null }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should BeNullOrEmpty
        }

        It "Should return multiple objects when found" {
            $mockObjects = @(
                @{ Name = "User1"; DistinguishedName = "CN=User1,OU=Users,DC=contoso,DC=com" },
                @{ Name = "User2"; DistinguishedName = "CN=User2,OU=Users,DC=contoso,DC=com" }
            )
            Mock Get-ADObject { return $mockObjects }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should -HaveCount 2
            $result[0].Name | Should Be "User1"
            $result[1].Name | Should Be "User2"
        }
    }

    Context "Error Handling" {
        It "Should handle Active Directory connection errors" {
            Mock Get-ADObject { throw "Unable to contact the server" }

            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Unable to contact the server*"
        }

        It "Should handle invalid search base errors" {
            Mock Get-ADObject { throw "A referral was returned from the server" }

            { Get-ADObjectFromSearchBase -SearchBase "OU=Invalid,DC=invalid,DC=com" -Filter $script:TestFilter } | Should Throw "*referral*"
        }

        It "Should handle authentication errors" {
            Mock Get-ADObject { throw "Access is denied" }

            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Access is denied*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete within acceptable time for small searches" {
            Mock Get-ADObject { Start-Sleep -Milliseconds 50; return @{ Name = "TestUser" } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle large result sets efficiently" {
            $largeResultSet = 1..1000 | ForEach-Object { @{ Name = "User$_"; DistinguishedName = "CN=User$_,OU=Users,DC=contoso,DC=com" } }
            Mock Get-ADObject { return $largeResultSet }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should -HaveCount 1000
        }
    }

    Context "Audit and Compliance" {
        It "Should log search operations with correlation ID" {
            Mock Write-StructuredLog { }

            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }

        It "Should include search parameters in audit log" {
            Mock Write-StructuredLog { }

            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$($script:TestSearchBase)*" }
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
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList } | Should Not Throw
        }

        It "Should accept batch size parameter" {
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 50 } | Should Not Throw
        }

        It "Should validate batch size is positive" {
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 0 } | Should Throw "*BatchSize*"
        }
    }

    Context "Core Functionality" {
        It "Should process objects in sequential batches" {
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = $Identity } }

            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 1

            Should Invoke Get-ADObject -Exactly 2 -Scope It
            $result | Should -HaveCount 2
        }

        It "Should handle empty object list" {
            $result = Get-ADObjectsSequential -ObjectList @()

            $result | Should BeNullOrEmpty
        }

        It "Should respect batch size limits" {
            $largeObjectList = 1..10 | ForEach-Object { "CN=User$_,OU=Users,DC=contoso,DC=com" }
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = $Identity } }

            $result = Get-ADObjectsSequential -ObjectList $largeObjectList -BatchSize 3

            Should Invoke Get-ADObject -Exactly 10 -Scope It
            $result | Should -HaveCount 10
        }
    }

    Context "Error Handling" {
        It "Should handle individual object lookup failures" {
            Mock Get-ADObject {
                if ($Identity -eq "CN=User1,OU=Users,DC=contoso,DC=com") {
                    throw "Object not found"
                }
                return @{ Name = "TestUser"; DistinguishedName = $Identity }
            }

            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction Continue

            $result | Should -HaveCount 1
            $result[0].DistinguishedName | Should Be "CN=User2,OU=Users,DC=contoso,DC=com"
        }

        It "Should continue processing after errors when specified" {
            Mock Get-ADObject { throw "Connection timeout" }

            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction Continue } | Should Not Throw
        }
    }

    Context "Performance and Memory Management" {
        It "Should use memory efficiently for large batches" {
            $largeObjectList = 1..100 | ForEach-Object { "CN=User$_,OU=Users,DC=contoso,DC=com" }
            Mock Get-ADObject { return @{ Name = "User$Identity"; DistinguishedName = $Identity } }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Get-ADObjectsSequential -ObjectList $largeObjectList -BatchSize 10
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 10MB
        }
    }

Describe "Invoke-ADOperationWithRetry" -Tag "Unit", "ActiveDirectory", "Reliability" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestScriptBlock = { Get-ADUser -Identity "testuser" }
    }

    Context "Parameter Validation" {
        It "Should require ScriptBlock parameter" {
            { Invoke-ADOperationWithRetry } | Should Throw "*ScriptBlock*"
        }

        It "Should accept retry count parameter" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 5 } | Should Not Throw
        }

        It "Should validate retry count is non-negative" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries -1 } | Should Throw "*MaxRetries*"
        }

        It "Should accept retry delay parameter" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should execute script block successfully on first try" {
            Mock Get-ADUser { return @{ Name = "TestUser"; SamAccountName = "testuser" } }

            $result = Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock

            $result | Should Not BeNullOrEmpty
            $result.SamAccountName | Should Be "testuser"
        }

        It "Should retry on transient failures" {
            $global:CallCount = 0
            Mock Get-ADUser {
                $global:CallCount++
                if ($global:CallCount -lt 3) {
                    throw "The server is not operational"
                }
                return @{ Name = "TestUser"; SamAccountName = "testuser" }
            }

            $result = Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 3

            $result | Should Not BeNullOrEmpty
            $global:CallCount | Should Be 3
        }

        It "Should fail after maximum retries exceeded" {
            Mock Get-ADUser { throw "Persistent error" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw "*Persistent error*"
        }

        It "Should implement exponential backoff delay" {
            Mock Start-Sleep { }
            Mock Get-ADUser { throw "Temporary failure" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 3 } | Should Throw

            Should Invoke Start-Sleep -Times 3 -Scope It
        }
    }

    Context "Error Classification" {
        It "Should retry on network errors" {
            Mock Get-ADUser { throw "The RPC server is unavailable" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 3 -Scope It  # Initial + 2 retries
        }

        It "Should not retry on authentication errors" {
            Mock Get-ADUser { throw "Logon failure: unknown user name or bad password" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 1 -Scope It  # No retries for auth errors
        }

        It "Should not retry on object not found errors" {
            Mock Get-ADUser { throw "Cannot find an object with identity" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 1 -Scope It  # No retries for not found
        }
    }

    Context "Audit and Compliance" {
        It "Should log retry attempts with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ADUser { throw "The server is not operational" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 -CorrelationId $script:TestCorrelationId } | Should Throw

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*retry*" }
        }
    }

Describe "Test-ValidDistinguishedName" -Tag "Unit", "ActiveDirectory", "Validation" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require DistinguishedName parameter" {
            { Test-ValidDistinguishedName } | Should Throw "*DistinguishedName*"
        }

        It "Should accept string input" {
            { Test-ValidDistinguishedName -DistinguishedName "CN=Test,DC=contoso,DC=com" } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Test-ValidDistinguishedName -DistinguishedName "CN=Test,DC=contoso,DC=com" -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Valid Distinguished Name Formats" {
        It "Should validate standard user DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=John Doe,OU=Users,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate computer DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=WORKSTATION01,OU=Computers,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate group DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Domain Admins,CN=Users,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate organizational unit DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "OU=Sales,OU=Departments,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate complex DN with special characters" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test\, User,OU=Special Characters,DC=contoso,DC=com"

            $result | Should Be $true
        }
    }

    Context "Invalid Distinguished Name Formats" {
        It "Should reject empty string" {
            $result = Test-ValidDistinguishedName -DistinguishedName ""

            $result | Should Be $false
        }

        It "Should reject null value" {
            $result = Test-ValidDistinguishedName -DistinguishedName $null

            $result | Should Be $false
        }

        It "Should reject malformed DN without DC component" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users"

            $result | Should Be $false
        }

        It "Should reject DN with invalid component separator" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test;OU=Users;DC=contoso;DC=com"

            $result | Should Be $false
        }

        It "Should reject DN with missing component values" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=,OU=Users,DC=contoso,DC=com"

            $result | Should Be $false
        }

        It "Should reject plain text that is not a DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "This is not a distinguished name"

            $result | Should Be $false
        }
    }

    Context "Performance and Edge Cases" {
        It "Should handle very long distinguished names" {
            $longOU = "A" * 200
            $longDN = "CN=Test,OU=$longOU,DC=contoso,DC=com"

            $result = Test-ValidDistinguishedName -DistinguishedName $longDN

            $result | Should Be $true
        }

        It "Should complete validation within acceptable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users,DC=contoso,DC=com"
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 100
        }
    }

    Context "Audit and Compliance" {
        It "Should log validation attempts with correlation ID" {
            Mock Write-StructuredLog { }

            Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users,DC=contoso,DC=com" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }

        It "Should log validation results for audit trail" {
            Mock Write-StructuredLog { }

            Test-ValidDistinguishedName -DistinguishedName "Invalid DN"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*validation*" }
        }
    }
}





.FullName
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

        It "Should accept valid parameters" {
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Not Throw
        }

        It "Should validate DistinguishedName format for SearchBase" {
            { Get-ADObjectFromSearchBase -SearchBase "InvalidDN" -Filter $script:TestFilter } | Should Throw "*DistinguishedName*"
        }

        It "Should accept correlation ID parameter" {
            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should call Get-ADObject with correct parameters" {
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = "CN=TestUser,OU=Users,DC=contoso,DC=com" } }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            Should Invoke Get-ADObject -Exactly 1 -Scope It
            $result | Should Not BeNullOrEmpty
        }

        It "Should handle empty search results gracefully" {
            Mock Get-ADObject { return $null }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should BeNullOrEmpty
        }

        It "Should return multiple objects when found" {
            $mockObjects = @(
                @{ Name = "User1"; DistinguishedName = "CN=User1,OU=Users,DC=contoso,DC=com" },
                @{ Name = "User2"; DistinguishedName = "CN=User2,OU=Users,DC=contoso,DC=com" }
            )
            Mock Get-ADObject { return $mockObjects }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should -HaveCount 2
            $result[0].Name | Should Be "User1"
            $result[1].Name | Should Be "User2"
        }
    }

    Context "Error Handling" {
        It "Should handle Active Directory connection errors" {
            Mock Get-ADObject { throw "Unable to contact the server" }

            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Unable to contact the server*"
        }

        It "Should handle invalid search base errors" {
            Mock Get-ADObject { throw "A referral was returned from the server" }

            { Get-ADObjectFromSearchBase -SearchBase "OU=Invalid,DC=invalid,DC=com" -Filter $script:TestFilter } | Should Throw "*referral*"
        }

        It "Should handle authentication errors" {
            Mock Get-ADObject { throw "Access is denied" }

            { Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter } | Should Throw "*Access is denied*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete within acceptable time for small searches" {
            Mock Get-ADObject { Start-Sleep -Milliseconds 50; return @{ Name = "TestUser" } }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle large result sets efficiently" {
            $largeResultSet = 1..1000 | ForEach-Object { @{ Name = "User$_"; DistinguishedName = "CN=User$_,OU=Users,DC=contoso,DC=com" } }
            Mock Get-ADObject { return $largeResultSet }

            $result = Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            $result | Should -HaveCount 1000
        }
    }

    Context "Audit and Compliance" {
        It "Should log search operations with correlation ID" {
            Mock Write-StructuredLog { }

            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }

        It "Should include search parameters in audit log" {
            Mock Write-StructuredLog { }

            Get-ADObjectFromSearchBase -SearchBase $script:TestSearchBase -Filter $script:TestFilter

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$($script:TestSearchBase)*" }
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
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList } | Should Not Throw
        }

        It "Should accept batch size parameter" {
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 50 } | Should Not Throw
        }

        It "Should validate batch size is positive" {
            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 0 } | Should Throw "*BatchSize*"
        }
    }

    Context "Core Functionality" {
        It "Should process objects in sequential batches" {
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = $Identity } }

            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -BatchSize 1

            Should Invoke Get-ADObject -Exactly 2 -Scope It
            $result | Should -HaveCount 2
        }

        It "Should handle empty object list" {
            $result = Get-ADObjectsSequential -ObjectList @()

            $result | Should BeNullOrEmpty
        }

        It "Should respect batch size limits" {
            $largeObjectList = 1..10 | ForEach-Object { "CN=User$_,OU=Users,DC=contoso,DC=com" }
            Mock Get-ADObject { return @{ Name = "TestUser"; DistinguishedName = $Identity } }

            $result = Get-ADObjectsSequential -ObjectList $largeObjectList -BatchSize 3

            Should Invoke Get-ADObject -Exactly 10 -Scope It
            $result | Should -HaveCount 10
        }
    }

    Context "Error Handling" {
        It "Should handle individual object lookup failures" {
            Mock Get-ADObject {
                if ($Identity -eq "CN=User1,OU=Users,DC=contoso,DC=com") {
                    throw "Object not found"
                }
                return @{ Name = "TestUser"; DistinguishedName = $Identity }
            }

            $result = Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction Continue

            $result | Should -HaveCount 1
            $result[0].DistinguishedName | Should Be "CN=User2,OU=Users,DC=contoso,DC=com"
        }

        It "Should continue processing after errors when specified" {
            Mock Get-ADObject { throw "Connection timeout" }

            { Get-ADObjectsSequential -ObjectList $script:TestObjectList -ErrorAction Continue } | Should Not Throw
        }
    }

    Context "Performance and Memory Management" {
        It "Should use memory efficiently for large batches" {
            $largeObjectList = 1..100 | ForEach-Object { "CN=User$_,OU=Users,DC=contoso,DC=com" }
            Mock Get-ADObject { return @{ Name = "User$Identity"; DistinguishedName = $Identity } }

            $memoryBefore = [System.GC]::GetTotalMemory($false)
            $result = Get-ADObjectsSequential -ObjectList $largeObjectList -BatchSize 10
            $memoryAfter = [System.GC]::GetTotalMemory($false)

            $memoryIncrease = $memoryAfter -$memoryBefore
            $memoryIncrease | Should BeLessThan 10MB
        }
    }

Describe "Invoke-ADOperationWithRetry" -Tag "Unit", "ActiveDirectory", "Reliability" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestScriptBlock = { Get-ADUser -Identity "testuser" }
    }

    Context "Parameter Validation" {
        It "Should require ScriptBlock parameter" {
            { Invoke-ADOperationWithRetry } | Should Throw "*ScriptBlock*"
        }

        It "Should accept retry count parameter" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 5 } | Should Not Throw
        }

        It "Should validate retry count is non-negative" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries -1 } | Should Throw "*MaxRetries*"
        }

        It "Should accept retry delay parameter" {
            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should execute script block successfully on first try" {
            Mock Get-ADUser { return @{ Name = "TestUser"; SamAccountName = "testuser" } }

            $result = Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock

            $result | Should Not BeNullOrEmpty
            $result.SamAccountName | Should Be "testuser"
        }

        It "Should retry on transient failures" {
            $global:CallCount = 0
            Mock Get-ADUser {
                $global:CallCount++
                if ($global:CallCount -lt 3) {
                    throw "The server is not operational"
                }
                return @{ Name = "TestUser"; SamAccountName = "testuser" }
            }

            $result = Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 3

            $result | Should Not BeNullOrEmpty
            $global:CallCount | Should Be 3
        }

        It "Should fail after maximum retries exceeded" {
            Mock Get-ADUser { throw "Persistent error" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw "*Persistent error*"
        }

        It "Should implement exponential backoff delay" {
            Mock Start-Sleep { }
            Mock Get-ADUser { throw "Temporary failure" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 3 } | Should Throw

            Should Invoke Start-Sleep -Times 3 -Scope It
        }
    }

    Context "Error Classification" {
        It "Should retry on network errors" {
            Mock Get-ADUser { throw "The RPC server is unavailable" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 3 -Scope It  # Initial + 2 retries
        }

        It "Should not retry on authentication errors" {
            Mock Get-ADUser { throw "Logon failure: unknown user name or bad password" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 1 -Scope It  # No retries for auth errors
        }

        It "Should not retry on object not found errors" {
            Mock Get-ADUser { throw "Cannot find an object with identity" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 } | Should Throw

            Should Invoke Get-ADUser -Times 1 -Scope It  # No retries for not found
        }
    }

    Context "Audit and Compliance" {
        It "Should log retry attempts with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-ADUser { throw "The server is not operational" }

            { Invoke-ADOperationWithRetry -ScriptBlock $script:TestScriptBlock -MaxRetries 2 -CorrelationId $script:TestCorrelationId } | Should Throw

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*retry*" }
        }
    }

Describe "Test-ValidDistinguishedName" -Tag "Unit", "ActiveDirectory", "Validation" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
    }

    Context "Parameter Validation" {
        It "Should require DistinguishedName parameter" {
            { Test-ValidDistinguishedName } | Should Throw "*DistinguishedName*"
        }

        It "Should accept string input" {
            { Test-ValidDistinguishedName -DistinguishedName "CN=Test,DC=contoso,DC=com" } | Should Not Throw
        }

        It "Should accept correlation ID parameter" {
            { Test-ValidDistinguishedName -DistinguishedName "CN=Test,DC=contoso,DC=com" -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Valid Distinguished Name Formats" {
        It "Should validate standard user DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=John Doe,OU=Users,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate computer DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=WORKSTATION01,OU=Computers,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate group DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Domain Admins,CN=Users,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate organizational unit DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "OU=Sales,OU=Departments,DC=contoso,DC=com"

            $result | Should Be $true
        }

        It "Should validate complex DN with special characters" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test\, User,OU=Special Characters,DC=contoso,DC=com"

            $result | Should Be $true
        }
    }

    Context "Invalid Distinguished Name Formats" {
        It "Should reject empty string" {
            $result = Test-ValidDistinguishedName -DistinguishedName ""

            $result | Should Be $false
        }

        It "Should reject null value" {
            $result = Test-ValidDistinguishedName -DistinguishedName $null

            $result | Should Be $false
        }

        It "Should reject malformed DN without DC component" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users"

            $result | Should Be $false
        }

        It "Should reject DN with invalid component separator" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=Test;OU=Users;DC=contoso;DC=com"

            $result | Should Be $false
        }

        It "Should reject DN with missing component values" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=,OU=Users,DC=contoso,DC=com"

            $result | Should Be $false
        }

        It "Should reject plain text that is not a DN" {
            $result = Test-ValidDistinguishedName -DistinguishedName "This is not a distinguished name"

            $result | Should Be $false
        }
    }

    Context "Performance and Edge Cases" {
        It "Should handle very long distinguished names" {
            $longOU = "A" * 200
            $longDN = "CN=Test,OU=$longOU,DC=contoso,DC=com"

            $result = Test-ValidDistinguishedName -DistinguishedName $longDN

            $result | Should Be $true
        }

        It "Should complete validation within acceptable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users,DC=contoso,DC=com"
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 100
        }
    }

    Context "Audit and Compliance" {
        It "Should log validation attempts with correlation ID" {
            Mock Write-StructuredLog { }

            Test-ValidDistinguishedName -DistinguishedName "CN=Test,OU=Users,DC=contoso,DC=com" -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }

        It "Should log validation results for audit trail" {
            Mock Write-StructuredLog { }

            Test-ValidDistinguishedName -DistinguishedName "Invalid DN"

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*validation*" }
        }
    }
}







