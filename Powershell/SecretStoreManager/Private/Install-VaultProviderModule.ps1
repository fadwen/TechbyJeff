# Vault Provider Module Management Functions
# Handles installation and management of provider modules

function Install-VaultProviderModule {
    <#
    .SYNOPSIS
        Installs missing vault provider modules
        
    .DESCRIPTION
        Automatically installs the required PowerShell modules for the specified
        vault providers. Can install all providers or specific ones.
        
    .PARAMETER ProviderType
        Array of provider types to install modules for
        
    .PARAMETER Force
        Force reinstallation even if modules are already available
        
    .EXAMPLE
        Install-VaultProviderModule -ProviderType @('AzureKeyVault', 'CredMan')
        
    .EXAMPLE
        Install-VaultProviderModule -Force
        
    .NOTES
        This function requires appropriate permissions to install PowerShell modules
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [string[]]$ProviderType = @('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager'),
        
        [Parameter()]
        [switch]$Force
    )

    $results = @{
        Installed = @()
        Failed = @()
        AlreadyInstalled = @()
    }

    foreach ($type in $ProviderType) {
        try {
            $provider = New-VaultProvider -ProviderType $type
            
            if ($provider.IsAvailable -and -not $Force) {
                $results.AlreadyInstalled += @{
                    Type = $type
                    ModuleName = $provider.ModuleName
                }
                Write-Verbose "Provider '$type' module '$($provider.ModuleName)' is already available"
                continue
            }

            Write-Information "Installing provider module '$($provider.ModuleName)' for '$type'..." -InformationAction Continue
            $provider.InstallModule()
            
            if ($provider.IsAvailable) {
                $results.Installed += @{
                    Type = $type
                    ModuleName = $provider.ModuleName
                }
                Write-Information "Successfully installed '$($provider.ModuleName)'" -InformationAction Continue
            }
            else {
                throw "Module installation verification failed"
            }
        }
        catch {
            $results.Failed += @{
                Type = $type
                Error = $_.Exception.Message
            }
            Write-Error "Failed to install provider '$type': $($_.Exception.Message)"
        }
    }

    return $results
}
