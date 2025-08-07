#
# Module manifest for module 'SecretStoreManager'
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'SecretStoreManager.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'Jeffrey Stuhr'

    # Company or vendor of this module
    CompanyName = 'Unknown'

    # Copyright statement for this module
    Copyright = '(c) Jeffrey Stuhr. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for managing multiple secret vault providers including Microsoft SecretStore, Azure Key Vault, Windows Credential Manager, and AWS Secrets Manager with enhanced security, automation, and error handling capabilities.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{
            ModuleName = 'Microsoft.PowerShell.SecretManagement'
            ModuleVersion = '1.1.0'
        },
        @{
            ModuleName = 'Microsoft.PowerShell.SecretStore'
            ModuleVersion = '1.0.0'
        }
    )

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Test-SecretStorePrerequisite',
        'New-TestSecretVault',
        'New-VaultConfigurationTemplate',
        'Remove-SecretStoreVault',
        'Get-SecretFromVault',
        'Set-SecretInVault'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('SecretStore', 'SecretManagement', 'Security', 'Automation', 'Vault', 'Credentials', 'PowerShell', 'AzureKeyVault', 'CredMan', 'AWS', 'SecretsManager', 'MultiVault')

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            # ProjectUri = ''

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
# SecretStoreManager v1.0.0

## Features
- Multi-vault provider support (SecretStore, Azure Key Vault, CredMan, AWS Secrets Manager)
- Configuration-driven vault provider management
- Automated prerequisite checking and module installation for all providers
- Secure secret storage and retrieval with expiration support
- Enhanced error handling and retry logic
- Support for both user and global vault scopes
- Orchestration capabilities for bulk operations
- Extensive logging and correlation tracking
- Provider-specific configuration and testing

## Functions
- Test-SecretStorePrerequisite: Verify and install required modules
- New-TestSecretVault: Create and configure vaults with any supported provider
- Remove-SecretStoreVault: Safely remove vaults and secrets
- Get-SecretFromVault: Retrieve secrets with filtering and metadata
- Set-SecretInVault: Store multiple secrets with automatic vault creation
- Get-VaultProvider: Retrieve vault provider information
- Install-VaultProvider: Install vault provider modules
- Register-VaultProvider: Register vault providers with SecretManagement
- Test-VaultProvider: Test vault provider functionality

## Supported Vault Providers
- Microsoft.PowerShell.SecretStore: Local encrypted storage
- CredentialStore.AzureKeyVault: Azure Key Vault integration
- SecretManagement.JustinGrote.CredMan: Windows Credential Manager
- CAWSSecretsManager: AWS Secrets Manager integration

## Security Features
- Configurable authentication modes for all providers
- Automatic expiration date handling
- Secure string and plaintext options
- Comprehensive audit logging
- Protection against expired credential usage
- Provider-specific security configurations
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
