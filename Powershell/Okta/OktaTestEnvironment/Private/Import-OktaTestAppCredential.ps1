function Import-OktaTestAppCredential {
    <#
    .SYNOPSIS
        Reads back the service app credential written by Export-OktaTestAppCredential

    .DESCRIPTION
        Resolves whichever of the three storage modes the file records and returns a uniform
        object with the private JWK attached, so callers never branch on storage.

        Schema version 1 is still accepted. Those files hold the JWK as plain JSON, from before
        the credential was encrypted at rest, and refusing them would strand anybody who seeded
        an environment with an earlier build. They are read, used, and reported with a warning
        naming the command that upgrades them - a warning being the right level because the
        credential still works and the run should not stop for it.

        The shape is validated rather than trusted, because the failure mode of a truncated or
        hand-edited file is an opaque 401 from the token endpoint several calls later, and that
        is a bad place to start debugging from.

    .PARAMETER Path
        The credential file to read

    .PARAMETER VaultPassword
        Password used to unlock the SecretStore vault, when the credential lives in one

    .OUTPUTS
        PSCustomObject with orgUrl, clientId, appId, label, scopes, protection and privateJwk

    .EXAMPLE
        $credential = Import-OktaTestAppCredential -Path $path

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not (Test-Path -Path $Path)) {
        throw ("No service app credential at '$Path'. Run New-OktaTestServiceApp while " +
            'connected with an SSWS token to create one.')
    }

    $json = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    # A UTF-8 BOM is legal in a file and illegal in JSON, and something else may have written
    # this file. Strip it rather than failing on it.
    $json = $json.TrimStart([char]0xFEFF)

    $credential = $null
    try { $credential = $json | ConvertFrom-Json }
    catch { throw "'$Path' is not valid JSON: $($_.Exception.Message)" }

    foreach ($required in @('orgUrl', 'clientId', 'appId')) {
        if (-not $credential.PSObject.Properties[$required] -or -not $credential.$required) {
            throw "'$Path' is missing the required '$required' field and cannot be used."
        }
    }

    # Absent on version 1 files, which predate encryption at rest.
    $protection = if ($credential.PSObject.Properties['protection']) {
        $credential.protection
    }
    else { 'None' }

    switch ($protection) {
        'SecretStore' {
            if (-not $credential.vaultName -or -not $credential.secretName) {
                throw "'$Path' says the key is in a vault but does not name the vault or secret."
            }

            $vaultArgs = @{ VaultName = $credential.vaultName; SecretName = $credential.secretName }
            if ($VaultPassword) { $vaultArgs.VaultPassword = $VaultPassword }
            $jwkJson = Get-OktaTestVaultSecret @vaultArgs
        }

        'DPAPI' {
            if (-not $credential.privateJwkProtected) {
                throw "'$Path' is marked DPAPI-protected but carries no protected key."
            }
            $jwkJson = Unprotect-OktaTestSecret -Method 'DPAPI' -Value $credential.privateJwkProtected
        }

        default {
            # Version 1, or a host where DPAPI was unavailable at write time.
            if ($credential.PSObject.Properties['privateJwk'] -and $credential.privateJwk) {
                $jwkJson = $credential.privateJwk | ConvertTo-Json -Depth 10 -Compress

                if (-not $credential.PSObject.Properties['schemaVersion'] -or
                    $credential.schemaVersion -lt 2) {
                    Write-Warning ("'$Path' stores the private key unencrypted, in the format " +
                        'used before this module encrypted credentials at rest. Re-run ' +
                        'New-OktaTestServiceApp -Force with an SSWS token to replace it.')
                }
            }
            elseif ($credential.PSObject.Properties['privateJwkProtected']) {
                $jwkJson = $credential.privateJwkProtected
            }
            else {
                throw "'$Path' carries no private key in any recognised form."
            }
        }
    }

    $privateJwk = $null
    try { $privateJwk = $jwkJson | ConvertFrom-Json }
    catch { throw "The stored private key in '$Path' is not valid JSON: $($_.Exception.Message)" }

    return [PSCustomObject]@{
        orgUrl     = $credential.orgUrl
        clientId   = $credential.clientId
        appId      = $credential.appId
        label      = $credential.label
        scopes     = @($credential.scopes)
        protection = $protection
        vaultName  = if ($credential.PSObject.Properties['vaultName']) { $credential.vaultName } else { $null }
        secretName = if ($credential.PSObject.Properties['secretName']) { $credential.secretName } else { $null }
        createdUtc = if ($credential.PSObject.Properties['createdUtc']) { $credential.createdUtc } else { $null }
        privateJwk = $privateJwk
        path       = $Path
    }
}
