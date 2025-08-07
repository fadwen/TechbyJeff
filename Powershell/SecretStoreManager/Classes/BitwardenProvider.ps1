# Bitwarden provider implementation
class BitwardenProvider : BaseVaultProvider {
    BitwardenProvider() : base('Bitwarden', 'SecretManagement.Warden') {
    }

    [hashtable] CreateVault([string]$vaultName, [hashtable]$parameters) {
        $result = @{
            VaultCreated = $false
            VaultConfigured = $false
            Errors = @()
            Provider = 'Bitwarden'
            Prerequisites = @()
        }

        try {
            # Check if SecretManagement.Warden module is available
            if (-not $this.IsAvailable) {
                $result.Errors += "SecretManagement.Warden module not available"
                return $result
            }

            # Check if Bitwarden CLI is installed
            $bwCommand = Get-Command 'bw' -ErrorAction SilentlyContinue
            if (-not $bwCommand) {
                $result.Errors += "Bitwarden CLI (bw) not found in PATH. Please install from https://bitwarden.com/help/cli/"
                $result.Prerequisites += "Install Bitwarden CLI: https://bitwarden.com/help/cli/"
                return $result
            }

            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
            if ($existingVault) {
                $result.VaultConfigured = $true
                return $result
            }

            # Prepare vault parameters for SecretManagement.Warden
            $vaultParameters = @{}
            
            if ($parameters.ServerURL) {
                $vaultParameters.ServerURL = $parameters.ServerURL
            }
            
            if ($parameters.Email) {
                $vaultParameters.Email = $parameters.Email
            }
            
            if ($parameters.OrganizationId) {
                $vaultParameters.OrganizationId = $parameters.OrganizationId
            }

            # Register Bitwarden vault
            if ($vaultParameters.Count -gt 0) {
                Register-SecretVault -Name $vaultName -ModuleName 'SecretManagement.Warden' -VaultParameters $vaultParameters
            } else {
                Register-SecretVault -Name $vaultName -ModuleName 'SecretManagement.Warden'
            }
            
            $result.VaultCreated = $true
            $result.VaultConfigured = $true

            # Check if user is logged in to Bitwarden CLI
            try {
                $statusOutput = & bw status 2>&1
                if ($statusOutput -match '"status":\s*"unauthenticated"') {
                    $result.Prerequisites += "Login to Bitwarden CLI: bw login <email>"
                } elseif ($statusOutput -match '"status":\s*"locked"') {
                    $result.Prerequisites += "Unlock Bitwarden CLI: bw unlock"
                }
            } catch {
                $result.Prerequisites += "Ensure Bitwarden CLI is properly configured"
            }

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
            Provider = 'Bitwarden'
        }

        try {
            # Check if vault exists
            $vault = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
            if (-not $vault) {
                $result.Errors += "Vault '$vaultName' not found"
                return $result
            }

            # For Bitwarden, we only unregister the vault from SecretManagement
            # The actual secrets remain in the user's Bitwarden account
            if ($force) {
                Unregister-SecretVault -Name $vaultName
                $result.VaultRemoved = $true
            } else {
                $result.Errors += "Use -Force to remove Bitwarden vault registration (secrets remain in your Bitwarden account)"
            }

        } catch {
            $result.Errors += $_.Exception.Message
        }

        return $result
    }

    [hashtable] TestConnection([hashtable]$parameters) {
        $result = @{
            Connected = $false
            ModuleAvailable = $this.IsAvailable
            CLIAvailable = $false
            Authenticated = $false
            Errors = @()
            Provider = 'Bitwarden'
        }

        try {
            # Check if Bitwarden CLI is available
            $bwCommand = Get-Command 'bw' -ErrorAction SilentlyContinue
            if ($bwCommand) {
                $result.CLIAvailable = $true
                
                # Check authentication status
                try {
                    $statusOutput = & bw status 2>&1
                    if ($statusOutput -match '"status":\s*"unlocked"') {
                        $result.Authenticated = $true
                        $result.Connected = $true
                    } elseif ($statusOutput -match '"status":\s*"locked"') {
                        $result.Errors += "Bitwarden CLI is locked. Run 'bw unlock' to authenticate."
                    } elseif ($statusOutput -match '"status":\s*"unauthenticated"') {
                        $result.Errors += "Bitwarden CLI is not authenticated. Run 'bw login <email>' to authenticate."
                    }
                } catch {
                    $result.Errors += "Failed to check Bitwarden CLI status: $($_.Exception.Message)"
                }
            } else {
                $result.Errors += "Bitwarden CLI (bw) not found. Install from https://bitwarden.com/help/cli/"
            }

        } catch {
            $result.Errors += $_.Exception.Message
        }

        return $result
    }

    [hashtable] ValidateConfiguration([hashtable]$parameters) {
        $result = @{
            Valid = $true
            MissingRequired = @()
            InvalidOptional = @()
            Errors = @()
            Provider = 'Bitwarden'
        }

        try {
            # Bitwarden has no required parameters, but validate optional ones if provided
            if ($parameters.ServerURL -and $parameters.ServerURL -notmatch '^https?://') {
                $result.InvalidOptional += 'ServerURL must be a valid HTTP/HTTPS URL'
                $result.Valid = $false
            }

            if ($parameters.Email -and $parameters.Email -notmatch '^[^@]+@[^@]+\.[^@]+$') {
                $result.InvalidOptional += 'Email must be a valid email address'
                $result.Valid = $false
            }

        } catch {
            $result.Errors += $_.Exception.Message
            $result.Valid = $false
        }

        return $result
    }
}
