function New-TestSecretVault {
    <#
    .SYNOPSIS
        Creates a new test secret vault with support for multiple providers

    .DESCRIPTION
        Creates and configures a test secret vault using one of the supported providers:
        - SecretStore: Local PowerShell SecretStore (default, good for development)
        - AzureKeyVault: Azure Key Vault (requires Azure subscription and authentication)
        - CredMan: Windows Credential Manager (Windows only)
        - AWSSecretsManager: AWS Secrets Manager (requires AWS account and credentials)

        The function handles provider-specific configuration, module installation,
        and vault registration automatically.

    .PARAMETER VaultName
        [String] (Mandatory: Yes, Pipeline: ByValue)
        Name for the new secret vault. Must be unique across all registered vaults.

    .PARAMETER ProviderType
        [String] (Mandatory: No, Default: SecretStore)
        The vault provider to use. Valid options:
        - SecretStore: Local encrypted storage
        - AzureKeyVault: Azure cloud vault
        - CredMan: Windows Credential Manager
        - AWSSecretsManager: AWS cloud vault

    .PARAMETER Configuration
        [Hashtable] (Mandatory: No)
        Provider-specific configuration parameters:
        
        AzureKeyVault requires:
        - AzureVaultName: Name of the Azure Key Vault
        - SubscriptionId: Azure subscription ID
        
        AWSSecretsManager requires:
        - AWSRegion: AWS region (e.g., 'us-east-1')
        Optional:
        - AWSProfile: AWS profile name

    .PARAMETER InstallMissingModules
        [Switch] (Mandatory: No)
        Automatically install required modules if they are missing

    .PARAMETER Force
        [Switch] (Mandatory: No)
        Force creation even if a vault with the same name already exists (will reconfigure)

    .PARAMETER DefaultVault
        [Switch] (Mandatory: No)
        Set this vault as the default vault for secret operations

    .EXAMPLE
        PS> New-TestSecretVault -VaultName "DevVault"

        DESCRIPTION: Creates a local SecretStore vault for development
        OUTPUT: Vault configuration details and success status
        USE CASE: Quick setup for development and testing scenarios

    .EXAMPLE
        PS> $azConfig = @{
                AzureVaultName = 'my-keyvault'
                SubscriptionId = '12345678-1234-1234-1234-123456789012'
            }
        PS> New-TestSecretVault -VaultName "ProdVault" -ProviderType "AzureKeyVault" -Configuration $azConfig -InstallMissingModules

        DESCRIPTION: Creates Azure Key Vault integration with automatic module installation
        BUSINESS CASE: Enterprise production environment with cloud-based secret management
        INTEGRATION: Requires Azure authentication (Connect-AzAccount)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2024-01-20
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter()]
        [ValidateSet('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager', 'Bitwarden')]
        [string]$ProviderType = 'SecretStore',

        [Parameter()]
        [hashtable]$Configuration = @{},

        [Parameter()]
        [switch]$InstallMissingModules,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DefaultVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-TestSecretVault - CorrelationId: $correlationId"
        Write-Verbose "Provider: $ProviderType, Vault: $VaultName"

        # Initialize result object
        $result = [PSCustomObject]@{
            VaultName = $VaultName
            ProviderType = $ProviderType
            Success = $false
            VaultCreated = $false
            VaultConfigured = $false
            ModulesInstalled = @()
            Errors = @()
            Warnings = @()
            CorrelationId = $correlationId
            CreatedDate = Get-Date
        }
    }

    process {
        try {
            if ($PSCmdlet.ShouldProcess($VaultName, "Create $ProviderType vault")) {
                
                Write-Information "Creating $ProviderType vault: $VaultName" -InformationAction Continue

                # Step 1: Get and validate provider
                Write-Verbose "Initializing provider: $ProviderType"
                $provider = New-VaultProvider -ProviderType $ProviderType
                
                if (-not $provider.IsAvailable) {
                    if ($InstallMissingModules) {
                        Write-Debug "Provider object: $($provider | ConvertTo-Json)"
                        Write-Information "Installing missing module: $($provider.ModuleName)" -InformationAction Continue
                        $provider.InstallModule()
                        if ($provider.IsAvailable) {
                            $result.ModulesInstalled += $provider.ModuleName
                            Write-Information "Successfully installed $($provider.ModuleName)" -InformationAction Continue
                        } else {
                            throw "Failed to install required module: $($provider.ModuleName)"
                        }
                    } else {
                        throw "Required module '$($provider.ModuleName)' is not available. Use -InstallMissingModules to install automatically."
                    }
                }

                # Step 2: Validate configuration
                Write-Verbose "Validating provider configuration"
                $configValidation = Test-VaultProviderConfiguration -ProviderType $ProviderType -Configuration $Configuration
                
                if (-not $configValidation.IsValid) {
                    $errorMessage = "Configuration validation failed for $ProviderType provider"
                    if ($configValidation.MissingParameters.Count -gt 0) {
                        $errorMessage += ". Missing required parameters: $($configValidation.MissingParameters -join ', ')"
                    }
                    if ($configValidation.Errors.Count -gt 0) {
                        $errorMessage += ". Errors: $($configValidation.Errors -join '; ')"
                    }
                    throw $errorMessage
                }

                # Add warnings for configuration issues
                foreach ($warning in $configValidation.Warnings) {
                    $result.Warnings += $warning
                    Write-Warning $warning
                }

                # Step 3: Check if vault already exists
                $existingVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
                if ($existingVault -and -not $Force) {
                    $result.Warnings += "Vault '$VaultName' already exists. Use -Force to reconfigure."
                    $result.VaultConfigured = $true
                    $result.Success = $true
                    Write-Information "Vault '$VaultName' already exists" -InformationAction Continue
                    return $result
                }

                # Step 4: Remove existing vault if Force is specified
                if ($existingVault -and $Force) {
                    Write-Information "Removing existing vault for reconfiguration" -InformationAction Continue
                    Unregister-SecretVault -Name $VaultName
                }

                # Step 5: Create the vault
                Write-Information "Creating vault with $ProviderType provider..." -InformationAction Continue
                $vaultResult = $provider.CreateVault($VaultName, $Configuration)
                
                $result.VaultCreated = $vaultResult.VaultCreated
                $result.VaultConfigured = $vaultResult.VaultConfigured
                
                if ($vaultResult.Errors.Count -gt 0) {
                    $result.Errors += $vaultResult.Errors
                    throw "Vault creation failed: $($vaultResult.Errors -join '; ')"
                }

                # Step 6: Set as default vault if requested
                if ($DefaultVault) {
                    try {
                        Set-SecretVaultDefault -Name $VaultName
                        Write-Information "Set '$VaultName' as default vault" -InformationAction Continue
                    } catch {
                        $result.Warnings += "Failed to set as default vault: $($_.Exception.Message)"
                        Write-Warning "Failed to set as default vault: $($_.Exception.Message)"
                    }
                }

                # Step 7: Test vault connectivity
                Write-Verbose "Testing vault connectivity"
                $connectivityTest = Test-VaultConnectivity -VaultName $VaultName
                if (-not $connectivityTest.IsAccessible) {
                    $result.Warnings += "Vault created but connectivity test failed: $($connectivityTest.Errors -join '; ')"
                    Write-Warning "Vault created but may not be fully accessible"
                } else {
                    Write-Verbose "Vault connectivity test passed (Response time: $($connectivityTest.ResponseTime)ms)"
                }

                $result.Success = $true
                Write-Information "Successfully created vault '$VaultName' using $ProviderType provider" -InformationAction Continue

                # Display summary
                Write-Information "`nVault Creation Summary:" -InformationAction Continue
                Write-Information "  Vault Name: $VaultName" -InformationAction Continue
                Write-Information "  Provider: $ProviderType" -InformationAction Continue
                Write-Information "  Status: Created and Configured" -InformationAction Continue
                if ($result.ModulesInstalled.Count -gt 0) {
                    Write-Information "  Modules Installed: $($result.ModulesInstalled -join ', ')" -InformationAction Continue
                }
                if ($DefaultVault) {
                    Write-Information "  Default Vault: Yes" -InformationAction Continue
                }
            }
        }
        catch {
            $result.Errors += $_.Exception.Message
            $result.Success = $false
            Write-Error "Failed to create vault '$VaultName': $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-TestSecretVault - CorrelationId: $correlationId"
        return $result
    }
}