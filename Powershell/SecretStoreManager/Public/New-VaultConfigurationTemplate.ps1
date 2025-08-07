# Vault Configuration Template Functions
# Generates configuration templates for different vault providers

function New-VaultConfigurationTemplate {
    <#
    .SYNOPSIS
        Generate a vault configuration template
        
    .DESCRIPTION
        Creates a configuration template for a specific vault provider,
        including required parameters, optional parameters, and example usage.
        Loads template structure from VaultProviders.psd1 for maintainability.
        
    .PARAMETER ProviderType
        The type of vault provider to create a template for
        
    .PARAMETER OutputPath
        Optional path to save the template file
        
    .PARAMETER GenerateExampleFiles
        Generate companion example files (PowerShell script and JSON config)
        
    .EXAMPLE
        $template = New-VaultConfigurationTemplate -ProviderType 'AzureKeyVault'
        
    .EXAMPLE
        New-VaultConfigurationTemplate -ProviderType 'AWSSecretsManager' -OutputPath 'aws-config.json'
        
    .EXAMPLE
        New-VaultConfigurationTemplate -ProviderType 'AzureKeyVault' -GenerateExampleFiles
        # Generates: AzureKeyVault-config.json and AzureKeyVault-example.ps1
        
    .NOTES
        This function helps users understand what configuration is needed for each provider.
        Uses data-driven templates from VaultProviders.psd1.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager', 'Bitwarden')]
        [string]$ProviderType,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$GenerateExampleFiles
    )

    $targetDescription = if ($OutputPath) { 
        "configuration template to file '$OutputPath'" 
    } elseif ($GenerateExampleFiles) { 
        "configuration template and example files for $ProviderType" 
    } else { 
        "configuration template for $ProviderType" 
    }
    
    if ($PSCmdlet.ShouldProcess($targetDescription, "Create vault configuration template")) {
        try {
        # Load provider requirements and metadata
        $requirements = Get-VaultProviderRequirement -ProviderType $ProviderType

        $template = @{
            ProviderType = $ProviderType
            CreatedDate = Get-Date
            Description = $requirements.Description
            PlatformSupport = $requirements.PlatformSupport
            AuthenticationMethods = $requirements.AuthenticationMethods
            Configuration = @{}
        }

        # Add required parameters with placeholder values
        foreach ($param in $requirements.RequiredParameters) {
            $template.Configuration[$param] = "[REQUIRED: Enter value for $param]"
        }

        # Add optional parameters with placeholder values
        foreach ($param in $requirements.OptionalParameters) {
            $template.Configuration[$param] = "[OPTIONAL: Enter value for $param if needed]"
        }

        # Load example configurations from the config file if available
        $configPath = Join-Path $PSScriptRoot '..\Configuration\VaultProviders.psd1'
        $providerConfig = Import-PowerShellDataFile -Path $configPath
        
        if ($providerConfig.Providers[$ProviderType].ExampleConfiguration) {
            # Merge example configuration
            foreach ($key in $providerConfig.Providers[$ProviderType].ExampleConfiguration.Keys) {
                $template.Configuration[$key] = $providerConfig.Providers[$ProviderType].ExampleConfiguration[$key]
            }
        }

        # Add example commands from config if available
        if ($providerConfig.Providers[$ProviderType].ExampleCommands) {
            $template.ExampleCommands = $providerConfig.Providers[$ProviderType].ExampleCommands
        } else {
            # Fallback to basic example
            $template.ExampleCommands = @(
                "# Create vault with this configuration:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType '$ProviderType' -Configuration `$config"
            )
        }

            if ($OutputPath) {
                $template | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Information "Configuration template saved to: $OutputPath" -InformationAction Continue
            }

            # Generate example files if requested
            if ($GenerateExampleFiles) {
                $baseFileName = "$ProviderType"
                $configFileName = "$baseFileName-config.json"
                $exampleFileName = "$baseFileName-example.ps1"
                
                # Generate JSON configuration file
                $configContent = @{
                    ProviderType = $ProviderType
                    Configuration = $template.Configuration
                    Description = $template.Description
                    Notes = @(
                        "This is an example configuration for $ProviderType provider"
                        "Update the configuration values according to your environment"
                        "Required parameters must be provided"
                        "Optional parameters can be omitted if not needed"
                    )
                }
                
                $configContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFileName -Encoding UTF8
                Write-Information "Configuration file saved to: $configFileName" -InformationAction Continue
                
                # Generate PowerShell example script
                $exampleScript = @"
# $ProviderType Provider Example Script
# Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Description: $($template.Description)

# Prerequisites and Setup
Write-Host "Setting up $ProviderType provider..." -ForegroundColor Green

# Required modules for $ProviderType
`$requiredModules = @($(($requirements.RequiredModules | ForEach-Object { "'$_'" }) -join ', '))

# Install required modules if not present
foreach (`$module in `$requiredModules) {
    if (-not (Get-Module `$module -ListAvailable)) {
        Write-Host "Installing module: `$module" -ForegroundColor Yellow
        Install-Module `$module -Force -Scope CurrentUser
    }
}

# Load configuration from JSON file
`$configPath = "./$configFileName"
if (Test-Path `$configPath) {
    `$configData = Get-Content `$configPath | ConvertFrom-Json
    `$config = `$configData.Configuration
    Write-Host "Loaded configuration from `$configPath" -ForegroundColor Green
} else {
    # Manual configuration setup
    Write-Host "Creating configuration manually..." -ForegroundColor Yellow
    `$config = @{
"@

                # Add configuration parameters
                foreach ($param in $requirements.RequiredParameters) {
                    $value = if ($template.Configuration[$param] -match '^\[REQUIRED:') { 
                        "# TODO: Set your $param value here"
                    } else { 
                        "'$($template.Configuration[$param])'"
                    }
                    $exampleScript += "`n        $param = $value"
                }
                
                foreach ($param in $requirements.OptionalParameters) {
                    $value = if ($template.Configuration[$param] -match '^\[OPTIONAL:') { 
                        "# OPTIONAL: Set your $param value here if needed"
                    } else { 
                        "'$($template.Configuration[$param])'"
                    }
                    $exampleScript += "`n        # $param = $value"
                }

                $exampleScript += @"

    }
}

