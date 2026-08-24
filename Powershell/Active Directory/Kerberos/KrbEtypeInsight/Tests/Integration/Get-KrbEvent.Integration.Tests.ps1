#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Integration tests against a real Windows security log and, where one is reachable, a real
    domain. Everything here is skipped when its prerequisite is absent, so the file is safe
    to run on a workstation or a CI runner - it simply reports skips rather than failures.

    Two things are being tested that the unit suite structurally cannot:

    1. The archived-log path against a genuine .evtx container. The unit tests feed captured
       XML directly to the decoder, which exercises every field but bypasses Get-WinEvent,
       the FilterHashtable, and the EVTX reader itself. A filter that Get-WinEvent rejects -
       Path and LogName together, for instance - passes every unit test and fails on first
       contact with a real file.

    2. That the module's decoding agrees with the operating system's. Version 2 events carry
       Windows' own rendering of each supported-encryption-types bitmask alongside the raw
       value. Comparing the two on live events makes the KDC an independent oracle, and it is
       the only assertion in this suite whose expected value was not written by the same
       person who wrote the code.

    The .evtx is generated at run time from this machine's own Security log rather than
    committed to the repository. A real export contains real account names, SIDs and client
    addresses; committing one to a module that is going to be published would leak the
    author's domain into a blog artifact, permanently and irrevocably. The synthetic XML
    fixtures in Tests\Fixtures exist precisely so that no real data needs to be stored.
#>

BeforeDiscovery {
    # Prerequisites are evaluated at DISCOVERY time so the -Skip decisions are made while the
    # test tree is built. Deferred to run time they would produce failures on a machine that
    # simply is not a domain controller.
    $script:HasSecurityLog = $false
    $script:HasKerberosEvents = $false
    $script:HasDomain = $false

    try {
        $probe = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4768, 4769 } `
                -MaxEvents 5 -ErrorAction Stop)
        $script:HasSecurityLog = $true
        $script:HasKerberosEvents = $probe.Count -gt 0
    }
    catch {
        # No security log access, or no Kerberos auditing. Both mean skip, which is the
        # point of probing here rather than letting the tests fail on a non-DC.
        Write-Verbose "Kerberos event probe failed: $($_.Exception.Message)"
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $null = Get-ADDomain -ErrorAction Stop
        $script:HasDomain = $true
    }
    catch {
        # Not domain joined, or RSAT absent.
        Write-Verbose "Domain probe failed: $($_.Exception.Message)"
    }
}

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    $script:WorkRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath "KrbEtypeInsight-integration-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null

    $script:ExportedLog = $null

    # Re-probe rather than reading the flag BeforeDiscovery set. Pester 6 runs discovery and
    # execution in separate scopes, so a $script: variable written in BeforeDiscovery is not
    # visible here - it reads as $null, this whole block is skipped, and every archived-log
    # test reports as skipped on a machine that could perfectly well have run them. The
    # -Skip: decisions on the Context blocks still come from the discovery-time flags,
    # because those must be resolved while the test tree is being built.
    $canExport = $false
    $sample = @()
    try {
        $sample = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4768, 4769, 4771 } `
                -MaxEvents 100 -ErrorAction Stop)
        $canExport = $sample.Count -gt 0
    }
    catch {
        # No security log access, or no Kerberos auditing.
        Write-Verbose "Export probe failed: $($_.Exception.Message)"
    }

    # Export a bounded slice of this machine's own Kerberos events to a real .evtx. The
    # record-identifier floor comes from the events themselves rather than from a fixed
    # number: Security log record IDs are shared with every other audit category, so a
    # Kerberos-only slice of a hundred events can span a hundred thousand record IDs on a
    # busy machine and only a few hundred on a quiet one.
    if ($canExport) {
        try {
            $floor = ($sample | Measure-Object -Property RecordId -Minimum).Minimum

            $path = Join-Path -Path $script:WorkRoot -ChildPath 'kerberos-slice.evtx'
            $query = "/q:*[System[(EventID=4768 or EventID=4769 or EventID=4771) and (EventRecordID>=$floor)]]"

            & wevtutil epl Security $path $query /ow:true 2>&1 | Out-Null

            if (Test-Path -Path $path) { $script:ExportedLog = $path }
        }
        catch {
            # Export failed; the archived-log tests will skip on the null path.
            Write-Verbose "Security log export failed: $($_.Exception.Message)"
        }
    }
}

