function Set-SecretInVault {
    <#
    .SYNOPSIS
        Sets multiple secrets in a vault with automatic vault creation and configuration

    .DESCRIPTION
        Handles comprehensive secret vault operations including:
        - Prerequisites verification
        - Vault creation and configuration for multiple providers
        - Secret storage in supported vaults
        
        This function provides end-to-end secret management while maintaining
        single responsibility principle. Supports SecretStore, AzureKeyVault,
        CredMan, and AWS Secrets Manager.

    .PARAMETER SecretData
        Array of secret objects to store in the vault.
        Expected format: @{ AccountName = "name"; Secret = "password"; SecretType = "type"; Description = "desc"; ExpirationDate = "date" }

    .PARAMETER VaultName
        Name of the secret vault to create/use. Defaults to "TestVault"

    .PARAMETER VaultProvider
        The vault provider to use: SecretStore, AzureKeyVault, CredMan, or AWSSecretsManager

    .PARAMETER VaultConfiguration
        Provider-specific configuration hashtable

    .PARAMETER CorrelationId
        Correlation ID for tracking related operations

    .PARAMETER DefaultExpirationDays
        Default number of days until expiration for secrets. Defaults to 90 days.

    .PARAMETER InstallMissingModules
        Automatically install required provider modules if they are not available

    .EXAMPLE
        $secrets = @(
            @{ AccountName = "MyApp"; Secret = "MyPassword123!"; SecretType = "Credential"; Description = "Application credential" }
        )
        Set-SecretInVault -SecretData $secrets -VaultName "MyVault" -VaultProvider "SecretStore"
        Creates SecretStore vault and stores secrets

    .EXAMPLE
        $config = @{ SubscriptionId = "12345"; VaultName = "MyKeyVault"; ResourceGroupName = "MyRG" }
        Set-SecretInVault -SecretData $secrets -VaultProvider "AzureKeyVault" -VaultConfiguration $config -InstallMissingModules
        Creates Azure Key Vault with auto-module installation and stores secrets

    .OUTPUTS
        PSCustomObject containing operation results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2024-01-15
        
        Security Notes:
        - Validates vault provider prerequisites before proceeding
        - Creates vault with appropriate scope and security
        - Stores secrets securely using provider-specific APIs
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$SecretData,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "TestVault",
        
        [Parameter()]
        [ValidateSet('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager', 'Bitwarden')]
        [string]$VaultProvider = 'SecretStore',
        
        [Parameter()]
        [hashtable]$VaultConfiguration = @{},
        
        [Parameter()]
        [ValidateNotNull()]
        [System.Guid]$CorrelationId = [System.Guid]::NewGuid(),
        
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$DefaultExpirationDays = 90,
        
        [Parameter()]
        [switch]$InstallMissingModules
    )

    begin {
        Write-Verbose "Starting secret storage operation - Provider: $VaultProvider, Vault: $VaultName, CorrelationId: $CorrelationId"
        
        $result = @{
            CorrelationId = $CorrelationId
            VaultName = $VaultName
            VaultProvider = $VaultProvider
            VaultCreated = $false
            VaultConfigured = $false
            SecretsStored = 0
            TotalSecrets = $SecretData.Count
            Errors = @()
            Warnings = @()
            VaultResult = $null
            SecretResult = $null
        }
    }

    process {
        if ($PSCmdlet.ShouldProcess("$VaultName ($VaultProvider)", "Create vault and store $($SecretData.Count) secrets")) {
            try {
                # Step 1: Verify provider prerequisites
                Write-Verbose "Verifying $VaultProvider prerequisites..."
                $prereqResult = Test-SecretStorePrerequisite
                if (-not $prereqResult.AllModulesAvailable) {
                    throw "Prerequisites not satisfied: $($prereqResult.Errors -join '; ')"
                }
                Write-Verbose "Prerequisites verified successfully"
            
            # Step 2: Create/configure vault using new provider system
            Write-Verbose "Creating/configuring $VaultProvider vault: $VaultName"
            $vaultParams = @{
                VaultName = $VaultName
                ProviderType = $VaultProvider
            }

            # Add provider-specific configuration
            if ($VaultConfiguration.Count -gt 0) {
                $vaultParams.Configuration = $VaultConfiguration
            }

            # Add InstallMissingModules if specified
            if ($InstallMissingModules) {
                $vaultParams.InstallMissingModules = $true
            }

            $vaultResult = New-TestSecretVault @vaultParams
            $result.VaultResult = $vaultResult
            
            if ($vaultResult.Errors.Count -gt 0) {
                throw "Failed to create/configure vault: $($vaultResult.Errors -join '; ')"
            }
            
            $result.VaultCreated = $vaultResult.VaultCreated
            $result.VaultConfigured = $vaultResult.VaultConfigured
            Write-Verbose "Vault operation completed successfully"
            
            # Step 3: Store secrets in vault
            Write-Verbose "Storing $($SecretData.Count) secrets in $VaultProvider vault..."
            $secretResult = Set-VaultSecret -SecretData $SecretData -VaultName $VaultName -CorrelationId $CorrelationId -DefaultExpirationDays $DefaultExpirationDays
            $result.SecretResult = $secretResult
            
            if ($secretResult.Errors.Count -gt 0) {
                throw "Failed to store secrets in vault: $($secretResult.Errors -join '; ')"
            }
            
            $result.SecretsStored = $secretResult.TotalStored
            Write-Verbose "Successfully stored $($secretResult.TotalStored) secrets in vault"
            
            # Collect any warnings from sub-operations
            if ($vaultResult.Warnings.Count -gt 0) {
                $result.Warnings += $vaultResult.Warnings
            }
            if ($secretResult.Warnings.Count -gt 0) {
                $result.Warnings += $secretResult.Warnings
            }
        }
        catch {
            $errorMsg = "Secret storage operation failed: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
        }
    }

    end {
        Write-Verbose "Completed secret storage operation - CorrelationId: $CorrelationId"
        return [PSCustomObject]$result
    }
}
