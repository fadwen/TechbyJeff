#
# SecretStoreManager Module
# PowerShell module for managing Microsoft.PowerShell.SecretStore vaults and secrets
# Author: Jeffrey Stuhr
# Version: 1.0.0
#

# Load classes in correct order (base class, then derived classes)
$Classes = @(
    'BaseVaultProvider.ps1',
    'SecretStoreProvider.ps1',
    'AzureKeyVaultProvider.ps1',
    'CredManProvider.ps1',
    'AWSSecretsManagerProvider.ps1',
    'BitwardenProvider.ps1'
)

foreach ($className in $Classes) {
    $classFile = Join-Path $PSScriptRoot "Classes\$className"
    if (Test-Path $classFile) {
        try {
            . $classFile
        }
        catch {
            Write-Error -Message "Failed to import class $className`: $($_.Exception.Message)"
        }
    }
}

# Get public and private function definition files.
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)

# Dot source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $($_.Exception.Message)"
    }
}

# Export public functions
Export-ModuleMember -Function $Public.Basename

# Module variables
$script:DefaultVaultName = "SecretStoreVault"
