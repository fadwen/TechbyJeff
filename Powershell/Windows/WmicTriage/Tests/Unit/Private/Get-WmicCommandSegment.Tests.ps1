#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Where one command ends, which decides both what the report prints and whether the finding
    lands in the Wrapped tier.

    Two failures live here and both are silent.

    A terminator inside quotes. A WMIC where-clause routinely contains > and |, and splitting on
    them turns "workingsetsize > 100000000" into a redirect to a file called 100000000: a
    truncated command in the report and a Wrapped finding that does not exist.

    A walk that starts inside a string. objShell.Exec("wmic ...") and Start-Process 'wmic.exe'
    both put the command inside a quoted argument, so the scan begins after the opening quote.
    Without seeding the state from the text behind it, the closing quote reads as an opening one
    and the command absorbs the rest of the host language - which is how a report ends up saying
    the command was wmic bios get serialnumber", 0, True.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WmicCommandSegment' -Tag 'Unit', 'Private' {

    Context 'terminators' {

        It 'stops at a pipe and records it as capture' {
            InModuleScope WmicTriage {
                $result = Get-WmicCommandSegment -Text 'wmic service get name | find "auto"' -StartIndex 0
                $result.Text | Should-Be 'wmic service get name'
                @($result.Capture) | Should-ContainCollection @('Pipe')
            }
        }

        It 'stops at a redirect and records it as capture' {
            InModuleScope WmicTriage {
                $result = Get-WmicCommandSegment -Text 'wmic qfe list brief > out.txt' -StartIndex 0
                $result.Text | Should-Be 'wmic qfe list brief'
                @($result.Capture) | Should-ContainCollection @('Redirect')
            }
        }

        It 'treats a logical or as a separator rather than a pipe' {
            # || decides whether the next command runs; nothing reads the output
            InModuleScope WmicTriage {
                $result = Get-WmicCommandSegment -Text 'wmic os get caption || echo failed' -StartIndex 0
                $result.Text | Should-Be 'wmic os get caption'
                @($result.Capture).Count | Should-Be 0
            }
        }

        It 'stops at <Name> without calling it capture' -ForEach @(
            @{ Name = 'an ampersand'; Text = 'wmic os get caption & echo done' }
            @{ Name = 'a closing parenthesis'; Text = "('wmic os get caption') do echo x" }
        ) {
            InModuleScope WmicTriage -Parameters @{ Text = $Text } {
                param($Text)
                $index = $Text.IndexOf('wmic')
                $result = Get-WmicCommandSegment -Text $Text -StartIndex $index
                $result.Text | Should-Be 'wmic os get caption'
                @($result.Capture).Count | Should-Be 0
            }
        }
    }

    Context 'quoted text' {

        It 'ignores a greater-than inside a where-clause' {
            InModuleScope WmicTriage {
                $text = 'wmic process where "workingsetsize > 100000000" get name'
                $result = Get-WmicCommandSegment -Text $text -StartIndex 0

                $result.Text | Should-Be $text
                @($result.Capture).Count | Should-Be 0
            }
        }

        It 'ignores a pipe inside a where-clause' {
            InModuleScope WmicTriage {
                $text = 'wmic service where "name like ''a|b''" get state'
                $result = Get-WmicCommandSegment -Text $text -StartIndex 0
                @($result.Capture).Count | Should-Be 0
            }
        }

        It 'still finds the redirect that follows a quoted clause' {
            InModuleScope WmicTriage {
                $text = 'wmic process where "workingsetsize > 100" get name > out.txt'
                $result = Get-WmicCommandSegment -Text $text -StartIndex 0

                $result.Text | Should-Be 'wmic process where "workingsetsize > 100" get name'
                @($result.Capture) | Should-ContainCollection @('Redirect')
            }
        }
    }

    Context 'starting inside a string' {

        It 'ends the command where the double-quoted string holding it ends' {
            InModuleScope WmicTriage {
                $text = 'objShell.Run "wmic bios get serialnumber", 0, True'
                $result = Get-WmicCommandSegment -Text $text -StartIndex $text.IndexOf('wmic')

                $result.Text | Should-Be 'wmic bios get serialnumber'
            }
        }

        It 'ends the command where a single-quoted string holding it ends' {
            InModuleScope WmicTriage {
                $text = "Start-Process -FilePath 'wmic.exe' -ArgumentList 'os get caption'"
                $result = Get-WmicCommandSegment -Text $text -StartIndex $text.IndexOf('wmic') `
                    -QuoteCharacter '"', "'"

                $result.Text | Should-Be 'wmic.exe'
            }
        }

        It 'does not treat an apostrophe as a quote when the language has none' {
            # Batch. Passing only the double quote is what keeps an echoed apostrophe harmless.
            InModuleScope WmicTriage {
                $text = "wmic os get caption & echo doesn't matter"
                $result = Get-WmicCommandSegment -Text $text -StartIndex 0

                $result.Text | Should-Be 'wmic os get caption'
            }
        }
    }
}
