# SecretStoreManager

A comprehensive PowerShell module for managing secret vaults across multi##  Architecture

### Module Structure
```
SecretStoreManager/
├── SecretStoreManager.psd1         # Module manifest
├── SecretStoreManager.psm1         # Module loader
├── Public/                         # Exported functions
│   ├── New-TestSecretVault.ps1    # Main vault creation function
│   ├── Invoke-SecretStoreOrchestration.ps1
│   ├── Get-SecretFromVault.ps1
│   ├── Remove-SecretStoreVault.ps1
│   └── Test-SecretStorePrerequisite.ps1
├── Private/                        # Internal management functions
│   ├── New-VaultProvider.ps1      # Provider factory
│   ├── Get-VaultProvider.ps1      # Provider discovery
│   ├── Install-VaultProviderModule.ps1 # Module management
│   ├── Test-VaultProviderConfiguration.ps1 # Validation
│   ├── Get-VaultProviderRequirement.ps1 # Requirements
│   ├── New-VaultConfigurationTemplate.ps1 # Templates
│   ├── Test-VaultConnectivity.ps1 # Connection testing
│   ├── Test-VaultSecurity.ps1     # Security validation
│   └── Set-SecretInVault.ps1      # Secret storage helper
└── Classes/                        # Provider class hierarchy
    ├── BaseVaultProvider.ps1       # Abstract base class
    ├── SecretStoreProvider.ps1     # Local encrypted storage
    ├── CredManProvider.ps1         # Windows Credential Manager
    ├── AzureKeyVaultProvider.ps1   # Azure Key Vault
    └── AWSSecretsManagerProvider.ps1 # AWS Secrets Manager
```

### Provider Abstraction Pattern
The module uses object-oriented design with provider classes that inherit from a common base:

```powershell
# Base abstract class defines common interface
class BaseVaultProvider {
    [string] $ProviderType
    [hashtable] $Configuration
    
    # Abstract methods implemented by each provider
    [object] CreateVault([string] $VaultName, [hashtable] $Config)
    [bool] TestConnection([hashtable] $Config)
    [hashtable] GetRequiredModules()
}

# Each provider implements the interface
class SecretStoreProvider : BaseVaultProvider { ... }
class AzureKeyVaultProvider : BaseVaultProvider { ... }
class CredManProvider : BaseVaultProvider { ... }
class AWSSecretsManagerProvider : BaseVaultProvider { ... }
```

### Key Design Principles
- **Factory Pattern**: `New-VaultProvider` creates provider instances dynamically
- **Class Inheritance**: All providers inherit from `BaseVaultProvider`
- **Configuration-Driven**: Provider-specific settings via hashtables
- **Error Resilience**: Comprehensive try/catch with correlation IDs
- **Secure by Default**: No plaintext exposure in logs or output
- **Enterprise Ready**: Audit trails, validation, and compliance features
- **PowerShell Standards**: All functions follow approved verb-noun naming providers with enterprise-grade orchestration, testing, and security features.

##  Overview

SecretStoreManager transforms basic secret management into a robust, multi-provider solution that supports SecretStore, CredMan, AWS Secrets Manager, and Azure Key Vault. Built with enterprise requirements in mind, it provides automated testing, comprehensive error handling, and seamless provider switching.

##  Key Features

- ** Multi-Provider Support**: Unified interface for SecretStore, CredMan, AWS, and Azure
- ** Provider Abstraction**: Switch between vault providers without code changes
- ** Automated Orchestration**: End-to-end workflows for vault setup and secret management
- ** Comprehensive Testing**: Built-in test suites with real execution validation
- ** Auto-Installation**: Automatic detection and installation of required modules
- ** Enterprise Security**: Correlation tracking, secure handling, and audit trails
- ** PowerShell 5.1+ Compatible**: Works across Windows PowerShell and PowerShell Core

##  Quick Start

### Installation
```powershell
# Clone and import the module
git clone <repository-url>
Import-Module .\SecretStoreManager\SecretStoreManager.psd1
```

