#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Report rendering, with particular attention to the fact that every name in a report
    originates in the event log and is therefore chosen by whoever made the request.

    A service principal name comes off the wire. Anyone who can request a service ticket can
    put markup in it, and it lands in a 4769 event, and from there in a report that a domain
    administrator opens in a browser. Rendering it verbatim makes the assessment tool a
    delivery mechanism for stored cross-site scripting aimed at its own reader - which is a
    memorable way to end a security review, and not in a good way.

    The other properties tested here are less dramatic and still matter:

    - JSON has to serialize deeply enough to keep the evidence. At the default depth of 2 the
      Evidence hashtable renders as the string 'System.Collections.Hashtable', and the file
      that exists specifically to preserve the working contains none of it.
    - CSV has to be one row per finding, not per principal, or the file cannot be pivoted and
      there was no reason to choose CSV.
    - An empty input has to warn rather than write an empty file, for the same reason it does
      everywhere else in this module: nothing measured is not nothing wrong.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    $script:FixtureRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'Fixtures'

    $script:OutputRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath "KrbEtypeInsight-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:OutputRoot -Force | Out-Null

    function Get-FixtureRisk {
        <#
            Produces risk objects from named fixtures, for the renderer to consume.
        #>
        param([Parameter(Mandatory)][string[]]$Name)

        $events = foreach ($item in $Name) {
            $raw = Get-Content -Path (Join-Path $script:FixtureRoot $item) -Raw
            InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw -SourceName 'fixture'
            }
        }

        @($events | Get-KrbEtypeRisk -Offline -IncludeHealthy)
    }
}

