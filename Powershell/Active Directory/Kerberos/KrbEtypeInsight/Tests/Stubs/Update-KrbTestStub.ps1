<#
.SYNOPSIS
    Regenerates the KrbEtypeInsight test stub module from the real cmdlets.

.DESCRIPTION
    Reads the parameter surface of the real ActiveDirectory cmdlets this module's suites
    mock, and writes an empty-bodied stub function for each. Run this on a host that
    actually has RSAT - a domain controller - then commit the result. See README.md beside
    this script for why the stubs exist.

    Parameter types are carried over only where the type ships with PowerShell itself. The
    AD types live in assemblies a CI runner has no way to load, so those parameters are
    emitted untyped and bind as [object].

.PARAMETER OutputPath
    Directory to write the stub module folder into. Defaults to this script's directory.

.EXAMPLE
    .\Update-KrbTestStub.ps1 -OutputPath .
    Regenerates the stub in place.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

Import-Module ActiveDirectory

$common = [System.Management.Automation.PSCmdlet]::CommonParameters +
          [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

# Only the cmdlets the suites actually mock. Keeping the list explicit stops the stub
# drifting into a module-wide mirror of RSAT. Every name here appears in a
# "Mock -ModuleName KrbEtypeInsight" line under Tests/Unit.
$sets = [ordered]@{
    'ActiveDirectory' = @(
        'Get-ADDomain', 'Get-ADDomainController', 'Get-ADForest', 'Get-ADObject'
        'Get-ADTrust', 'Get-ADUser'
    )
}

$safeType = @(
    [string], [string[]], [bool], [bool[]], [int], [int[]], [long], [switch]
    [System.Security.SecureString], [System.Management.Automation.PSCredential]
    [timespan], [datetime], [guid], [hashtable], [byte[]], [scriptblock]
)

$header = @(
    '# GENERATED FILE - do not edit by hand. See Tests/Stubs/README.md.'
    '#'
    '# A stand-in for RSAT, so Pester can mock commands that would otherwise not exist on'
    '# a host without it. Every function is empty: it exists only to reproduce the real'
    '# binding surface, so a call the real cmdlet would reject fails here too. Parameter'
    '# types are carried over wherever the type ships with PowerShell itself.'
    '#'
    '# The suppressions below are the point of the file, not an oversight. The parameters'
    '# are deliberately unused, and a body-less function has nothing to guard.'
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',"
    "    Justification = 'Stub parameters reproduce real cmdlet binding surfaces.')]"
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',"
    "    Justification = 'Stubs have no body to guard; the attribute mirrors the real cmdlet.')]"
    'param()'
    ''
)

foreach ($moduleName in $sets.Keys) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $header | ForEach-Object { $lines.Add($_) }

    foreach ($name in $sets[$moduleName]) {
        $cmd = Get-Command $name

        $params = $cmd.Parameters.GetEnumerator() |
            Where-Object { $common -notcontains $_.Key } |
            Sort-Object Key

        $lines.Add("function $name {")
        $lines.Add('    [CmdletBinding()]')
        $lines.Add('    param(')

        $decl = foreach ($p in $params) {
            $type = $p.Value.ParameterType
            $inner = [Nullable]::GetUnderlyingType($type)

            if ($inner -and $safeType -contains $inner) {
                "        [System.Nullable[$($inner.FullName)]]`$$($p.Key)"
            }
            elseif ($safeType -contains $type) {
                "        [$($type.FullName)]`$$($p.Key)"
            }
            else {
                "        `$$($p.Key)"
            }
        }

        $lines.Add(($decl -join ",`n"))
        $lines.Add('    )')
        $lines.Add('}')
        $lines.Add('')
    }

    $lines.Add('Export-ModuleMember -Function @(')
    $lines.Add((($sets[$moduleName] | ForEach-Object { "    '$_'" }) -join ",`n"))
    $lines.Add(')')

    $outDir = Join-Path $OutputPath $moduleName
    if ($PSCmdlet.ShouldProcess($outDir, 'Write stub module')) {
        $null = New-Item -ItemType Directory -Force -Path $outDir
        $target = Join-Path $outDir "$moduleName.psm1"
        Set-Content -LiteralPath $target -Value ($lines -join "`n") -Encoding UTF8
        Write-Verbose "Wrote $target"
    }
}
