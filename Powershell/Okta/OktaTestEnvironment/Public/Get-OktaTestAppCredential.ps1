function Get-OktaTestAppCredential {
    <#
    .SYNOPSIS
        Shows where the service app credential is stored and how it is protected

    .DESCRIPTION
        Answers "where did the key actually go, and is it encrypted?" without having to open a
        JSON file and interpret it.

        The private key is deliberately NOT returned by default. Everything this module does
        with the key it does internally - Get-OktaTestAccessToken signs an assertion and hands
        back a token - so there is no ordinary workflow that needs the raw key in a variable,
        and a function that returns one by default is a function that puts one in transcripts
        and scrollback. -IncludePrivateKey is there for the case where you genuinely need to
        move the key into another tool, and it asks first.

    .PARAMETER CredentialPath
        Path to the credential file. Defaults to the per-user location for the connected org.

    .PARAMETER OrgUrl
        Org whose credential to look up. Defaults to the connected org.

    .PARAMETER VaultPassword
        Password used to unlock the SecretStore vault, when the credential is stored in one

    .PARAMETER IncludePrivateKey
        Also return the private JWK. Prompts for confirmation, because the returned object then
        contains a live admin credential.

    .OUTPUTS
        PSCustomObject describing the credential

    .EXAMPLE
        Get-OktaTestAppCredential
        Shows the client id, scopes, storage location and protection method

    .EXAMPLE
        Get-OktaTestAppCredential -IncludePrivateKey -Confirm:$false | Select-Object -Expand PrivateJwk
        Extracts the raw key, for moving it into another tool

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Protection values:
        - DPAPI       encrypted into the file, bound to this user and machine (the default)
        - SecretStore encrypted in a vault; the file holds only a pointer
        - None        unprotected, guarded only by file permissions

    .LINK
        New-OktaTestServiceApp
        Get-OktaTestAccessToken
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path, not a credential. The key it points at never appears here.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [string]$OrgUrl,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$IncludePrivateKey
    )

    if (-not $CredentialPath) {
        $connection = Get-OktaTestConnection -AllowNone
        $resolvedOrg = if ($OrgUrl) { $OrgUrl } elseif ($connection) { $connection.OrgUrl } else { $null }

        if (-not $resolvedOrg) {
            throw ('Specify -CredentialPath or -OrgUrl, or connect first, so the credential ' +
                'file can be located.')
        }
        $CredentialPath = Get-OktaTestCredentialPath -OrgUrl $resolvedOrg
    }

    $importArgs = @{ Path = $CredentialPath }
    if ($VaultPassword) { $importArgs.VaultPassword = $VaultPassword }
    $credential = Import-OktaTestAppCredential @importArgs

    $result = [PSCustomObject]@{
        OrgUrl         = $credential.orgUrl
        ClientId       = $credential.clientId
        AppId          = $credential.appId
        Label          = $credential.label
        Scopes         = @($credential.scopes)
        Protection     = $credential.protection
        Encrypted      = ($credential.protection -in @('DPAPI', 'SecretStore'))
        VaultName      = $credential.vaultName
        SecretName     = $credential.secretName
        CredentialPath = $CredentialPath
        CreatedUtc     = $credential.createdUtc
    }

    if ($credential.protection -eq 'None') {
        Write-Warning ("The private key for $($credential.clientId) is stored UNENCRYPTED at " +
            "'$CredentialPath'. Re-run New-OktaTestServiceApp -Force to replace it, adding " +
            '-UseSecretStore if this platform has no DPAPI.')
    }

    if ($IncludePrivateKey) {
        if ($PSCmdlet.ShouldProcess($credential.clientId, 'Return the private key in plain form')) {
            $result | Add-Member -NotePropertyName PrivateJwk -NotePropertyValue $credential.privateJwk
        }
    }

    return $result
}
