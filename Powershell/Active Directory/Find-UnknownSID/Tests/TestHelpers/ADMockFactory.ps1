# TestHelpers/ADMockFactory.ps1
# Active Directory testing mock factory

class ADMockFactory {
    static [hashtable] $MockData = @{
        Domains = @()
        Users = @()
        Groups = @()
        Computers = @()
        OrganizationalUnits = @()
        SIDs = @()
    }
    
    static [hashtable] $Configuration = @{
        DomainDN = 'DC=contoso,DC=com'
        DomainName = 'CONTOSO'
        ForestName = 'contoso.com'
    }
    
    # Initialize mock AD environment
    static [void] Initialize([hashtable]$Config = @{}) {
        if ($Config.Count -gt 0) {
            foreach ($key in $Config.Keys) {
                [ADMockFactory]::Configuration[$key] = $Config[$key]
            }
        }
        
        [ADMockFactory]::CreateDefaultDomain()
        [ADMockFactory]::CreateDefaultOUs()
        [ADMockFactory]::CreateDefaultUsers()
        [ADMockFactory]::CreateDefaultGroups()
        [ADMockFactory]::CreateOrphanedSIDs()
    }
    
    # Create domain objects
    static [void] CreateDefaultDomain() {
        $domain = @{
            DistinguishedName = [ADMockFactory]::Configuration.DomainDN
            DNSRoot = [ADMockFactory]::Configuration.ForestName
            Name = [ADMockFactory]::Configuration.DomainName
            NetBIOSName = [ADMockFactory]::Configuration.DomainName
            DomainSID = 'S-1-5-21-1234567890-1234567890-1234567890'
            PDCEmulator = "DC01.$([ADMockFactory]::Configuration.ForestName)"
            DomainMode = 'Windows2016Domain'
            ForestMode = 'Windows2016Forest'
        }
        
        [ADMockFactory]::MockData.Domains = @($domain)
    }
    
    # Create organizational units
    static [void] CreateDefaultOUs() {
        $ous = @(
            @{
                Name = 'Users'
                DistinguishedName = "OU=Users,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'organizationalUnit'
                Description = 'User accounts'
            }
            @{
                Name = 'Groups'
                DistinguishedName = "OU=Groups,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'organizationalUnit'
                Description = 'Security and distribution groups'
            }
            @{
                Name = 'Computers'
                DistinguishedName = "OU=Computers,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'organizationalUnit'
                Description = 'Computer accounts'
            }
        )
        
        [ADMockFactory]::MockData.OrganizationalUnits = $ous
    }
    
    # Create user objects with various SID scenarios
    static [void] CreateDefaultUsers() {
        $users = @(
            @{
                Name = 'testuser1'
                SamAccountName = 'testuser1'
                DistinguishedName = "CN=testuser1,OU=Users,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'user'
                ObjectSID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'
                Enabled = $true
                Description = 'Test user account'
                SecurityDescriptor = [ADMockFactory]::CreateUserACL('S-1-5-21-1234567890-1234567890-1234567890-1001', $false)
            }
            @{
                Name = 'testuser2'
                SamAccountName = 'testuser2'
                DistinguishedName = "CN=testuser2,OU=Users,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'user'
                ObjectSID = 'S-1-5-21-1234567890-1234567890-1234567890-1002'
                Enabled = $true
                Description = 'Test user with orphaned SIDs in ACL'
                SecurityDescriptor = [ADMockFactory]::CreateUserACL('S-1-5-21-1234567890-1234567890-1234567890-1002', $true)
            }
            @{
                Name = 'disableduser'
                SamAccountName = 'disableduser'
                DistinguishedName = "CN=disableduser,OU=Users,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'user'
                ObjectSID = 'S-1-5-21-1234567890-1234567890-1234567890-1003'
                Enabled = $false
                Description = 'Disabled user account'
                SecurityDescriptor = [ADMockFactory]::CreateUserACL('S-1-5-21-1234567890-1234567890-1234567890-1003', $false)
            }
        )
        
        [ADMockFactory]::MockData.Users = $users
    }
    
