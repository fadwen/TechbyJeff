function Set-VaultSecret {
    <#
    .SYNOPSIS
        Stores secrets in a SecretStore vault with metadata

    .DESCRIPTION
        Internal helper functi        catch {
            $errorMsg = "Failed to store secrets: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
        } store secrets in a SecretStore vault with comprehensive metadata.
        Supports various secret types and automatic expiration date handling.

    .PARAMETER SecretData
        Array of secret objects to store in the vault.
        Expected format: @{ AccountName = "name"; Secret = "value"; SecretType = "type"; ExpirationDate = "date"; Description = "desc" }

    .PARAMETER VaultName
        Name of the secret vault to store secrets in

    .PARAMETER CorrelationId
        Correlation ID for tracking related operations

    .PARAMETER DefaultExpirationDays
        Default number of days until expiration if not specified per secret. Defaults to 90 days.

    .EXAMPLE
        Set-SecretInVault -SecretData $secrets -VaultName "MyVault"
        Stores secrets in the specified vault

    .OUTPUTS
        PSCustomObject containing storage operation results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        This is an internal helper function - use Set-SecretInVault for main operations
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$SecretData,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,
        
        [Parameter()]
        [ValidateNotNull()]
        [System.Guid]$CorrelationId = [System.Guid]::NewGuid(),
        
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$DefaultExpirationDays = 90
    )

    begin {
        Write-Verbose "Starting Set-SecretInVault - CorrelationId: $CorrelationId"
        
        $result = @{
            CorrelationId = $CorrelationId
            VaultName = $VaultName
            TotalSecrets = $SecretData.Count
            TotalStored = 0
            StoredSecrets = @()
            Errors = @()
            Warnings = @()
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    }

    process {
        if ($PSCmdlet.ShouldProcess("$VaultName", "Store $($SecretData.Count) secrets")) {
            try {
                Write-Verbose "Storing $($SecretData.Count) secrets in vault: $VaultName"
            
            foreach ($secret in $SecretData) {
                try {
                    # Validate secret object
                    if (-not $secret.AccountName) {
                        $result.Warnings += "Secret missing AccountName - skipping"
                        continue
                    }
                    
                    if (-not $secret.Secret) {
                        $result.Warnings += "Secret for '$($secret.AccountName)' missing Secret value - skipping"
                        continue
                    }
                    
                    # Create secret name with timestamp
                    $secretName = "$($secret.AccountName)-$timestamp"
                    
                    # Convert secret to SecureString if it isn't already
                    # Use secure credential handling function with fallback for automation scenarios
                    $secureSecret = ConvertTo-SecureSecret -InputSecret $secret.Secret -PromptMessage "Enter secret value for '$($secret.AccountName)'" -AllowPlaintextFallback
                    
                    # Prepare metadata
                    $metadata = @{
                        AccountName = $secret.AccountName
                        ServiceAccount = $secret.AccountName  # Backward compatibility
                        CreatedDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        StoredDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        CorrelationId = $CorrelationId.ToString()
                        Source = "SecretStoreManager"
                        SecretType = if ($secret.SecretType) { $secret.SecretType } else { "Credential" }
                    }
                    
                    # Add optional metadata
                    if ($secret.Description) {
                        $metadata.Description = $secret.Description
                    }
                    
                    if ($secret.Department) {
                        $metadata.Department = $secret.Department
                    }
                    
                    # Handle expiration date
                    if ($secret.ExpirationDate) {
                        if ($secret.ExpirationDate -is [DateTime]) {
                            $metadata.ExpirationDate = $secret.ExpirationDate.ToString('yyyy-MM-dd HH:mm:ss')
                        }
                        else {
                            try {
                                $expDate = [DateTime]::Parse($secret.ExpirationDate)
                                $metadata.ExpirationDate = $expDate.ToString('yyyy-MM-dd HH:mm:ss')
                            }
                            catch {
                                Write-Warning "Invalid expiration date format for '$($secret.AccountName)' - using default"
                                $metadata.ExpirationDate = (Get-Date).AddDays($DefaultExpirationDays).ToString('yyyy-MM-dd HH:mm:ss')
                            }
                        }
                    }
                    else {
                        # Use default expiration
                        $metadata.ExpirationDate = (Get-Date).AddDays($DefaultExpirationDays).ToString('yyyy-MM-dd HH:mm:ss')
                    }
                    
                    # Store the secret
                    Write-Verbose "Storing secret: $secretName"
                    Set-Secret -Name $secretName -Secret $secureSecret -Vault $VaultName -Metadata $metadata -ErrorAction Stop
                    
                    $result.TotalStored++
                    $result.StoredSecrets += @{
                        SecretName = $secretName
                        AccountName = $secret.AccountName
                        StoredDate = $metadata.StoredDate
                        ExpirationDate = $metadata.ExpirationDate
                    }
                    
                    Write-Verbose "Successfully stored secret for: $($secret.AccountName)"
                }
                catch {
                    $errorMsg = "Failed to store secret for '$($secret.AccountName)': $($_.Exception.Message)"
                    $result.Errors += $errorMsg
                    Write-Error $errorMsg
                }
            }
            
            Write-Verbose "Completed storing secrets - Successfully stored: $($result.TotalStored)/$($result.TotalSecrets)"
        }
        catch {
            $errorMsg = "Failed to store secrets in vault: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
        }
    }

    end {
        Write-Verbose "Completed Set-SecretInVault - CorrelationId: $CorrelationId"
        return [PSCustomObject]$result
    }
}
