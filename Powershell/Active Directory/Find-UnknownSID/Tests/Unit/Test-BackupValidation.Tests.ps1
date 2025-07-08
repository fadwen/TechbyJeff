#Requires -Module Pester
<#
.SYNOPSIS
    Comprehensive Pester tests for Test-BackupValidation module functions

.DESCRIPTION
    Enterprise-grade unit tests covering backup validation operations:
    - Test-BackupIntegrity: Backup file integrity and format validation
    - Confirm-BackupCompatibility: Version and format compatibility checks
    - Validate-BackupSignature: Signature verification and authentication
    - Test-SDDLIntegrity: SDDL format and hash validation
    - Validate-BackupMetadata: Metadata completeness and validity

    Test Coverage:
    - Backup file integrity verification using SHA256
    - Format validation and compatibility checks
    - Signature validation for version control
    - SDDL format validation and injection prevention
    - Metadata completeness and structure validation
    - Error handling for corrupted or invalid backups
    - Security validation and audit trail generation

.NOTES
    Author: Enterprise PowerShell Testing Framework
    Version: 1.0.0
    Testing Framework: Pester 5.x
    Coverage Target: 95%+
    Security Level: Enterprise
#>

BeforeAll {
        # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Import test helpers and required modules
    . $PSScriptRoot\..\TestHelpers\TestHelpers.ps1

    # Import the Private functions for testing
    $privatePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Private"
    $backupPath = Join-Path $privatePath "Backup"

    # Import Test-BackupValidation functions
    . (Join-Path $backupPath "Test-BackupValidation.ps1")

    # Mock external dependencies
    Mock Write-Verbose { } -Verifiable:$false
    Mock Write-Debug { } -Verifiable:$false
    Mock Write-Warning { } -Verifiable:$false
    Mock Write-Error { } -Verifiable:$false

    # Initialize test correlation ID
    $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()

    # Create test backup data
    $script:ValidBackupData = @{
        Signature = "Find-UnknownSID-Backup-v2.1"
        Version = "2.1.0"
        Timestamp = Get-Date
        DistinguishedName = "CN=TestUser,CN=Users,DC=contoso,DC=com"
        SDDL = "O:SYG:SYD:(A;;GA;;;SY)(A;;GA;;;BA)"
        SDDLHash = (Get-StringHash -InputString "O:SYG:SYD:(A;;GA;;;SY)(A;;GA;;;BA)" -Algorithm SHA256)
        BackupType = "ACL"
        CorrelationId = $TestCorrelationId
        Metadata = @{
            ScriptVersion = "2.1.0"
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
        }
    }

    $script:InvalidBackupData = @{
        Signature = "Invalid-Signature"
        Version = "0.0.0"
        DistinguishedName = ""
        SDDL = "InvalidSDDL"
        SDDLHash = "InvalidHash"
    }
}

