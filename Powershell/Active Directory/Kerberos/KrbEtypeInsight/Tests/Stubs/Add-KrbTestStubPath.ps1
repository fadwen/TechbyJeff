<#
.SYNOPSIS
    Makes the stub module discoverable so the suites can run without RSAT.

.DESCRIPTION
    The suites under Tests/Unit mock every directory call they make, so they never touch a
    domain. Pester has a problem from the other side, though: it cannot mock a command that
    does not exist, so "Mock Get-ADDomain" fails outright on a host without RSAT and takes
    the whole Describe block with it.

    This appends the Stubs directory to PSModulePath, which is enough to make the mocks
    attach. Appending rather than prepending is deliberate: a host that has the real RSAT
    keeps using it and the suite exercises the true binding surface, while a workstation
    without it falls back to the stub.

    The stub does not weaken anything. Every command a test relies on is still mocked; the
    stub only makes the command exist so the mock can be attached.

.EXAMPLE
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-KrbTestStubPath.ps1')

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding()]
param()

$stubRoot = $PSScriptRoot
$separator = [System.IO.Path]::PathSeparator
$current = @($env:PSModulePath -split $separator | Where-Object { $_ })

if ($current -notcontains $stubRoot) {
    $env:PSModulePath = (@($current) + $stubRoot) -join $separator
    Write-Verbose "Appended stub module path: $stubRoot"
}
