function ConvertTo-CaOutcome {
    <#
    .SYNOPSIS
        Turns a Conditional Access What If response into the effective outcome of the sign-in,
        and into the outcome that would follow from promoting the tenant's report-only policies

    .DESCRIPTION
        Core Functionality:
        Takes the whatIfAnalysisResult collection Graph returns from
        POST /beta/identity/conditionalAccess/evaluate and folds it twice. Current is the
        outcome the tenant enforces today, from the policies whose state is enabled. Projected
        is the outcome it would enforce if every report-only policy were switched on. Delta is
        the difference between them.

        Business Value:
        The What If API answers a question nobody asks. It reports, policy by policy, whether
        each one matches - so a tenant with thirteen policies returns thirteen verdicts, and
        working out what the user actually experiences is left to the reader. What an
        administrator wants to know is whether the sign-in succeeds, what the user has to do to
        make it succeed, and what changes if the policy being piloted goes live. All three come
        out of one response, because that response carries each policy's state alongside its
        verdict: filter to enabled and you have today, add the report-only ones and you have the
        promotion.

        That second fold is the reason this exists. There is no way to ask Graph to evaluate a
        hypothetical policy - the request body takes a sign-in to simulate, not a policy set, so
        the evaluation is always against what is really in the tenant. Staging a candidate as
        report-only and reading both worlds out of one response is the way to simulate a
        promotion without enforcing anything, and it costs no extra API calls.

        Use Cases:
        - Checking what a report-only policy will do before promoting it, per persona
        - Asserting in Maester that a given sign-in is blocked, or requires a given control
        - Storing an outcome as a baseline and failing a later run when a cell flips, which
          catches group membership changes that leave the policy JSON untouched

        Dependencies:
        None. This transforms a response somebody else fetched, so it needs no Graph module and
        no connection. Feed it Maester's Test-MtConditionalAccessWhatIf -AllResults, an
        Invoke-MgGraphRequest result, or a saved file.

        Side Effects:
        None. Nothing is fetched and nothing is changed.

        Important:
        The response must include every policy, not just the applying ones. Graph's
        appliedPoliciesOnly defaults to returning all of them, and Maester exposes the same
        thing as -AllResults. Without the non-applying policies the fold still works, but a
        report-only policy that does not apply is indistinguishable from one that was never
        returned, and the projection quietly loses its meaning.

    .PARAMETER WhatIfResult
        [System.Object] (Mandatory, Accepts Pipeline Input)

        The What If response, in any shape it arrives in: a JSON string, the OData envelope with
        its value property, or the already-unwrapped collection of policy results.

    .PARAMETER ScenarioName
        [System.String] (Optional, No Pipeline Support)

        A label for the sign-in this response describes, carried onto the output so a batch of
        outcomes stays readable. Something like 'jeff/office365/ios/noncompliant'.

    .PARAMETER SignInCondition
        [System.Object] (Optional, No Pipeline Support)

        The signInConditions object that was sent to the evaluate endpoint, if you still have
        it. Supplying it turns "this promotion adds a requirement" into "this promotion locks
        this persona out", by checking each requirement against the device state that was
        simulated.

        Business Context: The API reports that a policy requiring a compliant device applies,
        whether or not the simulated device is compliant, so an outcome read from the response
        alone understates a lockout as a mild extra requirement.

        Each rule rests on a documented Microsoft constraint: legacy authentication clients
        support neither MFA nor device state, device code flow cannot pass device state,
        approved client app is iOS and Android only, hybrid join is Windows only. What the
        request cannot decide - whether a user has registered a method or accepted terms of use
        - is reported as unknown rather than guessed at, because an invented lockout costs more
        than a missed one.

    .PARAMETER BaselineState
        [System.String[]] (Optional, No Pipeline Support)

        The policy states that make up the Current world. Defaults to enabled alone, which is
        what the tenant enforces.

    .PARAMETER CandidateState
        [System.String[]] (Optional, No Pipeline Support)

        The policy states that make up the Projected world. Defaults to enabled plus
        enabledForReportingButNotEnforced, which is the promotion simulation.

        Business Context: Overridable because the same fold answers a different question when
        the states are chosen differently - passing the same value as BaselineState turns the
        delta off and leaves you with a plain outcome, which is what you want when the response
        came from a tenant with no report-only policies at all.

    .OUTPUTS
        PSCustomObject with Scenario, Current, Projected, Delta, PolicyCount and
        ReportOnlyApplying. Current and Projected each carry Access, RequiredControls,
        OptionalChoices, SessionControls, SessionConflicts and AppliedPolicies.

    .EXAMPLE
        PS> $response = Invoke-MgGraphRequest -Method POST -OutputType Json `
                -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -Body $body
        PS> ConvertTo-CaOutcome -WhatIfResult $response

        DESCRIPTION: Folds a live evaluation into both worlds
        OUTPUT: One outcome object, with Current, Projected and Delta
        DURATION: Milliseconds; the API call is the slow part
        USE CASE: Checking a single sign-in by hand

    .EXAMPLE
        PS> $outcome = ConvertTo-CaOutcome -WhatIfResult $response -ScenarioName 'jeff/ios'
        PS> if ($outcome.Delta.HasChange) { $outcome.Delta.Summary }

        DESCRIPTION: Reports only what promoting the report-only policies would change
        OUTPUT: A sentence such as 'LOCKS OUT this sign-in; cannot satisfy GRANT - Compliant
                Windows Devices (compliantDevice)'
        DURATION: Milliseconds
        USE CASE: Deciding whether a piloted policy is safe to switch on

    .EXAMPLE
        PS> Get-ChildItem .\fixtures\*.json | ForEach-Object {
                ConvertTo-CaOutcome -WhatIfResult (Get-Content $_ -Raw) -ScenarioName $_.BaseName
            } |
                Where-Object { $_.Delta.HasChange } |
                Select-Object Scenario, @{n='Change';e={$_.Delta.Summary}}

        DESCRIPTION: Runs a stored matrix of scenarios and keeps the ones a promotion changes
        OUTPUT: One row per scenario whose outcome changes
        DURATION: Milliseconds per scenario
        USE CASE: The blast radius of a promotion, across every persona at once

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17

        The Conditional Access What If API is in beta and its shape may change. Everything this
        function reads - state, policyApplies, grantControls, sessionControls - is documented
        for whatIfAnalysisResult, but a beta response is not a contract.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$WhatIfResult,

        [Parameter()]
        [string]$ScenarioName,

        [Parameter()]
        [AllowNull()]
        [object]$SignInCondition,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$BaselineState = $script:CurrentStates,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$CandidateState = $script:ProjectedStates
    )

    process {
        $policies = ConvertFrom-CaWhatIfResponse -InputObject $WhatIfResult

        if ($policies.Count -eq 0) {
            Write-Warning 'The What If response contained no policy results. Nothing to fold.'
        }

        $current = Get-CaEffectiveControl -Policy $policies -State $BaselineState -World 'Current' `
            -SignInCondition $SignInCondition
        $projected = Get-CaEffectiveControl -Policy $policies -State $CandidateState -World 'Projected' `
            -SignInCondition $SignInCondition
        $delta = Compare-CaEffectiveControl -From $current -To $projected

        # Surfaced on its own because it is the number that decides whether the projection means
        # anything: no applying report-only policy and the two worlds are identical by
        # construction, not because the promotion is safe.
        $reportOnlyApplying = @($policies | Where-Object {
            (Get-CaProperty -InputObject $_ -Name 'policyApplies') -eq $true -and
            (Get-CaProperty -InputObject $_ -Name 'state') -eq 'enabledForReportingButNotEnforced'
        }).Count

        [PSCustomObject]@{
            PSTypeName         = 'CaOutcome.Result'
            Scenario           = $ScenarioName
            Current            = $current
            Projected          = $projected
            Delta              = $delta
            PolicyCount        = $policies.Count
            ReportOnlyApplying = $reportOnlyApplying
        }
    }
}