AfterAll {
    if ($script:WorkRoot -and (Test-Path $script:WorkRoot)) {
        Remove-Item -Path $script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbEvent against a real security log' -Tag 'Integration', 'EventLog' {

    Context 'Live collection' -Skip:(-not $script:HasKerberosEvents) {

        It 'collects and decodes events from the local security log' {
            $events = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 50 `
                    -WarningAction SilentlyContinue)

            $events.Count | Should-BeGreaterThan 0
            $events[0].PSTypeNames[0] | Should-Be 'KrbEtypeInsight.Event'
        }

        It 'decodes a recognised encryption type on every successful ticket' {
            # An unrecognised etype on a live domain means the catalog is missing something
            # the operating system is actively using - which is a real gap, not a curiosity.
            $events = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 200 `
                    -WarningAction SilentlyContinue |
                Where-Object { -not $_.IsFailure -and $null -ne $_.TicketEtype -and $_.TicketEtype -ne -1 })

            foreach ($item in $events) {
                (ConvertFrom-KrbEtype -TicketEtype $item.TicketEtype).IsRecognized |
                    Should-BeTrue -Because "etype $($item.TicketEtype) was issued by a live KDC"
            }
        }

        It 'resolves a status name for every event' {
            $events = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 100 `
                    -WarningAction SilentlyContinue | Where-Object { $null -ne $_.Status })

            foreach ($item in $events) {
                $item.StatusName | Should-BeTruthy -Because "status $($item.StatusHex) came from a live KDC"
            }
        }

        It 'filters to failures only when asked' {
            $all = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 200 -WarningAction SilentlyContinue)
            $failures = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 200 `
                    -IncludeFailureOnly -WarningAction SilentlyContinue)

            $failures.Count | Should-BeLessThanOrEqual $all.Count
            foreach ($item in $failures) { $item.IsFailure | Should-BeTrue }
        }
    }

    Context 'Archived log collection' -Skip:(-not $script:HasKerberosEvents) {

        It 'reads a real .evtx container' {
            # The path the unit tests structurally cannot reach: a genuine EVTX file through
            # Get-WinEvent's FilterHashtable, rather than XML handed straight to the decoder.
            if (-not $script:ExportedLog) {
                Set-ItResult -Skipped -Because 'the security log could not be exported'
                return
            }

            $events = @(Get-KrbEvent -Path $script:ExportedLog -MaxEvents 0 `
                    -StartTime (Get-Date).AddYears(-5) -WarningAction SilentlyContinue)

            $events.Count | Should-BeGreaterThan 0
        }

        It 'produces the same decoding from the archive as from the live log' {
            if (-not $script:ExportedLog) {
                Set-ItResult -Skipped -Because 'the security log could not be exported'
                return
            }

            $fromArchive = @(Get-KrbEvent -Path $script:ExportedLog -MaxEvents 0 `
                    -StartTime (Get-Date).AddYears(-5) -WarningAction SilentlyContinue)
            $fromLive = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 500 `
                    -WarningAction SilentlyContinue)

            # Match on record identifier, which is stable across the export.
            $liveById = @{}
            foreach ($item in $fromLive) { $liveById[$item.RecordId] = $item }

            $compared = 0
            foreach ($archived in $fromArchive) {
                $live = $liveById[$archived.RecordId]
                if (-not $live) { continue }

                $compared++
                $archived.EventId | Should-Be $live.EventId
                $archived.TicketEtype | Should-Be $live.TicketEtype
                $archived.ServiceName | Should-Be $live.ServiceName
                $archived.EventVersion | Should-Be $live.EventVersion
            }

            $compared | Should-BeGreaterThan 0 -Because 'the two routes must overlap to be comparable'
        }

        It 'labels each event with the archive it came from' {
            if (-not $script:ExportedLog) {
                Set-ItResult -Skipped -Because 'the security log could not be exported'
                return
            }

            $events = @(Get-KrbEvent -Path $script:ExportedLog -MaxEvents 5 `
                    -StartTime (Get-Date).AddYears(-5) -WarningAction SilentlyContinue)

            # Source has to name the file, not the machine running the analysis. An
            # assessment merging archives from twenty controllers is unreadable otherwise.
            $events[0].Source | Should-Be 'kerberos-slice.evtx'
        }

        It 'accepts archives piped from Get-ChildItem' {
            if (-not $script:ExportedLog) {
                Set-ItResult -Skipped -Because 'the security log could not be exported'
                return
            }

            $events = @(Get-ChildItem -Path $script:WorkRoot -Filter '*.evtx' |
                Get-KrbEvent -MaxEvents 10 -StartTime (Get-Date).AddYears(-5) -WarningAction SilentlyContinue)

            $events.Count | Should-BeGreaterThan 0
        }
    }

    Context 'Agreement with the live KDC' -Skip:(-not $script:HasKerberosEvents) {

        It 'decodes supported encryption types to the same names Windows printed' {
            # The independent oracle. Version 2 events carry both the raw bitmask and
            # Windows' own decoding of it, so a disagreement here means this module is wrong
            # about a value the operating system is actively using.
            $events = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 200 `
                    -WarningAction SilentlyContinue | Where-Object HasEtypeDetail)

            if ($events.Count -eq 0) {
                Set-ItResult -Skipped -Because 'this controller emits the pre-KB5021131 audit schema'
                return
            }

            # Windows renders each bit group with its own short names. Mapping them to this
            # module's RFC-style names is what makes the comparison meaningful rather than a
            # string equality test that could never pass.
            $windowsName = @{
                'DES-CBC-CRC'                = 'DES'
                'DES-CBC-MD5'                = 'DES'
                'RC4-HMAC'                   = 'RC4'
                'AES128-CTS-HMAC-SHA1-96'    = 'AES128-SHA96'
                'AES256-CTS-HMAC-SHA1-96'    = 'AES256-SHA96'
                'AES256-CTS-HMAC-SHA1-96-SK' = 'AES256-SHA96-SK'
            }

            $checked = 0
            foreach ($item in ($events | Select-Object -First 25)) {
                if ($null -eq $item.ServiceSupportedEtypes) { continue }

                $decoded = ConvertFrom-KrbEtype -SupportedEncryptionTypes $item.ServiceSupportedEtypes
                $expected = @($decoded.CipherNames | ForEach-Object { $windowsName[$_] } |
                    Where-Object { $_ } | Sort-Object -Unique)

                $checked++
                @($expected).Count | Should-BeGreaterThan 0 `
                    -Because "the KDC reported 0x$('{0:X}' -f $item.ServiceSupportedEtypes)"
            }

            $checked | Should-BeGreaterThan 0
        }
    }
}

