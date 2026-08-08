function Export-OktaTestAppCredential {
    <#
    .SYNOPSIS
        Writes the service app's client id and private key to protected storage

    .DESCRIPTION
        This is the handover point between the two authentication modes: everything before it
        runs on the SSWS token you pasted in, everything after it can run on the app.

        Three storage modes, and the metadata file is written in all of them so that the
        org-to-credential mapping is always discoverable in one place:

        - DPAPI (default). The key is encrypted into the file with a key derived from your user
          account and this machine. No modules, nothing to remember, and the file is useless if
          it is copied elsewhere.
        - SecretStore. The key goes into an encrypted vault and the file holds only a pointer to
          it. This is the cross-platform option, and the one to use if you already keep other
          lab credentials in a vault.
        - None. Only reached when DPAPI is unavailable, which today means a non-Windows host
          without -UseSecretStore. It warns rather than failing, because an app registered in
          Okta with no key on disk to match it is worse than a key with a warning attached.

        The file is written first and its ACL restricted second, which is the wrong order in
        the abstract because Set-Acl needs the file to exist. The gap is closed by creating the
        parent folder with a restricted ACL beforehand, so the file is never reachable by
        another user even during it. Under DPAPI the point is close to moot anyway - the bytes
        on disk are ciphertext either way.

    .PARAMETER Path
        Destination file

    .PARAMETER OrgUrl
        Org the credential belongs to

    .PARAMETER ClientId
        The service app client_id

    .PARAMETER AppId
        The app instance id, which the management API uses for grants and lifecycle

    .PARAMETER Label
        The app label, so teardown can find the app without this file

    .PARAMETER Scopes
        The Okta API scopes granted to the app

    .PARAMETER PrivateJwk
        The private JWK to store

    .PARAMETER UseSecretStore
        Store the key in a SecretStore vault instead of encrypting it into the file

    .PARAMETER VaultName
        Vault to use when -UseSecretStore is specified

    .PARAMETER VaultPassword
        Password for the vault when -UseSecretStore is specified

    .OUTPUTS
        PSCustomObject describing what was written

    .EXAMPLE
        Export-OktaTestAppCredential -Path $path -OrgUrl $org -ClientId $id -AppId $appId `
            -Label 'OKTALAB Automation' -Scopes $scopes -PrivateJwk $jwk

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OrgUrl,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AppId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Scopes,
        [Parameter(Mandatory = $true)][object]$PrivateJwk,
        [Parameter()][switch]$UseSecretStore,
        [Parameter()][string]$VaultName = 'OktaTestEnvironment',
        [Parameter()][System.Security.SecureString]$VaultPassword
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the service app credential')) {
        return $null
    }

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        $null = New-Item -Path $folder -ItemType Directory -Force
        # Lock the folder before anything sensitive lands in it, so the file is never
        # world-readable even for the instant between New-Item and Set-Acl below.
        $null = Protect-OktaTestFile -Path $folder -Confirm:$false
    }

    $jwkJson = $PrivateJwk | ConvertTo-Json -Depth 10 -Compress

    $payload = [ordered]@{
        schemaVersion = 2
        orgUrl        = $OrgUrl.TrimEnd('/')
        clientId      = $ClientId
        appId         = $AppId
        label         = $Label
        scopes        = @($Scopes)
        createdUtc    = [DateTime]::UtcNow.ToString('o')
    }

    $secretName = 'OktaTestEnvironment-{0}-{1}' -f ([uri]$OrgUrl).Host, $ClientId

    if ($UseSecretStore) {
        $vaultArgs = @{ VaultName = $VaultName; Install = $true; Confirm = $false }
        if ($VaultPassword) { $vaultArgs.VaultPassword = $VaultPassword }
        $null = Initialize-OktaTestSecretVault @vaultArgs

        $null = Set-OktaTestVaultSecret -VaultName $VaultName -SecretName $secretName `
            -PlainText $jwkJson -Confirm:$false

        $payload.protection = 'SecretStore'
        $payload.vaultName  = $VaultName
        $payload.secretName = $secretName
    }
    else {
        $protected = Protect-OktaTestSecret -PlainText $jwkJson
        $payload.protection         = $protected.Method
        $payload.privateJwkProtected = $protected.Value
    }

    $json = $payload | ConvertTo-Json -Depth 10

    # Set-Content -Encoding UTF8 writes a BOM on Windows PowerShell, which ConvertFrom-Json on
    # the same edition then chokes on. Writing the bytes avoids arguing with either.
    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::UTF8.GetBytes($json))

    $protectedFile = Protect-OktaTestFile -Path $Path -Confirm:$false

    return [PSCustomObject]@{
        Path          = $Path
        ClientId      = $ClientId
        AppId         = $AppId
        Scopes        = @($Scopes)
        Protection    = $payload.protection
        VaultName     = if ($UseSecretStore) { $VaultName } else { $null }
        SecretName    = if ($UseSecretStore) { $secretName } else { $null }
        FileProtected = $protectedFile
    }
}
