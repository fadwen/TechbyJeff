function Set-ADTestPasswordSecret {
    <#
    .SYNOPSIS
        Stores AD test environment passwords in a SecretStore vault

    .DESCRIPTION
        Takes password data and stores it securely in a specified SecretStore vault.
        Each password is stored as a SecureString with associated metadata.

    .PARAMETER PasswordData
        Array of objects containing password information to store.
        Each object should have: ServiceAccountName, Password, CreatedDate

    .PARAMETER VaultName
        Name of the secret vault to store passwords in. Defaults to "ADTestEnvironment"

    .PARAMETER CorrelationId
        Correlation ID for tracking related operations

    .PARAMETER OverwriteExisting
        Overwrite existing secrets with the same name

    .PARAMETER SecretNamePrefix
        Prefix for secret names. Defaults to service account name

    .EXAMPLE
        $passwordData = @(
            @{ ServiceAccountName = 'svc-app1'; Password = 'SecurePass123!'; CreatedDate = Get-Date }
        )
        Set-ADTestPasswordSecret -PasswordData $passwordData

        Stores passwords in the default ADTestEnvironment vault

    .EXAMPLE
        Set-ADTestPasswordSecret -PasswordData $passwords -VaultName "ProdVault" -OverwriteExisting

        Stores passwords in a custom vault, overwriting any existing secrets

    .OUTPUTS
        PSCustomObject containing storage operation results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Secret Naming Convention:
        - Format: {ServiceAccountName}-{Timestamp}
        - Timestamp: yyyyMMdd-HHmmss
        - Ensures unique secret names and version tracking
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [array]$PasswordData,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [Parameter()]
        [System.Guid]$CorrelationId = [System.Guid]::NewGuid(),
        
        [Parameter()]
        [switch]$OverwriteExisting,
        
        [Parameter()]
        [string]$SecretNamePrefix
    )

    begin {
        Write-Verbose "Starting Set-ADTestPasswordSecret - CorrelationId: $CorrelationId"
        
        $result = @{
            CorrelationId = $CorrelationId
            VaultName = $VaultName
            TotalPasswords = $PasswordData.Count
            StoredSecrets = @()
            SkippedSecrets = @()
            FailedSecrets = @()
            Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            Errors = @()
            Warnings = @()
        }
        
        # Ensure SecretManagement module is available
        try {
            Import-Module Microsoft.PowerShell.SecretManagement -Force -ErrorAction Stop
            Write-Verbose "SecretManagement module imported successfully"
        }
        catch {
            throw "SecretManagement module not available. Run Test-SecretStorePrerequisite first. Error: $($_.Exception.Message)"
        }
        
        # Verify vault exists
        $vault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
        if (-not $vault) {
            throw "SecretStore vault '$VaultName' not found. Create it first using New-ADTestSecretVault."
        }
        
        Write-Verbose "Using vault: $VaultName"
    }

    process {
        try {
            Write-Verbose "Processing $($PasswordData.Count) password entries"
            
            foreach ($entry in $PasswordData) {
                $secretResult = @{
                    ServiceAccount = $null
                    SecretName = $null
                    Success = $false
                    Error = $null
                    Skipped = $false
                    SkipReason = $null
                }
                
                try {
                    # Validate required properties
                    if (-not $entry.ServiceAccountName) {
                        $secretResult.SkipReason = "Missing ServiceAccountName"
                        $secretResult.Skipped = $true
                        $result.SkippedSecrets += [PSCustomObject]$secretResult
                        $result.Warnings += "Skipping entry with missing ServiceAccountName"
                        Write-Warning "Skipping entry with missing ServiceAccountName"
                        continue
                    }
                    
                    if (-not $entry.Password) {
                        $secretResult.ServiceAccount = $entry.ServiceAccountName
                        $secretResult.SkipReason = "Missing Password"
                        $secretResult.Skipped = $true
                        $result.SkippedSecrets += [PSCustomObject]$secretResult
                        $result.Warnings += "Skipping entry with missing Password for account: $($entry.ServiceAccountName)"
                        Write-Warning "Skipping entry with missing Password for account: $($entry.ServiceAccountName)"
                        continue
                    }
                    
                    $secretResult.ServiceAccount = $entry.ServiceAccountName
                    
                    # Create secret name
                    if ($SecretNamePrefix) {
                        $secretName = "$SecretNamePrefix-$($entry.ServiceAccountName)-$($result.Timestamp)"
                    }
                    else {
                        $secretName = "$($entry.ServiceAccountName)-$($result.Timestamp)"
                    }
                    $secretResult.SecretName = $secretName
                    
                    # Check if secret already exists
                    $existingSecret = Get-SecretInfo -Name $secretName -Vault $VaultName -ErrorAction SilentlyContinue
                    if ($existingSecret -and -not $OverwriteExisting) {
                        $secretResult.SkipReason = "Secret already exists (use -OverwriteExisting to replace)"
                        $secretResult.Skipped = $true
                        $result.SkippedSecrets += [PSCustomObject]$secretResult
                        $result.Warnings += "Secret '$secretName' already exists - skipping (use -OverwriteExisting to replace)"
                        Write-Warning "Secret '$secretName' already exists - skipping"
                        continue
                    }
                    
                    # Create metadata object
                    $metadata = @{
                        ServiceAccount = $entry.ServiceAccountName
                        CreatedDate = if ($entry.CreatedDate) { 
                            $entry.CreatedDate.ToString('yyyy-MM-dd HH:mm:ss') 
                        } else { 
                            (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') 
                        }
                        StoredDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        CorrelationId = $CorrelationId.ToString()
                        Source = "ADTestEnvironment"
                    }
                    
                    # Add optional metadata
                    if ($entry.Description) { $metadata.Description = $entry.Description }
                    if ($entry.Department) { $metadata.Department = $entry.Department }
                    if ($entry.ExpirationDate) { 
                        $metadata.ExpirationDate = $entry.ExpirationDate.ToString('yyyy-MM-dd HH:mm:ss') 
                    }
                    
                    # Convert password to SecureString
                    $securePassword = ConvertTo-SecureString -String $entry.Password -AsPlainText -Force
                    
                    # Store the secret
                    Write-Verbose "Storing secret: $secretName"
                    Set-Secret -Name $secretName -Secret $securePassword -Vault $VaultName -Metadata $metadata -ErrorAction Stop
                    
                    $secretResult.Success = $true
                    $result.StoredSecrets += [PSCustomObject]@{
                        SecretName = $secretName
                        ServiceAccount = $entry.ServiceAccountName
                        StoredDate = Get-Date
                        Metadata = $metadata
                    }
                    
                    Write-Verbose "Successfully stored secret for: $($entry.ServiceAccountName)"
                    
                }
                catch {
                    $errorMsg = "Failed to store secret for '$($entry.ServiceAccountName)': $($_.Exception.Message)"
                    $secretResult.Error = $errorMsg
                    $result.FailedSecrets += [PSCustomObject]$secretResult
                    $result.Errors += $errorMsg
                    Write-Error $errorMsg
                    continue
                }
            }
            
            # Summary
            $storedCount = $result.StoredSecrets.Count
            $skippedCount = $result.SkippedSecrets.Count
            $failedCount = $result.FailedSecrets.Count
            
            Write-Verbose "Password storage complete - Stored: $storedCount, Skipped: $skippedCount, Failed: $failedCount"
            
            if ($storedCount -eq 0 -and $failedCount -gt 0) {
                throw "No passwords were successfully stored. See errors for details."
            }
            
        }
        catch {
            $errorMsg = "Failed to store AD test passwords: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Set-ADTestPasswordSecret - CorrelationId: $CorrelationId"
        return [PSCustomObject]$result
    }
}
