function Remove-SecretStoreVault {
    <#
    .SYNOPSIS
        Removes a SecretStore vault and all its stored secrets

    .DESCRIPTION
        Safely removes a SecretStore vault and all its stored secrets.
        Includes safety checks and error handling.

    .PARAMETER VaultName
        Name of the secret vault to remove. Defaults to "SecretStoreVault"

    .PARAMETER Force
        Force removal without additional confirmation

    .PARAMETER ResetSecretStore
        Also reset the global SecretStore configuration to defaults.
        When used with -Force, sets SecretStore to no authentication mode.
        Without -Force, uses interactive Reset-SecretStore (prompts for new password).
        WARNING: This will affect ALL SecretStore vaults on the system.
        Use with caution if you have other vaults configured.

    .EXAMPLE
        Remove-SecretStoreVault
        Removes the default SecretStoreVault

    .EXAMPLE
        Remove-SecretStoreVault -ResetSecretStore
        Removes the default vault AND resets SecretStore configuration

    .EXAMPLE
        Remove-SecretStoreVault -VaultName "ProdVault" -ResetSecretStore -Force
        Removes a custom vault, resets SecretStore, without prompts

    .OUTPUTS
        PSCustomObject containing vault removal results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - All secrets in the vault will be permanently deleted
        - Vault configuration will be removed from the system
        - This operation cannot be undone
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = $script:DefaultVaultName,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$ResetSecretStore
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Remove-SecretStoreVault - CorrelationId: $correlationId"
        
        $result = @{
            CorrelationId = $correlationId
            VaultName = $VaultName
            VaultExists = $false
            VaultRemoved = $false
            SecretsRemoved = 0
            SecretStoreReset = $false
            Errors = @()
            Warnings = @()
        }
    }

    process {
        try {
            # Check if SecretStore modules are available
            $modulesAvailable = $true
            try {
                Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop
                Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction Stop
                Write-Verbose "SecretStore modules imported successfully"
            }
            catch {
                $modulesAvailable = $false
                $result.Warnings += "SecretStore modules not available - vault may not exist"
                Write-Verbose "SecretStore modules not available: $($_.Exception.Message)"
            }

            if ($modulesAvailable) {
                # Check if vault exists
                $existingVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
                
                if ($existingVault) {
                    $result.VaultExists = $true
                    Write-Verbose "Found vault '$VaultName' - proceeding with removal"
                    
                    try {
                        # Try to get list of secrets in the vault for counting (only if not forcing to avoid password prompt)
                        if (-not $Force) {
                            try {
                                $secrets = Get-SecretInfo -Vault $VaultName -ErrorAction Stop
                                $result.SecretsRemoved = $secrets.Count
                                
                                if ($secrets.Count -gt 0) {
                                    Write-Verbose "Vault contains $($secrets.Count) secrets that will be removed"
                                }
                                $secretCountMsg = "$($secrets.Count) secrets"
                            }
                            catch {
                                # If we can't access secrets (password required), we'll just remove the vault anyway
                                Write-Verbose "Cannot access vault contents (password may be required): $($_.Exception.Message)"
                                $result.SecretsRemoved = 0
                                $secretCountMsg = "contents"
                            }
                        }
                        else {
                            # Force specified - skip secret enumeration to avoid password prompt
                            Write-Verbose "Force specified - skipping secret enumeration to avoid password prompt"
                            $result.SecretsRemoved = 0
                            $secretCountMsg = "contents"
                        }
                        
                        # Remove the vault (this also removes all secrets)
                        if ($Force -or $PSCmdlet.ShouldProcess("SecretStore Vault: $VaultName", "Remove vault and $secretCountMsg")) {
                            Unregister-SecretVault -Name $VaultName -ErrorAction Stop
                            $result.VaultRemoved = $true
                            
                            Write-Verbose "Successfully removed vault: $VaultName"
                            Write-Verbose "Removed $($result.SecretsRemoved) secrets from vault"
                        }
                        else {
                            Write-Verbose "Vault removal cancelled by ShouldProcess"
                        }
                        
                    }
                    catch {
                        $errorMsg = "Failed to remove vault '$VaultName': $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        Write-Error $errorMsg
                    }
                }
                else {
                    Write-Verbose "Vault '$VaultName' does not exist - nothing to remove"
                    $result.Warnings += "Vault '$VaultName' was not found (may have been already removed)"
                }

                # Reset SecretStore configuration if requested
                if ($ResetSecretStore) {
                    try {
                        Write-Verbose "Resetting SecretStore configuration..."
                        
                        # Check if SecretStore is configured
                        $storeConfig = Get-SecretStoreConfiguration -ErrorAction SilentlyContinue
                        
                        if ($storeConfig) {
                            if ($Force -or $PSCmdlet.ShouldProcess("SecretStore Configuration", "Reset to no authentication")) {
                                # Reset SecretStore using proper parameters
                                try {
                                    # Use secure vault password handling with fallback for test scenarios
                                    $securePassword = Get-SecureVaultPassword -VaultName "SecretStore" -AllowDefault
                                    Reset-SecretStore -Password $securePassword -Authentication None -Interaction None -Force -ErrorAction Stop
                                    Write-Verbose "SecretStore reset with secure password to no authentication"
                                }
                                catch {
                                    # If that fails, try resetting to no authentication without specifying current password
                                    Write-Verbose "Trying alternative reset method: $($_.Exception.Message)"
                                    Reset-SecretStore -Authentication None -Interaction None -Force -ErrorAction Stop
                                    Write-Verbose "SecretStore reset to no authentication"
                                }
                                
                                $result.SecretStoreReset = $true
                                Write-Verbose "Successfully reset SecretStore configuration (no authentication required)"
                            }
                            else {
                                Write-Verbose "SecretStore reset cancelled by ShouldProcess"
                            }
                        }
                        else {
                            Write-Verbose "SecretStore is not configured - nothing to reset"
                        }
                    }
                    catch {
                        $errorMsg = "Failed to reset SecretStore configuration: $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        Write-Warning $errorMsg
                    }
                }
            }
            
        }
        catch {
            $errorMsg = "Failed to remove secret vault: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
    }

    end {
        Write-Verbose "Completed Remove-SecretStoreVault - CorrelationId: $correlationId"
        return [PSCustomObject]$result
    }
}
