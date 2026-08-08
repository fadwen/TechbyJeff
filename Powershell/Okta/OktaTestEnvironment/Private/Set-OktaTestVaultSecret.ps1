function Set-OktaTestVaultSecret {
    <#
    .SYNOPSIS
        Stores the service app private key in a SecretStore vault

    .DESCRIPTION
        The counterpart to the DPAPI path. The JWK is stored as a SecureString rather than a
        plain string, so SecretManagement treats it as a secret throughout and it does not turn
        up in a Get-SecretInfo listing or a transcript.

    .PARAMETER VaultName
        The vault to write to

    .PARAMETER SecretName
        The secret's name within the vault

    .PARAMETER PlainText
        The serialised private JWK

    .OUTPUTS
        Boolean indicating success

    .EXAMPLE
        Set-OktaTestVaultSecret -VaultName 'OktaTestEnvironment' -SecretName $name -PlainText $json

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Converting to SecureString is what hands the value to the vault as a secret.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VaultName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SecretName,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PlainText
    )

    if (-not $PSCmdlet.ShouldProcess("$VaultName\$SecretName", 'Store the service app private key')) {
        return $false
    }

    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    Set-Secret -Name $SecretName -SecureStringSecret $secure -Vault $VaultName -ErrorAction Stop

    Write-Verbose "Stored '$SecretName' in vault '$VaultName'."
    return $true
}
