function New-JSONReport {
    <#
    .SYNOPSIS
        Generates a JSON report from AD test data

    .DESCRIPTION
        Creates a structured JSON report from the provided test data,
        suitable for programmatic consumption and integration with other tools.

    .PARAMETER ReportData
        The report data hashtable containing all collected AD test information

    .PARAMETER OutputPath
        Path where the JSON file should be saved

    .EXAMPLE
        New-JSONReport -ReportData $data -OutputPath "C:\Reports\test.json"

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
        
        Creates a comprehensive JSON report with all available details including:
        - Full object attributes for all AD objects
        - Group membership information
        - Always outputs the most detailed information available
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ReportData,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting JSON report generation"
        
        # Ensure output directory exists
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

    process {
        try {
            Write-ADTestProgress -Message "Generating JSON report: $OutputPath" -Type Info
            
            # Build structured data for JSON
            $jsonData = @{
                metadata = @{
                    title = "Active Directory Test Data Report"
                    domain = $ReportData.Domain
                    generatedOn = $ReportData.GeneratedOn
                    correlationId = $ReportData.CorrelationId
                    includeDetails = $true  # Always include details now
                    includeGroupMembers = $IncludeGroupMembers.IsPresent
                    reportVersion = "2.0"
                }
                summary = @{
                    organizationalUnits = $ReportData.Summary.TotalOUs
                    users = $ReportData.Summary.TotalUsers
                    serviceAccounts = $ReportData.Summary.TotalServiceAccounts
                    devices = $ReportData.Summary.TotalDevices
                    groups = $ReportData.Summary.TotalGroups
                    groupMembers = $ReportData.Summary.TotalGroupMembers
                }
            }
            
            # Always add detailed data (this is what users expect to see)
            $jsonData.details = @{}
            
            # Organizational Units
            if ($ReportData.TestOUs.Count -gt 0) {
                $jsonData.details.organizationalUnits = @()
                foreach ($ou in $ReportData.TestOUs) {
                    $ouData = @{
                        name = $ou.Name
                        distinguishedName = $ou.DistinguishedName
                        description = $ou.Description
                        protectedFromAccidentalDeletion = $ou.ProtectedFromAccidentalDeletion
                        created = if ($ou.whenCreated) { $ou.whenCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                    }
                    $jsonData.details.organizationalUnits += $ouData
                }
            }
            
            # Users
            if ($ReportData.TestUsers.Count -gt 0) {
                $jsonData.details.users = @()
                foreach ($user in $ReportData.TestUsers) {
                    $userData = @{
                        name = $user.Name
                        displayName = $user.DisplayName
                        samAccountName = $user.SamAccountName
                        userPrincipalName = $user.UserPrincipalName
                        emailAddress = $user.EmailAddress
                        givenName = $user.GivenName
                        surname = $user.Surname
                        department = $user.Department
                        title = $user.Title
                        manager = $user.Manager
                        enabled = $user.Enabled
                        description = $user.Description
                        officePhone = $user.OfficePhone
                        mobilePhone = $user.MobilePhone
                        office = $user.Office
                        streetAddress = $user.StreetAddress
                        employeeID = $user.EmployeeID
                        employeeType = $user.EmployeeType
                        passwordNeverExpires = $user.PasswordNeverExpires
                        cannotChangePassword = $user.CannotChangePassword
                        accountExpirationDate = if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        badLogonCount = $user.BadLogonCount
                        distinguishedName = $user.DistinguishedName
                        created = if ($user.whenCreated) { $user.whenCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        modified = if ($user.whenChanged) { $user.whenChanged.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        passwordLastSet = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                    }
                    $jsonData.details.users += $userData
                }
            }
            
            # Service Accounts
            if ($ReportData.TestServiceAccounts.Count -gt 0) {
                $jsonData.details.serviceAccounts = @()
                foreach ($serviceAccount in $ReportData.TestServiceAccounts) {
                    $serviceAccountData = @{
                        name = $serviceAccount.Name
                        displayName = $serviceAccount.DisplayName
                        samAccountName = $serviceAccount.SamAccountName
                        userPrincipalName = $serviceAccount.UserPrincipalName
                        description = $serviceAccount.Description
                        manager = $serviceAccount.Manager
                        enabled = $serviceAccount.Enabled
                        passwordNeverExpires = $serviceAccount.PasswordNeverExpires
                        cannotChangePassword = $serviceAccount.CannotChangePassword
                        accountExpirationDate = if ($serviceAccount.AccountExpirationDate) { $serviceAccount.AccountExpirationDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        badLogonCount = $serviceAccount.BadLogonCount
                        servicePrincipalNames = $serviceAccount.ServicePrincipalNames
                        distinguishedName = $serviceAccount.DistinguishedName
                        created = if ($serviceAccount.whenCreated) { $serviceAccount.whenCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        modified = if ($serviceAccount.whenChanged) { $serviceAccount.whenChanged.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        lastLogon = if ($serviceAccount.LastLogonDate) { $serviceAccount.LastLogonDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        passwordLastSet = if ($serviceAccount.PasswordLastSet) { $serviceAccount.PasswordLastSet.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        accountType = "ServiceAccount"
                    }
                    $jsonData.details.serviceAccounts += $serviceAccountData
                }
            }
            
            # Devices
            if ($ReportData.TestDevices.Count -gt 0) {
                $jsonData.details.devices = @()
                foreach ($device in $ReportData.TestDevices) {
                    $deviceData = @{
                        name = $device.Name
                        dnsHostName = $device.DNSHostName
                        samAccountName = $device.SamAccountName
                        operatingSystem = $device.OperatingSystem
                        operatingSystemVersion = $device.OperatingSystemVersion
                        operatingSystemServicePack = $device.OperatingSystemServicePack
                        description = $device.Description
                        location = $device.Location
                        managedBy = $device.ManagedBy
                        servicePrincipalNames = $device.ServicePrincipalNames
                        enabled = $device.Enabled
                        distinguishedName = $device.DistinguishedName
                        created = if ($device.whenCreated) { $device.whenCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        modified = if ($device.whenChanged) { $device.whenChanged.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        lastLogon = if ($device.LastLogonDate) { $device.LastLogonDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        passwordLastSet = if ($device.PasswordLastSet) { $device.PasswordLastSet.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                    }
                    $jsonData.details.devices += $deviceData
                }
            }
            
            # Groups
            if ($ReportData.TestGroups.Count -gt 0) {
                $jsonData.details.groups = @()
                foreach ($group in $ReportData.TestGroups) {
                    $groupData = @{
                        name = $group.Name
                        displayName = $group.DisplayName
                        samAccountName = $group.SamAccountName
                        description = $group.Description
                        groupScope = $group.GroupScope
                        groupCategory = $group.GroupCategory
                        managedBy = $group.ManagedBy
                        info = $group.Info
                        notes = $group.Notes
                        distinguishedName = $group.DistinguishedName
                        created = if ($group.whenCreated) { $group.whenCreated.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                        modified = if ($group.whenChanged) { $group.whenChanged.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') } else { $null }
                    }
                    
                    # Add member information (always included)
                    $groupData.memberCount = $group.MemberCount
                    if ($group.Members) {
                        $groupData.members = @()
                        foreach ($member in $group.Members) {
                            $memberData = @{
                                name = $member.Name
                                samAccountName = $member.SamAccountName
                                objectClass = $member.objectClass
                                distinguishedName = $member.DistinguishedName
                            }
                            $groupData.members += $memberData
                        }
                    }
                    
                    $jsonData.details.groups += $groupData
                }
            }
            
            # Convert to JSON with proper formatting
            $jsonContent = $jsonData | ConvertTo-Json -Depth 10
            
            # Write the JSON file
            $jsonContent | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "JSON report saved to: $OutputPath" -ForegroundColor Green
            
        } catch {
            Write-Error "Failed to generate JSON report: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed JSON report generation"
    }
}
