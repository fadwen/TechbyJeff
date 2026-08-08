function New-OktaTestGroup {
    <#
    .SYNOPSIS
        Creates the seeded Okta groups and assigns their members

    .DESCRIPTION
        Creates seventeen groups from Data\OktaGroups.csv. The tenant caps users at ten, not
        groups, so this is where the environment gets its complexity back: eight users spread
        across seventeen groups produce far more interesting membership shapes than eight
        users in eight groups.

        The shapes are chosen on purpose:

        - Overlapping membership. Tomás is in both Engineering and IT, so a script that
          assumes one department per user is wrong about him.
        - A group with exactly one member, and a group with none. Empty is the case reports
          get wrong, because a group that is empty and a group that failed to resolve look
          identical in most output.
        - Two groups whose display names are not ASCII, Zürich Site Access and Ingénierie
          Réseau, for the same reason the users have accented names.
        - Three groups reserved for group rules, never assigned to directly. If a rule stops
          working, its group empties out and the manually assigned ones do not, which makes
          the failure visible instead of ambiguous.

        Okta groups do not nest, so there is no group-inside-a-group structure to model here.
        Group rules are the nearest equivalent, and they live in New-OktaTestGroupRule.

        Existing groups are updated rather than duplicated, so this is safe to re-run.

    .PARAMETER GroupName
        Restrict the operation to these CSV group names, for example Dept-Engineering. The
        prefix is added automatically, so pass the bare name.

    .PARAMETER SkipMemberAssignment
        Create the groups but leave them empty

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalGroups, CreatedGroups, UpdatedGroups, MembersAdded, Groups
        and Errors

    .EXAMPLE
        New-OktaTestGroup
        Creates every group and assigns members

    .EXAMPLE
        New-OktaTestGroup -SkipMemberAssignment -PassThru
        Creates the group shells only, for testing an assignment script against

    .EXAMPLE
        New-OktaTestGroup -GroupName Dept-Engineering, Dept-Sales -WhatIf

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Members are matched to users by login, so run New-OktaTestUser first. A member that
        does not resolve is reported and skipped rather than failing the group.

    .LINK
        New-OktaTestUser
        New-OktaTestGroupRule
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$GroupName,

        [Parameter()]
        [switch]$SkipMemberAssignment,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $csvPath = Join-Path -Path (Get-OktaTestDataPath) -ChildPath 'OktaGroups.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)

    if ($GroupName) {
        $rows = @($rows | Where-Object { $GroupName -contains $_.Name })
        $unknown = @($GroupName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalGroups   = $rows.Count
        CreatedGroups = 0
        UpdatedGroups = 0
        MembersAdded  = 0
        Groups        = @()
        Errors        = @()
    }

    # One listing up front rather than a lookup per member. Membership is expressed as logins
    # in the CSV and ids in the API, and at eight users the whole mapping costs one call.
    $userIdByLogin = @{}
    if (-not $SkipMemberAssignment) {
        $seeded = @(Get-OktaTestSeededUser -Prefix $connection.Prefix `
            -EmailDomain $connection.EmailDomain)
        foreach ($user in $seeded) {
            $userIdByLogin[$user.profile.login] = $user.id
        }
    }

    $groups = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        # The display name is what goes to Okta, so the accented names actually reach the
        # directory. The CSV Name column stays ASCII and is the key that rules and member
        # lists refer to.
        $oktaName = '{0}-{1}' -f $connection.Prefix, $row.DisplayName
        $description = '{0} {1}' -f $row.Description, $connection.SeedMarker

        if (-not $PSCmdlet.ShouldProcess($oktaName, 'Create Okta group')) { continue }

        try {
            $existing = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups' `
                -Query @{ q = $oktaName; limit = 50 } -Paginate |
                Where-Object { $_.profile.name -eq $oktaName })

            if ($existing.Count -gt 0) {
                $group = Invoke-OktaTestRequest -Method PUT -Path "/api/v1/groups/$($existing[0].id)" `
                    -Body @{ profile = @{ name = $oktaName; description = $description } }
                $result.UpdatedGroups++
                Write-Verbose "Updated group $oktaName"
            }
            else {
                $group = Invoke-OktaTestRequest -Method POST -Path '/api/v1/groups' `
                    -Body @{ profile = @{ name = $oktaName; description = $description } }
                $result.CreatedGroups++
                Write-Verbose "Created group $oktaName"
            }

            $assigned = @()

            if (-not $SkipMemberAssignment) {
                foreach ($memberPrefix in @($row.Members -split ';' | Where-Object { $_ })) {
                    $login = '{0}@{1}' -f $memberPrefix, $connection.EmailDomain

                    if (-not $userIdByLogin.ContainsKey($login)) {
                        $message = "Group '$oktaName' lists '$login', which does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # PUT is idempotent here: adding a user who is already a member returns
                    # 204 rather than an error, so a re-run does not need a membership check.
                    $null = Invoke-OktaTestRequest -Method PUT `
                        -Path "/api/v1/groups/$($group.id)/users/$($userIdByLogin[$login])"
                    $assigned += $login
                    $result.MembersAdded++
                }
            }

            $groups.Add([PSCustomObject]@{
                Id         = $group.id
                Key        = $row.Name
                Name       = $oktaName
                Category   = $row.Category
                Assignment = $row.Assignment
                Members    = $assigned
            })
        }
        catch {
            $message = "Failed to create group '$oktaName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Groups = $groups.ToArray()

    Write-Verbose ("Groups: $($result.CreatedGroups) created, $($result.UpdatedGroups) updated, " +
        "$($result.MembersAdded) memberships, $($result.Errors.Count) problems")

    if ($PassThru) { return $result }
}
