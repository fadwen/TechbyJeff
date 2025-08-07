# Azure Key Vault provider implementation
class AzureKeyVaultProvider : BaseVaultProvider {
    AzureKeyVaultProvider() : base('AzureKeyVault', 'CredentialStore.AzureKeyVault') {
    }

    [hashtable] CreateVault([string]$vaultName, [hashtable]$parameters) {
        $result = @{
            VaultCreated = $false
            VaultConfigured = $false
            Errors = @()
            Provider = 'AzureKeyVault'
        }

        try {
            if (-not $this.IsAvailable) {
                $result.Errors += "CredentialStore.AzureKeyVault module not available"
                return $result
            }

            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
            if ($existingVault) {
                $result.VaultConfigured = $true
                return $result
            }

            # Register Azure Key Vault
            $vaultParameters = @{
                AZKVaultName = if ($parameters.AzureVaultName) { $parameters.AzureVaultName } else { $vaultName }
                SubscriptionId = $parameters.SubscriptionId
            }

            Register-SecretVault -Name $vaultName -ModuleName 'CredentialStore.AzureKeyVault' -VaultParameters $vaultParameters
            $result.VaultCreated = $true
            $result.VaultConfigured = $true

        } catch {
            $result.Errors += $_.Exception.Message
        }

        return $result
    }

    [hashtable] RemoveVault([string]$vaultName, [bool]$force) {
        $result = @{
            VaultRemoved = $false
            SecretsRemoved = 0
            Errors = @()
            Provider = 'AzureKeyVault'
        }

        try {
            # Note: We don't remove secrets from Azure Key Vault as they may be used by other applications
            if ($force) {
                $result.Errors += "Warning: Secrets not removed from Azure Key Vault (vault registration only removed)"
            }

            Unregister-SecretVault -Name $vaultName
            $result.VaultRemoved = $true

        } catch {
            $result.Errors += $_.Exception.Message
        }

        return $result
    }

    [object] StoreSecret([string]$vaultName, [string]$secretName, [object]$secret, [hashtable]$metadata) {
        try {
            Set-Secret -Name $secretName -Secret $secret -Vault $vaultName -Metadata $metadata
            return @{ Success = $true; Provider = 'AzureKeyVault' }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message; Provider = 'AzureKeyVault' }
        }
    }

    [object] GetSecret([string]$vaultName, [string]$secretName, [bool]$asPlainText) {
        try {
            if ($asPlainText) {
                return Get-Secret -Name $secretName -Vault $vaultName -AsPlainText
            } else {
                return Get-Secret -Name $secretName -Vault $vaultName
            }
        } catch {
            throw "Failed to retrieve secret '$secretName' from Azure Key Vault '$vaultName': $($_.Exception.Message)"
        }
    }

    [array] ListSecrets([string]$vaultName) {
        try {
            return Get-SecretInfo -Vault $vaultName
        } catch {
            return @()
        }
    }
}
