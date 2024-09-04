<#
.SYNOPSIS
Determine all Microsoft license's in tenant and if they are assigned directly or inherited from a group.
.DESCRIPTION
This script retrieves all subscribed SKUs and groups with licenses assigned. 
It then extends the mapping to include the group ID, display name, and members. 
The script retrieves licensed users and finds users with SKUs not part of the corresponding groups. 
It exports the users who have the SKU but are not part of the corresponding groups to the DirectAssigned worksheet.
It adds a new sheet for each SKU and exports the data. 
.NOTES
Created by: Jeffrey Stuhr
Blog: techbyjeff.ghost.io
#>

# Install-Module -Name ImportExcel -Scope CurrentUser
# Install-Module -Name MGGraph -Scope CurrentUser
Import-Module ImportExcel
Connect-MgGraph -Scopes User.Read.All, Group.Read.All, Directory.Read.All -NoWelcome
# There are two variables that reference locally $csvPath and $filename, you can change them to your desired path


# Mapping for SKU names, bc naturally it's not the same as the license display name https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference

# Define the path to the CSV file
$csvPath = "C:\temp\licensenames.csv"
# Define the URL, if this is failing to download reference the above learn page for the correct URL
$url = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
# Check if the CSV file already exists
if (-Not (Test-Path -Path $csvPath)) {
    # Download the CSV file from the URL
    try {
        Invoke-WebRequest -Uri $url -OutFile $csvPath
    }
    catch {
        Write-Host "Failed to download the CSV file from $url"
        exit
    }
}
# Read the CSV file into a variable
$licenseNameCSV = Import-Csv -Path $csvPath
$skuToLicenseName = @{}

# Iterate through each row
foreach ($row in $licenseNameCSV) {
    # Use Column B as the key and Column A as the value
    $csvSkuID = $row.String_Id
    $LicenseName = $row.Product_Display_Name
    $skuToLicenseName[$csvSkuID] = $LicenseName
}

# Retrieve all subscribed SKUs and create an array of SkuId, SkuPartNumber, and SkuLicenseName, with empty fields for GroupId, GroupDisplayName, and Members
$skuMapList = foreach ($sku in (Get-MgSubscribedSku)) {
    [PSCustomObject]@{
        SkuId = $sku.SkuId
        SkuDisplayName = $sku.SkuPartNumber
        SkuLicenseName = $skuToLicenseName[$sku.SkuPartNumber]
        GroupId = ""
        GroupDisplayName = ""
        Members = @()
    }
}

# Gather groups with licenses assigned
$licensedGroupList = Get-MgGroup -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedGroupCount -All -Select Id,DisplayName,AssignedLicenses

# Extend the mapping to include the group ID, display name, and members
foreach ($group in $licensedGroupList) {
    foreach ($assignedLicense in $group.AssignedLicenses) {
        foreach ($skuMap in ($skuMapList | Where-Object SkuID -eq $assignedLicense.SkuId)) {
            $skuMap.GroupId = $group.Id
            $skuMap.GroupDisplayName = $group.DisplayName            
            $members = (Get-MgGroupMember -GroupID $group.Id -All).id
            if ($null -eq $members -or $members.Count -eq 0) {
                $skuMap.Members = "Not-In-Use"
            } else {
                $skuMap.Members = $members
            }
        }
    }
}

# Retrieve licensed users
$licensedUsersList = Get-MgUser -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedUserCount -All -Select Id,UserPrincipalName,DisplayName,AssignedLicenses

# Find users with SKUs not part of the corresponding groups
$usersNotInherited = [System.Collections.Generic.List[Object]]::new()
$inheritedSkus = [System.Collections.Generic.List[Object]]::new()
foreach ($user in $licensedUsersList) {
    foreach ($assignedLicense in $user.AssignedLicenses) {
        foreach ($skuMap in ($skuMapList | Where-Object SkuID -eq $assignedLicense.SkuId)) {
            $isInGroup = $false
            foreach ($groupId in $skuMap.GroupId) {
                $groupMemberList = $skuMap.Members
                foreach ($groupMember in $groupMemberList) {
                    #If this is assigned via group membership, populate the inheritedSkus array for use in Excel worksheet tab
                    if ($groupMember -eq $user.Id) {
                        $isInGroup = $true
                        $inheritedObj = [PSCustomObject]@{
                            SkuID = $skuMap.SkuID
                            GroupID = $skuMap.GroupId
                            GroupDisplayName = $skuMap.GroupDisplayName
                            UserID = $user.ID
                            UserPrincipalName = $user.UserPrincipalName
                            UserDisplayName = $user.DisplayName
                        }
                        $inheritedSkus.Add($inheritedObj)
                        break
                    }
                }
                # If the user is not part of any group assignation for that sku, add them to the list
                if (-not $isInGroup) {
                    $usersWithSkuNotInGroup = [PSCustomObject]@{
                        SkuID = $skuMap.SkuId
                        SkuPartName = $skuMap.SkuDisplayName
                        SkuLicenseName = $skuMap.SkuLicenseName
                        UserID = $user.ID
                        UserPrincipalName = $user.UserPrincipalName
                        UserDisplayName = $user.DisplayName
                    }
                    $usersNotInherited.Add($usersWithSkuNotInGroup)
                }
            }
        }
    }
}

# Get the current date and time in the format MM-DD-HH-MM
$timestamp = (Get-Date).ToString("MM-dd-HH-mm")
# Construct the filename with the timestamp
$filename = "C:\temp\MicrosoftLicenses_$timestamp.xlsx"
# Export the users who have the SKU but are not part of the corresponding groups
$usersNotInherited | Export-Excel -Path $filename -WorkSheetname 'DirectAssigned' -AutoSize -AutoFilter
# Add a new sheet for each SKU and export the data
foreach ($subscribedSku in $skuMapList) {
    # We only want tabs for SKUs that are assigned via a group
    if ($subscribedSku.GroupID -ne "" -and $subscribedSku.Members -ne "Not-In-Use") {
        # We don't want empty tabs if a group is assigned and not populated
        # We want to trust that MS updates their CSV when adding a new product, but just in case we'll use the skupartname if the license name is null
        if ( $null -eq $subscribedSku.SkuLicenseName ) {
            $sheetName = $subscribedSku.SkuDisplayName
        } else {
            $sheetName = $subscribedSku.SkuLicenseName
        }
        $users = $inheritedSkus | Where-Object { $_.SkuID -eq $subscribedSku.SkuId }
        $users | Select-Object -Property * -ExcludeProperty SkuId | Export-Excel -Path $filename -WorkSheetname $sheetName -AutoSize -AutoFilter
    }
}

Disconnect-MgGraph