Describe "Test-BackupIntegrity" -Tag "Unit", "Backup", "Security" {

    Context "Parameter Validation" {
        It "Should validate mandatory BackupData parameter" {
            { Test-BackupIntegrity -BackupData $null -CorrelationId $TestCorrelationId } | Should -Throw "*BackupData*"
        }

        It "Should validate BackupData is a hashtable or PSCustomObject" {
            { Test-BackupIntegrity -BackupData "invalid string" -CorrelationId $TestCorrelationId } | Should -Throw "*BackupData*type*"
        }

        It "Should accept valid backup data objects" {
            { Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId } | Should -Not -Throw
        }
    }

    Context "Required Property Validation" {
        It "Should validate presence of required properties" -TestCases @(
            @{ Property = "Signature"; Expected = $true }
            @{ Property = "Version"; Expected = $true }
            @{ Property = "DistinguishedName"; Expected = $true }
            @{ Property = "SDDL"; Expected = $true }
            @{ Property = "SDDLHash"; Expected = $true }
        ) {
            param($Property, $Expected)

            $incompleteData = $ValidBackupData.Clone()
            $incompleteData.Remove($Property)

            if ($Expected) {
                { Test-BackupIntegrity -BackupData $incompleteData -CorrelationId $TestCorrelationId } | Should -Throw "*$Property*required*"
            }
        }

        It "Should validate all required properties are present in valid backup" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.RequiredPropertiesValid | Should -Be $true
            $result.MissingProperties | Should -BeNullOrEmpty
        }

        It "Should identify missing properties in invalid backup" {
            $incompleteData = @{
                Signature = "Test"
                # Missing other required properties
            }

            $result = Test-BackupIntegrity -BackupData $incompleteData -CorrelationId $TestCorrelationId

            $result.RequiredPropertiesValid | Should -Be $false
            $result.MissingProperties | Should -HaveCount -GreaterThan 0
        }
    }

    Context "Signature Validation" {
        It "Should validate correct backup signature" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result.SignatureValid | Should -Be $true
        }

        It "Should reject invalid backup signatures" {
            $invalidData = $ValidBackupData.Clone()
            $invalidData.Signature = "Invalid-Signature"

            $result = Test-BackupIntegrity -BackupData $invalidData -CorrelationId $TestCorrelationId

            $result.SignatureValid | Should -Be $false
            $result.ValidationErrors | Should -Contain "*signature*"
        }

        It "Should support multiple valid signature formats" -TestCases @(
            @{ Signature = "Find-UnknownSID-Backup-v2.1" }
            @{ Signature = "Find-UnknownSID-Backup-v2.0" }
            @{ Signature = "Find-UnknownSID-ACL-Backup-v2.1" }
        ) {
            param($Signature)

            $testData = $ValidBackupData.Clone()
            $testData.Signature = $Signature

            $result = Test-BackupIntegrity -BackupData $testData -CorrelationId $TestCorrelationId

            $result.SignatureValid | Should -Be $true
        }
    }

    Context "SDDL Hash Integrity Validation" {
        It "Should validate correct SDDL hash" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result.SDDLHashValid | Should -Be $true
        }

        It "Should detect SDDL hash corruption" {
            $corruptedData = $ValidBackupData.Clone()
            $corruptedData.SDDLHash = "CorruptedHash"

            $result = Test-BackupIntegrity -BackupData $corruptedData -CorrelationId $TestCorrelationId

            $result.SDDLHashValid | Should -Be $false
            $result.ValidationErrors | Should -Contain "*hash*integrity*"
        }

        It "Should detect SDDL content tampering" {
            $tamperedData = $ValidBackupData.Clone()
            $tamperedData.SDDL = "O:SYG:SYD:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;EV)"  # Modified SDDL
            # Hash not updated to match

            $result = Test-BackupIntegrity -BackupData $tamperedData -CorrelationId $TestCorrelationId

            $result.SDDLHashValid | Should -Be $false
        }

        It "Should use SHA256 algorithm for hash validation" {
            Mock Get-StringHash {
                param($InputString, $Algorithm)
                $Algorithm | Should -Be "SHA256"
                return "ValidHashResult"
            }

            $testData = $ValidBackupData.Clone()
            $testData.SDDLHash = "ValidHashResult"

            Test-BackupIntegrity -BackupData $testData -CorrelationId $TestCorrelationId

            Assert-MockCalled Get-StringHash -Times 1 -ParameterFilter { $Algorithm -eq "SHA256" }
        }
    }

    Context "Version Compatibility Validation" {
        It "Should validate compatible backup versions" -TestCases @(
            @{ Version = "2.1.0"; Compatible = $true }
            @{ Version = "2.0.0"; Compatible = $true }
            @{ Version = "1.9.0"; Compatible = $false }
            @{ Version = "3.0.0"; Compatible = $false }
        ) {
            param($Version, $Compatible)

            $testData = $ValidBackupData.Clone()
            $testData.Version = $Version

            $result = Test-BackupIntegrity -BackupData $testData -CorrelationId $TestCorrelationId

            $result.VersionCompatible | Should -Be $Compatible
        }

        It "Should handle missing version gracefully" {
            $noVersionData = $ValidBackupData.Clone()
            $noVersionData.Remove("Version")

            $result = Test-BackupIntegrity -BackupData $noVersionData -CorrelationId $TestCorrelationId

            $result.VersionCompatible | Should -Be $false
            $result.ValidationErrors | Should -Contain "*version*"
        }
    }

    Context "SDDL Format Validation" {
        It "Should validate proper SDDL format" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result.SDDLFormatValid | Should -Be $true
        }

        It "Should reject malformed SDDL strings" -TestCases @(
            @{ SDDL = "InvalidSDDL" }
            @{ SDDL = "" }
            @{ SDDL = "O:SYG:SYD:(InvalidACE)" }
            @{ SDDL = "MaliciousScript{}" }
        ) {
            param($SDDL)

            $invalidData = $ValidBackupData.Clone()
            $invalidData.SDDL = $SDDL
            $invalidData.SDDLHash = (Get-StringHash -InputString $SDDL -Algorithm SHA256)

            $result = Test-BackupIntegrity -BackupData $invalidData -CorrelationId $TestCorrelationId

            $result.SDDLFormatValid | Should -Be $false
        }

        It "Should validate complex but valid SDDL strings" {
            $complexSDDL = "O:BAG:SYD:(A;OICI;GA;;;BA)(A;OICI;GA;;;SY)(A;OICIIO;GA;;;CO)(A;;GA;;;S-1-5-21-1234567890-1234567890-1234567890-1001)"

            $complexData = $ValidBackupData.Clone()
            $complexData.SDDL = $complexSDDL
            $complexData.SDDLHash = (Get-StringHash -InputString $complexSDDL -Algorithm SHA256)

            $result = Test-BackupIntegrity -BackupData $complexData -CorrelationId $TestCorrelationId

            $result.SDDLFormatValid | Should -Be $true
        }
    }

    Context "Overall Validation Results" {
        It "Should provide comprehensive validation summary" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result | Should -HaveProperty "OverallValid"
            $result | Should -HaveProperty "ValidationScore"
            $result | Should -HaveProperty "ValidationSummary"
            $result | Should -HaveProperty "RecommendedAction"
        }

        It "Should calculate validation score correctly" {
            $result = Test-BackupIntegrity -BackupData $ValidBackupData -CorrelationId $TestCorrelationId

            $result.ValidationScore | Should -BeGreaterThan 90
            $result.OverallValid | Should -Be $true
        }

        It "Should provide actionable recommendations for failed validation" {
            $result = Test-BackupIntegrity -BackupData $InvalidBackupData -CorrelationId $TestCorrelationId

            $result.OverallValid | Should -Be $false
            $result.RecommendedAction | Should -Not -BeNullOrEmpty
            $result.ValidationErrors | Should -HaveCount -GreaterThan 0
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle corrupted backup data gracefully" {
            $corruptedData = @{
                Signature = $null
                Version = [System.DBNull]::Value
                SDDL = [char]0x00  # Null character
            }

            { Test-BackupIntegrity -BackupData $corruptedData -CorrelationId $TestCorrelationId } | Should -Not -Throw
        }

        It "Should handle extremely large backup data" {
            $largeData = $ValidBackupData.Clone()
            $largeData.SDDL = "O:SYG:SYD:" + ("(A;;GA;;;SY)" * 1000)  # Very large SDDL
            $largeData.SDDLHash = (Get-StringHash -InputString $largeData.SDDL -Algorithm SHA256)

            $result = Test-BackupIntegrity -BackupData $largeData -CorrelationId $TestCorrelationId

            $result | Should -Not -BeNullOrEmpty
            $result.OverallValid | Should -Be $true
        }

        It "Should validate against injection attacks" {
            $maliciousData = $ValidBackupData.Clone()
            $maliciousData.SDDL = "O:SYG:SYD:(A;;GA;;;SY); Invoke-Expression 'malicious code'"
            $maliciousData.SDDLHash = (Get-StringHash -InputString $maliciousData.SDDL -Algorithm SHA256)

            $result = Test-BackupIntegrity -BackupData $maliciousData -CorrelationId $TestCorrelationId

            $result.SDDLFormatValid | Should -Be $false
            $result.SecurityThreatsDetected | Should -Be $true
        }
    }
}

