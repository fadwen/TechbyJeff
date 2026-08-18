function Compare-CaBaseline {
    <#
    .SYNOPSIS
        Compares a fresh set of outcomes against a recorded baseline and reports what moved

    .DESCRIPTION
        Core Functionality:
        Matches fresh outcomes to a stored baseline by scenario name and diffs each pair, in
        both worlds, using the same comparison that produces a promotion diff. Scenarios present
        on only one side are reported as added or missing.

        Business Value:
        This is the assertion a scheduled run is for. Everything else in this module answers
        "what happens"; this answers "what changed since it was approved", which is the question
        that belongs in a nightly job rather than in somebody's head.

        It sees a class of change that policy comparison cannot. A group membership change, a
        role assignment, an edit to a named location, a device falling out of compliance - each
        moves who a policy hits while the policy document sits untouched. Microsoft365DSC finds
        nothing, because nothing it watches drifted. The outcome for a persona nonetheless
        changed, and that shows up here.

        Both worlds are compared, and the distinction matters. Current drift means what the
        tenant enforces has moved. Projected drift means the pilot's blast radius has moved -
        which happens without anyone touching the pilot, because the population it would hit is
        not fixed.

        Use Cases:
        - A nightly run that fails when any persona's experience changes
        - Proving that a migration or a group restructure changed nothing users can feel
        - Reviewing a diff before re-approving a baseline

        Dependencies:
        None.

        Side Effects:
        None. Nothing is written; re-approving a baseline is Export-CaBaseline's job.

        Important:
        A scenario in the baseline with no fresh outcome is reported as Missing, not as removed.
        The usual cause is a failed evaluation rather than a deliberate change to the matrix, and
        those two need to look different or a transient HTTP error reads as a policy change.

    .PARAMETER Outcome
        [System.Object[]] (Mandatory, Accepts Pipeline Input)

        The fresh outcomes, from Invoke-CaScenarioMatrix.

    .PARAMETER Baseline
        [System.Object] (Mandatory in the Object set, No Pipeline Support)

        The baseline object from Export-CaBaseline.

    .PARAMETER Path
        [System.String] (Mandatory in the Path set, No Pipeline Support)

        A baseline JSON file to read.

    .OUTPUTS
        PSCustomObject per scenario, carrying Status, HasChange, CurrentDelta, ProjectedDelta
        and Summary. Status is Unchanged, Changed, Added, Missing or Failed.

    .EXAMPLE
        PS> Expand-CaScenario -Matrix $matrix | Invoke-CaScenarioMatrix |
                Compare-CaBaseline -Path .\ca-baseline.json |
                Where-Object HasChange

        DESCRIPTION: Runs the matrix and reports only the scenarios that have moved
        OUTPUT: One row per changed scenario
        DURATION: The matrix run, plus milliseconds
        USE CASE: The nightly job

    .EXAMPLE
        PS> $drift = $outcomes | Compare-CaBaseline -Path .\ca-baseline.json
        PS> $drift | Where-Object { $_.Status -eq 'Missing' }

        DESCRIPTION: Finds scenarios the run did not produce, usually a failed evaluation
        OUTPUT: One row per scenario in the baseline with no fresh outcome
        DURATION: Instant
        USE CASE: Telling a broken run apart from a real change before acting on the diff

    .EXAMPLE
        PS> $outcomes | Compare-CaBaseline -Path .\ca-baseline.json |
                Where-Object { $_.CurrentDelta.BecomesEffectivelyBlocked } |
                Select-Object Scenario, Summary

        DESCRIPTION: The severe case - a persona that used to get in and now does not
        OUTPUT: One row per newly locked out persona
        DURATION: Instant
        USE CASE: The alert worth waking somebody for, as opposed to the report worth reading

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.3.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Outcome,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [ValidateNotNull()]
        [object]$Baseline,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    begin {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "No baseline at '$Path'."
            }
            $Baseline = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }

        $stored = Get-CaProperty -InputObject $Baseline -Name 'scenarios'
        if ($null -eq $stored) {
            throw 'The baseline has no scenarios property. It may be from a different tool.'
        }

        $storedNames = @()
        if ($stored -is [System.Collections.IDictionary]) {
            $storedNames = @($stored.Keys)
        } elseif ($stored.PSObject) {
            $storedNames = @($stored.PSObject.Properties | Select-Object -ExpandProperty Name)
        }

        $seen = New-Object System.Collections.Generic.List[string]
        $results = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($item in $Outcome) {
            if ($null -eq $item) { continue }

            $name = [string]$item.Scenario
            $seen.Add($name)

            if ($item.PSObject.Properties['Failed'] -and $item.Failed) {
                $results.Add([PSCustomObject]@{
                    PSTypeName     = 'CaOutcome.Drift'
                    Scenario       = $name
                    Status         = 'Failed'
                    HasChange      = $false
                    CurrentDelta   = $null
                    ProjectedDelta = $null
                    Summary        = "Evaluation failed: $($item.Error)"
                })
                continue
            }

            $entry = Get-CaProperty -InputObject $stored -Name $name
            if ($null -eq $entry) {
                $results.Add([PSCustomObject]@{
                    PSTypeName     = 'CaOutcome.Drift'
                    Scenario       = $name
                    Status         = 'Added'
                    HasChange      = $true
                    CurrentDelta   = $null
                    ProjectedDelta = $null
                    Summary        = 'Not in the baseline; new scenario or a renamed one'
                })
                continue
            }

            $currentDelta = Compare-CaEffectiveControl `
                -From (ConvertFrom-CaBaselineEntry -Entry (Get-CaProperty -InputObject $entry -Name 'current')) `
                -To $item.Current
            $projectedDelta = Compare-CaEffectiveControl `
                -From (ConvertFrom-CaBaselineEntry -Entry (Get-CaProperty -InputObject $entry -Name 'projected')) `
                -To $item.Projected

            $hasChange = $currentDelta.HasChange -or $projectedDelta.HasChange

            $parts = New-Object System.Collections.Generic.List[string]
            if ($currentDelta.HasChange) { $parts.Add("enforced now: $($currentDelta.Summary)") }
            if ($projectedDelta.HasChange) { $parts.Add("after promotion: $($projectedDelta.Summary)") }
            $summary = 'No change'
            if ($parts.Count -gt 0) { $summary = $parts -join ' | ' }

            $results.Add([PSCustomObject]@{
                PSTypeName     = 'CaOutcome.Drift'
                Scenario       = $name
                Status         = $(if ($hasChange) { 'Changed' } else { 'Unchanged' })
                HasChange      = $hasChange
                CurrentDelta   = $currentDelta
                ProjectedDelta = $projectedDelta
                Summary        = $summary
            })
        }
    }

    end {
        # Reported last so that a missing scenario reads as a gap in the run rather than as a
        # result of it. The distinction from "removed" is the point: the usual cause is a failed
        # evaluation, and a transient HTTP error must not look like a policy change.
        foreach ($name in ($storedNames | Sort-Object)) {
            if ($seen -contains $name) { continue }

            $results.Add([PSCustomObject]@{
                PSTypeName     = 'CaOutcome.Drift'
                Scenario       = $name
                Status         = 'Missing'
                HasChange      = $true
                CurrentDelta   = $null
                ProjectedDelta = $null
                Summary        = ('In the baseline but not in this run - a failed evaluation, ' +
                    'or the scenario was taken out of the matrix')
            })
        }

        $results.ToArray()
    }
}
