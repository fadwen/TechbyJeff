#Requires -Version 5.1

<#
.SYNOPSIS
    Test helper functions for Backup module testing

.DESCRIPTION
    Provides comprehensive test helper functions for backup operations testing,
    including mock data generation, validation helpers, and security testing
    utilities specifically designed for backup functionality.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    
    Used exclusively for Pester testing of Backup module functions.
    Provides safe mock implementations and test data generation.
#>

# Mock structured logging function
function Write-StructuredLog {
    param(
        [string]$Message,
        [string]$Level = 'Information',
        [string]$CorrelationId,
        [string]$Component,
        [hashtable]$Data,
        [hashtable]$Details
    )
    # Mock implementation - just write to verbose stream
    Write-Verbose "[$Level] $Message - CorrelationId: $CorrelationId"
}

function New-TestBackupMetadata {
    <#
    .SYNOPSIS
        Creates test backup metadata objects for testing
    
    .DESCRIPTION
        Generates realistic backup metadata objects with configurable properties
        for comprehensive testing scenarios.
    
    .PARAMETER ObjectDN
        The distinguished name for the backup object
    
    .PARAMETER BackupDate
        The backup creation date
    
    .PARAMETER IntegrityStatus
        The integrity status of the backup
    #>
    [CmdletBinding()]
    param(
        [string]$ObjectDN = 'CN=TestObject,OU=Test,DC=company,DC=com',
        [string]$BackupDate = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ'),
        [string]$IntegrityStatus = 'Valid'
    )
    
    return [PSCustomObject]@{
        ObjectDN = $ObjectDN
        BackupDate = $BackupDate
        BackupVersion = '1.0'
        IntegrityStatus = $IntegrityStatus
        BackupSize = Get-Random -Minimum 1024 -Maximum 10240
        ChecksumValid = $IntegrityStatus -eq 'Valid'
        BackupHash = 'SHA256:' + (-join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }))
        CompressionRatio = [math]::Round((Get-Random -Minimum 0.3 -Maximum 0.8), 2)
        EncryptionStatus = 'Encrypted'
        BackupCreatedBy = 'Test User'
        BackupPath = "C:\TestBackups\$($ObjectDN.Replace(',','_').Replace('=','_')).xml"
    }
}

function New-TestBackupFile {
    <#
    .SYNOPSIS
        Creates test backup file objects for file system mocking
    
    .DESCRIPTION
        Generates realistic backup file objects that can be used to mock
        Get-ChildItem results in backup discovery testing.
    
    .PARAMETER Name
        The backup file name
    
    .PARAMETER FullName
        The full path to the backup file
    
    .PARAMETER CreationTime
        The file creation time
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$FullName,
        [DateTime]$CreationTime = (Get-Date)
    )
    
    return [PSCustomObject]@{
        Name = $Name
        FullName = $FullName
        Extension = '.xml'
        Length = Get-Random -Minimum 1024 -Maximum 51200
        CreationTime = $CreationTime
        LastWriteTime = $CreationTime
        LastAccessTime = (Get-Date)
        Attributes = 'Archive'
        Directory = Split-Path $FullName -Parent
        DirectoryName = Split-Path $FullName -Parent
        Exists = $true
        IsReadOnly = $false
    }
}

function Test-BackupPathSecurity {
    <#
    .SYNOPSIS
        Validates backup path for security issues
    
    .DESCRIPTION
        Performs security validation on backup paths to detect
        path traversal attempts and other security issues.
    
    .PARAMETER Path
        The path to validate
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )
    
    $issues = @()
    
    # Check for path traversal patterns
    if ($Path -match '\.\.') {
        $issues += 'Path traversal detected'
    }
    
    # Check for invalid characters
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    foreach ($char in $invalidChars) {
        if ($Path.Contains($char)) {
            $issues += "Invalid path character detected: $char"
        }
    }
    
    # Check for executable extensions
    $dangerousExtensions = @('.exe', '.bat', '.cmd', '.ps1', '.vbs', '.js')
    foreach ($ext in $dangerousExtensions) {
        if ($Path.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) {
            $issues += "Potentially dangerous file extension: $ext"
        }
    }
    
    return @{
        IsSecure = $issues.Count -eq 0
        Issues = $issues
        Path = $Path
    }
}

