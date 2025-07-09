#Requires -Module Pester

# Import test bootstrapper first
$testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
if (Test-Path $testBootstrapper) {
. $testBootstrapper
}
# Import Backup module functions for testing
$BackupModulePath = Join-Path $PSScriptRoot '..\..\Private\Backup'
Get-ChildItem -Path $BackupModulePath -Filter '*.ps1' | ForEach-Object {
. #Requires -Module Pester


    # Import test bootstrapper first
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
    }

    # Import Backup module functions for testing
    $BackupModulePath = Join-Path $PSScriptRoot '..\..\Private\Backup'
    Get-ChildItem -Path $BackupModulePath -Filter '*.ps1' | ForEach-Object {
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

    # Mock file system operations
    Mock Test-Path { return $true }
    Mock Get-Item { return @{ FullName = 'MockPath'; LastWriteTime = (Get-Date) } }
    Mock Get-ChildItem { return @() }
    Mock New-Item { return @{ FullName = 'MockPath' } }
    Mock Copy-Item { }
    Mock Remove-Item { }
    Mock Out-File { }
    Mock Get-Content { return @() }

    # Mock ACL operations
    Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
    Mock Set-Acl { }

    # Mock logging function
    Mock Write-StructuredLog { }

    # Mock compression operations
    Mock Compress-Archive { }
    Mock Expand-Archive { }

Describe "Find-BackupFile" -Tag "Unit", "Backup", "Discovery" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupPath = Join-Path $TestDrive 'backups'
        $script:TestObjectDN = "CN=TestUser,OU=Users,DC=contoso,DC=com"
    }

    Context "Parameter Validation" {
        It "Should require BackupPath parameter" {
            { Find-BackupFile } | Should Throw "*BackupPath*"
        }

        It "Should require ObjectDistinguishedName parameter" {
            { Find-BackupFile -BackupPath $script:TestBackupPath } | Should Throw "*ObjectDistinguishedName*"
        }

        It "Should accept valid parameters" {
            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Not Throw
        }

        It "Should validate backup path exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupPath }

            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*BackupPath*"
        }

        It "Should accept correlation ID parameter" {
            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should find existing backup files" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.json"; FullName = "C:\backups\file2.json"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockFiles } -ParameterFilter { $Path -eq $script:TestBackupPath }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should -HaveCount 2
            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }

        It "Should return empty array when no backups found" {
            Mock Get-ChildItem { return @() }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should BeNullOrEmpty
        }

        It "Should filter files by distinguished name pattern" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_OtherUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file2.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "unrelated_file.txt"; FullName = "C:\backups\file3.txt"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockFiles }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }

        It "Should sort results by creation time descending" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date).AddDays(-2) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250103_120000.xml"; FullName = "C:\backups\file2.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.xml"; FullName = "C:\backups\file3.xml"; LastWriteTime = (Get-Date).AddDays(-1) }
            )
            Mock Get-ChildItem { return $mockFiles }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250103_120000.xml"
            $result[1].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.xml"
            $result[2].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }
    }

    Context "Error Handling" {
        It "Should handle file system access errors" {
            Mock Get-ChildItem { throw "Access is denied" }

            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*Access is denied*"
        }

        It "Should handle network path unavailability" {
            Mock Test-Path { throw "The network path was not found" }

            { Find-BackupFile -BackupPath "\\server\share\backups" -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*network path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large backup directories efficiently" {
            $largeFileSet = 1..1000 | ForEach-Object {
                @{ Name = "backup_file_$_.xml"; FullName = "C:\backups\backup_file_$_.xml"; LastWriteTime = (Get-Date) }
            }
            Mock Get-ChildItem { return $largeFileSet }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }
    }

    Context "Audit and Compliance" {
        It "Should log backup search operations" {
            Mock Write-StructuredLog { }

            Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*backup search*" }
        }
    }

Describe "Get-BackupMetadata" -Tag "Unit", "Backup", "Metadata" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Get-BackupMetadata } | Should Throw "*BackupFilePath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupFile }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*BackupFilePath*"
        }

        It "Should accept valid file path" {
            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should extract metadata from XML backup files" {
            $mockXmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=TestUser,OU=Users,DC=contoso,DC=com</ObjectDN>
        <BackupDate>2025-01-01T12:00:00Z</BackupDate>
        <BackupType>ACL</BackupType>
        <Version>1.0</Version>
    </Metadata>
    <Data>
        <!-- ACL Data -->
    </Data>
</Backup>
"@
            Mock Get-Content { return $mockXmlContent }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=contoso,DC=com"
            $result.BackupType | Should Be "ACL"
        }

        It "Should extract metadata from JSON backup files" {
            $mockJsonContent = @"
{
    "Metadata": {
        "ObjectDN": "CN=TestUser,OU=Users,DC=contoso,DC=com",
        "BackupDate": "2025-01-01T12:00:00Z",
        "BackupType": "ACL",
        "Version": "1.0"
    },
    "Data": {}
}
"@
            Mock Get-Content { return $mockJsonContent }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=contoso,DC=com"
            $result.BackupType | Should Be "ACL"
        }

        It "Should handle missing metadata gracefully" {
            Mock Get-Content { return "<Backup><Data></Data></Backup>" }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle corrupted XML files" {
            Mock Get-Content { return "Invalid XML content" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*XML*"
        }

        It "Should handle corrupted JSON files" {
            Mock Get-Content { return "{ invalid json }" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*JSON*"
        }

        It "Should handle file access errors" {
            Mock Get-Content { throw "The process cannot access the file" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*access*"
        }
    }

    Context "Audit and Compliance" {
        It "Should log metadata extraction operations" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup></Backup>" }

            Get-BackupMetadata -BackupFilePath $script:TestBackupFile -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }
    }

Describe "New-ACLBackup" -Tag "Unit", "Backup", "ACL" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestObjectPath = "CN=TestUser,OU=Users,DC=contoso,DC=com"
        $script:TestBackupPath = Join-Path $TestDrive 'backups'
    }

    Context "Parameter Validation" {
        It "Should require ObjectPath parameter" {
            { New-ACLBackup } | Should Throw "*ObjectPath*"
        }

        It "Should require BackupPath parameter" {
            { New-ACLBackup -ObjectPath $script:TestObjectPath } | Should Throw "*BackupPath*"
        }

        It "Should accept valid parameters" {
            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Not Throw
        }

        It "Should validate backup directory exists or can be created" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupPath }
            Mock New-Item { return @{ FullName = $script:TestBackupPath } }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Not Throw

            Should Invoke New-Item -Exactly 1 -Scope It
        }
    }

    Context "Core Functionality" {
        It "Should create ACL backup successfully" {
            $mockAcl = @{
                Owner = 'BUILTIN\Administrators'
                Access = @(
                    @{ IdentityReference = 'DOMAIN\User1'; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                )
            }
            Mock Get-Acl { return $mockAcl }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
            $result.BackupFilePath | Should Match "\.xml$"
            Should Invoke Get-Acl -Exactly 1 -Scope It
            Should Invoke Out-File -Exactly 1 -Scope It
        }

        It "Should generate unique backup filenames" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result1 = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath
            Start-Sleep -Milliseconds 100
            $result2 = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result1.BackupFilePath | Should Not Be $result2.BackupFilePath
        }

        It "Should include metadata in backup" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result.Metadata | Should Not BeNullOrEmpty
            $result.Metadata.ObjectPath | Should Be $script:TestObjectPath
            $result.Metadata.BackupType | Should Be "ACL"
        }

        It "Should handle empty ACLs" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
            Should Invoke Out-File -Exactly 1 -Scope It
        }
    }

    Context "Error Handling" {
        It "Should handle ACL access denied errors" {
            Mock Get-Acl { throw "Access is denied" }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Throw "*Access is denied*"
        }

        It "Should handle backup file write errors" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { throw "Disk full" }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Throw "*Disk full*"
        }

        It "Should handle invalid object paths" {
            Mock Get-Acl { throw "Cannot find path" }

            { New-ACLBackup -ObjectPath "InvalidPath" -BackupPath $script:TestBackupPath } | Should Throw "*Cannot find path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete backup within acceptable time" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle large ACLs efficiently" {
            $largeAcl = @{
                Owner = 'Test'
                Access = 1..100 | ForEach-Object {
                    @{ IdentityReference = "DOMAIN\User$_"; FileSystemRights = 'Read'; AccessControlType = 'Allow' }
                }
            }
            Mock Get-Acl { return $largeAcl }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
        }
    }

    Context "Audit and Compliance" {
        It "Should log backup creation with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*backup created*" }
        }

        It "Should include security context in audit logs" {
            Mock Write-StructuredLog { }
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" }
        }
    }

