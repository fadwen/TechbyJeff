function New-OktaTestServiceApp {
    <#
    .SYNOPSIS
        Creates the OAuth service app that replaces the SSWS token for later runs

    .DESCRIPTION
        Registers an API Services app in the tenant, authenticating with private_key_jwt, and
        writes its private key to a protected file so every later run can authenticate as the
        app instead of as you.

        The reason this exists rather than just reusing the SSWS token: an SSWS token carries
        the permissions of the human who created it, never expires on its own, and is a bearer
        string that ends up pasted into scripts and scrollback. A service app key is scoped to
        exactly the Okta APIs it was granted, is never transmitted (only assertions signed by
        it are), and can be revoked by deleting one app. Once this has run, the SSWS token has
        done its job and can be revoked in the admin console.

        Four calls make up the registration, and all four are needed:

        1. POST /oauth2/v1/clients registers the client with the public half of a freshly
           generated RSA key.
        2. POST /api/v1/apps/{id}/grants grants each Okta API scope. Without these the app
           gets a token that every management endpoint then rejects.
        3. POST /oauth2/v1/clients/{id}/roles assigns an admin role. Scopes say which APIs
           the app may call; the role says which objects it may touch. An app with scopes and
           no role authenticates successfully and is authorised for nothing, which is a
           genuinely confusing failure.
        4. The private key is written locally, with its ACL replaced so only you can read it.

        The private key is generated here and the public half is what leaves the machine. Okta
        never sees the private key, and neither does anything else.

    .PARAMETER Label
        The app label shown in the admin console. Defaults to the connection prefix followed
        by a description, so teardown can find it without the credential file.

    .PARAMETER Scope
        Okta API scopes to grant. The default set is what this module itself needs to seed and
        tear down an environment. Narrow it if the app is only ever going to read.

    .PARAMETER AdminRole
        Standard admin roles to assign. SUPER_ADMIN is the default because managing the user
        schema, which this module does, is a super admin operation, and because the tenant
        this is aimed at is a disposable one. On anything you care about, assign USER_ADMIN
        and APP_ADMIN instead and accept that -Skip Schema becomes mandatory.

    .PARAMETER CredentialPath
        Where to write the credential. Defaults to a per-user file outside the repository.

    .PARAMETER UseSecretStore
        Store the private key in a PowerShell SecretStore vault instead of encrypting it into
        the credential file, installing SecretManagement and SecretStore if they are missing.

        The file-based default already encrypts the key with DPAPI on Windows, so this is not
        about plaintext-versus-encrypted. Reach for it when you want the key in the same vault
        as the rest of your lab credentials, when you want a password you chose rather than a
        machine-bound key, or when you are on Linux or macOS, where DPAPI does not exist and the
        file default degrades to unprotected.

    .PARAMETER VaultName
        Vault to use when -UseSecretStore is specified

    .PARAMETER VaultPassword
        Password for the vault when -UseSecretStore is specified. Defaults to a known lab value
        so that unattended runs are not blocked by a prompt.

    .PARAMETER KeySize
        RSA key size in bits

    .PARAMETER RevokeApiToken
        Name or id of an SSWS API token to revoke once the service app has proven it can issue
        a token. Use it to retire the bootstrap credential in the same command that replaces it.

        You have to name the token, because the module cannot work out which one it is using.
        /api/v1/api-tokens/current returns 404 on a standard org, and the list endpoint returns
        ids and names but never token values, so an SSWS string cannot be matched to a row. Orgs
        routinely hold several tokens serving Terraform, Postman and CI, and a guess would
        eventually revoke one of those.

        Three interlocks: nothing is revoked unless the new app has successfully issued a token,
        an ambiguous name is refused rather than resolved, and -WhatIf is honoured. Revocation
        is permanent - Okta cannot restore a token or recreate one with the same value.

        Note that rotating this app's key later needs an SSWS token, since okta.clients.manage
        is deliberately withheld from the app. Keep at least one token, or accept that a
        replacement is made by hand in the admin console.

    .PARAMETER Force
        Delete an existing app with the same label first. Needed because re-registering
        produces a second app rather than replacing the first, and because the credential file
        for the old app stops working the moment it is superseded.

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with ClientId, AppId, Label, Scopes, AdminRoles, CredentialPath and
        Warnings

    .EXAMPLE
        New-OktaTestServiceApp
        Creates the app with the default scopes and writes the key to the default location

    .EXAMPLE
        New-OktaTestServiceApp -Scope okta.users.read, okta.groups.read -AdminRole READ_ONLY_ADMIN
        A read-only companion app, for testing a reporting script under least privilege

    .EXAMPLE
        New-OktaTestServiceApp -Force -PassThru
        Rotates the key by replacing the app

    .EXAMPLE
        New-OktaTestServiceApp -RevokeApiToken 'bootstrap' -WhatIf
        Shows which token would be revoked, without creating or revoking anything

    .EXAMPLE
        New-OktaTestServiceApp -RevokeApiToken 'bootstrap'
        Creates the app and retires the SSWS token that created it, once the app has proven
        itself by issuing a token

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Requires an SSWS connection held by a super admin. Assigning an admin role to a client
        is a super admin operation; a lesser token gets through the app creation and then
        fails on the role, leaving an app that cannot do anything.

    .LINK
        Get-OktaTestAccessToken
        Connect-OktaTestEnvironment
        Remove-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path, not a credential. The key it points at never appears here.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Label,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scope = @(
            'okta.users.manage',
            'okta.groups.manage',
            'okta.apps.manage',
            'okta.schemas.manage',
            'okta.userTypes.manage',
            'okta.policies.manage',
            'okta.networkZones.manage',
            'okta.trustedOrigins.manage',
            'okta.eventHooks.manage',
            'okta.linkedObjects.manage'
        ),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$AdminRole = @('SUPER_ADMIN'),

        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'OktaTestEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [ValidateSet(2048, 3072, 4096)]
        [int]$KeySize = 2048,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RevokeApiToken,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    if ($connection.AuthType -ne 'ApiToken') {
        # Confirmed against a live tenant: this fails with a bare 403. Client registration goes
        # through /oauth2/v1/clients, which is gated by okta.clients.manage - NOT by
        # okta.apps.manage, and not by holding SUPER_ADMIN either. That scope is deliberately
        # absent from the default grant, because an app that can register further OAuth clients
        # can escalate its own privileges, and seeding a lab never needs to.
        #
        # The practical consequence: rotating the key means reconnecting with an SSWS token.
        # That is a reasonable thing to require once, and the alternative is a lab credential
        # that can mint more of itself.
        Write-Warning ('Registering an app requires the okta.clients.manage scope, which the ' +
            'seeded service app is deliberately not granted. Reconnect with -ApiToken (an SSWS ' +
            'token held by a super admin) to create or rotate a service app.')
    }

    if (-not $Label) { $Label = '{0} Test Environment Automation' -f $connection.Prefix }
    $resolvedCredentialPath = Get-OktaTestCredentialPath -OrgUrl $connection.OrgUrl -Path $CredentialPath

    $result = [PSCustomObject]@{
        ClientId       = $null
        AppId          = $null
        Label          = $Label
        Scopes         = @()
        AdminRoles     = @()
        CredentialPath  = $resolvedCredentialPath
        Protection      = $null
        VaultName       = $null
        ApiTokenRevoked = $null
        Warnings        = @()
    }

    $existing = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/apps' `
        -Query @{ q = $Label; limit = 50 } -Paginate | Where-Object { $_.label -eq $Label })

    if ($existing.Count -gt 0) {
        if (-not $Force) {
            throw ("An app labelled '$Label' already exists (id $($existing[0].id)). Its private " +
                "key is at '$resolvedCredentialPath' if it was created by this module. Pass " +
                '-Force to replace it, which invalidates that key, or -Label to create a second app.')
        }

        foreach ($app in $existing) {
            if ($PSCmdlet.ShouldProcess($app.label, "Delete the existing app $($app.id)")) {
                try {
                    $null = Invoke-OktaTestRequest -Method POST `
                        -Path "/api/v1/apps/$($app.id)/lifecycle/deactivate"
                }
                catch {
                    Write-Verbose "App $($app.id) was already inactive."
                }
                $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/apps/$($app.id)"
                Write-Verbose "Deleted existing app $($app.id)"
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Label, 'Register an OAuth service app with an admin role')) {
        return
    }

    $keyPair = New-OktaTestRsaKeyPair -KeySize $KeySize

    # The client registration endpoint rather than /api/v1/apps. It takes the flat OAuth
    # client shape, which is the documented way to register a service app with an inline JWKS,
    # and it returns the client_id that the grant and role endpoints both key off.
    $registration = @{
        client_name                = $Label
        response_types             = @('token')
        grant_types                = @('client_credentials')
        token_endpoint_auth_method = 'private_key_jwt'
        application_type           = 'service'
        jwks                       = @{ keys = @($keyPair.PublicJwk) }
    }

    $client = Invoke-OktaTestRequest -Method POST -Path '/oauth2/v1/clients' -Body $registration
    $result.ClientId = $client.client_id

    # For OIDC clients the app instance id and the client_id are the same value, but the
    # grants API is an app API and this is cheap insurance against that ever diverging.
    $appId = $client.client_id
    try {
        $app = Invoke-OktaTestRequest -Method GET -Path "/api/v1/apps/$($client.client_id)"
        $appId = $app.id
    }
    catch {
        Write-Verbose "Could not read the app instance back; assuming the app id equals the client id."
    }
    $result.AppId = $appId

    foreach ($scopeId in $Scope) {
        try {
            $null = Invoke-OktaTestRequest -Method POST -Path "/api/v1/apps/$appId/grants" -Body @{
                scopeId = $scopeId
                issuer  = $connection.OrgUrl
            }
            $result.Scopes += $scopeId
            Write-Verbose "Granted $scopeId"
        }
        catch {
            $message = "Could not grant '$scopeId': $($_.Exception.Message)"
            $result.Warnings += $message
            Write-Warning $message
        }
    }

    foreach ($role in $AdminRole) {
        try {
            $null = Invoke-OktaTestRequest -Method POST `
                -Path "/oauth2/v1/clients/$($client.client_id)/roles" -Body @{ type = $role }
            $result.AdminRoles += $role
            Write-Verbose "Assigned the $role role"
        }
        catch {
            $message = ("Could not assign the $role role: $($_.Exception.Message). The app has " +
                'scopes but no permissions, so every management call will return 403 until a ' +
                'role is assigned in the admin console.')
            $result.Warnings += $message
            Write-Warning $message
        }
    }

    $exportArgs = @{
        Path       = $resolvedCredentialPath
        OrgUrl     = $connection.OrgUrl
        ClientId   = $client.client_id
        AppId      = $appId
        Label      = $Label
        Scopes     = $result.Scopes
        PrivateJwk = $keyPair.PrivateJwk
        Confirm    = $false
    }
    if ($UseSecretStore) {
        $exportArgs.UseSecretStore = $true
        $exportArgs.VaultName      = $VaultName
        if ($VaultPassword) { $exportArgs.VaultPassword = $VaultPassword }
    }

    $export = Export-OktaTestAppCredential @exportArgs
    $result.Protection = $export.Protection
    $result.VaultName  = $export.VaultName

    if ($export -and -not $export.FileProtected) {
        $result.Warnings += ("The credential file at '$resolvedCredentialPath' could not be " +
            'locked to your account. Restrict it by hand before leaving it there.')
    }

    # Worth saying out loud rather than only recording in the file. An unprotected key is a
    # state the user can fix, but only if they know they are in it.
    if ($export.Protection -eq 'None') {
        $result.Warnings += ("The private key is stored UNENCRYPTED at " +
            "'$resolvedCredentialPath', protected only by file permissions. Re-run with " +
            '-UseSecretStore for encrypted storage on this platform.')
    }

    # Prove the whole chain works now, while the SSWS token is still connected and the cause of
    # any failure is still obvious. Grants and role assignments take a moment to propagate, so
    # a failure here is a warning rather than an error.
    $verified = $false
    try {
        $token = Get-OktaTestAccessToken -CredentialPath $resolvedCredentialPath
        $verified = $true
        Write-OktaTestProgress -Message ("Service app verified: token issued for " +
            "$($token.Scopes -join ', ')") -Type Success
    }
    catch {
        $message = ("The app was created but a test token could not be issued yet: " +
            "$($_.Exception.Message). Grants can take a minute to propagate; retry with " +
            'Get-OktaTestAccessToken.')
        $result.Warnings += $message
        Write-Warning $message
    }

    # Revoking the bootstrap token, last of all and only when told to.
    #
    # This takes a name rather than doing it automatically because the module cannot identify
    # the token it is authenticating with: /api/v1/api-tokens/current returns 404 on a standard
    # org, and the list endpoint never returns token values, so an SSWS string cannot be matched
    # to a row. An org routinely holds several tokens serving Terraform, Postman and CI, and
    # guessing would eventually revoke one of those.
    if ($RevokeApiToken) {
        if (-not $verified) {
            # The interlock that matters. Revoking is irreversible and rotating this app's key
            # later needs an SSWS token, so throwing away the bootstrap credential before the
            # replacement has proven itself would leave no way back except the admin console.
            $message = ("Not revoking '$RevokeApiToken': the service app could not issue a " +
                'token, so the credential replacing it is unproven. Re-run Get-OktaTestAccessToken ' +
                'and revoke the API token by hand once it succeeds.')
            $result.Warnings += $message
            Write-Warning $message
        }
        else {
            try {
                $apiToken = Resolve-OktaTestApiToken -NameOrId $RevokeApiToken

                if (Revoke-OktaTestApiToken -TokenId $apiToken.id -TokenName $apiToken.name) {
                    $result.ApiTokenRevoked = $apiToken.name
                    Write-OktaTestProgress -Message ("Revoked API token '$($apiToken.name)'. " +
                        'This session can no longer make SSWS calls; reconnect with -ServiceApp.') -Type Info
                }
            }
            catch {
                $message = "Could not revoke API token '$RevokeApiToken': $($_.Exception.Message)"
                $result.Warnings += $message
                Write-Warning $message
            }
        }
    }

    $where = switch ($export.Protection) {
        'SecretStore' { "SecretStore vault '$($export.VaultName)' (pointer: $resolvedCredentialPath)" }
        'DPAPI'       { "$resolvedCredentialPath (DPAPI-encrypted)" }
        default       { "$resolvedCredentialPath (UNENCRYPTED)" }
    }
    Write-OktaTestProgress -Message "Service app '$Label' created. Key: $where" -Type Info
    Write-OktaTestProgress -Message ("Reconnect with: Connect-OktaTestEnvironment -OrgUrl " +
        "$($connection.OrgUrl) -ServiceApp") -Type Info

    if ($PassThru) { return $result }
}
