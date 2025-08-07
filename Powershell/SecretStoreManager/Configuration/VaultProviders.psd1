# Vault Provider Configuration
# This file defines the available vault providers and their requirements

@{
    Providers = @{
        SecretStore = @{
            ModuleName = 'Microsoft.PowerShell.SecretStore'
            RequiredModules = @('Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore')
            OptionalModules = @()
            RequiredParameters = @()
            OptionalParameters = @('Authentication', 'PasswordTimeout', 'Interaction')
            PlatformSupport = @('Windows', 'Linux', 'macOS')
            AuthenticationMethods = @('None', 'Password')
            Description = 'Local encrypted storage for secrets, ideal for development and testing'
            ExampleConfiguration = @{}
            ExampleCommands = @(
                "# SecretStore works out of the box:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType 'SecretStore'"
            )
        }
        
        AzureKeyVault = @{
            ModuleName = 'CredentialStore.AzureKeyVault'
            RequiredModules = @('Microsoft.PowerShell.SecretManagement', 'CredentialStore.AzureKeyVault')
            OptionalModules = @('Az.Accounts', 'Az.KeyVault')
            RequiredParameters = @('AzureVaultName', 'SubscriptionId')
            OptionalParameters = @('TenantId', 'ResourceGroupName')
            PlatformSupport = @('Windows', 'Linux', 'macOS')
            AuthenticationMethods = @('Azure Service Principal', 'Azure Managed Identity', 'Azure CLI', 'Interactive')
            Description = 'Azure cloud-based key vault for enterprise secret management'
            ExampleConfiguration = @{
                AzureVaultName = "my-keyvault-name"
                SubscriptionId = "12345678-1234-1234-1234-123456789012"
            }
            ExampleCommands = @(
                "# Connect to Azure first:",
                "Connect-AzAccount",
                "# Create vault with this configuration:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType 'AzureKeyVault' -Configuration `$config"
            )
        }
        
        CredMan = @{
            ModuleName = 'SecretManagement.JustinGrote.CredMan'
            RequiredModules = @('Microsoft.PowerShell.SecretManagement', 'SecretManagement.JustinGrote.CredMan')
            OptionalModules = @()
            RequiredParameters = @()
            OptionalParameters = @()
            PlatformSupport = @('Windows')
            AuthenticationMethods = @('Windows Authentication')
            Description = 'Windows Credential Manager integration for local credential storage'
            ExampleConfiguration = @{}
            ExampleCommands = @(
                "# CredMan works out of the box on Windows:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType 'CredMan'"
            )
        }
        
        AWSSecretsManager = @{
            ModuleName = 'SecretsManagement.CAWSSecretsManager'
            RequiredModules = @('Microsoft.PowerShell.SecretManagement', 'SecretsManagement.CAWSSecretsManager')
            OptionalModules = @('AWS.Tools.Common', 'AWS.Tools.SecretsManager')
            RequiredParameters = @('AWSRegion')
            OptionalParameters = @('AWSProfile', 'AccessKey', 'SecretKey', 'SessionToken')
            PlatformSupport = @('Windows', 'Linux', 'macOS')
            AuthenticationMethods = @('AWS Credentials File', 'Environment Variables', 'IAM Roles', 'AWS SSO')
            Description = 'AWS cloud-based secrets manager for scalable secret management'
            ExampleConfiguration = @{
                AWSRegion = "us-east-1"
                AWSProfile = "default"
            }
            ExampleCommands = @(
                "# Configure AWS credentials first:",
                "Set-AWSCredential -AccessKey 'AKIA...' -SecretKey 'xyz...' -StoreAs 'default'",
                "# Create vault with this configuration:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType 'AWSSecretsManager' -Configuration `$config"
            )
        }
        
        Bitwarden = @{
            ModuleName = 'SecretManagement.Warden'
            RequiredModules = @('Microsoft.PowerShell.SecretManagement', 'SecretManagement.Warden')
            OptionalModules = @()
            RequiredParameters = @()
            OptionalParameters = @('ServerURL', 'Email', 'OrganizationId')
            PlatformSupport = @('Windows', 'Linux', 'macOS')
            AuthenticationMethods = @('Master Password', 'API Key', 'Session Token')
            Description = 'Bitwarden password manager integration for personal and business secret management'
            Prerequisites = @('Bitwarden CLI (bw) must be installed and available in PATH')
            ExampleConfiguration = @{
                ServerURL = "https://vault.bitwarden.com"
                Email = "user@example.com"
            }
            ExampleCommands = @(
                "# Install Bitwarden CLI first (if not already installed):",
                "# Download from: https://bitwarden.com/help/cli/",
                "# Login to Bitwarden:",
                "bw login user@example.com",
                "# Create vault with this configuration:",
                "Set-SecretInVault -VaultName 'MyTestVault' -ProviderType 'Bitwarden' -Configuration `$config"
            )
        }
    }
}
