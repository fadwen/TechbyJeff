# Test-ValidDistinguishedName Tests - Pester 3.4.x Compatible

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

# Import the function under test
$functionPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))) "Private\ActiveDirectory\Test-ValidDistinguishedName.ps1"
if (Test-Path $functionPath) {
    . $functionPath
}

# Import dependencies
$basePath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
. (Join-Path $basePath "Private\Logging\Write-ADOperationSecurityLog.ps1")
. (Join-Path $basePath "Private\Logging\Write-StructuredLog.ps1")

Describe "Test-ValidDistinguishedName" {
    
    BeforeEach {
        # Set up test environment for clean execution
        $env:PESTER_TESTING = $true
        
        # Initialize comprehensive test data for DN validation
        $script:testData = @{
            ValidDNs = @(
                'CN=TestUser,OU=Users,DC=contoso,DC=com'
                'CN=Test Group,OU=Groups,OU=Security,DC=corp,DC=example,DC=org'
                'CN=Computer$,OU=Computers,DC=domain,DC=local'
                'OU=Organizational Unit,DC=test,DC=local'
                'CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com'
                'CN=Users,DC=child,DC=parent,DC=com'
                'DC=contoso,DC=com'
                'CN=Jeff Stuhr,OU=IT Department,OU=Corporate,DC=techbyjeff,DC=net'
                'CN=Server-01$,OU=Domain Controllers,DC=contoso,DC=com'
                'CN=Exchange Organization,CN=Microsoft Exchange,CN=Services,CN=Configuration,DC=contoso,DC=com'
            )
            
            InvalidDNs = @(
                'InvalidDN'
                'CN=User'
                'OU=NoCommonName'
                'DC=onlydc'
                'CN=,OU=Users,DC=contoso,DC=com'  # Empty CN
                'CN=User,OU=,DC=contoso,DC=com'   # Empty OU
                'CN=User,DC=,DC=com'              # Empty DC
                'CN User OU=Users DC=contoso DC=com'  # Missing separators
                'CN==User,OU=Users,DC=contoso,DC=com'  # Double equals
                'RDN=User,OU=Users,DC=contoso,DC=com'  # Invalid RDN type
                ''  # Empty string
            )
            
            MaliciousDNs = @(
                'CN=User$(Get-Process),OU=Users,DC=contoso,DC=com'
                "CN=User`$(Invoke-Expression 'whoami'),OU=Users,DC=contoso,DC=com"
                'CN=User;DROP TABLE Users;--,OU=Users,DC=contoso,DC=com'
                'CN=User&powershell.exe,OU=Users,DC=contoso,DC=com'
                'CN=User|Out-File malicious.txt,OU=Users,DC=contoso,DC=com'
                "CN=User`nInvoke-Command,OU=Users,DC=contoso,DC=com"
                'CN=../../../etc/passwd,OU=Users,DC=contoso,DC=com'
                'CN=User<script>alert("xss")</script>,OU=Users,DC=contoso,DC=com'
                'CN=User%00,OU=Users,DC=contoso,DC=com'  # Null byte injection
                'CN=User' + [char]0x00 + 'Hidden,OU=Users,DC=contoso,DC=com'
            )
        }
        
        # Mock dependencies to prevent noise during testing
        Mock Write-StructuredLog { }
        Mock Write-ADOperationSecurityLog { }
        Mock Write-Verbose { }
    }
    
    Context "Parameter Validation and Input Security" {
        It "Should handle empty string gracefully" {
            $result = '' | Test-ValidDistinguishedName
            $result | Should Be $false
        }
        
        It "Should accept string array via pipeline" {
            { $script:testData.ValidDNs[0..2] | Test-ValidDistinguishedName } | Should Not Throw
        }
        
        It "Should accept single string for DistinguishedName parameter" {
            { Test-ValidDistinguishedName -DistinguishedName $script:testData.ValidDNs[0] } | Should Not Throw
        }
        
        It "Should support CorrelationId parameter" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            
            { Test-ValidDistinguishedName -DistinguishedName $script:testData.ValidDNs[0] -CorrelationId $testCorrelationId } | Should Not Throw
        }
        
        It "Should auto-generate correlation ID when not provided" {
            { Test-ValidDistinguishedName -DistinguishedName $script:testData.ValidDNs[0] } | Should Not Throw
        }
        
        It "Should reject null input gracefully" {
            $result = Test-ValidDistinguishedName -DistinguishedName $null
            
            $result | Should Be $false
        }
        
        It "Should reject empty string input" {
            $result = Test-ValidDistinguishedName -DistinguishedName ''
            
            $result | Should Be $false
        }
    }
    
    Context "Basic DN Format Validation" {
        It "Should validate standard user DN format" {
            $userDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $userDN
            
            $result | Should Be $true
        }
        
        It "Should validate group DN format" {
            $groupDN = 'CN=Test Group,OU=Groups,OU=Security,DC=corp,DC=example,DC=org'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $groupDN
            
            $result | Should Be $true
        }
        
        It "Should validate computer DN format" {
            $computerDN = 'CN=Computer$,OU=Computers,DC=domain,DC=local'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $computerDN
            
            $result | Should Be $true
        }
        
        It "Should validate organizational unit DN format" {
            $ouDN = 'OU=Organizational Unit,DC=test,DC=local'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $ouDN
            
            $result | Should Be $true
        }
        
        It "Should validate domain component only DN" {
            $dcDN = 'DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $dcDN
            
            $result | Should Be $true
        }
        
        It "Should validate complex configuration container DN" {
            $configDN = 'CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $configDN
            
            $result | Should Be $true
        }
    }
    
    Context "Invalid DN Format Detection" {
        It "Should reject obviously invalid DN - InvalidDN" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'InvalidDN'
            $result | Should Be $false
        }
        
        It "Should reject obviously invalid DN - CN=User" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'CN=User'
            $result | Should Be $false
        }
        
        It "Should reject obviously invalid DN - OU=NoCommonName" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'OU=NoCommonName'
            $result | Should Be $false
        }
        
        It "Should reject obviously invalid DN - DC=onlydc" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'DC=onlydc'
            $result | Should Be $false
        }
        
        It "Should reject DNs with empty components" {
            $emptyComponentDNs = @(
                'CN=,OU=Users,DC=contoso,DC=com'
                'CN=User,OU=,DC=contoso,DC=com'
                'CN=User,DC=,DC=com'
            )
            
            foreach ($dn in $emptyComponentDNs) {
                $result = Test-ValidDistinguishedName -DistinguishedName $dn
                $result | Should Be $false
            }
        }
        
        It "Should reject DNs with invalid separators" {
            $invalidSeparatorDNs = @(
                'CN User OU=Users DC=contoso DC=com'
                'CN==User,OU=Users,DC=contoso,DC=com'
                'RDN=User,OU=Users,DC=contoso,DC=com'
            )
            
            foreach ($dn in $invalidSeparatorDNs) {
                $result = Test-ValidDistinguishedName -DistinguishedName $dn
                $result | Should Be $false
            }
        }
    }
    
    Context "Security Injection Prevention" {
        It "Should detect and reject PowerShell injection - Get-Process" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'CN=User$(Get-Process),OU=Users,DC=contoso,DC=com'
            $result | Should Be $false
        }
        
        It "Should detect and reject PowerShell injection - Invoke-Expression" {
            $result = Test-ValidDistinguishedName -DistinguishedName "CN=User`$(Invoke-Expression 'whoami'),OU=Users,DC=contoso,DC=com"
            $result | Should Be $false
        }
        
        It "Should detect and reject PowerShell injection - powershell.exe" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'CN=User&powershell.exe,OU=Users,DC=contoso,DC=com'
            $result | Should Be $false
        }
        
        It "Should detect and reject PowerShell injection - Out-File" {
            $result = Test-ValidDistinguishedName -DistinguishedName 'CN=User|Out-File malicious.txt,OU=Users,DC=contoso,DC=com'
            $result | Should Be $false
        }
        
        It "Should detect SQL injection patterns" {
            $sqlInjectionDN = 'CN=User;DROP TABLE Users;--,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $sqlInjectionDN
            
            $result | Should Be $false
        }
        
        It "Should detect path traversal attempts" {
            $pathTraversalDN = 'CN=../../../etc/passwd,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $pathTraversalDN
            
            $result | Should Be $false
        }
        
        It "Should detect script injection attempts" {
            $scriptInjectionDN = 'CN=User<script>alert("xss")</script>,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $scriptInjectionDN
            
            $result | Should Be $false
        }
        
        It "Should detect null byte injection" {
            $nullByteDN = 'CN=User%00,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $nullByteDN
            
            $result | Should Be $false
        }
        
        It "Should handle embedded null characters safely" {
            $nullCharDN = 'CN=User' + [char]0x00 + 'Hidden,OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $nullCharDN
            
            $result | Should Be $false
        }
    }
    
    Context "LDAP Compliance and RFC Standards" {
        It "Should handle Unicode characters properly" {
            $unicodeDN = 'CN=Üser Tëst,OU=Spëcial Ćhars,DC=tëst,DC=cöm'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $unicodeDN
            
            # Should be valid for Unicode characters
            $result | Should Be $true
        }
        
        It "Should handle escaped characters correctly" {
            $escapedDN = 'CN=User\, Name,OU=Users\=Test,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $escapedDN
            
            # Should be valid for properly escaped characters
            $result | Should Be $true
        }
        
        It "Should handle quoted values correctly" {
            $quotedDN = 'CN="User, With Comma",OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $quotedDN
            
            # Should be valid for quoted values
            $result | Should Be $true
        }
        
        It "Should be case insensitive for attribute names" {
            $mixedCaseDN = 'cn=user,ou=users,dc=CONTOSO,DC=COM'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $mixedCaseDN
            
            $result | Should Be $true
        }
        
        It "Should handle spaces around equals signs" {
            $spacedDN = 'CN = User Name , OU = Users , DC = contoso , DC = com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $spacedDN
            
            # Should normalize spaces correctly
            $result | Should Be $true
        }
        
        It "Should validate against maximum DN length limits" {
            # Create a very long but valid DN
            $longDN = 'CN=' + ('A' * 500) + ',OU=' + ('B' * 500) + ',DC=' + ('C' * 500) + ',DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $longDN
            
            # Should reject overly long DNs
            $result | Should Be $false
        }
    }
    
    Context "Batch Processing and Array Handling" {
        It "Should process multiple valid DNs correctly" {
            $validDNs = $script:testData.ValidDNs[0..4]
            
            $results = $validDNs | Test-ValidDistinguishedName
            
            @($results).Count | Should Be $validDNs.Count
            $results | Where-Object { $_ -eq $false } | Should BeNullOrEmpty
        }
        
        It "Should process mixed valid and invalid DNs" {
            $mixedDNs = @(
                $script:testData.ValidDNs[0]
                $script:testData.InvalidDNs[0]
                $script:testData.ValidDNs[1]
                $script:testData.InvalidDNs[1]
            )
            
            $results = $mixedDNs | Test-ValidDistinguishedName
            
            @($results).Count | Should Be 4
            $results[0] | Should Be $true   # Valid
            $results[1] | Should Be $false  # Invalid
            $results[2] | Should Be $true   # Valid
            $results[3] | Should Be $false  # Invalid
        }
        
        It "Should handle empty array input" {
            $results = @() | Test-ValidDistinguishedName
            
            $results | Should BeNullOrEmpty
        }
        
        It "Should handle large arrays efficiently" {
            # Create large array of valid DNs
            $largeDNArray = 1..100 | ForEach-Object {
                "CN=User$_,OU=Users,DC=contoso,DC=com"
            }
            
            $results = $largeDNArray | Test-ValidDistinguishedName
            
            @($results).Count | Should Be 100
            $results | Where-Object { $_ -eq $false } | Should BeNullOrEmpty
        }
    }
    
    Context "Enterprise Security Logging and Auditing" {
        It "Should log validation attempt with security context" {
            $testDN = 'CN=TestUser,OU=Users,DC=contoso,DC=com'
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            
            Test-ValidDistinguishedName -DistinguishedName $testDN -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -match 'Distinguished Name validation successful'
            }
        }
        
        It "Should log validation results for each DN" {
            $mixedDNs = @(
                $script:testData.ValidDNs[0]
                $script:testData.InvalidDNs[0]
                $script:testData.MaliciousDNs[0]
            )
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            
            $mixedDNs | Test-ValidDistinguishedName -CorrelationId $testCorrelationId
            
            Assert-MockCalled Write-StructuredLog -Times 3 -ParameterFilter {
                $Component -eq 'DNValidator'
            }
        }
        
        It "Should log security violations separately" {
            $maliciousDN = $script:testData.MaliciousDNs[0]
            
            Test-ValidDistinguishedName -DistinguishedName $maliciousDN
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -match 'Contains dangerous characters' -and
                $Level -eq 'Warning'
            }
        }
        
        It "Should include result summary in success logging" {
            $testDNs = $script:testData.ValidDNs[0..2]
            
            $testDNs | Test-ValidDistinguishedName
            
            Assert-MockCalled Write-StructuredLog -Times 3 -ParameterFilter {
                $Message -match 'Distinguished Name validation successful'
            }
        }
    }
    
    Context "Performance and Scalability" {
        It "Should process large batches efficiently" {
            $largeBatch = 1..100 | ForEach-Object {
                "CN=User$_,OU=Users,DC=test$($_ % 10),DC=com"
            }
            
            $executionTime = Measure-Command {
                $results = $largeBatch | Test-ValidDistinguishedName
            }
            
            # Should complete within reasonable time (5 seconds for 100 DNs)
            $executionTime.TotalSeconds | Should BeLessThan 5
        }
        
        It "Should provide structured logging for operations" {
            $largeBatch = 1..100 | ForEach-Object {
                "CN=User$_,OU=Users,DC=contoso,DC=com"
            }
            
            $largeBatch | Test-ValidDistinguishedName
            
            Assert-MockCalled Write-StructuredLog -Times 100 -ParameterFilter {
                $Message -match 'Distinguished Name validation successful'
            }
        }
        
        It "Should handle memory efficiently for large datasets" {
            # Test with very large dataset
            $veryLargeBatch = 1..500 | ForEach-Object {
                "CN=User$_,OU=Department$($_ % 20),DC=company$($_ % 5),DC=com"
            }
            
            $results = $veryLargeBatch | Test-ValidDistinguishedName
            
            @($results).Count | Should Be 500
            $results | Where-Object { $_ -eq $false } | Should BeNullOrEmpty  # All should be valid
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle null values in arrays gracefully" {
            $arrayWithNulls = @(
                'CN=ValidUser,OU=Users,DC=contoso,DC=com'
                $null
                'CN=AnotherValidUser,OU=Users,DC=contoso,DC=com'
            )
            
            $results = $arrayWithNulls | Test-ValidDistinguishedName
            
            @($results).Count | Should Be 3
            $results[0] | Should Be $true
            $results[1] | Should Be $false  # null should be invalid
            $results[2] | Should Be $true
        }
        
        It "Should handle whitespace-only strings" {
            $whitespaceStrings = @(
                '   '
                "`t"
                "`n"
                "`r`n"
            )
            
            foreach ($ws in $whitespaceStrings) {
                $result = Test-ValidDistinguishedName -DistinguishedName $ws
                $result | Should Be $false
            }
        }
        
        It "Should handle extremely long individual DN components" {
            $longComponentDN = 'CN=' + ('A' * 1000) + ',OU=Users,DC=contoso,DC=com'
            
            $result = Test-ValidDistinguishedName -DistinguishedName $longComponentDN
            
            # Should reject overly long components
            $result | Should Be $false
        }
        
        It "Should handle special characters that might break regex" {
            $specialCharDNs = @(
                'CN=User[],OU=Users,DC=contoso,DC=com'
                'CN=User(),OU=Users,DC=contoso,DC=com'
                'CN=User{},OU=Users,DC=contoso,DC=com'
                'CN=User^,OU=Users,DC=contoso,DC=com'
            )
            
            foreach ($dn in $specialCharDNs) {
                # Should not throw exceptions
                { $dn | Test-ValidDistinguishedName } | Should Not Throw
            }
        }
    }
    
    AfterEach {
        # Clean up test environment
        Remove-Variable -Name 'testData' -Scope Script -ErrorAction SilentlyContinue
        $env:PESTER_TESTING = $null
    }
}
