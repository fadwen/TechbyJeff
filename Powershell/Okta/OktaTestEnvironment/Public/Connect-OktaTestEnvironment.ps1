function Connect-OktaTestEnvironment {
    <#
    .SYNOPSIS
        Establishes the Okta connection every other function in the module uses

    .DESCRIPTION
        Two authentication modes, and the order between them is the whole point of the
        module's design:

        1. -ApiToken, an SSWS token created by hand in the admin console. This is the
           bootstrap. It is the only credential that exists before anything has been created,
           and it is the one that can create the service app.
        2. -ServiceApp, the OAuth service app created by New-OktaTestServiceApp. From the
           second run onward this is what you use, and the SSWS token can be revoked.

        The connection is validated before it is stored. A bad token that is accepted here and
        rejected on the first real call gives you an error about users when the problem is the
        credential, so the cheapest possible request is made up front.

        Prefix and EmailDomain are recorded on the connection rather than passed to every
        function. They are what teardown keys off, so having them set once, at connect time,
        removes the failure mode where an environment is seeded under one prefix and torn down
        under another.

    .PARAMETER OrgUrl
        The org URL, for example https://trial-123456.okta.com. Both the admin host
        (-admin.okta.com) and a trailing slash are tolerated and normalised away, because both
        are what you get from copying the address bar.

    .PARAMETER ApiToken
        An SSWS API token as a SecureString. Create one under Security > API > Tokens in the
        admin console. The token inherits the permissions of the admin who created it, so a
        super admin's token is needed to create the service app and assign it a role.

    .PARAMETER ServiceApp
        Authenticate with the saved service app credential instead of an SSWS token

    .PARAMETER CredentialPath
        Path to the service app credential file. Defaults to the per-user location for this
        org.

    .PARAMETER Prefix
        Name prefix and seed tag for everything this module creates. Everything created and
        everything removed is scoped by it.

    .PARAMETER EmailDomain
        Domain for seeded user logins and emails. The default is under example.com, which RFC
        2606 reserves precisely so test data cannot deliver mail to a real recipient. Change
        it only if you own the domain you change it to.

    .PARAMETER ActiveUserLimit
        The tenant's active user ceiling. Ten matches an Okta trial org; raise it
        if this tenant is on a paid plan.

    .PARAMETER PassThru
        Return the connection object

    .OUTPUTS
        PSCustomObject describing the connection, when -PassThru is used

    .EXAMPLE
        $token = Read-Host 'SSWS token' -AsSecureString
        Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ApiToken $token
        First run: bootstrap with the API token

    .EXAMPLE
        Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ServiceApp
        Every run after that: authenticate as the app

    .EXAMPLE
        Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ApiToken $token `
            -Prefix CONTOSO -EmailDomain contoso-lab.example.com
        Seed under a different prefix, so two labs can share one tenant

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

    .LINK
        New-OktaTestEnvironment
        New-OktaTestServiceApp
        Disconnect-OktaTestEnvironment
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path, not a credential. The key it points at never appears here.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ServiceApp',
        Justification = 'Selects the ServiceApp parameter set; the set name is what is read, not the switch.')]
    [CmdletBinding(DefaultParameterSetName = 'ApiToken')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^https://')]
        [string]$OrgUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'ApiToken')]
        [System.Security.SecureString]$ApiToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServiceApp')]
        [switch]$ServiceApp,

        [Parameter(ParameterSetName = 'ServiceApp')]
        [string]$CredentialPath,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9]{2,20}$')]
        [string]$Prefix = 'OKTALAB',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain = 'oktalab.example.com',

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$ActiveUserLimit = 10,

        [Parameter()]
        [switch]$PassThru
    )

    # The admin console lives on a different host from the API. Pasting the address bar is the
    # single most common way to get this wrong, and the resulting failure is a 404 on every
    # call rather than anything that names the cause.
    $normalisedOrg = $OrgUrl.TrimEnd('/')
    if ($normalisedOrg -match '^(?<scheme>https://)(?<org>[^.]+)-admin\.(?<rest>.+)$') {
        $normalisedOrg = '{0}{1}.{2}' -f $Matches.scheme, $Matches.org, $Matches.rest
        Write-Warning "Using the API host '$normalisedOrg' rather than the admin host you supplied."
    }

    $scopes = @()
    $tokenExpiry = $null

    if ($PSCmdlet.ParameterSetName -eq 'ApiToken') {
        $authorizationHeader = 'SSWS {0}' -f (ConvertFrom-OktaTestSecureString -SecureString $ApiToken)
        $authType = 'ApiToken'
        $resolvedCredentialPath = $null
    }
    else {
        $resolvedCredentialPath = Get-OktaTestCredentialPath -OrgUrl $normalisedOrg -Path $CredentialPath
        $token = Get-OktaTestAccessToken -CredentialPath $resolvedCredentialPath -OrgUrl $normalisedOrg
        $authorizationHeader = "Bearer $($token.AccessToken)"
        $authType = 'ServiceApp'
        $scopes = @($token.Scopes)
        $tokenExpiry = $token.ExpiresUtc
    }

    $candidate = @{
        OrgUrl              = $normalisedOrg
        AuthorizationHeader = $authorizationHeader
        AuthType            = $authType
        Prefix              = $Prefix.ToUpperInvariant()
        EmailDomain         = $EmailDomain.TrimStart('@')
        ActiveUserLimit     = $ActiveUserLimit
        SeedMarker          = '[seed:{0}]' -f $Prefix.ToUpperInvariant()
        CredentialPath      = $resolvedCredentialPath
        Scopes              = $scopes
        TokenExpiresUtc     = $tokenExpiry
        ConnectedAt         = Get-Date
    }

    # Cheapest call that proves both the host and the credential. limit=1 keeps it to a single
    # user's worth of response on a tenant that may only hold ten.
    try {
        $null = Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' -Query @{ limit = 1 } `
            -Connection $candidate
    }
    catch {
        throw ("Could not authenticate to $normalisedOrg as $authType`: $($_.Exception.Message)")
    }

    $script:OktaConnection = $candidate

    Write-OktaTestProgress -Message "Connected to $normalisedOrg as $authType (prefix $($candidate.Prefix))" `
        -Type Success

    if ($PassThru) {
        # The Authorization header is deliberately absent from what is returned. It is a live
        # credential and this object ends up in transcripts and PassThru result bundles.
        return [PSCustomObject]@{
            OrgUrl          = $candidate.OrgUrl
            AuthType        = $candidate.AuthType
            Prefix          = $candidate.Prefix
            EmailDomain     = $candidate.EmailDomain
            ActiveUserLimit = $candidate.ActiveUserLimit
            Scopes          = $candidate.Scopes
            TokenExpiresUtc = $candidate.TokenExpiresUtc
            ConnectedAt     = $candidate.ConnectedAt
        }
    }
}