Describe "Test-BackupIntegrity" -Tag "Unit", "Backup", "Integrity" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Test-BackupIntegrity } | Should Throw "*BackupFilePath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false }

            { Test-BackupIntegrity -BackupFilePath $script:TestBackupFile } | Should Throw "*BackupFilePath*"
        }

        It "Should accept valid file path" {
            { Test-BackupIntegrity -BackupFilePath $script:TestBackupFile } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should validate XML backup file structure" {
            $validXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN>
        <BackupDate>2025-01-01T12:00:00Z</BackupDate>
    </Metadata>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $validXml }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $true
            $result.ValidationErrors | Should BeNullOrEmpty
        }

        It "Should detect corrupted XML files" {
            Mock Get-Content { return "Invalid XML content" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Not BeNullOrEmpty
        }

        It "Should validate JSON backup file structure" {
            $validJson = @"
{
    "Metadata": {
        "ObjectDN": "CN=Test,DC=contoso,DC=com",
        "BackupDate": "2025-01-01T12:00:00Z"
    },
    "Data": {}
}
"@
            Mock Get-Content { return $validJson }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $true
        }

        It "Should verify required metadata fields" {
            $incompleteXml = @"
<?xml version="1.0"?>
<Backup>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $incompleteXml }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*Metadata*"
        }

        It "Should validate checksum if present" {
            $xmlWithChecksum = @"
<?xml version="1.0"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN>
        <Checksum>ABC123</Checksum>
    </Metadata>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $xmlWithChecksum }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.ChecksumValid | Should Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle file access errors gracefully" {
            Mock Get-Content { throw "File is locked" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*File is locked*"
        }

        It "Should handle zero-byte files" {
            Mock Get-Content { return "" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*empty*"
        }
    }

    Context "Performance" {
        It "Should validate large backup files efficiently" {
            $largeXmlContent = "<?xml version='1.0'?><Backup><Metadata><ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN></Metadata><Data>" + ("x" * 10000) + "</Data></Backup>"
            Mock Get-Content { return $largeXmlContent }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.IsValid | Should Be $true
        }
    }

    Context "Audit and Compliance" {
        It "Should log integrity check results" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<?xml version='1.0'?><Backup></Backup>" }

            Test-BackupIntegrity -BackupFilePath $script:TestBackupFile -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*integrity*" }
        }
    }

