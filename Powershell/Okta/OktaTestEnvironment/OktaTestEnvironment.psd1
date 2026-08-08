@{
    # Module manifest for OktaTestEnvironment
    RootModule = 'OktaTestEnvironment.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f3a7c619-2d84-4b51-9e6a-8c0d5f2b7e14'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'EntraVantage LLC'
    Copyright = '(c) 2026 EntraVantage LLC. Licensed under GPL-3.0.'
    Description = 'Seeds and tears down an Okta test tenant within a ten active user licence'

    # PowerShell Version Requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required Modules
    # Deliberately none. Everything is done with Invoke-WebRequest and the .NET crypto types,
    # so this runs on a stock host with no gallery installs and nothing to keep in step.
    RequiredModules = @()

    # Functions to Export
    FunctionsToExport = @(
        'Connect-OktaTestEnvironment',
        'Disconnect-OktaTestEnvironment',
        'New-OktaTestEnvironment',
        'New-OktaTestProfileAttribute',
        'New-OktaTestUser',
        'New-OktaTestGroup',
        'New-OktaTestGroupRule',
        'New-OktaTestApp',
        'New-OktaTestUserType',
        'New-OktaTestNetworkZone',
        'New-OktaTestPolicy',
        'New-OktaTestLinkedObject',
        'New-OktaTestTrustedOrigin',
        'New-OktaTestEventHook',
        'New-OktaTestServiceApp',
        'Get-OktaTestAccessToken',
        'Get-OktaTestAppCredential',
        'Get-OktaTestEnvironmentReport',
        'Remove-OktaTestEnvironment'
    )

    # Cmdlets to Export
    CmdletsToExport = @()

    # Variables to Export
    VariablesToExport = @()

    # Aliases to Export
    AliasesToExport = @()

    # Private Data
    PrivateData = @{
        PSData = @{
            Tags = @('Okta', 'TestData', 'Identity', 'Automation', 'OAuth', 'SCIM')
            LicenseUri = 'https://github.com/fadwen/TechbyJeff/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/TechbyJeff/tree/main/Powershell/Okta/OktaTestEnvironment'
            IconUri = ''
            ReleaseNotes = 'Initial release - Okta test environment generation module'
            RequireLicenseAcceptance = $false
        }
    }

    # Help Information
    HelpInfoURI = ''
}
