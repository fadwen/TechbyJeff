@{
    # Module manifest for EntraBrandingCss
    RootModule = 'EntraBrandingCss.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'b7d3f2a1-5c84-4e9b-a6f0-2d8c1e7b9a43'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'Jeffrey Stuhr'
    Copyright = '(c) 2026 Jeffrey Stuhr. All rights reserved.'
    # One line for the 115-character limit; the README carries the full description
    Description = 'Finds retired CSS properties in Entra ID company branding, from a tenant or a .css file'

    # File mode is pure PowerShell and runs on Windows PowerShell 5.1. Tenant mode needs
    # Microsoft.Graph.Authentication, which also supports 5.1.
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Deliberately none. Tenant mode looks for Invoke-MgGraphRequest at run time and says so
    # if it is missing; file mode has no dependency at all. Declaring the Graph SDK here would
    # stop the module importing, and its tests running, on a host that only scans files.
    RequiredModules = @()

    FormatsToProcess = @('EntraBrandingCss.Format.ps1xml')

    FunctionsToExport = @(
        'Test-EntraBrandingCss',
        'Get-EntraBrandingCssProperty'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'Entra', 'EntraID', 'MicrosoftEntra', 'CompanyBranding', 'CSS', 'MicrosoftGraph',
                'Identity', 'PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS'
            )
            LicenseUri = 'https://github.com/fadwen/TechbyJeff/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/TechbyJeff/tree/main/Powershell/Entra/EntraBrandingCss'
            ReleaseNotes = '0.1.0 - Initial release. Scans files and tenants for the 58 retired property names.'
            RequireLicenseAcceptance = $false
        }
    }
}