    # Create group objects
    static [void] CreateDefaultGroups() {
        $groups = @(
            @{
                Name = 'Domain Admins'
                SamAccountName = 'Domain Admins'
                DistinguishedName = "CN=Domain Admins,OU=Groups,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'group'
                ObjectSID = 'S-1-5-21-1234567890-1234567890-1234567890-512'
                GroupScope = 'Global'
                GroupCategory = 'Security'
                Members = @('S-1-5-21-1234567890-1234567890-1234567890-500')  # Administrator
                SecurityDescriptor = [ADMockFactory]::CreateGroupACL('S-1-5-21-1234567890-1234567890-1234567890-512')
            }
            @{
                Name = 'Test Group'
                SamAccountName = 'TestGroup'
                DistinguishedName = "CN=Test Group,OU=Groups,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'group'
                ObjectSID = 'S-1-5-21-1234567890-1234567890-1234567890-2001'
                GroupScope = 'Global'
                GroupCategory = 'Security'
                Members = @(
                    'S-1-5-21-1234567890-1234567890-1234567890-1001',  # testuser1
                    'S-1-5-21-1234567890-1234567890-1234567890-1002'   # testuser2
                )
                SecurityDescriptor = [ADMockFactory]::CreateGroupACL('S-1-5-21-1234567890-1234567890-1234567890-2001')
            }
        )
        
        [ADMockFactory]::MockData.Groups = $groups
    }
    
    # Create orphaned SID test data
    static [void] CreateOrphanedSIDs() {
        $orphanedSIDs = @(
            @{
                SID = 'S-1-5-21-9999999999-9999999999-9999999999-9999'
                Type = 'DeletedUser'
                LastSeen = (Get-Date).AddDays(-30)
                FoundIn = @('User ACLs', 'Group Memberships')
                Description = 'Deleted user account - orphaned SID'
            }
            @{
                SID = 'S-1-5-21-8888888888-8888888888-8888888888-8888'
                Type = 'DeletedGroup'
                LastSeen = (Get-Date).AddDays(-60)
                FoundIn = @('User ACLs', 'OU ACLs')
                Description = 'Deleted group - orphaned SID'
            }
            @{
                SID = 'S-1-5-21-7777777777-7777777777-7777777777-7777'
                Type = 'MigratedAccount'
                LastSeen = (Get-Date).AddDays(-90)
                FoundIn = @('File ACLs', 'Registry ACLs')
                Description = 'Account from domain migration - orphaned SID'
            }
        )
        
        [ADMockFactory]::MockData.SIDs = $orphanedSIDs
    }
    
    # Create realistic ACL with optional orphaned SIDs
    static [object] CreateUserACL([string]$OwnerSID, [bool]$IncludeOrphanedSIDs) {
        $aces = @(
            @{
                IdentityReference = $OwnerSID
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'GenericAll'
                InheritanceType = 'None'
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
                IsOrphaned = $false
            }
            @{
                IdentityReference = 'S-1-5-21-1234567890-1234567890-1234567890-512'  # Domain Admins
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'GenericAll'
                InheritanceType = 'All'
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
                IsOrphaned = $false
            }
            @{
                IdentityReference = 'S-1-5-18'  # SYSTEM
                AccessControlType = 'Allow'
                ActiveDirectoryRights = 'GenericAll'
                InheritanceType = 'None'
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
                IsOrphaned = $false
            }
        )
        
        if ($IncludeOrphanedSIDs) {
            $aces += @(
                @{
                    IdentityReference = 'S-1-5-21-9999999999-9999999999-9999999999-9999'
                    AccessControlType = 'Allow'
                    ActiveDirectoryRights = 'ReadProperty'
                    InheritanceType = 'None'
                    ObjectType = [System.Guid]::Empty
                    InheritedObjectType = [System.Guid]::Empty
                    IsOrphaned = $true
                }
                @{
                    IdentityReference = 'S-1-5-21-8888888888-8888888888-8888888888-8888'
                    AccessControlType = 'Allow'
                    ActiveDirectoryRights = 'WriteProperty'
                    InheritanceType = 'All'
                    ObjectType = [System.Guid]::Empty
                    InheritedObjectType = [System.Guid]::Empty
                    IsOrphaned = $true
                }
            )
        }
        
        return @{
            Owner = $OwnerSID
            Access = $aces
            Audit = @()
            Group = 'S-1-5-21-1234567890-1234567890-1234567890-512'
        }
    }
    
