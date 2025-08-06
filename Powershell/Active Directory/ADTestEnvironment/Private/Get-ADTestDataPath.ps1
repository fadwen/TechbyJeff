function Get-ADTestDataPath {
    <#
    .SYNOPSIS
        Gets the path to the test data files

    .DESCRIPTION
        Returns the path to the Data folder containing CSV files and user images

    .OUTPUTS
        String path to the Data folder

    .EXAMPLE
        $dataPath = Get-ADTestDataPath
        $usersCSV = Join-Path $dataPath "ADUsers.csv"

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    # First try the module variable if set
    if ($script:ModuleDataPath -and (Test-Path $script:ModuleDataPath)) {
        return $script:ModuleDataPath
    }

    # Fallback: look for Data folder relative to module root
    $dataPath = Join-Path $PSScriptRoot "..\Data"
    if (Test-Path $dataPath) {
        return $dataPath
    }

    # Additional fallback: check relative to current location
    $currentPath = Join-Path (Get-Location) "Generate-TestData\Data"
    if (Test-Path $currentPath) {
        return $currentPath
    }

    # Final fallback: hardcoded path based on known structure
    $hardcodedPath = "C:\Users\Administrator.TBJ-ALBEDO\Downloads\CreateUserAccounts\Generate-TestData\Data"
    if (Test-Path $hardcodedPath) {
        return $hardcodedPath
    }

    throw "Could not locate Data folder. Tried paths: $dataPath, $currentPath, $hardcodedPath"
}