AfterAll {
    if ($script:OutputRoot -and (Test-Path $script:OutputRoot)) {
        Remove-Item -Path $script:OutputRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Export-KrbEtypeReport' -Tag 'Unit', 'Public', 'Report' {

    Context 'HTML output' {

        BeforeAll {
            $script:HtmlRisks = Get-FixtureRisk @(
                '4769-v2-healthy-aes.xml'
                '4769-v2-service-no-aes-key.xml'
                '4768-v2-legacy-client.xml'
                '4769-v2-legacy-client-to-service.xml'
            )

            $script:HtmlPath = Join-Path $script:OutputRoot 'report.html'
            $script:HtmlRisks | Export-KrbEtypeReport -Path $script:HtmlPath -Title 'Test assessment'
            $script:Html = Get-Content -Path $script:HtmlPath -Raw
        }

        It 'writes a file' {
            $script:HtmlPath | Should -Exist
        }

        It 'produces a complete HTML document' {
            $script:Html | Should-MatchString '<!DOCTYPE html>'
            $script:Html | Should-MatchString '</html>'
        }

        It 'uses the supplied title' {
            $script:Html | Should-MatchString '<title>Test assessment</title>'
        }

        It 'references no external resource' {
            # The report is opened on isolated machines and from email. A CDN stylesheet or a
            # remote font makes it render wrongly exactly where it is most needed, and leaks
            # the fact that it was opened to a third party.
            $script:Html | Should-NotMatchString '<script\s+src='
            $script:Html | Should-NotMatchString '<link[^>]+href=["'']https?:'
            $script:Html | Should-NotMatchString '@import\s+url'
        }

        It 'names the affected principals' {
            $script:Html | Should-MatchString 'svc-payroll'
            $script:Html | Should-MatchString 'APPLIANCE-SCAN01'
        }

        It 'includes the finding codes' {
            $script:Html | Should-MatchString 'KRB005'
            $script:Html | Should-MatchString 'KRB002'
        }

        It 'renders in both light and dark themes' {
            # Security reports get read at all hours by people whose terminal is dark.
            $script:Html | Should-MatchString 'prefers-color-scheme'
        }
    }

    Context 'HTML encoding of untrusted content' {

        BeforeAll {
            $script:HostileRisks = Get-FixtureRisk @('4769-v2-hostile-spn.xml')
            $script:HostilePath = Join-Path $script:OutputRoot 'hostile.html'
            $script:HostileRisks | Export-KrbEtypeReport -Path $script:HostilePath
            $script:HostileHtml = Get-Content -Path $script:HostilePath -Raw
        }

        It 'does not emit an executable script tag from a service principal name' {
            # The fixture SPN contains a literal <script>alert(1)</script>, exactly as a
            # hostile client could register it. It must survive into the report as text.
            $script:HostileHtml | Should-NotMatchString '<script>alert'
        }

        It 'encodes the angle brackets it received' {
            $script:HostileHtml | Should-MatchString '&lt;script&gt;'
        }

        It 'still shows the operator what the real value was' {
            # Encoding must not mean discarding. An administrator investigating a hostile SPN
            # needs to see it, and a report that silently drops the interesting part of a
            # value is worse than one that never showed it.
            $script:HostileHtml | Should-MatchString 'objectClass'
        }

        It 'contains no script tag anywhere in the document' {
            # The report ships no JavaScript of its own, so any script tag at all in the
            # output came from input data.
            $script:HostileHtml | Should-NotMatchString '(?i)<script'
        }
    }

    Context 'JSON output' {

        BeforeAll {
            $script:JsonPath = Join-Path $script:OutputRoot 'report.json'
            Get-FixtureRisk @('4769-v2-service-no-aes-key.xml') |
                Export-KrbEtypeReport -Path $script:JsonPath -Format Json

            $script:Json = Get-Content -Path $script:JsonPath -Raw | ConvertFrom-Json
        }

        It 'writes valid JSON' {
            $script:Json | Should-NotBeNull
        }

        It 'preserves the findings' {
            $risk = @($script:Json) | Where-Object PrincipalName -like 'MSSQLSvc*'
            @($risk.Findings).Count | Should-BeGreaterThan 0
        }

        It 'serializes deeply enough to keep the evidence' {
            # At ConvertTo-Json's default depth of 2 the Evidence hashtable becomes the
            # literal string 'System.Collections.Hashtable', and the format chosen
            # specifically to preserve the working preserves none of it.
            $risk = @($script:Json) | Where-Object PrincipalName -like 'MSSQLSvc*'
            $finding = @($risk.Findings) | Where-Object Code -eq 'KRB002'

            $finding.Evidence | Should-NotBeNull
            "$($finding.Evidence)" | Should-NotMatchString 'System.Collections.Hashtable'
            @($finding.Evidence.AvailableKeys) | Should-ContainCollection @('RC4')
        }
    }

    Context 'CSV output' {

        BeforeAll {
            $script:CsvPath = Join-Path $script:OutputRoot 'report.csv'
            $script:CsvRisks = Get-FixtureRisk @(
                '4769-v2-service-no-aes-key.xml'
                '4769-v2-healthy-aes.xml'
            )
            $script:CsvRisks | Export-KrbEtypeReport -Path $script:CsvPath -Format Csv
            $script:Csv = @(Import-Csv -Path $script:CsvPath)
        }

        It 'writes one row per finding, not per principal' {
            # A principal with four findings needs four rows to be filtered and pivoted. One
            # row per principal forces the findings into a joined cell and there was no point
            # choosing CSV.
            $expectedRows = ($script:CsvRisks | ForEach-Object { @($_.Findings).Count } |
                Measure-Object -Sum).Sum

            $script:Csv | Should-BeCollection -Count $expectedRows
        }

        It 'includes the columns a triage spreadsheet needs' {
            $columns = @($script:Csv[0].PSObject.Properties.Name)

            foreach ($required in 'PrincipalName', 'RiskLevel', 'RiskScore', 'FindingCode',
                                  'Severity', 'ClientsWithoutAes', 'ObservedEtypes', 'AvailableKeys') {
                $columns | Should-ContainCollection @($required)
            }
        }

        It 'flattens list columns to a delimited string' {
            $row = $script:Csv | Where-Object FindingCode -eq 'KRB002' | Select-Object -First 1
            $row.AvailableKeys | Should-Be 'RC4'
        }
    }

    Context 'Baseline section' {

        It 'states when the domain default was assumed rather than measured' {
            # Every conclusion about an account with an unset attribute inherits this
            # uncertainty. A reader who was not in the room cannot otherwise tell.
            $context = [PSCustomObject]@{
                PSTypeName = 'KrbEtypeInsight.DomainContext'
                DomainName = 'ad.techbyjeff.net'
                DomainMode = 'Windows2016Domain'
                ForestMode = 'Windows2016Forest'
                SupportsAesKeyDerivation = $true
                DomainDefaultDecoded = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x27
                DomainDefaultSource = 'WindowsDefault'
                ControllersDisagreeOnDefault = $false
                KrbtgtEncryptionTypes = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0
                KrbtgtPasswordAgeDays = 380
                DomainControllers = @()
                TrustsWithRc4Only = @()
            }

            $path = Join-Path $script:OutputRoot 'baseline.html'
            Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                Export-KrbEtypeReport -Path $path -DomainContext $context

            $html = Get-Content -Path $path -Raw
            $html | Should-MatchString 'could not be read from the domain controllers'
            $html | Should-MatchString 'Windows2016Domain'
        }
    }

    Context 'Behaviour and validation' {

        It 'supports -WhatIf without writing a file' {
            $path = Join-Path $script:OutputRoot 'whatif.html'
            Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                Export-KrbEtypeReport -Path $path -WhatIf

            Test-Path -Path $path | Should-BeFalse
        }

        It 'returns the file with -PassThru' {
            $path = Join-Path $script:OutputRoot 'passthru.html'
            $result = Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                Export-KrbEtypeReport -Path $path -PassThru

            $result | Should-HaveType ([System.IO.FileInfo])
            $result.FullName | Should-Be $path
        }

        It 'returns nothing without -PassThru' {
            $path = Join-Path $script:OutputRoot 'quiet.html'
            $result = Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                Export-KrbEtypeReport -Path $path

            $result | Should-BeNull
        }

        It 'errors on a directory that does not exist' {
            $path = Join-Path $script:OutputRoot 'no-such-directory\report.html'

            {
                Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                    Export-KrbEtypeReport -Path $path -ErrorAction Stop
            } | Should-Throw
        }

        It 'warns rather than writing an empty report' {
            $path = Join-Path $script:OutputRoot 'empty.html'
            $captured = @(@() | Export-KrbEtypeReport -Path $path 3>&1)

            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
            Test-Path -Path $path | Should-BeFalse
        }

        It 'truncates a long evidence list and says where the full set is' {
            # A widely used service can carry hundreds of client names in one evidence field.
            # The HTML truncates for readability; the JSON export exists for the complete set,
            # and the report has to say so rather than silently shortening the evidence.
            $finding = InModuleScope KrbEtypeInsight {
                New-KrbRiskFinding -Code 'KRB005' -Severity 'Critical' -Title 'Many clients' `
                    -Detail 'Synthetic finding with an oversized evidence list.' `
                    -Evidence @{ Clients = @(1..200 | ForEach-Object { "LEGACY-CLIENT-$_`$" }) }
            }
            $summary = InModuleScope KrbEtypeInsight -Parameters @{ F = @($finding) } {
                Measure-KrbRiskLevel -Finding $F
            }
            $risk = InModuleScope KrbEtypeInsight -Parameters @{ F = @($finding); S = $summary } {
                New-KrbRiskObject -PrincipalName 'svc-popular' -Finding $F -Summary $S -Role 'Service'
            }

            $path = Join-Path $script:OutputRoot 'truncated.html'
            $risk | Export-KrbEtypeReport -Path $path
            $html = Get-Content -Path $path -Raw

            $html | Should-MatchString 'truncated, see JSON export'
            $html | Should-MatchString 'LEGACY-CLIENT-1\$'
        }

        It 'writes the configured encryption types into the CSV' {
            $path = Join-Path $script:OutputRoot 'configured.csv'

            $risk = InModuleScope KrbEtypeInsight {
                $finding = New-KrbRiskFinding -Code 'KRB003' -Severity 'High' -Title 'No AES' `
                    -Detail 'Synthetic.'
                $summary = Measure-KrbRiskLevel -Finding @($finding)
                New-KrbRiskObject -PrincipalName 'svc-rc4' -Finding @($finding) -Summary $summary `
                    -Role 'Service' `
                    -ConfiguredEncryptionTypes (ConvertFrom-KrbEtype -SupportedEncryptionTypes 4)
            }

            $risk | Export-KrbEtypeReport -Path $path -Format Csv
            $row = @(Import-Csv -Path $path)[0]

            $row.ConfiguredEtypes | Should-Be '0x4'
        }

        It 'reports a write failure rather than failing silently' {
            # A report that could not be written must say so. The caller has just spent
            # minutes collecting events, and a silent failure looks identical to success
            # until somebody goes looking for the file.
            Mock -ModuleName KrbEtypeInsight Set-Content { throw 'The device is not ready' }

            {
                Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                    Export-KrbEtypeReport -Path (Join-Path $script:OutputRoot 'fail.html') -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*Failed to write report*'
        }

        It 'names the path it could not write in the error' {
            Mock -ModuleName KrbEtypeInsight Set-Content { throw 'The device is not ready' }
            $target = Join-Path $script:OutputRoot 'named-in-error.html'

            # Caught rather than collected with -ErrorVariable. The function raises this with
            # Write-Error -ErrorAction Stop, which is terminating from inside regardless of
            # the caller's preference, so -ErrorAction SilentlyContinue does not suppress it
            # and the error never reaches the variable.
            $message = $null
            try {
                Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                    Export-KrbEtypeReport -Path $target -ErrorAction Stop
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should-MatchString 'named-in-error'
        }

        It 'rejects an unsupported format' {
            {
                Get-FixtureRisk @('4769-v2-healthy-aes.xml') |
                    Export-KrbEtypeReport -Path (Join-Path $script:OutputRoot 'x.pdf') -Format 'Pdf'
            } | Should-Throw
        }
    }
}
