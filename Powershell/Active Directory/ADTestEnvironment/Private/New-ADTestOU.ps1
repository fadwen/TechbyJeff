function New-ADTestOU {
    <#
    .SYNOPSIS
        Creates an Active Directory OU with WhatIf support

    .DESCRIPTION
        Helper function to create OUs with consistent error handling and WhatIf support

    .PARAMETER Name
        Name of the OU to create

    .PARAMETER Path
        Parent path where the OU should be created

    .PARAMETER Description
        Description for the OU

    .EXAMPLE
        New-ADTestOU -Name "TestUsers" -Path "DC=contoso,DC=com" -Description "Test user accounts"

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $fullPath = "OU=$Name,$Path"

    try {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullPath'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($fullPath, "Create OU")) {
                New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description
                Write-Verbose "Created OU: $Name"
                return @{ Success = $true; Action = 'Created'; Message = "OU created: $Name" }
            } else {
                return @{ Success = $true; Action = 'WhatIf'; Message = "Would create OU: $Name" }
            }
        } else {
            Write-Verbose "OU already exists: $Name"
            return @{ Success = $true; Action = 'Skipped'; Message = "OU already exists: $Name" }
        }
    } catch {
        Write-Error "Failed to create OU '$Name': $($_.Exception.Message)"
        return @{ Success = $false; Action = 'Failed'; Message = "Failed to create OU '$Name': $($_.Exception.Message)" }
    }
}
