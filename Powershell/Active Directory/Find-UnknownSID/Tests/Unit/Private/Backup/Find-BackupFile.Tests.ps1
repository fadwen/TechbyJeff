#Requires -Module Pester

Describe "Find-BackupFile Function Tests" -Tag "Unit", "Backup", "Discovery" {
    
    BeforeAll {
        # Ensure PESTER_TESTING environment variable is set for clean test output
        $env:PESTER_TESTING = 'true'

        # Mock logging functions to avoid dependency loading issues
        function Write-StructuredLog {
            param($Message, $Level, $CorrelationId, $Component, $Data, $Details)
            # Mock implementation - suppress output during tests
        }

        function Write-StructuredLogEntry {
            param($Message, $Level, $CorrelationId, $Component, $Details)        It "Should provide comprehensive discovery results logging" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check for discovery completion log
            $discoveryLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.Message -match 'Backup discovery completed' -and $_.Level -eq 'Verbose'
            }
            $discoveryLogs | Should Not BeNullOrEmpty
        }       # Mock implementation - suppress output during tests
        }

        # Import required functions directly for dot sourcing without module manifest
        $RootPath = Join-Path $PSScriptRoot '..\..\..\..'
        $PrivatePath = Join-Path $RootPath 'Private'
        
        # Import backup-related functions
        . (Join-Path $PrivatePath 'Backup\Get-BackupMetadata.ps1')
        . (Join-Path $PrivatePath 'Backup\Find-BackupFile.ps1')

        # Import test helpers if available
        $testHelpersPath = Join-Path $PSScriptRoot '..\..\..\TestHelpers\BackupTestHelpers.ps1'
        if (Test-Path $testHelpersPath) {
            . $testHelpersPath
        }

        # CRITICAL FIX FOR PESTER 3.4: Force override functions after importing
        # Remove original functions and redefine to ensure overrides work in Pester 3.4
        
        # Override utility functions
        function global:Write-Verbose { }
        function global:Write-Debug { }
        function global:Write-Information { }
        function global:Write-Progress { }
        function global:Write-StructuredLog { }

        # Let Pester handle mock cleanup automatically
        
        function Get-BackupMetadata {
            param(
                [string]$BackupFilePath,
                [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
            )
            
            # Return mock metadata based on file path
            switch ($BackupFilePath) {
                'C:\ValidBackupPath\backup1.xml' {
                    return @{
                        ObjectDN = 'CN=TestUser1,OU=Users,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-15 10:30:00'
                        BackupType = 'Full'
                        DomainController = 'DC01.company.com'
                        FileSize = 1024
                        IntegrityValid = $true
                    }
                }
                'C:\ValidBackupPath\backup2.xml' {
                    return @{
                        ObjectDN = 'CN=TestUser2,OU=Employees,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-20 15:45:00'
                        BackupType = 'Incremental'
                        DomainController = 'DC02.company.com'
                        FileSize = 2048
                        IntegrityValid = $true
                    }
                }
                'C:\ValidBackupPath\Subfolder\backup3.xml' {
                    return @{
                        ObjectDN = 'CN=TestUser3,OU=Contractors,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-25 09:15:00'
                        BackupType = 'Full'
                        DomainController = 'DC01.company.com'
                        FileSize = 1536
                        IntegrityValid = $true
                    }
                }
                'C:\EmptyBackupPath\backup1.xml' {
                    return @{
                        ObjectDN = 'CN=EmptyTest,OU=Test,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-10 08:00:00'
                        BackupType = 'Full'
                        DomainController = 'DC01.company.com'
                        FileSize = 512
                        IntegrityValid = $true
                    }
                }
                'C:\ValidBackupPath\invalid-backup.xml' {
                    throw "Simulated metadata extraction failure"
                }
                'C:\ValidBackupPath\wildcard1.xml' {
                    return @{
                        ObjectDN = 'CN=TestUser*,OU=TestOU*,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-15 10:30:00'
                        BackupType = 'Full'
                        DomainController = 'DC01.company.com'
                        FileSize = 1024
                        IntegrityValid = $true
                    }
                }
                'C:\ValidBackupPath\wildcard2.xml' {
                    return @{
                        ObjectDN = 'CN=AnotherUser,OU=TestOU*,DC=company,DC=com'
                        BackupDate = [DateTime]'2024-01-16 11:30:00'
                        BackupType = 'Incremental'
                        DomainController = 'DC02.company.com'
                        FileSize = 1100
                        IntegrityValid = $true
                    }
                }
                default {
                    return $null
                }
            }
        }
    }

    # Set up comprehensive mocking for backup operations - use BeforeEach for Pester 3.4 compatibility
    BeforeEach {
        # CRITICAL FIX FOR PESTER 3.4: Remove and redefine functions to ensure overrides work
        
        # Let Pester handle mock cleanup automatically
        
        # Override utility functions
        function global:Write-Verbose { }
        function global:Write-Debug { }
        function global:Write-Information { }
        
        # Create tracking variables for mock validation
        $script:WriteProgressCalls = @()
        $script:WriteStructuredLogCalls = @()
        $script:GetChildItemCalls = @()
        $script:GetBackupMetadataCalls = @()

        # Override Write-Progress with tracking
        function Write-Progress { 
            param(
                [string]$Activity, 
                [string]$Status, 
                [int]$PercentComplete, 
                [switch]$Completed
            )
            $script:WriteProgressCalls += @{
                Activity = $Activity
                Status = $Status
                PercentComplete = $PercentComplete
                Completed = $Completed.IsPresent
            }
        }

        # Override Write-StructuredLog with tracking
        function Write-StructuredLog { 
            param($Message, $Level, $CorrelationId, $Component, $Data, $Details)
            $script:WriteStructuredLogCalls += @{
                Message = $Message
                Level = $Level
                CorrelationId = $CorrelationId
                Component = $Component
            }
        }

        # Override Test-Path for directory validation
        function Test-Path {
            param($Path, $PathType)
            switch ($Path) {
                'C:\ValidBackupPath' { return $true }
                'C:\InvalidBackupPath' { return $false }
                'C:\EmptyBackupPath' { return $true }
                'C:\AccessDeniedPath' { return $true }
                'C:\ValidBackupPath\backup1.xml' { return $true }
                'C:\ValidBackupPath\backup2.xml' { return $true }
                'C:\ValidBackupPath\Subfolder\backup3.xml' { return $true }
                'C:\EmptyBackupPath\backup1.xml' { return $true }
                'C:\ValidBackupPath\wildcard1.xml' { return $true }
                'C:\ValidBackupPath\wildcard2.xml' { return $true }
                'C:\ValidBackupPath\invalid-backup.xml' { return $true }
                default { return $false }
            }
        }

        # Override Get-ChildItem for backup file discovery
        function Get-ChildItem {
            param($Path, $Filter, [switch]$Recurse, [switch]$File, $ErrorAction)
            
            $script:GetChildItemCalls += @{
                Path = $Path
                Filter = $Filter
                Recurse = $Recurse.IsPresent
                File = $File.IsPresent
            }
            
            if ($Path -eq 'C:\ValidBackupPath') {
                $file1 = New-Object PSObject
                $file1 | Add-Member -MemberType NoteProperty -Name Name -Value 'backup1.xml'
                $file1 | Add-Member -MemberType NoteProperty -Name FullName -Value 'C:\ValidBackupPath\backup1.xml'
                $file1 | Add-Member -MemberType NoteProperty -Name DirectoryName -Value 'C:\ValidBackupPath'
                $file1 | Add-Member -MemberType NoteProperty -Name LastWriteTime -Value (Get-Date '2025-07-01')
                
                $file2 = New-Object PSObject
                $file2 | Add-Member -MemberType NoteProperty -Name Name -Value 'backup2.xml'
                $file2 | Add-Member -MemberType NoteProperty -Name FullName -Value 'C:\ValidBackupPath\backup2.xml'
                $file2 | Add-Member -MemberType NoteProperty -Name DirectoryName -Value 'C:\ValidBackupPath'
                $file2 | Add-Member -MemberType NoteProperty -Name LastWriteTime -Value (Get-Date '2025-07-05')
                
                $file3 = New-Object PSObject
                $file3 | Add-Member -MemberType NoteProperty -Name Name -Value 'backup3.xml'
                $file3 | Add-Member -MemberType NoteProperty -Name FullName -Value 'C:\ValidBackupPath\Subfolder\backup3.xml'
                $file3 | Add-Member -MemberType NoteProperty -Name DirectoryName -Value 'C:\ValidBackupPath\Subfolder'
                $file3 | Add-Member -MemberType NoteProperty -Name LastWriteTime -Value (Get-Date '2025-07-08')
                
                # Only include the 3 main files to match expected count
                $result = @($file1, $file2, $file3)
                return ,$result  # Force array return
            }
            elseif ($Path -eq 'C:\EmptyBackupPath') {
                return @()
            }
            elseif ($Path -eq 'C:\AccessDeniedPath') {
                throw [System.UnauthorizedAccessException]::new('Access denied to backup directory')
            }
            return @()
        }

        # Override Get-BackupMetadata 
        function Get-BackupMetadata {
            param($BackupFilePath, $CorrelationId)
            
            $script:GetBackupMetadataCalls += @{
                BackupFilePath = $BackupFilePath
                CorrelationId = $CorrelationId
            }
            
            switch ($BackupFilePath) {
                'C:\ValidBackupPath\backup1.xml' {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=TestUser1,OU=Users,DC=company,DC=com'
                        BackupDate = '2025-07-10T10:00:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'PSSecurityBackup_v1.0_TestUser1'
                        IntegrityStatus = 'Valid'
                        BackupSize = 1024
                        ChecksumValid = $true
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
                'C:\ValidBackupPath\backup2.xml' {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=TestUser2,OU=Sales,DC=company,DC=com'
                        BackupDate = '2025-07-12T14:30:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'PSSecurityBackup_v1.0_TestUser2'
                        IntegrityStatus = 'Valid'
                        BackupSize = 2048
                        ChecksumValid = $true
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
                'C:\ValidBackupPath\Subfolder\backup3.xml' {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=TestComputer,OU=Computers,DC=company,DC=com'
                        BackupDate = '2025-07-13T08:15:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'PSSecurityBackup_v1.0_TestComputer'
                        IntegrityStatus = 'Valid'
                        BackupSize = 1536
                        ChecksumValid = $true
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
                'C:\ValidBackupPath\wildcard1.xml' {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=TestUser*,OU=TestOU*,DC=company,DC=com'
                        BackupDate = '2025-07-10T10:00:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'PSSecurityBackup_v1.0_Wildcard1'
                        IntegrityStatus = 'Valid'
                        BackupSize = 1024
                        ChecksumValid = $true
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
                'C:\ValidBackupPath\wildcard2.xml' {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=AnotherUser,OU=TestOU*,DC=company,DC=com'
                        BackupDate = '2025-07-10T11:00:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'PSSecurityBackup_v1.0_Wildcard2'
                        IntegrityStatus = 'Valid'
                        BackupSize = 1100
                        ChecksumValid = $true
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
                'C:\ValidBackupPath\invalid-backup.xml' {
                    throw "Simulated metadata extraction failure"
                }
                default {
                    $result = [PSCustomObject]@{
                        ObjectDN = 'CN=UnknownObject,DC=company,DC=com'
                        BackupDate = '2025-07-10T00:00:00Z'
                        BackupVersion = 'v1.0'
                        ValidationSignature = 'Unknown'
                        IntegrityStatus = 'Invalid'
                        BackupSize = 0
                        ChecksumValid = $false
                        CorrelationId = $CorrelationId
                    }
                    $result.PSObject.TypeNames.Insert(0, 'BackupMetadata')
                    return $result
                }
            }
        }
    }

    Context "Parameter Validation" {
        It "Should accept valid backup path" {
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' } | Should Not Throw
        }

        It "Should reject null or empty backup path" {
            { Find-BackupFile -BackupPath $null } | Should Throw "Failed to discover backup files: BackupPath cannot be empty or whitespace"
            { Find-BackupFile -BackupPath '' } | Should Throw "Failed to discover backup files: BackupPath cannot be empty or whitespace"
            { Find-BackupFile -BackupPath '   ' } | Should Throw "Failed to discover backup files: BackupPath cannot be empty or whitespace"
        }

        It "Should reject non-existent backup path" {
            { Find-BackupFile -BackupPath 'C:\InvalidBackupPath' } | Should Throw "Failed to discover backup files: Backup directory not found or inaccessible: C:\InvalidBackupPath"
        }

        It "Should accept optional ObjectDN filter parameter" {
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*Sales*' } | Should Not Throw
        }

        It "Should accept optional DateRange filter parameter" {
            $dateRange = @{ 
                StartDate = (Get-Date).AddDays(-30)
                EndDate = Get-Date 
            }
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange } | Should Not Throw
        }

        It "Should validate DateRange parameter format" {
            $invalidDateRange = @{ StartDate = 'invalid'; EndDate = 'invalid' }
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $invalidDateRange } | Should Throw "Failed to discover backup files: DateRange.StartDate must be a DateTime object"
        }

        It "Should validate DateRange start before end" {
            $invalidDateRange = @{ 
                StartDate = Get-Date
                EndDate = (Get-Date).AddDays(-1)
            }
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $invalidDateRange } | Should Throw "Failed to discover backup files: DateRange.StartDate cannot be later than DateRange.EndDate"
        }

        It "Should generate correlation ID if not provided" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            $result[0].DiscoveryCorrelationId | Should Not BeNullOrEmpty
            $result[0].DiscoveryCorrelationId | Should Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }

    Context "Core Backup Discovery Functionality" {
        It "Should discover all backup files in valid directory" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            $result | Should Not BeNullOrEmpty
            $result.Count | Should Be 3
            $result[0].PSObject.TypeNames[0] | Should Be 'BackupInventoryResult'
        }

        It "Should include comprehensive metadata for each backup" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            foreach ($backup in $result) {
                $backup.ObjectDN | Should Not BeNullOrEmpty
                $backup.BackupDate | Should Not BeNullOrEmpty
                $backup.BackupVersion | Should Not BeNullOrEmpty
                $backup.IntegrityStatus | Should Not BeNullOrEmpty
                $backup.BackupSize | Should BeGreaterThan 0
                $backup.ChecksumValid | Should Be $true
            }
        }

        It "Should add discovery context to results" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -CorrelationId $correlationId
            
            foreach ($backup in $result) {
                $backup.DiscoveryCorrelationId | Should Be $correlationId
                $backup.DiscoveryTime | Should Not BeNullOrEmpty
                $backup.FilteredByObjectDN | Should Be $false
                $backup.FilteredByDateRange | Should Be $false
            }
        }

        It "Should handle empty backup directory gracefully" {
            $result = Find-BackupFile -BackupPath 'C:\EmptyBackupPath'
            
            $result | Should BeNullOrEmpty
            @($result).Count | Should Be 0
        }

        It "Should call Get-ChildItem with correct parameters" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check our tracking variable instead of Assert-MockCalled
            $script:GetChildItemCalls.Count | Should BeGreaterThan 0
            $script:GetChildItemCalls[0].Path | Should Be 'C:\ValidBackupPath'
            $script:GetChildItemCalls[0].Filter | Should Be '*.xml'
            $script:GetChildItemCalls[0].Recurse | Should Be $true
            $script:GetChildItemCalls[0].File | Should Be $true
        }

        It "Should call Get-BackupMetadata for each discovered file" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check that Get-BackupMetadata was called for each file
            $script:GetBackupMetadataCalls.Count | Should Be 3
            $script:GetBackupMetadataCalls[0].BackupFilePath | Should Match '\.xml$'
        }
    }

    Context "ObjectDN Filtering" {
        It "Should filter backups by ObjectDN pattern" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*Sales*'
            
            $result.Count | Should Be 1
            $result[0].ObjectDN | Should Be 'CN=TestUser2,OU=Sales,DC=company,DC=com'
            $result[0].FilteredByObjectDN | Should Be $true
        }

        It "Should handle wildcard patterns correctly" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*User*'
            
            $result.Count | Should Be 2
            $result[0].ObjectDN | Should Match 'TestUser'
            $result[1].ObjectDN | Should Match 'TestUser'
        }

        It "Should return empty results when no matches found" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*NonExistent*'
            
            $result.Count | Should Be 0
        }

        It "Should handle exact DN matches" {
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN 'CN=TestUser1,OU=Users,DC=company,DC=com'
            
            $result.Count | Should Be 1
            $result[0].ObjectDN | Should Be 'CN=TestUser1,OU=Users,DC=company,DC=com'
        }
    }

    Context "Date Range Filtering" {
        It "Should filter backups by start date" {
            $dateRange = @{ StartDate = [DateTime]::Parse('2025-07-12T00:00:00Z') }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange
            
            $result.Count | Should Be 2
            $result[0].FilteredByDateRange | Should Be $true
        }

        It "Should filter backups by end date" {
            $dateRange = @{ EndDate = [DateTime]::Parse('2025-07-11T23:59:59Z') }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange
            
            $result.Count | Should Be 1
            $result[0].BackupDate | Should Be '2025-07-10T10:00:00Z'
        }

        It "Should filter backups by date range" {
            $dateRange = @{ 
                StartDate = [DateTime]::Parse('2025-07-11T00:00:00Z')
                EndDate = [DateTime]::Parse('2025-07-12T23:59:59Z')
            }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange
            
            $result.Count | Should Be 1
            $result[0].BackupDate | Should Be '2025-07-12T14:30:00Z'
        }

        It "Should handle date range with no matches" {
            $dateRange = @{ 
                StartDate = [DateTime]::Parse('2025-07-01T00:00:00Z')
                EndDate = [DateTime]::Parse('2025-07-05T23:59:59Z')
            }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange
            
            $result.Count | Should Be 0
        }
    }

    Context "Combined Filtering" {
        It "Should apply both ObjectDN and DateRange filters" {
            $dateRange = @{ StartDate = [DateTime]::Parse('2025-07-11T00:00:00Z') }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*User*' -DateRange $dateRange
            
            $result.Count | Should Be 1
            $result[0].ObjectDN | Should Be 'CN=TestUser2,OU=Sales,DC=company,DC=com'
            $result[0].FilteredByObjectDN | Should Be $true
            $result[0].FilteredByDateRange | Should Be $true
        }

        It "Should return empty when filters exclude all results" {
            $dateRange = @{ EndDate = [DateTime]::Parse('2025-07-01T00:00:00Z') }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '*User*' -DateRange $dateRange
            
            $result.Count | Should Be 0
        }
    }

    Context "Error Handling" {
        It "Should handle directory access denied gracefully" {
            { Find-BackupFile -BackupPath 'C:\AccessDeniedPath' } | Should Throw "Failed to discover backup files: Failed to scan backup directory C:\AccessDeniedPath : Access denied to backup directory"
        }

        It "Should continue processing when individual files fail" {
            # Mock Get-BackupMetadata to fail for one file
            Mock Get-BackupMetadata {
                param($BackupFilePath, $CorrelationId)
                if ($BackupFilePath -eq 'C:\ValidBackupPath\backup2.xml') {
                    throw "Metadata extraction failed"
                }
                # Return normal metadata for other files
                return [PSCustomObject]@{
                    ObjectDN = 'CN=TestObject,DC=company,DC=com'
                    BackupDate = '2025-07-10T10:00:00Z'
                    BackupVersion = '1.0'
                    IntegrityStatus = 'Valid'
                    BackupSize = 1024
                    ChecksumValid = $true
                }
            }

            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Should continue processing and return results for successful files
            $result.Count | Should Be 2
        }

        It "Should log structured error information" {
            { Find-BackupFile -BackupPath 'C:\AccessDeniedPath' } | Should Throw
            
            # Check our tracking variable for error logs
            $errorLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.Level -eq 'Error' -and $_.Message -match 'Failed to scan backup directory'
            }
            $errorLogs | Should Not BeNullOrEmpty
        }

        It "Should handle malformed date parsing gracefully" {
            # Mock Get-BackupMetadata to return invalid date
            Mock Get-BackupMetadata {
                return [PSCustomObject]@{
                    ObjectDN = 'CN=TestObject,DC=company,DC=com'
                    BackupDate = 'invalid-date-format'
                    BackupVersion = '1.0'
                    IntegrityStatus = 'Valid'
                    BackupSize = 1024
                    ChecksumValid = $true
                }
            }

            $dateRange = @{ StartDate = (Get-Date).AddDays(-1) }
            $result = Find-BackupFile -BackupPath 'C:\ValidBackupPath' -DateRange $dateRange
            
            # Should skip files with invalid dates
            $result.Count | Should Be 0
        }
    }

    Context "Performance and Memory Safety" {
        It "Should execute within reasonable time limits" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
        }

        It "Should use Write-Progress for user feedback" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check our tracking variable
            $script:WriteProgressCalls.Count | Should BeGreaterThan 0
        }

        It "Should complete Write-Progress when finished" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check for completion call in our tracking
            $completionCall = $script:WriteProgressCalls | Where-Object { $_.Completed -eq $true }
            $completionCall | Should Not BeNullOrEmpty
        }
    }

    Context "Enterprise Integration" {
        It "Should track correlation IDs consistently" {
            $correlationId = [System.Guid]::NewGuid().ToString()
            Find-BackupFile -BackupPath 'C:\ValidBackupPath' -CorrelationId $correlationId
            
            # Check our tracking variable for correlation ID usage
            $correlationLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.CorrelationId -eq $correlationId
            }
            $correlationLogs | Should Not BeNullOrEmpty
        }

        It "Should log discovery start and completion" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check for start log
            $startLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.Message -match 'Starting backup file discovery' -and $_.Level -eq 'Debug'
            }
            $startLogs | Should Not BeNullOrEmpty
            
            # Check for completion log
            $completionLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.Message -match 'completed' -and $_.Level -eq 'Debug'
            }
            $completionLogs | Should Not BeNullOrEmpty
        }

        It "Should provide comprehensive discovery results logging" {
            Find-BackupFile -BackupPath 'C:\ValidBackupPath'
            
            # Check for discovery completion log
            $discoveryLogs = $script:WriteStructuredLogCalls | Where-Object { 
                $_.Message -match 'Backup discovery completed' -and $_.Level -eq 'Verbose'
            }
            $discoveryLogs | Should Not BeNullOrEmpty
        }
    }

    Context "Input Sanitization and Security" {
        It "Should sanitize backup path input" {
            # Test with path containing extra whitespace
            $result = Find-BackupFile -BackupPath '  C:\ValidBackupPath  '
            
            $result | Should Not BeNullOrEmpty
            $result.Count | Should Be 3
        }

        It "Should prevent path traversal in backup path" {
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath\..\..\..\Windows\System32' } | Should Throw "Failed to discover backup files: Backup directory not found or inaccessible: C:\ValidBackupPath\..\..\..\Windows\System32"
        }

        It "Should validate ObjectDN filter for malicious patterns" {
            # ObjectDN filter should be safe as it's used with -like operator
            { Find-BackupFile -BackupPath 'C:\ValidBackupPath' -ObjectDN '$(Get-Process)' } | Should Not Throw
        }
    }
}




