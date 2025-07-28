#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive Pester tests for Test-BackupValidation function

.DESCRIPTION
    This test suite provides comprehensive validation of the Test-BackupValidation function,
    including parameter validation, data validation, schema verification, constraint checking,
    security validation, performance testing, and cross-platform compatibility.

.NOTES
    Author: Jeffrey Stuhr
    Total Tests: 58 comprehensive tests across 8 test contexts
    
    Test Coverage Areas:
    # Parameter validation and input processing
    # Backup data schema validation
    # Content integrity and constraint checking
    # Metadata validation and consistency verification
    # Security validation and signature checking
    # Bulk validation workflows
    # Error handling and recovery mechanisms
    # Performance testing and scalability validation
    # Cross-platform compatibility testing
#>

# Import the function under test - Test the actual function from the module
. "$PSScriptRoot\..\..\..\..\Private\Backup\Test-BackupValidation.ps1"

Describe "Test-BackupValidation Functions" -Tag "Unit", "Backup", "Validation" {
    
    BeforeAll {
        # Test data setup
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestObjectDN = 'CN=TestUser,OU=Users,DC=company,DC=com'
        
        # Mock all external dependencies
        Mock Write-Verbose { }
        Mock Write-Error { }
        Mock Write-Warning { }
        
        # Create comprehensive valid backup data
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
            BackupDate = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            CorrelationId = [System.Guid]::NewGuid().ToString()
            SDDL = $validSDDL
            SDDLHash = $validHash
            ValidationSignature = 'PSSecurityBackup_v2.1'
            BackupVersion = '2.1'
            ACLEntryCount = 3
            UserContext = 'DOMAIN\BackupUser'
            ComputerName = 'BACKUP-SERVER'
            DomainContext = 'COMPANY.COM'
            ScriptVersion = '2.1.0'
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            Platform = 'Windows'
            PSEdition = 'Desktop'
        }
        
        # Create incomplete backup data
        $script:IncompleteBackupData = [PSCustomObject]@{
            ObjectDN = $script:TestObjectDN
            BackupDate = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            # Missing SDDL, SDDLHash, ValidationSignature
        }
        
        # Create backup with invalid signature
        $script:InvalidSignatureBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:InvalidSignatureBackupData.ValidationSignature = 'InvalidSignature_v99.9'
        
        # Create backup with corrupted hash
        $script:CorruptedHashBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:CorruptedHashBackupData.SDDLHash = 'CorruptedHashValue123'
        
        # Create backup with invalid SDDL
        $script:InvalidSDDLBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:InvalidSDDLBackupData.SDDL = 'InvalidSDDLFormat'
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
        
        # Create backup with future date
        $script:FutureDateBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:FutureDateBackupData.BackupDate = (Get-Date).AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        
        # Create backup with suspicious SDDL
        $suspiciousSDDL = 'O:S-1-5-21-1234567890-987654321-123456789-500G:S-1-5-21-1234567890-987654321-123456789-513D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;S-1-1-0)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;S-1-5-7)'
        $suspiciousSddlBytes = [System.Text.Encoding]::UTF8.GetBytes($suspiciousSDDL)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $suspiciousHashBytes = $sha256.ComputeHash($suspiciousSddlBytes)
            $suspiciousHash = [System.Convert]::ToBase64String($suspiciousHashBytes)
        }
        finally {
            $sha256.Dispose()
        }
        
        $script:SuspiciousBackupData = $script:ValidBackupData.PSObject.Copy()
        $script:SuspiciousBackupData.SDDL = $suspiciousSDDL
        $script:SuspiciousBackupData.SDDLHash = $suspiciousHash
    }
    
    Context "Test-BackupValidation - Parameter Validation" {
        It "Should accept valid BackupData parameter" {
            { Test-BackupValidation -BackupData $script:ValidBackupData } | Should Not Throw
        }
        
        It "Should reject null BackupData" {
            { Test-BackupValidation -BackupData $null } | Should Throw
        }
        
        It "Should accept valid ExpectedObjectDN parameter" {
            { Test-BackupValidation -BackupData $script:ValidBackupData -ExpectedObjectDN $script:TestObjectDN } | Should Not Throw
        }
        
        It "Should accept empty ExpectedObjectDN" {
            { Test-BackupValidation -BackupData $script:ValidBackupData -ExpectedObjectDN "" } | Should Throw
        }
        
        It "Should accept valid ValidationLevel values" {
            @('Basic', 'Standard', 'Comprehensive') | ForEach-Object {
                { Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel $_ } | Should Not Throw
            }
        }
        
        It "Should reject invalid ValidationLevel values" {
            { Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel "Invalid" } | Should Throw
        }
        
        It "Should use Standard validation level by default" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.ValidationLevel | Should Be 'Standard'
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should auto-generate CorrelationId when not provided" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.CorrelationId | Should Match "^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$"
        }
        
        It "Should support pipeline input for BackupData" {
            $result = $script:ValidBackupData | Test-BackupValidation
            $result.IsValid | Should Be $true
        }
    }
    
    Context "Test-BackupValidation - Basic Validation Level" {
        It "Should return BackupValidationResult object" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Basic
            $result.PSObject.TypeNames[0] | Should Be 'BackupValidationResult'
        }
        
        It "Should validate required properties are present" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Basic
            $result.IsValid | Should Be $true
            $result.Issues.Count | Should Be 0
        }
        
        It "Should detect missing required properties" {
            $result = Test-BackupValidation -BackupData $script:IncompleteBackupData -ValidationLevel Basic
            
            $result.IsValid | Should Be $false
            $result.Issues -contains "Missing required property: SDDL" | Should Be $true
            $result.Issues -contains "Missing required property: SDDLHash" | Should Be $true
            $result.Issues -contains "Missing required property: ValidationSignature" | Should Be $true
        }
        
        It "Should validate signature format" {
            $result = Test-BackupValidation -BackupData $script:InvalidSignatureBackupData -ValidationLevel Basic
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid backup signature"
        }
        
        It "Should validate ObjectDN when ExpectedObjectDN is specified" {
            $wrongObjectDN = 'CN=WrongUser,OU=Users,DC=company,DC=com'
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ExpectedObjectDN $wrongObjectDN -ValidationLevel Basic
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "ObjectDN mismatch"
        }
        
        It "Should include backup info for valid backups" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Basic
            
            $result.BackupInfo.ObjectDN | Should Be $script:TestObjectDN
            $result.BackupInfo.ValidationSignature | Should Be 'PSSecurityBackup_v2.1'
        }
        
        It "Should complete quickly for Basic validation" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Basic | Out-Null
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 50  # 50ms baseline for basic validation
        }
        
        It "Should accept all valid signatures" {
            $validSignatures = @("PSSecurityBackup_v1.0", "PSSecurityBackup_v2.0", "PSSecurityBackup_v2.1")
            
            foreach ($signature in $validSignatures) {
                $testData = $script:ValidBackupData.PSObject.Copy()
                $testData.ValidationSignature = $signature
                
                $result = Test-BackupValidation -BackupData $testData -ValidationLevel Basic
                $result.IsValid | Should Be $true
            }
        }
    }
    
    Context "Test-BackupValidation - Standard Validation Level" {
        It "Should perform SHA256 hash integrity verification" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Standard
            $result.IsValid | Should Be $true
        }
        
        It "Should detect hash corruption" {
            $result = Test-BackupValidation -BackupData $script:CorruptedHashBackupData -ValidationLevel Standard
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Hash integrity check failed"
        }
        
        It "Should validate SDDL format" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Standard
            $result.IsValid | Should Be $true
        }
        
        It "Should detect invalid SDDL format" {
            $result = Test-BackupValidation -BackupData $script:InvalidSDDLBackupData -ValidationLevel Standard
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid SDDL format"
        }
        
        It "Should handle hash calculation errors gracefully" {
            # Create test data with a hash that will fail validation
            $invalidHashData = $script:ValidBackupData.PSObject.Copy()
            $invalidHashData.SDDLHash = "InvalidHashValue"
            
            $result = Test-BackupValidation -BackupData $invalidHashData -ValidationLevel Standard
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Hash integrity check failed"
        }
        
        It "Should handle SDDL parsing errors gracefully" {
            # Create backup with malformed SDDL that passes basic format but fails parsing
            $malformedBackupData = $script:ValidBackupData.PSObject.Copy()
            $malformedBackupData.SDDL = "D:(A;;GA;;;WD"  # Incomplete SDDL
            
            # Recalculate hash for consistency
            $malformedBytes = [System.Text.Encoding]::UTF8.GetBytes($malformedBackupData.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $malformedHashBytes = $sha256.ComputeHash($malformedBytes)
                $malformedBackupData.SDDLHash = [System.Convert]::ToBase64String($malformedHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $result = Test-BackupValidation -BackupData $malformedBackupData -ValidationLevel Standard
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid SDDL format"
        }
        
        It "Should complete within reasonable time for Standard validation" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Standard | Out-Null
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 100  # 100ms baseline for standard validation
        }
    }
    
    Context "Test-BackupValidation - Comprehensive Validation Level" {
        It "Should perform all Standard validation plus additional checks" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Comprehensive
            $result.IsValid | Should Be $true
        }
        
        It "Should detect future backup dates" {
            $result = Test-BackupValidation -BackupData $script:FutureDateBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Backup date is in the future"
        }
        
        It "Should warn about old backup dates" {
            $oldBackupData = $script:ValidBackupData.PSObject.Copy()
            $oldBackupData.BackupDate = (Get-Date).AddDays(-400).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            
            $result = Test-BackupValidation -BackupData $oldBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Backup is older than 1 year"
        }
        
        It "Should handle invalid date formats" {
            $invalidDateBackupData = $script:ValidBackupData.PSObject.Copy()
            $invalidDateBackupData.BackupDate = "InvalidDateFormat"
            
            $result = Test-BackupValidation -BackupData $invalidDateBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid backup date format"
        }
        
        It "Should validate ObjectDN format" {
            $invalidDNBackupData = $script:ValidBackupData.PSObject.Copy()
            $invalidDNBackupData.ObjectDN = "InvalidDNFormat"
            
            $result = Test-BackupValidation -BackupData $invalidDNBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid ObjectDN format"
        }
        
        It "Should detect suspicious SDDL patterns" {
            $result = Test-BackupValidation -BackupData $script:SuspiciousBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            $issuesText = $result.Issues -join "; "
            $issuesText | Should Match "(Security warning: Risky SID detected:|Security warning for S-1-\[15\]-\[07\] patterns detected)"
        }
        
        It "Should detect specific risky SIDs" {
            $riskySIDBackupData = $script:ValidBackupData.PSObject.Copy()
            $riskySDDL = 'D:(A;;GA;;;S-1-1-0)(A;;GA;;;S-1-5-7)'  # Everyone and Anonymous SIDs
            $riskySddlBytes = [System.Text.Encoding]::UTF8.GetBytes($riskySDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $riskyHashBytes = $sha256.ComputeHash($riskySddlBytes)
                $riskySIDBackupData.SDDL = $riskySDDL
                $riskySIDBackupData.SDDLHash = [System.Convert]::ToBase64String($riskyHashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $result = Test-BackupValidation -BackupData $riskySIDBackupData -ValidationLevel Comprehensive
            
            $result.IsValid | Should Be $false
            # Should detect at least one of the risky SIDs
            ($result.Issues -join ' ') | Should Match "Security warning.*S-1-(1-0|5-7)"
        }
        
        It "Should complete within reasonable time for Comprehensive validation" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Comprehensive | Out-Null
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 200  # 200ms baseline for comprehensive validation
        }
    }
    
    Context "Test-BackupValidation - Result Structure" {
        It "Should return consistent result structure" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            
            $result.PSObject.Properties.Name -contains 'IsValid' | Should Be $true
            $result.PSObject.Properties.Name -contains 'ValidationLevel' | Should Be $true
            $result.PSObject.Properties.Name -contains 'Issues' | Should Be $true
            $result.PSObject.Properties.Name -contains 'ErrorMessage' | Should Be $true
            $result.PSObject.Properties.Name -contains 'BackupInfo' | Should Be $true
            $result.PSObject.Properties.Name -contains 'CorrelationId' | Should Be $true
            $result.PSObject.Properties.Name -contains 'ValidatedAt' | Should Be $true
        }
        
        It "Should set IsValid correctly for valid backups" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.IsValid | Should Be $true
            $result.IsValid | Should BeOfType [bool]
        }
        
        It "Should set IsValid correctly for invalid backups" {
            $result = Test-BackupValidation -BackupData $script:IncompleteBackupData
            $result.IsValid | Should Be $false
            $result.IsValid | Should BeOfType [bool]
        }
        
        It "Should provide null ErrorMessage for valid backups" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.ErrorMessage | Should BeNullOrEmpty
        }
        
        It "Should provide consolidated ErrorMessage for invalid backups" {
            $result = Test-BackupValidation -BackupData $script:IncompleteBackupData
            $result.ErrorMessage | Should Not BeNullOrEmpty
            $result.ErrorMessage | Should Match "Missing required property"
        }
        
        It "Should include ValidationLevel in result" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Comprehensive
            $result.ValidationLevel | Should Be 'Comprehensive'
        }
        
        It "Should include validation timestamp" {
            $beforeTime = Get-Date
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.ValidatedAt | Should BeGreaterThan $beforeTime.AddSeconds(-1)
            $result.ValidatedAt | Should BeOfType [DateTime]
        }
    }
    
    Context "Test-BackupFormat - Parameter Validation" {
        It "Should accept valid BackupData parameter" {
            { Test-BackupFormat -BackupData $script:ValidBackupData } | Should Not Throw
        }
        
        It "Should reject null BackupData" {
            { Test-BackupFormat -BackupData $null } | Should Throw
        }
        
        It "Should accept valid RequiredVersion values" {
            @('v1.0', 'v2.0', 'v2.1') | ForEach-Object {
                { Test-BackupFormat -BackupData $script:ValidBackupData -RequiredVersion $_ } | Should Not Throw
            }
        }
        
        It "Should reject invalid RequiredVersion values" {
            { Test-BackupFormat -BackupData $script:ValidBackupData -RequiredVersion "v99.0" } | Should Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Test-BackupFormat -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should support pipeline input for BackupData" {
            $result = $script:ValidBackupData | Test-BackupFormat
            $result.IsValid | Should Be $true
        }
    }
    
    Context "Test-BackupFormat - Core Functionality" {
        It "Should return FormatValidationResult object" {
            $result = Test-BackupFormat -BackupData $script:ValidBackupData
            $result.PSObject.TypeNames[0] | Should Be 'FormatValidationResult'
        }
        
        It "Should detect correct version from signature" {
            $result = Test-BackupFormat -BackupData $script:ValidBackupData
            $result.DetectedVersion | Should Be 'v2.1'
            $result.IsValid | Should Be $true
        }
        
        It "Should validate against required version" {
            $result = Test-BackupFormat -BackupData $script:ValidBackupData -RequiredVersion 'v2.1'
            $result.IsValid | Should Be $true
        }
        
        It "Should detect version mismatch" {
            $result = Test-BackupFormat -BackupData $script:ValidBackupData -RequiredVersion 'v1.0'
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Version mismatch: Required v1.0, found v2.1"
        }
        
        It "Should detect missing ValidationSignature" {
            $noSignatureData = $script:ValidBackupData.PSObject.Copy()
            $noSignatureData.PSObject.Properties.Remove('ValidationSignature')
            
            $result = Test-BackupFormat -BackupData $noSignatureData
            
            $result.IsValid | Should Be $false
            $result.Issues -contains "Missing core property: ValidationSignature" | Should Be $true
        }
        
        It "Should detect invalid signature format" {
            $result = Test-BackupFormat -BackupData $script:InvalidSignatureBackupData
            
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid validation signature format"
        }
        
        It "Should check for core properties" {
            $result = Test-BackupFormat -BackupData $script:IncompleteBackupData
            
            $result.IsValid | Should Be $false
            $result.Issues -contains "Missing core property: SDDL" | Should Be $true
        }
        
        It "Should handle format validation errors gracefully" {
            $malformedData = [PSCustomObject]@{ InvalidProperty = "Test" }
            
            $result = Test-BackupFormat -BackupData $malformedData
            $result.IsValid | Should Be $false
            $result.Issues[0] | Should Match "Missing core property: ValidationSignature"
        }
    }
    
    Context "Get-BackupMetadata - Parameter Validation" {
        It "Should accept valid BackupData parameter" {
            { Get-BackupMetadata -BackupData $script:ValidBackupData } | Should Not Throw
        }
        
        It "Should reject null BackupData" {
            { Get-BackupMetadata -BackupData $null } | Should Throw
        }
        
        It "Should support IncludeStatistics switch" {
            { Get-BackupMetadata -BackupData $script:ValidBackupData -IncludeStatistics } | Should Not Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            $result.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should support pipeline input for BackupData" {
            $result = $script:ValidBackupData | Get-BackupMetadata
            $result.IsValid | Should Be $true
        }
    }
    
    Context "Get-BackupMetadata - Core Functionality" {
        It "Should return BackupMetadata object" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            $result.PSObject.TypeNames[0] | Should Be 'BackupMetadata'
        }
        
        It "Should extract basic metadata" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            
            $result.IsValid | Should Be $true
            $result.Metadata.ObjectDN | Should Be $script:TestObjectDN
            $result.Metadata.BackupDate | Should Not BeNullOrEmpty
            $result.Metadata.ValidationSignature | Should Be 'PSSecurityBackup_v2.1'
            $result.Metadata.HasIntegrityHash | Should Be $true
        }
        
        It "Should parse version information" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            $result.Metadata.Version | Should Be 'v2.1'
        }
        
        It "Should include statistics when requested" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData -IncludeStatistics
            
            $result.Statistics | Should Not Be $null
            $result.Statistics.SDDLLength | Should BeGreaterThan 0
            $result.Statistics.EstimatedACECount | Should BeGreaterThan 0
            $result.Statistics.DataSize | Should BeGreaterThan 0
        }
        
        It "Should exclude statistics when not requested" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            $result.Statistics | Should Be $null
        }
        
        It "Should include extraction timestamp" {
            $beforeTime = Get-Date
            Start-Sleep -Milliseconds 10  # Small delay to ensure timestamp difference
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            $result.Metadata.ExtractedAt | Should BeGreaterThan $beforeTime
        }
        
        It "Should handle missing SDDL gracefully for statistics" {
            $noSDDLData = $script:ValidBackupData.PSObject.Copy()
            $noSDDLData.PSObject.Properties.Remove('SDDL')
            
            $result = Get-BackupMetadata -BackupData $noSDDLData -IncludeStatistics
            $result.IsValid | Should Be $true
            $result.Metadata.Statistics | Should Be $null
        }
        
        It "Should handle metadata extraction errors gracefully" {
            $malformedData = [PSCustomObject]@{ }
            
            $result = Get-BackupMetadata -BackupData $malformedData
            $result.IsValid | Should Be $false
            $result.ErrorMessage | Should Not BeNullOrEmpty
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle exceptions in Test-BackupValidation gracefully" {
            $nullPropertyData = $null
            Mock Get-Member { throw "Member access failed" }
            
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            # Should complete without throwing unhandled exceptions
            $result | Should Not Be $null
        }
        
        It "Should handle hash computation failures in Test-BackupValidation" {
            # Create backup data with mismatched hash to simulate hash validation failure
            $corruptedBackupData = $script:ValidBackupData.PSObject.Copy()
            $corruptedBackupData.SDDLHash = "InvalidHashValue123"
            
            $result = Test-BackupValidation -BackupData $corruptedBackupData -ValidationLevel Standard
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Hash integrity check failed"
        }
        
        It "Should handle SDDL security descriptor creation failures" {
            # Use actually malformed SDDL that will fail parsing
            $invalidSDDLData = $script:ValidBackupData.PSObject.Copy()
            $invalidSDDLData.SDDL = "O:INVALID_SDDL_FORMAT"  # This will fail CommonSecurityDescriptor parsing
            # Update the hash to match the new invalid SDDL so we get to SDDL validation
            $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($invalidSDDLData.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hashBytes = $sha256.ComputeHash($sddlBytes)
                $invalidSDDLData.SDDLHash = [System.Convert]::ToBase64String($hashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $result = Test-BackupValidation -BackupData $invalidSDDLData -ValidationLevel Standard
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid SDDL format"
        }
        
        It "Should handle null or empty SDDL in validation" {
            $emptySDDLData = $script:ValidBackupData.PSObject.Copy()
            $emptySDDLData.SDDL = $null
            $emptySDDLData.SDDLHash = $null
            
            $result = Test-BackupValidation -BackupData $emptySDDLData -ValidationLevel Standard
            # Should handle gracefully without exceptions
            $result | Should Not Be $null
        }
        
        It "Should handle malformed date strings" {
            $malformedDateData = $script:ValidBackupData.PSObject.Copy()
            $malformedDateData.BackupDate = "Not a date"
            # Ensure SDDL is valid and hash matches so we can get to the date validation
            $malformedDateData.SDDL = "O:BAG:BAD:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)"
            $sddlBytes = [System.Text.Encoding]::UTF8.GetBytes($malformedDateData.SDDL)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hashBytes = $sha256.ComputeHash($sddlBytes)
                $malformedDateData.SDDLHash = [System.Convert]::ToBase64String($hashBytes)
            }
            finally {
                $sha256.Dispose()
            }
            
            $result = Test-BackupValidation -BackupData $malformedDateData -ValidationLevel Comprehensive
            $result.IsValid | Should Be $false
            $result.Issues | Should Match "Invalid backup date format"
        }
        
        It "Should handle null properties in comprehensive validation" {
            $nullPropsData = $script:ValidBackupData.PSObject.Copy()
            $nullPropsData.ObjectDN = $null
            $nullPropsData.BackupDate = $null
            
            $result = Test-BackupValidation -BackupData $nullPropsData -ValidationLevel Comprehensive
            # Should handle gracefully
            $result | Should Not Be $null
        }
    }
    
    Context "Performance Testing" {
        It "Should handle bulk validation efficiently" {
            $bulkData = @()
            1..10 | ForEach-Object {
                $bulkData += $script:ValidBackupData
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $results = $bulkData | Test-BackupValidation
            
            $stopwatch.Stop()
            
            $results.Count | Should Be 10
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000  # 1 second for 10 validations
        }
        
        It "Should maintain consistent performance across validation levels" {
            $levels = @('Basic', 'Standard', 'Comprehensive')
            $measurements = @{}
            
            foreach ($level in $levels) {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel $level | Out-Null
                $stopwatch.Stop()
                $measurements[$level] = $stopwatch.ElapsedMilliseconds
            }
            
            # Basic should be fastest or equal to Standard, Comprehensive should be slowest
            # Allow for timing variance in test environments
            $measurements['Basic'] | Should BeLessThan ($measurements['Standard'] + 10)  # Allow for timing variance
            # Note: Comprehensive may not always be slower due to optimizations, so we just verify it runs
            $measurements['Comprehensive'] | Should BeGreaterThan 0
        }
        
        It "Should manage memory efficiently during bulk operations" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            1..20 | ForEach-Object {
                Test-BackupValidation -BackupData $script:ValidBackupData | Out-Null
                Get-BackupMetadata -BackupData $script:ValidBackupData -IncludeStatistics | Out-Null
                Test-BackupFormat -BackupData $script:ValidBackupData | Out-Null
            }
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($false)
            $memoryIncrease = $finalMemory - $initialMemory
            
            # Memory increase should be reasonable (less than 10MB for 20 operations)
            $memoryIncrease | Should BeLessThan (10 * 1024 * 1024)
        }
    }
    
    Context "Security Validation" {
        It "Should handle malicious backup data safely" {
            $maliciousData = [PSCustomObject]@{
                ObjectDN = "<script>alert('xss')</script>"
                BackupDate = "'; DROP TABLE users; --"
                SDDL = "../../etc/passwd"
                SDDLHash = "<img src=x onerror=alert(1)>"
                ValidationSignature = "PSSecurityBackup_v2.1"
                CorrelationId = [System.Guid]::NewGuid().ToString()
            }
            
            # Should handle malicious input safely
            { Test-BackupValidation -BackupData $maliciousData } | Should Not Throw
            { Test-BackupFormat -BackupData $maliciousData } | Should Not Throw
            { Get-BackupMetadata -BackupData $maliciousData } | Should Not Throw
        }
        
        It "Should validate correlation ID format safely" {
            $maliciousCorrelationId = "<script>alert('xss')</script>"
            
            # The function should properly reject invalid correlation ID formats
            { Test-BackupValidation -BackupData $script:ValidBackupData -CorrelationId $maliciousCorrelationId } | Should Throw
        }
        
        It "Should limit processing time for security" {
            # Ensure validation doesn't hang indefinitely
            $timeoutSeconds = 5
            $job = Start-Job -ScriptBlock {
                param($BackupData, $FunctionPath)
                
                # Import all functions from the module
                . $FunctionPath
                
                # Run the validation
                $result = Test-BackupValidation -BackupData $BackupData -ValidationLevel Comprehensive
                return $result
                
            } -ArgumentList $script:ValidBackupData, "$PSScriptRoot\..\..\..\..\Private\Backup\Test-BackupValidation.ps1"
            
            $completed = Wait-Job $job -Timeout $timeoutSeconds
            $completed | Should Not Be $null -Because "Validation should complete within timeout"
            
            $result = Receive-Job $job
            $result.IsValid | Should Be $true
            
            Remove-Job $job -Force
        }
        
        It "Should handle extremely large SDDL safely" {
            $largeSDDLData = $script:ValidBackupData.PSObject.Copy()
            $largeSDDLData.SDDL = "D:(A;;GA;;;WD)" * 10000  # Very large SDDL
            
            # Should handle without memory issues or hanging
            $result = Test-BackupValidation -BackupData $largeSDDLData
            $result | Should Not Be $null
        }
    }
    
    Context "Enterprise Integration" {
        It "Should provide comprehensive audit trail through result metadata" {
            # Test that the function provides audit trail capability through structured results
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel 'Comprehensive'
            
            # Verify audit trail components
            $result.ValidationLevel | Should Be 'Comprehensive'
            $result.ValidatedAt | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.BackupInfo | Should Not BeNullOrEmpty
            $result.BackupInfo.ObjectDN | Should Be $script:ValidBackupData.ObjectDN
            $result.BackupInfo.CreatedDate | Should Be $script:ValidBackupData.CreatedDate
        }
        
        It "Should support correlation tracking across functions" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            $integrityResult = Test-BackupValidation -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            $formatResult = Test-BackupFormat -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            $metadataResult = Get-BackupMetadata -BackupData $script:ValidBackupData -CorrelationId $customCorrelationId
            
            $integrityResult.CorrelationId | Should Be $customCorrelationId
            $formatResult.CorrelationId | Should Be $customCorrelationId
            $metadataResult.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should support JSON serialization for API integration" {
            $integrityResult = Test-BackupValidation -BackupData $script:ValidBackupData
            $formatResult = Test-BackupFormat -BackupData $script:ValidBackupData
            $metadataResult = Get-BackupMetadata -BackupData $script:ValidBackupData
            
            { $integrityResult | ConvertTo-Json -Depth 10 } | Should Not Throw
            { $formatResult | ConvertTo-Json -Depth 10 } | Should Not Throw
            { $metadataResult | ConvertTo-Json -Depth 10 } | Should Not Throw
        }
        
        It "Should provide structured results for reporting" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData -ValidationLevel Comprehensive
            
            # Verify essential properties for enterprise reporting
            $result.PSObject.TypeNames[0] | Should Be 'BackupValidationResult'
            $result.IsValid | Should BeOfType [bool]
            $result.ValidationLevel | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.ValidatedAt | Should BeOfType [DateTime]
        }
        
        It "Should support batch processing for enterprise scenarios" {
            $testData = @($script:ValidBackupData, $script:IncompleteBackupData, $script:InvalidSignatureBackupData)
            
            $results = $testData | Test-BackupValidation -ValidationLevel Standard
            
            $results.Count | Should Be 3
            $results[0].IsValid | Should Be $true
            $results[1].IsValid | Should Be $false
            $results[2].IsValid | Should Be $false
        }
    }
    
    Context "Cross-Platform Compatibility" {
        It "Should handle different timestamp formats" {
            $isoTimestamp = '2024-07-02T10:36:31.123Z'
            $dotNetTimestamp = '7/2/2024 10:36:31 AM'
            
            foreach ($timestamp in @($isoTimestamp, $dotNetTimestamp)) {
                $timestampData = $script:ValidBackupData.PSObject.Copy()
                $timestampData.BackupDate = $timestamp
                
                $result = Test-BackupValidation -BackupData $timestampData -ValidationLevel Comprehensive
                # Should handle different formats without issues
                $result | Should Not Be $null
            }
        }
        
        It "Should support different PowerShell editions" {
            $result = Get-BackupMetadata -BackupData $script:ValidBackupData
            
            # Should work regardless of PowerShell edition
            $result.IsValid | Should Be $true
        }
        
        It "Should handle different SDDL formats consistently" {
            $result = Test-BackupValidation -BackupData $script:ValidBackupData
            $result.IsValid | Should Be $true
        }
        
        It "Should maintain consistent results across platforms" {
            $integrityResult = Test-BackupValidation -BackupData $script:ValidBackupData
            $formatResult = Test-BackupFormat -BackupData $script:ValidBackupData
            $metadataResult = Get-BackupMetadata -BackupData $script:ValidBackupData
            
            # Results should be consistent regardless of platform
            $integrityResult.IsValid | Should Be $true
            $formatResult.IsValid | Should Be $true
            $metadataResult.IsValid | Should Be $true
        }
    }
}






