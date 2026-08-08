function Remove-OktaTestEnvironment {
    <#
    .SYNOPSIS
        Removes everything this module created, in the order Okta will accept

    .DESCRIPTION
        Teardown is the half of a test environment that gets written badly, and on a tenant
        with ten user slots it is the half you run most often. Two things make it safe here.

        First, ownership is proven rather than assumed. Users must carry the labSeedTag
        attribute or sit under the seed email domain; groups must have both the name prefix
        and the seed marker in their description. Nothing is deleted because its name looked
        familiar.

        Second, the order is forced by Okta's own dependencies and runs in reverse of
        creation:

        1. Event hooks, trusted origins, policies and network zones. First, because Okta
           refuses to delete a zone that a policy rule still points at.
        2. Group rules, deactivated then deleted. A rule holding a group open will block the
           group's deletion.
        3. Users, deactivated then deleted. Okta needs both; a single DELETE on an active
           user only deactivates it.
        4. Groups.
        5. App integrations, deactivated then deleted. Kept separate from the service app,
           because -Keep ServiceApp is about retaining the credential you authenticate with
           and should not also strand eight lab apps you asked to be rid of.
        6. The service app, deactivated then deleted, and its private key with it.
        7. Linked object definitions. After the users, since removing a definition removes
           every link made with it.
        8. Custom profile attributes, nulled out of every schema. Removing an attribute that
           users still carry destroys their data, and it is what Get-OktaTestSeededUser
           identifies users by.
        9. User types. Genuinely last: a type cannot be deleted while a user is on it, and
           Okta returns a transient conflict for a while after its schema is touched, so this
           tolerates a retry.

        -WhatIf beats -Force. If both are passed nothing is deleted, because the only reason
        to pass -WhatIf is to find out what would happen.

    .PARAMETER Keep
        Components to leave alone. Valid values: UserTypes, Schema, Users, Groups, GroupRules,
        Apps, LinkedObjects, NetworkZones, Policies, TrustedOrigins, EventHooks, ServiceApp.

    .PARAMETER RemoveCredentialFile
        Also delete the local private key file. Off by default: the file is worthless once the
        app is gone, but deleting a key the user may have copied a path to is not something to
        do without being asked.

    .PARAMETER Force
        Skip the confirmation prompt. Has no effect under -WhatIf.

    .PARAMETER PassThru
        Return the detailed results object

    .OUTPUTS
        PSCustomObject with per-component Removed and Errors collections

    .EXAMPLE
        Remove-OktaTestEnvironment -WhatIf
        Lists every object that would be deleted. Worth running first, every time.

    .EXAMPLE
        Remove-OktaTestEnvironment -Force
        Tears the environment down without prompting

    .EXAMPLE
        Remove-OktaTestEnvironment -Keep ServiceApp, Schema -Force
        Clears the users, groups and rules but keeps the app you authenticate with, ready for
        an immediate re-seed

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        User deletion is irreversible. Okta has no recycle bin.

        If you are connected as the service app and do not use -Keep ServiceApp, the app
        deletes the credential it is authenticating with. That works, because the access token
        already issued stays valid for the rest of the run, but the next connection attempt
        will fail until a new app is created with an SSWS token.

    .LINK
        New-OktaTestEnvironment
        Connect-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('UserTypes', 'Schema', 'Users', 'Groups', 'GroupRules', 'Apps',
            'LinkedObjects', 'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks',
            'ServiceApp')]
        [string[]]$Keep = @(),

        [Parameter()]
        [switch]$RemoveCredentialFile,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $results = [PSCustomObject]@{
        OrgUrl     = $connection.OrgUrl
        Prefix     = $connection.Prefix
        StartTime  = Get-Date
        EndTime    = $null
        GroupRules = @{ Removed = @(); Errors = @() }
        Users      = @{ Removed = @(); Errors = @() }
        Groups     = @{ Removed = @(); Errors = @() }
        Apps           = @{ Removed = @(); Errors = @() }
        LinkedObjects  = @{ Removed = @(); Errors = @() }
        NetworkZones   = @{ Removed = @(); Errors = @() }
        Policies       = @{ Removed = @(); Errors = @() }
        TrustedOrigins = @{ Removed = @(); Errors = @() }
        EventHooks     = @{ Removed = @(); Errors = @() }
        UserTypes      = @{ Removed = @(); Errors = @() }
        ServiceApp = @{ Removed = @(); Errors = @() }
        Schema     = @{ Removed = @(); Errors = @() }
    }

    Write-OktaTestProgress -Message "Okta Test Environment Teardown ($($connection.OrgUrl))" -Type Header

    # WhatIfPreference is set by -WhatIf and by $WhatIfPreference in the caller's scope.
    # Reading it directly, rather than only relying on ShouldProcess, is what lets -Force skip
    # the prompt without also skipping the preview.
    $isWhatIf = $WhatIfPreference

    # -Force has to suppress the per-object ShouldProcess prompts as well as the single
    # ShouldContinue below, or ConfirmImpact = High makes it prompt for every user anyway and
    # the switch does not mean what it says. Setting the preference rather than short-
    # circuiting ShouldProcess is the part that keeps -WhatIf working: ShouldProcess is still
    # called, and still returns false under -WhatIf.
    if ($Force -and -not $isWhatIf) {
        $ConfirmPreference = 'None'
    }

    if (-not $Force -and -not $isWhatIf) {
        $prompt = ("This permanently deletes every user, group and group rule tagged " +
            "'$($connection.Prefix)' in $($connection.OrgUrl). Okta has no undo.")
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Remove Okta test environment')) {
            Write-OktaTestProgress -Message 'Teardown cancelled.' -Type Warning
            if ($PassThru) { return $results }
            return
        }
    }

    # --- 0. Outbound integrations, policies and zones -----------------------------------
    # First, because they reference the groups and zones that later steps delete, and Okta
    # refuses to delete a zone a policy rule still points at. Each is a simple prefix match on
    # a name this module owns, and each deactivates before deleting where the API requires it.
    # Singular is carried explicitly rather than derived by trimming an "s", which turned
    # "policies" into "Delete Okta policie" in the confirmation prompt.
    $simpleSweeps = @(
        @{ Key = 'EventHooks'; Label = 'event hooks'; One = 'event hook'
           Path = '/api/v1/eventHooks'; Deactivate = $true }
        @{ Key = 'TrustedOrigins'; Label = 'trusted origins'; One = 'trusted origin'
           Path = '/api/v1/trustedOrigins'; Deactivate = $true }
        @{ Key = 'Policies'; Label = 'policies'; One = 'policy'
           Path = '/api/v1/policies'; Deactivate = $false }
        @{ Key = 'NetworkZones'; Label = 'network zones'; One = 'network zone'
           Path = '/api/v1/zones'; Deactivate = $true }
    )

    foreach ($sweep in $simpleSweeps) {
        if ($sweep.Key -in $Keep) { continue }

        Write-OktaTestProgress -Message "Removing $($sweep.Label)" -Type Info
        try {
            $query = @{ limit = 200 }
            # The policy list endpoint requires a type; there is no "all policies" listing.
            $items = if ($sweep.Key -eq 'Policies') {
                @(foreach ($policyType in @('OKTA_SIGN_ON', 'PASSWORD')) {
                    Invoke-OktaTestRequest -Method GET -Path $sweep.Path `
                        -Query @{ type = $policyType; limit = 200 } -Paginate
                })
            }
            else {
                @(Invoke-OktaTestRequest -Method GET -Path $sweep.Path -Query $query -Paginate)
            }

            $owned = @($items | Where-Object {
                $_.name -and $_.name.StartsWith("$($connection.Prefix)-", [StringComparison]::OrdinalIgnoreCase)
            })

            foreach ($item in $owned) {
                $what = 'Delete Okta {0}' -f $sweep.One
                if (-not $PSCmdlet.ShouldProcess($item.name, $what)) { continue }

                try {
                    if ($sweep.Deactivate) {
                        try {
                            $null = Invoke-OktaTestRequest -Method POST `
                                -Path "$($sweep.Path)/$($item.id)/lifecycle/deactivate"
                        }
                        catch {
                            Write-Verbose "$($item.name) was already inactive."
                        }
                    }
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "$($sweep.Path)/$($item.id)"
                    $results.($sweep.Key).Removed += $item.name
                }
                catch {
                    $results.($sweep.Key).Errors += "$($item.name): $($_.Exception.Message)"
                    Write-Error "Failed to delete '$($item.name)': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.($sweep.Key).Errors += $_.Exception.Message
            Write-Error "Could not enumerate $($sweep.Label): $($_.Exception.Message)"
        }
    }

    # --- 1. Group rules -----------------------------------------------------------------
    if ('GroupRules' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 1: Removing group rules' -Type Info
        try {
            $rulePrefix = '{0}-Rule-' -f $connection.Prefix
            $rules = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/groups/rules' `
                -Query @{ limit = 200 } -Paginate |
                Where-Object {
                    $_.name -and $_.name.StartsWith($rulePrefix, [StringComparison]::OrdinalIgnoreCase)
                })

            foreach ($rule in $rules) {
                if (-not $PSCmdlet.ShouldProcess($rule.name, 'Delete group rule')) { continue }
                try {
                    try {
                        $null = Invoke-OktaTestRequest -Method POST `
                            -Path "/api/v1/groups/rules/$($rule.id)/lifecycle/deactivate"
                    }
                    catch {
                        Write-Verbose "Rule $($rule.name) was already inactive."
                    }
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/groups/rules/$($rule.id)"
                    $results.GroupRules.Removed += $rule.name
                }
                catch {
                    $results.GroupRules.Errors += "$($rule.name): $($_.Exception.Message)"
                    Write-Error "Failed to delete rule '$($rule.name)': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.GroupRules.Errors += $_.Exception.Message
            Write-Error "Could not enumerate group rules: $($_.Exception.Message)"
        }
    }

    # --- 2. Users -----------------------------------------------------------------------
    if ('Users' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 2: Removing users' -Type Info
        try {
            $users = @(Get-OktaTestSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)

            foreach ($user in $users) {
                $login = $user.profile.login
                if (-not $PSCmdlet.ShouldProcess($login, 'Deactivate and delete Okta user')) { continue }

                try {
                    # Okta deletes in two steps and a DELETE against an active user only
                    # performs the first of them. Deactivating explicitly means the DELETE
                    # below is always the second step, whatever state the user was in.
                    if ($user.status -ne 'DEPROVISIONED') {
                        $null = Invoke-OktaTestRequest -Method POST `
                            -Path "/api/v1/users/$($user.id)/lifecycle/deactivate"
                    }
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/users/$($user.id)"
                    $results.Users.Removed += $login
                }
                catch {
                    $results.Users.Errors += "$login`: $($_.Exception.Message)"
                    Write-Error "Failed to delete user '$login': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.Users.Errors += $_.Exception.Message
            Write-Error "Could not enumerate seeded users: $($_.Exception.Message)"
        }
    }

    # --- 3. Groups ----------------------------------------------------------------------
    if ('Groups' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 3: Removing groups' -Type Info
        try {
            $groups = @(Get-OktaTestSeededGroup -Prefix $connection.Prefix -SeedMarker $connection.SeedMarker)

            foreach ($group in $groups) {
                $name = $group.profile.name
                if (-not $PSCmdlet.ShouldProcess($name, 'Delete Okta group')) { continue }

                try {
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/groups/$($group.id)"
                    $results.Groups.Removed += $name
                }
                catch {
                    $results.Groups.Errors += "$name`: $($_.Exception.Message)"
                    Write-Error "Failed to delete group '$name': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.Groups.Errors += $_.Exception.Message
            Write-Error "Could not enumerate seeded groups: $($_.Exception.Message)"
        }
    }

    # --- 4a. Lab apps -------------------------------------------------------------------
    # Separate from the service app on purpose. -Keep ServiceApp is for keeping the credential
    # you authenticate with; it should not also strand eight lab apps you asked to be rid of.
    if ('Apps' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 4: Removing app integrations' -Type Info
        try {
            $labApps = @(Get-OktaTestSeededApp -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)

            foreach ($app in $labApps) {
                if (-not $PSCmdlet.ShouldProcess($app.label, 'Deactivate and delete Okta app')) { continue }

                try {
                    try {
                        $null = Invoke-OktaTestRequest -Method POST `
                            -Path "/api/v1/apps/$($app.id)/lifecycle/deactivate"
                    }
                    catch {
                        Write-Verbose "App $($app.label) was already inactive."
                    }
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/apps/$($app.id)"
                    $results.Apps.Removed += $app.label
                }
                catch {
                    $results.Apps.Errors += "$($app.label): $($_.Exception.Message)"
                    Write-Error "Failed to delete app '$($app.label)': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.Apps.Errors += $_.Exception.Message
            Write-Error "Could not enumerate app integrations: $($_.Exception.Message)"
        }
    }

    # --- 4b. Service app ----------------------------------------------------------------
    if ('ServiceApp' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 5: Removing the service app' -Type Info
        try {
            $serviceApps = @(Get-OktaTestSeededApp -Prefix $connection.Prefix `
                -EmailDomain $connection.EmailDomain -IncludeServiceApp |
                Where-Object {
                    -not $_.label.StartsWith("$($connection.Prefix)-", [StringComparison]::OrdinalIgnoreCase)
                })

            foreach ($app in $serviceApps) {
                if (-not $PSCmdlet.ShouldProcess($app.label, 'Deactivate and delete Okta app')) { continue }

                try {
                    try {
                        $null = Invoke-OktaTestRequest -Method POST `
                            -Path "/api/v1/apps/$($app.id)/lifecycle/deactivate"
                    }
                    catch {
                        Write-Verbose "App $($app.label) was already inactive."
                    }
                    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/apps/$($app.id)"
                    $results.ServiceApp.Removed += $app.label
                }
                catch {
                    $results.ServiceApp.Errors += "$($app.label): $($_.Exception.Message)"
                    Write-Error "Failed to delete app '$($app.label)': $($_.Exception.Message)"
                }
            }

            if ($RemoveCredentialFile) {
                $credentialPath = Get-OktaTestCredentialPath -OrgUrl $connection.OrgUrl

                if (Test-Path -Path $credentialPath) {
                    # Read the pointer before deleting it. If the key lives in a vault, the file
                    # is the only record of which vault and which secret, so deleting the file
                    # first would orphan the secret with no way left to find it.
                    $vaultName = $null
                    $secretName = $null
                    try {
                        $stored = Import-OktaTestAppCredential -Path $credentialPath
                        $vaultName = $stored.vaultName
                        $secretName = $stored.secretName
                    }
                    catch {
                        Write-Verbose ("Could not read '$credentialPath' before deleting it: " +
                            $_.Exception.Message)
                    }

                    if ($vaultName -and $secretName) {
                        try {
                            if (Remove-OktaTestVaultSecret -VaultName $vaultName -SecretName $secretName) {
                                $results.ServiceApp.Removed += "$vaultName\$secretName"
                            }
                        }
                        catch {
                            $results.ServiceApp.Errors += "vault secret: $($_.Exception.Message)"
                            Write-Error "Failed to remove the vault secret: $($_.Exception.Message)"
                        }
                    }

                    $deleteAction = 'Delete the service app credential file'
                    if ($PSCmdlet.ShouldProcess($credentialPath, $deleteAction)) {
                        Remove-Item -Path $credentialPath -Force
                        $results.ServiceApp.Removed += $credentialPath
                    }
                }
            }
        }
        catch {
            $results.ServiceApp.Errors += $_.Exception.Message
            Write-Error "Could not enumerate apps: $($_.Exception.Message)"
        }
    }

    # --- 4c. Linked objects -------------------------------------------------------------
    # After the users and before the schema. Removing a definition removes every link made with
    # it, so by this point the links have already gone with the users that carried them.
    if ('LinkedObjects' -notin $Keep) {
        Write-OktaTestProgress -Message 'Removing linked object definitions' -Type Info
        try {
            $linkRows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaLinkedObjects.csv') `
                -Encoding UTF8)
            $defined = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/schemas/user/linkedObjects')

            foreach ($linkRow in $linkRows) {
                if (-not @($defined | Where-Object { $_.primary.name -eq $linkRow.PrimaryName })) { continue }
                if (-not $PSCmdlet.ShouldProcess($linkRow.PrimaryName, 'Delete linked object definition')) {
                    continue
                }

                try {
                    $null = Invoke-OktaTestRequest -Method DELETE `
                        -Path "/api/v1/meta/schemas/user/linkedObjects/$($linkRow.PrimaryName)"
                    $results.LinkedObjects.Removed += $linkRow.PrimaryName
                }
                catch {
                    $results.LinkedObjects.Errors += "$($linkRow.PrimaryName): $($_.Exception.Message)"
                    Write-Error "Failed to delete linked object '$($linkRow.PrimaryName)': $($_.Exception.Message)"
                }
            }
        }
        catch {
            $results.LinkedObjects.Errors += $_.Exception.Message
            Write-Error "Could not enumerate linked objects: $($_.Exception.Message)"
        }
    }

    # --- 5. Schema ----------------------------------------------------------------------
    # Last on purpose. Removing labSeedTag before the users are gone would leave the next
    # teardown attempt with nothing but the email domain to identify them by.
    if ('Schema' -notin $Keep) {
        Write-OktaTestProgress -Message 'Step 6: Removing custom profile attributes' -Type Info
        try {
            $schemaResult = New-OktaTestProfileAttribute -Remove -PassThru -Confirm:$false
            $results.Schema.Removed = @($schemaResult.Removed)
            $results.Schema.Errors = @($schemaResult.Errors)
        }
        catch {
            $results.Schema.Errors += $_.Exception.Message
            Write-Error "Could not remove custom profile attributes: $($_.Exception.Message)"
        }
    }

    # --- 6. User types ------------------------------------------------------------------
    # Genuinely last. A type cannot be deleted while a user is on it, and Okta also returns a
    # transient 409 for a short while after its schema is touched - so this both runs after the
    # users are gone and tolerates one retry.
    if ('UserTypes' -notin $Keep) {
        Write-OktaTestProgress -Message 'Removing the second user type' -Type Info
        try {
            $typeRows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaUserTypes.csv') -Encoding UTF8)
            $liveTypes = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/types/user')

            foreach ($typeRow in $typeRows) {
                $typeName = '{0}{1}' -f $connection.Prefix.ToLowerInvariant(), $typeRow.Name
                $match = @($liveTypes | Where-Object { $_.name -eq $typeName -and -not $_.default })
                if ($match.Count -eq 0) { continue }
                if (-not $PSCmdlet.ShouldProcess($typeName, 'Delete Okta user type')) { continue }

                $deleted = $false
                foreach ($attempt in 1..2) {
                    try {
                        $null = Invoke-OktaTestRequest -Method DELETE `
                            -Path "/api/v1/meta/types/user/$($match[0].id)"
                        $deleted = $true
                        break
                    }
                    catch {
                        if ($attempt -eq 2) { throw }
                        Write-Verbose "User type delete returned a conflict; retrying once."
                        Start-Sleep -Seconds 3
                    }
                }

                if ($deleted) { $results.UserTypes.Removed += $typeName }
            }
        }
        catch {
            $results.UserTypes.Errors += $_.Exception.Message
            Write-Error "Could not remove the user type: $($_.Exception.Message)"
        }
    }

    $results.EndTime = Get-Date

    $tracked = @('GroupRules', 'Users', 'Groups', 'Apps', 'ServiceApp', 'Schema',
        'EventHooks', 'TrustedOrigins', 'Policies', 'NetworkZones', 'LinkedObjects', 'UserTypes')
    $removedCount = @($tracked | ForEach-Object { @($results.$_.Removed).Count } |
        Measure-Object -Sum).Sum
    $errorCount = @($tracked | ForEach-Object { @($results.$_.Errors).Count } |
        Measure-Object -Sum).Sum

    Write-OktaTestProgress -Message 'Teardown Summary' -Type Header
    Write-Host "Objects removed: $removedCount" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Warning "Failures: $errorCount. Inspect the results object with -PassThru."
    }

    if ($PassThru) { return $results }
}