Describe "Invoke-RestoreWorkflow" -Tag "Unit", "Backup", "Restore" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
        $script:TestTargetPath = "CN=TestUser,OU=Users,DC=contoso,DC=com"
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Invoke-RestoreWorkflow } | Should Throw "*BackupFilePath*"
        }

        It "Should require TargetPath parameter" {
            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile } | Should Throw "*TargetPath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupFile }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*BackupFilePath*"
        }

        It "Should accept WhatIf parameter" {
            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -WhatIf } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should perform restore operation successfully" {
            $mockBackupContent = @"
<?xml version="1.0"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=TestUser,OU=Users,DC=contoso,DC=com</ObjectDN>
        <BackupType>ACL</BackupType>
    </Metadata>
    <Data>
        <ACL>
            <Owner>BUILTIN\Administrators</Owner>
            <Access>
                <Entry>
                    <Identity>DOMAIN\User1</Identity>
                    <Rights>FullControl</Rights>
                </Entry>
            </Access>
        </ACL>
    </Data>
</Backup>
"@
            Mock Get-Content { return $mockBackupContent }
            Mock Set-Acl { }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath

            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            Should Invoke Set-Acl -Exactly 1 -Scope It
        }

        It "Should validate backup integrity before restore" {
            Mock Test-BackupIntegrity { return @{ IsValid = $false; ValidationErrors = @("Corruption detected") } }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*Corruption detected*"

            Should Invoke Test-BackupIntegrity -Exactly 1 -Scope It
        }

        It "Should support WhatIf parameter" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Set-Acl { }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -WhatIf

            $result.WhatIfPreview | Should Not BeNullOrEmpty
            Should Invoke Set-Acl -Exactly 0 -Scope It  # Should not actually apply changes
        }

        It "Should create restore point before operation" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock New-ACLBackup { return @{ BackupFilePath = "restore_point.xml" } }
            Mock Set-Acl { }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CreateRestorePoint

            Should Invoke New-ACLBackup -Exactly 1 -Scope It
            $result.RestorePointPath | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle backup file corruption" {
            Mock Test-BackupIntegrity { return @{ IsValid = $false; ValidationErrors = @("File corrupted") } }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*File corrupted*"
        }

        It "Should handle restore operation failures" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { throw "Access denied" }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*Access denied*"
        }

        It "Should rollback on failure when restore point exists" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock New-ACLBackup { return @{ BackupFilePath = "restore_point.xml" } }
            Mock Set-Acl { throw "Operation failed" } -ParameterFilter { $Path -eq $script:TestTargetPath }
            Mock Set-Acl { } -ParameterFilter { $Path -ne $script:TestTargetPath }  # Allow rollback

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CreateRestorePoint } | Should Throw "*Operation failed*"

            Should Invoke Set-Acl -Times 2 -Scope It  # Original attempt + rollback
        }
    }

    Context "Performance and Scalability" {
        It "Should complete restore within acceptable time" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }
    }

    Context "Audit and Compliance" {
        It "Should log restore operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*restore*" }
        }

        It "Should log security context and user information" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" -and $Message -like "*restore*" }
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
# Mock file system operations
Mock Test-Path { return $true }
Mock Get-Item { return @{ FullName = 'MockPath'; LastWriteTime = (Get-Date) } }
Mock Get-ChildItem { return @() }
Mock New-Item { return @{ FullName = 'MockPath' } }
Mock Copy-Item { }
Mock Remove-Item { }
Mock Out-File { }
Mock Get-Content { return @() }
# Mock ACL operations
Mock Get-Acl { return @{ Access = @(); Owner = 'BUILTIN\Administrators' } }
Mock Set-Acl { }
# Mock logging function
Mock Write-StructuredLog { }
# Mock compression operations
Mock Compress-Archive { }
Mock Expand-Archive { }

