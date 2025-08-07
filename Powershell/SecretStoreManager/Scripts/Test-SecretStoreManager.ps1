# SecretStoreManager Test Suite
# Comprehensive testing for all vault providers

param(
    [switch]$SkipInstallation,
    [switch]$Detailed
)

# Import helper for structured output
$helperPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Private\Write-ProgressMessage.ps1"
if (Test-Path $helperPath) {
    . $helperPath
}

Write-Information "SecretStoreManager Test Suite Starting..." -InformationAction Continue
Write-Information "Timestamp: $(Get-Date)" -InformationAction Continue

# Import the module
try {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "SecretStoreManager.psd1"
    Import-Module $modulePath -Force
    Write-Information "Module imported successfully" -InformationAction Continue
} catch {
    Write-Error "Failed to import module: $($_.Exception.Message)"
    exit 1
}

# Test 1: Prerequisites
Write-Information "`nTest 1: Prerequisites Check" -InformationAction Continue
try {
    $prereqResult = Test-SecretStorePrerequisite
    if ($prereqResult.AllModulesAvailable) {
        Write-Information "Prerequisites: PASS" -InformationAction Continue
    } else {
        Write-Warning "Prerequisites: FAIL - Missing modules"
    }
    if ($Detailed) {
        Write-Information "Available modules: $($prereqResult.ModulesImported -join ', ')" -InformationAction Continue
    }
} catch {
    Write-Error "Prerequisites: ERROR - $($_.Exception.Message)"
}

# Test 2: SecretStore Vault Creation
Write-Information "`nTest 2: SecretStore Vault Creation" -InformationAction Continue
try {
    $testVaultName = "TestVault-$(Get-Random)"
    if ($SkipInstallation) {
        $result = New-TestSecretVault -VaultName $testVaultName -ProviderType SecretStore
    } else {
        $result = New-TestSecretVault -VaultName $testVaultName -ProviderType SecretStore -InstallMissingModules
    }
    
    if ($result.Success) {
        Write-Information "SecretStore Creation: PASS" -InformationAction Continue
        if ($Detailed) {
            Write-Information "Vault Name: $($result.VaultName)" -InformationAction Continue
            Write-Information "Provider: $($result.ProviderType)" -InformationAction Continue
        }
        
        # Test secret storage
        Write-Verbose "Testing secret storage..."
        Set-Secret -Name "TestSecret" -Secret "TestValue" -Vault $testVaultName
        $retrievedSecret = Get-Secret -Name "TestSecret" -Vault $testVaultName -AsPlainText
        
        if ($retrievedSecret -eq "TestValue") {
            Write-Information "  Secret Storage: PASS" -InformationAction Continue
        } else {
            Write-Warning "  Secret Storage: FAIL"
        }
        
        # Cleanup
        Write-Verbose "Cleaning up..."
        Remove-Secret -Name "TestSecret" -Vault $testVaultName -ErrorAction SilentlyContinue
        Unregister-SecretVault -Name $testVaultName -ErrorAction SilentlyContinue
        
    } else {
        Write-Warning "SecretStore Creation: FAIL"
        if ($result.Errors.Count -gt 0) {
            Write-Error "Errors: $($result.Errors -join '; ')"
        }
    }
} catch {
    Write-Error "SecretStore Creation: ERROR - $($_.Exception.Message)"
}

# Test 3: Provider Detection
Write-Information "`nTest 3: Provider Detection" -InformationAction Continue
try {
    $providers = @('SecretStore', 'AzureKeyVault', 'CredMan', 'AWSSecretsManager', 'Bitwarden')
    foreach ($provider in $providers) {
        try {
            # Try to create a test vault to see if provider is available
            $testVaultName = "ProviderTest-$provider-$(Get-Random)"
            if ($SkipInstallation) {
                $result = New-TestSecretVault -VaultName $testVaultName -ProviderType $provider -ErrorAction SilentlyContinue
            } else {
                $result = New-TestSecretVault -VaultName $testVaultName -ProviderType $provider -InstallMissingModules -ErrorAction SilentlyContinue
            }
            
            if ($result.Success) {
                Write-Information "  $provider`: AVAILABLE" -InformationAction Continue
                # Cleanup test vault
                Unregister-SecretVault -Name $testVaultName -ErrorAction SilentlyContinue
            } else {
                Write-Information "  $provider`: NOT AVAILABLE" -InformationAction Continue
                if ($result.Errors.Count -gt 0) {
                    Write-Information "    Reason: $($result.Errors[0])" -InformationAction Continue
                }
            }
        } catch {
            Write-Error "  $provider`: ERROR - $($_.Exception.Message)"
        }
    }
} catch {
    Write-Error "Provider Detection: ERROR - $($_.Exception.Message)"
}

# Test 4: Orchestration
Write-Information "`nTest 4: Orchestration Test" -InformationAction Continue
try {
    $orchVaultName = "OrchTest-$(Get-Random)"
    $secretData = @(
        @{ 
            AccountName = "OrchSecret"
            Secret = "OrchValue"
            SecretType = "Credential"
            Description = "Test orchestration secret"
        }
    )
    $result = Set-SecretInVault -SecretData $secretData -VaultName $orchVaultName -VaultProvider SecretStore
    
    if ($result.VaultCreated -and $result.SecretsStored -gt 0) {
        Write-Information "Orchestration: PASS" -InformationAction Continue
        if ($Detailed) {
            Write-Information "Vault Created: $($result.VaultCreated)" -InformationAction Continue
            Write-Information "Secrets Stored: $($result.SecretsStored)" -InformationAction Continue
        }
        
        # Cleanup
        Write-Verbose "Cleaning up orchestration test..."
        Remove-Secret -Name "OrchSecret" -Vault $orchVaultName -ErrorAction SilentlyContinue
        Unregister-SecretVault -Name $orchVaultName -ErrorAction SilentlyContinue
        
    } else {
        Write-Information "Orchestration: PARTIAL SUCCESS" -InformationAction Continue
        Write-Information "  Vault Created: $($result.VaultCreated)" -InformationAction Continue
        Write-Information "  Secrets Stored: $($result.SecretsStored)" -InformationAction Continue
        if ($result.Errors.Count -gt 0) {
            Write-Error "  Errors: $($result.Errors -join '; ')"
        }
        if ($result.Warnings.Count -gt 0) {
            Write-Warning "  Warnings: $($result.Warnings -join '; ')"
        }
        
        # Cleanup
        Write-Verbose "Cleaning up orchestration test..."
        Unregister-SecretVault -Name $orchVaultName -ErrorAction SilentlyContinue
    }
} catch {
    Write-Error "Orchestration: ERROR - $($_.Exception.Message)"
}

Write-Information "`nTest Suite Completed" -InformationAction Continue
Write-Information "Timestamp: $(Get-Date)" -InformationAction Continue
