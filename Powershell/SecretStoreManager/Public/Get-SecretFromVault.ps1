function Get-SecretFromVault {
    <#
    .SYNOPSIS
        Retrieves stored secrets from a SecretStore vault

    .DESCRIPTION
        Helper function to retrieve secrets that were stored in a SecretStore vault.
        Can retrieve by account name, exact secret name, or list all secrets with metadata.
        Supports expiration date filtering and secure string or plain text output.

    .PARAMETER AccountName
        Name of the account to retrieve the secret for

    .PARAMETER SecretName
        Exact name of the secret in the vault (includes timestamp if applicable)

    .PARAMETER VaultName
        Name of the secret vault to search. Defaults to "SecretStoreVault"

    .PARAMETER AsPlainText
        Return the secret as plain text instead of SecureString. Use with caution.

    .PARAMETER ListSecrets
        List all secrets in the vault with their metadata

    .PARAMETER IncludeExpired
        Include expired secrets in results (based on ExpirationDate metadata)

    .EXAMPLE
        Get-SecretFromVault -AccountName "svc-app1"
        Retrieves the most recent secret for svc-app1 as a SecureString

    .EXAMPLE
        Get-SecretFromVault -AccountName "svc-app1" -AsPlainText
        Retrieves the secret as plain text (use with caution)

    .EXAMPLE
        Get-SecretFromVault -ListSecrets
        Lists all stored secrets with their metadata

    .EXAMPLE
        Get-SecretFromVault -ListSecrets -IncludeExpired
        Lists all secrets including expired ones

    .EXAMPLE
        Get-SecretFromVault -SecretName "MyApp-Credentials-20250805-143022"
        Retrieves a specific secret by exact name

    .OUTPUTS
        SecureString (default) or String (with -AsPlainText) containing the secret
        PSCustomObject array (with -ListSecrets) containing secret information

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Security Notes:
        - Use -AsPlainText sparingly and ensure secure handling
        - SecureString return type is recommended for production use
        - Expired secrets are filtered out by default
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByAccountName')]
    [OutputType([System.String], ParameterSetName = 'ByAccountName')]
    [OutputType([System.Security.SecureString], ParameterSetName = 'ByAccountName')]
    [OutputType([System.String], ParameterSetName = 'BySecretName')]
    [OutputType([System.Security.SecureString], ParameterSetName = 'BySecretName')]
    [OutputType([PSCustomObject[]], ParameterSetName = 'ListSecrets')]
    param(
        [Parameter(ParameterSetName = 'ByAccountName', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName,
        
        [Parameter(ParameterSetName = 'BySecretName', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = $script:DefaultVaultName,
        
        [Parameter()]
        [switch]$AsPlainText,
        
        [Parameter(ParameterSetName = 'ListSecrets')]
        [switch]$ListSecrets,
        
        [Parameter()]
        [switch]$IncludeExpired
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Get-SecretFromVault - CorrelationId: $correlationId"
    }

    process {
        try {
            # Check if SecretManagement module is available
            if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
                throw "Microsoft.PowerShell.SecretManagement module is not installed. Install it using: Install-Module Microsoft.PowerShell.SecretManagement"
            }
            
            Import-Module Microsoft.PowerShell.SecretManagement -Force

            # Check if vault exists
            $vault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
            if (-not $vault) {
                throw "SecretStore vault '$VaultName' not found. Create it first using New-SecretStoreVault."
            }

            if ($ListSecrets) {
                # List all secrets in the vault
                Write-Verbose "Listing all secrets in vault: $VaultName"
                $secrets = Get-SecretInfo -Vault $VaultName
                $secretList = @()
                
                foreach ($secret in $secrets) {
                    $secretInfo = [PSCustomObject]@{
                        SecretName = $secret.Name
                        AccountName = $secret.Metadata.AccountName
                        ServiceAccount = $secret.Metadata.ServiceAccount  # Backward compatibility
                        CreatedDate = $secret.Metadata.CreatedDate
                        StoredDate = $secret.Metadata.StoredDate
                        Description = $secret.Metadata.Description
                        Department = $secret.Metadata.Department
                        ExpirationDate = $secret.Metadata.ExpirationDate
                        CorrelationId = $secret.Metadata.CorrelationId
                        Source = $secret.Metadata.Source
                        SecretType = $secret.Metadata.SecretType
                        IsExpired = $false
                    }
                    
                    # Check if secret is expired
                    if ($secret.Metadata.ExpirationDate) {
                        try {
                            $expirationDate = [DateTime]::Parse($secret.Metadata.ExpirationDate)
                            $secretInfo.IsExpired = $expirationDate -lt (Get-Date)
                        }
                        catch {
                            Write-Verbose "Could not parse expiration date for secret: $($secret.Name)"
                        }
                    }
                    
                    # Filter expired secrets unless specifically included
                    if ($secretInfo.IsExpired -and -not $IncludeExpired) {
                        Write-Verbose "Excluding expired secret: $($secret.Name)"
                        continue
                    }
                    
                    $secretList += $secretInfo
                }
                
                Write-Verbose "Found $($secretList.Count) secrets in vault"
                return $secretList
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByAccountName') {
                # Find secrets for the specified account
                Write-Verbose "Searching for secrets for account: $AccountName"
                $secrets = Get-SecretInfo -Vault $VaultName | Where-Object { 
                    $_.Metadata.AccountName -eq $AccountName -or $_.Metadata.ServiceAccount -eq $AccountName
                }
                
                if (-not $secrets) {
                    throw "No secrets found for account '$AccountName' in vault '$VaultName'"
                }
                
                # Filter out expired secrets unless specifically included
                if (-not $IncludeExpired) {
                    $secrets = $secrets | Where-Object {
                        if ($_.Metadata.ExpirationDate) {
                            try {
                                $expirationDate = [DateTime]::Parse($_.Metadata.ExpirationDate)
                                return $expirationDate -ge (Get-Date)
                            }
                            catch {
                                # If we can't parse the date, include it
                                return $true
                            }
                        }
                        # No expiration date means it doesn't expire
                        return $true
                    }
                }
                
                if (-not $secrets) {
                    throw "No non-expired secrets found for account '$AccountName' in vault '$VaultName'. Use -IncludeExpired to include expired secrets."
                }
                
                # Get the most recent secret (by name which includes timestamp)
                $latestSecret = $secrets | Sort-Object Name -Descending | Select-Object -First 1
                Write-Verbose "Retrieved latest secret: $($latestSecret.Name)"
                
                $secret = Get-Secret -Name $latestSecret.Name -Vault $VaultName
                
                if ($AsPlainText) {
                    Write-Warning "Returning secret as plain text - ensure secure handling"
                    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret))
                }
                else {
                    return $secret
                }
            }
            else {
                # Get secret by exact name
                Write-Verbose "Retrieving secret by name: $SecretName"
                
                # Check if secret exists and is not expired
                $secretInfo = Get-SecretInfo -Name $SecretName -Vault $VaultName -ErrorAction SilentlyContinue
                if (-not $secretInfo) {
                    throw "Secret '$SecretName' not found in vault '$VaultName'"
                }
                
                # Check expiration if not including expired
                if (-not $IncludeExpired -and $secretInfo.Metadata.ExpirationDate) {
                    try {
                        $expirationDate = [DateTime]::Parse($secretInfo.Metadata.ExpirationDate)
                        if ($expirationDate -lt (Get-Date)) {
                            throw "Secret '$SecretName' has expired on $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss')). Use -IncludeExpired to retrieve expired secrets."
                        }
                    }
                    catch [System.FormatException] {
                        Write-Verbose "Could not parse expiration date for secret: $SecretName"
                    }
                }
                
                $secret = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop
                
                if ($AsPlainText) {
                    Write-Warning "Returning secret as plain text - ensure secure handling"
                    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret))
                }
                else {
                    return $secret
                }
            }
        }
        catch {
            Write-Error "Failed to retrieve secret from vault: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Get-SecretFromVault - CorrelationId: $correlationId"
    }
}
