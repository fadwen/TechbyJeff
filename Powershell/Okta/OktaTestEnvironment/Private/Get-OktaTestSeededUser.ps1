function Get-OktaTestSeededUser {
    <#
    .SYNOPSIS
        Finds the users this module created, and only those

    .DESCRIPTION
        Teardown deletes users irreversibly, so what counts as "ours" needs to be something
        stronger than a naming convention that a real employee could coincidentally match.

        Two independent markers are used, and either one is enough:

        - profile.labSeedTag equal to the prefix. This is the authoritative one, written by
          New-OktaTestUser and defined in the custom schema. It cannot be produced by
          accident.
        - The login sitting under the seed email domain. This is the fallback for the case
          where the schema attribute was removed before the users were, which is exactly what
          happens if a teardown is interrupted halfway.

        Filtering happens here rather than in the API query on purpose. The tenant holds at
        most ten users, so fetching all of them costs one call, whereas an Okta search
        expression over a custom attribute depends on that attribute still existing and on
        the search index having caught up. Neither is true immediately after a failed run.

    .PARAMETER Prefix
        The seed tag value to match

    .PARAMETER EmailDomain
        The email domain the seeded logins live under

    .OUTPUTS
        Array of Okta user objects

    .EXAMPLE
        Get-OktaTestSeededUser -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'

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
        [string]$EmailDomain
    )

    # Deactivated users still need deleting, and the default listing hides them, so ask for
    # them explicitly as a second pass rather than relying on the default population.
    $active = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' -Query @{ limit = 200 } -Paginate)
    $deprovisioned = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' `
        -Query @{ limit = 200; filter = 'status eq "DEPROVISIONED"' } -Paginate)

    $all = @($active) + @($deprovisioned)

    $suffix = '@' + $EmailDomain.TrimStart('@')

    $seeded = $all | Where-Object {
        $taggedProfile = $_.profile
        $byTag = $taggedProfile.PSObject.Properties['labSeedTag'] -and
            $taggedProfile.labSeedTag -eq $Prefix
        $byDomain = $taggedProfile.login -and
            $taggedProfile.login.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)

        $byTag -or $byDomain
    }

    # The two listings can overlap if a user changes status between the calls.
    return @($seeded | Sort-Object -Property id -Unique)
}
