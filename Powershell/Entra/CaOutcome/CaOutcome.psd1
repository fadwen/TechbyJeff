@{
    # Module manifest for CaOutcome
    RootModule = 'CaOutcome.psm1'
    ModuleVersion = '0.5.1'
    GUID = '4c1e8a76-9b23-4f5d-8e10-6d7a2f3b95c8'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'EntraVantage LLC'
    Copyright = '(c) 2026 EntraVantage LLC. All rights reserved.'
    # Kept to one line for the repository's 115-character limit. The README carries the
    # full explanation of what "promotion" means here.
    Description = 'Folds a Conditional Access What If response into an effective outcome and diffs a promotion'

    # PowerShell Version Requirements
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Required Modules
    # Deliberately none, even though Invoke-CaScenarioMatrix does send requests. Its default
    # request handler looks for Invoke-MgGraphRequest at run time and says so if it is absent,
    # and every other function is a pure transform. Declaring the Graph SDK here would make the
    # whole module unimportable - and its tests unrunnable - on a host that only ever needed the
    # folding. Supply -RequestHandler and the SDK is not involved at all.
    RequiredModules = @()

    # Functions to Export
    FunctionsToExport = @(
        'ConvertTo-CaOutcome',
        'Expand-CaScenario',
        'Invoke-CaScenarioMatrix',
        'Export-CaBaseline',
        'Compare-CaBaseline'
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
            Tags = @('Entra', 'ConditionalAccess', 'WhatIf', 'Maester', 'Identity', 'Security')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = '0.5.1 - deterministic winner for an unresolved session conflict'
            RequireLicenseAcceptance = $false
        }
    }

    # Help Information
    HelpInfoURI = ''
}