    # Create group ACL
    static [object] CreateGroupACL([string]$OwnerSID) {
        return [ADMockFactory]::CreateUserACL($OwnerSID, $false)
    }
    
    # Get mock AD objects by search base
    static [object[]] GetADObjects([string]$SearchBase, [string]$Filter = '*') {
        $results = @()
        
        # Determine what type of objects to return based on SearchBase
        if ($SearchBase -match 'OU=Users') {
            $results = [ADMockFactory]::MockData.Users
        }
        elseif ($SearchBase -match 'OU=Groups') {
            $results = [ADMockFactory]::MockData.Groups
        }
        elseif ($SearchBase -match 'OU=Computers') {
            $results = [ADMockFactory]::MockData.Computers
        }
        elseif ($SearchBase -match '^DC=') {
            # Domain root - return all objects
            $results = [ADMockFactory]::MockData.Users + 
                      [ADMockFactory]::MockData.Groups + 
                      [ADMockFactory]::MockData.Computers +
                      [ADMockFactory]::MockData.OrganizationalUnits
        }
        
        # Apply filter if not wildcard
        if ($Filter -ne '*') {
            $results = $results | Where-Object { $_.Name -like $Filter -or $_.SamAccountName -like $Filter }
        }
        
        return $results
    }
    
    # Create performance test data
    static [object[]] CreateLargeDataset([int]$UserCount, [int]$GroupCount, [bool]$IncludeOrphanedSIDs) {
        $users = @()
        $groups = @()
        $orphanedSIDCount = if ($IncludeOrphanedSIDs) { [math]::Floor($UserCount * 0.1) } else { 0 }
        
        # Generate users
        for ($i = 1; $i -le $UserCount; $i++) {
            $hasOrphanedSIDs = ($i -le $orphanedSIDCount)
            
            $users += @{
                Name = "perfuser$i"
                SamAccountName = "perfuser$i"
                DistinguishedName = "CN=perfuser$i,OU=Users,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'user'
                ObjectSID = "S-1-5-21-1234567890-1234567890-1234567890-$($i + 2000)"
                Enabled = $true
                SecurityDescriptor = [ADMockFactory]::CreateUserACL("S-1-5-21-1234567890-1234567890-1234567890-$($i + 2000)", $hasOrphanedSIDs)
            }
        }
        
        # Generate groups
        for ($i = 1; $i -le $GroupCount; $i++) {
            $groups += @{
                Name = "perfgroup$i"
                SamAccountName = "perfgroup$i"
                DistinguishedName = "CN=perfgroup$i,OU=Groups,$([ADMockFactory]::Configuration.DomainDN)"
                ObjectClass = 'group'
                ObjectSID = "S-1-5-21-1234567890-1234567890-1234567890-$($i + 5000)"
                GroupScope = 'Global'
                GroupCategory = 'Security'
                SecurityDescriptor = [ADMockFactory]::CreateGroupACL("S-1-5-21-1234567890-1234567890-1234567890-$($i + 5000)")
            }
        }
        
        return $users + $groups
    }
    
    # Clear mock data
    static [void] Reset() {
        [ADMockFactory]::MockData = @{
            Domains = @()
            Users = @()
            Groups = @()
            Computers = @()
            OrganizationalUnits = @()
            SIDs = @()
        }
    }
}

