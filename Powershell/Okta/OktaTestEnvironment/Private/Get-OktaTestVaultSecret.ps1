function Get-OktaTestVaultSecret {
    <#
    .SYNOPSIS
        Reads the service app private key back out of a SecretStore vault

    .DESCRIPTION
        Imports SecretManagement on demand rather than at module load, for the same reason
        Initialize-OktaTestSecretVault does: the module declares no required modules, and a
        credential stored as a plain file must not pay the cost of a vault it never uses.

        A missing secret is reported with the vault and name in the message. The default
        SecretManagement error for this says only that the secret was not found, which is not
        much help when the cause is usually a vault that exists but is locked.

    .PARAMETER VaultName
        The vault to read from

    .PARAMETER SecretName
        The secret's name within the vault

    .PARAMETER VaultPassword
        Password used to unlock the store if it is locked

    .OUTPUTS
        String containing the serialised private JWK

    .EXAMPLE
        $json = Get-OktaTestVaultSecret -VaultName 'OktaTestEnvironment' -SecretName $name

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Default lab vault password; -VaultPassword overrides it.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VaultName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SecretName,
        [Parameter()][System.Security.SecureString]$VaultPassword
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
        throw ("The credential is stored in the SecretStore vault '$VaultName', but " +
            'Microsoft.PowerShell.SecretManagement is not installed on this machine. Install ' +
            'it, or re-run New-OktaTestServiceApp -Force to mint a new key stored as a file.')
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop -Verbose:$false

    # Unlocking is attempted before the read rather than after a failure, because a locked
    # store's read error is a prompt on an interactive host and a hang on any other.
    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore) {
        Import-Module Microsoft.PowerShell.SecretStore -ErrorAction SilentlyContinue -Verbose:$false
        try {
            $unlockPassword = $VaultPassword
            if (-not $unlockPassword) {
                $unlockPassword = ConvertTo-SecureString -String 'OktaTestEnvironmentPassword' `
                    -AsPlainText -Force
            }
            Unlock-SecretStore -Password $unlockPassword -ErrorAction Stop
        }
        catch {
            Write-Verbose "SecretStore did not need unlocking: $($_.Exception.Message)"
        }
    }

    $secret = $null
    try {
        $secret = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop
    }
    catch {
        throw ("Could not read secret '$SecretName' from vault '$VaultName': " +
            "$($_.Exception.Message). If the vault is locked, unlock it with Unlock-SecretStore.")
    }

    if (-not $secret) {
        throw "Secret '$SecretName' was not found in vault '$VaultName'."
    }

    if ($secret -is [System.Security.SecureString]) {
        return ConvertFrom-OktaTestSecureString -SecureString $secret
    }

    return [string]$secret
}
