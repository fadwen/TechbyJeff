function New-CSVReport {
    <#
    .SYNOPSIS
        Generates CSV reports from AD test data

    .DESCRIPTION
        Creates one or more CSV files from the provided test data, with separate
        files for each object type (users, devices, grou                        }
                    }
                }
            }ervice accounts).
        Suitable for spreadsheet analysis and data import/export operations.

    .PARAMETER ReportData
        The report data hashtable containing all collected AD test information

    .PARAMETER OutputPath
        Base path for CSV files. Individual CSV files will be created with suffixes

    .PARAMETER IncludeDetails
        Include detailed object properties in the CSV output

    .PARAMETER IncludeGroupMembers
        Include group membership information in separate CSV files

    .EXAMPLE
        New-CSVReport -ReportData $data -OutputPath "C:\Reports\test" -IncludeDetails

        This creates files like:
        - C:\Reports\test_summary.csv
        - C:\Reports\test_users.csv
        - C:\Reports\test_devices.csv
        - C:\Reports\test_groups.csv
        - C:\Reports\test_serviceaccounts.csv

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ReportData,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting CSV report generation"

        # For CSV reports, create a folder based on the output path
        # If OutputPath is "C:\temp\report.csv", create folder "C:\temp\report" and place CSVs inside
        $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
        $parentDirectory = Split-Path $OutputPath -Parent
        if (-not $parentDirectory) { $parentDirectory = "." }
        
        # Create the report folder
        $baseDirectory = Join-Path $parentDirectory $baseFileName
        if (-not (Test-Path $baseDirectory)) {
            try {
                New-Item -Path $baseDirectory -ItemType Directory -Force | Out-Null
                Write-Host "Created CSV report folder: $baseDirectory" -ForegroundColor Yellow
            }
            catch {
                throw "Cannot create CSV report directory: $baseDirectory"
            }
        }

        $createdFiles = @()
    }    process {
        try {
            Write-ADTestProgress -Message "Generating CSV reports: $OutputPath" -Type Info
            
            # Create summary CSV
            $summaryPath = Join-Path $baseDirectory "$baseFileName`_summary.csv"
            $summaryData = @(
                [PSCustomObject]@{
                    Category = "Organizational Units"
                    Count = $ReportData.Summary.TotalOUs
                    Description = "Test OU structure"
                }
                [PSCustomObject]@{
                    Category = "Users"
                    Count = $ReportData.Summary.TotalUsers
                    Description = "Test user accounts"
                }
                [PSCustomObject]@{
                    Category = "Service Accounts"
                    Count = $ReportData.Summary.TotalServiceAccounts
                    Description = "Test service accounts"
                }
                [PSCustomObject]@{
                    Category = "Devices"
                    Count = $ReportData.Summary.TotalDevices
                    Description = "Test device accounts"
                }
                [PSCustomObject]@{
                    Category = "Groups"
                    Count = $ReportData.Summary.TotalGroups
                    Description = "Test security groups"
                },
                [PSCustomObject]@{
                    Category = "Group Members"
                    Count = $ReportData.Summary.TotalGroupMembers
                    Description = "Total group memberships"
                }
            )
            
            $summaryData | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
            $createdFiles += $summaryPath
            Write-Host "Summary CSV saved to: $summaryPath" -ForegroundColor Green
            
            # Always create detailed CSVs (this is what users expect to see)
            
            # Organizational Units CSV
            if ($ReportData.TestOUs.Count -gt 0) {
                    $ouPath = Join-Path $baseDirectory "$baseFileName`_organizationalunits.csv"
                    $ouData = @()
                    foreach ($ou in $ReportData.TestOUs) {
                        $ouData += [PSCustomObject]@{
                            Name = $ou.Name
                            DistinguishedName = $ou.DistinguishedName
                            Description = $ou.Description
                            ProtectedFromAccidentalDeletion = $ou.ProtectedFromAccidentalDeletion
                            Created = if ($ou.whenCreated) { $ou.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                        }
                    }
                    $ouData | Export-Csv -Path $ouPath -NoTypeInformation -Encoding UTF8
                    $createdFiles += $ouPath
                    Write-Host "OUs CSV saved to: $ouPath" -ForegroundColor Green
                }
                
                # Users CSV
                if ($ReportData.TestUsers.Count -gt 0) {
                    $usersPath = Join-Path $baseDirectory "$baseFileName`_users.csv"
                    $userData = @()
                    foreach ($user in $ReportData.TestUsers) {
                        $userData += [PSCustomObject]@{
                            Name = $user.Name
                            DisplayName = $user.DisplayName
                            SamAccountName = $user.SamAccountName
                            UserPrincipalName = $user.UserPrincipalName
                            EmailAddress = $user.EmailAddress
                            GivenName = $user.GivenName
                            Surname = $user.Surname
                            Department = $user.Department
                            Title = $user.Title
                            Manager = $user.Manager
                            Description = $user.Description
                            OfficePhone = $user.OfficePhone
                            MobilePhone = $user.MobilePhone
                            Office = $user.Office
                            StreetAddress = $user.StreetAddress
                            EmployeeID = $user.EmployeeID
                            EmployeeType = $user.EmployeeType
                            Enabled = $user.Enabled
                            PasswordNeverExpires = $user.PasswordNeverExpires
                            CannotChangePassword = $user.CannotChangePassword
                            AccountExpirationDate = if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            BadLogonCount = $user.BadLogonCount
                            DistinguishedName = $user.DistinguishedName
                            Created = if ($user.whenCreated) { $user.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            Modified = if ($user.whenChanged) { $user.whenChanged.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            LastLogon = if ($user.LastLogonDate) { $user.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            PasswordLastSet = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                        }
                    }
                    $userData | Export-Csv -Path $usersPath -NoTypeInformation -Encoding UTF8
                    $createdFiles += $usersPath
                    Write-Host "Users CSV saved to: $usersPath" -ForegroundColor Green
                }
                
                # Service Accounts CSV
                if ($ReportData.TestServiceAccounts.Count -gt 0) {
                    $serviceAccountsPath = Join-Path $baseDirectory "$baseFileName`_serviceaccounts.csv"
                    $serviceAccountData = @()
                    foreach ($serviceAccount in $ReportData.TestServiceAccounts) {
                        $serviceAccountData += [PSCustomObject]@{
                            Name = $serviceAccount.Name
                            DisplayName = $serviceAccount.DisplayName
                            SamAccountName = $serviceAccount.SamAccountName
                            UserPrincipalName = $serviceAccount.UserPrincipalName
                            EmailAddress = $serviceAccount.EmailAddress
                            Description = $serviceAccount.Description
                            ServicePrincipalNames = if ($serviceAccount.ServicePrincipalNames) { $serviceAccount.ServicePrincipalNames -join "; " } else { "" }
                            Manager = $serviceAccount.Manager
                            Enabled = $serviceAccount.Enabled
                            PasswordNeverExpires = $serviceAccount.PasswordNeverExpires
                            CannotChangePassword = $serviceAccount.CannotChangePassword
                            PasswordNotRequired = $serviceAccount.PasswordNotRequired
                            SmartcardLogonRequired = $serviceAccount.SmartcardLogonRequired
                            TrustedForDelegation = $serviceAccount.TrustedForDelegation
                            AccountNotDelegated = $serviceAccount.AccountNotDelegated
                            UseDESKeyOnly = $serviceAccount.UseDESKeyOnly
                            DoesNotRequirePreAuth = $serviceAccount.DoesNotRequirePreAuth
                            DistinguishedName = $serviceAccount.DistinguishedName
                            Created = if ($serviceAccount.whenCreated) { $serviceAccount.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            Modified = if ($serviceAccount.whenChanged) { $serviceAccount.whenChanged.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            LastLogon = if ($serviceAccount.LastLogonDate) { $serviceAccount.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            PasswordLastSet = if ($serviceAccount.PasswordLastSet) { $serviceAccount.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            AccountType = "ServiceAccount"
                        }
                    }
                    $serviceAccountData | Export-Csv -Path $serviceAccountsPath -NoTypeInformation -Encoding UTF8
                    $createdFiles += $serviceAccountsPath
                    Write-Host "Service Accounts CSV saved to: $serviceAccountsPath" -ForegroundColor Green
                }
                
                # Devices CSV
                if ($ReportData.TestDevices.Count -gt 0) {
                    $devicesPath = Join-Path $baseDirectory "$baseFileName`_devices.csv"
                    $deviceData = @()
                    foreach ($device in $ReportData.TestDevices) {
                        $deviceData += [PSCustomObject]@{
                            Name = $device.Name
                            DNSHostName = $device.DNSHostName
                            SamAccountName = $device.SamAccountName
                            OperatingSystem = $device.OperatingSystem
                            OperatingSystemVersion = $device.OperatingSystemVersion
                            OperatingSystemServicePack = $device.OperatingSystemServicePack
                            Description = $device.Description
                            Location = $device.Location
                            ManagedBy = $device.ManagedBy
                            Enabled = $device.Enabled
                            TrustedForDelegation = $device.TrustedForDelegation
                            ServicePrincipalNames = if ($device.ServicePrincipalNames) { $device.ServicePrincipalNames -join "; " } else { "" }
                            IPv4Address = $device.IPv4Address
                            IPv6Address = $device.IPv6Address
                            DistinguishedName = $device.DistinguishedName
                            Created = if ($device.whenCreated) { $device.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            Modified = if ($device.whenChanged) { $device.whenChanged.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            LastLogon = if ($device.LastLogonDate) { $device.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            PasswordLastSet = if ($device.PasswordLastSet) { $device.PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                        }
                    }
                    $deviceData | Export-Csv -Path $devicesPath -NoTypeInformation -Encoding UTF8
                    $createdFiles += $devicesPath
                    Write-Host "Devices CSV saved to: $devicesPath" -ForegroundColor Green
                }
                
                # Groups CSV
                if ($ReportData.TestGroups.Count -gt 0) {
                    $groupsPath = Join-Path $baseDirectory "$baseFileName`_groups.csv"
                    $groupData = @()
                    foreach ($group in $ReportData.TestGroups) {
                        $groupData += [PSCustomObject]@{
                            Name = $group.Name
                            DisplayName = $group.DisplayName
                            SamAccountName = $group.SamAccountName
                            Description = $group.Description
                            GroupScope = $group.GroupScope
                            GroupCategory = $group.GroupCategory
                            ManagedBy = $group.ManagedBy
                            Mail = $group.Mail
                            HomePage = $group.HomePage
                            Info = $group.Info
                            MemberCount = $group.MemberCount
                            Members = if ($group.Members) { ($group.Members | ForEach-Object { $_.Name }) -join "; " } else { "" }
                            DistinguishedName = $group.DistinguishedName
                            Created = if ($group.whenCreated) { $group.whenCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                            Modified = if ($group.whenChanged) { $group.whenChanged.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
                        }
                    }
                    $groupData | Export-Csv -Path $groupsPath -NoTypeInformation -Encoding UTF8
                    $createdFiles += $groupsPath
                    Write-Host "Groups CSV saved to: $groupsPath" -ForegroundColor Green
                    
                    # Group Members CSV (always created when group data is available)
                    $groupMembersPath = Join-Path $baseDirectory "$baseFileName`_groupmembers.csv"
                    $memberData = @()
                    foreach ($group in $ReportData.TestGroups) {
                        if ($group.Members) {
                            foreach ($member in $group.Members) {
                                $memberData += [PSCustomObject]@{
                                    GroupName = $group.Name
                                    GroupSamAccountName = $group.SamAccountName
                                    MemberName = $member.Name
                                    MemberSamAccountName = $member.SamAccountName
                                    MemberObjectClass = $member.objectClass
                                    MemberDistinguishedName = $member.DistinguishedName
                                }
                            }
                        }
                    }
                    if ($memberData.Count -gt 0) {
                        $memberData | Export-Csv -Path $groupMembersPath -NoTypeInformation -Encoding UTF8
                        $createdFiles += $groupMembersPath
                        Write-Host "Group Members CSV saved to: $groupMembersPath" -ForegroundColor Green
                    }
                }
            
            # Create a master file listing all generated CSVs
            $masterPath = Join-Path $baseDirectory "$baseFileName`_manifest.csv"
            $manifestData = @()
            foreach ($file in $createdFiles) {
                $fileInfo = Get-Item $file
                $manifestData += [PSCustomObject]@{
                    FileName = $fileInfo.Name
                    FullPath = $fileInfo.FullName
                    SizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
                    Created = $fileInfo.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                    Type = switch -Wildcard ($fileInfo.Name) {
                        "*summary*" { "Summary" }
                        "*users*" { "Users" }
                        "*serviceaccounts*" { "Service Accounts" }
                        "*devices*" { "Devices" }
                        "*groups*" { "Groups" }
                        "*groupmembers*" { "Group Members" }
                        "*organizationalunits*" { "Organizational Units" }
                        default { "Unknown" }
                    }
                }
            }
            $manifestData | Export-Csv -Path $masterPath -NoTypeInformation -Encoding UTF8
            Write-Host "CSV manifest saved to: $masterPath" -ForegroundColor Green
            
        } catch {
            Write-Error "Failed to generate CSV reports: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed CSV report generation. Created $($createdFiles.Count) files."
        return @{
            CreatedFiles = $createdFiles
            ManifestFile = $masterPath
            TotalFiles = $createdFiles.Count + 1  # +1 for manifest
        }
    }
}
