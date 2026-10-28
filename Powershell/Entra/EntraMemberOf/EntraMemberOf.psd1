@{
    # Module manifest for EntraMemberOf
    RootModule = 'EntraMemberOf.psm1'
    ModuleVersion = '0.1.0'
    GUID = '3f6c2a8e-9b41-4d7a-8e5c-1a2b7c0d9e64'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'Jeffrey Stuhr'
    Copyright = '(c) 2026 Jeffrey Stuhr. All rights reserved.'
    # One line for the 115-character limit; the README carries the full description
    Description = 'Finds memberOf dynamic membership rules in Entra ID groups, administrative units and policies'

    # PowerShell 7 only. 7.4 is the oldest release still in support when this was written;
    # Windows PowerShell 5.1 was not tested and is not claimed.
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')

    # Deliberately none. Tenant mode looks for Invoke-MgGraphRequest at run time and says so
    # if it is missing; rule text and file mode have no dependency at all. Declaring the Graph
    # SDK here would stop the module importing, and its tests running, on a host that only
    # scans an export.
    RequiredModules = @()

    FormatsToProcess = @('EntraMemberOf.Format.ps1xml')

    FunctionsToExport = @(
        'Test-EntraMemberOfRule'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'Entra', 'EntraID', 'MicrosoftEntra', 'DynamicGroups', 'memberOf', 'AdministrativeUnits',
                'EntitlementManagement', 'MicrosoftGraph', 'Identity', 'PSEdition_Core', 'Windows', 'Linux',
                'MacOS'
            )
            LicenseUri = 'https://github.com/fadwen/TechbyJeff/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/TechbyJeff/tree/main/Powershell/Entra/EntraMemberOf'
            ReleaseNotes = '0.1.0 - Initial release. Scans rule text, exports and tenants for memberOf rules.'
            RequireLicenseAcceptance = $false
        }
    }
}
