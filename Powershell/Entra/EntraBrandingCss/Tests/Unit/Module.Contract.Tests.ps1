#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The module's shape and its data, checked separately from its behavior.

    The data file is the one thing a future maintainer edits, and the mistakes that are easy
    to make there are silent: a name typed twice, a name on both lists, a count that no longer
    matches the README. This file turns each of those into a failing test.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'EntraBrandingCss.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EntraBrandingCss -Force -ErrorAction SilentlyContinue
}

Describe 'EntraBrandingCss module contract' -Tag 'Unit', 'Contract' {

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop | Should-NotBeNull
    }

    It 'declares no required modules, so file mode runs with nothing installed' {
        @((Test-ModuleManifest -Path $script:ManifestPath).RequiredModules).Count | Should-Be 0
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7 in the manifest' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.PowerShellVersion | Should-Be ([version]'5.1')
        @($manifest.CompatiblePSEditions | Sort-Object) | Should-BeCollection @('Core', 'Desktop')
    }

    It 'exports exactly the public functions' {
        $exported = @((Get-Command -Module EntraBrandingCss -CommandType Function).Name | Sort-Object)
        $exported | Should-BeCollection @('Get-EntraBrandingCssProperty', 'Test-EntraBrandingCss')
    }

    It 'keeps the Graph request function private' {
        Get-Command Invoke-EntraBrandingRequest -ErrorAction SilentlyContinue | Should-BeNull
    }

    It 'declares a named output type on every public function' {
        (Get-Command Test-EntraBrandingCss).OutputType.Name | Should-ContainCollection 'EntraBrandingCss.Result'
        (Get-Command Get-EntraBrandingCssProperty).OutputType.Name |
            Should-ContainCollection 'EntraBrandingCss.Property'
    }

    It 'gives <Name> help with a synopsis and at least three examples' -ForEach @(
        @{ Name = 'Test-EntraBrandingCss' }
        @{ Name = 'Get-EntraBrandingCssProperty' }
    ) {
        $help = Get-Help $Name -Full
        $help.Synopsis | Should-NotBeNull
        $help.Synopsis.Trim() | Should-NotBeEmptyString
        @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
    }

    It 'ships a format file the manifest loads' {
        $view = Get-FormatData -TypeName 'EntraBrandingCss.Result' -PowerShellVersion $PSVersionTable.PSVersion
        $view | Should-NotBeNull
    }
}

Describe 'RetiredProperties.psd1' -Tag 'Unit', 'Contract', 'Data' {

    BeforeAll {
        $script:Data = Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'Data\RetiredProperties.psd1')
        $script:Retired = @($script:Data.Retired)
        $script:Review = @($script:Data.Review)
    }

    It 'holds the 58 names the README counts: 49 Learn bullets plus 9 included longhands' {
        $script:Retired.Count | Should-Be 58
        @($script:Retired | ForEach-Object { $_.Bullet } | Sort-Object -Unique).Count | Should-Be 49
    }

    It 'folds exactly the longhands Learn names under position and margin' {
        $position = @($script:Retired | Where-Object Bullet -eq 'position' | ForEach-Object Property)
        $margin = @($script:Retired | Where-Object Bullet -eq 'margin' | ForEach-Object Property)

        ($position | Sort-Object) | Should-BeCollection @('bottom', 'left', 'position', 'right', 'top', 'z-index')
        ($margin | Sort-Object) |
            Should-BeCollection @('margin', 'margin-bottom', 'margin-left', 'margin-right', 'margin-top')
    }

    It 'attributes every name to one of the three announcements: 19, 28 and 11' {
        $groups = @{}
        foreach ($entry in $script:Retired) {
            $groups[$entry.FirstListedIn] = 1 + [int]$groups[$entry.FirstListedIn]
        }

        $groups['MC1435782'] | Should-Be 19
        $groups['MC1458474'] | Should-Be 28
        $groups['Learn'] | Should-Be 11
        $groups.Keys.Count | Should-Be 3
    }

    It 'lists display and visibility among the names only Learn carries' {
        $learnOnly = @($script:Retired | Where-Object FirstListedIn -eq 'Learn' | ForEach-Object Property)
        $learnOnly | Should-ContainCollection 'display'
        $learnOnly | Should-ContainCollection 'visibility'
    }

    It 'has no name twice, and no name on both lists' {
        $all = @($script:Retired | ForEach-Object Property) + @($script:Review | ForEach-Object Property)
        @($all | Sort-Object -Unique).Count | Should-Be $all.Count
    }

    It 'writes every name in lower case with no surrounding whitespace' {
        $all = @($script:Retired | ForEach-Object Property) + @($script:Review | ForEach-Object Property)
        $all | Should-All { $_ -ceq $_.Trim().ToLowerInvariant() }
    }

    It 'gives every Review entry a reason' {
        $script:Review | Should-All { -not [string]::IsNullOrWhiteSpace($_.Reason) }
    }

    It 'records where the list came from and when it was checked' {
        $script:Data.SourceUrl | Should-MatchString '^https://learn\.microsoft\.com/'
        $script:Data.SourceDate | Should-MatchString '^\d{4}-\d{2}-\d{2}$'
        $script:Data.VerifiedOn | Should-MatchString '^\d{4}-\d{2}-\d{2}$'
    }
}

Describe 'Get-EntraBrandingCssProperty' -Tag 'Unit', 'Public' {

    It 'returns 58 Retired and 9 Review entries by default' {
        $all = @(Get-EntraBrandingCssProperty)
        @($all | Where-Object Level -eq 'Retired').Count | Should-Be 58
        @($all | Where-Object Level -eq 'Review').Count | Should-Be 9
    }

    It 'filters by level' {
        @(Get-EntraBrandingCssProperty -Level Review) | Should-All { $_.Level -eq 'Review' }
        @(Get-EntraBrandingCssProperty -Level Retired).Count | Should-Be 58
    }

    It 'keeps the data file order, so position comes first' {
        @(Get-EntraBrandingCssProperty -Level Retired)[0].Property | Should-Be 'position'
    }

    It 'stamps the typed name and the source on each entry' {
        $entry = @(Get-EntraBrandingCssProperty -Level Retired)[0]
        $entry.PSObject.TypeNames | Should-ContainCollection 'EntraBrandingCss.Property'
        $entry.SourceUrl | Should-MatchString 'learn\.microsoft\.com'
        $entry.SourceDate | Should-MatchString '^\d{4}-\d{2}-\d{2}$'
    }
}
