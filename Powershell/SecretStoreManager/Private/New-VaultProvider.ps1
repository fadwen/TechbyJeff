# Vault Provider Factory Functions
# Creates and manages provider instances

function New-VaultProvider {
    <#
    .SYNOPSIS
        Creates a vault provider instance based on the specified type
        
    .DESCRIPTION
        Factory function that creates and returns the appropriate vault provider
        instance based on the provider type specified.
        
    .PARAMETER ProviderType
        The type of vault provider to create
        
    .EXAMPLE
        $provider = New-VaultProvider -ProviderType 'SecretStore'
        
    .NOTES
        This is the main factory function for creating provider instances
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager', 'Bitwarden')]
        [string]$ProviderType
    )

    if ($PSCmdlet.ShouldProcess("$ProviderType Provider", "Create vault provider instance")) {
        switch ($ProviderType) {
            'SecretStore' { return [SecretStoreProvider]::new() }
            'AzureKeyVault' { return [AzureKeyVaultProvider]::new() }
            'CredMan' { return [CredManProvider]::new() }
            'AWSSecretsManager' { return [AWSSecretsManagerProvider]::new() }
            'Bitwarden' { return [BitwardenProvider]::new() }
            default { throw "Unknown provider type: $ProviderType" }
        }
    }
}

function Get-VaultProviderDescription {
    <#
    .SYNOPSIS
        Gets a human-readable description for a vault provider
        
    .DESCRIPTION
        Returns a descriptive string that explains what the provider is used for
        
    .PARAMETER ProviderType
        The type of vault provider to describe
        
    .EXAMPLE
        $description = Get-VaultProviderDescription -ProviderType 'AzureKeyVault'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderType
    )

    $descriptions = @{
        'SecretStore' = 'Local PowerShell SecretStore vault for development and testing'
        'AzureKeyVault' = 'Azure Key Vault for cloud-based secret management'
        'CredMan' = 'Windows Credential Manager for local credential storage'
        'AWSSecretsManager' = 'AWS Secrets Manager for cloud-based secret management'
        'Bitwarden' = 'Bitwarden password manager for personal and business secret management'
    }

    if ($descriptions.ContainsKey($ProviderType)) {
        return $descriptions[$ProviderType]
    } else {
        return "Unknown provider: $ProviderType"
    }
}
