function Export-CaBaseline {
    <#
    .SYNOPSIS
        Records a set of outcomes as a baseline that can be committed and compared against later

    .DESCRIPTION
        Core Functionality:
        Reduces outcomes to the stable subset a comparison needs and writes them as JSON, keyed
        by scenario name and ordered so that the only thing which changes between runs is the
        outcome itself.

        Business Value:
        This is the part that catches what configuration comparison cannot see. Microsoft365DSC
        and every policy-export tool watch the policy: they tell you when its JSON changes. But
        a Conditional Access outcome depends on far more than the policy document - group
        membership, role assignment, named locations, the compliance state of a device. Someone
        joins a group and a policy that already required a compliant device now applies to them.
        No policy changed. No configuration drifted. A user is nonetheless locked out on Monday
        who was not on Friday, and nothing in a config-drift tool will ever mention it.

        A committed baseline of outcomes catches exactly that class of change, because it
        records what the tenant does rather than what it is configured to do.

        Use Cases:
        - Committing an approved set of outcomes next to the matrix that produced it
        - Failing a scheduled run when any persona's experience changes
        - Recording the state before a migration, to prove afterwards what moved

        Dependencies:
        None.

        Side Effects:
        Writes the file at Path when one is given. Supports -WhatIf.

        Important:
        A baseline containing a failed scenario is refused unless -Force. A scenario that
        errored has no outcome, so recording it as absent would make the next comparison report
        it as removed - a change invented by a transient HTTP error, in the artefact whose whole
        value is that its changes are real.

        No timestamp is written. The file is meant to be committed, and a generated-on field
        would produce a diff on every run whether or not anything moved, which trains everyone
        to stop reading the diff. Git already records when the file changed and who changed it.

    .PARAMETER Outcome
        [System.Object[]] (Mandatory, Accepts Pipeline Input)

        Outcomes from Invoke-CaScenarioMatrix or ConvertTo-CaOutcome. Each must carry a
        Scenario name, which is the key the baseline is stored under.

    .PARAMETER Path
        [System.String] (Optional, No Pipeline Support)

        Where to write the JSON. Omit it and the baseline object is returned instead.

    .PARAMETER Force
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Write the baseline even though a scenario failed. The failed scenario is omitted from
        the file, so read the warning before using this on a run you intend to trust.

    .PARAMETER PassThru
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Return the baseline object as well as writing it.

    .OUTPUTS
        PSCustomObject when no Path is given or -PassThru is used. Nothing otherwise.

    .EXAMPLE
        PS> Expand-CaScenario -Matrix $matrix | Invoke-CaScenarioMatrix |
                Export-CaBaseline -Path .\ca-baseline.json

        DESCRIPTION: Records the current outcomes as the approved baseline
        OUTPUT: None; the file is written
        DURATION: Instant once the matrix has run
        USE CASE: The first run, once the outcomes have been reviewed and are considered correct

    .EXAMPLE
        PS> $outcomes | Export-CaBaseline -Path .\ca-baseline.json -WhatIf

        DESCRIPTION: Reports what would be written without writing it
        OUTPUT: The WhatIf message naming the file and the scenario count
        DURATION: Instant
        USE CASE: Checking the scenario count before overwriting an approved baseline

    .EXAMPLE
        PS> $baseline = $outcomes | Export-CaBaseline
        PS> $baseline.scenarios.Keys

        DESCRIPTION: Builds the baseline in memory, without a file
        OUTPUT: The baseline object, and then its scenario names
        DURATION: Instant
        USE CASE: Comparing two runs against each other without committing either

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.3.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Outcome,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $collected = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($item in $Outcome) {
            if ($null -ne $item) { $collected.Add($item) }
        }
    }

    end {
        $failed = @($collected | Where-Object {
            $_.PSObject.Properties['Failed'] -and $_.Failed
        })

        if ($failed.Count -gt 0) {
            $names = ($failed | ForEach-Object { $_.Scenario }) -join ', '
            if (-not $Force) {
                throw ("$($failed.Count) scenario(s) failed and would be missing from this " +
                    "baseline: $names. A later comparison would report them as removed. Fix " +
                    'the run, or pass -Force if you accept a partial baseline.')
            }
            Write-Warning "Writing a partial baseline; these scenarios failed and are omitted: $names"
        }

        $usable = @($collected | Where-Object {
            -not ($_.PSObject.Properties['Failed'] -and $_.Failed)
        })

        $scenarios = [ordered]@{}
        foreach ($item in ($usable | Sort-Object -Property Scenario)) {
            $name = [string]$item.Scenario
            if ([string]::IsNullOrWhiteSpace($name)) {
                throw ('An outcome has no Scenario name. A baseline is keyed by name, so ' +
                    'every outcome needs one - pass -ScenarioName to ConvertTo-CaOutcome.')
            }
            if ($scenarios.Contains($name)) {
                throw "Two outcomes share the scenario name '$name'. Names must be unique."
            }

            $scenarios[$name] = [ordered]@{
                current            = ConvertTo-CaBaselineEntry -EffectiveControl $item.Current
                projected          = ConvertTo-CaBaselineEntry -EffectiveControl $item.Projected
                reportOnlyApplying = [int]$item.ReportOnlyApplying
            }
        }

        $baseline = [PSCustomObject]@{
            PSTypeName    = 'CaOutcome.Baseline'
            schemaVersion = 1
            scenarios     = $scenarios
        }

        if (-not $Path) {
            return $baseline
        }

        $target = "$($scenarios.Count) scenario(s) to $Path"
        if ($PSCmdlet.ShouldProcess($target, 'Write Conditional Access outcome baseline')) {
            $json = $baseline | Select-Object schemaVersion, scenarios | ConvertTo-Json -Depth 20
            Set-Content -Path $Path -Value $json -Encoding utf8
        }

        if ($PassThru) { return $baseline }
    }
}
