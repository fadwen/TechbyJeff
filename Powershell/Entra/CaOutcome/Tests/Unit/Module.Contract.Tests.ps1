#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The module's shape, checked separately from its behaviour.

    The manifest and the psm1 both name the exported functions, and nothing enforces that the
    two lists agree. Getting them out of step is silent: the manifest wins on import, so a
    function added to Export-ModuleMember and forgotten in FunctionsToExport simply is not
    there, and every test of it fails somewhere confusing instead of here.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'CaOutcome.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module CaOutcome -Force -ErrorAction SilentlyContinue
}

Describe 'CaOutcome module contract' -Tag 'Unit', 'Contract' {

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop | Should-NotBeNull
    }

    It 'declares no required modules, so it runs on a host with nothing installed' {
        # The point of a pure transform is that it needs no Graph SDK and no connection. A
        # RequiredModules entry creeping in would break running this in a bare CI container.
        @((Test-ModuleManifest -Path $script:ManifestPath).RequiredModules).Count | Should-Be 0
    }

    It 'exports exactly the public functions' {
        $exported = @((Get-Command -Module CaOutcome -CommandType Function).Name | Sort-Object)
        $exported | Should-BeCollection @(
            'Compare-CaBaseline'
            'ConvertTo-CaOutcome'
            'Expand-CaScenario'
            'Export-CaBaseline'
            'Invoke-CaScenarioMatrix'
        )
    }

    It 'gives every public function comment-based help with worked examples' {
        foreach ($command in (Get-Command -Module CaOutcome -CommandType Function)) {
            $help = Get-Help $command.Name -Full
            $help.Synopsis | Should-NotBeWhiteSpaceString
            @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
        }
    }

    It 'supports -WhatIf on the one function that writes anything' {
        Get-Command Export-CaBaseline | Should-HaveParameter 'WhatIf'
    }

    It 'keeps every private function private' {
        Get-Command -Module CaOutcome -Name 'Get-CaEffectiveControl' -ErrorAction SilentlyContinue |
            Should-BeNull
    }

    It 'gives the public function comment-based help with worked examples' {
        $help = Get-Help ConvertTo-CaOutcome -Full
        $help.Synopsis | Should-NotBeWhiteSpaceString
        @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
    }
}