Describe "Find-BackupFile" -Tag "Unit", "Backup", "Discovery" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupPath = Join-Path $TestDrive 'backups'
        $script:TestObjectDN = "CN=TestUser,OU=Users,DC=contoso,DC=com"
    }

    Context "Parameter Validation" {
        It "Should require BackupPath parameter" {
            { Find-BackupFile } | Should Throw "*BackupPath*"
        }

        It "Should require ObjectDistinguishedName parameter" {
            { Find-BackupFile -BackupPath $script:TestBackupPath } | Should Throw "*ObjectDistinguishedName*"
        }

        It "Should accept valid parameters" {
            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Not Throw
        }

        It "Should validate backup path exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupPath }

            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*BackupPath*"
        }

        It "Should accept correlation ID parameter" {
            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should find existing backup files" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.json"; FullName = "C:\backups\file2.json"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockFiles } -ParameterFilter { $Path -eq $script:TestBackupPath }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should -HaveCount 2
            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }

        It "Should return empty array when no backups found" {
            Mock Get-ChildItem { return @() }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should BeNullOrEmpty
        }

        It "Should filter files by distinguished name pattern" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_OtherUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file2.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "unrelated_file.txt"; FullName = "C:\backups\file3.txt"; LastWriteTime = (Get-Date) }
            )
            Mock Get-ChildItem { return $mockFiles }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result | Should -HaveCount 1
            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }

        It "Should sort results by creation time descending" {
            $mockFiles = @(
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"; FullName = "C:\backups\file1.xml"; LastWriteTime = (Get-Date).AddDays(-2) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250103_120000.xml"; FullName = "C:\backups\file2.xml"; LastWriteTime = (Get-Date) },
                @{ Name = "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.xml"; FullName = "C:\backups\file3.xml"; LastWriteTime = (Get-Date).AddDays(-1) }
            )
            Mock Get-ChildItem { return $mockFiles }

            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN

            $result[0].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250103_120000.xml"
            $result[1].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250102_120000.xml"
            $result[2].Name | Should Be "CN_TestUser_CN_Users_DC_contoso_DC_com_20250101_120000.xml"
        }
    }

    Context "Error Handling" {
        It "Should handle file system access errors" {
            Mock Get-ChildItem { throw "Access is denied" }

            { Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*Access is denied*"
        }

        It "Should handle network path unavailability" {
            Mock Test-Path { throw "The network path was not found" }

            { Find-BackupFile -BackupPath "\\server\share\backups" -ObjectDistinguishedName $script:TestObjectDN } | Should Throw "*network path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should handle large backup directories efficiently" {
            $largeFileSet = 1..1000 | ForEach-Object {
                @{ Name = "backup_file_$_.xml"; FullName = "C:\backups\backup_file_$_.xml"; LastWriteTime = (Get-Date) }
            }
            Mock Get-ChildItem { return $largeFileSet }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }
    }

    Context "Audit and Compliance" {
        It "Should log backup search operations" {
            Mock Write-StructuredLog { }

            Find-BackupFile -BackupPath $script:TestBackupPath -ObjectDistinguishedName $script:TestObjectDN -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*backup search*" }
        }
    }

Describe "Get-BackupMetadata" -Tag "Unit", "Backup", "Metadata" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Get-BackupMetadata } | Should Throw "*BackupFilePath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupFile }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*BackupFilePath*"
        }

        It "Should accept valid file path" {
            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should extract metadata from XML backup files" {
            $mockXmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=TestUser,OU=Users,DC=contoso,DC=com</ObjectDN>
        <BackupDate>2025-01-01T12:00:00Z</BackupDate>
        <BackupType>ACL</BackupType>
        <Version>1.0</Version>
    </Metadata>
    <Data>
        <!-- ACL Data -->
    </Data>
</Backup>
"@
            Mock Get-Content { return $mockXmlContent }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=contoso,DC=com"
            $result.BackupType | Should Be "ACL"
        }

        It "Should extract metadata from JSON backup files" {
            $mockJsonContent = @"
{
    "Metadata": {
        "ObjectDN": "CN=TestUser,OU=Users,DC=contoso,DC=com",
        "BackupDate": "2025-01-01T12:00:00Z",
        "BackupType": "ACL",
        "Version": "1.0"
    },
    "Data": {}
}
"@
            Mock Get-Content { return $mockJsonContent }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should Be "CN=TestUser,OU=Users,DC=contoso,DC=com"
            $result.BackupType | Should Be "ACL"
        }

        It "Should handle missing metadata gracefully" {
            Mock Get-Content { return "<Backup><Data></Data></Backup>" }

            $result = Get-BackupMetadata -BackupFilePath $script:TestBackupFile

            $result | Should Not BeNullOrEmpty
            $result.ObjectDN | Should BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle corrupted XML files" {
            Mock Get-Content { return "Invalid XML content" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*XML*"
        }

        It "Should handle corrupted JSON files" {
            Mock Get-Content { return "{ invalid json }" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*JSON*"
        }

        It "Should handle file access errors" {
            Mock Get-Content { throw "The process cannot access the file" }

            { Get-BackupMetadata -BackupFilePath $script:TestBackupFile } | Should Throw "*access*"
        }
    }

    Context "Audit and Compliance" {
        It "Should log metadata extraction operations" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup></Backup>" }

            Get-BackupMetadata -BackupFilePath $script:TestBackupFile -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId }
        }
    }

