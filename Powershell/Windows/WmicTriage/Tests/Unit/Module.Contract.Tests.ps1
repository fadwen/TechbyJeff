#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The contract between the module and everything that consumes it.

    Two things are worth pinning here beyond the usual manifest checks.

    The export boundary, because this module is meant to be read as well as run: the engine holds
    no WMIC knowledge, and that claim is only true while the private helpers stay private. An
    accidental export turns an internal shape into something somebody scripts against.

    The ruleset integrity, because the whole extensibility story is "a new detection is a data
    change". That is a promise about failure modes as much as about effort. A rule with a typo in
    its Match key would never fire, and a scanner that quietly returns fewer findings than it
    should is worse than one that will not start - it will be believed. So every one of those
    mistakes has to be an error at load time, and these tests are what keep it that way.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'WmicTriage.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
}

Describe 'WmicTriage module contract' -Tag 'Unit' {

    Context 'manifest' {

        It 'is a valid module manifest' {
            $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
            $manifest.Name | Should-Be 'WmicTriage'
        }

        It 'targets Windows PowerShell as well as Core' {
            # The estates that still run WMIC are the ones whose build servers never got pwsh
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $manifest.PowerShellVersion | Should-Be '5.1'
            $manifest.CompatiblePSEditions | Should-ContainCollection @('Desktop', 'Core') -IgnoreOrder
        }

        It 'declares no required modules' {
            # Scanning is text and XML parsing. A dependency here would stop the tool running on
            # the build agent that most needs it.
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            @($manifest.RequiredModules).Count | Should-Be 0
        }
    }

    Context 'export boundary' {

        It 'exports exactly the three public functions' {
            $exported = @((Get-Command -Module WmicTriage).Name | Sort-Object)
            $exported | Should-BeCollection @('Export-WmicScanReport', 'Get-WmicRule', 'Invoke-WmicScan')
        }

        It 'keeps every private helper private' {
            $private = Get-ChildItem (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1'
            foreach ($file in $private) {
                $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
                Get-Command -Module WmicTriage -Name $name -ErrorAction SilentlyContinue |
                    Should-BeNull -Because "$name is a private helper"
            }
        }

        It 'names every public function in the manifest' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $public = @(Get-ChildItem (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1' |
                    ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
            @($manifest.FunctionsToExport) | Should-ContainCollection $public -IgnoreOrder
        }
    }

    Context 'comment-based help' {

        It 'gives <Name> a synopsis, a description and at least three examples' -ForEach @(
            @{ Name = 'Invoke-WmicScan' }
            @{ Name = 'Export-WmicScanReport' }
            @{ Name = 'Get-WmicRule' }
        ) {
            $help = Get-Help -Name $Name -Full
            [string]$help.Synopsis | Should-NotBeEmptyString
            ($help.Description.Text -join '') | Should-NotBeEmptyString
            @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
        }
    }

    Context 'ruleset integrity' {

        It 'loads every rule' {
            @(Get-WmicRule).Count | Should-BeGreaterThan 20
        }

        It 'gives every rule an id, a name, a reason and a suggestion' {
            foreach ($rule in Get-WmicRule) {
                [string]$rule.Id | Should-NotBeEmptyString
                [string]$rule.Name | Should-NotBeEmptyString
                [string]$rule.Reason | Should-NotBeEmptyString
                [string]$rule.Suggestion | Should-NotBeEmptyString
            }
        }

        It 'uses each rule id only once' {
            # Ids appear in SARIF and in anything anyone builds on this
            $ids = @((Get-WmicRule).Id)
            @($ids | Select-Object -Unique).Count | Should-Be $ids.Count
        }

        It 'covers all four tiers' {
            foreach ($tier in 'Mechanical', 'Wrapped', 'Semantic', 'Environmental') {
                @(Get-WmicRule -Tier $tier).Count | Should-BeGreaterThan 0 -Because "$tier needs a rule"
            }
        }

        It 'joins multi-line reasons into one line of prose' {
            # They are arrays in the data file only because a .psd1 cannot concatenate strings
            foreach ($rule in Get-WmicRule) {
                $rule.Reason | Should-HaveType ([string])
                $rule.Reason | Should-NotMatchString "`n"
            }
        }
    }
}
