function Get-OktaTestSeededApp {
    <#
    .SYNOPSIS
        Finds the app integrations this module created, separating lab apps from the service app

    .DESCRIPTION
        Two markers are required, the same belt-and-braces rule the groups use: the label starts
        with the prefix, AND a second marker confirms the app was created here. Requiring both
        matters more for apps than anywhere else, because the tenant this was developed against
        already held apps named after real things (Google Workspace, a Postman client, an AD
        agent). A label-prefix match alone is the kind of rule that eventually deletes one.

        The second marker is not uniform, and finding that out cost a bug. Okta ACCEPTS a
        profile object on any app and then silently discards it for every sign-on mode except
        OPENID_CONNECT - the POST succeeds, the response omits it, and a follow-up PUT does not
        help either. Verified against a live tenant. A teardown keyed on the profile alone
        therefore found one app out of eight and quietly left the rest behind.

        So two second markers are accepted, either of which is enough:

        - profile.labSeedTag equal to the prefix. Reliable for OIDC apps only.
        - A URL pointing at the seed email domain. Every seeded app targets that domain, it
          survives on every app type, and it is the same fallback the users use.

        The URL lives in a different place per type: settings.app.url for bookmark and SWA
        apps, settings.oauthClient.redirect_uris for OIDC ones.

        The service app is excluded by default and returned separately, so teardown can remove
        the lab apps while keeping the credential it authenticates with. The two are told apart
        by the delimiter: lab apps are "PREFIX-Label", the service app is "PREFIX Something".

    .PARAMETER Prefix
        The label prefix and seed tag to match

    .PARAMETER EmailDomain
        The seed domain the app URLs point at

    .PARAMETER IncludeServiceApp
        Return the service app as well as the lab apps

    .OUTPUTS
        Array of Okta app objects

    .EXAMPLE
        Get-OktaTestSeededApp -Prefix 'OKTALAB' -EmailDomain 'oktalab.example.com'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.1.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain,

        [Parameter()]
        [switch]$IncludeServiceApp
    )

    $apps = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/apps' `
        -Query @{ q = $Prefix; limit = 200 } -Paginate)

    $domain = $EmailDomain.TrimStart('@')

    return @($apps | Where-Object {
        if (-not $_.label) { return $false }

        $isLabApp = $_.label.StartsWith("$Prefix-", [StringComparison]::OrdinalIgnoreCase)

        if (-not $isLabApp) {
            # The service app carries neither marker: it predates them, and its OIDC profile is
            # not set. It is identified by its label alone, which is safe because the prefix is
            # followed by a space rather than being an open-ended pattern.
            if ($IncludeServiceApp) {
                return $_.label.StartsWith("$Prefix ", [StringComparison]::OrdinalIgnoreCase)
            }
            return $false
        }

        $tagged = $_.settings -and $_.profile -and
            $_.profile.PSObject.Properties['labSeedTag'] -and
            $_.profile.labSeedTag -eq $Prefix

        if ($tagged) { return $true }

        # Gather every URL the app exposes, whichever shape it uses.
        $urls = @()
        if ($_.settings) {
            if ($_.settings.PSObject.Properties['app'] -and $_.settings.app -and
                $_.settings.app.PSObject.Properties['url']) {
                $urls += $_.settings.app.url
            }
            if ($_.settings.PSObject.Properties['oauthClient'] -and $_.settings.oauthClient) {
                $urls += @($_.settings.oauthClient.redirect_uris)
            }
        }

        foreach ($url in ($urls | Where-Object { $_ })) {
            $urlHost = $null
            try { $urlHost = ([uri]$url).Host } catch { continue }
            if (-not $urlHost) { continue }

            # Suffix match on a dot boundary, or the domain exactly. A bare -like '*domain*'
            # would match notoktalab.example.com.evil.test, the same trap the user lookup avoids.
            if ($urlHost.Equals($domain, [StringComparison]::OrdinalIgnoreCase) -or
                $urlHost.EndsWith(".$domain", [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    })
}
