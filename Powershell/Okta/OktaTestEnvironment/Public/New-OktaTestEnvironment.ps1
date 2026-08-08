function New-OktaTestEnvironment {
    <#
    .SYNOPSIS
        Creates a complete Okta test environment: user types, schema, users, groups, group
        rules, apps, linked objects, zones, policies, origins, hooks and a service app

    .DESCRIPTION
        The single entry point. Runs twelve creation steps in the only order that works, because
        each one depends on the last:

         1. User types. A type must exist before its schema can be extended or a user assigned
            to it.
         2. Custom profile attributes, on every type's schema. Users cannot carry an attribute
            the schema does not define, and the seed tag teardown relies on is one of them.
         3. Users. Eight of them, which is what an Okta trial org's ten active user
            licence leaves room for once your own admin account is counted.
         4. Groups. Seventeen, because groups are not licence-limited and are where an eight
            user tenant gets its complexity back.
         5. Group rules. They need their target groups to exist and their source attributes to
            be populated.
         6. App integrations. They need the groups and users that get assigned to them, and
            they are what turn "who exists" into "who has access to what".
         7. Linked objects. They link users, so the users have to exist.
         8. Network zones. Policy rules reference them by id.
         9. Policies and their rules. They need both the groups they scope to and the zones
            their rules condition on.
        10. Trusted origins.
        11. Event hooks.
        12. The service app. Last, because it is the handover: everything above ran on the SSWS
            token you connected with, and from here on you can connect as the app instead and
            revoke that token.

        Every step is skippable and every step reports rather than throws, so one failure does
        not cost you the other eleven. The summary at the end says what actually happened.

    .PARAMETER Skip
        Components to skip. Valid values: UserTypes, Schema, Users, Groups, GroupRules, Apps,
        LinkedObjects, NetworkZones, Policies, TrustedOrigins, EventHooks, ServiceApp.

    .PARAMETER UserCount
        How many of the eight users to create. Lower it if the tenant already holds users.

    .PARAMETER AccountPassword
        Password for the seeded accounts. Defaults to a known, weak, shared lab value.

    .PARAMETER SkipLifecycleStates
        Create every user active rather than honouring the suspended and staged states

    .PARAMETER ServiceAppLabel
        Label for the service app

    .PARAMETER ServiceAppScope
        Okta API scopes to grant the service app

    .PARAMETER CredentialPath
        Where to write the service app credential

    .PARAMETER RevokeApiToken
        Name or id of an SSWS API token to revoke once the service app has proven it can issue
        a token, retiring the bootstrap credential in the same command that replaces it. The
        service app step runs last, so nothing else depends on the token by the time it goes.
        See New-OktaTestServiceApp for why the token has to be named rather than inferred.

    .PARAMETER UseSecretStore
        Store the service app private key in a SecretStore vault rather than encrypting it into
        the credential file. See New-OktaTestServiceApp for when that is worth doing.

    .PARAMETER VaultName
        Vault to use when -UseSecretStore is specified

    .PARAMETER VaultPassword
        Password for the vault when -UseSecretStore is specified

    .PARAMETER ActiveUserLimit
        The tenant's active user ceiling, checked before anything is created. Defaults to the
        value recorded at connect time.

    .PARAMETER Force
        Replace an existing service app with the same label

    .PARAMETER ShowProgress
        Emit per-step detail as verbose output

    .PARAMETER PassThru
        Return the detailed results object

    .OUTPUTS
        PSCustomObject summarising every operation, when -PassThru is used

    .EXAMPLE
        Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ApiToken $token
        New-OktaTestEnvironment
        The normal first run

    .EXAMPLE
        New-OktaTestEnvironment -WhatIf
        Shows every object that would be created, without creating any

    .EXAMPLE
        New-OktaTestEnvironment -Skip ServiceApp -UserCount 4
        Seeds a smaller environment and keeps using the SSWS token

    .EXAMPLE
        New-OktaTestEnvironment -Skip Schema, Users -PassThru
        Rebuilds only the groups and rules over users that already exist

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        REQUIREMENTS:
        - An Okta org and an SSWS API token belonging to a super admin
        - Connect-OktaTestEnvironment run first
        - Ten free active user slots minus whatever the tenant already holds

        The user count is the constraint the whole module is shaped around. Eight is not a
        sample size, it is what the tenant licence leaves room for, and every other object type
        is scaled up to compensate because none of them are capped.

    .LINK
        Connect-OktaTestEnvironment
        New-OktaTestProfileAttribute
        New-OktaTestUser
        New-OktaTestGroup
        New-OktaTestGroupRule
        New-OktaTestServiceApp
        Remove-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path, not a credential. The key it points at never appears here.')]
    # SupportsShouldProcess is declared so -WhatIf is accepted and propagates, but the decision
    # belongs to the step functions: each calls ShouldProcess per object, which is what makes
    # the preview name the users and groups instead of the steps.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Delegated to the step functions, which each call ShouldProcess per object.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('UserTypes', 'Schema', 'Users', 'Groups', 'GroupRules', 'Apps',
            'LinkedObjects', 'NetworkZones', 'Policies', 'TrustedOrigins', 'EventHooks',
            'ServiceApp')]
        [string[]]$Skip = @(),

        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$UserCount = 8,

        [Parameter()]
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$SkipLifecycleStates,

        [Parameter()]
        [string]$ServiceAppLabel,

        [Parameter()]
        [string[]]$ServiceAppScope,

        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RevokeApiToken,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'OktaTestEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [int]$ActiveUserLimit,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $correlationId = [Guid]::NewGuid()
        Write-Verbose "Starting New-OktaTestEnvironment - CorrelationId: $correlationId"

        $connection = Get-OktaTestConnection
        if (-not $PSBoundParameters.ContainsKey('ActiveUserLimit')) {
            $ActiveUserLimit = $connection.ActiveUserLimit
        }

        # The headroom check only matters if users are actually going to be created, and
        # asking for it when they are not would fail a groups-only rebuild on a full tenant.
        $requiredSlots = if ('Users' -in $Skip) { 0 } else { $UserCount }

        $prerequisiteArgs = @{
            CheckDataFiles    = $true
            RequiredUserSlots = $requiredSlots
            ActiveUserLimit   = $ActiveUserLimit
        }
        if (-not (Test-OktaTestPrerequisite @prerequisiteArgs)) {
            throw 'Prerequisites not met for Okta test environment creation'
        }
    }

    process {
        Write-OktaTestProgress -Message "Okta Test Environment Creation ($($connection.OrgUrl))" -Type Header

        $results = [PSCustomObject]@{
            CorrelationId = $correlationId
            OrgUrl        = $connection.OrgUrl
            Prefix        = $connection.Prefix
            StartTime     = Get-Date
            EndTime       = $null
            Duration      = $null
            Operations    = [ordered]@{
                UserTypes      = @{ Attempted = $false; Success = $false; Results = $null }
                Schema         = @{ Attempted = $false; Success = $false; Results = $null }
                Users      = @{ Attempted = $false; Success = $false; Results = $null }
                Groups     = @{ Attempted = $false; Success = $false; Results = $null }
                GroupRules = @{ Attempted = $false; Success = $false; Results = $null }
                Apps           = @{ Attempted = $false; Success = $false; Results = $null }
                LinkedObjects  = @{ Attempted = $false; Success = $false; Results = $null }
                NetworkZones   = @{ Attempted = $false; Success = $false; Results = $null }
                Policies       = @{ Attempted = $false; Success = $false; Results = $null }
                TrustedOrigins = @{ Attempted = $false; Success = $false; Results = $null }
                EventHooks     = @{ Attempted = $false; Success = $false; Results = $null }
                ServiceApp = @{ Attempted = $false; Success = $false; Results = $null }
            }
            Summary       = [ordered]@{
                TotalOperations      = 0
                SuccessfulOperations = 0
                FailedOperations     = 0
            }
        }

        # Each step is the same shape: attempt, record, keep going. Declaring them as data
        # rather than repeating the try/catch five times keeps the ordering visible, which is
        # the part of this function that actually matters.
        $steps = @(
            @{
                Key   = 'UserTypes'
                Title = 'Step 0: Creating the second user type'
                Run   = { New-OktaTestUserType -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedTypes) created" }
            }
            @{
                Key   = 'Schema'
                Title = 'Step 1: Adding custom profile attributes'
                Run   = {
                    New-OktaTestProfileAttribute -PassThru -Confirm:$false
                }
                Report = { param($r) "Applied $(@($r.Applied).Count) attributes" }
            }
            @{
                Key   = 'Users'
                Title = "Step 2: Creating $UserCount users"
                Run   = {
                    $userArgs = @{ UserCount = $UserCount; PassThru = $true; Confirm = $false }
                    if ($AccountPassword)     { $userArgs.AccountPassword = $AccountPassword }
                    if ($SkipLifecycleStates) { $userArgs.SkipLifecycleStates = $true }
                    New-OktaTestUser @userArgs
                }
                Report = { param($r) "$($r.CreatedUsers) created, $($r.UpdatedUsers) updated" }
            }
            @{
                Key   = 'Groups'
                Title = 'Step 3: Creating groups and memberships'
                Run   = {
                    New-OktaTestGroup -PassThru -Confirm:$false
                }
                Report = { param($r) "$($r.CreatedGroups) created, $($r.MembersAdded) memberships" }
            }
            @{
                Key   = 'GroupRules'
                Title = 'Step 4: Creating group rules'
                Run   = {
                    New-OktaTestGroupRule -PassThru -Confirm:$false
                }
                Report = { param($r) "$($r.CreatedRules) created, $($r.ActivatedRules) activated" }
            }
            @{
                Key   = 'Apps'
                Title = 'Step 5: Creating app integrations and assignments'
                Run   = {
                    New-OktaTestApp -PassThru -Confirm:$false
                }
                Report = { param($r)
                    "$($r.CreatedApps) created, $($r.GroupsAssigned) group and " +
                    "$($r.UsersAssigned) direct assignments"
                }
            }
            @{
                Key   = 'LinkedObjects'
                Title = 'Step 6: Creating linked objects'
                Run   = { New-OktaTestLinkedObject -PassThru -Confirm:$false }
                Report = { param($r) "$($r.LinksCreated) links" }
            }
            @{
                Key   = 'NetworkZones'
                Title = 'Step 7: Creating network zones'
                Run   = { New-OktaTestNetworkZone -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedZones) created" }
            }
            @{
                Key   = 'Policies'
                Title = 'Step 8: Creating policies and rules'
                Run   = { New-OktaTestPolicy -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedPolicies) policies, $($r.RulesCreated) rules" }
            }
            @{
                Key   = 'TrustedOrigins'
                Title = 'Step 9: Creating trusted origins'
                Run   = { New-OktaTestTrustedOrigin -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedOrigins) created" }
            }
            @{
                Key   = 'EventHooks'
                Title = 'Step 10: Creating event hooks'
                Run   = { New-OktaTestEventHook -PassThru -Confirm:$false }
                Report = { param($r) "$($r.CreatedHooks) created" }
            }
            @{
                Key   = 'ServiceApp'
                Title = 'Step 11: Registering the service app'
                Run   = {
                    $appArgs = @{ PassThru = $true; Confirm = $false }
                    if ($ServiceAppLabel) { $appArgs.Label = $ServiceAppLabel }
                    if ($ServiceAppScope) { $appArgs.Scope = $ServiceAppScope }
                    if ($CredentialPath)  { $appArgs.CredentialPath = $CredentialPath }
                    if ($Force)           { $appArgs.Force = $true }
                    if ($RevokeApiToken)  { $appArgs.RevokeApiToken = $RevokeApiToken }
                    if ($UseSecretStore) {
                        $appArgs.UseSecretStore = $true
                        $appArgs.VaultName      = $VaultName
                        if ($VaultPassword) { $appArgs.VaultPassword = $VaultPassword }
                    }
                    New-OktaTestServiceApp @appArgs
                }
                Report = { param($r) "client_id $($r.ClientId), key protection $($r.Protection)" }
            }
        )

        $stepNumber = 0
        foreach ($step in $steps) {
            $stepNumber++

            if ($step.Key -in $Skip) {
                Write-OktaTestProgress -Message "$($step.Title) - skipped as requested" -Type Warning
                continue
            }

            Write-OktaTestProgress -Message $step.Title -Type Info
            $results.Operations[$step.Key].Attempted = $true
            $results.Summary.TotalOperations++

            # Deliberately no ShouldProcess gate here. Every step function implements its own,
            # and $WhatIfPreference propagates into them, so letting them run is what makes
            # -WhatIf list the eight users and seventeen groups by name. Gating at this level
            # instead produced a preview that said only "would perform step 2", which tells you
            # nothing you did not already know from reading the parameter.
            try {
                $stepResult = & $step.Run
                $results.Operations[$step.Key].Success = $true
                $results.Operations[$step.Key].Results = $stepResult
                $results.Summary.SuccessfulOperations++

                if ($ShowProgress -and $stepResult) {
                    Write-Verbose (& $step.Report $stepResult)
                }
            }
            catch {
                $results.Operations[$step.Key].Results = $_.Exception.Message
                $results.Summary.FailedOperations++
                Write-Error "$($step.Title) failed: $($_.Exception.Message)"
            }
        }

        $results.EndTime = Get-Date
        $results.Duration = $results.EndTime - $results.StartTime

        Write-OktaTestProgress -Message 'Environment Creation Summary' -Type Header
        Write-Host ("Operations completed: $($results.Summary.SuccessfulOperations)/" +
            "$($results.Summary.TotalOperations)") -ForegroundColor Green
        Write-Host "Duration: $($results.Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

        if ($results.Summary.FailedOperations -gt 0) {
            Write-Warning "Failed operations: $($results.Summary.FailedOperations)"
            Write-Warning 'Inspect the results object with -PassThru for the detail.'
        }

        Write-OktaTestProgress -Message 'Test environment creation complete.' -Type Success

        if ($PassThru) { return $results }
    }

    end {
        Write-Verbose "Completed New-OktaTestEnvironment - CorrelationId: $correlationId"
    }
}
