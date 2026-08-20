#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The tier decisions, end to end, over the fixture corpus.

    These are the tests worth having. The module's output is a classification, so a scan that runs
    without error and puts a finding in the wrong tier has failed completely while looking fine -
    and the two ways it can be wrong are not symmetric.

    Over-reporting Wrapped is the cheaper failure and still expensive: it sends somebody to
    restructure a block that only needed a one-line swap, and after that happens twice nobody
    believes the tier again. Under-reporting it is the one that costs money, because a Wrapped
    call migrated as though it were Mechanical does not break. The for /f keeps running against
    an object it was never written for, sets its variables from whatever the token positions now
    land on, and the report it feeds looks exactly as plausible as it did last week.

    So the sharpest test here is the pair on Wrapped.cmd: the call in a for /f in-clause must be
    Wrapped, and the call in that same block's do-body must not be. Only the first has its output
    parsed. Marking the whole block Wrapped is the easier implementation and the one that quietly
    inflates the number the tool exists to report.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force
    $script:FixtureRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures'

    $script:Findings = @(Invoke-WmicScan -Path $script:FixtureRoot)

    function global:Get-Finding {
        param([string]$File, [int]$Line, [string]$Kind = 'Deprecation')
        @($script:Findings | Where-Object {
                $_.RelativePath -eq $File -and $_.Line -eq $Line -and $_.Kind -eq $Kind
            })[0]
    }
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:Get-Finding' -ErrorAction SilentlyContinue
}

