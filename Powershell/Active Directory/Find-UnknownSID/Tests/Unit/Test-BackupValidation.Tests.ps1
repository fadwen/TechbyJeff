#Requires -Module Pester

# Import the module under test
. $PSScriptRoot\..\..\Private\Restore\Test-BackupValidation.ps1

Describe "Test-BackupValidation Module" -Tag "Unit", "BackupValidation" {

    Context "Test-BackupIntegrity" {

        BeforeEach {
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
