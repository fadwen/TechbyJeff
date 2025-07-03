[CmdletBinding()]
param(
    [switch]$NoOutput,
    [string]$LogPath = $null
)

# Comprehensive Orphaned SID Generator with Optional Logging
# This script creates various orphaned SID scenarios for testing remediation scripts

# Setup logging based on parameters
$LoggingEnabled = -not $NoOutput
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if ($LoggingEnabled) {
    if ([string]::IsNullOrEmpty($LogPath)) {
        $LogFileName = "OrphanedSID_Generation_$Timestamp.log"
        $LogFilePath = Join-Path (Get-Location) $LogFileName
    } else {
        $LogFilePath = $LogPath
        $LogFileName = Split-Path $LogPath -Leaf
    }
} else {
    $LogFileName = "Console Only (No File Output)"
    $LogFilePath = $null
}

# Function to write to console and optionally to log file
function Write-LogOutput {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = "White"
    )

    # Always write to console with color
    Write-Host $Message -ForegroundColor $Color

    # Write to log file only if logging is enabled
    if ($LoggingEnabled -and $LogFilePath) {
        $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        $LogEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}

# Function for detailed logging (log only, not console)
function Write-DetailedLog {
    param(
        [string]$Message,
        [string]$Level = "DETAIL"
    )

    # Write to log file only if logging is enabled
    if ($LoggingEnabled -and $LogFilePath) {
        $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        $LogEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}

# Function to create secure password
function New-TestPassword {
    return ConvertTo-SecureString "OrphanTest123!" -AsPlainText -Force
}

# Function to wait and verify AD replication
function Wait-ADReplication {
    param([int]$Seconds = 3)
    Write-LogOutput "Waiting $Seconds seconds for AD replication..." -Color Yellow
    Start-Sleep $Seconds
}

# Function to check if delegation already exists
function Test-DelegationExists {
    param(
        [string]$TargetDN,
        [string]$Principal
    )

    try {
        $acl = Get-Acl "AD:\$TargetDN" -ErrorAction SilentlyContinue
        if (-not $acl) { return $false }

        # Extract just the account name from principal (remove DOMAIN\ prefix)
        $accountName = ($Principal -split '\\')[-1]

        foreach ($access in $acl.Access) {
            $identity = $access.IdentityReference.Value
            if ($identity -like "*\$accountName" -or $identity -like "*$accountName*") {
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

# Initialize log file only if logging is enabled
if ($LoggingEnabled) {
    "=" * 80 | Out-File -FilePath $LogFilePath -Encoding UTF8
    "ORPHANED SID GENERATOR LOG" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    "Generation Started: $(Get-Date)" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    "Log File: $LogFileName" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    "Parameters: NoOutput=$NoOutput" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    "=" * 80 | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
}

# Dynamically detect current domain information
try {
    $CurrentDomain = Get-ADDomain -Current LocalComputer
    $Domain = $CurrentDomain.DNSRoot
    $DomainDN = $CurrentDomain.DistinguishedName
    $DomainNetBIOS = $CurrentDomain.NetBIOSName
    $BaseOU = "OU=OrphanedSIDDemo,$DomainDN"

    Write-LogOutput "=== Orphaned SID Generator ===" -Color Cyan
    Write-LogOutput "Detected Domain: $Domain" -Color White
    Write-LogOutput "Domain DN: $DomainDN" -Color White
    Write-LogOutput "NetBIOS Name: $DomainNetBIOS" -Color White
    Write-LogOutput "Base OU: $BaseOU" -Color White
    if ($LoggingEnabled) {
        Write-LogOutput "Log File: $LogFileName" -Color Green
    } else {
        Write-LogOutput "Logging: Disabled (-NoOutput)" -Color Yellow
    }
    Write-LogOutput "Creating comprehensive test scenarios..." -Color Green

    # Log detailed domain information
    Write-DetailedLog "Domain Forest: $($CurrentDomain.Forest)"
    Write-DetailedLog "Domain Functional Level: $($CurrentDomain.DomainMode)"
    Write-DetailedLog "Domain Controllers: $($CurrentDomain.ReplicaDirectoryServers -join ', ')"
}
catch {
    Write-LogOutput "Failed to detect current domain information. Ensure you're running on a domain-joined machine with AD PowerShell module loaded." -Level "ERROR" -Color Red
    Write-LogOutput "Error: $($_.Exception.Message)" -Level "ERROR" -Color Red
    Write-DetailedLog $_.Exception.ToString()
    exit 1
}

# Phase 1: Create Complex Enterprise OU Structure (Idempotent)
Write-LogOutput "`n--- Phase 1: Creating Enterprise OU Structure ---" -Color Magenta

# Create main demo OU if it doesn't exist
try {
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$BaseOU'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "OrphanedSIDDemo" -Path $DomainDN -Description "Enterprise test OU for orphaned SID demonstration"
        Write-LogOutput "Created: $BaseOU" -Color Green
        Write-DetailedLog "Successfully created base OU: $BaseOU"
    } else {
        Write-LogOutput "Already exists: $BaseOU" -Color Yellow
        Write-DetailedLog "Base OU already exists, skipping creation"
    }
}
catch {
    Write-LogOutput "Base OU Creation Error: $($_.Exception.Message)" -Level "WARN" -Color Yellow
    Write-DetailedLog $_.Exception.ToString()
}

# Create complex enterprise OU structure simulating real organization
$EnterpriseOUStructure = @(
    # Regional Structure
    "OU=Corporate,$BaseOU",
    "OU=Regions,$BaseOU",
    "OU=NorthAmerica,OU=Regions,$BaseOU",
    "OU=Europe,OU=Regions,$BaseOU",
    "OU=AsiaPacific,OU=Regions,$BaseOU",

    # Departmental Structure
    "OU=Departments,$BaseOU",
    "OU=IT,OU=Departments,$BaseOU",
    "OU=Finance,OU=Departments,$BaseOU",
    "OU=HR,OU=Departments,$BaseOU",
    "OU=Sales,OU=Departments,$BaseOU",
    "OU=Marketing,OU=Departments,$BaseOU",
    "OU=Operations,OU=Departments,$BaseOU",
    "OU=Legal,OU=Departments,$BaseOU",

    # IT Sub-departments
    "OU=Infrastructure,OU=IT,OU=Departments,$BaseOU",
    "OU=Security,OU=IT,OU=Departments,$BaseOU",
    "OU=Development,OU=IT,OU=Departments,$BaseOU",
    "OU=Support,OU=IT,OU=Departments,$BaseOU",
    "OU=DataCenter,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU",
    "OU=Network,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU",

    # Service Accounts and Resources
    "OU=ServiceAccounts,$BaseOU",
    "OU=DatabaseServices,OU=ServiceAccounts,$BaseOU",
    "OU=WebServices,OU=ServiceAccounts,$BaseOU",
    "OU=BackupServices,OU=ServiceAccounts,$BaseOU",
    "OU=MonitoringServices,OU=ServiceAccounts,$BaseOU",

    # Computer Objects
    "OU=Computers,$BaseOU",
    "OU=Workstations,OU=Computers,$BaseOU",
    "OU=Servers,OU=Computers,$BaseOU",
    "OU=DomainControllers,OU=Servers,OU=Computers,$BaseOU",
    "OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU",
    "OU=DatabaseServers,OU=Servers,OU=Computers,$BaseOU",
    "OU=WebServers,OU=Servers,OU=Computers,$BaseOU",

    # Groups Structure
    "OU=Groups,$BaseOU",
    "OU=SecurityGroups,OU=Groups,$BaseOU",
    "OU=DistributionGroups,OU=Groups,$BaseOU",
    "OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU",
    "OU=ResourceGroups,OU=SecurityGroups,OU=Groups,$BaseOU",

    # Projects and Temporary
    "OU=Projects,$BaseOU",
    "OU=Project2024,OU=Projects,$BaseOU",
    "OU=Project2025,OU=Projects,$BaseOU",
    "OU=Contractors,OU=Projects,$BaseOU",

    # Legacy and Migration
    "OU=Legacy,$BaseOU",
    "OU=Disabled,OU=Legacy,$BaseOU",
    "OU=Migration,OU=Legacy,$BaseOU"
)

Write-DetailedLog "Creating enterprise OU structure with $($EnterpriseOUStructure.Count) organizational units"

foreach ($OU in $EnterpriseOUStructure) {
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OU'" -ErrorAction SilentlyContinue)) {
            $OUName = ($OU -split ',')[0] -replace 'OU=', ''
            $ParentPath = ($OU -split ',', 2)[1]
            New-ADOrganizationalUnit -Name $OUName -Path $ParentPath -Description "Enterprise test OU for delegation scenarios"
            Write-LogOutput "Created: $OU" -Color Green
            Write-DetailedLog "Successfully created OU: $OU"
        } else {
            Write-LogOutput "Already exists: $OU" -Color Yellow
            Write-DetailedLog "OU already exists, skipping: $OU"
        }
    }
    catch {
        Write-LogOutput "OU Creation Error for $OU`: $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

Wait-ADReplication

# Phase 2: Create Enterprise-Scale Security Principals
Write-LogOutput "`n--- Phase 2: Creating Enterprise Security Principals ---" -Color Magenta

$EnterpriseTestPrincipals = @{
    Users = @(
        # IT Department Users
        @{Name="ITDirector"; Sam="it.director"; Description="IT Director - Executive level"; Dept="IT"; Path="OU=IT,OU=Departments,$BaseOU"}
        @{Name="ITManager"; Sam="it.manager"; Description="IT Manager - Management level"; Dept="IT"; Path="OU=IT,OU=Departments,$BaseOU"}
        @{Name="InfrastructureAdmin"; Sam="infra.admin"; Description="Infrastructure Administrator"; Dept="IT"; Path="OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"}
        @{Name="SecurityAdmin"; Sam="sec.admin"; Description="Security Administrator"; Dept="IT"; Path="OU=Security,OU=IT,OU=Departments,$BaseOU"}
        @{Name="NetworkAdmin"; Sam="net.admin"; Description="Network Administrator"; Dept="IT"; Path="OU=Network,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"}
        @{Name="DeveloperLead"; Sam="dev.lead"; Description="Development Team Lead"; Dept="IT"; Path="OU=Development,OU=IT,OU=Departments,$BaseOU"}
        @{Name="SupportManager"; Sam="support.mgr"; Description="IT Support Manager"; Dept="IT"; Path="OU=Support,OU=IT,OU=Departments,$BaseOU"}
        @{Name="DataCenterTech"; Sam="dc.tech"; Description="Data Center Technician"; Dept="IT"; Path="OU=DataCenter,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"}

        # Service Accounts
        @{Name="SQLServiceAccount"; Sam="svc.sql"; Description="SQL Server Service Account"; Dept="Services"; Path="OU=DatabaseServices,OU=ServiceAccounts,$BaseOU"}
        @{Name="WebServiceAccount"; Sam="svc.web"; Description="Web Application Service Account"; Dept="Services"; Path="OU=WebServices,OU=ServiceAccounts,$BaseOU"}
        @{Name="BackupServiceAccount"; Sam="svc.backup"; Description="Backup System Service Account"; Dept="Services"; Path="OU=BackupServices,OU=ServiceAccounts,$BaseOU"}
        @{Name="MonitoringServiceAccount"; Sam="svc.monitor"; Description="Monitoring System Service Account"; Dept="Services"; Path="OU=MonitoringServices,OU=ServiceAccounts,$BaseOU"}

        # Business Department Users
        @{Name="FinanceManager"; Sam="fin.manager"; Description="Finance Manager"; Dept="Finance"; Path="OU=Finance,OU=Departments,$BaseOU"}
        @{Name="HRDirector"; Sam="hr.director"; Description="HR Director"; Dept="HR"; Path="OU=HR,OU=Departments,$BaseOU"}
        @{Name="SalesDirector"; Sam="sales.director"; Description="Sales Director"; Dept="Sales"; Path="OU=Sales,OU=Departments,$BaseOU"}
        @{Name="MarketingManager"; Sam="mkt.manager"; Description="Marketing Manager"; Dept="Marketing"; Path="OU=Marketing,OU=Departments,$BaseOU"}
        @{Name="OperationsManager"; Sam="ops.manager"; Description="Operations Manager"; Dept="Operations"; Path="OU=Operations,OU=Departments,$BaseOU"}
        @{Name="LegalCounsel"; Sam="legal.counsel"; Description="Legal Counsel"; Dept="Legal"; Path="OU=Legal,OU=Departments,$BaseOU"}

        # Regional Users
        @{Name="NARegionalManager"; Sam="na.manager"; Description="North America Regional Manager"; Dept="Regional"; Path="OU=NorthAmerica,OU=Regions,$BaseOU"}
        @{Name="EURegionalManager"; Sam="eu.manager"; Description="Europe Regional Manager"; Dept="Regional"; Path="OU=Europe,OU=Regions,$BaseOU"}
        @{Name="APACRegionalManager"; Sam="apac.manager"; Description="Asia Pacific Regional Manager"; Dept="Regional"; Path="OU=AsiaPacific,OU=Regions,$BaseOU"}

        # Project Users
        @{Name="ProjectManager2024"; Sam="pm.2024"; Description="Project Manager 2024"; Dept="Projects"; Path="OU=Project2024,OU=Projects,$BaseOU"}
        @{Name="ProjectManager2025"; Sam="pm.2025"; Description="Project Manager 2025"; Dept="Projects"; Path="OU=Project2025,OU=Projects,$BaseOU"}
        @{Name="ContractorLead"; Sam="contractor.lead"; Description="Contractor Team Lead"; Dept="Projects"; Path="OU=Contractors,OU=Projects,$BaseOU"}

        # Legacy/Migration Users
        @{Name="MigrationAdmin"; Sam="migration.admin"; Description="Migration Administrator"; Dept="Legacy"; Path="OU=Migration,OU=Legacy,$BaseOU"}
        @{Name="LegacyAdmin"; Sam="legacy.admin"; Description="Legacy System Administrator"; Dept="Legacy"; Path="OU=Disabled,OU=Legacy,$BaseOU"}
    )

    Groups = @(
        # IT Security Groups
        @{Name="ITAdministrators"; Scope="Global"; Description="IT Administrators Group"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="InfrastructureAdmins"; Scope="Global"; Description="Infrastructure Administrators"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="SecurityAdmins"; Scope="Global"; Description="Security Administrators"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="NetworkAdmins"; Scope="Global"; Description="Network Administrators"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="DevelopmentTeam"; Scope="Global"; Description="Development Team Access"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="SupportTeam"; Scope="Global"; Description="IT Support Team"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Application Groups
        @{Name="DatabaseAdmins"; Scope="DomainLocal"; Description="Database Administrators"; Path="OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="WebAppAdmins"; Scope="DomainLocal"; Description="Web Application Administrators"; Path="OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="BackupOperators"; Scope="DomainLocal"; Description="Backup System Operators"; Path="OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="MonitoringAdmins"; Scope="DomainLocal"; Description="System Monitoring Administrators"; Path="OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Business Groups
        @{Name="FinanceStaff"; Scope="Global"; Description="Finance Department Staff"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="HRStaff"; Scope="Global"; Description="Human Resources Staff"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="SalesTeam"; Scope="Global"; Description="Sales Team Members"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="MarketingTeam"; Scope="Global"; Description="Marketing Team Members"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="OperationsStaff"; Scope="Global"; Description="Operations Staff"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="LegalTeam"; Scope="Global"; Description="Legal Department"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Regional Groups
        @{Name="NorthAmericaManagers"; Scope="Universal"; Description="North America Management"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="EuropeManagers"; Scope="Universal"; Description="Europe Management"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="AsiaPacificManagers"; Scope="Universal"; Description="Asia Pacific Management"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Resource Groups
        @{Name="FileServerAccess"; Scope="DomainLocal"; Description="File Server Access Group"; Path="OU=ResourceGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="PrinterAccess"; Scope="DomainLocal"; Description="Printer Access Group"; Path="OU=ResourceGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="VPNAccess"; Scope="DomainLocal"; Description="VPN Access Group"; Path="OU=ResourceGroups,OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Project Groups
        @{Name="Project2024Team"; Scope="Global"; Description="Project 2024 Team Members"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="Project2025Team"; Scope="Global"; Description="Project 2025 Team Members"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}
        @{Name="ContractorAccess"; Scope="DomainLocal"; Description="Contractor Access Group"; Path="OU=SecurityGroups,OU=Groups,$BaseOU"}

        # Distribution Groups
        @{Name="AllStaff"; Scope="Universal"; Description="All Staff Distribution List"; Path="OU=DistributionGroups,OU=Groups,$BaseOU"}
        @{Name="ITAnnouncements"; Scope="Universal"; Description="IT Announcements Distribution"; Path="OU=DistributionGroups,OU=Groups,$BaseOU"}
        @{Name="ExecutiveTeam"; Scope="Universal"; Description="Executive Team Distribution"; Path="OU=DistributionGroups,OU=Groups,$BaseOU"}
    )

    Computers = @(
        # Domain Controllers
        @{Name="DC01-Primary"; Description="Primary Domain Controller"; Path="OU=DomainControllers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="DC02-Secondary"; Description="Secondary Domain Controller"; Path="OU=DomainControllers,OU=Servers,OU=Computers,$BaseOU"}

        # Application Servers
        @{Name="SQL01-Production"; Description="Production SQL Server"; Path="OU=DatabaseServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="SQL02-Development"; Description="Development SQL Server"; Path="OU=DatabaseServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="WEB01-Production"; Description="Production Web Server"; Path="OU=WebServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="WEB02-Staging"; Description="Staging Web Server"; Path="OU=WebServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="APP01-Business"; Description="Business Application Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="APP02-Finance"; Description="Finance Application Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}

        # Infrastructure Servers
        @{Name="BACKUP01"; Description="Primary Backup Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="MONITOR01"; Description="System Monitoring Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="FILE01"; Description="Primary File Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}
        @{Name="PRINT01"; Description="Print Server"; Path="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"}

        # Workstations
        @{Name="WS-IT-001"; Description="IT Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
        @{Name="WS-FIN-001"; Description="Finance Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
        @{Name="WS-HR-001"; Description="HR Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
        @{Name="WS-SALES-001"; Description="Sales Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
        @{Name="WS-MKT-001"; Description="Marketing Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
        @{Name="WS-OPS-001"; Description="Operations Department Workstation"; Path="OU=Workstations,OU=Computers,$BaseOU"}
    )
}

Write-DetailedLog "Creating enterprise security principals: $($EnterpriseTestPrincipals.Users.Count) users, $($EnterpriseTestPrincipals.Groups.Count) groups, $($EnterpriseTestPrincipals.Computers.Count) computers"

# Create Users (Idempotent)
foreach ($User in $EnterpriseTestPrincipals.Users) {
    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$($User.Sam)'" -ErrorAction SilentlyContinue)) {
            $UserParams = @{
                Name = $User.Name
                SamAccountName = $User.Sam
                UserPrincipalName = "$($User.Sam)@$Domain"
                AccountPassword = New-TestPassword
                Enabled = $true
                Path = $User.Path
                Description = $User.Description
                Department = $User.Dept
            }
            New-ADUser @UserParams
            Write-LogOutput "Created User: $($User.Name) ($($User.Dept))" -Color Green
            Write-DetailedLog "User created - Name: $($User.Name), SamAccount: $($User.Sam), Dept: $($User.Dept), Path: $($User.Path)"
        } else {
            Write-LogOutput "User already exists: $($User.Name)" -Color Yellow
            Write-DetailedLog "User already exists, skipping: $($User.Name)"
        }
    }
    catch {
        Write-LogOutput "User Creation Error for $($User.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

# Create Groups (Idempotent)
foreach ($Group in $EnterpriseTestPrincipals.Groups) {
    try {
        if (-not (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue)) {
            $GroupParams = @{
                Name = $Group.Name
                GroupScope = $Group.Scope
                GroupCategory = "Security"
                Path = $Group.Path
                Description = $Group.Description
            }
            New-ADGroup @GroupParams
            Write-LogOutput "Created Group: $($Group.Name) ($($Group.Scope))" -Color Green
            Write-DetailedLog "Group created - Name: $($Group.Name), Scope: $($Group.Scope), Path: $($Group.Path)"
        } else {
            Write-LogOutput "Group already exists: $($Group.Name)" -Color Yellow
            Write-DetailedLog "Group already exists, skipping: $($Group.Name)"
        }
    }
    catch {
        Write-LogOutput "Group Creation Error for $($Group.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

# Create Computers (Idempotent)
foreach ($Computer in $EnterpriseTestPrincipals.Computers) {
    try {
        if (-not (Get-ADComputer -Filter "Name -eq '$($Computer.Name)'" -ErrorAction SilentlyContinue)) {
            $ComputerParams = @{
                Name = $Computer.Name
                Path = $Computer.Path
                Description = $Computer.Description
                Enabled = $true
            }
            New-ADComputer @ComputerParams
            Write-LogOutput "Created Computer: $($Computer.Name)" -Color Green
            Write-DetailedLog "Computer created - Name: $($Computer.Name), Path: $($Computer.Path)"
        } else {
            Write-LogOutput "Computer already exists: $($Computer.Name)" -Color Yellow
            Write-DetailedLog "Computer already exists, skipping: $($Computer.Name)"
        }
    }
    catch {
        Write-LogOutput "Computer Creation Error for $($Computer.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

Wait-ADReplication -Seconds 5

# Phase 3: Apply Complex Enterprise Delegations (Idempotent)
Write-LogOutput "`n--- Phase 3: Applying Enterprise-Scale Delegations ---" -Color Magenta

$EnterpriseExplicitDelegations = @(
    # Executive Level Delegations
    @{Target="$BaseOU"; Principal="$DomainNetBIOS\it.director"; Rights="GA"; Description="IT Director - Full Control on entire structure"}
    @{Target="OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\hr.director"; Rights="CCDC"; Description="HR Director - Manage all departments"}
    @{Target="OU=Corporate,$BaseOU"; Principal="$DomainNetBIOS\ExecutiveTeam"; Rights="GA"; Description="Executive team access to corporate OU"}

    # IT Department Delegations
    @{Target="OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\it.manager"; Rights="GA"; Description="IT Manager - Full Control over IT department"}
    @{Target="OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\infra.admin"; Rights="GA"; Description="Infrastructure Admin - Full infrastructure control"}
    @{Target="OU=Security,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\sec.admin"; Rights="GA"; Description="Security Admin - Security OU control"}
    @{Target="OU=Network,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\net.admin"; Rights="GA"; Description="Network Admin - Network infrastructure"}
    @{Target="OU=Development,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\dev.lead"; Rights="CCDC"; Description="Dev Lead - Development team management"}
    @{Target="OU=Support,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\support.mgr"; Rights="CCDC"; Description="Support Manager - Support team management"}
    @{Target="OU=DataCenter,OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\dc.tech"; Rights="CC"; Description="DC Tech - Data center access"}

    # Service Account Delegations
    @{Target="OU=DatabaseServers,OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\svc.sql"; Rights="GA"; Description="SQL Service - Database servers management"}
    @{Target="OU=WebServers,OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\svc.web"; Rights="RPWP"; Description="Web Service - Web servers management"}
    @{Target="OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\svc.backup"; Rights="RP"; Description="Backup Service - Server backup access"}
    @{Target="OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\svc.monitor"; Rights="RP"; Description="Monitoring Service - All computers read access"}

    # Business Department Delegations
    @{Target="OU=Finance,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\fin.manager"; Rights="GA"; Description="Finance Manager - Finance department control"}
    @{Target="OU=HR,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\hr.director"; Rights="GA"; Description="HR Director - HR department control"}
    @{Target="OU=Sales,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\sales.director"; Rights="CCDC"; Description="Sales Director - Sales team management"}
    @{Target="OU=Marketing,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\mkt.manager"; Rights="CCDC"; Description="Marketing Manager - Marketing team management"}
    @{Target="OU=Operations,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\ops.manager"; Rights="CCDC"; Description="Operations Manager - Operations management"}
    @{Target="OU=Legal,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\legal.counsel"; Rights="RPWP"; Description="Legal Counsel - Legal department access"}

    # Regional Delegations
    @{Target="OU=NorthAmerica,OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\na.manager"; Rights="GA"; Description="NA Manager - North America region control"}
    @{Target="OU=Europe,OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\eu.manager"; Rights="GA"; Description="EU Manager - Europe region control"}
    @{Target="OU=AsiaPacific,OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\apac.manager"; Rights="GA"; Description="APAC Manager - Asia Pacific region control"}

    # Project Delegations
    @{Target="OU=Project2024,OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\pm.2024"; Rights="GA"; Description="Project Manager 2024 - Project control"}
    @{Target="OU=Project2025,OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\pm.2025"; Rights="GA"; Description="Project Manager 2025 - Project control"}
    @{Target="OU=Contractors,OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\contractor.lead"; Rights="CCDC"; Description="Contractor Lead - Contractor management"}

    # Group-Based Delegations
    @{Target="OU=SecurityGroups,OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\ITAdministrators"; Rights="GA"; Description="IT Admins - Security groups management"}
    @{Target="OU=ApplicationGroups,OU=SecurityGroups,OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\InfrastructureAdmins"; Rights="GA"; Description="Infrastructure Admins - Application groups"}
    @{Target="OU=ResourceGroups,OU=SecurityGroups,OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\SecurityAdmins"; Rights="CCDC"; Description="Security Admins - Resource groups"}
    @{Target="OU=DistributionGroups,OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\HRStaff"; Rights="CCDC"; Description="HR Staff - Distribution groups management"}

    # Computer Delegations
    @{Target="OU=DomainControllers,OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\DC01-Primary$"; Rights="CC"; Description="Primary DC - Domain controller management"}
    @{Target="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\SQL01-Production$"; Rights="CC"; Description="SQL Server - Application server access"}
    @{Target="OU=Workstations,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\WS-IT-001$"; Rights="RP"; Description="IT Workstation - Workstation read access"}

    # Advanced Group Delegations
    @{Target="OU=DatabaseServices,OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\DatabaseAdmins"; Rights="GA"; Description="Database Admins - Database service accounts"}
    @{Target="OU=WebServices,OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\WebAppAdmins"; Rights="GA"; Description="Web App Admins - Web service accounts"}
    @{Target="OU=BackupServices,OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\BackupOperators"; Rights="RPWP"; Description="Backup Operators - Backup service accounts"}
    @{Target="OU=MonitoringServices,OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\MonitoringAdmins"; Rights="RPWP"; Description="Monitoring Admins - Monitoring service accounts"}

    # Cross-Departmental Delegations
    @{Target="OU=Finance,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\APP02-Finance$"; Rights="CC"; Description="Finance App Server - Finance department access"}
    @{Target="OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\Project2024Team"; Rights="CCDC"; Description="Project 2024 Team - Projects OU access"}
    @{Target="OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\Project2025Team"; Rights="CCDC"; Description="Project 2025 Team - Projects OU access"}

    # Legacy and Migration Delegations
    @{Target="OU=Migration,OU=Legacy,$BaseOU"; Principal="$DomainNetBIOS\migration.admin"; Rights="GA"; Description="Migration Admin - Migration OU control"}
    @{Target="OU=Disabled,OU=Legacy,$BaseOU"; Principal="$DomainNetBIOS\legacy.admin"; Rights="RPWP"; Description="Legacy Admin - Disabled objects access"}
)

Write-DetailedLog "Applying $($EnterpriseExplicitDelegations.Count) explicit delegations across enterprise structure"

foreach ($Delegation in $EnterpriseExplicitDelegations) {
    try {
        # Check if delegation already exists
        if (Test-DelegationExists -TargetDN $Delegation.Target -Principal $Delegation.Principal) {
            Write-LogOutput "Delegation already exists: $($Delegation.Description)" -Color Yellow
            continue
        }

        $cmd = "dsacls `"$($Delegation.Target)`" /G `"$($Delegation.Principal):$($Delegation.Rights)`""
        Write-LogOutput "Applying: $($Delegation.Description)" -Color Yellow
        Write-DetailedLog "Delegation command: $cmd"

        Invoke-Expression $cmd

        if ($LASTEXITCODE -eq 0) {
            Write-LogOutput " Successfully applied delegation" -Color Green
            Write-DetailedLog "Successfully applied: $($Delegation.Description)"
        } else {
            Write-LogOutput " Failed to apply delegation (Exit Code: $LASTEXITCODE)" -Level "WARN" -Color Yellow
            Write-DetailedLog "Failed delegation: $($Delegation.Description) - Exit Code: $LASTEXITCODE"
        }
    }
    catch {
        Write-LogOutput "Delegation Error: $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

Wait-ADReplication -Seconds 3

# Phase 4: Apply Complex Inherited Delegations (Idempotent)
Write-LogOutput "`n--- Phase 4: Applying Enterprise Inherited Delegations ---" -Color Magenta

$EnterpriseInheritedDelegations = @(
    # Top-level inheritance affecting multiple child OUs
    @{Target="OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\it.director"; Rights="RP"; Description="IT Director read access inheriting to all departments"}
    @{Target="OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\ExecutiveTeam"; Rights="RPWP"; Description="Executive team access inheriting to all regions"}
    @{Target="OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\ITAdministrators"; Rights="CCDC"; Description="IT Admins group management inheriting to all group OUs"}
    @{Target="OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\InfrastructureAdmins"; Rights="RP"; Description="Infrastructure read access inheriting to all computers"}

    # Department-level inheritance
    @{Target="OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\it.manager"; Rights="CCDC"; Description="IT Manager create/delete inheriting to IT sub-departments"}
    @{Target="OU=Infrastructure,OU=IT,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\infra.admin"; Rights="RPWP"; Description="Infrastructure admin inheriting to network/datacenter"}

    # Service account inheritance
    @{Target="OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\SecurityAdmins"; Rights="RP"; Description="Security team read access to all service accounts"}
    @{Target="OU=ServiceAccounts,$BaseOU"; Principal="$DomainNetBIOS\svc.monitor"; Rights="RP"; Description="Monitoring service read access to all service accounts"}

    # Server inheritance patterns
    @{Target="OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\NetworkAdmins"; Rights="RP"; Description="Network admins read access to all servers"}
    @{Target="OU=ApplicationServers,OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\DevelopmentTeam"; Rights="RP"; Description="Development team read access to application servers"}

    # Cross-functional inheritance
    @{Target="OU=Projects,$BaseOU"; Principal="$DomainNetBIOS\ContractorAccess"; Rights="RP"; Description="Contractor read access inheriting to all projects"}
    @{Target="OU=Legacy,$BaseOU"; Principal="$DomainNetBIOS\migration.admin"; Rights="RPWP"; Description="Migration admin access inheriting to legacy OUs"}

    # Group-based inheritance scenarios
    @{Target="OU=SecurityGroups,OU=Groups,$BaseOU"; Principal="$DomainNetBIOS\HRStaff"; Rights="RP"; Description="HR read access to security groups (for compliance)"}
    @{Target="$BaseOU"; Principal="$DomainNetBIOS\MonitoringAdmins"; Rights="RP"; Description="Monitoring read access inheriting to entire structure"}
    @{Target="$BaseOU"; Principal="$DomainNetBIOS\BackupOperators"; Rights="RP"; Description="Backup operators read access inheriting everywhere"}

    # Computer account inheritance
    @{Target="OU=Servers,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\MONITOR01$"; Rights="RP"; Description="Monitoring server read access to all servers"}
    @{Target="OU=Workstations,OU=Computers,$BaseOU"; Principal="$DomainNetBIOS\WS-IT-001$"; Rights="RP"; Description="IT workstation read access to all workstations"}

    # Regional inheritance with complex nesting
    @{Target="OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\NorthAmericaManagers"; Rights="RP"; Description="NA managers read access to all regions"}
    @{Target="OU=Regions,$BaseOU"; Principal="$DomainNetBIOS\EuropeManagers"; Rights="RP"; Description="EU managers read access to all regions"}

    # Department inheritance affecting business operations
    @{Target="OU=Finance,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\FinanceStaff"; Rights="RPWP"; Description="Finance staff access (no child OUs but inheritance ready)"}
    @{Target="OU=Sales,OU=Departments,$BaseOU"; Principal="$DomainNetBIOS\SalesTeam"; Rights="CCDC"; Description="Sales team management (inheritance ready for expansion)"}
)

Write-DetailedLog "Applying $($EnterpriseInheritedDelegations.Count) inherited delegations across enterprise structure"

foreach ($Delegation in $EnterpriseInheritedDelegations) {
    try {
        # Check if delegation already exists
        if (Test-DelegationExists -TargetDN $Delegation.Target -Principal $Delegation.Principal) {
            Write-LogOutput "Inherited delegation already exists: $($Delegation.Description)" -Color Yellow
            continue
        }

        # Apply with inheritance (CI = Container Inherit, OI = Object Inherit)
        $cmd = "dsacls `"$($Delegation.Target)`" /G `"$($Delegation.Principal):$($Delegation.Rights)`" /I:T"
        Write-LogOutput "Applying Inherited: $($Delegation.Description)" -Color Yellow
        Write-DetailedLog "Inherited delegation command: $cmd"

        Invoke-Expression $cmd

        if ($LASTEXITCODE -eq 0) {
            Write-LogOutput " Successfully applied inherited delegation" -Color Green
            Write-DetailedLog "Successfully applied inherited: $($Delegation.Description)"
        } else {
            Write-LogOutput " Failed to apply inherited delegation (Exit Code: $LASTEXITCODE)" -Level "WARN" -Color Yellow
            Write-DetailedLog "Failed inherited delegation: $($Delegation.Description) - Exit Code: $LASTEXITCODE"
        }
    }
    catch {
        Write-LogOutput "Inherited Delegation Error: $($_.Exception.Message)" -Level "WARN" -Color Yellow
        Write-DetailedLog $_.Exception.ToString()
    }
}

Wait-ADReplication -Seconds 5

# Phase 5: Verification Before Orphaning
Write-LogOutput "`n--- Phase 5: Verification Before Orphaning ---" -Color Magenta

function Show-CurrentDelegations {
    param($TargetDN)

    Write-LogOutput "`nCurrent delegations for: $TargetDN" -Color Cyan
    Write-DetailedLog "Checking delegations for: $TargetDN"
    try {
        $result = & dsacls $TargetDN
        $enterpriseDelegations = $result | Where-Object { $_ -match "$DomainNetBIOS\\" -and $_ -notmatch "Domain Admins" -and $_ -notmatch "Enterprise Admins" -and $_ -notmatch "Exchange" -and $_ -notmatch "MSOL" -and $_ -notmatch "pGMSA" }

        if ($enterpriseDelegations) {
            $enterpriseDelegations | ForEach-Object {
                Write-LogOutput "  $_" -Color Gray
                Write-DetailedLog "  Delegation found: $_"
            }
        } else {
            Write-LogOutput "  No enterprise test delegations found (only system/inherited)" -Color Gray
            Write-DetailedLog "  No enterprise delegations found for $TargetDN"
        }
    }
    catch {
        Write-LogOutput "Could not retrieve delegations for $TargetDN" -Level "WARN" -Color Yellow
        Write-DetailedLog "Error retrieving delegations for $TargetDN`: $($_.Exception.Message)"
    }
}

# Show current state for key OUs
$VerifyTargets = @(
    $BaseOU,
    "OU=Departments,$BaseOU",
    "OU=IT,OU=Departments,$BaseOU",
    "OU=ServiceAccounts,$BaseOU",
    "OU=Computers,$BaseOU"
)

foreach ($Target in $VerifyTargets) {
    Show-CurrentDelegations $Target
}

# Phase 6: Create Orphaned SIDs (Soft and Hard Deletion)
Write-LogOutput "`n--- Phase 6: Creating Orphaned SIDs ---" -Color Red
Write-LogOutput "This phase will create two types of orphaned SIDs:" -Color Yellow
Write-LogOutput "   Soft Delete (Recoverable): Objects moved to AD Recycle Bin" -Color Cyan
Write-LogOutput "   Hard Delete (Permanent): Objects completely removed from AD" -Color Red

# Check if AD Recycle Bin is enabled
$RecycleBinEnabled = $false
try {
    $adRecycleBin = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
    if ($adRecycleBin.EnabledScopes.Count -gt 0) {
        $RecycleBinEnabled = $true
        Write-LogOutput " AD Recycle Bin is enabled - soft deletes will be recoverable" -Color Green
    } else {
        Write-LogOutput " AD Recycle Bin is NOT enabled - all deletes will be hard deletes" -Color Yellow
    }
}
catch {
    Write-LogOutput " Could not determine AD Recycle Bin status" -Color Yellow
}

Write-LogOutput "`nWARNING: About to delete security principals to create orphaned SIDs!" -Color Red

$ConfirmOrphan = Read-Host "Continue with orphaning process? (y/N)"
if ($ConfirmOrphan -ne 'y' -and $ConfirmOrphan -ne 'Y') {
    Write-LogOutput "Orphaning process cancelled. Test principals remain for manual testing." -Color Yellow
    exit
}

# Split enterprise principals into soft delete and hard delete groups for realistic scenarios
$SoftDeletePrincipals = @{
    Users = $EnterpriseTestPrincipals.Users[0..11]  # First 12 users for soft delete (recoverable)
    Groups = $EnterpriseTestPrincipals.Groups[0..13]  # First 14 groups for soft delete
    Computers = $EnterpriseTestPrincipals.Computers[0..8]  # First 9 computers for soft delete
}

$HardDeletePrincipals = @{
    Users = $EnterpriseTestPrincipals.Users[12..24]  # Last 13 users for hard delete (permanent)
    Groups = $EnterpriseTestPrincipals.Groups[14..27]  # Last 14 groups for hard delete
    Computers = $EnterpriseTestPrincipals.Computers[9..17]  # Last 9 computers for hard delete
}

Write-LogOutput "`nPhase 6a: Soft Delete (Recoverable) - Creating orphaned SIDs..." -Color Cyan

# Soft Delete Users
foreach ($User in $SoftDeletePrincipals.Users) {
    try {
        if (Get-ADUser -Filter "SamAccountName -eq '$($User.Sam)'" -ErrorAction SilentlyContinue) {
            Remove-ADUser -Identity $User.Sam -Confirm:$false
            Write-LogOutput " Soft Deleted User: $($User.Name) (SID orphaned but recoverable)" -Color Cyan
        } else {
            Write-LogOutput "User already deleted: $($User.Name)" -Color Gray
        }
    }
    catch {
        Write-LogOutput "Failed to soft delete user $($User.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
    }
}

# Soft Delete Groups
foreach ($Group in $SoftDeletePrincipals.Groups) {
    try {
        if (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue) {
            Remove-ADGroup -Identity $Group.Name -Confirm:$false
            Write-LogOutput " Soft Deleted Group: $($Group.Name) (SID orphaned but recoverable)" -Color Cyan
        } else {
            Write-LogOutput "Group already deleted: $($Group.Name)" -Color Gray
        }
    }
    catch {
        Write-LogOutput "Failed to soft delete group $($Group.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
    }
}

# Soft Delete Computers
foreach ($Computer in $SoftDeletePrincipals.Computers) {
    try {
        if (Get-ADComputer -Filter "Name -eq '$($Computer.Name)'" -ErrorAction SilentlyContinue) {
            Remove-ADComputer -Identity $Computer.Name -Confirm:$false
            Write-LogOutput " Soft Deleted Computer: $($Computer.Name) (SID orphaned but recoverable)" -Color Cyan
        } else {
            Write-LogOutput "Computer already deleted: $($Computer.Name)" -Color Gray
        }
    }
    catch {
        Write-LogOutput "Failed to soft delete computer $($Computer.Name): $($_.Exception.Message)" -Level "WARN" -Color Yellow
    }
}

Wait-ADReplication -Seconds 3

Write-LogOutput "`nPhase 6b: Hard Delete (Permanent) - Creating permanently orphaned SIDs..." -Color Red

# Function to perform hard delete
function Remove-ADObjectPermanently {
    param(
        [string]$Identity,
        [string]$ObjectClass,
        [string]$DisplayName
    )

    try {
        # First, perform normal deletion
        switch ($ObjectClass) {
            "User" {
                Remove-ADUser -Identity $Identity -Confirm:$false
                Write-LogOutput "  Step 1: Moved $DisplayName to recycle bin" -Color Yellow
            }
            "Group" {
                Remove-ADGroup -Identity $Identity -Confirm:$false
                Write-LogOutput "  Step 1: Moved $DisplayName to recycle bin" -Color Yellow
            }
            "Computer" {
                Remove-ADComputer -Identity $Identity -Confirm:$false
                Write-LogOutput "  Step 1: Moved $DisplayName to recycle bin" -Color Yellow
            }
        }

        Start-Sleep 2

        # If Recycle Bin is enabled, permanently delete from recycle bin
        if ($RecycleBinEnabled) {
            try {
                # Find the deleted object in recycle bin
                $deletedObject = Get-ADObject -Filter "Name -like '*$Identity*'" -IncludeDeletedObjects -ErrorAction SilentlyContinue |
                    Where-Object { $_.ObjectClass -eq $ObjectClass -and $_.Deleted -eq $true } |
                    Select-Object -First 1

                if ($deletedObject) {
                    Remove-ADObject -Identity $deletedObject.ObjectGUID -IncludeDeletedObjects -Confirm:$false
                    Write-LogOutput "  Step 2: Permanently deleted $DisplayName from AD (HARD DELETE)" -Color Red
                    Write-LogOutput " Hard Deleted: $DisplayName (SID permanently orphaned)" -Color Red
                } else {
                    Write-LogOutput "Could not find $DisplayName in recycle bin for hard deletion" -Level "WARN" -Color Yellow
                }
            }
            catch {
                Write-LogOutput "Failed to hard delete $DisplayName from recycle bin: $($_.Exception.Message)" -Level "WARN" -Color Yellow
            }
        } else {
            Write-LogOutput " Hard Deleted: $DisplayName (SID permanently orphaned - no recycle bin)" -Color Red
        }
    }
    catch {
        Write-LogOutput "Failed to delete $DisplayName`: $($_.Exception.Message)" -Level "WARN" -Color Yellow
    }
}

# Hard Delete Users
foreach ($User in $HardDeletePrincipals.Users) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($User.Sam)'" -ErrorAction SilentlyContinue) {
        Write-LogOutput "Hard deleting User: $($User.Name)" -Color Red
        Remove-ADObjectPermanently -Identity $User.Sam -ObjectClass "User" -DisplayName $User.Name
    } else {
        Write-LogOutput "User already deleted: $($User.Name)" -Color Gray
    }
}

# Hard Delete Groups
foreach ($Group in $HardDeletePrincipals.Groups) {
    if (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue) {
        Write-LogOutput "Hard deleting Group: $($Group.Name)" -Color Red
        Remove-ADObjectPermanently -Identity $Group.Name -ObjectClass "Group" -DisplayName $Group.Name
    } else {
        Write-LogOutput "Group already deleted: $($Group.Name)" -Color Gray
    }
}

# Hard Delete Computers
foreach ($Computer in $HardDeletePrincipals.Computers) {
    if (Get-ADComputer -Filter "Name -eq '$($Computer.Name)'" -ErrorAction SilentlyContinue) {
        Write-LogOutput "Hard deleting Computer: $($Computer.Name)" -Color Red
        Remove-ADObjectPermanently -Identity $Computer.Name -ObjectClass "Computer" -DisplayName $Computer.Name
    } else {
        Write-LogOutput "Computer already deleted: $($Computer.Name)" -Color Gray
    }
}

Wait-ADReplication -Seconds 5

# Phase 7: Final Verification - Show Orphaned SIDs
Write-LogOutput "`n--- Phase 7: Final Verification - Orphaned SIDs Created ---" -Color Magenta

function Show-OrphanedSIDs {
    param($TargetDN)

    Write-LogOutput "`nOrphaned SIDs in: $TargetDN" -Color Red
    try {
        $acl = Get-Acl "AD:\$TargetDN"
        $orphanCount = 0

        foreach ($access in $acl.Access) {
            $sid = $access.IdentityReference

            # Skip well-known SIDs
            if ($sid -like "S-1-5-32-*" -or $sid -like "NT AUTHORITY\*" -or $sid -like "BUILTIN\*" -or $sid -like "*\Domain Admins" -or $sid -like "*\Enterprise Admins") {
                continue
            }

            try {
                $resolved = $sid.Translate([System.Security.Principal.NTAccount])
            }
            catch {
                Write-LogOutput "  ORPHANED SID: $sid" -Color Red
                Write-LogOutput "    Rights: $($access.ActiveDirectoryRights)" -Color Yellow
                Write-LogOutput "    Type: $($access.AccessControlType)" -Color Yellow
                Write-LogOutput "    Inheritance: $($access.InheritanceType)" -Color Yellow
                $orphanCount++
            }
        }

        if ($orphanCount -eq 0) {
            Write-LogOutput "  No orphaned SIDs found" -Color Green
        } else {
            Write-LogOutput "  Total orphaned SIDs: $orphanCount" -Color Red
        }
    }
    catch {
        Write-LogOutput "Could not check orphaned SIDs for $TargetDN" -Level "WARN" -Color Yellow
    }
}

# Check all target OUs for orphaned SIDs
$CheckTargets = @(
    $BaseOU,
    "OU=Departments,$BaseOU",
    "OU=IT,OU=Departments,$BaseOU",
    "OU=Infrastructure,OU=IT,OU=Departments,$BaseOU",
    "OU=Security,OU=IT,OU=Departments,$BaseOU",
    "OU=ServiceAccounts,$BaseOU",
    "OU=DatabaseServices,OU=ServiceAccounts,$BaseOU",
    "OU=Computers,$BaseOU",
    "OU=Servers,OU=Computers,$BaseOU",
    "OU=Groups,$BaseOU",
    "OU=SecurityGroups,OU=Groups,$BaseOU",
    "OU=Projects,$BaseOU",
    "OU=Regions,$BaseOU"
)

foreach ($Target in $CheckTargets) {
    Show-OrphanedSIDs $Target
}

# Summary for console
Write-LogOutput "`n=== ORPHANED SID GENERATION COMPLETE ===" -Color Cyan
Write-LogOutput " Generated comprehensive enterprise test environment" -Color Green
Write-LogOutput " Created both recoverable and permanent orphaned SIDs" -Color Green
Write-LogOutput " Applied complex enterprise-scale delegations" -Color Green

if ($LoggingEnabled) {
    Write-LogOutput " Full report saved to: $LogFileName" -Color Yellow
} else {
    Write-LogOutput " Console-only mode (no log file generated)" -Color Yellow
}

Write-LogOutput "`nREADY FOR TESTING:" -Color White
Write-LogOutput "- 35+ Soft orphaned SIDs (recoverable)" -Color Cyan
Write-LogOutput "- 36+ Hard orphaned SIDs (permanent)" -Color Red
Write-LogOutput "- Complex enterprise delegation scenarios" -Color Gray
if ($LoggingEnabled) {
    Write-LogOutput "- Comprehensive logging completed" -Color Green
} else {
    Write-LogOutput "- Console output only" -Color Yellow
}

Write-LogOutput "`nYour remediation script can now be tested against these orphaned SIDs!" -Color Green
Write-LogOutput "Use 'dsacls' or PowerShell ACL cmdlets to verify the orphaned SIDs before and after remediation." -Color Yellow

# Recovery instructions for soft-deleted objects
if ($RecycleBinEnabled) {
    Write-LogOutput "`n--- Recovery Instructions for Soft-Deleted Objects ---" -Color Magenta
    Write-LogOutput "To restore soft-deleted objects (for re-testing):" -Color White
    Write-LogOutput "# Restore enterprise test users:" -Color Gray
    Write-LogOutput "Get-ADObject -Filter 'Name -like `"*director*`" -or Name -like `"*manager*`" -or Name -like `"*admin*`"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject" -Color Gray
    Write-LogOutput "# Restore enterprise test groups:" -Color Gray
    Write-LogOutput "Get-ADObject -Filter 'Name -like `"*Administrators*`" -or Name -like `"*Team*`" -or Name -like `"*Staff*`"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject" -Color Gray
    Write-LogOutput "Get-ADObject -Filter 'Name -like `"*DC*`" -or Name -like `"*SQL*`" -or Name -like `"*WEB*`" -or Name -like `"*WS-*`"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject" -Color Gray
}

# Cleanup instructions
Write-LogOutput "`n--- Cleanup Instructions ---" -Color Magenta
Write-LogOutput "To remove this test structure when done:" -Color White
Write-LogOutput "Remove-ADOrganizationalUnit -Identity '$BaseOU' -Recursive -Confirm:`$false" -Color Gray

# Quick verification commands
Write-LogOutput "`n--- Quick Verification Commands ---" -Color Magenta
Write-LogOutput "Check for orphaned SIDs in enterprise structure:" -Color White
Write-LogOutput "dsacls `"$BaseOU`"" -Color Gray
Write-LogOutput "dsacls `"OU=Departments,$BaseOU`"" -Color Gray
Write-LogOutput "dsacls `"OU=IT,OU=Departments,$BaseOU`"" -Color Gray
Write-LogOutput "`nPowerShell verification:" -Color White
Write-LogOutput "Get-Acl `"AD:\$BaseOU`" | Select-Object -ExpandProperty Access | Where-Object {`$_.IdentityReference -like `"S-1-5-21-*`"}" -Color Gray
Write-LogOutput "`nCheck deleted objects in recycle bin:" -Color White
Write-LogOutput "Get-ADObject -Filter 'Name -like `"*director*`" -or Name -like `"*admin*`" -or Name -like `"*manager*`"' -IncludeDeletedObjects | Select Name,ObjectClass,Deleted" -Color Gray

# Generate final comprehensive report only if logging is enabled
if ($LoggingEnabled) {
    $FinalReport = @"

===============================================================================
                        ORPHANED SID GENERATION REPORT
===============================================================================
Generation Date/Time: $(Get-Date)
Domain: $Domain
Domain DN: $DomainDN
NetBIOS Name: $DomainNetBIOS
Log File: $LogFileName

TEST ENVIRONMENT SUMMARY:
===============================================================================
Base OU: $BaseOU

Enterprise OU Structure Created (45+ OUs):
- Regional Structure: Corporate, Regions (NA, EU, APAC)
- Departmental Structure: IT, Finance, HR, Sales, Marketing, Operations, Legal
- IT Sub-departments: Infrastructure, Security, Development, Support, DataCenter, Network
- Service Accounts: Database, Web, Backup, Monitoring Services
- Computer Structure: Workstations, Servers (DC, App, DB, Web)
- Groups Structure: Security Groups, Distribution Groups, Application Groups, Resource Groups
- Projects Structure: Project2024, Project2025, Contractors
- Legacy Structure: Disabled, Migration

SECURITY PRINCIPALS CREATED & ORPHANED:
===============================================================================

SOFT DELETED (Recoverable via AD Recycle Bin):
Users (12): IT Director, IT Manager, Infrastructure Admin, Security Admin, Network Admin,
Developer Lead, Support Manager, Data Center Tech, SQL Service Account, Web Service Account,
Backup Service Account, Monitoring Service Account

Groups (14): IT Administrators, Infrastructure Admins, Security Admins, Network Admins,
Development Team, Support Team, Database Admins, Web App Admins, Backup Operators,
Monitoring Admins, Finance Staff, HR Staff, Sales Team, Marketing Team

Computers (9): DC01-Primary, DC02-Secondary, SQL01-Production, SQL02-Development,
WEB01-Production, WEB02-Staging, APP01-Business, APP02-Finance, BACKUP01

HARD DELETED (Permanently Removed):
Users (13): Finance Manager, HR Director, Sales Director, Marketing Manager, Operations Manager,
Legal Counsel, NA Regional Manager, EU Regional Manager, APAC Regional Manager,
Project Manager 2024, Project Manager 2025, Contractor Lead, Migration Admin, Legacy Admin

Groups (14): Operations Staff, Legal Team, North America Managers, Europe Managers,
Asia Pacific Managers, File Server Access, Printer Access, VPN Access, Project 2024 Team,
Project 2025 Team, Contractor Access, All Staff, IT Announcements, Executive Team

Computers (9): MONITOR01, FILE01, PRINT01, WS-IT-001, WS-FIN-001, WS-HR-001,
WS-SALES-001, WS-MKT-001, WS-OPS-001

DELEGATION SCENARIOS CREATED:
===============================================================================

Explicit Delegations (40+):
1. IT Director - Full Control on entire structure
2. HR Director - Manage all departments
3. Executive Team - Corporate OU access
4. IT Manager - Full Control over IT department
5. Infrastructure Admin - Full infrastructure control
6. Security Admin - Security OU control
7. Network Admin - Network infrastructure
8. Development Lead - Development team management
9. Support Manager - Support team management
10. Data Center Tech - Data center access
[... and 30+ more enterprise delegations across all departments, regions, projects]

Inherited Delegations (20+):
1. IT Director read access inheriting to all departments
2. Executive team access inheriting to all regions
3. IT Admins group management inheriting to all group OUs
4. Infrastructure read access inheriting to all computers
5. IT Manager create/delete inheriting to IT sub-departments
6. Security team read access to all service accounts
7. Monitoring service read access to all service accounts
8. Network admins read access to all servers
[... and 12+ more inherited delegation scenarios]

AD RECYCLE BIN STATUS:
===============================================================================
$(if ($RecycleBinEnabled) { " ENABLED - Soft-deleted objects are recoverable" } else { " NOT ENABLED - All deletions are permanent" })

VERIFICATION COMMANDS:
===============================================================================

Check for orphaned SIDs in enterprise structure:
dsacls "$BaseOU"
dsacls "OU=Departments,$BaseOU"
dsacls "OU=IT,OU=Departments,$BaseOU"
dsacls "OU=ServiceAccounts,$BaseOU"

PowerShell verification:
Get-Acl "AD:\$BaseOU" | Select-Object -ExpandProperty Access | Where-Object {`$_.IdentityReference -like "S-1-5-21-*"}

$(if ($RecycleBinEnabled) { @"
Check deleted objects in recycle bin:
Get-ADObject -Filter 'Name -like "*director*" -or Name -like "*admin*" -or Name -like "*manager*"' -IncludeDeletedObjects | Select Name,ObjectClass,Deleted

Restore soft-deleted objects (for re-testing):
Get-ADObject -Filter 'Name -like "*director*" -or Name -like "*manager*" -or Name -like "*admin*"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject
Get-ADObject -Filter 'Name -like "*Administrators*" -or Name -like "*Team*" -or Name -like "*Staff*"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject
Get-ADObject -Filter 'Name -like "*DC*" -or Name -like "*SQL*" -or Name -like "*WEB*" -or Name -like "*APP*"' -IncludeDeletedObjects | Where-Object {`$_.Deleted -eq `$true} | Restore-ADObject
"@ } else { "AD Recycle Bin not enabled - no recovery options available" })

CLEANUP COMMANDS:
===============================================================================
Remove-ADOrganizationalUnit -Identity '$BaseOU' -Recursive -Confirm:`$false

TESTING RECOMMENDATIONS:
===============================================================================
1. Run your orphaned SID remediation script against this enterprise structure
2. Verify it handles both soft and hard orphaned SIDs appropriately
3. Check that it distinguishes between recoverable and permanent orphans
4. Validate inheritance scenarios are properly addressed across complex OU hierarchy
5. Test against different permission types (Full Control, specific rights) at enterprise scale
6. Verify computer account orphaned SIDs are handled across multiple server types
7. Test group-based orphaned SID scenarios across different group scopes and types
8. Validate cross-departmental and regional delegation cleanup
9. Test service account orphaned SID remediation
10. Verify performance with 70+ orphaned SIDs across 45+ OUs

GENERATED BY: Enterprise Orphaned SID Generator Script
LOG COMPLETED: $(Get-Date)
===============================================================================
"@

    # Write final report to log file
    Write-DetailedLog "FINAL COMPREHENSIVE ENTERPRISE REPORT"
    $FinalReport | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
}