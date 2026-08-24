#Requires -Version 7.6

function Measure-KrbRiskLevel {
    <#
    .SYNOPSIS
        Reduces a set of findings to a single risk level and score

    .DESCRIPTION
        Produces two summary values from a principal's findings, because neither alone
        answers the question an administrator is asking.

        - Level is the highest severity present. It answers "how bad is the worst thing here",
          which is what decides whether this principal blocks the change.
        - Score is the capped sum of finding weights. It answers "how much is wrong here",
          which is what orders a remediation backlog when a hundred principals all come back
          Critical.

        Deriving Level from the score instead - the obvious simplification - loses the
        distinction. Four Medium findings and one Critical finding can reach the same total,
        and treating them as equivalent puts a tidy-up task ahead of an outage.

        Blast radius scales the score but never the level. A principal with one critical
        finding and 300 dependent clients and a principal with one critical finding and one
        dependent client are both Critical - both will break - but the first should be worked
        first. Letting client count raise the level would let a widely-used but healthy
        service outrank a broken but obscure one.

    .PARAMETER Finding
        [System.Object[]] (Mandatory, No Pipeline Support)

        The findings to summarise. An empty set is valid and yields a level of None.

    .PARAMETER ClientCount
        [System.Int32] (Optional, No Pipeline Support)

        Number of distinct clients depending on the principal. Applies a logarithmic uplift
        to the score. Logarithmic rather than linear because the difference between one
        client and ten is a change in kind, while the difference between three hundred and
        three thousand is not - both are "the whole estate".

    .EXAMPLE
        PS> Measure-KrbRiskLevel -Finding $findings -ClientCount 12

        DESCRIPTION: Summarises a principal's findings with its blast radius
        OUTPUT: An object carrying Level, Score and the per-severity counts
        USE CASE: Called once per principal by Get-KrbEtypeRisk

    .OUTPUTS
        KrbEtypeInsight.RiskSummary

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Interpreting risk scores: .\Troubleshooting\Common\Risk-Scoring.md
    #>
    [CmdletBinding()]
    [OutputType('KrbEtypeInsight.RiskSummary')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Finding,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ClientCount = 0
    )

    $counts = @{ Critical = 0; High = 0; Medium = 0; Low = 0; Info = 0 }
    $baseScore = 0

    foreach ($item in $Finding) {
        if ($counts.ContainsKey($item.Severity)) { $counts[$item.Severity]++ }
        $baseScore += $item.Weight
    }

    $level = if ($counts.Critical -gt 0)   { 'Critical' }
             elseif ($counts.High -gt 0)   { 'High' }
             elseif ($counts.Medium -gt 0) { 'Medium' }
             elseif ($counts.Low -gt 0)    { 'Low' }
             elseif ($counts.Info -gt 0)   { 'Info' }
             else                          { 'None' }

    # Log base 10 of the client count, scaled. One client contributes nothing, ten contribute
    # 10, a hundred contribute 20. A principal with no findings stays at zero regardless of
    # how many clients use it - blast radius multiplies a problem, it does not create one.
    $radiusUplift = 0
    if ($ClientCount -gt 1 -and $baseScore -gt 0) {
        $radiusUplift = [int][Math]::Round([Math]::Log10($ClientCount) * 10)
    }

    [PSCustomObject]@{
        PSTypeName    = 'KrbEtypeInsight.RiskSummary'
        Level         = $level
        Score         = [Math]::Min(100, $baseScore + $radiusUplift)
        BaseScore     = $baseScore
        RadiusUplift  = $radiusUplift
        CriticalCount = $counts.Critical
        HighCount     = $counts.High
        MediumCount   = $counts.Medium
        LowCount      = $counts.Low
        InfoCount     = $counts.Info
    }
}