Describe "New-ACLBackup" -Tag "Unit", "Backup", "ACL" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestObjectPath = "CN=TestUser,OU=Users,DC=contoso,DC=com"
        $script:TestBackupPath = Join-Path $TestDrive 'backups'
    }

    Context "Parameter Validation" {
        It "Should require ObjectPath parameter" {
            { New-ACLBackup } | Should Throw "*ObjectPath*"
        }

        It "Should require BackupPath parameter" {
            { New-ACLBackup -ObjectPath $script:TestObjectPath } | Should Throw "*BackupPath*"
        }

        It "Should accept valid parameters" {
            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Not Throw
        }

        It "Should validate backup directory exists or can be created" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupPath }
            Mock New-Item { return @{ FullName = $script:TestBackupPath } }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Not Throw

            Should Invoke New-Item -Exactly 1 -Scope It
        }
    }

    Context "Core Functionality" {
        It "Should create ACL backup successfully" {
            $mockAcl = @{
                Owner = 'BUILTIN\Administrators'
                Access = @(
                    @{ IdentityReference = 'DOMAIN\User1'; FileSystemRights = 'FullControl'; AccessControlType = 'Allow' }
                )
            }
            Mock Get-Acl { return $mockAcl }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
            $result.BackupFilePath | Should Match "\.xml$"
            Should Invoke Get-Acl -Exactly 1 -Scope It
            Should Invoke Out-File -Exactly 1 -Scope It
        }

        It "Should generate unique backup filenames" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result1 = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath
            Start-Sleep -Milliseconds 100
            $result2 = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result1.BackupFilePath | Should Not Be $result2.BackupFilePath
        }

        It "Should include metadata in backup" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result.Metadata | Should Not BeNullOrEmpty
            $result.Metadata.ObjectPath | Should Be $script:TestObjectPath
            $result.Metadata.BackupType | Should Be "ACL"
        }

        It "Should handle empty ACLs" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
            Should Invoke Out-File -Exactly 1 -Scope It
        }
    }

    Context "Error Handling" {
        It "Should handle ACL access denied errors" {
            Mock Get-Acl { throw "Access is denied" }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Throw "*Access is denied*"
        }

        It "Should handle backup file write errors" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { throw "Disk full" }

            { New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath } | Should Throw "*Disk full*"
        }

        It "Should handle invalid object paths" {
            Mock Get-Acl { throw "Cannot find path" }

            { New-ACLBackup -ObjectPath "InvalidPath" -BackupPath $script:TestBackupPath } | Should Throw "*Cannot find path*"
        }
    }

    Context "Performance and Scalability" {
        It "Should complete backup within acceptable time" {
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000
        }

        It "Should handle large ACLs efficiently" {
            $largeAcl = @{
                Owner = 'Test'
                Access = 1..100 | ForEach-Object {
                    @{ IdentityReference = "DOMAIN\User$_"; FileSystemRights = 'Read'; AccessControlType = 'Allow' }
                }
            }
            Mock Get-Acl { return $largeAcl }
            Mock Out-File { }

            $result = New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            $result | Should Not BeNullOrEmpty
        }
    }

    Context "Audit and Compliance" {
        It "Should log backup creation with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*backup created*" }
        }

        It "Should include security context in audit logs" {
            Mock Write-StructuredLog { }
            Mock Get-Acl { return @{ Owner = 'Test'; Access = @() } }
            Mock Out-File { }

            New-ACLBackup -ObjectPath $script:TestObjectPath -BackupPath $script:TestBackupPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" }
        }
    }

