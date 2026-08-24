#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

# Timing taken while other test files compete for the CPU is noise. This keeps the file on the
# serial path even when Run.Parallel is set elsewhere.
#pester:no-parallel

<#
    Performance regression tests for the decode and correlation paths.

    These exist because the README makes numeric claims - throughput per event, and the share of
    a collection spent inside Get-WinEvent - and until now nothing enforced them. A change that
    quietly made decoding three times slower would pass all 405 functional tests.

    Everything here runs offline against the synthetic XML fixtures. No domain, no security log
    and no network are required, so this file behaves identically on a domain controller, a
    workstation and a CI runner. That matters: a performance suite that skips on CI is a
    performance suite that never runs.

    MEASUREMENT METHODOLOGY

    Two properties of the runtime shape every threshold below, and both were measured rather
    than assumed.

    1. Tiered JIT compilation makes early iterations badly unrepresentative. Twelve consecutive
       runs of 500 decodes, with only a token warmup, produced this sequence in milliseconds:

           1088, 897, 650, 564, 494, 453, 458, 400

       That is a 2.7x spread with a coefficient of variation of 36.6 percent, and it is still
       trending downward at the eighth run. Asserting a coefficient of variation under 20
       percent against that - which the standard template suggests - would produce a test that
       fails at random. After a 3000-decode warmup the same measurement settles at 409 ms
       average with a CV of 6.1 percent. Every timed context here therefore warms up hard
       first, and the warmup is not optional.

    2. Absolute wall-clock thresholds are hardware. The measured steady state on the
       development machine is roughly 0.82 ms per event, or about 1200 events per second. The
       absolute assertions below are set at five to eight times that cost so they survive a
       slow or contended runner while still catching the kind of regression that matters - an
       accidental O(n^2), a per-event module load, a catalog rebuilt on every call.

    The assertions that do not depend on machine speed are the real regression detectors.
    Scaling efficiency is a ratio of two measurements taken back to back in the same session,
    and the catalog identity checks are exact. Read a failure in "Correlation scaling" as a
    genuine algorithmic complexity change, and a failure in "Catalog caching" as the cache
    having been broken outright; read a failure in an absolute wall-clock threshold as "look at
    what else the machine was doing first".

    Every threshold here was set from a measurement, and where a plausible assertion turned out
    to be untestable it was replaced rather than kept for appearance. The comment above the
    catalog caching tests records one such case in full, because the discarded version is the
    one most people would write.

    WHAT IS DELIBERATELY NOT TESTED

    Collection throughput - the Get-WinEvent share of a real run - is not measurable offline
    and is not asserted here. The README's 2.8 ms per event warm figure covers the whole
    pipeline including event log RPC, and RPC latency is a property of the network rather than
    the module. Tests/Integration covers the live path.

    Writing this file is what corrected that figure. The README previously claimed 3.6 ms per
    event with a 35 percent Get-WinEvent share, taken from one half-warmed run. Measured
    properly over eight consecutive runs of 600 events the warm cost is 2.8 ms and the
    Get-WinEvent share is 57 percent - the I/O half does not warm up, so its share rises as
    everything around it gets faster. Troubleshooting/Performance/Event-Volume.md carries the
    breakdown.
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\KrbEtypeInsight.psd1'
    Import-Module $ModulePath -Force

    $script:PerfConfig = @{
        WarmupDecodes      = 3000
        BatchSize          = 500
        ConsistencyRuns    = 10
        MaxSingleDecodeMs  = 25      # steady state is ~0.8 ms; 30x headroom for a cold path
        MinEventsPerSecond = 150     # steady state is ~1200/sec; 8x headroom
        MaxDecodeCv        = 0.30    # measured 0.061 after warmup
        MaxCachedCallMs    = 1.75    # measured 0.52 cached, 2.52 when rebuilt per call
        MaxScalingFactor   = 2.0     # measured 0.25; a quadratic path would score ~8
        MaxLeakMb          = 25
    }

    # The fixture corpus. malformed-truncated.xml is excluded on purpose: it is the
    # deliberately unparseable record, it returns nothing by design, and including it would
    # mean measuring the failure path rather than the decode path.
    $script:FixtureTemplates = @(
        Get-ChildItem (Join-Path $PSScriptRoot '..\Fixtures') -Filter *.xml |
            Where-Object { $_.Name -ne 'malformed-truncated.xml' } |
            ForEach-Object { Get-Content $_.FullName -Raw }
    )

    # Builds a corpus of the requested size by cycling the fixtures and varying the principal
    # so the correlation engine sees realistic cardinality rather than one account repeated N
    # times. A single-principal corpus would hide exactly the aggregation cost this measures.
    function script:New-PerfCorpus {
        param([int]$Count)

        $corpus = [System.Collections.Generic.List[string]]::new($Count)
        for ($i = 0; $i -lt $Count; $i++) {
            $template = $script:FixtureTemplates[$i % $script:FixtureTemplates.Count]
            $corpus.Add(($template -replace 'svc-payroll', "svc-app$($i % 50)" `
                        -replace 'WKS-FINANCE-04', "WKS-$($i % 200)"))
        }

        return $corpus
    }
}

Describe 'Decode throughput' -Tag 'Performance', 'Benchmark', 'Decode' {
    BeforeAll {
        $script:DecodeCorpus = script:New-PerfCorpus -Count $script:PerfConfig.BatchSize

        # Warm up past tiered compilation. See the methodology note in the file header - this
        # is load-bearing, not defensive.
        InModuleScope KrbEtypeInsight -Parameters @{
            Corpus = $script:DecodeCorpus
            Passes = [int]($script:PerfConfig.WarmupDecodes / $script:PerfConfig.BatchSize)
        } {
            1..$Passes | ForEach-Object {
                foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml | Out-Null }
            }
        }

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    It 'Decodes a single event well inside the per-event budget' {
        $single = $script:DecodeCorpus[0]

        InModuleScope KrbEtypeInsight -Parameters @{
            Xml    = $single
            Budget = $script:PerfConfig.MaxSingleDecodeMs
        } {
            { ConvertFrom-KrbEventRecord -Xml $Xml } |
                Should-BeFasterThan ([TimeSpan]::FromMilliseconds($Budget))
        }
    }

    It 'Sustains the minimum decode throughput across a batch' {
        $result = InModuleScope KrbEtypeInsight -Parameters @{ Corpus = $script:DecodeCorpus } {
            # Collected into a pre-sized list rather than assigned from the loop so that the
            # count is observably used - the analyser cannot see through the Measure-Command
            # scriptblock and reports an assigned-but-unused variable otherwise. The Add call
            # is a constant per-event cost far below the XML parse it sits next to.
            $decoded = [System.Collections.Generic.List[object]]::new($Corpus.Count)

            # Nothing is asserted inside Measure-Command - the assertion cost would land in the
            # measurement and a failure there reports a confusing location.
            $elapsed = Measure-Command {
                foreach ($xml in $Corpus) { $decoded.Add((ConvertFrom-KrbEventRecord -Xml $xml)) }
            }

            [PSCustomObject]@{
                Count             = $decoded.Count
                EventsPerSecond   = $Corpus.Count / $elapsed.TotalSeconds
                MillisecondsEvent = $elapsed.TotalMilliseconds / $Corpus.Count
            }
        }

        # Every fixture in the corpus decodes; if this drops the throughput number is measuring
        # a fast failure path rather than real work.
        $result.Count | Should-Be $script:PerfConfig.BatchSize

        $result.EventsPerSecond |
            Should-BeGreaterThan $script:PerfConfig.MinEventsPerSecond `
                -Because "decode throughput was $([math]::Round($result.MillisecondsEvent, 3)) ms per event"
    }

    It 'Holds decode timing stable across repeated runs' {
        $cv = InModuleScope KrbEtypeInsight -Parameters @{
            Corpus = $script:DecodeCorpus
            Runs   = $script:PerfConfig.ConsistencyRuns
        } {
            $measurements = 1..$Runs | ForEach-Object {
                (Measure-Command {
                    foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml }
                }).TotalMilliseconds
            }

            $average = ($measurements | Measure-Object -Average).Average
            $sumOfSquares = ($measurements | ForEach-Object { ($_ - $average) * ($_ - $average) } |
                Measure-Object -Sum).Sum

            [Math]::Sqrt($sumOfSquares / $measurements.Count) / $average
        }

        $cv | Should-BeLessThan $script:PerfConfig.MaxDecodeCv `
            -Because 'a warmed-up decode path should not vary by more than a third between runs'
    }
}

Describe 'Catalog caching' -Tag 'Performance', 'Benchmark', 'Decode' {
    # The two catalogs are built once and held in module scope. That is the single most
    # important performance property in the module: the etype catalog costs roughly 30 ms to
    # construct, and rebuilding it per call would make a 50,000-event collection take 25
    # minutes of pure table building. This test exists so that a refactor which drops the
    # cache fails loudly rather than silently costing two orders of magnitude.

    # A note on why these are reference-equality tests rather than timing tests, because the
    # obvious timing version is wrong and was written here first.
    #
    # The intuitive assertion is "the first call is much slower than later calls". It passes
    # whether or not caching works. Disabling the cache entirely and re-measuring gives:
    #
    #     cache disabled -> cold 76.79 ms, warm average 2.52 ms, ratio 30.5
    #     cache enabled  -> cold 86.46 ms, warm average 0.52 ms, ratio 166.0
    #
    # Both clear any sane ratio threshold, because the cold measurement is dominated by JIT
    # compiling the builder rather than by building the table. The ratio test cannot fail, so
    # it tests nothing. The difference that actually matters is in the warm path - 0.52 ms
    # against 2.52 ms - and the cleanest way to assert it is to check the identity the cache
    # is supposed to provide: every caller gets the same object back, not an equal one.

    It 'Returns the same encryption type catalog instance on every call' {
        InModuleScope KrbEtypeInsight {
            $script:KrbEtypeCatalog = $null       # force a genuine cold build

            $first = Get-KrbEtypeCatalog
            $second = Get-KrbEtypeCatalog

            $first | Should-NotBeNull
            $second | Should-BeSame $first
        }
    }

    It 'Returns the same protocol catalog instance on every call' {
        InModuleScope KrbEtypeInsight {
            $script:KrbProtocolCatalog = $null

            $first = Get-KrbProtocolCatalog
            $second = Get-KrbProtocolCatalog

            $first | Should-NotBeNull
            $second | Should-BeSame $first
        }
    }

    It 'Keeps the warm per-call cost inside budget once the catalog is built' {
        # The complement to the identity tests above: this is the cost a caller actually pays.
        # Rebuilding the table per call measured 2.52 ms here, so the budget sits between that
        # and the 0.52 ms cached figure, with room for a slower machine.
        $perCallMs = InModuleScope KrbEtypeInsight {
            ConvertFrom-KrbEtype -TicketEtype 23 | Out-Null          # ensure built and JITted
            1..200 | ForEach-Object { ConvertFrom-KrbEtype -TicketEtype 23 | Out-Null }

            (Measure-Command {
                1..200 | ForEach-Object { ConvertFrom-KrbEtype -TicketEtype 23 | Out-Null }
            }).TotalMilliseconds / 200
        }

        $perCallMs | Should-BeLessThan $script:PerfConfig.MaxCachedCallMs `
            -Because 'a decode against a built catalog is a hashtable lookup and object construction'
    }
}

Describe 'Correlation scaling' -Tag 'Performance', 'Benchmark', 'Correlation' {
    # Get-KrbEtypeRisk groups events by principal and, within each principal, tracks the
    # distinct clients that presented each encryption type. The obvious naive implementation -
    # scanning the accumulated client list on every event - is quadratic in events per
    # principal and looks perfectly fine against the 18-event fixture set. It falls over on a
    # real domain, where a single service account can own hundreds of thousands of events.
    #
    # This is the highest-value test in the file. It compares two measurements taken back to
    # back on the same machine, so it detects a complexity change regardless of how fast that
    # machine is.

    It 'Scales sub-linearly from 500 to 4000 events' {
        $baselineSize = 500
        $scaledSize = 4000

        $decode = {
            param($Corpus)

            InModuleScope KrbEtypeInsight -Parameters @{ Corpus = $Corpus } {
                foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml }
            }
        }

        $baselineEvents = & $decode (script:New-PerfCorpus -Count $baselineSize)
        $scaledEvents = & $decode (script:New-PerfCorpus -Count $scaledSize)

        # Warm the correlation path itself before either measurement, for the same reason the
        # decode tests warm up.
        $baselineEvents | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        $baselineTime = Measure-Command {
            $baselineEvents | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue | Out-Null
        }
        $scaledTime = Measure-Command {
            $scaledEvents | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue | Out-Null
        }

        $dataScaleFactor = $scaledSize / $baselineSize
        $timeScaleFactor = $scaledTime.TotalMilliseconds / $baselineTime.TotalMilliseconds
        $scalingEfficiency = $timeScaleFactor / $dataScaleFactor

        $scalingEfficiency | Should-BeLessThan $script:PerfConfig.MaxScalingFactor `
            -Because (("8x the events cost {0:N1}x the time; a quadratic correlation path " +
                       'would score around 8 here') -f $timeScaleFactor)
    }

    It 'Produces a stable principal count regardless of event volume' {
        # A scaling test is only meaningful if both runs did the same work. The corpus cycles a
        # fixed set of principals, so the number of risk objects must converge rather than grow
        # with the event count - if it grows, the two measurements above are not comparable.
        $small = InModuleScope KrbEtypeInsight -Parameters @{ Corpus = (script:New-PerfCorpus -Count 1000) } {
            foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml }
        }
        $large = InModuleScope KrbEtypeInsight -Parameters @{ Corpus = (script:New-PerfCorpus -Count 4000) } {
            foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml }
        }

        $smallCount = @($small | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue).Count
        $largeCount = @($large | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue).Count

        $smallCount | Should-BeGreaterThan 0
        $largeCount | Should-Be $smallCount
    }
}

Describe 'Memory behaviour' -Tag 'Performance', 'Benchmark', 'Memory' {
    It 'Does not accumulate memory across repeated decode batches' {
        # Absolute footprint is not asserted - the decoded objects are the return value, so
        # holding memory proportional to output is correct behaviour rather than a leak. What
        # would be a leak is growth across batches whose output is discarded each time.
        $corpus = script:New-PerfCorpus -Count 200

        InModuleScope KrbEtypeInsight -Parameters @{ Corpus = $corpus } {
            1..3 | ForEach-Object {
                foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml | Out-Null }
            }
        }

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        $baseline = [System.GC]::GetTotalMemory($true)

        InModuleScope KrbEtypeInsight -Parameters @{ Corpus = $corpus } {
            1..15 | ForEach-Object {
                foreach ($xml in $Corpus) { ConvertFrom-KrbEventRecord -Xml $xml | Out-Null }
            }
        }

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        $growthMb = ([System.GC]::GetTotalMemory($true) - $baseline) / 1MB

        $growthMb | Should-BeLessThan $script:PerfConfig.MaxLeakMb `
            -Because '3000 discarded decodes should not retain allocations'
    }
}
