# CredMan provider implementation
class CredManProvider : BaseVaultProvider {
    CredManProvider() : base('CredMan', 'SecretManagement.JustinGrote.CredMan') {
    }

    [hashtable] CreateVault([string]$vaultName, [hashtable]$parameters) {
        $result = @{
            VaultCreated = $false
            VaultConfigured = $false
            Errors = @()
            Provider = 'CredMan'
        }

        try {
            if (-not $this.IsAvailable) {
                $result.Errors += "SecretManagement.JustinGrote.CredMan module not available"
                return $result
            }

            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
            if ($existingVault) {
                $result.VaultConfigured = $true
                return $result
            }

            # Register CredMan vault
            Register-SecretVault -Name $vaultName -ModuleName 'SecretManagement.JustinGrote.CredMan'
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
            Provider = 'CredMan'
        }

        try {
            # Remove all secrets first if force is specified
            if ($force) {
                $secrets = $this.ListSecrets($vaultName)
                foreach ($secret in $secrets) {
                    try {
                        Remove-Secret -Name $secret.Name -Vault $vaultName -ErrorAction SilentlyContinue
                        $result.SecretsRemoved++
                    } catch {
                        $result.Errors += "Failed to remove secret '$($secret.Name)': $($_.Exception.Message)"
                    }
                }
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
            return @{ Success = $true; Provider = 'CredMan' }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message; Provider = 'CredMan' }
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
            throw "Failed to retrieve secret '$secretName' from CredMan vault '$vaultName': $($_.Exception.Message)"
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
