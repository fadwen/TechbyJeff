#Requires -Modules ExchangePowerShell
Import-Module Microsoft.Online.SharePoint.Powershell -UseWindowsPowerShell -DisableNameChecking
#Tenant Admin Site
$AdminSiteURL="https://{tenantname}-admin.sharepoint.com" 
$OwnerEmail = {adminUPN}

Connect-SPOService -Url $AdminSiteURL
$sites = Get-SPOSite -IncludePersonalSite $true -Limit All | Where-Object { $_.Url -like "*-my.sharepoint.com/personal/*" }

Connect-IPPSSession -UserPrincipalName $OwnerEmail  
[array]$HoldURLs = import-csv C:\Users\$user\onedrivesites.csv
ForEach ($HoldURL in $HoldURLs) {
    Try {
        $site = $HoldURL.url
        $Holds = Invoke-HoldRemovalAction -Action GetHolds -Sharepointlocation $site
        if ($null -ne $Holds) {
            ForEach ($Hold in $Holds) {
                Invoke-HoldRemovalAction -Action RemoveHold -Sharepointlocation $site -Holdid $Hold -force
            }
        }
    } catch {

    }
}
Disconnect-IPPSSession

ForEach ($site in $sites) {
    try {
    Write-Host "Removing site: $($site.Url)"
    if ($site.LockState -ne "Unlock") {
        Set-SPOSite -Identity $site.Url -LockState Unlock
    }
    if ($site.Owner -ne $OwnerEmail) {
        Set-SPOSite -Identity $site.Url -Owner $OwnerEmail -NoWait
    }
    Remove-SPOSite -Confirm:$false -Identity $site.Url -NoWait
    } catch {
        Write-Host "Failed to remove site: $($site.Url)"
    }
}

Disconnect-SPOService