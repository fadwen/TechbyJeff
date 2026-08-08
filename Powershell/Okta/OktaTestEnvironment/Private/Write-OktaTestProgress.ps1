function Write-OktaTestProgress {
    <#
    .SYNOPSIS
        Writes standardised progress messages for Okta test environment operations

    .DESCRIPTION
        Provides consistent console formatting during seed and teardown operations. Results
        are still returned as objects; this is display only.

    .PARAMETER Message
        The progress message to display

    .PARAMETER Type
        Type of message (Info, Warning, Error, Success, Header)

    .EXAMPLE
        Write-OktaTestProgress -Message 'Creating users...' -Type Info

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console progress display is the entire purpose of this function.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Header')]
        [string]$Type = 'Info'
    )

    switch ($Type) {
        'Header' {
            Write-Host "`n=========================================" -ForegroundColor Cyan
            Write-Host "   $Message" -ForegroundColor Cyan
            Write-Host "=========================================" -ForegroundColor Cyan
        }
        'Info'    { Write-Host $Message -ForegroundColor Green }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}
