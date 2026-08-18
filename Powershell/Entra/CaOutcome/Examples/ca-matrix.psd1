@{
    # A Conditional Access scenario matrix, expanded by Expand-CaScenario into every
    # combination of persona, resource and condition.
    #
    #     $matrix = Import-PowerShellDataFile .\ca-matrix.psd1
    #     Expand-CaScenario -Matrix $matrix | Invoke-CaScenarioMatrix
    #
    # Held as data rather than code on purpose. It can be reviewed and extended by someone who
    # does not write PowerShell, it diffs cleanly next to the baseline it produces, and it is
    # the same artefact whether it is driving an ad hoc check or a nightly run.
    #
    # Every axis multiplies. Three personas by two resources by five conditions is thirty API
    # calls, which is why Expand-CaScenario refuses to expand past MaxScenarioCount rather than
    # quietly running a shorter matrix than the one you wrote.

    # One row per shape of user you actually care about, not one per user. The interesting
    # failures live in populations - the contractor, the service desk, the break glass account -
    # not in individuals.
    Personas = @(
        @{ Name = 'standard';   UserId = '00000000-0000-0000-0000-000000000001' }
        @{ Name = 'admin';      UserId = '00000000-0000-0000-0000-000000000002' }

        # The account that has to work when everything else has stopped. A policy tightened
        # without its emergency access exclusion is discovered during the incident it was
        # supposed to survive, which is the worst possible moment to find out.
        @{ Name = 'breakglass'; UserId = '00000000-0000-0000-0000-000000000003' }
    )

    # Exactly one of ApplicationId, UserAction or AuthenticationContext per resource - they map
    # to three different signInContext types and a resource asking for two describes no request
    # that can be sent.
    Resources = @(
        @{ Name = 'office365'; ApplicationId = '00000003-0000-0ff1-ce00-000000000000' }

        # Registering security information is the user action that most often turns out to be
        # blocked by a policy nobody meant to point at it, stranding a user who cannot enrol
        # the very factor the policy is demanding.
        @{ Name = 'register-mfa'; UserAction = 'registerSecurityInformation' }
    )

    # PascalCase here, camelCase on the wire - Expand-CaScenario lowercases the first letter.
    # Any documented signInConditions property works, and so does one Microsoft adds later.
    Conditions = @(
        @{ Name = 'managed-windows'
           DevicePlatform = 'windows'; ClientAppType = 'browser'
           SignInRiskLevel = 'low'; UserRiskLevel = 'low'; Country = 'US'
           DeviceInfo = @{ isCompliant = $true; trustType = 'azureAD' } }

        # The row that most often produces a finding. A report-only policy requiring a compliant
        # device applies to this sign-in exactly as it does to the managed one, and the API
        # reports it as applying either way - so without the device state in the request it
        # reads as a mild extra requirement rather than as the lockout it is.
        @{ Name = 'unmanaged-windows'
           DevicePlatform = 'windows'; ClientAppType = 'browser'
           SignInRiskLevel = 'low'; UserRiskLevel = 'low'; Country = 'US'
           DeviceInfo = @{ isCompliant = $false } }

        @{ Name = 'unmanaged-ios'
           DevicePlatform = 'iOS'; ClientAppType = 'browser'
           SignInRiskLevel = 'low'; UserRiskLevel = 'low'; Country = 'US'
           DeviceInfo = @{ isCompliant = $false } }

        # Legacy authentication, which should be blocked outright. Worth asserting rather than
        # assuming: the block is usually there, and usually has an exclusion nobody remembers.
        @{ Name = 'legacy-auth'
           DevicePlatform = 'windows'; ClientAppType = 'exchangeActiveSync'
           SignInRiskLevel = 'low'; UserRiskLevel = 'low'; Country = 'US'
           DeviceInfo = @{ isCompliant = $false } }

        @{ Name = 'high-risk-foreign'
           DevicePlatform = 'windows'; ClientAppType = 'browser'
           SignInRiskLevel = 'high'; UserRiskLevel = 'high'; Country = 'DE'
           DeviceInfo = @{ isCompliant = $false } }

        # Device code flow, which cannot pass device state to the device doing the
        # authentication - so any policy requiring a compliant or hybrid joined device is
        # unsatisfiable here no matter how well managed the device is. Note the deliberately
        # compliant, hybrid joined device below: the flow overrides it.
        @{ Name = 'device-code-flow'
           DevicePlatform = 'windows'; ClientAppType = 'mobileAppsAndDesktopClients'
           SignInRiskLevel = 'low'; UserRiskLevel = 'low'; Country = 'US'
           AuthenticationFlow = @{ transferMethod = 'deviceCodeFlow' }
           DeviceInfo = @{ isCompliant = $true; trustType = 'serverAD' } }
    )
}