### Basic Usage
```powershell
# Create a vault and store secrets in one command
$secretData = @(
    @{ AccountName = "DatabaseAdmin"; Secret = "SecurePassword123!"; SecretType = "Credential" }
    @{ AccountName = "APIKey"; Secret = "api-key-12345"; SecretType = "String" }
)

# Orchestrate complete setup
Invoke-SecretStoreOrchestration -SecretData $secretData -VaultName "ProductionVault" -VaultProvider "SecretStore"

# Retrieve secrets securely
$secrets = Get-SecretFromVault -VaultName "ProductionVault" -SecretName "DatabaseAdmin*" -AsPlainText
```

### Multi-Provider Examples
```powershell
# Create different vault types using the class-based provider system
New-TestSecretVault -VaultName "LocalVault" -ProviderType "SecretStore"
New-TestSecretVault -VaultName "WindowsCredVault" -ProviderType "CredMan"  
New-TestSecretVault -VaultName "AWSVault" -ProviderType "AWSSecretsManager" -Configuration @{ AWSRegion = "us-east-1" }
New-TestSecretVault -VaultName "AzureVault" -ProviderType "AzureKeyVault" -Configuration @{ SubscriptionId = "your-sub-id"; KeyVaultName = "your-vault" }

# Same secrets, different providers - all use the same interface
$secretData = @(
    @{ AccountName = "DatabaseAdmin"; Secret = "SecurePassword123!"; SecretType = "Credential" }
    @{ AccountName = "APIKey"; Secret = "api-key-12345"; SecretType = "String" }
)

Invoke-SecretStoreOrchestration -SecretData $secretData -VaultName "LocalVault" -VaultProvider "SecretStore"
Invoke-SecretStoreOrchestration -SecretData $secretData -VaultName "AWSVault" -VaultProvider "AWSSecretsManager"
```

### Provider Class Usage
```powershell
# The provider factory creates the appropriate class instance
$provider = New-VaultProvider -ProviderType "SecretStore"
$vault = $provider.CreateVault("MyVault", @{})

# Each provider class implements the same interface
$awsProvider = New-VaultProvider -ProviderType "AWSSecretsManager"
$awsVault = $awsProvider.CreateVault("MyAWSVault", @{ AWSRegion = "us-east-1" })
```

##  Core Functions

### Public Functions
| Function | Purpose | Example |
|----------|---------|---------|
| **New-TestSecretVault** | Create/configure vaults | `New-TestSecretVault -VaultName "MyVault" -ProviderType "SecretStore"` |
| **Invoke-SecretStoreOrchestration** | End-to-end automation | `Invoke-SecretStoreOrchestration -SecretData $secrets -VaultName "MyVault"` |
| **Get-SecretFromVault** | Secure secret retrieval | `Get-SecretFromVault -VaultName "MyVault" -SecretName "ApiKey*"` |
| **Remove-SecretStoreVault** | Complete cleanup | `Remove-SecretStoreVault -VaultName "MyVault" -Force` |
| **Test-SecretStorePrerequisite** | Dependency management | `Test-SecretStorePrerequisite -InstallMissing` |

### Internal Management Functions
The module includes specialized management functions that handle provider-specific operations:

| Function | Purpose | Used By |
|----------|---------|---------|
| **New-VaultProvider** | Create provider instances | New-TestSecretVault |
| **Get-VaultProvider** | Discover available providers | New-TestSecretVault |
| **Install-VaultProviderModule** | Auto-install required modules | New-TestSecretVault |
| **Test-VaultProviderConfiguration** | Validate provider settings | New-TestSecretVault |
| **Get-VaultProviderRequirement** | Get provider metadata | New-TestSecretVault |
| **New-VaultConfigurationTemplate** | Generate config templates | Provider classes |
| **Test-VaultConnectivity** | Verify provider connections | Provider classes |
| **Test-VaultSecurity** | Security validation | Provider classes |

##  Testing

### Comprehensive Test Suite
```powershell
# Test all providers and functionality
.\Test-SecretStoreManager.ps1

# Test specific provider
.\Test-SecretStoreManager.ps1 -ProviderType SecretStore

# Keep test vaults for debugging
.\Test-SecretStoreManager.ps1 -SkipCleanup
```

