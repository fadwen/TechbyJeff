@{
    # Module manifest for ADTestEnvironment
    RootModule = 'ADTestEnvironment.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b5e8c4a2-1d3f-4e7a-9b2c-6f8d4e1a5c7b'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'EntraVantage LLC'
    Copyright = '(c) 2025 EntraVantage LLC. All rights reserved.'
    Description = 'PowerShell module for generating Active Directory test data including OUs, users, devices, and security groups'

    # PowerShell Version Requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required Modules
    RequiredModules = @('ActiveDirectory')

    # Functions to Export
    FunctionsToExport = @(
        'New-ADTestEnvironment',
        'New-ADTestOUStructure',
        'New-ADTestUsers',
        'New-ADTestDevices', 
        'New-ADTestSecurityGroups',
        'New-ADTestServiceAccounts',
        'Get-ADTestEnvironmentReport',
        'Remove-ADTestEnvironment'
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
            Tags = @('ActiveDirectory', 'TestData', 'Enterprise', 'Automation', 'AD')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = 'Initial release - Active Directory test data generation module'
            RequireLicenseAcceptance = $false
        }
    }

    # Help Information
    HelpInfoURI = ''
}
