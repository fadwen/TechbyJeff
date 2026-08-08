function Revoke-OktaTestApiToken {
    <#
    .SYNOPSIS
        Revokes a single Okta API token by id

    .DESCRIPTION
        Deletes the token, which takes effect immediately and cannot be undone. Okta has no
        facility to restore a revoked token or to recreate one with the same value; a
        replacement is a new token, created by hand in the admin console.

        Callers are expected to have resolved the id through Resolve-OktaTestApiToken, so that
        the ambiguity check has already happened. This function takes an id rather than a name
        specifically so that it cannot be the place a wrong guess is made.

    .PARAMETER TokenId
        The id of the token to revoke

    .PARAMETER TokenName
        The token's name, used only to make the confirmation prompt and messages readable

    .OUTPUTS
        Boolean indicating whether the token was revoked

    .EXAMPLE
        Revoke-OktaTestApiToken -TokenId '00T4cxwlhd2fCSwol697' -TokenName 'ci-automation'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TokenId,

        [Parameter()]
        [string]$TokenName
    )

    $label = if ($TokenName) { "'$TokenName' ($TokenId)" } else { $TokenId }

    if (-not $PSCmdlet.ShouldProcess($label, 'Permanently revoke this Okta API token')) {
        return $false
    }

    $null = Invoke-OktaTestRequest -Method DELETE -Path "/api/v1/api-tokens/$TokenId"

    Write-Verbose "Revoked API token $label."
    return $true
}
