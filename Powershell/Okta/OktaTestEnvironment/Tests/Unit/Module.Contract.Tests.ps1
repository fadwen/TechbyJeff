#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the module itself - manifest, exports and layout.

    Each of these corresponds to a defect that shows up in modules of this shape: a private
    helper that silently shadows a cmdlet introduced in a later PowerShell version, two files
    holding three functions between them against an otherwise one-function-per-file layout, and
    a function exported from the root module but absent from the manifest, which exports nothing
    and fails only when somebody calls it.

    They are cheap, they need no tenant, and they catch the class of mistake that is invisible
    until the module is in use.

    There are no stubs to load. This module declares no RequiredModules and calls nothing that
    is absent from a stock host, so it imports on a bare CI runner as-is.
#>

BeforeDiscovery {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent

    # Built at discovery time so each file gets its own -ForEach case and a failure names the
    # file rather than burying it in one aggregate assertion.
    $script:FunctionFile = @(
        Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public'), (Join-Path $script:ModuleRoot 'Private') `
            -Filter *.ps1 -ErrorAction SilentlyContinue |
            ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName; BaseName = $_.BaseName } }
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:Manifest = Join-Path $script:ModuleRoot 'OktaTestEnvironment.psd1'

    Import-Module $script:Manifest -Force

    function Get-FunctionNameFromFile {
        param([string]$Path)

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        return @($ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    }
}

AfterAll {
    Remove-Module OktaTestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'Module manifest' -Tag 'Unit', 'Contract' {

    It 'is a valid manifest' {
        # Pester 6 has no Should-Not-Throw. Running the command is the assertion: anything it
        # throws fails the test, with the real error rather than a wrapped one.
        $manifestData = Test-ModuleManifest -Path $script:Manifest -ErrorAction Stop
        $manifestData.Name | Should-Be 'OktaTestEnvironment'
    }

    It 'declares both editions it claims to support' {
        $data = Import-PowerShellDataFile -Path $script:Manifest
        $data.CompatiblePSEditions | Should-BeCollection @('Desktop', 'Core')
    }

    It 'exports exactly what the root module exports' {
        # A name in one list and not the other is invisible until somebody calls it. The root
        # module's list is read from its AST rather than by regex, so a name that appears in a
        # comment or a verbose message cannot be mistaken for an export.
        $fromManifest = @((Import-PowerShellDataFile -Path $script:Manifest).FunctionsToExport) | Sort-Object

        $rootModulePath = Join-Path $script:ModuleRoot 'OktaTestEnvironment.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($rootModulePath, [ref]$null, [ref]$null)
        $exportCall = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Export-ModuleMember'
        }, $true))

        $exportCall.Count | Should-Be 1

        # Skip the first command element: it is the literal 'Export-ModuleMember', which
        # matches the verb-noun shape as readily as anything it exports.
        $fromRoot = @(@($exportCall[0].CommandElements) | Select-Object -Skip 1 | ForEach-Object {
            $_.FindAll({
                param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)
        } | ForEach-Object { $_.Value } | Where-Object { $_ -match '^[A-Za-z]+-[A-Za-z]+$' }) |
            Sort-Object -Unique

        $missing = @($fromManifest | Where-Object { $fromRoot -notcontains $_ })
        $extra = @($fromRoot | Where-Object { $fromManifest -notcontains $_ })

        "$($missing -join ',')|$($extra -join ',')" | Should-Be '|'
    }

    It 'exports every file in Public and nothing from Private' {
        $exported = @((Get-Command -Module OktaTestEnvironment).Name) | Sort-Object
        $public = @(Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public') -Filter *.ps1 |
            ForEach-Object { $_.BaseName }) | Sort-Object

        $exported | Should-BeCollection $public
    }

    It 'declares no required modules' {
        # The module's selling point on a locked-down host is that it installs nothing. A
        # RequiredModules entry added later would break that quietly, since it only fails on a
        # machine that lacks the module.
        $data = Import-PowerShellDataFile -Path $script:Manifest
        @($data.RequiredModules).Count | Should-Be 0
    }
}

Describe 'Function layout' -Tag 'Unit', 'Contract' {

    It '<Name> holds exactly one function' -ForEach $script:FunctionFile {
        $found = Get-FunctionNameFromFile -Path $FullName
        $found.Count | Should-Be 1
    }

    It '<Name> defines a function matching its file name' -ForEach $script:FunctionFile {
        $found = Get-FunctionNameFromFile -Path $FullName
        $found[0].Name | Should-Be $BaseName
    }

    It '<Name> parses without error' -ForEach $script:FunctionFile {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$parseErrors)
        @($parseErrors).Count | Should-Be 0
    }
}

Describe 'Command name safety' -Tag 'Unit', 'Contract' {

    It '<BaseName> does not shadow a built-in cmdlet' -ForEach $script:FunctionFile {
        # A module claiming both Desktop and Core support has to be checked on whichever
        # edition the suite is running on, because the cmdlet set differs between them.
        $builtIn = Get-Command -Name $BaseName -CommandType Cmdlet -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -ne 'OktaTestEnvironment' }

        $builtIn | Should-BeNull
    }
}