# Mock AD PowerShell cmdlets
function New-ADMocks {
    <#
    .SYNOPSIS
        Creates comprehensive Active Directory mocks for testing
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludePerformanceData,
        [int]$PerformanceUserCount = 1000,
        [int]$PerformanceGroupCount = 100
    )
    
    # Initialize mock factory
    [ADMockFactory]::Initialize()
    
    # Mock Get-ADDomain
    Mock Get-ADDomain {
        param($Identity, $Server)
        
        $domain = [ADMockFactory]::MockData.Domains[0]
        if (-not $domain) {
            throw [Microsoft.ActiveDirectory.Management.ADServerDownException]::new("Unable to contact domain controller")
        }
        
        return [PSCustomObject]$domain
    }
    
    # Mock Get-ADUser
    Mock Get-ADUser {
        param($Identity, $Filter, $SearchBase, $Properties)
        
        $users = [ADMockFactory]::MockData.Users
        
        if ($Identity) {
            $user = $users | Where-Object { $_.SamAccountName -eq $Identity -or $_.DistinguishedName -eq $Identity }
            if (-not $user) {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("User '$Identity' not found")
            }
            return [PSCustomObject]$user
        }
        
        if ($SearchBase) {
            $users = $users | Where-Object { $_.DistinguishedName -like "*$SearchBase" }
        }
        
        if ($Filter -and $Filter -ne '*') {
            # Simple filter processing
            if ($Filter -match 'Enabled -eq \$true') {
                $users = $users | Where-Object { $_.Enabled -eq $true }
            }
            elseif ($Filter -match 'Enabled -eq \$false') {
                $users = $users | Where-Object { $_.Enabled -eq $false }
            }
        }
        
        return $users | ForEach-Object { [PSCustomObject]$_ }
    }
    
    # Mock Get-ADGroup
    Mock Get-ADGroup {
        param($Identity, $Filter, $SearchBase, $Properties)
        
        $groups = [ADMockFactory]::MockData.Groups
        
        if ($Identity) {
            $group = $groups | Where-Object { $_.SamAccountName -eq $Identity -or $_.DistinguishedName -eq $Identity }
            if (-not $group) {
                throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new("Group '$Identity' not found")
            }
            return [PSCustomObject]$group
        }
        
        if ($SearchBase) {
            $groups = $groups | Where-Object { $_.DistinguishedName -like "*$SearchBase" }
        }
        
        return $groups | ForEach-Object { [PSCustomObject]$_ }
    }
    
    # Mock Get-ADObject (generic)
    Mock Get-ADObject {
        param($Identity, $Filter, $SearchBase, $Properties)
        
        if ($SearchBase) {
            return [ADMockFactory]::GetADObjects($SearchBase, $Filter) | ForEach-Object { [PSCustomObject]$_ }
        }
        
        # Return all objects if no search base
        $allObjects = [ADMockFactory]::MockData.Users + 
                     [ADMockFactory]::MockData.Groups + 
                     [ADMockFactory]::MockData.OrganizationalUnits
        
        return $allObjects | ForEach-Object { [PSCustomObject]$_ }
    }
    
    # Mock Get-Acl
    Mock Get-Acl {
        param($Path)
        
        # Return mock ACL for AD paths
        if ($Path -match '^AD:') {
            $objectDN = $Path -replace '^AD:', ''
            $allObjects = [ADMockFactory]::MockData.Users + [ADMockFactory]::MockData.Groups
            $adObject = $allObjects | Where-Object { $_.DistinguishedName -eq $objectDN }
            
            if ($adObject -and $adObject.SecurityDescriptor) {
                return [PSCustomObject]$adObject.SecurityDescriptor
            }
        }
        
        # Default ACL for other paths
        return @{
            Owner = 'BUILTIN\Administrators'
            Access = @()
        }
    }
    
    # Mock Set-Acl
    Mock Set-Acl {
        param($Path, $AclObject)
        
        Write-Verbose "Mock Set-Acl called for path: $Path"
        return @{ Success = $true; Path = $Path }
    }
    
    # Create performance data if requested
    if ($IncludePerformanceData) {
        $performanceData = [ADMockFactory]::CreateLargeDataset($PerformanceUserCount, $PerformanceGroupCount, $true)
        [ADMockFactory]::MockData.Users += $performanceData | Where-Object { $_.ObjectClass -eq 'user' }
        [ADMockFactory]::MockData.Groups += $performanceData | Where-Object { $_.ObjectClass -eq 'group' }
    }
    
    Write-Host "AD mocks created with $([ADMockFactory]::MockData.Users.Count) users, $([ADMockFactory]::MockData.Groups.Count) groups" -ForegroundColor Green
}

function Get-MockOrphanedSIDs {
    <#
    .SYNOPSIS
        Returns mock orphaned SID data for testing
    #>
    [CmdletBinding()]
    param()
    
    return [ADMockFactory]::MockData.SIDs
}

function Reset-ADMocks {
    <#
    .SYNOPSIS
        Resets all AD mock data
    #>
    [CmdletBinding()]
    param()
    
    [ADMockFactory]::Reset()
}

# Functions available for dot-sourcing in tests
# New-ADMocks, Get-MockOrphanedSIDs, Reset-ADMocks
