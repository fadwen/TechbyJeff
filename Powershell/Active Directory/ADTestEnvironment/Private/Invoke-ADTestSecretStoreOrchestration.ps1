function Invoke-ADTestSecretStoreOrchestration {
    <#
    .SYNOPSIS
        Orchestrates SecretStore vault creation and password storage for AD test environment

    .DESCRIPTION
        Handles all SecretStore operations including:
        - Prerequisites verification
        - Vault creation and configuration
        - Password storage in SecretStore
        
        This function separates SecretStore orchestration from service account creation
        to maintain single responsibility principle.

    .PARAMETER PasswordData
        Array of password objects to store in the vault.
        Expected format: @{ AccountName = "name"; Password = "password" }

    .PARAMETER VaultName
        Name of the secret vault to create/use. Defaults to "ADTestEnvironment"

    .PARAMETER VaultPassword
        Password for the secret vault. If not provided, uses default password.

    .PARAMETER GlobalVault
        Create vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges.

    .PARAMETER CorrelationId
        Correlation ID for tracking related operations

    .EXAMPLE
        Invoke-ADTestSecretStoreOrchestration -PasswordData $passwords -VaultName "TestVault"
        Creates vault and stores passwords

    .EXAMPLE
        Invoke-ADTestSecretStoreOrchestration -PasswordData $passwords -GlobalVault
        Creates global vault and stores passwords

    .OUTPUTS
        PSCustomObject containing orchestration results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - Validates SecretStore prerequisites before proceeding
        - Creates vault with appropriate scope and security
        - Stores passwords securely using SecretStore APIs
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$PasswordData,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [Parameter()]
        [System.Security.SecureString]$VaultPassword,
        
        [Parameter()]
        [switch]$GlobalVault,
        
        [Parameter()]
        [ValidateNotNull()]
        [System.Guid]$CorrelationId = [System.Guid]::NewGuid()
    )

    begin {
        Write-Verbose "Starting Invoke-ADTestSecretStoreOrchestration - CorrelationId: $CorrelationId"
        
        $result = @{
            CorrelationId = $CorrelationId
            VaultName = $VaultName
            VaultCreated = $false
            VaultConfigured = $false
            PasswordsStored = 0
            TotalPasswords = $PasswordData.Count
            Errors = @()
            Warnings = @()
            VaultResult = $null
            SecretResult = $null
        }
    }

    process {
        try {
            # Step 1: Verify SecretStore prerequisites
            Write-Verbose "Verifying SecretStore prerequisites..."
            $prereqResult = Test-SecretStorePrerequisite
            if (-not $prereqResult.AllModulesAvailable) {
                throw "SecretStore prerequisites not satisfied: $($prereqResult.Errors -join '; ')"
            }
            Write-Verbose "SecretStore prerequisites verified successfully"
            
            # Step 2: Create/configure vault
            Write-Verbose "Creating/configuring SecretStore vault: $VaultName"
            $vaultParams = @{ 
                VaultName = $VaultName
                UseDefaultPassword = $true  # Always use default if no password provided
                GlobalVault = $GlobalVault
            }
            
            if ($VaultPassword) { 
                $vaultParams.VaultPassword = $VaultPassword 
                $vaultParams.UseDefaultPassword = $false  # Don't use default when password is provided
            }
            
            $vaultResult = New-ADTestSecretVault @vaultParams
            $result.VaultResult = $vaultResult
            
            if ($vaultResult.Errors.Count -gt 0) {
                throw "Failed to create/configure vault: $($vaultResult.Errors -join '; ')"
            }
            
            $result.VaultCreated = $vaultResult.VaultCreated
            $result.VaultConfigured = $vaultResult.VaultConfigured
            Write-Verbose "Vault operation completed successfully"
            
            # Step 3: Store passwords in vault
            Write-Verbose "Storing $($PasswordData.Count) passwords in SecretStore vault..."
            $secretResult = Set-ADTestPasswordSecret -PasswordData $PasswordData -VaultName $VaultName -CorrelationId $CorrelationId
            $result.SecretResult = $secretResult
            
            if ($secretResult.Errors.Count -gt 0) {
                throw "Failed to store passwords in vault: $($secretResult.Errors -join '; ')"
            }
            
            $result.PasswordsStored = $secretResult.TotalStored
            Write-Verbose "Successfully stored $($secretResult.TotalStored) passwords in vault"
            
            # Collect any warnings from sub-operations
            if ($vaultResult.Warnings.Count -gt 0) {
                $result.Warnings += $vaultResult.Warnings
            }
            if ($secretResult.Warnings.Count -gt 0) {
                $result.Warnings += $secretResult.Warnings
            }
            
        }
        catch {
            $errorMsg = "SecretStore orchestration failed: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
    }

    end {
        Write-Verbose "Completed Invoke-ADTestSecretStoreOrchestration - CorrelationId: $CorrelationId"
        return [PSCustomObject]$result
    }
}
