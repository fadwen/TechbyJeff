function Get-OktaTestCredentialPath {
    <#
    .SYNOPSIS
        Resolves where the service app's private key is stored

    .DESCRIPTION
        The default is a per-user folder outside the repository. That location is chosen so
        the private key cannot be committed by accident: a path under the module directory
        would sit inside a working tree, one .gitignore edit away from being published.

        The file name carries the org host, so credentials for two different tenants do not
        overwrite each other.

    .PARAMETER OrgUrl
        The org URL the credential belongs to

    .PARAMETER Path
        An explicit path, which is returned unchanged. Present so callers can pass a
        user-supplied -CredentialPath straight through without branching.

    .OUTPUTS
        String path to the credential file

    .EXAMPLE
        Get-OktaTestCredentialPath -OrgUrl 'https://trial-123456.okta.com'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OrgUrl,

        [Parameter()]
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $profileFolder = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($profileFolder)) { $profileFolder = $env:HOME }
    if ([string]::IsNullOrWhiteSpace($profileFolder)) {
        throw 'Could not determine the user profile folder. Pass -CredentialPath explicitly.'
    }

    $orgHost = ([uri]$OrgUrl).Host
    if ([string]::IsNullOrWhiteSpace($orgHost)) {
        throw "'$OrgUrl' is not a usable org URL; it has no host component."
    }

    return (Join-Path -Path (Join-Path -Path $profileFolder -ChildPath '.oktatestenvironment') `
        -ChildPath "$orgHost.serviceapp.json")
}
