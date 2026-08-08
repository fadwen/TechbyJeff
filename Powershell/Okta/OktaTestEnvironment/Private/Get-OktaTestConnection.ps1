function Get-OktaTestConnection {
    <#
    .SYNOPSIS
        Returns the active Okta connection established by Connect-OktaTestEnvironment

    .DESCRIPTION
        Every function that talks to Okta calls this rather than reading the script variable
        directly, so there is exactly one place that decides what "not connected" means and
        exactly one error message for it.

    .PARAMETER AllowNone
        Return $null instead of throwing when no connection is established. Used by teardown
        and report paths that want to degrade rather than fail.

    .OUTPUTS
        Hashtable with OrgUrl, AuthorizationHeader, AuthType, Prefix, EmailDomain and
        ConnectedAt keys.

    .EXAMPLE
        $connection = Get-OktaTestConnection
        $connection.OrgUrl

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$AllowNone
    )

    if (-not $script:OktaConnection) {
        if ($AllowNone) { return $null }

        throw ('Not connected to Okta. Run Connect-OktaTestEnvironment -OrgUrl ' +
            'https://<your-org>.okta.com -ApiToken <SSWS token> first.')
    }

    # A service app access token lives an hour, which is longer than a seed run but shorter
    # than a working session, and the symptom of letting it lapse is a 401 partway through a
    # teardown. Renewing here means every caller gets a live token without knowing about it.
    #
    # This does not recurse: Get-OktaTestAccessToken talks to the token endpoint through an
    # explicit -Connection, so it never comes back through this function.
    if ($script:OktaConnection.AuthType -eq 'ServiceApp' -and $script:OktaConnection.TokenExpiresUtc) {
        if ([DateTime]::UtcNow -ge $script:OktaConnection.TokenExpiresUtc.AddSeconds(-60)) {
            Write-Verbose 'Service app access token is about to expire; requesting a new one.'
            $token = Get-OktaTestAccessToken -CredentialPath $script:OktaConnection.CredentialPath `
                -Scope $script:OktaConnection.Scopes
            $script:OktaConnection.AuthorizationHeader = "Bearer $($token.AccessToken)"
            $script:OktaConnection.TokenExpiresUtc = $token.ExpiresUtc
        }
    }

    return $script:OktaConnection
}
