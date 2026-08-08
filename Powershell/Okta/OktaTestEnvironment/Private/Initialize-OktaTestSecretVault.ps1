function Initialize-OktaTestSecretVault {
    <#
    .SYNOPSIS
        Makes sure a usable SecretStore vault exists, installing the modules if asked to

    .DESCRIPTION
        SecretManagement and SecretStore are deliberately absent from the manifest's
        RequiredModules. The module's zero-dependency promise is what lets it run on a
        locked-down host, and a required module would break that for everybody in order to
        serve the minority who opt into the vault. They are therefore imported here, on demand,
        only when -UseSecretStore is passed.

        Installing modules from the gallery onto somebody's machine is not something to do
        quietly, so it happens only under the explicit -UseSecretStore opt-in, is announced,
        and goes to CurrentUser scope so it needs no elevation.

        The vault is configured with Interaction disabled and a password supplied
        programmatically. Without that, SecretStore prompts on first access, which deadlocks
        any non-interactive run - the exact scenario a lab automation module exists for.

    .PARAMETER VaultName
        The vault to register or reuse

    .PARAMETER VaultPassword
        Password for the vault. A default is used when none is supplied, for the same reason
        the seeded users have a known weak password: this protects lab credentials on a machine
        you already control, and prompting would defeat automation.

    .PARAMETER Install
        Install the SecretManagement and SecretStore modules if they are missing

    .OUTPUTS
        PSCustomObject with VaultName, Created and Available

    .EXAMPLE
        Initialize-OktaTestSecretVault -VaultName 'OktaTestEnvironment' -Install

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Default lab vault password; -VaultPassword overrides it.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$Install
    )

    $result = [PSCustomObject]@{ VaultName = $VaultName; Created = $false; Available = $false }

    foreach ($required in @('Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore')) {
        if (Get-Module -ListAvailable -Name $required) { continue }

        if (-not $Install) {
            throw ("$required is not installed. Re-run with -UseSecretStore to have it " +
                "installed automatically, or install it yourself with " +
                "Install-Module $required -Scope CurrentUser.")
        }

        if (-not $PSCmdlet.ShouldProcess($required, 'Install module from the PowerShell Gallery')) {
            throw "$required is required for -UseSecretStore and was not installed."
        }

        Write-OktaTestProgress -Message "Installing $required from the PowerShell Gallery..." -Type Info
        Install-Module -Name $required -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop -Verbose:$false
    Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop -Verbose:$false

    if (-not $VaultPassword) {
        $VaultPassword = ConvertTo-SecureString -String 'OktaTestEnvironmentPassword' -AsPlainText -Force
    }

    # Interaction None is the part that matters. Left at the default, SecretStore prompts for
    # the password on first access, and a prompt in a script that was meant to run unattended
    # is indistinguishable from a hang.
    $storeConfig = @{
        Authentication  = 'Password'
        Password        = $VaultPassword
        Interaction     = 'None'
        Confirm         = $false
        ErrorAction     = 'Stop'
    }

    $existing = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
    if (-not $existing) {
        if (-not $PSCmdlet.ShouldProcess($VaultName, 'Register a SecretStore vault')) {
            return $result
        }

        Set-SecretStoreConfiguration @storeConfig
        Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore `
            -ErrorAction Stop
        $result.Created = $true
        Write-Verbose "Registered SecretStore vault '$VaultName'."
    }

    # Unlocking an already-unlocked store is harmless, and skipping it when the store happens
    # to be locked is not, so this runs either way.
    try {
        Unlock-SecretStore -Password $VaultPassword -ErrorAction Stop
    }
    catch {
        Write-Verbose "SecretStore did not need unlocking: $($_.Exception.Message)"
    }

    $result.Available = $true
    return $result
}
