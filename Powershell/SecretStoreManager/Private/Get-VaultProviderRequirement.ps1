# Vault Provider Requirements and Metadata Functions
# Provides detailed information about provider requirements and capabilities

# Vault Provider Requirements and Metadata Functions
# Provides detailed information about provider requirements and capabilities

function Get-VaultProviderRequirement {
    <#
    .SYNOPSIS
        Gets detailed requirements and metadata for a vault provider
        
    .DESCRIPTION
        Returns comprehensive information about a provider including module
        requirements, configuration parameters, platform support, and authentication methods.
        Loads configuration from VaultProviders.psd1 for maintainability.
        
    .PARAMETER ProviderType
        The type of vault provider to get requirements for
        
    .EXAMPLE
        $requirements = Get-VaultProviderRequirement -ProviderType 'AzureKeyVault'
        $requirements.RequiredParameters
        
    .NOTES
        This function loads provider configuration from the VaultProviders.psd1
        configuration file to make adding new providers easier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderType
    )

    # Load provider configuration from data file
    $configPath = Join-Path $PSScriptRoot '..\Configuration\VaultProviders.psd1'
    
    if (-not (Test-Path $configPath)) {
        throw "Provider configuration file not found: $configPath"
    }

    try {
        $providerConfig = Import-PowerShellDataFile -Path $configPath
        
        if ($providerConfig.Providers.ContainsKey($ProviderType)) {
            $requirements = $providerConfig.Providers[$ProviderType].Clone()
            $requirements.Type = $ProviderType
            return $requirements
        } else {
            throw "Unknown provider type: $ProviderType. Available providers: $($providerConfig.Providers.Keys -join ', ')"
        }
    }
    catch {
        Write-Error "Failed to load provider configuration: $($_.Exception.Message)"
        throw
    }
}