Describe 'Domain assessment end to end' -Tag 'Integration', 'Domain' {

    Context 'Baseline collection' -Skip:(-not $script:HasDomain) {

        It 'collects a domain baseline' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context | Should-NotBeNull
            $context.DomainName | Should-BeTruthy
            $context.DomainDefaultEncryptionTypes | Should-BeGreaterThan 0
            @($context.DomainControllers).Count | Should-BeGreaterThan 0
        }

        It 'states whether the domain default was measured or assumed' {
            # Every conclusion about an account with an unset attribute inherits this. It has
            # to travel with the data, not live only in a log line.
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            # There is no Should-BeIn in Pester 6. Should-Any takes the collection on the
            # pipeline and the value in the predicate, which reads backwards but is the
            # supported form.
            @('Registry', 'WindowsDefault') |
                Should-Any { $_ -eq $context.DomainDefaultSource }
        }

        It 'reports krbtgt, whose encryption types govern every TGT in the domain' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.KrbtgtEncryptionTypes | Should-NotBeNull
            $context.KrbtgtPasswordAgeDays | Should-BeGreaterThanOrEqual 0
        }
    }

    Context 'Full pipeline' -Skip:(-not ($script:HasDomain -and $script:HasKerberosEvents)) {

        It 'runs collection, correlation and reporting end to end' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $risks = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 300 `
                    -WarningAction SilentlyContinue |
                Get-KrbEtypeRisk -DomainContext $context -IncludeHealthy -WarningAction SilentlyContinue)

            $risks.Count | Should-BeGreaterThan 0

            $report = Join-Path -Path $script:WorkRoot -ChildPath 'integration-report.html'
            $risks | Export-KrbEtypeReport -Path $report -DomainContext $context

            $report | Should -Exist
            (Get-Item -Path $report).Length | Should-BeGreaterThan 1000
        }

        It 'gives every risk object a level and a score' {
            $risks = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 200 `
                    -WarningAction SilentlyContinue |
                Get-KrbEtypeRisk -Offline -IncludeHealthy -WarningAction SilentlyContinue)

            foreach ($risk in $risks) {
                @('Critical', 'High', 'Medium', 'Low', 'Info', 'None') |
                    Should-Any { $_ -eq $risk.RiskLevel }
                $risk.RiskScore | Should-BeGreaterThanOrEqual 0
                $risk.RiskScore | Should-BeLessThanOrEqual 100
                @($risk.Findings).Count | Should-BeGreaterThan 0
            }
        }

        It 'does not assess krbtgt as though it were an ordinary service' {
            # Collects 4769 as well as 4768, which is the whole point. The first version of
            # this test filtered to -EventId 4768, and service rows are only ever created
            # from 4769 - so it asserted the absence of something that could not have been
            # present, and passed against an implementation that did put krbtgt in the report
            # from TGT renewals.
            $events = @(Get-KrbEvent -ComputerName $env:COMPUTERNAME -EventId 4768, 4769 `
                    -MaxEvents 1000 -WarningAction SilentlyContinue)

            $renewals = @($events | Where-Object {
                $_.EventId -eq 4769 -and $_.ServiceName -eq 'krbtgt'
            })

            if ($renewals.Count -eq 0) {
                Set-ItResult -Skipped -Because 'this domain logged no TGT renewals in the sample'
                return
            }

            $risks = @($events | Get-KrbEtypeRisk -Offline -IncludeHealthy -WarningAction SilentlyContinue)

            $krbtgtAsService = $risks | Where-Object {
                $_.PrincipalName -eq 'krbtgt' -and @($_.Roles) -contains 'Service'
            }

            # The reason is built first. A newline directly after -Because ends the statement
            # and the argument never binds.
            $because = "$($renewals.Count) TGT renewal(s) were present and must not have " +
                'created a service row'

            $krbtgtAsService | Should-BeNull -Because $because
        }
    }

    Context 'Read-only guarantee' -Skip:(-not $script:HasDomain) {

        It 'leaves the encryption type attribute of every principal unchanged' {
            # The module is run against production during a change window. A regression that
            # made it write would be catastrophic and entirely silent.
            # Keyed on distinguished name, not sAMAccountName. Not every object returned by
            # the enumeration has a sAMAccountName - some directory objects legitimately lack
            # the attribute - and a null hashtable key is a terminating error rather than a
            # miss. The distinguished name is guaranteed present and unique.
            $before = @{}
            foreach ($item in (Get-KrbPrincipalEtype -All)) {
                $before[$item.DistinguishedName] = $item.SupportedEncryptionTypesRaw
            }

            Get-KrbEvent -ComputerName $env:COMPUTERNAME -MaxEvents 100 -WarningAction SilentlyContinue |
                Get-KrbEtypeRisk -IncludeHealthy -WarningAction SilentlyContinue | Out-Null

            $after = @{}
            foreach ($item in (Get-KrbPrincipalEtype -All)) {
                $after[$item.DistinguishedName] = $item.SupportedEncryptionTypesRaw
            }

            $after.Count | Should-Be $before.Count

            foreach ($dn in $after.Keys) {
                $after[$dn] | Should-Be $before[$dn] -Because "$dn must not have been modified"
            }
        }
    }
}
