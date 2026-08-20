@{
    # Module manifest for WmicTriage
    RootModule = 'WmicTriage.psm1'
    ModuleVersion = '0.1.0'
    GUID = '2f901247-35c5-4a3d-a358-1ddf365e2c14'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'EntraVantage LLC'
    Copyright = '(c) 2026 EntraVantage LLC. All rights reserved.'
    # Kept to one line for the repository's 115-character limit. The README carries the full
    # explanation of what each tier means and why the tool sorts by them.
    Description = 'Finds deprecated WMIC usage and sorts each hit by how hard it will be to replace'

    # PowerShell Version Requirements
    # 5.1 rather than the repository default of 7.6. The estates that still run WMIC are the same
    # estates whose jump boxes and build servers never got pwsh, and a migration tool that cannot
    # run where the migration is happening is not much use.
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required Modules
    # None. Everything here is text and XML parsing over files on disk - nothing calls WMI, and
    # nothing needs to run on Windows. Scanning a deployment share from a Linux build agent works.
    RequiredModules = @()

    # Functions to Export
    FunctionsToExport = @(
        'Invoke-WmicScan',
        'Export-WmicScanReport',
        'Get-WmicRule'
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
            Tags = @('WMIC', 'Deprecation', 'Migration', 'CIM', 'WMI', 'Windows', 'SARIF')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = '0.1.0 - first release: four tiers, batch for /f block capture, SARIF output'
            RequireLicenseAcceptance = $false
        }
    }

    # Help Information
    HelpInfoURI = ''
}
