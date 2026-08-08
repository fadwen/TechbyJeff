function Disconnect-OktaTestEnvironment {
    <#
    .SYNOPSIS
        Clears the stored Okta connection

    .DESCRIPTION
        Drops the API token or access token held in the session. Worth running when you are
        finished, because until you do, the credential sits in a module-scoped variable that
        anything else in the session can read.

        Removing the module clears it too. This exists so you do not have to remove the module
        to drop a credential you no longer want loaded.

    .EXAMPLE
        Disconnect-OktaTestEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

    .LINK
        Connect-OktaTestEnvironment
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([void])]
    param()

    if (-not $script:OktaConnection) {
        Write-Verbose 'No Okta connection to clear.'
        return
    }

    if ($PSCmdlet.ShouldProcess($script:OktaConnection.OrgUrl, 'Clear the stored credential')) {
        $script:OktaConnection = $null
        Write-OktaTestProgress -Message 'Okta connection cleared.' -Type Info
    }
}