Describe 'Invoke-WmicScan' -Tag 'Unit', 'Public' {

    Context 'the Wrapped tier' {

        It 'reports a call whose output a for /f block parses as Wrapped' {
            $finding = Get-Finding -File 'Wrapped.cmd' -Line 2
            $finding.Tier | Should-Be 'Wrapped'
            $finding.Structure | Should-Be 'ForBlock'
        }

        It 'does not treat a call merely running inside the block as Wrapped' {
            # Wrapped.cmd line 6 sits in the do-body of the block that starts on line 4. The
            # block does not parse its output - it only runs there - so it is an ordinary swap.
            $finding = Get-Finding -File 'Wrapped.cmd' -Line 6
            $finding.Tier | Should-Be 'Mechanical'
            $finding.Structure | Should-Be 'Line'
        }

        It 'spans the whole block rather than the line the command is on' {
            # The tokens= spec is what has to be rewritten, and it is not always on the same line
            $finding = Get-Finding -File 'Wrapped.cmd' -Line 4
            $finding.StartLine | Should-Be 4
            $finding.EndLine | Should-BeGreaterThan 4
        }

        It 'records the token spec that has to be rewritten' {
            $finding = Get-Finding -File 'Wrapped.cmd' -Line 2
            $finding.ForOptions | Should-BeString 'tokens=2 delims=='
        }

        It 'reports <Because> as Wrapped' -ForEach @(
            @{ Line = 9; Because = 'redirection to a file' }
            @{ Line = 10; Because = 'a pipe into a text tool' }
            @{ Line = 11; Because = 'the /output: switch' }
        ) {
            (Get-Finding -File 'Wrapped.cmd' -Line $Line).Tier | Should-Be 'Wrapped'
        }

        It 'does not invent a redirect from a > inside a quoted where-clause' {
            # wmic process where "workingsetsize > 100000000" get name. Splitting on that > gives
            # a redirect into a file called 100000000, and a Wrapped finding that is not real.
            $finding = Get-Finding -File 'Wrapped.cmd' -Line 12
            $finding.Tier | Should-Be 'Mechanical'
            @($finding.Capture).Count | Should-Be 0
        }

        It 'reads <Expected> capture out of the PowerShell syntax tree' -ForEach @(
            @{ Line = 7; Expected = 'Variable' }
            @{ Line = 8; Expected = 'Pipe' }
            @{ Line = 9; Expected = 'Redirect' }
            @{ Line = 10; Expected = 'Variable' }
        ) {
            $finding = Get-Finding -File 'Capture.ps1' -Line $Line
            $finding.Tier | Should-Be 'Wrapped'
            @($finding.Capture) | Should-ContainCollection @($Expected)
        }
    }

    Context 'the Semantic tier' {

        It 'refuses to treat Win32_Product as a swap' {
            # Enumerating it runs an MSI consistency check whichever command asks for it, so a
            # like-for-like translation keeps the actual problem
            $finding = Get-Finding -File 'Semantic.cmd' -Line 2
            $finding.Tier | Should-Be 'Semantic'
            $finding.RuleId | Should-Be 'WMIC200'
        }

        It 'catches a <Group> property at line <Line>' -ForEach @(
            @{ Line = 3; Group = 'DateTime' }
            @{ Line = 4; Group = 'MultiValue' }
        ) {
            $finding = Get-Finding -File 'Semantic.cmd' -Line $Line
            $finding.Tier | Should-Be 'Semantic'
            @($finding.PropertyGroup) | Should-ContainCollection @($Group)
        }

        It 'mines the where-clause for property names as well as the get' {
            # where "IPEnabled=TRUE" is the Boolean comparison problem, and it never appears
            # after a get
            $finding = Get-Finding -File 'Semantic.cmd' -Line 4
            @($finding.PropertyGroup) | Should-ContainCollection @('Boolean')
        }

        It 'treats a remote /node: call as a protocol change rather than a swap' {
            $finding = Get-Finding -File 'Semantic.cmd' -Line 5
            $finding.Tier | Should-Be 'Semantic'
            $finding.Node | Should-Be 'SRV01'
        }

        It 'classifies <Verb> at line <Line> as Semantic' -ForEach @(
            @{ Line = 6; Verb = 'call' }
            @{ Line = 7; Verb = 'set' }
        ) {
            $finding = Get-Finding -File 'Semantic.cmd' -Line $Line
            $finding.Tier | Should-Be 'Semantic'
            $finding.Verb | Should-Be $Verb
        }

        It 'reports a wmic path held in a variable, and says the call sites are missing' {
            # The one place the tool knows it is incomplete. It says so in the finding rather
            # than only in the documentation, because the report is what gets read.
            $finding = Get-Finding -File 'Indirect.cmd' -Line 2
            $finding.RuleId | Should-Be 'WMIC210'
            $finding.Tier | Should-Be 'Semantic'
            $finding.Reason | Should-MatchString 'undercount'
        }
    }

    Context 'the Environmental tier' {

        It 'escalates every finding in a WinPE script' {
            # startnet.cmd only exists in a boot image, and a boot image has PowerShell only if
            # somebody added it
            $winPe = @($script:Findings | Where-Object { $_.RelativePath -eq 'startnet.cmd' })
            @($winPe).Count | Should-BeGreaterThan 1
            foreach ($finding in $winPe) { $finding.Tier | Should-Be 'Environmental' }
        }

        It 'outranks the Wrapped tier when both apply' {
            # startnet.cmd line 3 is a for /f block. It is still reported as Environmental,
            # because whether PowerShell exists there has to be answered before the block matters
            $finding = Get-Finding -File 'startnet.cmd' -Line 3
            $finding.Tier | Should-Be 'Environmental'
            @($finding.RuleIds) | Should-ContainCollection @('WMIC100')
        }

        It 'escalates only the pre-install phase of a task sequence' {
            $steps = @($script:Findings | Where-Object { $_.FileType -eq 'TaskSequence' })
            $winPeStep = @($steps | Where-Object { $_.Tier -eq 'Environmental' })[0]
            $fullOsStep = @($steps | Where-Object { $_.Tier -ne 'Environmental' })[0]

            $winPeStep.StepName | Should-Be 'Capture serial'
            $fullOsStep.StepName | Should-Be 'Record installed products'
            $fullOsStep.Tier | Should-Be 'Semantic'
        }
    }

    Context 'reaching WMIC without writing wmic first' {

        It 'finds a call made through <Route>' -ForEach @(
            @{ File = 'Mechanical.cmd'; Line = 5; Route = '%COMSPEC% /c'; Expected = 'ComSpec' }
            @{ File = 'Mechanical.cmd'; Line = 6; Route = 'a full path'; Expected = 'Path' }
            @{ File = 'Indirect.cmd'; Line = 4; Route = 'start'; Expected = 'ProcessLauncher' }
            @{ File = 'Inventory.vbs'; Line = 4; Route = 'WScript.Shell'; Expected = 'ProcessLauncher' }
        ) {
            $finding = Get-Finding -File $File -Line $Line
            $finding | Should-NotBeNull -Because "$Route is a call site"
            @($finding.Invocation) | Should-ContainCollection @($Expected)
        }

        It 'stops the command at the end of the string that held it' {
            # objShell.Run "wmic bios get serialnumber", 0, True - without seeding the quote
            # state the command swallows the rest of the VBScript line
            (Get-Finding -File 'Inventory.vbs' -Line 5).Command |
                Should-Be 'wmic bios get serialnumber'
        }
    }

    Context 'not reporting things that are not calls' {

        It 'ignores prose that merely contains the word wmic' {
            # echo Replace wmic with PowerShell before the next image refresh. A scanner that
            # reports this teaches people to ignore the whole report.
            Get-Finding -File 'Mechanical.cmd' -Line 7 | Should-BeNull
        }

        It 'reports a WMIC command in a comment but never fails a build on it' {
            $finding = Get-Finding -File 'Mechanical.cmd' -Line 2
            $finding.Region | Should-Be 'Comment'
            $finding.FailsBuild | Should-BeFalse
            @($finding.RuleIds) | Should-ContainCollection @('WMIC002')
        }

        It 'drops comment findings entirely with -ExcludeComment' {
            $trimmed = @(Invoke-WmicScan -Path $script:FixtureRoot -ExcludeComment)
            @($trimmed | Where-Object { $_.Region -eq 'Comment' }).Count | Should-Be 0
            $trimmed.Count | Should-BeLessThan $script:Findings.Count
        }
    }

    Context 'security findings' {

        It 'raises a credential on the command line as its own finding' {
            # Worth fixing whether or not the WMIC call is ever migrated, so it must not be
            # closeable by a change that only moves the call
            $security = Get-Finding -File 'Semantic.cmd' -Line 5 -Kind 'Security'
            $security | Should-NotBeNull
            $security.RuleId | Should-Be 'WMIC900'
        }

        It 'keeps the deprecation finding for the same line' {
            Get-Finding -File 'Semantic.cmd' -Line 5 | Should-NotBeNull
        }

        It 'never fails a build on a security finding' {
            # The build gate is about WMIC deprecation. Letting a credential finding fail it lets
            # one problem hide behind the other.
            (Get-Finding -File 'Semantic.cmd' -Line 5 -Kind 'Security').FailsBuild | Should-BeFalse
        }
    }

    Context 'naming the target class' {

        It 'resolves the non-obvious alias <Alias> to <Class>' -ForEach @(
            @{ File = 'Mechanical.cmd'; Line = 6; Alias = 'qfe'; Class = 'Win32_QuickFixEngineering' }
            @{ File = 'Semantic.cmd'; Line = 4; Alias = 'nicconfig'; Class = 'Win32_NetworkAdapterConfiguration' }
            @{ File = 'Indirect.cmd'; Line = 4; Alias = 'cpu'; Class = 'Win32_Processor' }
        ) {
            $finding = Get-Finding -File $File -Line $Line
            $finding.Alias | Should-Be $Alias
            $finding.TargetClass | Should-Be $Class
        }

        It 'fills the target class into the advisory replacement' {
            (Get-Finding -File 'Mechanical.cmd' -Line 3).SuggestedReplacement |
                Should-MatchString 'Win32_BIOS'
        }

        It 'marks every suggestion advisory' {
            foreach ($finding in $script:Findings) { $finding.Advisory | Should-BeTrue }
        }
    }

    Context 'filtering and the build verdict' {

        It 'returns only the tier asked for' {
            $wrapped = @(Invoke-WmicScan -Path $script:FixtureRoot -Tier 'Wrapped')
            @($wrapped).Count | Should-BeGreaterThan 0
            foreach ($finding in $wrapped) { $finding.Tier | Should-Be 'Wrapped' }
        }

        It 'fails a build on Mechanical and Wrapped code only' {
            foreach ($finding in $script:Findings) {
                $shouldFail = $finding.Region -eq 'Code' -and
                    $finding.Kind -eq 'Deprecation' -and
                    $finding.Tier -in @('Mechanical', 'Wrapped')
                $finding.FailsBuild | Should-Be $shouldFail
            }
        }

        It 'summarises the run with a verdict a CI step can read' {
            # The module never calls exit. A library that terminates its host is a library you
            # cannot call from anything else.
            $summary = Invoke-WmicScan -Path $script:FixtureRoot -Summary
            $summary.FilesScanned | Should-BeGreaterThan 0
            $summary.FindingCount | Should-BeGreaterThan 0
            $summary.FailsBuild | Should-BeTrue
            $summary.ByTier['Wrapped'] | Should-BeGreaterThan 0
        }

        It 'reports no findings and no verdict for a tree with no WMIC in it' {
            $empty = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $empty | Out-Null
            try {
                Set-Content -Path (Join-Path $empty 'clean.cmd') -Value '@echo off'
                $summary = Invoke-WmicScan -Path $empty -Summary
                $summary.FindingCount | Should-Be 0
                $summary.FailsBuild | Should-BeFalse
            }
            finally {
                Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