# Example commands for $ProviderType
Write-Host "Example usage for ${ProviderType}:" -ForegroundColor Cyan

"@

                # Add example commands
                foreach ($command in $template.ExampleCommands) {
                    if ($command.StartsWith('#')) {
                        $exampleScript += "`n$command"
                    } else {
                        $exampleScript += "`n# $command"
                    }
                }

                $exampleScript += @"


# Create a test vault
`$vaultName = "Test$ProviderType$(Get-Random -Maximum 9999)"
Write-Host "Creating test vault: `$vaultName" -ForegroundColor Green

try {
    `$result = Set-SecretInVault -VaultName `$vaultName -ProviderType '$ProviderType' -Configuration `$config -SecretData @{
        'test-secret' = 'test-value'
        'another-secret' = 'another-value'
    }
    
    if (`$result.Success) {
        Write-Host "✅ Vault created successfully!" -ForegroundColor Green
        Write-Host "Vault Name: `$vaultName" -ForegroundColor Gray
        
        # Test secret retrieval
        Write-Host "Testing secret retrieval..." -ForegroundColor Yellow
        `$retrievedSecrets = Get-SecretFromVault -VaultName `$vaultName
        Write-Host "Retrieved `$(`$retrievedSecrets.Count) secrets" -ForegroundColor Green
        
    } else {
        Write-Host "❌ Vault creation failed: `$(`$result.ErrorMessage)" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Error: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nExample completed. Check the generated files:" -ForegroundColor Cyan
Write-Host "- Configuration: $configFileName" -ForegroundColor Gray
Write-Host "- Example Script: $exampleFileName" -ForegroundColor Gray
"@
                
                $exampleScript | Out-File -FilePath $exampleFileName -Encoding UTF8
                Write-Information "Example script saved to: $exampleFileName" -InformationAction Continue
                
                # Add file paths to return object
                $template.GeneratedFiles = @{
                    ConfigurationFile = $configFileName
                    ExampleScript = $exampleFileName
                }
            }

            return $template
        }
        catch {
            Write-Error "Failed to generate configuration template: $($_.Exception.Message)"
            throw
        }
    }
}
