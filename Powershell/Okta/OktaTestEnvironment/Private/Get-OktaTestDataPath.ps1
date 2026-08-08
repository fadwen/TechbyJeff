function Get-OktaTestDataPath {
    <#
    .SYNOPSIS
        Gets the path to the module's CSV seed data

    .DESCRIPTION
        Returns the path to the Data folder holding the user, group, group rule and profile
        attribute definitions.

    .OUTPUTS
        String path to the Data folder

    .EXAMPLE
        $dataPath = Get-OktaTestDataPath
        $users = Import-Csv (Join-Path $dataPath 'OktaUsers.csv') -Encoding UTF8

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Set by the root module at import time. Everything else is a fallback for the case where
    # the file was dot-sourced directly rather than imported as a module, which is how the
    # unit tests load private functions.
    if ($script:ModuleDataPath -and (Test-Path -Path $script:ModuleDataPath)) {
        return $script:ModuleDataPath
    }

    $relativePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Data'
    if (Test-Path -Path $relativePath) {
        return (Resolve-Path -Path $relativePath).ProviderPath
    }

    throw "Could not locate the Data folder. Tried '$script:ModuleDataPath' and '$relativePath'."
}
