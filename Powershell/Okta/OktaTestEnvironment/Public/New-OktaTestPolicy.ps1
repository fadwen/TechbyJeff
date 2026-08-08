function New-OktaTestPolicy {
    <#
    .SYNOPSIS
        Creates the seeded sign-on and password policies, with their rules

    .DESCRIPTION
        Policies are where an identity environment stops being a list of objects and starts
        having behaviour. Three are created, chosen so that precedence and scoping are both
        observable:

        - Admin-Session, scoped to the administrators group, whose rule only permits sign-in
          from the Corporate-Egress network zone.
        - Standard-Session, scoped to everyone, allowing sign-in from anywhere with a longer
          session. Two overlapping sign-on policies is the interesting part: a user in both
          groups is governed by the higher-priority one, and a report that lists policies
          without their order tells you nothing about what actually applies.
        - Contractor-Password, scoped to the rule-driven contractors group, with a longer
          minimum length and a shorter maximum age than the org default.

        Okta assigns priority by creation order, newest first, so the order of the CSV rows is
        the order of precedence. That is worth knowing before wondering why a policy seems to
        be ignored.

        Password policies carry their settings on the policy itself. Sign-on policies carry
        almost nothing useful until a rule is added, which is why each sign-on row here also
        defines one - a sign-on policy with no rules is inert, and inert-but-present is a
        confusing thing to find in a lab.

    .PARAMETER PolicyName
        Restrict the operation to these CSV policy names

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalPolicies, CreatedPolicies, ExistingPolicies, RulesCreated,
        Policies and Errors

    .EXAMPLE
        New-OktaTestPolicy -PassThru

    .EXAMPLE
        New-OktaTestPolicy -PolicyName Admin-Session -WhatIf

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Needs the groups it scopes to and the zones its rules reference, so run
        New-OktaTestGroup and New-OktaTestNetworkZone first.

        These policies govern real sign-in behaviour for the groups they name. On a shared
        tenant that is not a hypothetical: an admin who is only in the administrators group and
        is not on a listed IP range will be denied.

    .LINK
        New-OktaTestNetworkZone
        New-OktaTestGroup
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $dataPath = Get-OktaTestDataPath
    $rows = @(Import-Csv -Path (Join-Path $dataPath 'OktaPolicies.csv') -Encoding UTF8)
    $groupRows = @(Import-Csv -Path (Join-Path $dataPath 'OktaGroups.csv') -Encoding UTF8)

    if ($PolicyName) {
        $rows = @($rows | Where-Object { $PolicyName -contains $_.Name })
        $unknown = @($PolicyName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No policy definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalPolicies    = $rows.Count
        CreatedPolicies  = 0
        ExistingPolicies = 0
        RulesCreated     = 0
        Policies         = @()
        Errors           = @()
    }

    $oktaNameByKey = @{}
    foreach ($groupRow in $groupRows) {
        $oktaNameByKey[$groupRow.Name] = '{0}-{1}' -f $connection.Prefix, $groupRow.DisplayName
    }

    $groupIdByKey = @{}
    $seededGroups = @(Get-OktaTestSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)
    foreach ($group in $seededGroups) {
        $key = @($oktaNameByKey.Keys | Where-Object { $oktaNameByKey[$_] -eq $group.profile.name })
        if ($key.Count -eq 1) { $groupIdByKey[$key[0]] = $group.id }
    }

    $zoneIdByKey = @{}
    $liveZones = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/zones' `
        -Query @{ limit = 200 } -Paginate)
    foreach ($zone in $liveZones) {
        if ($zone.name -and $zone.name.StartsWith("$($connection.Prefix)-",
                [StringComparison]::OrdinalIgnoreCase)) {
            $zoneIdByKey[$zone.name.Substring($connection.Prefix.Length + 1)] = $zone.id
        }
    }

    $policies = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        $groupIds = @(
            foreach ($key in @($row.Groups -split ';' | Where-Object { $_ })) {
                if ($groupIdByKey.ContainsKey($key)) { $groupIdByKey[$key] }
                else {
                    $message = "Policy '$name' scopes to group '$key', which does not exist. Skipped."
                    $result.Errors += $message
                    Write-Warning $message
                }
            }
        )

        if ($groupIds.Count -eq 0) {
            # A policy with no group condition applies to everybody in the org. Creating one by
            # accident because a group lookup failed is exactly the kind of mistake that locks
            # people out, so this refuses rather than falling back to org-wide.
            $message = ("Policy '$name' resolved no groups, so it was not created. An " +
                'unscoped policy would apply to the whole org.')
            $result.Errors += $message
            Write-Warning $message
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, "Create Okta policy ($($row.Type))")) { continue }

        try {
            $existingPolicies = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/policies' `
                -Query @{ type = $row.Type; limit = 200 } -Paginate |
                Where-Object { $_.name -eq $name })

            if ($existingPolicies.Count -gt 0) {
                $policy = $existingPolicies[0]
                $result.ExistingPolicies++
                Write-Verbose "Reusing policy $name"
            }
            else {
                $body = [ordered]@{
                    type        = $row.Type
                    name        = $name
                    description = '{0} {1}' -f $row.Description, $connection.SeedMarker
                    status      = 'ACTIVE'
                    conditions  = @{ people = @{ groups = @{ include = $groupIds } } }
                }

                if ($row.Type -eq 'PASSWORD') {
                    $complexity = [ordered]@{
                        minLowerCase = 1; minUpperCase = 1; minNumber = 1; minSymbol = 1
                    }
                    if ($row.MinLength) { $complexity.minLength = [int]$row.MinLength }

                    $age = [ordered]@{ expireWarnDays = 7; historyCount = 4 }
                    if ($row.MaxAgeDays) { $age.maxAgeDays = [int]$row.MaxAgeDays }

                    $body.settings = @{ password = @{ complexity = $complexity; age = $age } }
                }

                $policy = Invoke-OktaTestRequest -Method POST -Path '/api/v1/policies' -Body $body
                $result.CreatedPolicies++
                Write-Verbose "Created policy $name"
            }

            $ruleName = $null
            if ($row.RuleName) {
                $ruleName = '{0}-{1}' -f $connection.Prefix, $row.RuleName

                $existingRules = @(Invoke-OktaTestRequest -Method GET `
                    -Path "/api/v1/policies/$($policy.id)/rules" |
                    Where-Object { $_.name -eq $ruleName })

                if ($existingRules.Count -eq 0) {
                    $network = @{ connection = 'ANYWHERE' }
                    if ($row.RuleZone) {
                        if ($zoneIdByKey.ContainsKey($row.RuleZone)) {
                            $network = @{ connection = 'ZONE'; include = @($zoneIdByKey[$row.RuleZone]) }
                        }
                        else {
                            $message = ("Policy '$name' rule references zone '$($row.RuleZone)', which " +
                                'does not exist. The rule was created for ANYWHERE instead.')
                            $result.Errors += $message
                            Write-Warning $message
                        }
                    }

                    $session = [ordered]@{ usePersistentCookie = $false }
                    if ($row.MaxSessionIdleMinutes) {
                        $session.maxSessionIdleMinutes = [int]$row.MaxSessionIdleMinutes
                    }
                    if ($row.MaxSessionLifetimeMinutes) {
                        $session.maxSessionLifetimeMinutes = [int]$row.MaxSessionLifetimeMinutes
                    }

                    $null = Invoke-OktaTestRequest -Method POST `
                        -Path "/api/v1/policies/$($policy.id)/rules" -Body @{
                            type       = 'SIGN_ON'
                            name       = $ruleName
                            conditions = @{ network = $network; authContext = @{ authType = 'ANY' } }
                            actions    = @{ signon = @{
                                access        = $row.RuleAccess
                                requireFactor = $false
                                session       = $session
                            } }
                        }
                    $result.RulesCreated++
                    Write-Verbose "Created rule $ruleName"
                }
            }

            $policies.Add([PSCustomObject]@{
                Id       = $policy.id
                Key      = $row.Name
                Name     = $name
                Type     = $row.Type
                Priority = $policy.priority
                Rule     = $ruleName
                Groups   = @($row.Groups -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create policy '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Policies = $policies.ToArray()

    if ($PassThru) { return $result }
}
