function Test-OktaTestPrerequisite {
    <#
    .SYNOPSIS
        Verifies that the module can do what it is about to be asked to do

    .DESCRIPTION
        Checks the things that are cheap to check and expensive to discover halfway through a
        seed run: an established connection, reachable data files, and enough licence
        headroom for the users about to be created.

        Every failure is collected before any is reported, so a first run against a fresh
        tenant tells you about all of the problems at once rather than one per attempt.

    .PARAMETER CheckDataFiles
        Also verify that the CSV seed files exist

    .PARAMETER RequiredUserSlots
        Also verify that this many user slots are free under the tenant's active user limit

    .PARAMETER ActiveUserLimit
        The tenant's active user ceiling, used with -RequiredUserSlots

    .OUTPUTS
        Boolean indicating whether all prerequisites are met

    .EXAMPLE
        if (-not (Test-OktaTestPrerequisite -CheckDataFiles -RequiredUserSlots 8)) {
            throw 'Prerequisites not met'
        }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$CheckDataFiles,

        [Parameter()]
        [int]$RequiredUserSlots = 0,

        [Parameter()]
        [int]$ActiveUserLimit = 10
    )

    $issues = @()

    $connection = Get-OktaTestConnection -AllowNone
    if (-not $connection) {
        $issues += ('Not connected to Okta. Run Connect-OktaTestEnvironment first.')
    }

    if ($CheckDataFiles) {
        try {
            $dataPath = Get-OktaTestDataPath
            $requiredFiles = @(
                'OktaUsers.csv', 'OktaGroups.csv', 'OktaGroupRules.csv', 'OktaProfileAttributes.csv',
                'OktaApps.csv', 'OktaUserTypes.csv', 'OktaNetworkZones.csv',
                'OktaPolicies.csv', 'OktaLinkedObjects.csv', 'OktaTrustedOrigins.csv',
                'OktaEventHooks.csv')

            foreach ($file in $requiredFiles) {
                $filePath = Join-Path -Path $dataPath -ChildPath $file
                if (-not (Test-Path -Path $filePath)) {
                    $issues += "Required data file missing: $filePath"
                }
            }
        }
        catch {
            $issues += "Data path validation failed: $($_.Exception.Message)"
        }
    }

    if ($connection -and $RequiredUserSlots -gt 0) {
        try {
            # AvailableForSeed, not Available. Users this module already created are updated
            # rather than duplicated, so they need no new slot. Checking Available instead made
            # the module refuse to re-run against the environment it had just built.
            $headroom = Get-OktaTestUserHeadroom -ActiveUserLimit $ActiveUserLimit
            if ($headroom.AvailableForSeed -lt $RequiredUserSlots) {
                $reuse = if ($headroom.SeededInUse -gt 0) {
                    " ($($headroom.SeededInUse) of them already seeded and reusable)"
                }
                else { '' }

                $issues += ("The tenant holds $($headroom.InUse) of its $($headroom.Limit) active " +
                    "users$reuse, leaving room for $($headroom.AvailableForSeed). Seeding needs " +
                    "$RequiredUserSlots. Remove users, lower -UserCount, or raise " +
                    '-ActiveUserLimit if this tenant is not a trial org.')
            }
        }
        catch {
            $issues += "Could not read the tenant's current user count: $($_.Exception.Message)"
        }
    }

    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) { Write-Error $issue }
        return $false
    }

    return $true
}
