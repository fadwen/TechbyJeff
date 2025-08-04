function Get-ADTestEnvironmentReport {
    <#
    .SYNOPSIS
        Generates a comprehensive report of the AD test environment
        
    .DESCRIPTION
        Creates detailed reports of all test data including users, devices, groups, service accounts, and OUs.
        All reports are always generated with complete details including group membership, full attribute sets,
        and comprehensive object information. Supports multiple output formats including console, JSON, HTML, and CSV.

    .PARAMETER OutputFormat
        Specifies the output format: Console, JSON, HTML, or CSV

    .PARAMETER OutputPath
        Path where the report file should be saved (for JSON, HTML, and CSV formats)

    .PARAMETER PassThru
        Returns the report data object instead of just displaying output

    .EXAMPLE
        Get-ADTestEnvironmentReport
        Displays a console report with complete details

    .EXAMPLE
        Get-ADTestEnvironmentReport -OutputFormat HTML -OutputPath "C:\Reports\ADTestReport.html"
        Creates a detailed HTML report with collapsible sections

    .EXAMPLE
        Get-ADTestEnvironmentReport -OutputFormat CSV -OutputPath "C:\Reports\"
        Creates separate CSV files for each object type with full details and group membership

    .EXAMPLE
        $reportData = Get-ADTestEnvironmentReport -PassThru
        Gets the complete report data object for further processing

    .OUTPUTS
        PSCustomObject with complete report data and statistics (when -PassThru is used)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.1.0
        Last Updated: 2025-08-03
        
        All reports include:
        - Complete AD object attributes
        - Group membership details
        - Service account information
        - Full organizational structure
        - Comprehensive statistics
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject], ParameterSetName = 'PassThru')]
    [OutputType([void], ParameterSetName = 'Default')]
    param(
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',
        
        [string]$OutputPath,
        
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Get-ADTestEnvironmentReport - CorrelationId: $correlationId"
        
        # Get domain information
        $domain = Get-ADTestDomain
        
        # Validate output path if specified
        if ($OutputPath -and $OutputFormat -ne 'Console') {
            if ($OutputFormat -eq 'CSV') {
                # For CSV, ensure it's a directory
                if (-not (Test-Path $OutputPath -PathType Container)) {
                    try {
                        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                    }
                    catch {
                        throw "Cannot create output directory: $OutputPath"
                    }
                }
            }
            else {
                # For single files, ensure directory exists
                $directory = Split-Path $OutputPath -Parent
                if ($directory -and -not (Test-Path $directory)) {
                    try {
                        New-Item -Path $directory -ItemType Directory -Force | Out-Null
                    }
                    catch {
                        throw "Cannot create output directory: $directory"
                    }
                }
            }
        }
    }

    process {
        try {
            Write-ADTestProgress -Message "Generating Active Directory Test Data Report" -Type Header
            
            # Initialize report data structure
            $reportData = @{
                GeneratedOn = Get-Date
                Domain = $domain.DNSName
                CorrelationId = $correlationId
                TestOUs = @()
                TestUsers = @()
                TestServiceAccounts = @()
                TestDevices = @()
                TestGroups = @()
                Summary = @{
                    TotalOUs = 0
                    TotalUsers = 0
                    TotalServiceAccounts = 0
                    TotalDevices = 0
                    TotalGroups = 0
                    TotalGroupMembers = 0
                }
            }
            
            # Collect Test OUs
            Write-ADTestProgress -Message "Collecting OU information..." -Type Info
            try {
                $testOUs = Get-ADOrganizationalUnit -Filter "*" -SearchBase "OU=TestData,$($domain.DomainDN)" -Properties Description,ProtectedFromAccidentalDeletion | 
                    Select-Object Name, DistinguishedName, Description, ProtectedFromAccidentalDeletion, 
                        @{Name='ParentOU';Expression={($_.DistinguishedName -split ',',2)[1]}}
                
                $reportData.TestOUs = $testOUs
                $reportData.Summary.TotalOUs = $testOUs.Count
            }
            catch {
                Write-Warning "Error collecting OU data: $($_.Exception.Message)"
                $reportData.TestOUs = @()
            }
            
            # Collect Test Users
            Write-ADTestProgress -Message "Collecting user information..." -Type Info
            try {
                # Get ALL properties from AD
                $testUsers = Get-ADUser -Filter "*" -SearchBase "OU=Users,OU=TestData,$($domain.DomainDN)" -Properties *
                
                $reportData.TestUsers = $testUsers
                $reportData.Summary.TotalUsers = $testUsers.Count
            }
            catch {
                Write-Warning "Error collecting user data: $($_.Exception.Message)"
                $reportData.TestUsers = @()
            }
            
            # Collect Test Service Accounts
            Write-ADTestProgress -Message "Collecting service account information..." -Type Info
            try {
                # Get ALL properties from AD
                $testServiceAccounts = Get-ADUser -Filter "*" -SearchBase "OU=ServiceAccounts,OU=TestData,$($domain.DomainDN)" -Properties *
                
                $reportData.TestServiceAccounts = $testServiceAccounts
                $reportData.Summary.TotalServiceAccounts = $testServiceAccounts.Count
            }
            catch {
                Write-Warning "Error collecting service account data: $($_.Exception.Message)"
                $reportData.TestServiceAccounts = @()
            }
            
            # Collect Test Devices
            Write-ADTestProgress -Message "Collecting device information..." -Type Info
            try {
                # Get ALL properties from AD
                $testDevices = Get-ADComputer -Filter "*" -SearchBase "OU=Devices,OU=TestData,$($domain.DomainDN)" -Properties *
                
                $reportData.TestDevices = $testDevices
                $reportData.Summary.TotalDevices = $testDevices.Count
            }
            catch {
                Write-Warning "Error collecting device data: $($_.Exception.Message)"
                $reportData.TestDevices = @()
            }
            
            # Collect Test Groups
            Write-ADTestProgress -Message "Collecting group information..." -Type Info
            try {
                # Get ALL properties from AD
                $testGroups = Get-ADGroup -Filter "*" -SearchBase "OU=Groups,OU=TestData,$($domain.DomainDN)" -Properties *
                
                # Always collect group members and add member counts
                $groupMembers = @()
                foreach ($group in $testGroups) {
                    try {
                        $members = Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction SilentlyContinue
                        $group | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $members.Count -Force
                        $group | Add-Member -MemberType NoteProperty -Name 'Members' -Value ($members | Select-Object Name, objectClass) -Force
                        
                        # Create individual member records for the GroupMembers collection
                        foreach ($member in $members) {
                            $groupMembers += [PSCustomObject]@{
                                GroupName = $group.Name
                                GroupDistinguishedName = $group.DistinguishedName
                                MemberName = $member.Name
                                MemberType = $member.objectClass
                                MemberDistinguishedName = $member.DistinguishedName
                                    MemberSamAccountName = $member.SamAccountName
                                }
                            }
                        }
                        catch {
                            $group | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value 0 -Force
                            $group | Add-Member -MemberType NoteProperty -Name 'Members' -Value @() -Force
                        }
                    }
                    $reportData.GroupMembers = $groupMembers
                    $reportData.Summary.TotalGroupMembers = $groupMembers.Count
                
                $reportData.TestGroups = $testGroups
                $reportData.Summary.TotalGroups = $testGroups.Count
            }
            catch {
                Write-Warning "Error collecting group data: $($_.Exception.Message)"
                $reportData.TestGroups = @()
            }
            
            # Generate output based on format using dedicated helper functions
            switch ($OutputFormat) {
                'Console' {
                    Write-ADTestProgress -Message "Active Directory Test Data Report" -Type Success
                    Write-Host ""
                    Write-Host "Domain: $($reportData.Domain)" -ForegroundColor Cyan
                    Write-Host "Generated: $($reportData.GeneratedOn)" -ForegroundColor Cyan
                    Write-Host ""
                    
                    Write-Host "=== SUMMARY ===" -ForegroundColor Yellow
                    Write-Host "Total OUs: $($reportData.Summary.TotalOUs)" -ForegroundColor Green
                    Write-Host "Total Users: $($reportData.Summary.TotalUsers)" -ForegroundColor Green
                    Write-Host "Total Service Accounts: $($reportData.Summary.TotalServiceAccounts)" -ForegroundColor Green
                    Write-Host "Total Devices: $($reportData.Summary.TotalDevices)" -ForegroundColor Green
                    Write-Host "Total Groups: $($reportData.Summary.TotalGroups)" -ForegroundColor Green
                    Write-Host "Total Group Members: $($reportData.Summary.TotalGroupMembers)" -ForegroundColor Green
                    Write-Host ""
                    
                    # Always show detailed information
                    if ($reportData.TestOUs.Count -gt 0) {
                        Write-Host "=== ORGANIZATIONAL UNITS ===" -ForegroundColor Yellow
                        $reportData.TestOUs | Format-Table Name, Description, ProtectedFromAccidentalDeletion -AutoSize
                    }
                    
                    if ($reportData.TestUsers.Count -gt 0) {
                        Write-Host "=== USERS ===" -ForegroundColor Yellow
                        $reportData.TestUsers | Format-Table Name, Department, Title, Enabled -AutoSize
                    }
                    
                    if ($reportData.TestServiceAccounts.Count -gt 0) {
                        Write-Host "=== SERVICE ACCOUNTS ===" -ForegroundColor Yellow
                        $reportData.TestServiceAccounts | Format-Table Name, SamAccountName, Description, Enabled -AutoSize
                    }
                    
                    if ($reportData.TestDevices.Count -gt 0) {
                        Write-Host "=== DEVICES ===" -ForegroundColor Yellow
                        $reportData.TestDevices | Format-Table Name, OperatingSystem, Enabled -AutoSize
                    }
                        
                    if ($reportData.TestGroups.Count -gt 0) {
                        Write-Host "=== SECURITY GROUPS ===" -ForegroundColor Yellow
                        $reportData.TestGroups | Format-Table Name, GroupScope, MemberCount -AutoSize
                    }
                }
                
                'JSON' {
                    if (-not $OutputPath) {
                        $OutputPath = "ADTestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                    }
                    
                    New-JSONReport -ReportData $reportData -OutputPath $OutputPath
                }
                
                'HTML' {
                    if (-not $OutputPath) {
                        $OutputPath = "ADTestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
                    }
                    
                    New-HTMLReport -ReportData $reportData -OutputPath $OutputPath
                }
                
                'CSV' {
                    if (-not $OutputPath) {
                        $OutputPath = ".\ADTestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                    }
                    
                    New-CSVReport -ReportData $reportData -OutputPath $OutputPath
                }
            }
            
            # Return data only if PassThru is specified
            if ($PassThru) {
                # Convert hashtable to PSCustomObject for better usability
                return [PSCustomObject]$reportData
            }
            
        } catch {
            Write-Error "Failed to generate report: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Get-ADTestEnvironmentReport - CorrelationId: $correlationId"
    }
}
