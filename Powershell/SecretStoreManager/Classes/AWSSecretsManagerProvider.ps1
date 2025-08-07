# AWS Secrets Manager provider implementation
class AWSSecretsManagerProvider : BaseVaultProvider {
    AWSSecretsManagerProvider() : base('AWSSecretsManager', 'SecretsManagement.CAWSSecretsManager') {
    }

    [hashtable] CreateVault([string]$vaultName, [hashtable]$parameters) {
        $result = @{
            VaultCreated = $false
            VaultConfigured = $false
            Errors = @()
            Provider = 'AWSSecretsManager'
        }

        try {
            if (-not $this.IsAvailable) {
                $result.Errors += "SecretsManagement.CAWSSecretsManager module not available"
                return $result
            }

            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
            if ($existingVault) {
                $result.VaultConfigured = $true
                return $result
            }

            # Register AWS Secrets Manager vault
            $vaultParameters = @{
                Region = if ($parameters.AWSRegion) { $parameters.AWSRegion } else { 'us-east-1' }
            }

            if ($parameters.AWSProfile) {
                $vaultParameters.Profile = $parameters.AWSProfile
            }

            Register-SecretVault -Name $vaultName -ModuleName 'SecretsManagement.CAWSSecretsManager' -VaultParameters $vaultParameters
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
            Provider = 'AWSSecretsManager'
        }

        try {
            # Note: We don't remove secrets from AWS Secrets Manager as they may be used by other applications
            if ($force) {
                $result.Errors += "Warning: Secrets not removed from AWS Secrets Manager (vault registration only removed)"
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
            return @{ Success = $true; Provider = 'AWSSecretsManager' }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message; Provider = 'AWSSecretsManager' }
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
            throw "Failed to retrieve secret '$secretName' from AWS Secrets Manager vault '$vaultName': $($_.Exception.Message)"
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
