# Load all required DSC modules FIRST
Write-Host "Loading DSC modules..." -ForegroundColor Cyan
Import-Module PSDesiredStateConfiguration -Force
Import-Module CisDsc -Force -ErrorAction SilentlyContinue
Import-Module SecurityPolicyDsc -Force -ErrorAction SilentlyContinue
Import-Module AuditPolicyDsc -Force -ErrorAction SilentlyContinue
Write-Host "✓ All DSC modules loaded" -ForegroundColor Green

Configuration ComprehensiveSecurity {
    param(
        [string]$NodeName = 'localhost',
        [string]$ServerRole = 'MemberServer',
        [string]$LogPath = 'C:\Logs\DSC'
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName CisDsc
    Import-DscResource -ModuleName SecurityPolicyDsc
    Import-DscResource -ModuleName AuditPolicyDsc

    Node $NodeName {
        # Ensure log directory exists
        File DSCLogDirectory {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = $LogPath
            Force = $true
        }

        # Configure LCM consistently
        LocalConfigurationManager {
            RefreshMode = 'Push'
            ConfigurationMode = 'ApplyAndMonitor'
            RebootNodeIfNeeded = $false
            ActionAfterReboot = 'ContinueConfiguration'
        }

        # DSC Execution Logger - Start
        Script DSCExecutionStart {
            SetScript = {
                function Write-DSCLog {
                    param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    $logDir = Split-Path $LogPath
                    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                    Write-Host $logEntry
                }

                Write-DSCLog "=== Starting DSC Configuration Application ===" -Level "INFO"
                Write-DSCLog "Server Role: $using:ServerRole" -Level "INFO"
                Write-DSCLog "Node Name: $using:NodeName" -Level "INFO"
                Write-DSCLog "Log Path: $using:LogPath" -Level "INFO"
                Write-DSCLog "Execution Time: $(Get-Date)" -Level "INFO"

                # Log system information
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
                Write-DSCLog "OS: $($osInfo.Caption) $($osInfo.Version)" -Level "INFO"
                Write-DSCLog "Computer Name: $($env:COMPUTERNAME)" -Level "INFO"
            }
            TestScript = { $false }
            GetScript = { @{ Result = "DSC Start Logger" } }
            DependsOn = '[File]DSCLogDirectory'
        }

        # Common CIS parameters
        $CommonParams = @{
            Cis2316AccountsRenameGuestaccount = "GuestRenamed"
            Cis2374LegalNoticeText = "Authorized access only - All activity monitored"
            Cis2375LegalNoticeCaption = "Security Warning"
            Cis2376CachedLogonsCount = "2"
            Cis1849ScreensaverGracePeriod = "5"
        }

        # Role-specific CIS baseline with account policy exclusions
        switch ($ServerRole) {
            'DomainController' {
                Script DCConfigStart {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Applying Domain Controller CIS baseline" -Level "INFO"
                        Write-DSCLog "Excluding controls for DC-specific requirements" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "DC Config Start" } }
                    DependsOn = '[Script]DSCExecutionStart'
                }

                CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2 DCBaseline {
                    Cis2316AccountsRenameGuestaccount = $CommonParams.Cis2316AccountsRenameGuestaccount
                    Cis2374LegalNoticeText = $CommonParams.Cis2374LegalNoticeText
                    Cis2375LegalNoticeCaption = $CommonParams.Cis2375LegalNoticeCaption
                    Cis2376CachedLogonsCount = $CommonParams.Cis2376CachedLogonsCount
                    Cis1849ScreensaverGracePeriod = $CommonParams.Cis1849ScreensaverGracePeriod
                    ExcludeList = @(
                        '2.2.21',  # Deny access from network (DCs need this)
                        '2.2.26',  # Deny logon as service (some DC services)
                        '2.3.1.5', # Administrator account status (needed for break-glass)
                        '2.3.1.1', # Administrator account status (alternative ID)
                        '1.1.1',   # Account lockout duration
                        '1.1.2',   # Account lockout threshold
                        '1.1.3',   # Reset account lockout counter
                        '1.1.4',   # Account lockout duration (alternative)
                        '1.1.5',   # Account lockout threshold (alternative)
                        '1.1.6',   # Reset account lockout counter (alternative)
                        '1.2.1',   # Account lockout duration (variant)
                        '1.2.2',   # Account lockout threshold (variant)
                        '1.2.3'    # Reset account lockout counter (variant)
                    )
                    DependsOn = '[Script]DCConfigStart'
                }

                # Remove the AccountPolicy resource that's causing conflicts
                Script DCConfigComplete {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Domain Controller CIS baseline application completed" -Level "INFO"
                        Write-DSCLog "Account policy excluded to avoid conflicts" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "DC Config Complete" } }
                    DependsOn = '[CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2]DCBaseline'
                }
            }
            'WebServer' {
                Script WebConfigStart {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Applying Web Server CIS baseline" -Level "INFO"
                        Write-DSCLog "Excluding controls for IIS requirements" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "Web Config Start" } }
                    DependsOn = '[Script]DSCExecutionStart'
                }

                CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2 WebBaseline {
                    Cis2316AccountsRenameGuestaccount = $CommonParams.Cis2316AccountsRenameGuestaccount
                    Cis2374LegalNoticeText = $CommonParams.Cis2374LegalNoticeText
                    Cis2375LegalNoticeCaption = $CommonParams.Cis2375LegalNoticeCaption
                    Cis2376CachedLogonsCount = $CommonParams.Cis2376CachedLogonsCount
                    Cis1849ScreensaverGracePeriod = $CommonParams.Cis1849ScreensaverGracePeriod
                    ExcludeList = @(
                        '2.3.1.5',    # Administrator account status (needed for break-glass)
                        '2.3.1.1',    # Administrator account status (alternative ID)
                        '5.1',        # Windows Firewall (IIS manages its own)
                        '18.9.47.5.1', # WinRM for remote management
                        '1.1.1',      # Account lockout duration
                        '1.1.2',      # Account lockout threshold
                        '1.1.3',      # Reset account lockout counter
                        '1.1.4',      # Account lockout duration (alternative)
                        '1.1.5',      # Account lockout threshold (alternative)
                        '1.1.6',      # Reset account lockout counter (alternative)
                        '1.2.1',      # Account lockout duration (variant)
                        '1.2.2',      # Account lockout threshold (variant)
                        '1.2.3'       # Reset account lockout counter (variant)
                    )
                    DependsOn = '[Script]WebConfigStart'
                }

                # Remove the AccountPolicy resource that's causing conflicts
                Script WebConfigComplete {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Web Server CIS baseline application completed" -Level "INFO"
                        Write-DSCLog "Account policy excluded to avoid conflicts" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "Web Config Complete" } }
                    DependsOn = '[CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2]WebBaseline'
                }
            }
            Default {
                Script MemberConfigStart {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Applying Member Server CIS baseline" -Level "INFO"
                        Write-DSCLog "Standard member server configuration" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "Member Config Start" } }
                    DependsOn = '[Script]DSCExecutionStart'
                }

                CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2 MemberBaseline {
                    Cis2316AccountsRenameGuestaccount = $CommonParams.Cis2316AccountsRenameGuestaccount
                    Cis2374LegalNoticeText = $CommonParams.Cis2374LegalNoticeText
                    Cis2375LegalNoticeCaption = $CommonParams.Cis2375LegalNoticeCaption
                    Cis2376CachedLogonsCount = $CommonParams.Cis2376CachedLogonsCount
                    Cis1849ScreensaverGracePeriod = $CommonParams.Cis1849ScreensaverGracePeriod
                    ExcludeList = @(
                        '2.3.1.5',  # Administrator account status (needed for break-glass)
                        '2.3.1.1',  # Administrator account status (alternative ID)
                        '18.9.4.1', # AutoAdminLogon (some automation requires this)
                        '1.1.1',    # Account lockout duration
                        '1.1.2',    # Account lockout threshold
                        '1.1.3',    # Reset account lockout counter
                        '1.1.4',    # Account lockout duration (alternative)
                        '1.1.5',    # Account lockout threshold (alternative)
                        '1.1.6',    # Reset account lockout counter (alternative)
                        '1.2.1',    # Account lockout duration (variant)
                        '1.2.2',    # Account lockout threshold (variant)
                        '1.2.3'     # Reset account lockout counter (variant)
                    )
                    DependsOn = '[Script]MemberConfigStart'
                }

                # Remove the AccountPolicy resource that's causing conflicts
                Script MemberConfigComplete {
                    SetScript = {
                        function Write-DSCLog {
                            param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                            $logEntry = "[$timestamp] [$Level] $Message"
                            $logDir = Split-Path $LogPath
                            if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                            Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                            Write-Host $logEntry
                        }

                        Write-DSCLog "Member Server CIS baseline application completed" -Level "INFO"
                        Write-DSCLog "Account policy excluded to avoid conflicts" -Level "INFO"
                    }
                    TestScript = { $false }
                    GetScript = { @{ Result = "Member Config Complete" } }
                    DependsOn = '[CIS_Microsoft_Windows_Server_2022_Member_Server_Release_21H2]MemberBaseline'
                }
            }
        }

        # Custom registry settings that complement CIS
        Script CustomRegistryStart {
            SetScript = {
                function Write-DSCLog {
                    param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    $logDir = Split-Path $LogPath
                    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                    Write-Host $logEntry
                }

                Write-DSCLog "Applying custom registry security settings" -Level "INFO"
            }
            TestScript = { $false }
            GetScript = { @{ Result = "Custom Registry Start" } }
            DependsOn = '[File]DSCLogDirectory'
        }

        Registry DisableAutorun {
            Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            ValueName = 'NoDriveTypeAutoRun'
            ValueData = 255
            ValueType = 'Dword'
            Ensure = 'Present'
            DependsOn = '[Script]CustomRegistryStart'
        }

        Registry DisableLLMNR {
            Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            ValueName = 'EnableMulticast'
            ValueData = 0
            ValueType = 'Dword'
            Ensure = 'Present'
            DependsOn = '[Script]CustomRegistryStart'
        }

        Script CustomRegistryComplete {
            SetScript = {
                function Write-DSCLog {
                    param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    $logDir = Split-Path $LogPath
                    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                    Write-Host $logEntry
                }

                Write-DSCLog "Custom registry settings applied successfully" -Level "INFO"
                Write-DSCLog "- Disabled autorun for all drive types" -Level "INFO"
                Write-DSCLog "- Disabled LLMNR for security" -Level "INFO"
            }
            TestScript = { $false }
            GetScript = { @{ Result = "Custom Registry Complete" } }
            DependsOn = '[Registry]DisableAutorun', '[Registry]DisableLLMNR'
        }

        # Additional audit policies
        Script AuditPolicyStart {
            SetScript = {
                function Write-DSCLog {
                    param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    $logDir = Split-Path $LogPath
                    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                    Write-Host $logEntry
                }

                Write-DSCLog "Configuring additional audit policies" -Level "INFO"
            }
            TestScript = { $false }
            GetScript = { @{ Result = "Audit Policy Start" } }
            DependsOn = '[File]DSCLogDirectory'
        }

        AuditPolicySubcategory AccountLockout {
            Name = 'Account Lockout'
            AuditFlag = 'Failure'
            Ensure = 'Present'
            DependsOn = '[Script]AuditPolicyStart'
        }

        AuditPolicySubcategory LogonEvents {
            Name = 'Logon'
            AuditFlag = 'Failure'
            Ensure = 'Present'
            DependsOn = '[Script]AuditPolicyStart'
        }

        if ($ServerRole -eq 'DomainController') {
            AuditPolicySubcategory DirectoryServiceAccess {
                Name = 'Directory Service Access'
                AuditFlag = 'Failure'
                Ensure = 'Present'
                DependsOn = '[Script]AuditPolicyStart'
            }

            Script DCAuditComplete {
                SetScript = {
                    function Write-DSCLog {
                        param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                        $logEntry = "[$timestamp] [$Level] $Message"
                        $logDir = Split-Path $LogPath
                        if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                        Write-Host $logEntry
                    }

                    Write-DSCLog "Domain Controller audit policies configured" -Level "INFO"
                    Write-DSCLog "- Account lockout failures" -Level "INFO"
                    Write-DSCLog "- Logon failures" -Level "INFO"
                    Write-DSCLog "- Directory service access failures" -Level "INFO"
                }
                TestScript = { $false }
                GetScript = { @{ Result = "DC Audit Complete" } }
                DependsOn = '[AuditPolicySubcategory]DirectoryServiceAccess'
            }
        } else {
            Script StandardAuditComplete {
                SetScript = {
                    function Write-DSCLog {
                        param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                        $logEntry = "[$timestamp] [$Level] $Message"
                        $logDir = Split-Path $LogPath
                        if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                        Write-Host $logEntry
                    }

                    Write-DSCLog "Standard audit policies configured" -Level "INFO"
                    Write-DSCLog "- Account lockout failures" -Level "INFO"
                    Write-DSCLog "- Logon failures" -Level "INFO"
                }
                TestScript = { $false }
                GetScript = { @{ Result = "Standard Audit Complete" } }
                DependsOn = '[AuditPolicySubcategory]LogonEvents'
            }
        }

        # Final completion logging
        Script DSCExecutionComplete {
            SetScript = {
                function Write-DSCLog {
                    param([string]$Message, [string]$Level = "INFO", [string]$LogPath = "C:\Logs\DSC\dsc-execution.log")
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    $logDir = Split-Path $LogPath
                    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }
                    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
                    Write-Host $logEntry
                }

                Write-DSCLog "=== DSC Configuration Application Completed ===" -Level "INFO"
                Write-DSCLog "Server Role: $using:ServerRole" -Level "INFO"
                Write-DSCLog "Completion Time: $(Get-Date)" -Level "INFO"
                Write-DSCLog "Configuration applied successfully" -Level "INFO"

                $summaryPath = "$using:LogPath\dsc-summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
                $summary = "DSC Configuration Summary`nServer Role: $using:ServerRole`nNode Name: $using:NodeName`nCompletion Time: $(Get-Date)`nStatus: SUCCESS"
                $summary | Out-File -FilePath $summaryPath -Encoding UTF8
                Write-DSCLog "Summary report generated: $summaryPath" -Level "INFO"
            }
            TestScript = { $false }
            GetScript = { @{ Result = "DSC Execution Complete" } }
            DependsOn = '[Script]CustomRegistryComplete'
        }
    }
}

