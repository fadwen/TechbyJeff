#Requires -Version 7.6

<#
    KrbEtypeInsight - Kerberos encryption type breakage prediction for Active Directory.

    Copyright (C) 2026 EntraVantage LLC.

    This program is free software: you can redistribute it and/or modify it under the terms
    of the GNU General Public License as published by the Free Software Foundation, either
    version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program.
    If not, see <https://www.gnu.org/licenses/>. A copy is included as LICENSE in the module
    root.

    Load order matters and is not alphabetical:

    1. Classes. KrbEtypeEnum.ps1 defines [KrbTicketEtype] and [KrbEtypeFlag]. Function bodies
       reference them at runtime rather than in param() type constraints, which is deliberate:
       a type literal in a parameter attribute is resolved when the file is parsed, and a
       dot-sourced file cannot see a class defined by a sibling file at that moment. Keeping
       the enums out of parameter blocks is what allows the simple dot-source loader below to
       work at all.

    2. Private. The catalogs and converters, which the public functions call unqualified.

    3. Public. Exported last, once everything they depend on exists.

    ActiveDirectory is deliberately NOT declared in RequiredModules. Three of the six public
    functions never touch the directory, and the entire decode and correlation core runs
    against archived .evtx files with no domain present - which is both how the test suite
    exercises it and how an assessment gets done from an analyst's workstation. Declaring the
    dependency in the manifest would make the module fail to import on any machine without
    RSAT, including a Linux CI runner, for the benefit of functions that already import it
    themselves and report a clear error when it is missing.
#>

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing KrbEtypeInsight from: $ModuleRoot"

$loadOrder = @('Classes', 'Private', 'Public')
$loaded = @{}

try {
    foreach ($folder in $loadOrder) {
        $folderPath = Join-Path -Path $ModuleRoot -ChildPath $folder
        if (-not (Test-Path -Path $folderPath)) {
            $loaded[$folder] = 0
            continue
        }

        $files = @(Get-ChildItem -Path $folderPath -Filter '*.ps1' -File -ErrorAction Stop |
            Sort-Object -Property Name)

        foreach ($file in $files) {
            Write-Verbose "Loading $folder component: $($file.Name)"
            . $file.FullName
        }

        $loaded[$folder] = $files.Count
    }

    Write-Verbose ("KrbEtypeInsight loaded - classes: $($loaded['Classes']), " +
        "private: $($loaded['Private']), public: $($loaded['Public'])")
}
catch {
    # A partially loaded module is worse than no module: functions resolve, calls succeed,
    # and results are silently wrong because a catalog the decoder depends on never got
    # defined. Fail the import instead.
    Write-Error "Failed to load KrbEtypeInsight components: $($_.Exception.Message)"
    throw
}

# Explicit, not derived from the file listing. The export boundary is the module's contract
# and changing it should require editing this list and the manifest together, not merely
# adding a file to Public.
Export-ModuleMember -Function @(
    'ConvertFrom-KrbEtype'
    'Get-KrbEvent'
    'Get-KrbPrincipalEtype'
    'Get-KrbDomainEtypeContext'
    'Get-KrbEtypeRisk'
    'Export-KrbEtypeReport'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose 'Cleaning up KrbEtypeInsight'
    Remove-Variable -Name KrbEtypeCatalog -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name KrbProtocolCatalog -Scope Script -ErrorAction SilentlyContinue
}
