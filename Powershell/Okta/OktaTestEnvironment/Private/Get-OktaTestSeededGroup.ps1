function Get-OktaTestSeededGroup {
    <#
    .SYNOPSIS
        Finds the groups this module created, and only those

    .DESCRIPTION
        Okta group profiles hold nothing but a name and a description, so there is no custom
        attribute to hang a seed tag on the way there is for users. Both markers therefore
        have to live in those two fields, and both are required rather than either:

        - the name starts with the prefix and a hyphen
        - the description ends with the seed marker

        Requiring both is the point. A real group could plausibly be called OKTALAB-Something
        after somebody copies a naming convention, and a real group could plausibly carry a
        description mentioning the module. A group with both was written by this module.

        Built-in groups are excluded by type: Everyone is a BUILT_IN group and deleting it is
        not possible anyway, but filtering to OKTA_GROUP keeps the intent visible.

    .PARAMETER Prefix
        The group name prefix to match

    .PARAMETER SeedMarker
        The description suffix that confirms ownership

    .OUTPUTS
        Array of Okta group objects

    .EXAMPLE
        Get-OktaTestSeededGroup -Prefix 'OKTALAB' -SeedMarker '[seed:OKTALAB]'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SeedMarker
    )

    $groups = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups' `
        -Query @{ limit = 200; q = $Prefix } -Paginate)

    return @($groups | Where-Object {
        $_.type -eq 'OKTA_GROUP' -and
        $_.profile.name -and
        $_.profile.name.StartsWith("$Prefix-", [StringComparison]::OrdinalIgnoreCase) -and
        $_.profile.description -and
        $_.profile.description.EndsWith($SeedMarker, [StringComparison]::OrdinalIgnoreCase)
    })
}
