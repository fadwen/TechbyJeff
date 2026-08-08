function Get-OktaTestUserHeadroom {
    <#
    .SYNOPSIS
        Reports how many more users the tenant will accept before it hits its licence ceiling

    .DESCRIPTION
        The Okta Integrator Free Plan allows ten active users, and your own admin account is
        one of them. That is the single constraint this whole module is shaped around, and the
        reason it seeds eight users rather than the hundreds a test-data generator would
        normally produce.

        The count comes from GET /api/v1/users, which by default lists everything that is not
        DEPROVISIONED. That is the same population the licence counts, so a deactivated user
        left behind from a previous run does not eat headroom, but a suspended or staged one
        does. Both of those were confirmed against a real tenant rather than assumed.

        The important distinction is between Available and AvailableForSeed. A user this module
        already created needs no new licence slot, because seeding updates it rather than
        creating a second one. Counting those against the ceiling would mean the module refuses
        to re-run against the environment it just built, which is exactly the situation you are
        in after a seed run fails halfway and you want to fix the cause and try again.

    .PARAMETER ActiveUserLimit
        The tenant's active user ceiling. Ten for the Integrator Free Plan.

    .OUTPUTS
        PSCustomObject with Limit, InUse, Available, SeededInUse, AvailableForSeed and
        ExistingLogins

    .EXAMPLE
        $headroom = Get-OktaTestUserHeadroom -ActiveUserLimit 10
        if ($headroom.AvailableForSeed -lt 8) { throw 'Not enough room' }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.1.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$ActiveUserLimit = 10
    )

    $connection = Get-OktaTestConnection

    $existing = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' -Query @{ limit = 200 } -Paginate)

    # Classified from the listing already in hand rather than by calling Get-OktaTestSeededUser,
    # which would repeat the same request. The rule matches that function's: the seed tag, or
    # the seed email domain as a true suffix.
    $suffix = '@' + $connection.EmailDomain.TrimStart('@')
    $seeded = @($existing | Where-Object {
        $userProfile = $_.profile
        ($userProfile.PSObject.Properties['labSeedTag'] -and
            $userProfile.labSeedTag -eq $connection.Prefix) -or
        ($userProfile.login -and
            $userProfile.login.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase))
    })

    $inUse = $existing.Count
    $available = [Math]::Max(0, $ActiveUserLimit - $inUse)

    return [PSCustomObject]@{
        Limit            = $ActiveUserLimit
        InUse            = $inUse
        Available        = $available
        SeededInUse      = $seeded.Count
        AvailableForSeed = $available + $seeded.Count
        ExistingLogins   = @($existing | ForEach-Object { $_.profile.login })
    }
}