Describe 'Seed data' -Tag 'Unit', 'Contract' {

    BeforeAll {
        $script:DataPath = Join-Path $script:ModuleRoot 'Data'
        $script:Users = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaUsers.csv') -Encoding UTF8)
        $script:Groups = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaGroups.csv') -Encoding UTF8)
        $script:Rules = @(Import-Csv -Path (Join-Path $script:DataPath 'OktaGroupRules.csv') -Encoding UTF8)
        $script:Attributes = @(
            Import-Csv -Path (Join-Path $script:DataPath 'OktaProfileAttributes.csv') -Encoding UTF8)
    }

    It 'ships exactly eight users, which is what the ten user licence leaves room for' {
        # The single most important number in this module. Nine would leave no slot for a
        # second admin; eleven would fail on creation with a licence error partway through.
        $script:Users.Count | Should-Be 8
    }

    It 'keeps every login ASCII even where the display name is not' {
        # A real directory has accented display names and plain logins. Getting this backwards
        # produces users who cannot sign in and URLs that need escaping everywhere.
        $nonAscii = @($script:Users | Where-Object { $_.LoginPrefix -notmatch '^[a-z0-9._-]+$' })
        @($nonAscii).Count | Should-Be 0
    }

    It 'ships display names that are not all ASCII' {
        # The counterpart: if somebody "cleans up" the accents, the encoding bugs these users
        # exist to expose stop being reachable.
        $accented = @($script:Users | Where-Object { $_.DisplayName -match '[^\x00-\x7F]' })
        @($accented).Count | Should-BeGreaterThan 0
    }

    It 'gives every manager reference a user that exists' {
        $logins = @($script:Users.LoginPrefix)
        $dangling = @($script:Users |
            Where-Object { $_.ManagerLoginPrefix -and $logins -notcontains $_.ManagerLoginPrefix })

        @($dangling).Count | Should-Be 0
    }

    It 'gives every group member a user that exists' {
        $logins = @($script:Users.LoginPrefix)
        $dangling = foreach ($group in $script:Groups) {
            foreach ($member in @($group.Members -split ';' | Where-Object { $_ })) {
                if ($logins -notcontains $member) { "$($group.Name):$member" }
            }
        }

        @($dangling) | Should-BeCollection @()
    }

    It 'gives every group rule a target group that exists' {
        $groupNames = @($script:Groups.Name)
        $dangling = @($script:Rules | Where-Object { $groupNames -notcontains $_.TargetGroup })

        @($dangling).Count | Should-Be 0
    }

    It 'gives every user a lifecycle state the module knows how to create' {
        # This is a column alignment test wearing a different hat, and it earned its place:
        # one missing empty field in the middle of a 34 column row shifted six users by one,
        # which Import-Csv reports as nothing at all. The symptom was a blank lifecycle state,
        # and blank happens to fall through to "create it active", so nothing failed.
        $valid = @('Active', 'Staged', 'Suspended')
        $bad = @($script:Users | Where-Object { $valid -notcontains $_.LifecycleState })

        @($bad).Count | Should-Be 0
    }

    It 'keeps every boolean column parseable as a boolean' {
        # The same alignment failure from the other end of the row.
        $bad = @($script:Users | Where-Object { $_.LabIsContractor -notin @('TRUE', 'FALSE') })
        @($bad).Count | Should-Be 0
    }

    It 'ships all three lifecycle states, not just the easy one' {
        @($script:Users | Where-Object { $_.LifecycleState -eq 'Staged' }).Count | Should-Be 1
        @($script:Users | Where-Object { $_.LifecycleState -eq 'Suspended' }).Count | Should-Be 1
    }

    It 'ships a user with a risk score of zero' {
        # Zero is falsy in PowerShell, so a guard written as "if ($value)" drops it silently.
        # The attribute only tests that if a user actually carries the value.
        @($script:Users | Where-Object { $_.LabRiskScore -eq '0' }).Count | Should-BeGreaterThan 0
    }

    It 'ships a user with no entitlements and a user with several' {
        # An array attribute that is always populated does not exercise the empty case, and an
        # array that is always a single value does not exercise the join.
        @($script:Users | Where-Object { -not $_.LabEntitlements }).Count | Should-BeGreaterThan 0
        @($script:Users | Where-Object { @($_.LabEntitlements -split ';').Count -gt 1 }).Count |
            Should-BeGreaterThan 0
    }

    It 'covers more than one attribute type, which is the point of the custom schema' {
        # A schema of nothing but strings would not exercise the array, boolean and numeric
        # handling that flat exports actually break on.
        $types = @($script:Attributes.Type | Sort-Object -Unique)
        @($types).Count | Should-BeGreaterThan 2
    }

    It 'defines the seed tag teardown identifies users by' {
        @($script:Attributes.Name) | Should-ContainCollection 'labSeedTag'
    }

    It 'leaves the rule-driven groups with no manual members' {
        # A rule group with manual members cannot tell you whether the rule is working, which
        # is the only reason those groups exist.
        $contaminated = @($script:Groups | Where-Object { $_.Assignment -eq 'Rule' -and $_.Members })
        @($contaminated).Count | Should-Be 0
    }
}