function New-MaliciousBackupInput {
    <#
    .SYNOPSIS
        Generates malicious input patterns for security testing
    
    .DESCRIPTION
        Creates various malicious input patterns to test backup function
        security and input validation capabilities.
    
    .PARAMETER Type
        The type of malicious input to generate
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('PathTraversal', 'CommandInjection', 'SQLInjection', 'XSS', 'LDAP')]
        [string]$Type
    )
    
    switch ($Type) {
        'PathTraversal' {
            return @(
                '..\..\..\..\Windows\System32',
                '..\..\..\etc\passwd',
                'C:\Backups\..\..\sensitive\files',
                'C:\Backups\..\..\..\Program Files\malicious.exe'
            )
        }
        'CommandInjection' {
            return @(
                'C:\Backups; Remove-Item C:\* -Recurse',
                'C:\Backups && del /q /s C:\*',
                'C:\Backups | Get-Process',
                'C:\Backups`$(Get-Content secrets.txt)'
            )
        }
        'SQLInjection' {
            return @(
                "'; DROP TABLE backups; --",
                "C:\Backups' OR 1=1 --",
                "C:\Backups'; INSERT INTO logs VALUES ('hack'); --"
            )
        }
        'XSS' {
            return @(
                '<script>alert("xss")</script>',
                'javascript:alert("xss")',
                '<img src=x onerror=alert("xss")>'
            )
        }
        'LDAP' {
            return @(
                'CN=*)(objectClass=*',
                'CN=test)(|(userPassword=*',
                'CN=*)(&(objectClass=user)(userPassword=*'
            )
        }
        default {
            return @('Generic malicious input')
        }
    }
}

function Test-BackupFilterValidation {
    <#
    .SYNOPSIS
        Validates backup filter parameters for security
    
    .DESCRIPTION
        Performs validation on filter parameters used in backup operations
        to ensure they don't contain malicious patterns.
    
    .PARAMETER ObjectDN
        The ObjectDN filter to validate
    
    .PARAMETER DateRange
        The DateRange filter to validate
    #>
    [CmdletBinding()]
    param(
        [string]$ObjectDN,
        [hashtable]$DateRange
    )
    
    $validation = @{
        IsValid = $true
        Issues = @()
        ObjectDNValid = $true
        DateRangeValid = $true
    }
    
    if ($ObjectDN) {
        # Check for LDAP injection patterns
        $ldapPatterns = @('\*\)', '\)\(', '\)\(&', '\)\(\|')
        foreach ($pattern in $ldapPatterns) {
            if ($ObjectDN -match $pattern) {
                $validation.Issues += "Potential LDAP injection pattern detected: $pattern"
                $validation.ObjectDNValid = $false
                $validation.IsValid = $false
            }
        }
        
        # Check for command injection
        $commandPatterns = @('\$\(', '`', ';', '&', '\|')
        foreach ($pattern in $commandPatterns) {
            if ($ObjectDN -match $pattern) {
                $validation.Issues += "Potential command injection pattern detected: $pattern"
                $validation.ObjectDNValid = $false
                $validation.IsValid = $false
            }
        }
    }
    
    if ($DateRange) {
        if ($DateRange.StartDate -and $DateRange.StartDate -isnot [DateTime]) {
            $validation.Issues += "Invalid StartDate type - must be DateTime"
            $validation.DateRangeValid = $false
            $validation.IsValid = $false
        }
        
        if ($DateRange.EndDate -and $DateRange.EndDate -isnot [DateTime]) {
            $validation.Issues += "Invalid EndDate type - must be DateTime"
            $validation.DateRangeValid = $false
            $validation.IsValid = $false
        }
        
        if ($DateRange.StartDate -and $DateRange.EndDate -and 
            $DateRange.StartDate -gt $DateRange.EndDate) {
            $validation.Issues += "StartDate cannot be later than EndDate"
            $validation.DateRangeValid = $false
            $validation.IsValid = $false
        }
    }
    
    return $validation
}

