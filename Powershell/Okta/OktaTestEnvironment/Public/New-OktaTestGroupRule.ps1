function New-OktaTestGroupRule {
    <#
    .SYNOPSIS
        Creates the group rules that populate the automatic groups

    .DESCRIPTION
        Group rules are Okta's answer to dynamic membership: an expression over the user
        profile, evaluated by Okta, that maintains a group without anybody assigning anyone.
        Since Okta groups cannot nest, rules are the closest it gets to structural membership,
        and they are worth having in a lab because they fail in ways direct assignment does not.

        Three rules ship, each reading a different kind of attribute:

        - a boolean custom attribute (labIsContractor)
        - an enumerated custom attribute (labClearanceLevel)
        - a base attribute through an expression function (department)

        Two behaviours are worth knowing, both confirmed against a real tenant rather than
        assumed:

        - Rules are evaluated against staged and suspended users, not only active ones. The
          contractor rule picks up both seeded contractors even though one has never been
          activated and the other is suspended. That is worth knowing because it is the
          opposite of what "only active users are in scope" would suggest, and it means a
          rule granting an entitlement reaches accounts nobody has signed into.
        - Rules apply asynchronously. Membership appears a short while after activation rather
          than immediately, so a report run straight afterwards can understate it.

    .PARAMETER RuleName
        Restrict the operation to these CSV rule names. The prefix is added automatically.

    .PARAMETER SkipActivation
        Create the rules but leave them inactive. An inactive rule assigns nobody, which is a
        useful state to test a compliance report against.

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalRules, CreatedRules, UpdatedRules, ActivatedRules, Rules and
        Errors

    .EXAMPLE
        New-OktaTestGroupRule

    .EXAMPLE
        New-OktaTestGroupRule -SkipActivation -PassThru
        Creates the rules inactive, so you can watch membership appear when you activate them

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        The target groups must exist first, so run New-OktaTestGroup before this.

    .LINK
        New-OktaTestGroup
        New-OktaTestUser
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$RuleName,

        [Parameter()]
        [switch]$SkipActivation,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $dataPath = Get-OktaTestDataPath
    $rows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaGroupRules.csv') -Encoding UTF8)
    $groupRows = @(Import-Csv -Path (Join-Path -Path $dataPath -ChildPath 'OktaGroups.csv') -Encoding UTF8)

    if ($RuleName) {
        $rows = @($rows | Where-Object { $RuleName -contains $_.Name })
        $unknown = @($RuleName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No rule definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalRules     = $rows.Count
        CreatedRules   = 0
        UpdatedRules   = 0
        ActivatedRules = 0
        Rules          = @()
        Errors         = @()
    }

    # The CSV names a target by its ASCII key; Okta knows it by its prefixed display name.
    $oktaNameByKey = @{}
    foreach ($groupRow in $groupRows) {
        $oktaNameByKey[$groupRow.Name] = '{0}-{1}' -f $connection.Prefix, $groupRow.DisplayName
    }

    $existingGroups = @(Get-OktaTestSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)
    $groupIdByName = @{}
    foreach ($group in $existingGroups) { $groupIdByName[$group.profile.name] = $group.id }

    $existingRules = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups/rules' `
        -Query @{ limit = 200 } -Paginate)

    $rules = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $ruleFullName = '{0}-Rule-{1}' -f $connection.Prefix, $row.Name
        $targetOktaName = $oktaNameByKey[$row.TargetGroup]

        if (-not $targetOktaName -or -not $groupIdByName.ContainsKey($targetOktaName)) {
            $message = ("Rule '$ruleFullName' targets group '$($row.TargetGroup)', which does not " +
                'exist. Run New-OktaTestGroup first. Skipped.')
            $result.Errors += $message
            Write-Warning $message
            continue
        }

        $activate = (-not $SkipActivation) -and ([bool]::Parse($row.Activate))

        if (-not $PSCmdlet.ShouldProcess($ruleFullName, 'Create Okta group rule')) { continue }

        $body = @{
            type       = 'group_rule'
            name       = $ruleFullName
            conditions = @{
                people     = @{
                    users  = @{ exclude = @() }
                    groups = @{ exclude = @() }
                }
                expression = @{
                    value = $row.Expression
                    type  = 'urn:okta:expression:1.0'
                }
            }
            actions    = @{
                assignUserToGroups = @{ groupIds = @($groupIdByName[$targetOktaName]) }
            }
        }

        try {
            $existing = @($existingRules | Where-Object { $_.name -eq $ruleFullName })

            if ($existing.Count -gt 0) {
                $ruleId = $existing[0].id

                # Okta refuses to modify an active rule. Deactivating first is not optional,
                # and doing it unconditionally is simpler than reading the current status and
                # costs one call that would usually be made anyway.
                try {
                    $null = Invoke-OktaTestRequest -Method POST `
                        -Path "/api/v1/groups/rules/$ruleId/lifecycle/deactivate"
                }
                catch {
                    Write-Verbose "Rule $ruleFullName was already inactive."
                }

                $rule = Invoke-OktaTestRequest -Method PUT -Path "/api/v1/groups/rules/$ruleId" -Body $body
                $result.UpdatedRules++
            }
            else {
                $rule = Invoke-OktaTestRequest -Method POST -Path '/api/v1/groups/rules' -Body $body
                $result.CreatedRules++
            }

            if ($activate) {
                $null = Invoke-OktaTestRequest -Method POST `
                    -Path "/api/v1/groups/rules/$($rule.id)/lifecycle/activate"
                $result.ActivatedRules++
            }

            $rules.Add([PSCustomObject]@{
                Id          = $rule.id
                Name        = $ruleFullName
                TargetGroup = $targetOktaName
                Expression  = $row.Expression
                Active      = $activate
            })
        }
        catch {
            $message = "Failed to create rule '$ruleFullName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Rules = $rules.ToArray()

    if ($result.ActivatedRules -gt 0) {
        Write-Verbose ('Group rules evaluate asynchronously; membership will appear shortly, and ' +
            'only for active users.')
    }

    if ($PassThru) { return $result }
}
