<#
.SYNOPSIS
    Defines placeholder ActiveDirectory cmdlets when the RSAT module is not installed.

.DESCRIPTION
    Pester 3.4 can only mock a command that already exists. Every test that mocks an
    ActiveDirectory cmdlet therefore fails with "Could not find Command Get-ADObject" on a
    machine without RSAT. Dot-source this file before the first Mock and the cmdlets exist as
    global functions that throw if a test ever reaches them unmocked.

    Nothing is defined when the real module is available, so the stubs never shadow it.

.EXAMPLE
    . "$PSScriptRoot\..\..\TestHelpers\ADCmdletStubs.ps1"
    Mock Get-ADObject { @() }

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

$adCmdletNames = @(
    'Get-ADDomain'
    'Get-ADDomainController'
    'Get-ADObject'
    'Set-ADObject'
    'Remove-ADObject'
    'Get-ADUser'
    'New-ADUser'
    'Set-ADUser'
    'Get-ADTrust'
    'Get-ADRootDSE'
    'Test-ADServiceAccount'
)

foreach ($cmdletName in $adCmdletNames) {
    if (Get-Command -Name $cmdletName -ErrorAction SilentlyContinue) {
        continue
    }

    # One body for every stub: the name is read back from the invocation so the error says
    # which cmdlet a test reached without mocking it.
    $body = {
        param([Parameter(ValueFromRemainingArguments)]$Arguments)
        $name = $MyInvocation.MyCommand.Name
        $count = @($Arguments).Count
        throw "$name stub: the ActiveDirectory module is not installed and this call ($count argument(s)) was not mocked"
    }

    Set-Item -Path "function:global:$cmdletName" -Value $body
}