function New-TestDateRange {
    <#
    .SYNOPSIS
        Creates test date range objects for testing
    
    .DESCRIPTION
        Generates various date range configurations for testing
        backup filtering functionality.
    
    .PARAMETER Type
        The type of date range to create
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('LastWeek', 'LastMonth', 'LastYear', 'Future', 'Invalid', 'Reversed')]
        [string]$Type = 'LastWeek'
    )
    
    $now = Get-Date
    
    switch ($Type) {
        'LastWeek' {
            return @{
                StartDate = $now.AddDays(-7)
                EndDate = $now
            }
        }
        'LastMonth' {
            return @{
                StartDate = $now.AddDays(-30)
                EndDate = $now
            }
        }
        'LastYear' {
            return @{
                StartDate = $now.AddDays(-365)
                EndDate = $now
            }
        }
        'Future' {
            return @{
                StartDate = $now.AddDays(1)
                EndDate = $now.AddDays(30)
            }
        }
        'Invalid' {
            return @{
                StartDate = 'invalid-date'
                EndDate = 'invalid-date'
            }
        }
        'Reversed' {
            return @{
                StartDate = $now
                EndDate = $now.AddDays(-7)
            }
        }
    }
}

function Assert-BackupResultStructure {
    <#
    .SYNOPSIS
        Validates the structure of backup result objects
    
    .DESCRIPTION
        Performs comprehensive validation of backup result objects
        to ensure they contain all required properties and correct types.
    
    .PARAMETER Result
        The backup result object to validate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )
    
    $requiredProperties = @(
        'ObjectDN', 'BackupDate', 'BackupVersion', 'IntegrityStatus',
        'BackupSize', 'ChecksumValid', 'DiscoveryCorrelationId',
        'DiscoveryTime', 'FilteredByObjectDN', 'FilteredByDateRange'
    )
    
    $validation = @{
        IsValid = $true
        MissingProperties = @()
        InvalidTypes = @()
        PropertyCount = 0
    }
    
    if ($Result) {
        $validation.PropertyCount = ($Result | Get-Member -MemberType NoteProperty).Count
        
        foreach ($property in $requiredProperties) {
            if (-not ($Result.PSObject.Properties.Name -contains $property)) {
                $validation.MissingProperties += $property
                $validation.IsValid = $false
            }
        }
        
        # Validate specific property types
        if ($Result.BackupSize -and $Result.BackupSize -isnot [int] -and $Result.BackupSize -isnot [long]) {
            $validation.InvalidTypes += "BackupSize should be numeric"
            $validation.IsValid = $false
        }
        
        if ($Result.ChecksumValid -and $Result.ChecksumValid -isnot [bool]) {
            $validation.InvalidTypes += "ChecksumValid should be boolean"
            $validation.IsValid = $false
        }
        
        if ($Result.FilteredByObjectDN -and $Result.FilteredByObjectDN -isnot [bool]) {
            $validation.InvalidTypes += "FilteredByObjectDN should be boolean"
            $validation.IsValid = $false
        }
        
        if ($Result.FilteredByDateRange -and $Result.FilteredByDateRange -isnot [bool]) {
            $validation.InvalidTypes += "FilteredByDateRange should be boolean"
            $validation.IsValid = $false
        }
        
        # Validate PSTypeName
        if ($Result.PSTypeName -ne 'BackupInventoryResult') {
            $validation.InvalidTypes += "PSTypeName should be 'BackupInventoryResult'"
            $validation.IsValid = $false
        }
    } else {
        $validation.IsValid = $false
        $validation.MissingProperties = $requiredProperties
    }
    
    return $validation
}

# Functions are automatically available when dot-sourced
# No Export-ModuleMember needed for script files
