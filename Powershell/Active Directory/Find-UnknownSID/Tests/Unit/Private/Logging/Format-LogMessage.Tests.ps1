#Requires -Version 5.1

<#
.SYNOPSIS
    Pester 3.4 tests for Format-LogMessage function

.DESCRIPTION
    Tests the Format-LogMessage function for proper parameter handling,
    message formatting, output format variations, and enterprise compliance.

.NOTES
    Uses Pester 3.4 test framework with enterprise PowerShell standards
    Validates message formatting according to specified styles and requirements
#>

# Import testing framework and dependencies
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$script:TestHelperPath = Join-Path $script:ModuleRoot "Tests\TestHelpers\SecurityTestHelpers.ps1"

# Import test helpers if available
if (Test-Path $script:TestHelperPath) {
    . $script:TestHelperPath
}

# Import function under test
$script:FunctionPath = Join-Path $script:ModuleRoot "Private\Logging\Format-LogMessage.ps1"

if (Test-Path $script:FunctionPath) {
    . $script:FunctionPath
}

Describe "Format-LogMessage" {
    Context "Parameter Validation" {
        It "Should accept mandatory Message parameter" {
            { Format-LogMessage -Message "Test message" -Level "Information" } | Should Not Throw
        }

        It "Should reject null or empty Message" {
            { Format-LogMessage -Message "" -Level "Information" } | Should Throw
            { Format-LogMessage -Message $null -Level "Information" } | Should Throw
        }

        It "Should accept mandatory Level parameter" {
            { Format-LogMessage -Message "Test message" -Level "Information" } | Should Not Throw
        }

        It "Should accept all valid Level values" {
            $validLevels = @('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose', 'INFO')
            
            foreach ($level in $validLevels) {
                { Format-LogMessage -Message "Test message" -Level $level } | Should Not Throw
            }
        }

        It "Should reject invalid Level values" {
            { Format-LogMessage -Message "Test message" -Level "InvalidLevel" } | Should Throw
        }

        It "Should use default Component when not specified" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "PlainText"
            $result | Should Match "General"
        }

        It "Should accept valid Component parameter" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Component "TestComponent" -Format "PlainText"
            $result | Should Match "TestComponent"
        }

        It "Should auto-generate CorrelationId when not provided" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.CorrelationId | Should Match "^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$"
        }

        It "Should accept valid CorrelationId parameter" {
            $testCorrelationId = "test-correlation-123"
            $result = Format-LogMessage -Message "Test message" -Level "Information" -CorrelationId $testCorrelationId -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.CorrelationId | Should Be $testCorrelationId
        }

        It "Should use default JSON format when not specified" {
            $result = Format-LogMessage -Message "Test message" -Level "Information"
            { $result | ConvertFrom-Json } | Should Not Throw
        }

        It "Should accept all valid Format values" {
            $validFormats = @('JSON', 'PlainText', 'CSV', 'XML')
            
            foreach ($format in $validFormats) {
                { Format-LogMessage -Message "Test message" -Level "Information" -Format $format } | Should Not Throw
            }
        }

        It "Should reject invalid Format values" {
            { Format-LogMessage -Message "Test message" -Level "Information" -Format "InvalidFormat" } | Should Throw
        }

        It "Should accept empty AdditionalData hashtable" {
            $emptyData = @{}
            { Format-LogMessage -Message "Test message" -Level "Information" -AdditionalData $emptyData } | Should Not Throw
        }

        It "Should accept AdditionalData with content" {
            $testData = @{ TestKey = "TestValue"; Number = 42 }
            { Format-LogMessage -Message "Test message" -Level "Information" -AdditionalData $testData } | Should Not Throw
        }
    }

    Context "Level Normalization" {
        It "Should normalize INFO to Information" {
            $result = Format-LogMessage -Message "Test message" -Level "INFO" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Level | Should Be "Information"
        }

        It "Should preserve other valid levels unchanged" {
            $levels = @('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')
            
            foreach ($level in $levels) {
                $result = Format-LogMessage -Message "Test message" -Level $level -Format "JSON"
                $data = $result | ConvertFrom-Json
                $data.Level | Should Be $level
            }
        }
    }

    Context "JSON Format Output" {
        It "Should produce valid JSON" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            { $result | ConvertFrom-Json } | Should Not Throw
        }

        It "Should include all required fields in JSON" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            
            ($data.PSObject.Properties | Where-Object { $_.Name -eq "Timestamp" }) | Should Not BeNullOrEmpty
            ($data.PSObject.Properties | Where-Object { $_.Name -eq "Level" }) | Should Not BeNullOrEmpty
            ($data.PSObject.Properties | Where-Object { $_.Name -eq "Component" }) | Should Not BeNullOrEmpty
            ($data.PSObject.Properties | Where-Object { $_.Name -eq "CorrelationId" }) | Should Not BeNullOrEmpty
            ($data.PSObject.Properties | Where-Object { $_.Name -eq "Message" }) | Should Not BeNullOrEmpty
        }

        It "Should format timestamp correctly in JSON" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Timestamp | Should Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$"
        }

        It "Should include AdditionalData fields in JSON" {
            $testData = @{ TestKey = "TestValue"; Number = 42; Boolean = $true }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON" -AdditionalData $testData
            $data = $result | ConvertFrom-Json
            
            $data.TestKey | Should Be "TestValue"
            $data.Number | Should Be 42
            $data.Boolean | Should Be $true
        }

        It "Should produce compressed JSON without whitespace" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            $result | Should Not Match "\n"
            $result | Should Not Match "\r"
            $result | Should Not Match "  " # Multiple spaces
        }

        It "Should handle complex nested data in JSON" {
            $complexData = @{
                Nested = @{ Inner = "Value"; Deeper = @{ Level3 = 123 } }
                Array = @(1, 2, 3)
                String = "Test"
            }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON" -AdditionalData $complexData
            $data = $result | ConvertFrom-Json
            
            $data.Nested.Inner | Should Be "Value"
            $data.Nested.Deeper.Level3 | Should Be 123
            $data.Array.Count | Should Be 3
        }
    }

    Context "PlainText Format Output" {
        It "Should produce properly formatted plain text" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "PlainText"
            $result | Should Match "^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}\] \[Information\] \[General\] \[[a-fA-F0-9-]+\] Test message$"
        }

        It "Should include custom component in plain text" {
            $result = Format-LogMessage -Message "Test message" -Level "Warning" -Component "TestComponent" -Format "PlainText"
            $result | Should Match "\[TestComponent\]"
        }

        It "Should include custom correlation ID in plain text" {
            $testCorrelationId = "test-123"
            $result = Format-LogMessage -Message "Test message" -Level "Error" -CorrelationId $testCorrelationId -Format "PlainText"
            $result | Should Match "\[test-123\]"
        }

        It "Should handle special characters in message for plain text" {
            $specialMessage = "Message with [brackets] and (parentheses)"
            $result = Format-LogMessage -Message $specialMessage -Level "Information" -Format "PlainText"
            $escapedMessage = [regex]::Escape($specialMessage)
            $result | Should Match $escapedMessage
        }

        It "Should ignore AdditionalData in plain text format" {
            $testData = @{ TestKey = "TestValue" }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "PlainText" -AdditionalData $testData
            $result | Should Not Match "TestKey"
            $result | Should Not Match "TestValue"
        }
    }

    Context "CSV Format Output" {
        It "Should produce properly formatted CSV" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "CSV"
            $result | Should Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2},Information,General,[a-fA-F0-9-]+,`"Test message`"$"
        }

        It "Should include custom component in CSV" {
            $result = Format-LogMessage -Message "Test message" -Level "Warning" -Component "TestComponent" -Format "CSV"
            $result | Should Match ",TestComponent,"
        }

        It "Should include custom correlation ID in CSV" {
            $testCorrelationId = "test-123"
            $result = Format-LogMessage -Message "Test message" -Level "Error" -CorrelationId $testCorrelationId -Format "CSV"
            $result | Should Match ",test-123,"
        }

        It "Should properly quote message with commas in CSV" {
            $messageWithCommas = "Message with, commas, here"
            $result = Format-LogMessage -Message $messageWithCommas -Level "Information" -Format "CSV"
            $result | Should Match "`"Message with, commas, here`""
        }

        It "Should handle double quotes in message for CSV" {
            $messageWithQuotes = "Message with `"quotes`" here"
            $result = Format-LogMessage -Message $messageWithQuotes -Level "Information" -Format "CSV"
            $result | Should Match "`"Message with `"quotes`" here`""
        }

        It "Should ignore AdditionalData in CSV format" {
            $testData = @{ TestKey = "TestValue" }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "CSV" -AdditionalData $testData
            $result | Should Not Match "TestKey"
            $result | Should Not Match "TestValue"
        }
    }

    Context "XML Format Output" {
        It "Should produce valid XML" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "XML"
            { [xml]$result } | Should Not Throw
        }

        It "Should include all required fields in XML" {
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "XML"
            $xml = [xml]$result
            
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "Timestamp" } | Should Not BeNullOrEmpty
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "Level" } | Should Not BeNullOrEmpty
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "Component" } | Should Not BeNullOrEmpty
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "CorrelationId" } | Should Not BeNullOrEmpty
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "Message" } | Should Not BeNullOrEmpty
        }

        It "Should include AdditionalData fields in XML" {
            $testData = @{ TestKey = "TestValue"; Number = 42 }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "XML" -AdditionalData $testData
            $xml = [xml]$result
            
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "TestKey" } | Should Not BeNullOrEmpty
            $xml.Objects.Object.Property | Where-Object { $_.Name -eq "Number" } | Should Not BeNullOrEmpty
        }

        It "Should handle special XML characters properly" {
            $messageWithXmlChars = "Message with <tags> & entities"
            $result = Format-LogMessage -Message $messageWithXmlChars -Level "Information" -Format "XML"
            { [xml]$result } | Should Not Throw
        }
    }

    Context "Special Characters and Encoding" {
        It "Should handle Unicode characters in message" {
            $unicodeMessage = "Test message with üñíçødé characters ñ€"
            $result = Format-LogMessage -Message $unicodeMessage -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Message | Should Be $unicodeMessage
        }

        It "Should handle newlines and tabs in message" {
            $multilineMessage = "Line 1`nLine 2`tTabbed"
            $result = Format-LogMessage -Message $multilineMessage -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Message | Should Be $multilineMessage
        }

        It "Should handle PowerShell special characters in message" {
            $specialMessage = "Test `$variable with `"quotes`" and 'apostrophes'"
            $result = Format-LogMessage -Message $specialMessage -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Message | Should Be $specialMessage
        }

        It "Should handle very long messages" {
            $longMessage = "A" * 10000
            $result = Format-LogMessage -Message $longMessage -Level "Information" -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Message.Length | Should Be 10000
        }

        It "Should handle special characters in component name" {
            $specialComponent = "Component-With_Special.Characters@123"
            $result = Format-LogMessage -Message "Test" -Level "Information" -Component $specialComponent -Format "JSON"
            $data = $result | ConvertFrom-Json
            $data.Component | Should Be $specialComponent
        }

        It "Should handle special characters in AdditionalData values" {
            $specialData = @{
                "Key With Spaces" = "Value with üñíçødé"
                "Number" = 42.5
                "Special" = "`$null and `"quotes`""
            }
            $result = Format-LogMessage -Message "Test" -Level "Information" -Format "JSON" -AdditionalData $specialData
            $data = $result | ConvertFrom-Json
            
            $data."Key With Spaces" | Should Be "Value with üñíçødé"
            $data.Number | Should Be 42.5
            $data.Special | Should Be "`$null and `"quotes`""
        }
    }

    Context "Timestamp Handling" {
        It "Should generate consistent timestamp format" {
            $result1 = Format-LogMessage -Message "Test message 1" -Level "Information" -Format "JSON"
            $result2 = Format-LogMessage -Message "Test message 2" -Level "Information" -Format "JSON"
            
            $data1 = $result1 | ConvertFrom-Json
            $data2 = $result2 | ConvertFrom-Json
            
            $data1.Timestamp | Should Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$"
            $data2.Timestamp | Should Match "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$"
        }

        It "Should generate timestamps close in time for rapid calls" {
            $before = Get-Date
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON"
            $after = Get-Date
            
            $data = $result | ConvertFrom-Json
            $timestamp = [DateTime]::Parse($data.Timestamp)
            
            $timestamp | Should BeGreaterThan $before.AddSeconds(-1)
            $timestamp | Should BeLessThan $after.AddSeconds(1)
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle null AdditionalData gracefully" {
            { Format-LogMessage -Message "Test message" -Level "Information" -AdditionalData $null } | Should Not Throw
        }

        It "Should handle empty string in AdditionalData values" {
            $testData = @{ EmptyString = ""; ValidValue = "test" }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON" -AdditionalData $testData
            $data = $result | ConvertFrom-Json
            
            $data.EmptyString | Should Be ""
            $data.ValidValue | Should Be "test"
        }

        It "Should handle very large AdditionalData hashtables" {
            $largeData = @{}
            for ($i = 1; $i -le 100; $i++) {
                $largeData["Key$i"] = "Value$i"
            }
            
            $result = Format-LogMessage -Message "Large data test" -Level "Information" -Format "JSON" -AdditionalData $largeData
            $data = $result | ConvertFrom-Json
            
            $data.Key1 | Should Be "Value1"
            $data.Key100 | Should Be "Value100"
        }

        It "Should handle duplicate keys in AdditionalData gracefully" {
            $testData = @{ Timestamp = "CustomTimestamp"; Level = "CustomLevel" }
            $result = Format-LogMessage -Message "Test message" -Level "Information" -Format "JSON" -AdditionalData $testData
            $data = $result | ConvertFrom-Json
            
            # AdditionalData should override the default values
            $data.Timestamp | Should Be "CustomTimestamp"
            $data.Level | Should Be "CustomLevel"
        }

        It "Should handle invalid format parameter validation" {
            # The ValidateSet attribute should prevent invalid formats from being passed
            { Format-LogMessage -Message "Test message" -Level "Information" -Format "InvalidFormat" } | Should Throw
        }
    }

    Context "Performance and Memory" {
        It "Should complete formatting within reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Format-LogMessage -Message "Performance test" -Level "Information"
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 50
        }

        It "Should handle multiple concurrent calls efficiently" {
            $jobs = @()
            for ($i = 1; $i -le 10; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($ModuleRoot, $i)
                    . "$ModuleRoot\Private\Logging\Format-LogMessage.ps1"
                    Format-LogMessage -Message "Concurrent test $i" -Level "Information" -Format "JSON"
                } -ArgumentList $script:ModuleRoot, $i
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results.Count | Should Be 10
            foreach ($result in $results) {
                { $result | ConvertFrom-Json } | Should Not Throw
            }
        }

        It "Should not leak memory with large data sets" {
            $beforeMemory = [System.GC]::GetTotalMemory($false)
            
            for ($i = 1; $i -le 100; $i++) {
                $testData = @{
                    Iteration = $i
                    Data = "x" * 1000
                    Timestamp = Get-Date
                }
                $result = Format-LogMessage -Message "Memory test $i" -Level "Information" -AdditionalData $testData
            }
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $afterMemory = [System.GC]::GetTotalMemory($false)
            $memoryIncrease = $afterMemory - $beforeMemory
            
            # Memory increase should be reasonable (less than 5MB for this test)
            $memoryIncrease | Should BeLessThan 5242880
        }
    }

    Context "Enterprise Integration" {
        It "Should support audit trail formatting" {
            $auditData = @{
                UserId = "testuser@domain.com"
                Action = "PermissionModification"
                Resource = "\\server\share\folder"
                Success = $true
            }
            $result = Format-LogMessage -Message "Audit event" -Level "Information" -Component "AuditTrail" -Format "JSON" -AdditionalData $auditData
            $data = $result | ConvertFrom-Json
            
            $data.Component | Should Be "AuditTrail"
            $data.UserId | Should Be "testuser@domain.com"
            $data.Action | Should Be "PermissionModification"
        }

        It "Should support compliance log formatting" {
            $complianceData = @{
                Regulation = "SOX"
                ControlId = "IT-GC-01"
                ComplianceStatus = "Pass"
                Evidence = "Log file verification completed"
            }
            $result = Format-LogMessage -Message "Compliance check" -Level "Information" -Component "Compliance" -Format "JSON" -AdditionalData $complianceData
            $data = $result | ConvertFrom-Json
            
            $data.Regulation | Should Be "SOX"
            $data.ControlId | Should Be "IT-GC-01"
            $data.ComplianceStatus | Should Be "Pass"
        }

        It "Should support security event formatting" {
            $securityData = @{
                SecurityPrincipal = "DOMAIN\ServiceAccount"
                AuthenticationMethod = "Kerberos"
                SourceIP = "192.168.1.100"
                ThreatLevel = "Low"
            }
            $result = Format-LogMessage -Message "Security event" -Level "Warning" -Component "Security" -Format "JSON" -AdditionalData $securityData
            $data = $result | ConvertFrom-Json
            
            $data.SecurityPrincipal | Should Be "DOMAIN\ServiceAccount"
            $data.AuthenticationMethod | Should Be "Kerberos"
            $data.ThreatLevel | Should Be "Low"
        }
    }
}
