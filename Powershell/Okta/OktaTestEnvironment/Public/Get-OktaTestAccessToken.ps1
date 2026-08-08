function Get-OktaTestAccessToken {
    <#
    .SYNOPSIS
        Exchanges the service app's private key for an Okta API access token

    .DESCRIPTION
        Runs the client credentials flow with private_key_jwt against the org authorisation
        server. This is the "later auth" half of the module: the SSWS token is only needed
        once, to create the app, and every run after that can authenticate with the key this
        reads off disk.

        The org authorisation server (/oauth2/v1/token) is used rather than the default
        custom one (/oauth2/default/v1/token). Only the org server issues tokens carrying
        okta.* scopes, and a token from the default server will be accepted by the token
        endpoint and then rejected by every management API call, which is a confusing way to
        find out.

        No client secret is involved anywhere. A service app configured for private_key_jwt
        does not have one, which is the reason to prefer it for a lab that lives in a
        repository: there is nothing to leak into a transcript.

    .PARAMETER CredentialPath
        Path to the credential file written by New-OktaTestServiceApp. Defaults to the
        per-user location for the connected org.

    .PARAMETER OrgUrl
        Org to authenticate against. Defaults to the one recorded in the credential file.

    .PARAMETER Scope
        Scopes to request. Defaults to the scopes recorded in the credential file, which are
        the ones actually granted to the app; asking for more than was granted fails.

    .PARAMETER VaultPassword
        Password used to unlock the SecretStore vault, when the credential is stored in one.
        Ignored for the DPAPI default, which needs no password.

    .PARAMETER AsPlainText
        Return the raw token string rather than the result object. Convenient for piping into
        another tool, and deliberately not the default.

    .OUTPUTS
        PSCustomObject with AccessToken, TokenType, Scopes, ExpiresInSeconds and ExpiresUtc,
        or a String when -AsPlainText is used.

    .EXAMPLE
        Get-OktaTestAccessToken
        Mints a token using the saved credential for the connected org

    .EXAMPLE
        $token = Get-OktaTestAccessToken -AsPlainText
        curl -H "Authorization: Bearer $token" https://trial-123456.okta.com/api/v1/users

    .EXAMPLE
        Get-OktaTestAccessToken -Scope okta.users.read
        Requests a narrower token than the app is entitled to

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        The returned token is a bearer credential with whatever admin role the app holds.
        Treat it exactly as you would the SSWS token it replaces.

    .LINK
        New-OktaTestServiceApp
        Connect-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path, not a credential. The key it points at never appears here.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [string]$OrgUrl,

        [Parameter()]
        [string[]]$Scope,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$AsPlainText
    )

    if (-not $CredentialPath) {
        $connection = Get-OktaTestConnection -AllowNone
        $resolvedOrg = if ($OrgUrl) { $OrgUrl } elseif ($connection) { $connection.OrgUrl } else { $null }

        if (-not $resolvedOrg) {
            throw ('Specify -CredentialPath or -OrgUrl, or connect first, so the credential ' +
                'file can be located.')
        }
        $CredentialPath = Get-OktaTestCredentialPath -OrgUrl $resolvedOrg
    }

    $importArgs = @{ Path = $CredentialPath }
    if ($VaultPassword) { $importArgs.VaultPassword = $VaultPassword }
    $credential = Import-OktaTestAppCredential @importArgs

    $tokenOrg = if ($OrgUrl) { $OrgUrl.TrimEnd('/') } else { $credential.orgUrl.TrimEnd('/') }
    $audience = "$tokenOrg/oauth2/v1/token"

    $requestedScopes = if ($Scope) { $Scope } else { @($credential.scopes) }
    if (-not $requestedScopes -or $requestedScopes.Count -eq 0) {
        throw ("The credential at '$CredentialPath' records no scopes and none were passed. " +
            'Pass -Scope with the scopes the app was granted.')
    }

    $assertion = New-OktaTestClientAssertion -PrivateJwk $credential.privateJwk `
        -ClientId $credential.clientId -Audience $audience

    $form = @(
        'grant_type=client_credentials'
        'scope={0}' -f [uri]::EscapeDataString(($requestedScopes -join ' '))
        'client_assertion_type={0}' -f
            [uri]::EscapeDataString('urn:ietf:params:oauth:client-assertion-type:jwt-bearer')
        'client_assertion={0}' -f [uri]::EscapeDataString($assertion)
    ) -join '&'

    # An explicit connection with no Authorization header. The assertion in the body is the
    # credential here, and this also keeps the call from re-entering Get-OktaTestConnection,
    # which is what would otherwise recurse when it renews an expiring token.
    $tokenConnection = @{ OrgUrl = $tokenOrg; AuthorizationHeader = $null }

    $response = Invoke-OktaTestRequest -Method POST -Path '/oauth2/v1/token' -Body $form `
        -ContentType 'application/x-www-form-urlencoded' -Connection $tokenConnection

    if (-not $response.access_token) {
        throw 'The token endpoint returned no access_token.'
    }

    if ($AsPlainText) { return $response.access_token }

    return [PSCustomObject]@{
        AccessToken      = $response.access_token
        TokenType        = $response.token_type
        Scopes           = @($response.scope -split ' ' | Where-Object { $_ })
        ExpiresInSeconds = $response.expires_in
        ExpiresUtc       = [DateTime]::UtcNow.AddSeconds([int]$response.expires_in)
        ClientId         = $credential.clientId
        OrgUrl           = $tokenOrg
        CredentialPath   = $CredentialPath
    }
}
