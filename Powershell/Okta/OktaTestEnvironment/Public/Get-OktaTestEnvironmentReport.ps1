function Get-OktaTestEnvironmentReport {
    <#
    .SYNOPSIS
        Reports on what this module has created in the connected tenant

    .DESCRIPTION
        Reads back the seeded users, groups, memberships, group rules, custom schema
        attributes and service app, and renders them.

        The report is the fastest way to answer the two questions that come up constantly with
        a licence-capped tenant: how many user slots are left, and did the group rules
        actually populate anything. Both are shown first for that reason.

        Memberships are read per group rather than per user, because Okta's group membership
        endpoint is authoritative and a user's own record does not list its groups.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV. CSV writes one file per object type, since users, groups
        and rules have nothing in common to flatten into a single table.

    .PARAMETER OutputPath
        Destination file for JSON and HTML, or destination folder for CSV. Required for
        anything other than Console.

    .PARAMETER PassThru
        Return the report object as well as rendering it

    .OUTPUTS
        PSCustomObject describing the environment, when -PassThru is used

    .EXAMPLE
        Get-OktaTestEnvironmentReport
        Prints a summary to the console

    .EXAMPLE
        Get-OktaTestEnvironmentReport -OutputFormat HTML -OutputPath .\okta-lab.html

    .EXAMPLE
        Get-OktaTestEnvironmentReport -OutputFormat CSV -OutputPath .\reports\
        Writes OktaLabUsers.csv, OktaLabGroups.csv and OktaLabRules.csv

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        CSV export is written as UTF-8 explicitly. Windows PowerShell's Export-Csv defaults to
        ASCII and would replace every accented character in the seeded names with a question
        mark, which is the exact data loss those names exist to expose.

    .LINK
        New-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console rendering is one of the supported output formats.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $headroom = Get-OktaTestUserHeadroom -ActiveUserLimit $connection.ActiveUserLimit
    $users = @(Get-OktaTestSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
    $groups = @(Get-OktaTestSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)

    $rulePrefix = '{0}-Rule-' -f $connection.Prefix
    $rules = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups/rules' -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith($rulePrefix, [StringComparison]::OrdinalIgnoreCase) })

    $apps = @(Get-OktaTestSeededApp -Prefix $connection.Prefix `
        -EmailDomain $connection.EmailDomain -IncludeServiceApp)

    # Every user type, not just the default. Reading only the default schema is the exact
    # mistake the second user type exists to expose, so the report must not make it.
    $userTypes = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/types/user')
    $ownedTypes = @($userTypes | Where-Object {
        $_.name -and $_.name.StartsWith($connection.Prefix.ToLowerInvariant(),
            [StringComparison]::OrdinalIgnoreCase)
    })

    $customAttributes = foreach ($type in $userTypes) {
        $schemaPath = '/api/v1/meta/schemas/user/default'
        if (-not $type.default -and $type._links -and $type._links.schema) {
            $schemaPath = ([uri]$type._links.schema.href).AbsolutePath
        }

        $schema = $null
        try { $schema = Invoke-OktaTestRequest -Method GET -Path $schemaPath }
        catch { Write-Verbose "Could not read schema for '$($type.name)': $($_.Exception.Message)" }

        if ($schema -and $schema.definitions.custom.properties) {
            $schema.definitions.custom.properties.PSObject.Properties |
                Where-Object { $_.Name -like 'lab*' } |
                ForEach-Object {
                    [PSCustomObject]@{
                        UserType = $type.name
                        Name     = $_.Name
                        Title    = $_.Value.title
                        Type     = $_.Value.type
                    }
                }
        }
    }

    $zones = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/zones' -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    # There is no "all policies" listing; the endpoint requires a type.
    $policies = @(foreach ($policyType in @('OKTA_SIGN_ON', 'PASSWORD')) {
        Invoke-OktaTestRequest -Method GET -Path '/api/v1/policies' `
            -Query @{ type = $policyType; limit = 200 } -Paginate |
            Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
                [StringComparison]::OrdinalIgnoreCase) }
    })

    $origins = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/trustedOrigins' `
        -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    $hooks = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/eventHooks' `
        -Query @{ limit = 200 } -Paginate |
        Where-Object { $_.name -and $_.name.StartsWith("$($connection.Prefix)-",
            [StringComparison]::OrdinalIgnoreCase) })

    $linkedObjects = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/schemas/user/linkedObjects')

    $userReport = foreach ($user in $users) {
        [PSCustomObject]@{
            Login      = $user.profile.login
            Name       = $user.profile.displayName
            Status     = $user.status
            Title      = $user.profile.title
            Department = $user.profile.department
            Manager    = $user.profile.manager
            Clearance  = $user.profile.labClearanceLevel
            Contractor = $user.profile.labIsContractor
            RiskScore  = $user.profile.labRiskScore
        }
    }

    $groupReport = foreach ($group in $groups) {
        # Wrapped for the same reason the app assignments are: a permission problem or a rate
        # limit on ONE group should cost you that group's member count, not the whole report.
        $members = @()
        try {
            $members = @(Invoke-OktaTestRequest -Method GET -Path "/api/v1/groups/$($group.id)/users" `
                -Query @{ limit = 200 } -Paginate)
        }
        catch {
            Write-Warning ("Could not read members of '$($group.profile.name)': " +
                "$($_.Exception.Message). Its count is reported as zero.")
        }

        [PSCustomObject]@{
            Name        = $group.profile.name
            Description = $group.profile.description
            MemberCount = $members.Count
            Members     = @($members | ForEach-Object { $_.profile.login })
        }
    }

    # Assignments are read per app rather than per user, because Okta's app-user endpoint is
    # authoritative and a user's own record does not list the apps they can reach. The scope
    # field is what distinguishes a direct assignment from a group-derived one, and keeping
    # both counts separate is the whole point: an access review that reports only the total
    # cannot tell you who would lose access if a group were unassigned.
    $appReport = foreach ($app in $apps) {
        $assignedGroups = @()
        $assignedUsers = @()
        try {
            $assignedGroups = @(Invoke-OktaTestRequest -Method GET `
                -Path "/api/v1/apps/$($app.id)/groups" -Query @{ limit = 200 } -Paginate)
            $assignedUsers = @(Invoke-OktaTestRequest -Method GET `
                -Path "/api/v1/apps/$($app.id)/users" -Query @{ limit = 200 } -Paginate)
        }
        catch {
            Write-Verbose "Could not read assignments for '$($app.label)': $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            Label       = $app.label
            Id          = $app.id
            Status      = $app.status
            SignOnMode  = $app.signOnMode
            GroupCount  = $assignedGroups.Count
            UserCount   = $assignedUsers.Count
            DirectUsers = @($assignedUsers | Where-Object { $_.scope -eq 'USER' } |
                ForEach-Object { $_.credentials.userName })
        }
    }

    $ruleReport = foreach ($rule in $rules) {
        [PSCustomObject]@{
            Name       = $rule.name
            Status     = $rule.status
            Expression = $rule.conditions.expression.value
            TargetIds  = @($rule.actions.assignUserToGroups.groupIds)
        }
    }

    $report = [PSCustomObject]@{
        GeneratedUtc     = [DateTime]::UtcNow.ToString('o')
        OrgUrl           = $connection.OrgUrl
        Prefix           = $connection.Prefix
        AuthType         = $connection.AuthType
        Licence          = [PSCustomObject]@{
            ActiveUserLimit = $headroom.Limit
            InUse           = $headroom.InUse
            Available       = $headroom.Available
        }
        Users            = @($userReport)
        Groups           = @($groupReport)
        GroupRules       = @($ruleReport)
        CustomAttributes = @($customAttributes)
        Apps             = @($appReport)
        UserTypes        = @($ownedTypes | ForEach-Object {
            [PSCustomObject]@{ Name = $_.name; DisplayName = $_.displayName; Id = $_.id }
        })
        NetworkZones     = @($zones | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.name
                Usage    = $_.usage
                Status   = $_.status
                Gateways = @($_.gateways | ForEach-Object { $_.value })
            }
        })
        Policies         = @($policies | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.name
                Type     = $_.type
                Status   = $_.status
                Priority = $_.priority
            }
        })
        TrustedOrigins   = @($origins | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.name
                Origin = $_.origin
                Scopes = @($_.scopes | ForEach-Object { $_.type })
            }
        })
        EventHooks       = @($hooks | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.name
                Status = $_.status
                Uri    = $_.channel.config.uri
                Events = @($_.events.items)
            }
        })
        LinkedObjects    = @($linkedObjects | ForEach-Object {
            [PSCustomObject]@{ Primary = $_.primary.name; Associated = $_.associated.name }
        })
    }

    switch ($OutputFormat) {
        'Console' {
            Write-OktaTestProgress -Message "Okta Test Environment - $($report.OrgUrl)" -Type Header

            $licenceColour = if ($headroom.Available -le 0) { 'Red' } else { 'Green' }
            Write-Host ("Active users: $($headroom.InUse)/$($headroom.Limit) " +
                "($($headroom.Available) free)") -ForegroundColor $licenceColour

            Write-Host "`nSeeded users ($($userReport.Count)):" -ForegroundColor Cyan
            $userReport | Format-Table Login, Status, Department, Clearance, Contractor -AutoSize |
                Out-String | Write-Host

            Write-Host "Groups ($($groupReport.Count)):" -ForegroundColor Cyan
            $groupReport | Format-Table Name, MemberCount -AutoSize | Out-String | Write-Host

            Write-Host "Group rules ($($ruleReport.Count)):" -ForegroundColor Cyan
            $ruleReport | Format-Table Name, Status, Expression -AutoSize | Out-String | Write-Host

            Write-Host "User types ($(@($report.UserTypes).Count) beyond the default):" -ForegroundColor Cyan
            $report.UserTypes | Format-Table Name, DisplayName -AutoSize | Out-String | Write-Host

            $attrHeading = 'Custom attributes ({0} across all schemas):' -f @($customAttributes).Count
            Write-Host $attrHeading -ForegroundColor Cyan
            $customAttributes | Format-Table UserType, Name, Type, Title -AutoSize | Out-String | Write-Host

            Write-Host "Apps ($(@($report.Apps).Count)):" -ForegroundColor Cyan
            $report.Apps | Format-Table Label, SignOnMode, GroupCount, UserCount -AutoSize |
                Out-String | Write-Host

            Write-Host "Network zones ($(@($report.NetworkZones).Count)):" -ForegroundColor Cyan
            $report.NetworkZones | Select-Object Name, Usage, Status,
                @{ Name = 'Gateways'; Expression = { $_.Gateways -join ', ' } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Policies ($(@($report.Policies).Count)):" -ForegroundColor Cyan
            $report.Policies | Format-Table Name, Type, Status, Priority -AutoSize |
                Out-String | Write-Host

            Write-Host "Trusted origins ($(@($report.TrustedOrigins).Count)):" -ForegroundColor Cyan
            $report.TrustedOrigins | Select-Object Name, Origin,
                @{ Name = 'Scopes'; Expression = { $_.Scopes -join ', ' } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Event hooks ($(@($report.EventHooks).Count)):" -ForegroundColor Cyan
            $report.EventHooks | Select-Object Name, Status, Uri,
                @{ Name = 'Events'; Expression = { @($_.Events).Count } } |
                Format-Table -AutoSize | Out-String | Write-Host

            Write-Host "Linked objects ($(@($report.LinkedObjects).Count)):" -ForegroundColor Cyan
            $report.LinkedObjects | Format-Table Primary, Associated -AutoSize |
                Out-String | Write-Host
        }

        'JSON' {
            $json = $report | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($json))
            Write-OktaTestProgress -Message "JSON report written to $OutputPath" -Type Success
        }

        'CSV' {
            if (-not (Test-Path -Path $OutputPath)) {
                $null = New-Item -Path $OutputPath -ItemType Directory -Force
            }

            # -Encoding UTF8 is not optional here. The default on Windows PowerShell is ASCII,
            # and the seeded directory is full of names that do not survive it.
            $userReport | Export-Csv -Path (Join-Path $OutputPath 'OktaLabUsers.csv') `
                -NoTypeInformation -Encoding UTF8
            $groupReport | Select-Object Name, Description, MemberCount,
                @{ Name = 'Members'; Expression = { $_.Members -join ';' } } |
                Export-Csv -Path (Join-Path $OutputPath 'OktaLabGroups.csv') -NoTypeInformation -Encoding UTF8
            $ruleReport | Select-Object Name, Status, Expression |
                Export-Csv -Path (Join-Path $OutputPath 'OktaLabRules.csv') -NoTypeInformation -Encoding UTF8
            $report.Apps | Select-Object Label, SignOnMode, Status, GroupCount, UserCount,
                @{ Name = 'DirectUsers'; Expression = { $_.DirectUsers -join ';' } } |
                Export-Csv -Path (Join-Path $OutputPath 'OktaLabApps.csv') -NoTypeInformation -Encoding UTF8
            $report.Policies | Export-Csv -Path (Join-Path $OutputPath 'OktaLabPolicies.csv') `
                -NoTypeInformation -Encoding UTF8
            $customAttributes | Export-Csv -Path (Join-Path $OutputPath 'OktaLabAttributes.csv') `
                -NoTypeInformation -Encoding UTF8

            Write-OktaTestProgress -Message "CSV reports written to $OutputPath" -Type Success
        }

        'HTML' {
            $style = @'
<style>
body { font-family: Segoe UI, system-ui, sans-serif; margin: 2rem; color: #1f2933; }
h1 { border-bottom: 2px solid #005b9f; padding-bottom: .3rem; }
h2 { margin-top: 2rem; color: #005b9f; }
table { border-collapse: collapse; width: 100%; margin-bottom: 1rem; }
th, td { border: 1px solid #d3d8de; padding: .4rem .6rem; text-align: left; font-size: .9rem; }
th { background: #eef3f8; }
tr:nth-child(even) td { background: #fafbfc; }
.warn { color: #b34700; font-weight: 600; }
</style>
'@
            $licenceLine = "Active users: $($headroom.InUse) of $($headroom.Limit), $($headroom.Available) free"
            if ($headroom.Available -le 0) { $licenceLine = "<span class='warn'>$licenceLine</span>" }

            $sections = @(
                "<h1>Okta Test Environment</h1>"
                ("<p>$($report.OrgUrl) &mdash; prefix $($report.Prefix) &mdash; " +
                    "generated $($report.GeneratedUtc)</p>")
                "<p>$licenceLine</p>"
                "<h2>Users</h2>"
                ($userReport | ConvertTo-Html -Fragment)
                "<h2>Groups</h2>"
                ($groupReport | Select-Object Name, MemberCount,
                    @{ Name = 'Members'; Expression = { $_.Members -join ', ' } } | ConvertTo-Html -Fragment)
                "<h2>Group rules</h2>"
                ($ruleReport | Select-Object Name, Status, Expression | ConvertTo-Html -Fragment)
                "<h2>User types</h2>"
                ($report.UserTypes | ConvertTo-Html -Fragment)
                "<h2>Custom attributes</h2>"
                ($customAttributes | ConvertTo-Html -Fragment)
                "<h2>Network zones</h2>"
                ($report.NetworkZones | Select-Object Name, Usage, Status,
                    @{ Name = 'Gateways'; Expression = { $_.Gateways -join ', ' } } |
                    ConvertTo-Html -Fragment)
                "<h2>Policies</h2>"
                ($report.Policies | ConvertTo-Html -Fragment)
                "<h2>Trusted origins</h2>"
                ($report.TrustedOrigins | Select-Object Name, Origin,
                    @{ Name = 'Scopes'; Expression = { $_.Scopes -join ', ' } } |
                    ConvertTo-Html -Fragment)
                "<h2>Event hooks</h2>"
                ($report.EventHooks | Select-Object Name, Status, Uri,
                    @{ Name = 'Events'; Expression = { $_.Events -join ', ' } } |
                    ConvertTo-Html -Fragment)
                "<h2>Linked objects</h2>"
                ($report.LinkedObjects | ConvertTo-Html -Fragment)
                "<h2>Apps</h2>"
                ($report.Apps | Select-Object Label, SignOnMode, Status, GroupCount, UserCount,
                    @{ Name = 'DirectUsers'; Expression = { $_.DirectUsers -join ', ' } } |
                    ConvertTo-Html -Fragment)
            ) -join "`n"

            $html = ConvertTo-Html -Head "<title>Okta Test Environment</title>$style" -Body $sections |
                Out-String
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($html))
            Write-OktaTestProgress -Message "HTML report written to $OutputPath" -Type Success
        }
    }

    if ($PassThru) { return $report }
}
