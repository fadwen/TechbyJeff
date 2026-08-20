#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The batch reader, which is the part of this module with no equivalent anywhere else.

    PSScriptAnalyzer never opens a .cmd file, so the oldest and least reviewed automation in an
    estate is exactly the part no existing tool reports on. Everything downstream of this reader
    depends on it getting three things right, and each of them is a place a regex would be wrong:

    Block extent, because the finding has to cover the whole for /f block. The tokens= spec is
    what has to be rewritten and it is not reliably on the same line as the command.

    Block boundaries, because an apostrophe means something different inside an in-clause than in
    a do-body. Treat it as a quote in the body and one echoed "don't" swallows the rest of the
    file into a single region; refuse to treat it as one in the in-clause and every parenthesis
    in a WMIC where-clause moves the block end.

    Which call the block actually parses, because only the in-clause is Wrapped. A call in the
    do-body just runs there.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
}

Describe 'Read-WmicBatchRegion' -Tag 'Unit', 'Private' {

    Context 'for /f blocks' {

        It 'captures a single line block as one region' {
            InModuleScope WmicTriage {
                $text = @'
@echo off
for /f "tokens=2 delims==" %%A in ('wmic os get caption /value') do set OS=%%A
'@
                $block = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Structure -eq 'ForBlock' })

                @($block).Count | Should-Be 1
                $block[0].StartLine | Should-Be 2
                $block[0].EndLine | Should-Be 2
                $block[0].Detail.ForOptions | Should-Be 'tokens=2 delims=='
            }
        }

        It 'runs the region to the end of a multi-line do-body' {
            InModuleScope WmicTriage {
                $text = @'
for /f "skip=1 tokens=1,2" %%A in ('wmic logicaldisk get deviceid') do (
    echo %%A
    echo %%B
)
'@
                $block = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Structure -eq 'ForBlock' })[0]

                $block.StartLine | Should-Be 1
                $block.EndLine | Should-Be 4
            }
        }

        It 'is not ended early by an apostrophe in the do-body' {
            # An apostrophe quotes a command inside an in-clause and quotes nothing in a body.
            # Treating it as a quote here would run the region past the closing parenthesis.
            InModuleScope WmicTriage {
                $text = @'
for /f "tokens=1" %%A in ('wmic bios get serialnumber') do (
    echo That doesn't look right
    echo %%A
)
'@
                $block = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Structure -eq 'ForBlock' })[0]

                $block.EndLine | Should-Be 4
            }
        }

        It 'is not ended early by a parenthesis inside the in-clause' {
            InModuleScope WmicTriage {
                $text = "for /f `"tokens=2`" %%A in ('wmic service " +
                "where (name=`"spooler`") get state') do echo %%A"
                $block = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Structure -eq 'ForBlock' })

                @($block).Count | Should-Be 1
            }
        }

        It 'leaves the do-body to be read as ordinary lines' {
            # Only the in-clause is parsed by the block. A call in the body merely runs there,
            # and marking it Wrapped would inflate the tier this module exists to report.
            InModuleScope WmicTriage {
                $text = @'
for /f "tokens=1" %%A in ('wmic os get caption') do (
    wmic bios get serialnumber
)
'@
                $regions = @(Read-WmicBatchRegion -Content $text)
                $body = @($regions | Where-Object {
                        $_.Structure -eq 'Line' -and $_.Text -match 'bios'
                    })

                @($body).Count | Should-Be 1
            }
        }
    }

    Context 'line continuations' {

        It 'joins a caret continuation into one logical line' {
            InModuleScope WmicTriage {
                $text = "wmic os get ^`ncaption"
                $region = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Text -match 'wmic' })[0]

                $region.Text | Should-Be 'wmic os get caption'
                @($region.Lines).Count | Should-Be 2
            }
        }

        It 'keeps the physical lines so the finding still points somewhere real' {
            InModuleScope WmicTriage {
                $text = "@echo off`nwmic os get ^`ncaption"
                $region = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Text -match 'wmic' })[0]

                $region.StartLine | Should-Be 2
                $region.EndLine | Should-Be 3
            }
        }

        It 'does not continue on an escaped caret' {
            # ^^ is a literal caret that happens to end the line and continues nothing
            InModuleScope WmicTriage {
                $text = "echo ^^`nwmic os get caption"
                $region = @(Read-WmicBatchRegion -Content $text |
                        Where-Object { $_.Text -match 'wmic' })[0]

                $region.StartLine | Should-Be 2
            }
        }
    }

    Context 'comments and assignments' {

        It 'marks a <Marker> line as a comment' -ForEach @(
            @{ Marker = 'rem' }
            @{ Marker = 'REM' }
            @{ Marker = '::' }
        ) {
            InModuleScope WmicTriage -Parameters @{ Marker = $Marker } {
                param($Marker)
                $region = @(Read-WmicBatchRegion -Content "$Marker wmic os get caption")[0]
                $region.Kind | Should-Be 'Comment'
            }
        }

        It 'reports a variable holding the path to wmic.exe' {
            InModuleScope WmicTriage {
                $text = 'set WMICPATH=%SystemRoot%\System32\wbem\wmic.exe'
                $region = @(Read-WmicBatchRegion -Content $text)[0]

                $region.Structure | Should-Be 'Assignment'
                $region.Detail.VariableName | Should-Be 'WMICPATH'
            }
        }

        It 'does not treat an unrelated assignment as one' {
            InModuleScope WmicTriage {
                $region = @(Read-WmicBatchRegion -Content 'set LOGPATH=C:\Temp\out.log')[0]
                $region.Structure | Should-Be 'Line'
            }
        }
    }

    Context 'malformed input' {

        It 'does not swallow the file when a block never closes' {
            # Truncated batch is common. Falling back to a single line beats consuming the rest.
            InModuleScope WmicTriage {
                $text = @'
for /f "tokens=1" %%A in ('wmic os get caption') do (
    echo %%A
wmic bios get serialnumber
'@
                $regions = @(Read-WmicBatchRegion -Content $text)
                @($regions | Where-Object { $_.Text -match 'bios' }).Count | Should-Be 1
            }
        }

        It 'returns nothing for empty content' {
            InModuleScope WmicTriage {
                @(Read-WmicBatchRegion -Content '').Count | Should-Be 0
            }
        }
    }
}
