function Remove-OktaTestVaultSecret {
    <#
    .SYNOPSIS
        Deletes the service app secret from a SecretStore vault

    .DESCRIPTION
        Removes the named secret and leaves the vault itself alone. The vault may hold secrets
        put there by something else, and this module registering it does not make it this
        module's to delete.

        A missing secret is not an error. Teardown runs this after the app has been deleted, and
        the common reason for the secret being absent is that a previous teardown already
        removed it, which is the desired end state either way.

    .PARAMETER VaultName
        The vault to remove the secret from

    .PARAMETER SecretName
        The secret's name within the vault

    .OUTPUTS
        Boolean indicating whether a secret was actually removed

    .EXAMPLE
        Remove-OktaTestVaultSecret -VaultName 'OktaTestEnvironment' -SecretName $name

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VaultName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SecretName
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
        Write-Verbose 'SecretManagement is not installed; nothing to remove.'
        return $false
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop -Verbose:$false

    if (-not (Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Vault '$VaultName' is not registered; nothing to remove."
        return $false
    }

    if (-not (Get-SecretInfo -Name $SecretName -Vault $VaultName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Secret '$SecretName' is not present in '$VaultName'."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess("$VaultName\$SecretName", 'Delete the service app private key')) {
        return $false
    }

    Remove-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop
    Write-Verbose "Removed '$SecretName' from vault '$VaultName'."
    return $true
}
