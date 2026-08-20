#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The two report formats, and the properties each one exists to have.

    The CSV is for a person planning work, so it has to survive Excel and every hand-rolled
    parser that will ever be pointed at it. That means no newline inside a field - the snippet of
    a for /f block is by definition multi-line, and left alone it turns one row into four that
    every naive reader mis-associates.

    The SARIF is for a pipeline, so it has to say the same thing about severity that FailsBuild
    says, and it has to recognise a finding it has seen before. The fingerprint deliberately
    excludes the line number: add a comment at the top of a batch file and every call below it
    moves, and a fingerprint that included the line would close two hundred findings and open two
    hundred identical ones. The second report anyone reads would be noise.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'WmicTriage.psd1') -Force
    $script:FixtureRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures'
    $script:Findings = @(Invoke-WmicScan -Path $script:FixtureRoot)
}

AfterAll {
    Remove-Module WmicTriage -Force -ErrorAction SilentlyContinue
}

Describe 'Export-WmicScanReport' -Tag 'Unit', 'Public' {

    BeforeEach {
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Work | Out-Null
        $script:CsvPath = Join-Path $script:Work 'report.csv'
        $script:SarifPath = Join-Path $script:Work 'report.sarif'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'CSV' {

        It 'writes one row per finding' {
            $script:Findings | Export-WmicScanReport -Path $script:CsvPath
            @(Import-Csv -Path $script:CsvPath).Count | Should-Be $script:Findings.Count
        }

        It 'flattens every field onto a single line' {
            # A for /f snippet spans lines. Left alone it splits one row into several.
            $script:Findings | Export-WmicScanReport -Path $script:CsvPath
            foreach ($row in Import-Csv -Path $script:CsvPath) {
                foreach ($property in $row.PSObject.Properties) {
                    [string]$property.Value | Should-NotMatchString "`n"
                }
            }
        }

        It 'keeps the tier and the advisory replacement' {
            $script:Findings | Export-WmicScanReport -Path $script:CsvPath
            $rows = @(Import-Csv -Path $script:CsvPath)

            @($rows | Where-Object { $_.Tier -eq 'Wrapped' }).Count | Should-BeGreaterThan 0
            @($rows | Where-Object { $_.SuggestedReplacement }).Count | Should-BeGreaterThan 0
            $rows[0].Advisory | Should-Be 'True'
        }

        It 'joins the matched rules rather than emitting a type name' {
            $script:Findings | Export-WmicScanReport -Path $script:CsvPath
            $row = @(Import-Csv -Path $script:CsvPath | Where-Object { $_.RuleId -eq 'WMIC100' })[0]
            $row.MatchedRules | Should-MatchString 'WMIC001'
        }
    }

    Context 'SARIF' {

        It 'writes a valid 2.1.0 document' {
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $sarif.version | Should-Be '2.1.0'
            @($sarif.runs).Count | Should-Be 1
            $sarif.runs[0].tool.driver.name | Should-Be 'WmicTriage'
            @($sarif.runs[0].results).Count | Should-Be $script:Findings.Count
        }

        It 'describes every rule in the tool driver' {
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            @($sarif.runs[0].tool.driver.rules).Count | Should-Be @(Get-WmicRule).Count
        }

        It 'maps <Tier> to the <Level> level' -ForEach @(
            @{ Tier = 'Mechanical'; Level = 'error' }
            @{ Tier = 'Wrapped'; Level = 'error' }
            @{ Tier = 'Semantic'; Level = 'warning' }
            @{ Tier = 'Environmental'; Level = 'warning' }
        ) {
            # The same rule as FailsBuild, in the vocabulary the consuming tools use. Promoting
            # Semantic to error would look more rigorous and would teach people to bypass the check.
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $matching = @($sarif.runs[0].results | Where-Object {
                    $_.properties.tier -eq $Tier -and $_.level -ne 'note' -and
                    $_.properties.kind -eq 'Deprecation'
                })
            @($matching).Count | Should-BeGreaterThan 0
            foreach ($result in $matching) { $result.level | Should-Be $Level }
        }

        It 'raises a security finding to error whatever tier it sits in' {
            # The one place level and FailsBuild disagree, on purpose: a checked-in password is
            # an error by any reading, but the build gate here is about WMIC deprecation
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $security = @($sarif.runs[0].results | Where-Object { $_.properties.kind -eq 'Security' })
            @($security).Count | Should-BeGreaterThan 0
            foreach ($result in $security) {
                $result.level | Should-Be 'error'
                $result.properties.failsBuild | Should-BeFalse
            }
        }

        It 'drops a finding in a comment to note' {
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $notes = @($sarif.runs[0].results | Where-Object { $_.level -eq 'note' })
            @($notes).Count | Should-BeGreaterThan 0
            foreach ($note in $notes) { $note.properties.failsBuild | Should-BeFalse }
        }

        It 'gives every result a fingerprint that ignores the line number' {
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            foreach ($result in $sarif.runs[0].results) {
                $result.partialFingerprints.'wmicTriage/v1' | Should-NotBeEmptyString
            }
        }

        It 'uses forward slashes and escapes spaces in the artifact uri' {
            # A Windows path handed over unchanged matches no file in the repository, which shows
            # up as a report full of findings that annotate nothing
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            foreach ($result in $sarif.runs[0].results) {
                $uri = $result.locations[0].physicalLocation.artifactLocation.uri
                $uri | Should-NotMatchString '\\'
                $uri | Should-NotMatchString ' '
            }
        }

        It 'spans the whole block for a for /f finding' {
            $script:Findings | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $block = @($sarif.runs[0].results | Where-Object {
                    $_.properties.structure -eq 'ForBlock' -and
                    $_.locations[0].physicalLocation.region.endLine -gt
                    $_.locations[0].physicalLocation.region.startLine
                })
            @($block).Count | Should-BeGreaterThan 0
        }
    }

    Context 'behaviour' {

        It 'supports WhatIf and writes nothing' {
            $script:Findings | Export-WmicScanReport -Path $script:CsvPath -WhatIf
            Test-Path -LiteralPath $script:CsvPath | Should-BeFalse
        }

        It 'returns the findings with PassThru so it can sit mid-pipeline' {
            $returned = @($script:Findings | Export-WmicScanReport -Path $script:CsvPath -PassThru)
            @($returned).Count | Should-Be $script:Findings.Count
        }

        It 'returns nothing without PassThru' {
            $returned = $script:Findings | Export-WmicScanReport -Path $script:CsvPath
            $returned | Should-BeNull
        }

        It 'writes an empty but valid SARIF document for a clean scan' {
            # A pipeline uploading the result should not have to special-case success
            @() | Export-WmicScanReport -Path $script:SarifPath -Format Sarif
            $sarif = Get-Content -Path $script:SarifPath -Raw | ConvertFrom-Json

            $sarif.version | Should-Be '2.1.0'
            @($sarif.runs[0].results).Count | Should-Be 0
        }
    }
}
