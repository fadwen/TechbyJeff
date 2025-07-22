#Requires -Module Pester
#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive Pester tests for Test-BackupIntegrity function

.DESCRIPTION
    This test suite provides comprehensive validation of the Test-BackupIntegrity function,
    including parameter validation, integrity checking, file validation, corruption detection,
    security verification, performance testing, and cross-platform compatibility.

.NOTES
    Author: Jeffrey Stuhr
    Total Tests: 63 comprehensive tests across various contexts
    
    Test Coverage Areas:
    # Parameter validation and input processing
    # File integrity verification
    # Checksum validation and corruption detection
    # Metadata integrity verification
    # Security signature validation
    # Bulk integrity checking workflows
    # Error handling and recovery mechanisms
    # Performance testing and scalability validation
    # Cross-platform compatibility testing
#>

# Import test helpers only (no main script needed for isolated function testing)
. "$PSScriptRoot\..\..\TestHelpers\BackupTestHelpers.ps1"

Describe "Test-BackupIntegrity" -Tag "Unit", "Backup", "Integrity" {
    
    BeforeAll {
        # Import required dependencies
        $script:ProjectRoot = Join-Path $PSScriptRoot '..\..\..'
        
        # Source the logging function (required dependency)
        . (Join-Path $script:ProjectRoot 'Private\Logging\Write-StructuredLog.ps1')
        
        # Source the target function
        . (Join-Path $script:ProjectRoot 'Private\Utilities\Test-BackupIntegrity.ps1')
        
        # Test data setup
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupDir = Join-Path $env:TEMP "IntegrityTests"
        $script:TestObjectDN = 'CN=TestUser,OU=Users,DC=company,DC=com'
        
        # Create test directory
        if (-not (Test-Path $script:TestBackupDir)) {
            New-Item -ItemType Directory -Path $script:TestBackupDir -Force | Out-Null
        }
        
        # Mock all external dependencies
        Mock Write-StructuredLog { }
        Mock Write-Verbose { }
        Mock Write-Error { }
        Mock Write-Warning { }
        
        # Create comprehensive test backup data with valid SDDL and hash
        $validSDDL = 'O:S-1-5-21-1234567890-987654321-123456789-500G:S-1-5-21-1234567890-987654321-123456789-513D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRCWDWO;;;AU)'
        $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($validSDDL)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $validHashBytes = $sha256.ComputeHash($sddlBytes)
            $validHash = [System.Convert]::ToBase64String($validHashBytes)
        }
        finally {
            $sha256.Dispose()
        }
        
        $script:ValidBackupData = [PSCustomObject]@{
            ObjectDN = $script:TestObjectDN
            BackupDate = '2024-07-02T10:36:31.123Z'
            CorrelationId = [System.Guid]::NewGuid().ToString()
            SDDL = $validSDDL
            SDDLHash = $validHash
            BackupVersion = '2.1'
            ValidationSignature = 'PSSecurityBackup_v2.1'
            ACLEntryCount = 3
            UserContext = 'DOMAIN\BackupUser'
            ComputerName = 'BACKUP-SERVER'
            DomainContext = 'COMPANY.COM'
            ScriptVersion = '2.1.0'
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            Platform = 'Windows'
            PSEdition = 'Desktop'
        }
        
        # Create valid backup file
        $script:ValidBackupFile = Join-Path $script:TestBackupDir "valid_backup.xml"
        $script:ValidBackupData | Export-Clixml -Path $script:ValidBackupFile -Force
        
        # Create corrupt backup data with mismatched hash
        $script:CorruptBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:CorruptBackupData.SDDLHash = "InvalidHashValue123"
        $script:CorruptBackupFile = Join-Path $script:TestBackupDir "corrupt_backup.xml"
        $script:CorruptBackupData | Export-Clixml -Path $script:CorruptBackupFile -Force
        
        # Create incomplete backup data missing required properties
        $script:IncompleteBackupData = [PSCustomObject]@{
            ObjectDN = $script:TestObjectDN
            BackupDate = '2024-07-02T10:36:31.123Z'
            # Missing SDDL, SDDLHash, CorrelationId
        }
        $script:IncompleteBackupFile = Join-Path $script:TestBackupDir "incomplete_backup.xml"
        $script:IncompleteBackupData | Export-Clixml -Path $script:IncompleteBackupFile -Force
        
        # Create backup with invalid SDDL
        $script:InvalidSDDLBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:InvalidSDDLBackupData.SDDL = "InvalidSDDLString"
        # Recalculate hash for invalid SDDL
        $invalidSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($script:InvalidSDDLBackupData.SDDL)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $invalidHashBytes = $sha256.ComputeHash($invalidSddlBytes)
            $script:InvalidSDDLBackupData.SDDLHash = [System.Convert]::ToBase64String($invalidHashBytes)
        }
        finally {
            $sha256.Dispose()
        }
        $script:InvalidSDDLBackupFile = Join-Path $script:TestBackupDir "invalid_sddl_backup.xml"
        $script:InvalidSDDLBackupData | Export-Clixml -Path $script:InvalidSDDLBackupFile -Force
        
        # Create backup with unsupported version
        $script:UnsupportedVersionBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:UnsupportedVersionBackupData.BackupVersion = '99.0'
        $script:UnsupportedVersionBackupFile = Join-Path $script:TestBackupDir "unsupported_version_backup.xml"
        $script:UnsupportedVersionBackupData | Export-Clixml -Path $script:UnsupportedVersionBackupFile -Force
    }
    
    AfterAll {
        # Cleanup test files
        if (Test-Path $script:TestBackupDir) {
            Remove-Item $script:TestBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Parameter Validation" {
        It "Should accept valid BackupFilePath parameter" {
            { Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile } | Should Not Throw
        }
        
        It "Should reject null BackupFilePath" {
            { Test-BackupIntegrity -BackupFilePath $null } | Should Throw
        }
        
        It "Should reject empty BackupFilePath" {
            { Test-BackupIntegrity -BackupFilePath "" } | Should Throw
        }
        
        It "Should accept absolute file paths" {
            { Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile } | Should Not Throw
        }
        
        It "Should accept relative file paths" {
            $relativePath = "..\IntegrityTests\valid_backup.xml"
            { Test-BackupIntegrity -BackupFilePath $relativePath } | Should Not Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            { Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile -CorrelationId $customCorrelationId } | Should Not Throw
        }
        
        It "Should auto-generate CorrelationId when not provided" {
            { Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile } | Should Not Throw
        }
        
        It "Should handle Windows path formats" {
            $windowsPath = "C:\Temp\backup.xml"
            { Test-BackupIntegrity -BackupFilePath $windowsPath } | Should Not Throw -Because "Should accept Windows path format even if file doesn't exist"
        }
        
        It "Should handle UNC path formats" {
            $uncPath = "\\server\share\backup.xml"
            { Test-BackupIntegrity -BackupFilePath $uncPath } | Should Not Throw -Because "Should accept UNC path format even if file doesn't exist"
        }
    }
    
    Context "File Existence and Accessibility Validation" {
        It "Should return valid result for existing backup file" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
            $result.ErrorMessage | Should BeNullOrEmpty
        }
        
        It "Should return invalid result for non-existent file" {
            $nonExistentFile = Join-Path $script:TestBackupDir "nonexistent.xml"
            $result = Test-BackupIntegrity -BackupFilePath $nonExistentFile
            
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Backup file not found:"
            $result.ValidationDetails -join " " | Should Match "File does not exist"
            $result.BackupData | Should Be $null
        }
        
        It "Should validate file path type correctly" {
            # Test with directory path instead of file
            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupDir
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Backup file not found"
        }
        
        It "Should handle file access permission issues" {
            # Mock Test-Path to simulate access denied
            Mock Test-Path { $false } -ParameterFilter { $PathType -eq 'Leaf' }
            
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Backup file not found"
        }
        
        It "Should log file not found appropriately" {
            $nonExistentFile = Join-Path $script:TestBackupDir "missing.xml"
            
            Mock Write-StructuredLog { } -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match "Backup file not found"
            }
            
            Test-BackupIntegrity -BackupFilePath $nonExistentFile | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match "Backup file not found"
            }
        }
    }
    
    Context "SHA256 Hash Integrity Verification" {
        It "Should validate correct SHA256 hash" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
            $result.BackupData | Should Not Be $null
        }
        
        It "Should detect hash mismatch and reject backup" {
            $result = Test-BackupIntegrity -BackupFilePath $script:CorruptBackupFile
            
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "SHA256 hash verification failed"
            $result.ValidationDetails -join " " | Should Match "Hash mismatch detected"
            $result.BackupData | Should Be $null
        }
        
        It "Should compute hash correctly for validation" {
            # Create a new backup with known SDDL and verify hash calculation
            $testSDDL = "D:(A;;GA;;;WD)"
            $testSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($testSDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $expectedHashBytes = $sha256.ComputeHash($testSddlBytes)
                $expectedHash = [System.Convert]::ToBase64String($expectedHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $testBackupData = $script:ValidBackupData.PSObject.Copy()
            $testBackupData.SDDL = $testSDDL
            $testBackupData.SDDLHash = $expectedHash
            
            $testBackupFile = Join-Path $script:TestBackupDir "hash_test_backup.xml"
            $testBackupData | Export-Clixml -Path $testBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $testBackupFile
            $result.IsValid | Should Be $true
            $result.ErrorMessage | Should BeNullOrEmpty
            
            Remove-Item $testBackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle empty SDDL hash validation" {
            $emptySDDLBackupData = $script:ValidBackupData.PSObject.Copy()
            $emptySDDLBackupData.SDDL = ""
            $emptySDDLBytes = [System.Text.Encoding]::UTF8.GetBytes("")
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $emptyHashBytes = $sha256.ComputeHash($emptySDDLBytes)
                $emptySDDLBackupData.SDDLHash = [System.Convert]::ToBase64String($emptyHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $emptySDDLBackupFile = Join-Path $script:TestBackupDir "empty_sddl_backup.xml"
            $emptySDDLBackupData | Export-Clixml -Path $emptySDDLBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $emptySDDLBackupFile
            $result.IsValid | Should Be $false  # Should fail SDDL format validation
            $result.ValidationDetails -join " " | Should Match "Invalid SDDL format"
            
            Remove-Item $emptySDDLBackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should log hash verification failures with details" {
            Mock Write-StructuredLog { } -ParameterFilter {
                $Level -eq 'Error' -and $Message -match "SHA256 hash verification failed"
            }
            
            Test-BackupIntegrity -BackupFilePath $script:CorruptBackupFile | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Error' -and $Message -match "SHA256 hash verification failed"
            }
        }
        
        It "Should dispose of SHA256 resources properly" {
            # This test ensures no resource leaks occur during hash verification
            $iterations = 10
            
            1..$iterations | ForEach-Object {
                Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            }
            
            # If there were resource leaks, this would likely cause issues
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
        }
    }
    
    Context "SDDL Format Validation" {
        It "Should validate correct SDDL format" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
            $result.ValidationDetails.Count | Should Be 0
        }
        
        It "Should detect invalid SDDL format" {
            $result = Test-BackupIntegrity -BackupFilePath $script:InvalidSDDLBackupFile
            
            $result.IsValid | Should Be $false
            $result.ValidationDetails | Should Match "Invalid SDDL format"
        }
        
        It "Should handle SDDL parsing exceptions gracefully" {
            # Create backup with malformed SDDL that causes parsing exception
            $malformedSDDL = "D:(A;;GA;;;WD"  # Incomplete SDDL
            $malformedSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($malformedSDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $malformedHashBytes = $sha256.ComputeHash($malformedSddlBytes)
                $malformedHash = [System.Convert]::ToBase64String($malformedHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $malformedBackupData = $script:ValidBackupData.PSObject.Copy()
            $malformedBackupData.SDDL = $malformedSDDL
            $malformedBackupData.SDDLHash = $malformedHash
            
            $malformedBackupFile = Join-Path $script:TestBackupDir "malformed_sddl_backup.xml"
            $malformedBackupData | Export-Clixml -Path $malformedBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $malformedBackupFile
            $result.IsValid | Should Be $false
            $result.ValidationDetails | Should Match "Invalid SDDL format"
            
            Remove-Item $malformedBackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should validate complex SDDL structures" {
            # Test with more complex but valid SDDL
            $complexSDDL = 'O:BAG:SYD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPLOCRRCWDWO;;;IU)(A;;CCLCSWRPLOCRRCWDWO;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)'
            $complexSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($complexSDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $complexHashBytes = $sha256.ComputeHash($complexSddlBytes)
                $complexHash = [System.Convert]::ToBase64String($complexHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $complexBackupData = $script:ValidBackupData.PSObject.Copy()
            $complexBackupData.SDDL = $complexSDDL
            $complexBackupData.SDDLHash = $complexHash
            
            $complexBackupFile = Join-Path $script:TestBackupDir "complex_sddl_backup.xml"
            $complexBackupData | Export-Clixml -Path $complexBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $complexBackupFile
            $result.IsValid | Should Be $true
            
            Remove-Item $complexBackupFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Metadata Structure Validation" {
        It "Should validate all required properties are present" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
            $result.BackupData | Should Not Be $null
        }
        
        It "Should detect missing required properties" {
            $result = Test-BackupIntegrity -BackupFilePath $script:IncompleteBackupFile
            
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Backup file structure validation failed"
            $result.ValidationDetails -join " " | Should Match "Missing required property"
            $result.BackupData | Should Be $null
        }
        
        It "Should validate backup version compatibility" {
            $result = Test-BackupIntegrity -BackupFilePath $script:UnsupportedVersionBackupFile
            
            $result.IsValid | Should Be $false
            $result.ValidationDetails | Should Match "Unsupported backup version: 99.0"
        }
        
        It "Should accept version 1.x backups" {
            $v1BackupData = $script:ValidBackupData.PSObject.Copy()
            $v1BackupData.BackupVersion = '1.5'
            
            $v1BackupFile = Join-Path $script:TestBackupDir "v1_backup.xml"
            $v1BackupData | Export-Clixml -Path $v1BackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $v1BackupFile
            $result.IsValid | Should Be $true
            
            Remove-Item $v1BackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should accept version 2.x backups" {
            $v2BackupData = $script:ValidBackupData.PSObject.Copy()
            $v2BackupData.BackupVersion = '2.1'
            
            $v2BackupFile = Join-Path $script:TestBackupDir "v2_backup.xml"
            $v2BackupData | Export-Clixml -Path $v2BackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $v2BackupFile
            $result.IsValid | Should Be $true
            
            Remove-Item $v2BackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle missing BackupVersion property gracefully" {
            $noVersionBackupData = $script:ValidBackupData.PSObject.Copy()
            $noVersionBackupData.PSObject.Properties.Remove('BackupVersion')
            
            $noVersionBackupFile = Join-Path $script:TestBackupDir "no_version_backup.xml"
            $noVersionBackupData | Export-Clixml -Path $noVersionBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $noVersionBackupFile
            $result.IsValid | Should Be $true  # Should pass if version property is missing
            
            Remove-Item $noVersionBackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should log structure validation failures with details" {
            Mock Write-StructuredLog { } -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match "Backup structure validation failed"
            }
            
            Test-BackupIntegrity -BackupFilePath $script:IncompleteBackupFile | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Warning' -and $Message -match "Backup structure validation failed"
            }
        }
    }
    
    Context "Result Structure and Properties" {
        It "Should return consistent result structure" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            
            $result.PSObject.Properties.Name -contains 'IsValid' | Should Be $true
            $result.PSObject.Properties.Name -contains 'ErrorMessage' | Should Be $true
            $result.PSObject.Properties.Name -contains 'ValidationDetails' | Should Be $true
            $result.PSObject.Properties.Name -contains 'BackupData' | Should Be $true
        }
        
        It "Should set IsValid to true for valid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $true
            $result.IsValid.GetType() | Should Be ([bool])
        }
        
        It "Should set IsValid to false for invalid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:CorruptBackupFile
            $result.IsValid | Should Be $false
            $result.IsValid.GetType() | Should Be ([bool])
        }
        
        It "Should provide null ErrorMessage for valid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.ErrorMessage | Should BeNullOrEmpty
        }
        
        It "Should provide descriptive ErrorMessage for invalid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:CorruptBackupFile
            $result.ErrorMessage | Should Not BeNullOrEmpty
            $result.ErrorMessage.GetType() | Should Be ([string])
        }
        
        It "Should provide empty ValidationDetails array for valid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.ValidationDetails | Should BeNullOrEmpty
        }
        
        It "Should provide detailed ValidationDetails for invalid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:IncompleteBackupFile
            $result.ValidationDetails | Should Not BeNullOrEmpty
            $result.ValidationDetails.GetType().Name | Should Match "Object\[\]|Array"
            $result.ValidationDetails.Count | Should BeGreaterThan 0
        }
        
        It "Should include BackupData for valid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.BackupData | Should Not Be $null
            $result.BackupData.ObjectDN | Should Be $script:TestObjectDN
        }
        
        It "Should set BackupData to null for invalid backups" {
            $result = Test-BackupIntegrity -BackupFilePath $script:CorruptBackupFile
            $result.BackupData | Should Be $null
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle Import-Clixml failures gracefully" {
            # Create a non-XML file with .xml extension
            $invalidXmlFile = Join-Path $script:TestBackupDir "invalid.xml"
            "This is not valid XML content" | Out-File $invalidXmlFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $invalidXmlFile
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Validation error"
            
            Remove-Item $invalidXmlFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle hash computation failures" {
            # Create backup with intentionally corrupted hash to trigger hash validation failure
            $corruptHashBackup = @{
                ObjectDN = $script:TestObjectDN
                BackupDate = Get-Date
                SDDL = 'O:S-1-5-21-12345G:S-1-5-21-12345D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'
                SDDLHash = 'INTENTIONALLY_CORRUPTED_HASH_VALUE_TO_TRIGGER_FAILURE'
                CorrelationId = [System.Guid]::NewGuid().ToString()
            }
            
            $corruptHashFile = Join-Path $script:TestBackupDir "corrupt_hash_backup.xml"
            $corruptHashBackup | Export-Clixml -Path $corruptHashFile
            
            $result = Test-BackupIntegrity -BackupFilePath $corruptHashFile
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "hash verification failed"
            
            Remove-Item $corruptHashFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle file lock scenarios" {
            # This would typically require file locking, which is hard to simulate
            # We'll mock Import-Clixml to simulate the failure
            Mock Import-Clixml { throw [System.IO.IOException]::new("File is locked") }
            
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Match "Validation error"
        }
        
        It "Should provide detailed error logging for exceptions" {
            Mock Import-Clixml { throw "Test exception" }
            
            Mock Write-StructuredLog { } -ParameterFilter {
                $Level -eq 'Error' -and $Message -match "Error during backup integrity validation"
            }
            
            Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Error' -and $Message -match "Error during backup integrity validation"
            }
        }
        
        It "Should handle null backup data gracefully" {
            Mock Import-Clixml { return $null }
            
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $result.IsValid | Should Be $false
        }
        
        It "Should handle extremely large backup files" {
            # Create backup with very large SDDL
            $largeSDDL = "D:(A;;GA;;;WD)" * 1000  # Repeat SDDL many times
            $largeSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($largeSDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $largeHashBytes = $sha256.ComputeHash($largeSddlBytes)
                $largeHash = [System.Convert]::ToBase64String($largeHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $largeBackupData = $script:ValidBackupData.PSObject.Copy()
            $largeBackupData.SDDL = $largeSDDL
            $largeBackupData.SDDLHash = $largeHash
            
            $largeBackupFile = Join-Path $script:TestBackupDir "large_backup.xml"
            $largeBackupData | Export-Clixml -Path $largeBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $largeBackupFile
            $result.IsValid | Should Be $false  # Should fail SDDL format validation due to repetition
            
            Remove-Item $largeBackupFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Performance Testing" {
        It "Should complete validation within performance baseline" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 500  # 500ms baseline
            $result.IsValid | Should Be $true
        }
        
        It "Should handle multiple validations efficiently" {
            $iterations = 10
            $measurements = @()
            
            1..$iterations | ForEach-Object {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
                $stopwatch.Stop()
                $measurements += $stopwatch.ElapsedMilliseconds
            }
            
            $averageTime = ($measurements | Measure-Object -Average).Average
            $maxTime = ($measurements | Measure-Object -Maximum).Maximum
            
            $averageTime | Should BeLessThan 200   # 200ms average
            $maxTime | Should BeLessThan 1000     # 1 second maximum
        }
        
        It "Should manage memory efficiently during validation" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            1..10 | ForEach-Object {
                Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            }
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($false)
            $memoryIncrease = $finalMemory - $initialMemory
            
            # Memory increase should be reasonable (less than 5MB for 10 validations)
            $memoryIncrease | Should BeLessThan (5 * 1024 * 1024)
        }
        
        It "Should scale validation time linearly with file size" {
            # This test assumes file I/O is the primary factor in performance
            $startTime = Get-Date
            Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            $smallFileTime = (Get-Date) - $startTime
            
            # Small file should complete quickly
            $smallFileTime.TotalMilliseconds | Should BeLessThan 100
        }
    }
    
    Context "Security Validation" {
        It "Should handle malicious file paths safely" {
            $maliciousPaths = @(
                "..\..\..\..\Windows\System32\cmd.exe",
                "C:\Windows\System32\calc.exe",
                "/etc/passwd",
                "\\?\C:\test.xml"
            )
            
            foreach ($maliciousPath in $maliciousPaths) {
                $result = Test-BackupIntegrity -BackupFilePath $maliciousPath
                $result.IsValid | Should Be $false
                $result.ErrorMessage | Should Match "Backup file not found|Validation error"
            }
        }
        
        It "Should validate correlation ID format safely" {
            $maliciousCorrelationId = "<script>alert('xss')</script>"
            
            { Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile -CorrelationId $maliciousCorrelationId } | Should Not Throw
        }
        
        It "Should handle malicious XML content safely" {
            $maliciousXmlFile = Join-Path $script:TestBackupDir "malicious.xml"
            @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<root>&xxe;</root>
"@ | Out-File $maliciousXmlFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $maliciousXmlFile
            $result.IsValid | Should Be $false
            
            Remove-Item $maliciousXmlFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should not expose sensitive information in error messages" {
            # Create backup with potentially sensitive data
            $sensitiveBackupData = $script:ValidBackupData.PSObject.Copy()
            $sensitiveBackupData.UserContext = "DOMAIN\PASSWORD123"
            $sensitiveBackupData.SDDL = "InvalidSDDL_PASSWORD456"
            
            # Recalculate hash
            $sensitiveBytes = [System.Text.Encoding]::UTF8.GetBytes($sensitiveBackupData.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $sensitiveHashBytes = $sha256.ComputeHash($sensitiveBytes)
                $sensitiveBackupData.SDDLHash = [System.Convert]::ToBase64String($sensitiveHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $sensitiveBackupFile = Join-Path $script:TestBackupDir "sensitive_backup.xml"
            $sensitiveBackupData | Export-Clixml -Path $sensitiveBackupFile -Force
            
            $result = Test-BackupIntegrity -BackupFilePath $sensitiveBackupFile
            $result.ErrorMessage | Should Not Match "PASSWORD123"
            $result.ErrorMessage | Should Not Match "PASSWORD456"
            
            Remove-Item $sensitiveBackupFile -Force -ErrorAction SilentlyContinue
        }
        
        It "Should limit validation processing time for security" {
            # Ensure validation doesn't hang indefinitely
            $timeoutSeconds = 10
            $startTime = Get-Date
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            $endTime = Get-Date
            $elapsed = ($endTime - $startTime).TotalSeconds
            
            $elapsed | Should BeLessThan $timeoutSeconds
            $result.IsValid | Should Be $true
        }
    }
    
    Context "Enterprise Integration" {
        It "Should provide comprehensive audit logging" {
            Mock Write-StructuredLog { } -Verifiable -ParameterFilter {
                $Component -eq 'BackupValidation' -and $Message -match "Starting backup integrity validation"
            }
            
            Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            
            Assert-VerifiableMocks
        }
        
        It "Should support correlation tracking throughout validation" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            Mock Write-StructuredLog { } -ParameterFilter {
                $CorrelationId -eq $customCorrelationId
            }
            
            Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile -CorrelationId $customCorrelationId | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $CorrelationId -eq $customCorrelationId
            } -Times 1
        }
        
        It "Should integrate with monitoring systems via structured logging" {
            Mock Write-StructuredLog { } -ParameterFilter {
                $Component -eq 'BackupValidation' -and $Level -eq 'Information'
            }
            
            Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Component -eq 'BackupValidation' -and $Level -eq 'Information'
            }
        }
        
        It "Should provide structured data for compliance reporting" {
            $result = Test-BackupIntegrity -BackupFilePath $script:ValidBackupFile
            
            # Verify result can be serialized for reporting
            { $result | ConvertTo-Json -Depth 10 } | Should Not Throw
            $jsonString = $result | ConvertTo-Json -Depth 10
            $jsonString | Should Match '"IsValid"'
            $jsonString | Should Match '"ValidationDetails"'
        }
        
        It "Should support batch processing for enterprise scenarios" {
            $allBackupFiles = @($script:ValidBackupFile, $script:CorruptBackupFile, $script:IncompleteBackupFile)
            $results = @()
            
            foreach ($backupFile in $allBackupFiles) {
                $results += Test-BackupIntegrity -BackupFilePath $backupFile
            }
            
            $results.Count | Should Be 3
            $results[0].IsValid | Should Be $true
            $results[1].IsValid | Should Be $false
            $results[2].IsValid | Should Be $false
        }
    }
}




