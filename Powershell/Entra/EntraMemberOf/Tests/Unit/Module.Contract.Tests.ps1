#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The module's shape and its data, checked separately from its behavior.

    Data/MemberOfRules.psd1 is the one file a maintainer edits when Microsoft changes the
    date, a limit or the guidance, and the mistakes that are easy to make there are silent: a
    dynamic expression Import-PowerShellDataFile refuses, a Review code typed twice, a date in
    the wrong shape. Each becomes a failing test here.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'EntraMemberOf.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EntraMemberOf -Force -ErrorAction SilentlyContinue
}

Describe 'EntraMemberOf module contract' -Tag 'Unit', 'Contract' {

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop | Should-NotBeNull
    }

    It 'declares no required modules, so rule text and file mode run with nothing installed' {
        @((Test-ModuleManifest -Path $script:ManifestPath).RequiredModules).Count | Should-Be 0
    }

    It 'targets PowerShell 7.4 or later, Core edition only' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.PowerShellVersion | Should-Be ([version]'7.4')
        @($manifest.CompatiblePSEditions) | Should-BeCollection @('Core')
    }

    It 'exports exactly the public function' {
        @((Get-Command -Module EntraMemberOf -CommandType Function).Name) |
            Should-BeCollection @('Test-EntraMemberOfRule')
    }

    It 'keeps the Graph request function private' {
        Get-Command Invoke-EntraMemberOfRequest -ErrorAction SilentlyContinue | Should-BeNull
    }

    It 'declares both output types on the public function' {
        $names = (Get-Command Test-EntraMemberOfRule).OutputType.Name
        $names | Should-ContainCollection 'EntraMemberOf.Result'
        $names | Should-ContainCollection 'EntraMemberOf.Summary'
    }

    It 'gives the public function help with a synopsis and at least three examples' {
        $help = Get-Help Test-EntraMemberOfRule -Full
        $help.Synopsis.Trim() | Should-NotBeEmptyString
        @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
    }

    It 'ships format views for both output types' {
        $version = $PSVersionTable.PSVersion
        Get-FormatData -TypeName 'EntraMemberOf.Result' -PowerShellVersion $version | Should-NotBeNull
        Get-FormatData -TypeName 'EntraMemberOf.Summary' -PowerShellVersion $version | Should-NotBeNull
    }
}

Describe 'MemberOfRules.psd1' -Tag 'Unit', 'Contract', 'Data' {

    BeforeAll {
        $script:DataPath = Join-Path $script:ModuleRoot 'Data\MemberOfRules.psd1'
        $script:Data = Import-PowerShellDataFile $script:DataPath
    }

    It 'loads with Import-PowerShellDataFile, so it holds literals only' {
        $script:Data | Should-NotBeNull
        $script:Data.RetirementDate | Should-Be '2026-11-03'
    }

    It 'names the two documented properties and the documented form' {
        @($script:Data.Retired.Properties) | Should-BeCollection @('user.memberOf', 'device.memberOf')
        $script:Data.Retired.SourceProperty | Should-Be 'group.objectId'
        $script:Data.Retired.Quantifier | Should-Be 'any'
        $script:Data.Retired.Operator | Should-Be 'in'
    }

    It 'carries the documented limits' {
        $script:Data.Limits.MemberOfGroupsPerTenant | Should-Be 500
        $script:Data.Limits.SourceGroupsPerGroup | Should-Be 50
        $script:Data.Limits.DynamicGroupsPerTenant | Should-Be 15000
    }

    It 'quotes the retirement effect with the date in it' {
        $script:Data.RetirementEffect | Should-MatchString 'November 3, 2026'
        $script:Data.RetirementEffect | Should-MatchString 'stop updating'
    }

    It 'has a reason for every Review code, and no code twice' {
        $codes = @($script:Data.Review | ForEach-Object Code)
        @($codes | Sort-Object -Unique).Count | Should-Be $codes.Count
        $script:Data.Review | Should-All { -not [string]::IsNullOrWhiteSpace($_.Reason) }
        ($codes | Sort-Object) |
            Should-BeCollection @('MemberOfAsOperator', 'StringLiteral', 'UnparsedRule', 'UnqualifiedMemberOf')
    }

    It 'has a remediation sentence for every object kind the scanner emits' {
        foreach ($kind in 'Group', 'AdministrativeUnit', 'AutoAssignmentPolicy', 'Rule') {
            $script:Data.Remediation[$kind] | Should-NotBeNull
            $script:Data.Remediation[$kind].Trim() | Should-NotBeEmptyString
        }
    }

    It 'records where the data came from and when it was checked' {
        $script:Data.SourceUrl | Should-MatchString '^https://learn\.microsoft\.com/'
        $script:Data.SourceDate | Should-MatchString '^\d{4}-\d{2}-\d{2}$'
        $script:Data.VerifiedOn | Should-MatchString '^\d{4}-\d{2}-\d{2}$'
        $script:Data.MessageCenterId | Should-MatchString '^MC\d+$'
    }

    It 'is read once into a catalog with lower-case lookups' {
        InModuleScope EntraMemberOf {
            $catalog = Get-MemberOfRuleCatalog
            $catalog.RetiredProperties | Should-BeCollection @('user.memberof', 'device.memberof')
            $catalog.SourceProperty | Should-Be 'group.objectid'
            $catalog.Review.Keys | Should-ContainCollection 'UnparsedRule'
            [object]::ReferenceEquals($catalog, (Get-MemberOfRuleCatalog)) | Should-BeTrue
        }
    }
}
