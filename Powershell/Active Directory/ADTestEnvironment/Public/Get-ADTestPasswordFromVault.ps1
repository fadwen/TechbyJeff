function Get-ADTestPasswordFromVault {
    <#
    .SYNOPSIS
        Retrieves a stored password from the ADTestEnvironment SecretStore vault

    .DESCRIPTION
        Helper function to retrieve passwords that were stored using Export-PasswordDocumentation
        with the -UseSecretStore parameter. Can retrieve by service account name or secret name.

    .PARAMETER ServiceAccountName
        Name of the service account to retrieve the password for

    .PARAMETER SecretName
        Exact name of the secret in the vault (includes timestamp)

    .PARAMETER VaultName
        Name of the secret vault to search. Defaults to "ADTestEnvironment"

    .PARAMETER AsPlainText
        Return the password as plain text instead of SecureString. Use with caution.

    .PARAMETER ListSecrets
        List all secrets in the vault with their metadata

    .PARAMETER IncludeExpired
        Include expired secrets in results (based on ExpirationDate metadata)

    .EXAMPLE
        Get-ADTestPasswordFromVault -ServiceAccountName "svc-app1"
        Retrieves the most recent password for svc-app1 as a SecureString

    .EXAMPLE
        Get-ADTestPasswordFromVault -ServiceAccountName "svc-app1" -AsPlainText
        Retrieves the password as plain text (use with caution)

    .EXAMPLE
        Get-ADTestPasswordFromVault -ListSecrets
        Lists all stored secrets with their metadata

    .EXAMPLE
        Get-ADTestPasswordFromVault -ListSecrets -IncludeExpired
        Lists all secrets including expired ones

    .OUTPUTS
        SecureString (default) or String (with -AsPlainText) containing the password
        PSCustomObject array (with -ListSecrets) containing secret information

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05

        Security Notes:
        - Use -AsPlainText sparingly and ensure secure handling
        - SecureString return type is recommended for production use
        - Expired passwords are filtered out by default
    #>

    [CmdletBinding(DefaultParameterSetName = 'ByServiceAccount')]
    [OutputType([System.Security.SecureString], ParameterSetName = 'ByServiceAccount')]
    [OutputType([System.Security.SecureString], ParameterSetName = 'BySecretName')]
    [OutputType([string], ParameterSetName = 'ByServiceAccount')]
    [OutputType([string], ParameterSetName = 'BySecretName')]
    [OutputType([PSCustomObject[]], ParameterSetName = 'ListSecrets')]
    param(
        [Parameter(ParameterSetName = 'ByServiceAccount', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName,

        [Parameter(ParameterSetName = 'BySecretName', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",

        [Parameter()]
        [switch]$AsPlainText,

        [Parameter(ParameterSetName = 'ListSecrets')]
        [switch]$ListSecrets,

        [Parameter()]
        [switch]$IncludeExpired
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Get-ADTestPasswordFromVault - CorrelationId: $correlationId"
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
                throw "SecretStore vault '$VaultName' not found. Create it first using Export-PasswordDocumentation with -UseSecretStore parameter."
            }

            if ($ListSecrets) {
                # List all secrets in the vault
                Write-Verbose "Listing all secrets in vault: $VaultName"
                $secrets = Get-SecretInfo -Vault $VaultName
                $secretList = @()

                foreach ($secret in $secrets) {
                    $secretInfo = [PSCustomObject]@{
                        SecretName = $secret.Name
                        ServiceAccount = $secret.Metadata.ServiceAccount
                        CreatedDate = $secret.Metadata.CreatedDate
                        StoredDate = $secret.Metadata.StoredDate
                        Description = $secret.Metadata.Description
                        Department = $secret.Metadata.Department
                        ExpirationDate = $secret.Metadata.ExpirationDate
                        CorrelationId = $secret.Metadata.CorrelationId
                        Source = $secret.Metadata.Source
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
            elseif ($PSCmdlet.ParameterSetName -eq 'ByServiceAccount') {
                # Find secrets for the specified service account
                Write-Verbose "Searching for secrets for service account: $ServiceAccountName"
                $secrets = Get-SecretInfo -Vault $VaultName | Where-Object {
                    $_.Metadata.ServiceAccount -eq $ServiceAccountName
                }

                if (-not $secrets) {
                    throw "No secrets found for service account '$ServiceAccountName' in vault '$VaultName'"
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
                    throw "No non-expired secrets found for service account '$ServiceAccountName' in vault '$VaultName'. Use -IncludeExpired to include expired secrets."
                }

                # Get the most recent secret (by name which includes timestamp)
                $latestSecret = $secrets | Sort-Object Name -Descending | Select-Object -First 1
                Write-Verbose "Retrieved latest secret: $($latestSecret.Name)"

                $password = Get-Secret -Name $latestSecret.Name -Vault $VaultName

                if ($AsPlainText) {
                    Write-Warning "Returning password as plain text - ensure secure handling"
                    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
                }
                else {
                    return $password
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

                $password = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop

                if ($AsPlainText) {
                    Write-Warning "Returning password as plain text - ensure secure handling"
                    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
                }
                else {
                    return $password
                }
            }
        }
        catch {
            Write-Error "Failed to retrieve password from vault: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Get-ADTestPasswordFromVault - CorrelationId: $correlationId"
    }
}