The test suite validates:
- ✅ Module function exports
- ✅ Prerequisites and dependencies  
- ✅ Vault creation across all providers
- ✅ End-to-end orchestration workflows
- ✅ Secret storage and retrieval
- ✅ Complete cleanup and removal

##  Provider Support Matrix

| Provider | Status | Module Required | Notes |
|----------|---------|-----------------|-------|
| **SecretStore** | ✅ **Fully Supported** | Microsoft.PowerShell.SecretStore | Default, most reliable |
| **CredMan** | ✅ **Supported*** | SecretManagement.JustinGrote.CredMan | *Session limitations |
| **AWS Secrets Manager** | ⚙️ **Configured** | SecretsManagement.CAWSSecretsManager | Requires AWS credentials |
| **Azure Key Vault** | ✅ **Supported** | CredentialStore.AzureKeyVault | Azure cloud vault service |

##  Architecture

### Data-Driven Provider Configuration
The SecretStoreManager uses a **data-driven architecture** for managing vault providers, making it easy to add new providers or modify existing ones without changing code:

- **Configuration File**: `Configuration/VaultProviders.psd1` - Central repository of provider metadata, requirements, and examples
- **Provider Classes**: `Classes/*.ps1` - Implementation logic for each provider
- **Management Functions**: `Private/*.ps1` - Load provider data and handle validation, requirements, and template generation

### Adding New Providers
To add a new provider:
1. Add provider configuration to `VaultProviders.psd1`
2. Create provider class in `Classes/NewProviderName.ps1` 
3. Test using the comprehensive test suite

### Provider Abstraction Pattern
`
SecretStoreManager
├── VaultProviders.psd1 (Configuration data)
├── Provider Factory (Dynamic instantiation)
├── Base Provider Class (Common interface)
├── SecretStore Provider (Local encrypted storage)
├── CredMan Provider (Windows Credential Manager)
├── AWS Provider (AWS Secrets Manager)
└── Azure Provider (Azure Key Vault)
`

### Key Design Principles
- **Data-Driven**: Provider configuration loaded from VaultProviders.psd1
- **Factory Pattern**: Dynamic provider creation
- **Configuration-Driven**: Provider-specific settings
- **Error Resilience**: Comprehensive try/catch with correlation IDs
- **Secure by Default**: No plaintext exposure in logs
- **Enterprise Ready**: Audit trails and compliance features

##  Requirements

### Core Dependencies
- **PowerShell 5.1+** (Windows PowerShell or PowerShell Core)
- **Microsoft.PowerShell.SecretManagement** (auto-installed)
- **Microsoft.PowerShell.SecretStore** (auto-installed)

### Provider-Specific Modules
Auto-installed when using `-InstallMissingModules` parameter:
- SecretManagement.JustinGrote.CredMan (for CredMan)
- SecretsManagement.CAWSSecretsManager (for AWS)
- CredentialStore.AzureKeyVault (for Azure)

### Cloud Provider Requirements
- **AWS**: Valid AWS credentials and region configuration
- **Azure**: Azure authentication and Key Vault access

##  Configuration

### Data-Driven Provider Configuration
All provider settings are managed through `Configuration/VaultProviders.psd1`:

```powershell
# View all provider configurations
Import-PowerShellDataFile 'Configuration/VaultProviders.psd1'

# Get specific provider requirements
Get-VaultProviderRequirement -ProviderType 'AzureKeyVault'

# Generate configuration template
New-VaultConfigurationTemplate -ProviderType 'AzureKeyVault'
```

#### Provider Configuration Structure
```powershell
@{
    SecretStore = @{
        ModuleName = 'Microsoft.PowerShell.SecretStore'
        RequiredParameters = @()
        ExampleConfig = @{ Authentication = 'Password'; Interaction = 'None' }
        Description = 'Local encrypted vault using Microsoft SecretStore'
    }
    AzureKeyVault = @{
        ModuleName = 'CredentialStore.AzureKeyVault'
        RequiredParameters = @('SubscriptionId', 'VaultName')
        ExampleConfig = @{
            SubscriptionId = '12345678-1234-1234-1234-123456789abc'
            VaultName = 'MyKeyVault'
            AZKVaultName = 'MyKeyVault'
        }
        Description = 'Azure Key Vault integration'
    }
}
```

