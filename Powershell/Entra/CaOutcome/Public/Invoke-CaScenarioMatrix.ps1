function Invoke-CaScenarioMatrix {
    <#
    .SYNOPSIS
        Evaluates a set of scenarios against the tenant and folds each response into an outcome

    .DESCRIPTION
        Core Functionality:
        Sends one What If evaluation per scenario, folds each response with ConvertTo-CaOutcome,
        and returns the outcomes. Throttling and transient failures are retried; a scenario that
        fails anyway is returned marked rather than dropped.

        Business Value:
        This is the step that turns a single what-if check into coverage. The question worth
        asking is never "what happens to this user" but "what happens to everybody, and what
        would promoting the pilot do to them", and answering it means evaluating a grid rather
        than a point.

        Failures are surfaced, not swallowed, because of what happens downstream. If a scenario
        that errored simply vanished from the output, a baseline written from that run would
        record it as absent and the next comparison would report it as removed - a real change,
        invented by a transient HTTP error. So a failed scenario comes back with Failed set, and
        Export-CaBaseline refuses to write a baseline containing one.

        Use Cases:
        - Running a stored matrix before promoting a report-only policy
        - Producing the input for Export-CaBaseline
        - A scheduled run whose output feeds Compare-CaBaseline

        Dependencies:
        - Microsoft.Graph.Authentication, for the default request handler, plus a connection
          with Policy.Read.ConditionalAccess. Checked at run time - supply -RequestHandler and
          the module needs neither.

        Side Effects:
        None in the tenant. Evaluation is a POST but changes nothing; it is a read that happens
        to need a request body.

        Important:
        One API call per scenario, serially. That is deliberate - the endpoint publishes no
        throttling limits, and a matrix run is exactly the traffic shape that finds an
        unpublished one. Use -DelayMillisecond to pace a large run.

    .PARAMETER Scenario
        [System.Object[]] (Mandatory, Accepts Pipeline Input)

        Scenarios from Expand-CaScenario.

    .PARAMETER RequestHandler
        [System.Management.Automation.ScriptBlock] (Optional, No Pipeline Support)

        A scriptblock taking the request body and the URI and returning the raw response.
        Defaults to Invoke-MgGraphRequest.

        Business Context: This is the seam that keeps the module dependency-free and testable
        without a tenant. It is also how you drive the call through an existing authenticated
        session, a proxy, or a recorded fixture.

    .PARAMETER Uri
        [System.String] (Optional, No Pipeline Support)

        The evaluate endpoint, should a national cloud or a future version need a different one.

    .PARAMETER MaxRetry
        [System.Int32] (Optional, No Pipeline Support)

        Retries per scenario after a throttle or transient failure. Defaults to 4.

    .PARAMETER InitialBackoffSecond
        [System.Int32] (Optional, No Pipeline Support)

        First backoff in seconds, doubling per attempt. A Retry-After from the server wins.

    .PARAMETER DelayMillisecond
        [System.Int32] (Optional, No Pipeline Support)

        A pause between scenarios. Zero by default; raise it to pace a large matrix rather than
        discovering the throttle.

    .OUTPUTS
        PSCustomObject per scenario - the ConvertTo-CaOutcome result with Failed and Error added.
        A failed scenario has Failed true and null Current, Projected and Delta.

    .EXAMPLE
        PS> Expand-CaScenario -Matrix $matrix | Invoke-CaScenarioMatrix

        DESCRIPTION: Runs every scenario in the matrix against the tenant
        OUTPUT: One outcome per scenario
        DURATION: About a second per scenario
        USE CASE: The whole grid, before promoting a report-only policy

    .EXAMPLE
        PS> $outcomes = Expand-CaScenario -Matrix $matrix |
                Invoke-CaScenarioMatrix -DelayMillisecond 250
        PS> $outcomes | Where-Object { $_.Delta.BecomesEffectivelyBlocked } |
                Select-Object Scenario, @{n='Why';e={$_.Delta.Summary}}

        DESCRIPTION: Paces a large run, then keeps only the personas a promotion would lock out
        OUTPUT: One row per persona that stops getting in
        DURATION: Scenario count times about 1.3 seconds
        USE CASE: The blast radius question, answered before anything is enforced

    .EXAMPLE
        PS> Expand-CaScenario -Matrix $matrix |
                Invoke-CaScenarioMatrix -RequestHandler { param($b, $u) $recorded[$b.signInIdentity.userId] }

        DESCRIPTION: Replays recorded responses instead of calling Graph
        OUTPUT: Outcomes folded from the recordings
        DURATION: Instant
        USE CASE: Testing the matrix and the assertions over it without a tenant

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17

        The Conditional Access What If API is in beta and its shape may change.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Scenario,

        [Parameter()]
        [scriptblock]$RequestHandler,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Uri = 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate',

        [Parameter()]
        [ValidateRange(0, 20)]
        [int]$MaxRetry = 4,

        [Parameter()]
        [ValidateRange(0, 300)]
        [int]$InitialBackoffSecond = 2,

        [Parameter()]
        [ValidateRange(0, 60000)]
        [int]$DelayMillisecond = 0
    )

    begin {
        $index = 0
    }

    process {
        foreach ($item in $Scenario) {
            if ($null -eq $item) { continue }

            $name = [string](Get-CaProperty -InputObject $item -Name 'Name')
            $index++

            if ($DelayMillisecond -gt 0 -and $index -gt 1) {
                Start-Sleep -Milliseconds $DelayMillisecond
            }

            Write-Verbose "Evaluating scenario $index : $name"

            try {
                $body = ConvertTo-CaEvaluateBody -Scenario $item
                $response = Invoke-CaEvaluateRequest -Body $body -Uri $Uri `
                    -RequestHandler $RequestHandler -MaxRetry $MaxRetry `
                    -InitialBackoffSecond $InitialBackoffSecond

                $outcome = ConvertTo-CaOutcome -WhatIfResult $response -ScenarioName $name `
                    -SignInCondition (Get-CaProperty -InputObject $item -Name 'Conditions')

                $outcome | Add-Member -NotePropertyName 'Failed' -NotePropertyValue $false
                $outcome | Add-Member -NotePropertyName 'Error' -NotePropertyValue $null
                $outcome
            } catch {
                # Reported twice on purpose: as an error so an interactive run is not silent,
                # and as an object so a pipeline can see which scenario is missing and why
                Write-Error "Scenario '$name' failed: $($_.Exception.Message)"

                [PSCustomObject]@{
                    PSTypeName         = 'CaOutcome.Result'
                    Scenario           = $name
                    Current            = $null
                    Projected          = $null
                    Delta              = $null
                    PolicyCount        = 0
                    ReportOnlyApplying = 0
                    Failed             = $true
                    Error              = $_.Exception.Message
                }
            }
        }
    }
}
