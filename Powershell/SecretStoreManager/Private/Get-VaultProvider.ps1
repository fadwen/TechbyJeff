# Vault Provider Discovery Functions
# Discovers and lists available vault providers

function Get-VaultProvider {
    <#
    .SYNOPSIS
        Gets information about all available vault providers
        
    .DESCRIPTION
        Scans all supported provider types and returns information about their
        availability, module requirements, and capabilities
        
    .EXAMPLE
        $providers = Get-VaultProvider
        $providers | Format-Table Type, IsAvailable, ModuleName
        
    .NOTES
        This function checks the actual availability of each provider by attempting
        to create an instance and checking module availability
    #>
    [CmdletBinding()]
    param()

    $providers = @()
    
    $providerTypes = @('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager')
    
    foreach ($type in $providerTypes) {
        try {
            $provider = New-VaultProvider -ProviderType $type
            $providers += @{
                Type = $type
                Name = $provider.Name
                ModuleName = $provider.ModuleName
                IsAvailable = $provider.IsAvailable
                Description = Get-VaultProviderDescription -ProviderType $type
            }
        }
        catch {
            Write-Warning "Failed to initialize provider '$type': $($_.Exception.Message)"
        }
    }
    
    return $providers
}
