function Get-OktaTestSchemaPath {
    <#
    .SYNOPSIS
        Resolves the schema path for a user type

    .DESCRIPTION
        Every Okta user type has its own schema, and the only reliable way to reach a non-default
        one is the link on the type object. The schema id is not derivable from the type id, so
        there is nothing to construct by hand - it has to be looked up.

        The default type is the exception: its schema really does live at a fixed path, which is
        why almost every script only ever touches that one and silently misses the rest.

    .PARAMETER UserTypeKey
        The CSV user type key, for example Contractor. Empty or absent means the default type.

    .PARAMETER Prefix
        The connection prefix, used to build the type's API name

    .OUTPUTS
        String path to the schema

    .EXAMPLE
        Get-OktaTestSchemaPath -Prefix 'OKTALAB'
        Returns the default user schema path

    .EXAMPLE
        Get-OktaTestSchemaPath -UserTypeKey 'Contractor' -Prefix 'OKTALAB'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$UserTypeKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($UserTypeKey)) {
        return '/api/v1/meta/schemas/user/default'
    }

    $typeName = '{0}{1}' -f $Prefix.ToLowerInvariant(), $UserTypeKey
    $types = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/types/user')
    $match = @($types | Where-Object { $_.name -eq $typeName })

    if ($match.Count -eq 0) {
        throw ("User type '$typeName' does not exist, so its schema cannot be reached. Run " +
            'New-OktaTestUserType first.')
    }

    if (-not $match[0]._links -or -not $match[0]._links.schema -or -not $match[0]._links.schema.href) {
        throw "User type '$typeName' exposes no schema link."
    }

    return ([uri]$match[0]._links.schema.href).AbsolutePath
}
