function New-ADTestSecretVault {
    <#
    .SYNOPSIS
        Creates or configures a SecretStore vault for AD test environment passwords

    .DESCRIPTION
        Creates a computer-level SecretStore vault for storing AD test environment passwords.
        Configures the vault with appropriate security settings and access controls.
        
        The SecretStore itself is configured with no authentication for ease of automation,
        but individual vaults are password-protected for security.

    .PARAMETER VaultName
        Name of the secret vault to create. Defaults to "ADTestEnvironment"

    .PARAMETER VaultPassword
        Password for the secret vault. If not provided, defaults to "ADTestEnvironmentPassword"

    .PARAMETER UseDefaultPassword
        Use the default password "ADTestEnvironmentPassword" instead of prompting. Defaults to $true for automation.

    .PARAMETER Force
        Force recreation of the vault if it already exists

    .PARAMETER AllowPlaintextVault
        Allow creation of a vault without password protection (less secure, for testing only)

    .PARAMETER GlobalVault
        Create vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges for optimal security.

    .EXAMPLE
        New-ADTestSecretVault
        Creates the default ADTestEnvironment vault with default password "ADTestEnvironmentPassword"

    .EXAMPLE
        New-ADTestSecretVault -UseDefaultPassword:$false
        Creates the vault but prompts for password instead of using default

    .EXAMPLE
        New-ADTestSecretVault -VaultName "ProdVault" -VaultPassword $securePass
        Creates a custom named vault with specified password

    .EXAMPLE
        New-ADTestSecretVault -Force
        Recreates the vault even if it already exists

    .EXAMPLE
        New-ADTestSecretVault -GlobalVault
        Creates a global vault (AllUsers scope) - requires admin privileges

    .OUTPUTS
        PSCustomObject containing vault creation results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - SecretStore is configured with no authentication for automation ease
        - Individual vaults are password-protected using Windows Data Protection API
        - Vault is created at computer level for shared access when running as admin
        - Requires administrative privileges for optimal security
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [Parameter()]
        [System.Security.SecureString]$VaultPassword,
        
        [Parameter()]
        [bool]$UseDefaultPassword = $true,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AllowPlaintextVault,
        
        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestSecretVault - CorrelationId: $correlationId"
        
        $result = @{
            CorrelationId = $correlationId
            VaultName = $VaultName
            VaultCreated = $false
            VaultExists = $false
            VaultConfigured = $false
            IsDefault = $false
            Errors = @()
            Warnings = @()
        }
        
        # Ensure SecretStore modules are available
        try {
            Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop
            Import-Module Microsoft.PowerShell.SecretStore -Force -ErrorAction Stop
            Write-Verbose "SecretStore modules imported successfully"
        }
        catch {
            throw "SecretStore modules not available. Run Test-SecretStorePrerequisite first. Error: $($_.Exception.Message)"
        }
        
        # Ensure SecretStore is configured - always use no authentication for the store
        $storeConfigured = $false
        $needsConfiguration = $false
        
        try {
            # Try to get configuration to see if SecretStore is set up
            $storeConfig = Get-SecretStoreConfiguration -ErrorAction Stop
            
            # Check if store is accessible 
            try {
                Get-SecretVault -ErrorAction Stop | Out-Null
                Write-Verbose "SecretStore is configured and accessible"
                $storeConfigured = $true
                
                # Check if it's already configured with no authentication (our preferred setup)
                if ($storeConfig.Authentication -ne 'None') {
                    Write-Verbose "SecretStore is configured but uses authentication - will reconfigure to no authentication"
                    $needsConfiguration = $true
                }
            }
            catch {
                Write-Verbose "SecretStore configured but not accessible: $($_.Exception.Message)"
                $needsConfiguration = $true
            }
        }
        catch {
            Write-Verbose "SecretStore not configured: $($_.Exception.Message)"
            $needsConfiguration = $true
        }
        
        # Configure SecretStore if needed - use no authentication for the store itself
        if ($needsConfiguration -or -not $storeConfigured) {
            try {
                Write-Verbose "Configuring SecretStore with no authentication (passwordless)..."
                Set-SecretStoreConfiguration -Authentication None -Interaction None -Scope CurrentUser -Confirm:$false -ErrorAction Stop
                Write-Verbose "Configured SecretStore with no authentication - individual vaults can still be password protected"
                $storeConfigured = $true
            }
            catch {
                $result.Warnings += "Could not configure SecretStore automatically: $($_.Exception.Message). May prompt for password during vault creation."
                Write-Warning "Could not configure SecretStore automatically: $($_.Exception.Message). May prompt for password during vault creation."
            }
        }
    }

    process {
        try {
            # Check if vault already exists
            $existingVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
            
            if ($existingVault) {
                $result.VaultExists = $true
                Write-Verbose "Vault '$VaultName' already exists"
                
                if (-not $Force) {
                    Write-Verbose "Vault exists and Force not specified - skipping creation"
                    $result.VaultConfigured = $true
                    $result.Warnings += "Vault '$VaultName' already exists. Use -Force to recreate."
                    return [PSCustomObject]$result
                }
                else {
                    Write-Verbose "Force specified - removing existing vault"
                    try {
                        Unregister-SecretVault -Name $VaultName -ErrorAction Stop
                        Write-Verbose "Successfully removed existing vault: $VaultName"
                    }
                    catch {
                        $errorMsg = "Failed to remove existing vault '$VaultName': $($_.Exception.Message)"
                        $result.Errors += $errorMsg
                        throw $errorMsg
                    }
                }
            }
            
            # Prepare vault parameters - always use password for vault even though store has none
            $vaultParams = @{}
            
            if ($VaultPassword) {
                # Use provided password
                $vaultParams.Password = $VaultPassword
                Write-Verbose "Using provided vault password"
            }
            elseif ($UseDefaultPassword) {
                # Use default password for the vault
                $defaultPassword = ConvertTo-SecureString -String "ADTestEnvironmentPassword" -AsPlainText -Force
                $vaultParams.Password = $defaultPassword
                Write-Verbose "Using default vault password: ADTestEnvironmentPassword"
            }
            elseif ($AllowPlaintextVault) {
                # Create vault without password (less secure)
                $vaultParams.Authentication = 'None'
                $result.Warnings += "Vault created without password protection (less secure)"
                Write-Warning "Creating vault without password protection - this is less secure"
            }
            else {
                # Default to using our standard password if nothing specified
                $defaultPassword = ConvertTo-SecureString -String "ADTestEnvironmentPassword" -AsPlainText -Force
                $vaultParams.Password = $defaultPassword
                Write-Verbose "No password specified - using default vault password: ADTestEnvironmentPassword"
            }
            
            # Configure vault scope based on GlobalVault parameter
            if ($GlobalVault) {
                # Check if running as administrator for global vault
                $isAdmin = $false
                try {
                    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                }
                catch {
                    Write-Verbose "Could not determine admin status: $($_.Exception.Message)"
                }
                
                if ($isAdmin) {
                    Write-Verbose "Creating global vault (AllUsers scope) - running as administrator"
                    $vaultParams.Scope = 'AllUsers'
                }
                else {
                    Write-Warning "GlobalVault requested but not running as administrator - using CurrentUser scope instead"
                    $vaultParams.Scope = 'CurrentUser'
                    $result.Warnings += "GlobalVault requested but not running as administrator - vault created for current user only"
                }
            }
            else {
                Write-Verbose "Creating user-specific vault (CurrentUser scope)"
                $vaultParams.Scope = 'CurrentUser'
            }
            
            # Create the vault
            Write-Verbose "Creating SecretStore vault: $VaultName"
            try {
                if ($vaultParams.Count -gt 0) {
                    Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -VaultParameters $vaultParams -ErrorAction Stop
                }
                else {
                    Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -ErrorAction Stop
                }
                
                $result.VaultCreated = $true
                $result.VaultConfigured = $true
                Write-Verbose "Successfully created SecretStore vault: $VaultName"
            }
            catch {
                $errorMsg = "Failed to create SecretStore vault '$VaultName': $($_.Exception.Message)"
                $result.Errors += $errorMsg
                throw $errorMsg
            }
            
            # Verify vault creation
            $newVault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
            if ($newVault) {
                Write-Verbose "Vault creation verified successfully"
                
                # Check if this is the default vault
                $defaultVault = Get-SecretVault | Where-Object { $_.IsDefault -eq $true }
                if (-not $defaultVault -or $defaultVault.Name -eq $VaultName) {
                    try {
                        Set-SecretVaultDefault -Name $VaultName -ErrorAction Stop
                        $result.IsDefault = $true
                        Write-Verbose "Set '$VaultName' as default secret vault"
                    }
                    catch {
                        $result.Warnings += "Failed to set as default vault: $($_.Exception.Message)"
                        Write-Warning "Failed to set '$VaultName' as default vault: $($_.Exception.Message)"
                    }
                }
            }
            else {
                $errorMsg = "Vault creation succeeded but vault verification failed"
                $result.Errors += $errorMsg
                throw $errorMsg
            }
            
        }
        catch {
            $errorMsg = "Failed to create AD test secret vault: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestSecretVault - CorrelationId: $correlationId"
        return [PSCustomObject]$result
    }
}
