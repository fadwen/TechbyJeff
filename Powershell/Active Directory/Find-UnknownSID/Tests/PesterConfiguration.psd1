# PesterConfiguration.psd1
# Enterprise-grade Pester configuration following pester.instructions.md standards

@{
    Run = @{
        Path = @('./Tests/Unit', './Tests/Integration', './Tests/Performance', './Tests/Security')
        PassThru = $true
        Throw = $true
        Container = $null
    }

    Output = @{
        Verbosity = 'Detailed'
        StackTraceVerbosity = 'Filtered'
        CIFormat = 'None'
    }

    CodeCoverage = @{
        Enabled = $true
        Path = @('./Public/*.ps1', './Private/*.ps1', './Classes/*.ps1')
        OutputFormat = 'JaCoCo'
        OutputPath = './Tests/Results/Coverage.xml'
        Threshold = 80
        UseBreakpoints = $false
        SingleHitBreakpoints = $true
    }

    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = './Tests/Results/TestResults.xml'
        TestSuiteName = 'Find-UnknownSID'
    }

    Filter = @{
        Tag = @()
        ExcludeTag = @()
        Line = @()
        ExcludeLine = @()
        FullName = @()
    }

    Debug = @{
        ShowFullErrors = $false
        WriteDebugMessages = $false
        WriteDebugMessagesFrom = @()
        ShowNavigationMarkers = $false
    }

    Should = @{
        ErrorAction = 'Stop'
        DisableV5 = $false
    }
}