#### Adding New Providers
1. **Update Configuration**: Add provider metadata to `VaultProviders.psd1`
2. **Create Provider Class**: Implement provider logic in `Classes/YourProvider.ps1`
3. **Test Integration**: Use comprehensive test suite to validate functionality

##  Troubleshooting

### Common Issues
- **CredMan Session Errors**: Known limitation in certain environments (`ERROR_NO_SUCH_LOGON_SESSION`)
- **AWS Credential Issues**: Ensure AWS CLI or PowerShell credentials are configured properly
- **Azure Module Issues**: `CredentialStore.AzureKeyVault` module may have availability issues
- **Module Not Found**: Use `-InstallMissingModules` parameter for auto-installation
- **Provider Class Loading**: Ensure all files in `Classes/` folder are present and properly formatted

### Debugging
```powershell
# Enable verbose output for detailed provider operations
New-TestSecretVault -VaultName "DebugVault" -ProviderType "SecretStore" -Verbose

# Check which providers are available
Get-VaultProvider

# Test provider requirements
Get-VaultProviderRequirement -ProviderType "AWSSecretsManager"

# Validate provider configuration
Test-VaultProviderConfiguration -ProviderType "SecretStore" -Configuration @{}

# Use correlation IDs to trace issues across function calls
# All functions generate correlation IDs for end-to-end tracing
```

### Module Architecture Debugging
```powershell
# Check if all provider classes loaded correctly
Get-Command -Module SecretStoreManager | Where-Object { $_.Name -like "*Vault*" }

# Verify provider factory is working
$provider = New-VaultProvider -ProviderType "SecretStore"
$provider.GetType().Name  # Should show "SecretStoreProvider"

# Test class inheritance
$provider -is [BaseVaultProvider]  # Should return True
```

##  Production Usage

### Enterprise Deployment
```powershell
# Production vault with full orchestration
$secretData = Import-Csv "secrets-manifest.csv"
Invoke-SecretStoreOrchestration -SecretData $secretData -VaultName "Production" -VaultProvider "AWSSecretsManager"

# Automated secret rotation
$secretNames = @("DatabasePassword", "APIKey", "ServiceToken")
foreach ($secretName in $secretNames) {
    $newPassword = New-ComplexPassword
    Set-Secret -Name $secretName -Secret $newPassword -Vault "Production"
}
```

### CI/CD Integration
```powershell
# Automated testing in pipeline
$testResult = .\Test-SecretStoreManager.ps1
if ($LASTEXITCODE -ne 0) { 
    throw "Secret management tests failed"
}

# Deploy secrets to production vault
$prodSecrets = Get-Content "production-secrets.json" | ConvertFrom-Json
Invoke-SecretStoreOrchestration -SecretData $prodSecrets -VaultName "Production" -VaultProvider "AzureKeyVault"
```

##  Contributing

1. **Fork** the repository
2. **Create** a feature branch (git checkout -b feature/amazing-feature)
3. **Add tests** for new functionality in Test-SecretStoreManager.ps1
4. **Ensure** all tests pass (.\Test-SecretStoreManager.ps1)
5. **Commit** changes (git commit -m 'Add amazing feature')
6. **Push** to branch (git push origin feature/amazing-feature)
7. **Open** a Pull Request

##  License

This project is licensed under the **MIT License** - see the LICENSE file for details.

##  Support

### Getting Help
1. **Run Tests**: .\Test-SecretStoreManager.ps1 for validation
2. **Check Logs**: Look for correlation IDs in error messages
3. **Verify Prerequisites**: Use Test-SecretStorePrerequisite
4. **Review Provider Status**: Check the Provider Support Matrix above

### Reporting Issues
Include the following in bug reports:
- PowerShell version ($PSVersionTable)
- Provider type being used
- Full error message with correlation ID
- Steps to reproduce the issue

---

**🔐 Ready for Enterprise Secret Management** | Built with ❤️ for PowerShell Community

*Features object-oriented provider architecture, comprehensive testing, and enterprise-grade security controls.*
