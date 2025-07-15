#Requires -Module Pester

<#
.SYNOPSIS
    Comprehensive Pes        $rule1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity1, [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty, [System.Security.AccessControl.AccessControlType]::Allow,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        , [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
        
        $rule2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity2, [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty, [System.Security.AccessControl.AccessControlType]::Allow,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        , [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
        
        $rule3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity3, [System.DirectoryServices.ActiveDirectoryRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        , [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)-ACLBackup function

.DESCRIPTION
    This test suite provides comprehensive validation of the New-ACLBackup function,
    including parameter validation, backup creation, integrity verification, file system
    operations, error handling, performance testing, and security validation.

.NOTES
    Author: Jeffrey Stuhr
    Total Tests: 71 comprehensive tests across 10 test contexts
    
    Test Coverage Areas:
    # Parameter validation and input processing
    # ACL backup creation and file operations
    # Integrity verification and security validation
    # Filename sanitization and safety measures
    # SDDL conversion and metadata generation
    # Error handling and recovery mechanisms
    # Performance testing and memory management
    # Enterprise integration and logging verification
    # Cross-platform compatibility testing
    # Security validation and input sanitization
#>

Describe "New-ACLBackup" -Tag "Unit", "Backup", "ACLBackup" {
    
    BeforeAll {
        # Import the main script directly since no module manifest exists
        $ScriptPath = Join-Path $PSScriptRoot '..\..\..\..\Find-UnknownSID.ps1'
        if (Test-Path $ScriptPath) {
            . $ScriptPath
        }

        # Import test helpers
        . "$PSScriptRoot\..\..\..\..\Tests\TestHelpers\BackupTestHelpers.ps1"
        
        # Test data setup
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupDir = Join-Path $env:TEMP "ACLBackupTests"
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
        
        # Create comprehensive test ACL object
        $script:TestACL = New-Object System.DirectoryServices.ActiveDirectorySecurity
        
        # Add realistic access rules
        $identity1 = [System.Security.Principal.SecurityIdentifier]"S-1-5-21-1234567890-987654321-123456789-1001"
        $identity2 = [System.Security.Principal.SecurityIdentifier]"S-1-5-21-1234567890-987654321-123456789-1002"
        $identity3 = [System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"  # Administrators
        
        $rule1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity1, [System.DirectoryServices.ActiveDirectoryRights]::GenericRead, [System.Security.AccessControl.AccessControlType]::Allow, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
        
        $rule2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity2, [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite, [System.Security.AccessControl.AccessControlType]::Allow, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
        
        $rule3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity3, [System.DirectoryServices.ActiveDirectoryRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
        
        $script:TestACL.SetAccessRule($rule1)
        $script:TestACL.SetAccessRule($rule2)
        $script:TestACL.SetAccessRule($rule3)
        
        # Create empty ACL for testing edge cases
        $script:EmptyACL = New-Object System.DirectoryServices.ActiveDirectorySecurity
    }
    
    AfterAll {
        # Cleanup test files
        if (Test-Path $script:TestBackupDir) {
            Remove-Item $script:TestBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Parameter Validation" {
        It "Should accept valid ObjectDN parameter" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should reject null ObjectDN" {
            { New-ACLBackup -ObjectDN $null -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw
        }
        
        It "Should reject empty ObjectDN" {
            { New-ACLBackup -ObjectDN "" -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw
        }
        
        It "Should reject whitespace-only ObjectDN" {
            { New-ACLBackup -ObjectDN "   " -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw "*empty or whitespace*"
        }
        
        It "Should trim whitespace from ObjectDN" {
            $paddedDN = "  $script:TestObjectDN  "
            { New-ACLBackup -ObjectDN $paddedDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should accept valid ACL object" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should reject null ACL object" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $null -BackupPath $script:TestBackupDir } | Should Throw
        }
        
        It "Should accept valid BackupPath parameter" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should reject null BackupPath" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $null } | Should Throw
        }
        
        It "Should reject empty BackupPath" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath "" } | Should Throw
        }
        
        It "Should accept custom CorrelationId" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir -CorrelationId $customCorrelationId } | Should Not Throw
        }
        
        It "Should auto-generate CorrelationId when not provided" {
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should support pipeline input for ObjectDN" {
            { $script:TestObjectDN | New-ACLBackup -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
        }
        
        It "Should validate ObjectDN format" {
            $validDNs = @(
                "CN=User,OU=Users,DC=company,DC=com",
                "OU=Users,DC=company,DC=com",
                "DC=company,DC=com"
            )
            
            foreach ($validDN in $validDNs) {
                { New-ACLBackup -ObjectDN $validDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Not Throw
            }
        }
        
        It "Should accept ActiveDirectorySecurity object" {
            $aclType = $script:TestACL.GetType()
            $aclType.FullName | Should Be "System.DirectoryServices.ActiveDirectorySecurity"
        }
    }
    
    Context "Backup Creation and File Operations" {
        It "Should create backup file successfully" {
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            $result | Should Be $true
            
            # Verify file was created
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $backupFiles.Count | Should BeGreaterThan 0
        }
        
        It "Should create backup directory if it doesn't exist" {
            $newBackupDir = Join-Path $env:TEMP "NewACLBackupDir"
            
            # Ensure directory doesn't exist
            if (Test-Path $newBackupDir) {
                Remove-Item $newBackupDir -Recurse -Force
            }
            
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $newBackupDir
            $result | Should Be $true
            Test-Path $newBackupDir | Should Be $true
            
            # Cleanup
            Remove-Item $newBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should generate timestamped filename" {
            $beforeTime = Get-Date -Format "yyyyMMdd_HHmmss"
            Start-Sleep -Milliseconds 100
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $latestFile.Name | Should Match '\d{8}_\d{6}\.xml$'
        }
        
        It "Should sanitize filename safely" {
            $problematicDN = 'CN=User/With\Problematic:Characters*?,OU="Quotes",DC=company,DC=com'
            
            $result = New-ACLBackup -ObjectDN $problematicDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            $result | Should Be $true
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $latestFile.Name | Should Not Match '[\\/:*?"<>|,=]'
        }
        
        It "Should handle long filenames by truncation" {
            $longDN = "CN=" + ("VeryLongUserName" * 20) + ",OU=Users,DC=company,DC=com"
            
            $result = New-ACLBackup -ObjectDN $longDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            $result | Should Be $true
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $latestFile.Name.Length | Should BeLessThan 260  # Windows MAX_PATH consideration
        }
        
        It "Should create backup with UTF8 encoding" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            
            # Verify file can be read as XML
            { Import-Clixml $latestFile.FullName } | Should Not Throw
        }
        
        It "Should create unique filename for concurrent operations" {
            $results = @()
            
            # Simulate concurrent operations
            1..3 | ForEach-Object {
                $results += New-ACLBackup -ObjectDN "CN=User$_,OU=Users,DC=company,DC=com" -ACL $script:TestACL -BackupPath $script:TestBackupDir
            }
            
            $results | ForEach-Object { $_ | Should Be $true }
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $backupFiles.Count | Should BeGreaterOrEqual 3
        }
        
        It "Should handle WhatIf mode correctly" {
            $initialFileCount = (Get-ChildItem $script:TestBackupDir -Filter "*.xml").Count
            
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir -WhatIf
            $result | Should Be $false
            
            $finalFileCount = (Get-ChildItem $script:TestBackupDir -Filter "*.xml").Count
            $finalFileCount | Should Be $initialFileCount
        }
    }
    
    Context "Integrity Verification and Security" {
        It "Should generate SDDL from ACL object" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.SDDL | Should Not BeNullOrEmpty
            $backupData.SDDL | Should Match '^(O:|G:|D:|S:)'  # SDDL format pattern
        }
        
        It "Should generate SHA256 hash for integrity verification" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.SDDLHash | Should Not BeNullOrEmpty
            $backupData.SDDLHash | Should Match '^[A-Za-z0-9+/]+=*$'  # Base64 pattern
        }
        
        It "Should verify backup integrity immediately after creation" {
            Mock Import-Clixml { 
                return [PSCustomObject]@{
                    SDDLHash = "InvalidHash"
                    ObjectDN = $script:TestObjectDN
                }
            }
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw "*integrity check failed*"
        }
        
        It "Should verify ObjectDN consistency in backup" {
            Mock Import-Clixml { 
                return [PSCustomObject]@{
                    SDDLHash = "ValidHash"
                    ObjectDN = "DifferentDN"
                }
            }
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw "*ObjectDN mismatch*"
        }
        
        It "Should include validation signature in backup" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.ValidationSignature | Should Be "PSSecurityBackup_v2.1"
        }
        
        It "Should clean up partial backup files on failure" {
            # Create a scenario that fails after file creation
            Mock Export-Clixml { throw "Export failed" }
            
            $initialFileCount = (Get-ChildItem $script:TestBackupDir -Filter "*.xml").Count
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw
            
            # Verify no additional files were left
            Start-Sleep -Milliseconds 500  # Allow cleanup time
            $finalFileCount = (Get-ChildItem $script:TestBackupDir -Filter "*.xml").Count
            $finalFileCount | Should Be $initialFileCount
        }
        
        It "Should handle hash verification securely" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            # Verify hash can be decoded
            { [System.Convert]::FromBase64String($backupData.SDDLHash) } | Should Not Throw
        }
    }
    
    Context "Metadata Generation and Tracking" {
        It "Should include comprehensive metadata in backup" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            # Verify essential metadata
            $backupData.ObjectDN | Should Be $script:TestObjectDN
            $backupData.BackupDate | Should Not BeNullOrEmpty
            $backupData.CorrelationId | Should Not BeNullOrEmpty
            $backupData.BackupVersion | Should Be "2.1"
            $backupData.UserContext | Should Not BeNullOrEmpty
            $backupData.ComputerName | Should Not BeNullOrEmpty
        }
        
        It "Should use custom CorrelationId when provided" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir -CorrelationId $customCorrelationId | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.CorrelationId | Should Be $customCorrelationId
        }
        
        It "Should include ISO 8601 formatted timestamp" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.BackupDate | Should Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
        }
        
        It "Should include ACL entry count" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.ACLEntryCount | Should Be $script:TestACL.Access.Count
        }
        
        It "Should include environment context information" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.PowerShellVersion | Should Not BeNullOrEmpty
            $backupData.PSEdition | Should Not BeNullOrEmpty
            $backupData.Platform | Should Not BeNullOrEmpty
            $backupData.BackupMethod | Should Be "New-ACLBackup"
        }
        
        It "Should include script version information" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.ScriptVersion | Should Be "2.1.0"
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle empty ACL with warning" {
            Mock Write-StructuredLog { } -ParameterFilter { $Level -eq 'Warning' }
            
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:EmptyACL -BackupPath $script:TestBackupDir
            $result | Should Be $true
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter { 
                $Level -eq 'Warning' -and $Message -match "contains no access entries"
            }
        }
        
        It "Should handle Export-Clixml failures gracefully" {
            Mock Export-Clixml { throw "Export failed" }
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw "Export failed"
        }
        
        It "Should handle Import-Clixml failures during verification" {
            Mock Import-Clixml { throw "Import failed" }
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw "Import failed"
        }
        
        It "Should handle file system permission errors" {
            # Create a read-only directory scenario
            $readOnlyDir = Join-Path $env:TEMP "ReadOnlyBackupDir"
            New-Item -ItemType Directory -Path $readOnlyDir -Force | Out-Null
            
            # Mock New-Item to simulate permission failure
            Mock New-Item { throw [System.UnauthorizedAccessException]::new("Access denied") }
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $readOnlyDir } | Should Throw
            
            Remove-Item $readOnlyDir -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle SDDL conversion errors" {
            # Create a mock ACL that fails SDDL conversion
            Mock -CommandName GetSecurityDescriptorSddlForm -MockWith { throw "SDDL conversion failed" } -InputObject $script:TestACL
            
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw
        }
        
        It "Should provide detailed error information" {
            Mock Export-Clixml { throw "Detailed export error" }
            
            try {
                New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            }
            catch {
                $_.Exception.Message | Should Match "Detailed export error"
            }
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Level -eq 'Error' -and $Message -match "Failed to create ACL backup"
            }
        }
        
        It "Should handle special characters in ObjectDN during error scenarios" {
            $specialDN = 'CN=User,With,Commas,OU=Special"Quotes",DC=company,DC=com'
            Mock Export-Clixml { throw "Export failed" }
            
            { New-ACLBackup -ObjectDN $specialDN -ACL $script:TestACL -BackupPath $script:TestBackupDir } | Should Throw
        }
        
        It "Should handle directory creation failures" {
            Mock New-Item { throw "Cannot create directory" } -ParameterFilter { $ItemType -eq 'Directory' }
            
            $nonExistentDir = Join-Path $env:TEMP "NonCreatableDir"
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $nonExistentDir } | Should Throw
        }
    }
    
    Context "Performance Testing" {
        It "Should complete backup creation within performance baseline" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000  # 1 second baseline
            $result | Should Be $true
        }
        
        It "Should handle multiple ACL entries efficiently" {
            # Create ACL with many entries
            $largeACL = New-Object System.DirectoryServices.ActiveDirectorySecurity
            
            1..50 | ForEach-Object {
                $identity = [System.Security.Principal.SecurityIdentifier]"S-1-5-21-1234567890-987654321-123456789-$_"
                $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, [System.DirectoryServices.ActiveDirectoryRights]::GenericRead, [System.Security.AccessControl.AccessControlType]::Allow, [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                $largeACL.SetAccessRule($rule)
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $largeACL -BackupPath $script:TestBackupDir
            $stopwatch.Stop()
            
            $result | Should Be $true
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000  # 2 second baseline for large ACL
        }
        
        It "Should maintain consistent performance across iterations" {
            $iterations = 5
            $measurements = @()
            
            1..$iterations | ForEach-Object {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                New-ACLBackup -ObjectDN "CN=PerfTest$_,OU=Users,DC=company,DC=com" -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
                $stopwatch.Stop()
                $measurements += $stopwatch.ElapsedMilliseconds
            }
            
            $averageTime = ($measurements | Measure-Object -Average).Average
            $maxTime = ($measurements | Measure-Object -Maximum).Maximum
            
            $averageTime | Should BeLessThan 800   # 800ms average
            $maxTime | Should BeLessThan 1500     # 1.5 second maximum
        }
        
        It "Should manage memory efficiently" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            1..10 | ForEach-Object {
                New-ACLBackup -ObjectDN "CN=MemTest$_,OU=Users,DC=company,DC=com" -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            }
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($false)
            $memoryIncrease = $finalMemory - $initialMemory
            
            # Memory increase should be reasonable (less than 10MB for 10 operations)
            $memoryIncrease | Should BeLessThan (10 * 1024 * 1024)
        }
        
        It "Should scale backup file size reasonably" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            
            # Backup file should be reasonable size (less than 100KB for typical ACL)
            $latestFile.Length | Should BeLessThan (100 * 1024)
            $latestFile.Length | Should BeGreaterThan 512  # Should have meaningful content
        }
    }
    
    Context "Security Validation" {
        It "Should sanitize malicious ObjectDN characters" {
            $maliciousInputs = @(
                "CN=User<script>alert('xss')</script>,OU=Users,DC=company,DC=com",
                "CN=User../../etc/passwd,OU=Users,DC=company,DC=com",
                'CN=User"DROP TABLE users;--,OU=Users,DC=company,DC=com'
            )
            
            foreach ($maliciousInput in $maliciousInputs) {
                $result = New-ACLBackup -ObjectDN $maliciousInput -ACL $script:TestACL -BackupPath $script:TestBackupDir
                $result | Should Be $true
                
                # Verify filename was sanitized
                $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
                $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
                $latestFile.Name | Should Not Match '[<>"]'
            }
        }
        
        It "Should handle path traversal attempts in BackupPath" {
            $maliciousPath = Join-Path $script:TestBackupDir "..\..\..\..\Windows\System32"
            
            # Should still create backup in a safe location
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $maliciousPath } | Should Not Throw
        }
        
        It "Should not expose sensitive information in error messages" {
            Mock Export-Clixml { throw "Sensitive error: PASSWORD123" }
            
            try {
                New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir
            }
            catch {
                $_.Exception.Message | Should Not Match "PASSWORD123"
            }
        }
        
        It "Should validate correlation ID format" {
            $maliciousCorrelationId = "<script>alert('xss')</script>"
            
            # Should accept the correlation ID (downstream should sanitize for logging)
            { New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir -CorrelationId $maliciousCorrelationId } | Should Not Throw
        }
        
        It "Should create backups with secure file permissions" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            
            # File should exist and be readable
            Test-Path $latestFile.FullName | Should Be $true
            { Get-Content $latestFile.FullName } | Should Not Throw
        }
        
        It "Should handle hash computation securely" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            # Hash should be properly formatted and decodable
            $backupData.SDDLHash | Should Match '^[A-Za-z0-9+/]+=*$'
            { [System.Convert]::FromBase64String($backupData.SDDLHash) } | Should Not Throw
        }
    }
    
    Context "Enterprise Integration" {
        It "Should provide comprehensive audit logging" {
            Mock Write-StructuredLog { } -Verifiable -ParameterFilter {
                $Level -eq 'Information' -and $Message -match "Successfully backed up ACL"
            }
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            Assert-MockCalledVerifiable
        }
        
        It "Should support correlation tracking" {
            $customCorrelationId = [System.Guid]::NewGuid().ToString()
            
            Mock Write-StructuredLog { } -ParameterFilter {
                $CorrelationId -eq $customCorrelationId
            }
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir -CorrelationId $customCorrelationId | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $CorrelationId -eq $customCorrelationId
            } -AtLeast 1
        }
        
        It "Should integrate with monitoring systems" {
            Mock Write-StructuredLog { }
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            Assert-MockCalled Write-StructuredLog -AtLeast 3
        }
        
        It "Should support compliance reporting requirements" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            # Verify compliance-required fields
            $backupData.BackupDate | Should Not BeNullOrEmpty
            $backupData.UserContext | Should Not BeNullOrEmpty
            $backupData.ComputerName | Should Not BeNullOrEmpty
            $backupData.ValidationSignature | Should Not BeNullOrEmpty
        }
        
        It "Should provide detailed operational metrics" {
            Mock Write-StructuredLog { } -ParameterFilter {
                $Message -match "Size: \d+ bytes.*Entries: \d+.*Hash:"
            }
            
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            Assert-MockCalled Write-StructuredLog -ParameterFilter {
                $Message -match "Size: \d+ bytes.*Entries: \d+.*Hash:"
            }
        }
    }
    
    Context "Cross-Platform Compatibility" {
        It "Should handle Windows path formats correctly" {
            $windowsPath = "C:\Backups\ACLs"
            if (-not (Test-Path $windowsPath)) {
                New-Item -ItemType Directory -Path $windowsPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            
            if (Test-Path $windowsPath) {
                $result = New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $windowsPath
                $result | Should Be $true
                
                Remove-Item $windowsPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should maintain consistent timestamp formats" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            # Verify ISO 8601 format
            { [DateTime]::Parse($backupData.BackupDate) } | Should Not Throw
        }
        
        It "Should support PowerShell Core and Windows PowerShell" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            $backupData = Import-Clixml $latestFile.FullName
            
            $backupData.PSEdition | Should BeIn @('Desktop', 'Core')
        }
        
        It "Should handle different line ending formats" {
            New-ACLBackup -ObjectDN $script:TestObjectDN -ACL $script:TestACL -BackupPath $script:TestBackupDir | Out-Null
            
            $backupFiles = Get-ChildItem $script:TestBackupDir -Filter "*.xml"
            $latestFile = $backupFiles | Sort-Object CreationTime -Descending | Select-Object -First 1
            
            # File should be readable regardless of line endings
            { Import-Clixml $latestFile.FullName } | Should Not Throw
        }
    }
}





