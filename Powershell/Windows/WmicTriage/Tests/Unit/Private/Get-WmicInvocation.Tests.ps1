#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Telling a WMIC command apart from the word "wmic" in a sentence.

    This matters more than it sounds like it should. Legacy scripts are heavily
    commented, and the comments are overwhelmingly *about* WMIC - explaining what was
    removed, what replaced it, why it was pinned to a path. A scanner that reports every
    one of those as a call site produces a report where most entries are wrong, and a
    report where most entries are wrong gets ignored entirely. That costs more than
    missing a call, because it discards the findings that were right along with the rest.

    The trap is that the obvious test - does a WMIC verb appear anywhere after the word -
    passes on ordinary English. "the WMIC call ever moves" contains call. "wmic was
    pulled off PATH by a hardening baseline" contains path. Both were reported as
    commands until these tests existed.

    So the test follows the actual grammar instead: what stands where an alias would, and
    what may follow one. The second clause is what keeps an alias missing from the table
    from becoming an undercount, which is the failure mode worth engineering against.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force

    function global:New-InvocationRegion {
        param([string]$Text, [string]$Kind = 'Code')
        [PSCustomObject]@{
            Kind      = $Kind
            Structure = 'Line'
            Text      = $Text
            Snippet   = $Text
            StartLine = 1
            EndLine   = 1
            Lines     = @(@{ Number = 1; Text = $Text })
            Detail    = @{}
        }
    }
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'function:global:New-InvocationRegion' -ErrorAction SilentlyContinue
}

Describe 'Get-WmicInvocation' -Tag 'Unit', 'Private' {

    Context 'prose that merely mentions WMIC' {

        It 'ignores <Name>' -ForEach @(
            @{
                Name = 'a sentence whose next word happens to be a verb'
                Text = 'rem worth fixing whether or not the WMIC call ever moves.'
            }
            @{
                Name = 'a sentence containing the word PATH'
                Text = 'rem the path is pinned because wmic was pulled off PATH by a baseline'
            }
            @{
                Name = 'an instruction to stop using it'
                Text = 'echo Replace wmic with PowerShell before the next image refresh'
            }
            @{
                Name = 'a bare quoted mention in a comment'
                Text = 'rem a search for a leading "wmic" misses this one'
                Kind = 'Comment'
            }
        ) {
            InModuleScope WmicTriage -Parameters @{ Text = $Text; Kind = $Kind } {
                param($Text, $Kind)
                if (-not $Kind) { $Kind = 'Code' }
                $region = New-InvocationRegion -Text $Text -Kind $Kind
                $calls = @(Get-WmicInvocation -Region $region -FileType Batch -RuleSet (Get-WmicRuleSet))
                @($calls).Count | Should-Be 0
            }
        }
    }

    Context 'commands that must not be missed' {

        It 'finds <Name>' -ForEach @(
            @{ Name = 'a known alias'; Text = 'wmic bios get serialnumber' }
            @{ Name = 'a leading switch'; Text = 'wmic /node:SRV01 os get caption' }
            @{ Name = 'a path expression'; Text = 'wmic path win32_process call terminate' }
            @{ Name = 'a where clause before the verb'; Text = 'wmic service where "name=''x''" get state' }
            @{ Name = 'a bare invocation in code'; Text = 'wmic' }
        ) {
            InModuleScope WmicTriage -Parameters @{ Text = $Text } {
                param($Text)
                $region = New-InvocationRegion -Text $Text
                $calls = @(Get-WmicInvocation -Region $region -FileType Batch -RuleSet (Get-WmicRuleSet))
                @($calls).Count | Should-Be 1
            }
        }

        It 'finds an alias the table does not carry' {
            # The second clause of the grammar test. An unfamiliar alias must not become an
            # undercount just because nobody has added it to WmicAliases.psd1 yet.
            InModuleScope WmicTriage {
                $region = New-InvocationRegion -Text 'wmic somefutureAlias get name'
                $calls = @(Get-WmicInvocation -Region $region -FileType Batch -RuleSet (Get-WmicRuleSet))
                @($calls).Count | Should-Be 1
            }
        }

        It 'still reports a documented command inside a comment' {
            # A real command in a rem line is the example somebody copies later
            InModuleScope WmicTriage {
                $region = New-InvocationRegion -Text 'rem Was: wmic csproduct get uuid' -Kind 'Comment'
                $calls = @(Get-WmicInvocation -Region $region -FileType Batch -RuleSet (Get-WmicRuleSet))
                @($calls).Count | Should-Be 1
            }
        }
    }

    Context 'how the call was reached' {

        It 'records <Expected> for <Name>' -ForEach @(
            @{ Name = 'a plain call'; Text = 'wmic os get caption'; Expected = 'Literal' }
            @{ Name = 'the interpreter'; Text = '%COMSPEC% /c wmic os get caption'; Expected = 'ComSpec' }
            @{
                Name = 'a full path'
                Text = 'C:\Windows\System32\wbem\wmic.exe qfe list brief'
                Expected = 'Path'
            }
        ) {
            InModuleScope WmicTriage -Parameters @{ Text = $Text; Expected = $Expected } {
                param($Text, $Expected)
                $region = New-InvocationRegion -Text $Text
                $calls = @(Get-WmicInvocation -Region $region -FileType Batch -RuleSet (Get-WmicRuleSet))
                @($calls[0].Invocation) | Should-ContainCollection @($Expected)
            }
        }
    }
}
