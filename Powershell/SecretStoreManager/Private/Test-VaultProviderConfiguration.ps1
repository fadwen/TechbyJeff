# Vault Provider Configuration Validation Functions
# Validates provider configurations and requirements

# Vault Provider Configuration Validation Functions
# Validates provider configurations and requirements

function Test-VaultProviderConfiguration {
    <#
    .SYNOPSIS
        Validates the configuration for a vault provider
        
    .DESCRIPTION
        Checks that all required parameters are provided and validates
        provider-specific configuration requirements.
        Loads validation rules from VaultProviders.psd1 for maintainability.
        
    .PARAMETER ProviderType
        The type of vault provider to validate
        
    .PARAMETER Configuration
        The configuration hashtable to validate
        
    .EXAMPLE
        $config = @{ AzureVaultName = 'MyVault'; SubscriptionId = '12345...' }
        $result = Test-VaultProviderConfiguration -ProviderType 'AzureKeyVault' -Configuration $config
        
    .NOTES
        Returns a detailed validation result with errors and warnings.
        Uses data-driven validation from VaultProviders.psd1.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderType,
        
        [Parameter()]
        [hashtable]$Configuration = @{}
    )

    $validationResult = @{
        IsValid = $false
        RequiredParameters = @()
        MissingParameters = @()
        Errors = @()
        Warnings = @()
    }

    try {
        # Load provider requirements from configuration
        $requirements = Get-VaultProviderRequirement -ProviderType $ProviderType
        $validationResult.RequiredParameters = $requirements.RequiredParameters
        
        # Check if provider module is available
        $provider = New-VaultProvider -ProviderType $ProviderType
        if (-not $provider.IsAvailable) {
            $validationResult.Errors += "Provider module '$($requirements.ModuleName)' is not available"
            return $validationResult
        }

        # Check required parameters
        foreach ($param in $requirements.RequiredParameters) {
            if (-not $Configuration.ContainsKey($param) -or [string]::IsNullOrWhiteSpace($Configuration[$param])) {
                $validationResult.MissingParameters += $param
            }
        }
        
        # Platform support validation
        if ($requirements.PlatformSupport -and $requirements.PlatformSupport.Count -gt 0) {
            $currentPlatform = if ($PSVersionTable.Platform) { 
                switch ($PSVersionTable.Platform) {
                    'Win32NT' { 'Windows' }
                    'Unix' { if ($IsLinux) { 'Linux' } else { 'macOS' } }
                    default { $PSVersionTable.Platform }
                }
            } else { 'Windows' }
            
            if ($currentPlatform -notin $requirements.PlatformSupport) {
                $validationResult.Errors += "Provider '$ProviderType' is not supported on platform '$currentPlatform'. Supported platforms: $($requirements.PlatformSupport -join ', ')"
                return $validationResult
            }
        }

        # Provider-specific validation (enhanced with data-driven approach)
        if ($validationResult.MissingParameters.Count -eq 0) {
            $validationResult.IsValid = $true
            
            # Add provider-specific authentication checks
            switch ($ProviderType) {
                'AzureKeyVault' {
                    try {
                        $context = Get-AzContext -ErrorAction SilentlyContinue
                        if (-not $context) {
                            $validationResult.Warnings += "Azure context not found. Run 'Connect-AzAccount' to authenticate."
                        }
                    }
                    catch {
                        $validationResult.Warnings += "Azure PowerShell module not available. Install Az.Accounts module for Azure authentication."
                    }
                }
                'AWSSecretsManager' {
                    try {
                        $awsCredentials = Get-AWSCredential -ErrorAction SilentlyContinue
                        if (-not $awsCredentials) {
                            $validationResult.Warnings += "AWS credentials not configured. Set up AWS credentials or profile."
                        }
                    }
                    catch {
                        $validationResult.Warnings += "AWS PowerShell module not available for credential validation."
                    }
                }
            }
        }
    }
    catch {
        $validationResult.Errors += $_.Exception.Message
    }

    return $validationResult
}