Describe "Test-BackupIntegrity" -Tag "Unit", "Backup", "Integrity" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Test-BackupIntegrity } | Should Throw "*BackupFilePath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false }

            { Test-BackupIntegrity -BackupFilePath $script:TestBackupFile } | Should Throw "*BackupFilePath*"
        }

        It "Should accept valid file path" {
            { Test-BackupIntegrity -BackupFilePath $script:TestBackupFile } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should validate XML backup file structure" {
            $validXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN>
        <BackupDate>2025-01-01T12:00:00Z</BackupDate>
    </Metadata>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $validXml }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $true
            $result.ValidationErrors | Should BeNullOrEmpty
        }

        It "Should detect corrupted XML files" {
            Mock Get-Content { return "Invalid XML content" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Not BeNullOrEmpty
        }

        It "Should validate JSON backup file structure" {
            $validJson = @"
{
    "Metadata": {
        "ObjectDN": "CN=Test,DC=contoso,DC=com",
        "BackupDate": "2025-01-01T12:00:00Z"
    },
    "Data": {}
}
"@
            Mock Get-Content { return $validJson }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $true
        }

        It "Should verify required metadata fields" {
            $incompleteXml = @"
<?xml version="1.0"?>
<Backup>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $incompleteXml }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*Metadata*"
        }

        It "Should validate checksum if present" {
            $xmlWithChecksum = @"
<?xml version="1.0"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN>
        <Checksum>ABC123</Checksum>
    </Metadata>
    <Data></Data>
</Backup>
"@
            Mock Get-Content { return $xmlWithChecksum }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.ChecksumValid | Should Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle file access errors gracefully" {
            Mock Get-Content { throw "File is locked" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*File is locked*"
        }

        It "Should handle zero-byte files" {
            Mock Get-Content { return "" }

            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile

            $result.IsValid | Should Be $false
            $result.ValidationErrors | Should Contain "*empty*"
        }
    }

    Context "Performance" {
        It "Should validate large backup files efficiently" {
            $largeXmlContent = "<?xml version='1.0'?><Backup><Metadata><ObjectDN>CN=Test,DC=contoso,DC=com</ObjectDN></Metadata><Data>" + ("x" * 10000) + "</Data></Backup>"
            Mock Get-Content { return $largeXmlContent }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Test-BackupIntegrity -BackupFilePath $script:TestBackupFile
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
            $result.IsValid | Should Be $true
        }
    }

    Context "Audit and Compliance" {
        It "Should log integrity check results" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<?xml version='1.0'?><Backup></Backup>" }

            Test-BackupIntegrity -BackupFilePath $script:TestBackupFile -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*integrity*" }
        }
    }