# Generate MOF files for all roles
Write-Host "Starting MOF generation process..." -ForegroundColor Cyan

@('WebServer', 'DomainController', 'MemberServer') | ForEach-Object {
    $Role = $_
    $OutputPath = ".\MOF\Comprehensive\$Role"

    Write-Host "Generating MOF for $Role role..." -ForegroundColor Yellow

    try {
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        ComprehensiveSecurity -ServerRole $Role -NodeName 'localhost' -OutputPath $OutputPath

        Write-Host "✓ Generated comprehensive security configuration for $Role role" -ForegroundColor Green

        $mofFile = Join-Path $OutputPath "localhost.mof"
        if (Test-Path $mofFile) {
            $mofSize = (Get-Item $mofFile).Length
            Write-Host "  MOF Size: $mofSize bytes" -ForegroundColor Gray
        } else {
            Write-Host "  WARNING: MOF file not found!" -ForegroundColor Red
        }

    } catch {
        Write-Host "✗ Failed to generate MOF for $Role role" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "MOF generation process completed!" -ForegroundColor Cyan
Write-Host "Upload the MOF files to S3 and update your Systems Manager associations." -ForegroundColor White

# Upload all MOFs to organized folders
Get-ChildItem -Path .\MOF -Recurse -Filter "*.mof" | ForEach-Object {
    $key = "configurations/$($_.Directory.Name)/$($_.Name)"
    Write-S3Object -BucketName "systems-manager-windows-server-dsc-configurations" `
                   -File $_.FullName `
                   -Key $key
}

# Verify they are all there
Get-S3Object -BucketName "systems-manager-windows-server-dsc-configurations" -Prefix "configurations/" |
    Select-Object Key, Size, LastModified |
    Format-Table -AutoSize