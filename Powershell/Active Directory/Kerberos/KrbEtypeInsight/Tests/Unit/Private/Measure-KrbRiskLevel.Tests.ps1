#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Risk summarisation.

    The property worth defending here is that Level and Score answer different questions and
    must not be derived from one another. Level is the worst thing present, which decides
    whether a principal blocks the change. Score is how much is wrong, which orders the
    backlog once a hundred principals all come back Critical.

    Deriving Level from Score - the obvious simplification, and the one every scoring scheme
    drifts towards - loses the distinction: four Medium findings can total the same as one
    Critical, and treating them as equivalent puts a tidy-up task ahead of an outage.

    Blast radius scales Score and must never touch Level. A widely used healthy service must
    not outrank a broken obscure one, and a principal with no findings must stay at zero no
    matter how many clients depend on it - blast radius multiplies a problem, it cannot
    create one.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Measure-KrbRiskLevel' -Tag 'Unit', 'Private' {

    Context 'Level selection' {

        It 'reports <Severity> as the level when it is the worst present' -ForEach @(
            @{ Severity = 'Critical' }
            @{ Severity = 'High' }
            @{ Severity = 'Medium' }
            @{ Severity = 'Low' }
            @{ Severity = 'Info' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Severity = $Severity } {
                $finding = New-KrbRiskFinding -Code 'KRB001' -Severity $Severity `
                    -Title 'Test' -Detail 'Test detail'

                (Measure-KrbRiskLevel -Finding @($finding)).Level | Should-Be $Severity
            }
        }

        It 'takes the worst severity, not the most common' {
            InModuleScope KrbEtypeInsight {
                $findings = @(
                    New-KrbRiskFinding -Code 'KRB010' -Severity 'Medium' -Title 'a' -Detail 'a'
                    New-KrbRiskFinding -Code 'KRB013' -Severity 'Medium' -Title 'b' -Detail 'b'
                    New-KrbRiskFinding -Code 'KRB003' -Severity 'Medium' -Title 'c' -Detail 'c'
                    New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title 'd' -Detail 'd'
                )

                (Measure-KrbRiskLevel -Finding $findings).Level | Should-Be 'Critical'
            }
        }

        It 'reports None for an empty finding set' {
            InModuleScope KrbEtypeInsight {
                $summary = Measure-KrbRiskLevel -Finding @()

                $summary.Level | Should-Be 'None'
                $summary.Score | Should-Be 0
            }
        }
    }

    Context 'Score accumulation' {

        It 'weights a single Critical above any number of Mediums' {
            # The scheme is spread deliberately so that housekeeping cannot outrank an
            # outage. Three Mediums is 30; one Critical is 40.
            InModuleScope KrbEtypeInsight {
                $threeMedium = @(1..3 | ForEach-Object {
                    New-KrbRiskFinding -Code 'KRB010' -Severity 'Medium' -Title "m$_" -Detail 'd'
                })
                $oneCritical = @(New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title 'c' -Detail 'd')

                $mediumScore = (Measure-KrbRiskLevel -Finding $threeMedium).Score
                $criticalScore = (Measure-KrbRiskLevel -Finding $oneCritical).Score

                $criticalScore | Should-BeGreaterThan $mediumScore
            }
        }

        It 'contributes nothing for an Info finding' {
            InModuleScope KrbEtypeInsight {
                $finding = New-KrbRiskFinding -Code 'KRB009' -Severity 'Info' -Title 'ok' -Detail 'ok'
                (Measure-KrbRiskLevel -Finding @($finding)).Score | Should-Be 0
            }
        }

        It 'counts findings by severity' {
            InModuleScope KrbEtypeInsight {
                $findings = @(
                    New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title 'a' -Detail 'a'
                    New-KrbRiskFinding -Code 'KRB005' -Severity 'Critical' -Title 'b' -Detail 'b'
                    New-KrbRiskFinding -Code 'KRB003' -Severity 'High' -Title 'c' -Detail 'c'
                )

                $summary = Measure-KrbRiskLevel -Finding $findings

                $summary.CriticalCount | Should-Be 2
                $summary.HighCount | Should-Be 1
                $summary.MediumCount | Should-Be 0
            }
        }

        It 'caps the score at 100' {
            InModuleScope KrbEtypeInsight {
                $findings = @(1..10 | ForEach-Object {
                    New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title "c$_" -Detail 'd'
                })

                (Measure-KrbRiskLevel -Finding $findings -ClientCount 5000).Score | Should-Be 100
            }
        }
    }

    Context 'Blast radius' {

        It 'raises the score of a principal with many dependent clients' {
            InModuleScope KrbEtypeInsight {
                $finding = @(New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title 'a' -Detail 'a')

                $few = (Measure-KrbRiskLevel -Finding $finding -ClientCount 1).Score
                $many = (Measure-KrbRiskLevel -Finding $finding -ClientCount 100).Score

                $many | Should-BeGreaterThan $few
            }
        }

        It 'scales logarithmically, not linearly' {
            # The difference between one client and ten is a change in kind. The difference
            # between three hundred and three thousand is not - both are "the whole estate" -
            # and a linear scale would let a single popular service saturate the ranking.
            InModuleScope KrbEtypeInsight {
                $finding = @(New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' -Title 'a' -Detail 'a')

                $ten = (Measure-KrbRiskLevel -Finding $finding -ClientCount 10).RadiusUplift
                $hundred = (Measure-KrbRiskLevel -Finding $finding -ClientCount 100).RadiusUplift
                $thousand = (Measure-KrbRiskLevel -Finding $finding -ClientCount 1000).RadiusUplift

                $ten | Should-Be 10
                $hundred | Should-Be 20
                $thousand | Should-Be 30
            }
        }

        It 'never changes the level' {
            # A healthy service used by the whole estate is still healthy. Letting client
            # count raise the level would put it above a broken but obscure one.
            InModuleScope KrbEtypeInsight {
                $finding = @(New-KrbRiskFinding -Code 'KRB010' -Severity 'Medium' -Title 'a' -Detail 'a')

                (Measure-KrbRiskLevel -Finding $finding -ClientCount 1).Level | Should-Be 'Medium'
                (Measure-KrbRiskLevel -Finding $finding -ClientCount 10000).Level | Should-Be 'Medium'
            }
        }

        It 'adds no uplift to a principal with nothing wrong' {
            # Blast radius multiplies a problem; it cannot create one. A popular service with
            # no findings must score zero, or the report fills with healthy busy services.
            InModuleScope KrbEtypeInsight {
                $finding = @(New-KrbRiskFinding -Code 'KRB009' -Severity 'Info' -Title 'ok' -Detail 'ok')

                (Measure-KrbRiskLevel -Finding $finding -ClientCount 5000).Score | Should-Be 0
            }
        }
    }

    Context 'Finding construction' {

        It 'rejects a malformed finding code' {
            InModuleScope KrbEtypeInsight {
                # Codes are a stable identifier an organisation tracks across quarters.
                # Letting an arbitrary string through would break that comparison silently.
                { New-KrbRiskFinding -Code 'BAD' -Severity 'High' -Title 'a' -Detail 'a' } | Should-Throw
                { New-KrbRiskFinding -Code 'KRB1' -Severity 'High' -Title 'a' -Detail 'a' } | Should-Throw
            }
        }

        It 'rejects an unrecognised severity' {
            InModuleScope KrbEtypeInsight {
                { New-KrbRiskFinding -Code 'KRB001' -Severity 'Catastrophic' -Title 'a' -Detail 'a' } |
                    Should-Throw
            }
        }

        It 'accepts a finding with no recommended action' {
            # Findings that describe a safe state legitimately have nothing to recommend.
            InModuleScope KrbEtypeInsight {
                $finding = New-KrbRiskFinding -Code 'KRB009' -Severity 'Info' -Title 'ok' -Detail 'ok'
                $finding.RecommendedAction | Should-BeNull
            }
        }

        It 'emits the declared PSTypeName' {
            InModuleScope KrbEtypeInsight {
                $finding = New-KrbRiskFinding -Code 'KRB001' -Severity 'High' -Title 'a' -Detail 'a'
                $finding.PSTypeNames[0] | Should-Be 'KrbEtypeInsight.Finding'
            }
        }
    }
}