Describe "Invoke-RestoreWorkflow" -Tag "Unit", "Backup", "Restore" {

    BeforeEach {
        $script:TestCorrelationId = [System.Guid]::NewGuid().ToString()
        $script:TestBackupFile = Join-Path $TestDrive 'backup.xml'
        $script:TestTargetPath = "CN=TestUser,OU=Users,DC=contoso,DC=com"
    }

    Context "Parameter Validation" {
        It "Should require BackupFilePath parameter" {
            { Invoke-RestoreWorkflow } | Should Throw "*BackupFilePath*"
        }

        It "Should require TargetPath parameter" {
            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile } | Should Throw "*TargetPath*"
        }

        It "Should validate backup file exists" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $script:TestBackupFile }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*BackupFilePath*"
        }

        It "Should accept WhatIf parameter" {
            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -WhatIf } | Should Not Throw
        }
    }

    Context "Core Functionality" {
        It "Should perform restore operation successfully" {
            $mockBackupContent = @"
<?xml version="1.0"?>
<Backup>
    <Metadata>
        <ObjectDN>CN=TestUser,OU=Users,DC=contoso,DC=com</ObjectDN>
        <BackupType>ACL</BackupType>
    </Metadata>
    <Data>
        <ACL>
            <Owner>BUILTIN\Administrators</Owner>
            <Access>
                <Entry>
                    <Identity>DOMAIN\User1</Identity>
                    <Rights>FullControl</Rights>
                </Entry>
            </Access>
        </ACL>
    </Data>
</Backup>
"@
            Mock Get-Content { return $mockBackupContent }
            Mock Set-Acl { }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath

            $result | Should Not BeNullOrEmpty
            $result.Success | Should Be $true
            Should Invoke Set-Acl -Exactly 1 -Scope It
        }

        It "Should validate backup integrity before restore" {
            Mock Test-BackupIntegrity { return @{ IsValid = $false; ValidationErrors = @("Corruption detected") } }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*Corruption detected*"

            Should Invoke Test-BackupIntegrity -Exactly 1 -Scope It
        }

        It "Should support WhatIf parameter" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Set-Acl { }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -WhatIf

            $result.WhatIfPreview | Should Not BeNullOrEmpty
            Should Invoke Set-Acl -Exactly 0 -Scope It  # Should not actually apply changes
        }

        It "Should create restore point before operation" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock New-ACLBackup { return @{ BackupFilePath = "restore_point.xml" } }
            Mock Set-Acl { }

            $result = Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CreateRestorePoint

            Should Invoke New-ACLBackup -Exactly 1 -Scope It
            $result.RestorePointPath | Should Not BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle backup file corruption" {
            Mock Test-BackupIntegrity { return @{ IsValid = $false; ValidationErrors = @("File corrupted") } }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*File corrupted*"
        }

        It "Should handle restore operation failures" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { throw "Access denied" }

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath } | Should Throw "*Access denied*"
        }

        It "Should rollback on failure when restore point exists" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock New-ACLBackup { return @{ BackupFilePath = "restore_point.xml" } }
            Mock Set-Acl { throw "Operation failed" } -ParameterFilter { $Path -eq $script:TestTargetPath }
            Mock Set-Acl { } -ParameterFilter { $Path -ne $script:TestTargetPath }  # Allow rollback

            { Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CreateRestorePoint } | Should Throw "*Operation failed*"

            Should Invoke Set-Acl -Times 2 -Scope It  # Original attempt + rollback
        }
    }

    Context "Performance and Scalability" {
        It "Should complete restore within acceptable time" {
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000
        }
    }

    Context "Audit and Compliance" {
        It "Should log restore operations with correlation ID" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath -CorrelationId $script:TestCorrelationId

            Should Invoke Write-StructuredLog -ParameterFilter { $CorrelationId -eq $script:TestCorrelationId -and $Message -like "*restore*" }
        }

        It "Should log security context and user information" {
            Mock Write-StructuredLog { }
            Mock Get-Content { return "<Backup><Metadata><BackupType>ACL</BackupType></Metadata><Data></Data></Backup>" }
            Mock Test-BackupIntegrity { return @{ IsValid = $true; ValidationErrors = @() } }
            Mock Set-Acl { }

            Invoke-RestoreWorkflow -BackupFilePath $script:TestBackupFile -TargetPath $script:TestTargetPath

            Should Invoke Write-StructuredLog -ParameterFilter { $Message -like "*$env:USERNAME*" -and $Message -like "*restore*" }
        }
    }
}