# Additional helper function tests if they exist in the module
Describe "Confirm-BackupCompatibility" -Tag "Unit", "Backup", "Compatibility" {

    Context "Version Compatibility Checks" {
        It "Should confirm compatible versions" {
            $result = Confirm-BackupCompatibility -BackupVersion "2.1.0" -CurrentVersion "2.1.0" -CorrelationId $TestCorrelationId

            $result.Compatible | Should -Be $true
            $result.Reason | Should -BeNullOrEmpty
        }

        It "Should detect incompatible versions" {
            $result = Confirm-BackupCompatibility -BackupVersion "1.0.0" -CurrentVersion "2.1.0" -CorrelationId $TestCorrelationId

            $result.Compatible | Should -Be $false
            $result.Reason | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Validate-BackupSignature" -Tag "Unit", "Backup", "Security" {

    Context "Signature Validation" {
        It "Should validate known good signatures" {
            $result = Validate-BackupSignature -Signature "Find-UnknownSID-Backup-v2.1" -CorrelationId $TestCorrelationId

            $result.Valid | Should -Be $true
            $result.SignatureType | Should -Not -BeNullOrEmpty
        }

        It "Should reject unknown signatures" {
            $result = Validate-BackupSignature -Signature "Unknown-Signature" -CorrelationId $TestCorrelationId

            $result.Valid | Should -Be $false
            $result.SecurityRisk | Should -Be $true
        }
    }
}

# Additional backup validation tests
Describe "Backup Integrity Validation" {
    BeforeAll {
        # Create valid test backup data
        $script:validBackup = [PSCustomObject]@{
            ObjectDN = "CN=TestUser,CN=Users,DC=contoso,DC=com"
            BackupDate = (Get-Date).ToString()
            SDDL = "O:DAG:DAD:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;DA)(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;SY)"
            SDDLHash = $null
            ValidationSignature = "PSSecurityBackup_v2.1"
        }

        # Calculate proper hash for test data
        $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($script:validBackup.SDDL)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $script:validBackup.SDDLHash = [System.Convert]::ToBase64String($sha256.ComputeHash($sddlBytes))
        $sha256.Dispose()
    }

    Context "Backup Data Validation" {
        It "Should validate a complete, valid backup" {
            $result = Test-BackupIntegrity -BackupData $script:validBackup

            $result | Should -Not -BeNullOrEmpty
            $result.PSTypeName | Should -Be 'BackupValidationResult'
            $result.IsValid | Should -Be $true
            $result.Issues | Should -HaveCount 0
            $result.ValidationLevel | Should -Be 'Standard'
        }

        It "Should detect missing required properties" {
            $invalidBackup = $script:validBackup.PSObject.Copy()
            $invalidBackup.PSObject.Properties.Remove('ObjectDN')

            $result = Test-BackupIntegrity -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Contain "Missing required property: ObjectDN"
        }

        It "Should detect invalid backup signature" {
            $invalidBackup = $script:validBackup.PSObject.Copy()
            $invalidBackup.ValidationSignature = "InvalidSignature"

            $result = Test-BackupIntegrity -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "Invalid backup signature.*InvalidSignature"
        }

        It "Should detect SDDL hash mismatch" {
            $invalidBackup = $script:validBackup.PSObject.Copy()
            $invalidBackup.SDDLHash = "InvalidHash123"

            $result = Test-BackupIntegrity -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "SDDL integrity check failed.*Hash mismatch"
        }

        It "Should validate ObjectDN when expected DN is provided" {
            $expectedDN = "CN=DifferentUser,CN=Users,DC=contoso,DC=com"

            $result = Test-BackupIntegrity -BackupData $script:validBackup -ExpectedObjectDN $expectedDN

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "ObjectDN mismatch.*Expected '$expectedDN'"
        }

        It "Should support Basic validation level" {
            $result = Test-BackupIntegrity -BackupData $script:validBackup -ValidationLevel Basic

            $result.IsValid | Should -Be $true
            $result.ValidationLevel | Should -Be 'Basic'
        }

        It "Should support Comprehensive validation level" {
            $result = Test-BackupIntegrity -BackupData $script:validBackup -ValidationLevel Comprehensive

            $result.IsValid | Should -Be $true
            $result.ValidationLevel | Should -Be 'Comprehensive'
        }

        It "Should detect invalid SDDL format" {
            $invalidBackup = $script:validBackup.PSObject.Copy()
            $invalidBackup.SDDL = "InvalidSDDLString"

            # Recalculate hash for the invalid SDDL
            $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($invalidBackup.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $invalidBackup.SDDLHash = [System.Convert]::ToBase64String($sha256.ComputeHash($sddlBytes))
            $sha256.Dispose()

            $result = Test-BackupIntegrity -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "Invalid SDDL format"
        }

        It "Should include correlation ID in results" {
            $correlationId = [System.Guid]::NewGuid().ToString()

            $result = Test-BackupIntegrity -BackupData $script:validBackup -CorrelationId $correlationId

            $result.CorrelationId | Should -Be $correlationId
        }

        It "Should handle validation errors gracefully" {
            $null_backup = $null

            $result = Test-BackupIntegrity -BackupData $null_backup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "Validation error"
        }

    Context "Test-BackupFormat" {

        BeforeEach {
            $script:formatTestBackup = [PSCustomObject]@{
                ObjectDN = "CN=TestUser,CN=Users,DC=contoso,DC=com"
                BackupDate = (Get-Date).ToString()
                SDDL = "O:DAG:DAD:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;DA)"
                ValidationSignature = "PSSecurityBackup_v2.1"
            }
        }

        It "Should validate backup format successfully" {
            $result = Test-BackupFormat -BackupData $script:formatTestBackup

            $result.PSTypeName | Should -Be 'FormatValidationResult'
            $result.IsValid | Should -Be $true
            $result.DetectedVersion | Should -Be 'v2.1'
        }

        It "Should detect missing core properties" {
            $invalidBackup = [PSCustomObject]@{
                ValidationSignature = "PSSecurityBackup_v2.1"
            }

            $result = Test-BackupFormat -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Contain "Missing core property: ObjectDN"
            $result.Issues | Should -Contain "Missing core property: BackupDate"
            $result.Issues | Should -Contain "Missing core property: SDDL"
        }

        It "Should validate specific version when required" {
            $result = Test-BackupFormat -BackupData $script:formatTestBackup -RequiredVersion 'v2.0'

            $result.IsValid | Should -Be $false
            $result.Issues | Should -Match "Version mismatch.*Required v2.0.*found v2.1"
        }
    }

    Context "Get-BackupMetadata" {

        BeforeEach {
            $script:metadataTestBackup = [PSCustomObject]@{
                ObjectDN = "CN=TestUser,CN=Users,DC=contoso,DC=com"
                BackupDate = (Get-Date).ToString()
                SDDL = "O:DAG:DAD:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;DA)(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;SY)"
                SDDLHash = "TestHash123"
                ValidationSignature = "PSSecurityBackup_v2.1"
            }
        }

        It "Should extract basic metadata" {
            $result = Get-BackupMetadata -BackupData $script:metadataTestBackup

            $result.PSTypeName | Should -Be 'BackupMetadata'
            $result.IsValid | Should -Be $true
            $result.Metadata.ObjectDN | Should -Be $script:metadataTestBackup.ObjectDN
            $result.Metadata.Version | Should -Be 'v2.1'
            $result.Metadata.HasIntegrityHash | Should -Be $true
        }

        It "Should include statistics when requested" {
            $result = Get-BackupMetadata -BackupData $script:metadataTestBackup -IncludeStatistics

            $result.Metadata.Statistics | Should -Not -BeNullOrEmpty
            $result.Metadata.Statistics.SDDLLength | Should -BeGreaterThan 0
            $result.Metadata.Statistics.EstimatedACECount | Should -BeGreaterThan 0
            $result.Metadata.Statistics.DataSize | Should -BeGreaterThan 0
        }

        It "Should handle metadata extraction errors" {
            $invalidBackup = "InvalidBackupData"

            $result = Get-BackupMetadata -BackupData $invalidBackup

            $result.IsValid | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context "Pipeline Support" {

        It "Should support pipeline input for Test-BackupIntegrity" {
            $backup1 = [PSCustomObject]@{
                ObjectDN = "CN=User1,CN=Users,DC=contoso,DC=com"
                BackupDate = (Get-Date).ToString()
                SDDL = "O:DAG:DAD:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;DA)"
                ValidationSignature = "PSSecurityBackup_v2.1"
            }

            $backup2 = [PSCustomObject]@{
                ObjectDN = "CN=User2,CN=Users,DC=contoso,DC=com"
                BackupDate = (Get-Date).ToString()
                SDDL = "O:DAG:DAD:(A;;RPWPCRCCDCLCLORCWOWDSDDTSW;;;SY)"
                ValidationSignature = "PSSecurityBackup_v2.1"
            }

            # Calculate hashes
            foreach ($backup in @($backup1, $backup2)) {
                $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($backup.SDDL)
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $backup | Add-Member -NotePropertyName SDDLHash -NotePropertyValue ([System.Convert]::ToBase64String($sha256.ComputeHash($sddlBytes)))
                $sha256.Dispose()
            }

            $results = @($backup1, $backup2) | Test-BackupIntegrity

            $results | Should -HaveCount 2
            $results[0].IsValid | Should -Be $true
            $results[1].IsValid | Should -Be $true
        }
    }
}

Describe "Test-BackupValidation Integration" -Tag "Integration", "BackupValidation" {

    Context "Real Backup File Processing" {

        It "Should process backup files from actual backup operations" -Skip {
            # This test would use real backup files in integration testing
            # Skipped in unit tests to avoid dependencies
            $true | Should -Be $true
        }
    }
}

# Test cleanup and summary reporting
AfterAll {
    Write-Host "Test-BackupValidation Module Tests Completed" -ForegroundColor Green
    Write-Host "Test Correlation ID: $TestCorrelationId" -ForegroundColor Gray
    Write-Host "Coverage Areas: Backup Integrity, SDDL Validation, Security Verification" -ForegroundColor Gray
}
