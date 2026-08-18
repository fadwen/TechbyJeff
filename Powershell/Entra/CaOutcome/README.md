# CaOutcome

[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Pester](https://img.shields.io/badge/Tested_with-Pester_6-green?style=flat-square)](https://pester.dev)
[![Graph beta](https://img.shields.io/badge/MS_Graph-beta-orange?style=flat-square&logo=microsoft)](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-evaluate?view=graph-rest-beta)

Folds a Conditional Access What If response into the outcome a sign-in actually
meets, diffs what the tenant enforces today against what it would enforce if the
report-only policies were promoted, runs that across a matrix of personas, and
compares a run against a committed baseline.

| Function | What it does |
|----------|--------------|
| `ConvertTo-CaOutcome` | One response → the effective outcome, today and after promotion |
| `Expand-CaScenario` | A matrix of personas × resources × conditions → individual sign-ins |
| `Invoke-CaScenarioMatrix` | Runs those against the tenant, with retry, and folds each |
| `Export-CaBaseline` | Records a run as a committable, deterministic JSON baseline |
| `Compare-CaBaseline` | Diffs a fresh run against that baseline |

## The problem

The What If API answers a question nobody asks. Given a simulated sign-in it
reports, policy by policy, whether each one matches — so a tenant with thirteen
policies returns thirteen verdicts and leaves you to work out what the user
experiences. What an administrator wants is three things:

- does the sign-in succeed
- what does the user have to do to make it succeed
- what changes if the policy I am piloting goes live

All three come out of a single response, because it carries each policy's
`state` alongside its verdict. Filter to `enabled` and you have today. Add
`enabledForReportingButNotEnforced` and you have the promotion.

That second fold is the point. There is no way to ask Graph to evaluate a
hypothetical policy — the request body takes a sign-in to simulate, not a policy
set, so evaluation is always against what is really in the tenant. Staging a
candidate as report-only and reading both worlds out of one response simulates
the promotion without enforcing anything, and costs no extra API calls.

## Install

Nothing to install. The module has no `RequiredModules` and needs no Graph
connection — it transforms a response someone else fetched.

```powershell
Import-Module .\CaOutcome.psd1
```

## Usage

```powershell
$body = @{
    signInIdentity      = @{ '@odata.type' = '#microsoft.graph.userSignIn'; userId = $userId }
    signInContext       = @{ '@odata.type' = '#microsoft.graph.applicationContext'
                             includeApplications = @('00000003-0000-0ff1-ce00-000000000000') }
    signInConditions    = @{ devicePlatform = 'windows'; clientAppType = 'browser'
                             deviceInfo = @{ isCompliant = $false } }
    appliedPoliciesOnly = $false          # required: the projection needs every policy
}

$response = Invoke-MgGraphRequest -Method POST -OutputType Json `
    -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' `
    -Body ($body | ConvertTo-Json -Depth 10)

ConvertTo-CaOutcome -WhatIfResult $response -SignInCondition $body.signInConditions
```

```
Scenario           :
Current            : GrantedWithControls, requires authenticationStrength:Passwordless MFA
Projected          : GrantedWithControls, requires compliantDevice as well
Delta.Summary      : LOCKS OUT this sign-in; cannot satisfy GRANT - Compliant Windows
                     Devices (compliantDevice); now requires compliantDevice
ReportOnlyApplying : 1
```

It also takes Maester's output directly:

```powershell
# Maester hands back the collection already unwrapped
Test-MtConditionalAccessWhatIf -UserId $u -IncludeApplications $app -AllResults |
    ConvertTo-CaOutcome
```

## Across a population

One sign-in is rarely the question. Declare the axes as data and multiply them
out — see [`Examples/ca-matrix.psd1`](./Examples/ca-matrix.psd1):

```powershell
$matrix = Import-PowerShellDataFile .\ca-matrix.psd1
$outcomes = Expand-CaScenario -Matrix $matrix |
    Invoke-CaScenarioMatrix -DelayMillisecond 100

# Who stops getting in if the pilot goes live
$outcomes | Where-Object { $_.Delta.BecomesEffectivelyBlocked } |
    Select-Object Scenario, @{n='Why';e={$_.Delta.Summary}}
```

Every axis multiplies, and every scenario is one API call, so
`Expand-CaScenario` throws past `-MaxScenarioCount` (250 by default) rather than
truncating — a silently shortened matrix reports a clean run over a fraction of
what was asked for.

Throttling and transient failures are retried, honouring `Retry-After`. A
scenario that fails anyway comes back with `Failed` set rather than vanishing,
because a dropped scenario would look like a *removed* one to the next baseline
comparison.

`Invoke-CaScenarioMatrix` takes a `-RequestHandler` scriptblock. That seam is why
the module declares no `RequiredModules` and why its tests need no tenant; it is
also how you replay recorded responses or route through your own transport.

## Baselining — the part config comparison cannot do

Microsoft365DSC and every policy-export tool watch the policy document. But a
Conditional Access outcome depends on far more than that document: group
membership, role assignment, named locations, device compliance. Someone joins a
group and a policy that already required a compliant device now applies to them.
**No policy changed. No configuration drifted.** A user is locked out on Monday
who was not on Friday, and nothing in a config-drift tool will ever mention it.

A committed baseline of *outcomes* catches exactly that, because it records what
the tenant does rather than what it is configured to do.

```powershell
# Once, after reviewing the outcomes
$outcomes | Export-CaBaseline -Path .\ca-baseline.json

# Nightly
Expand-CaScenario -Matrix $matrix | Invoke-CaScenarioMatrix |
    Compare-CaBaseline -Path .\ca-baseline.json |
    Where-Object HasChange
```

Each row carries `Status` — `Unchanged`, `Changed`, `Added`, `Missing` or
`Failed` — plus a `CurrentDelta` and a `ProjectedDelta`. The two worlds are kept
apart because they answer different questions: current drift means what the
tenant enforces has moved, projected drift means the pilot's blast radius has
moved, which happens without anyone touching the pilot.

```powershell
# The severe subset, in either world
$drift | Where-Object {
    $_.CurrentDelta.BecomesEffectivelyBlocked -or $_.ProjectedDelta.BecomesEffectivelyBlocked
}
```

### Authentication strengths are watched too

A custom authentication strength is an editable tenant object, and editing one
changes what **every** policy referencing it requires — without anyone editing
a policy, and with the requirement still reading
`authenticationStrength:Contoso strong` on both sides. Comparing requirement
names sees nothing.

A caveat measured rather than assumed: Graph *inlines* the whole strength object
inside each referencing policy, `allowedCombinations` and `modifiedDateTime`
included. So a policy export is **not** byte-identical after the edit — an
earlier version of this README claimed it was, and that was wrong. What a config
export shows is N policies whose embedded blob moved; what this shows is one
strength weakened, which combination was added, and which personas it reaches.

So the strength's `allowedCombinations` and its combination-configuration count
travel with the control and into the baseline. Widening one is reported as a
weakening:

```
jeff/managed  Changed  enforced now: WEAKENED authentication strength
                       'Contoso strong' now also allows password,sms
```

with `AccessChanged` false, no added required controls and no added policies —
the strength edit is the only signal. Narrowing one is reported the other way, as
is dropping a FIDO2 AAGUID allowlist or a certificate issuer restriction, which
widens what satisfies the strength without changing a single combination.

Three properties make the baseline worth committing:

- **Deterministic.** Arrays are sorted and no timestamp is written, so the only
  thing that ever appears in the diff is a changed outcome. Git already records
  when the file changed and who changed it.
- **Complete or refused.** `Export-CaBaseline` throws if any scenario failed
  (`-Force` overrides, with a warning). Recording a failed scenario as absent
  would make the next comparison report it as removed — a change invented by a
  transient HTTP error.
- **`Missing` is not `Removed`.** A scenario in the baseline with no fresh
  outcome is reported as a gap in the run, because the usual cause is a failed
  evaluation rather than a deliberate edit to the matrix.

> **`appliedPoliciesOnly` must be `$false`** (Maester's `-AllResults`). Without
> the non-applying policies a report-only policy that does not apply is
> indistinguishable from one that was never returned, and the projection quietly
> loses its meaning. Check `ReportOnlyApplying` on the output: zero means the two
> worlds are identical by construction, not because the promotion is safe.

## What it computes

| Field | Meaning |
|-------|---------|
| `Current` / `Projected` | The effective outcome in each world |
| `.Access` | `Blocked`, `GrantedWithControls` or `Granted` |
| `.RequiredControls` | Controls the user has no choice about |
| `.OptionalChoices` | Multi-option `OR` clauses, kept whole rather than flattened |
| `.UnsatisfiableRequirements` | Requirements the simulated sign-in demonstrably cannot meet |
| `.IsEffectivelyBlocked` | Blocked outright, or granted subject to something impossible |
| `.SessionControls` / `.SessionConflicts` | Merged session controls, and disagreements between policies |
| `Delta.BecomesEffectivelyBlocked` | The headline: gets in today, does not after promotion |
| `Delta.Summary` | The whole change in one sentence |

The fold follows Entra's documented evaluation: every matching policy is
evaluated and the aggregate is the most restrictive combination, so one applying
block ends it, and otherwise every policy's grant clause must be satisfied.

Three deliberate design choices:

**`OR` clauses are not flattened.** "MFA or compliant device" and "MFA and
compliant device" are different policies, and a flat list of strings cannot tell
them apart.

**Authentication strengths count as requirements.** A modern MFA policy has an
empty `builtInControls` array and its entire requirement in
`authenticationStrength`, so a reader that looks only at the array reports the
tenant's main MFA policy as requiring nothing.

**Session conflicts are always reported, resolved or not.** Two policies setting
the same control to different values is common and easy to create by accident.
Microsoft documents the aggregate as most-restrictive, which is applied for the
two controls where restrictiveness has a defensible ordering — sign-in frequency
and persistent browser. Everything else comes back marked `Resolved = $false`
rather than guessed at.

## Satisfiability

Supplying `-SignInCondition` turns *"this promotion adds a requirement"* into
*"this promotion locks this persona out"*. A report-only policy requiring a
compliant device applies to a non-compliant device just the same, and the API
reports it as applying — which reads as a mild extra requirement when it is in
fact a lockout.

Every rule rests on a documented Microsoft constraint, never on inference:

| Condition | Rules out | Because |
|-----------|-----------|---------|
| `clientAppType` = `other` or `exchangeActiveSync` | `mfa`, `passwordChange`, authentication strengths, terms of use, custom factors, `compliantDevice`, `domainJoinedDevice` | Legacy clients *"don't support multifactor authentication and don't pass device state information"* |
| `authenticationFlow.transferMethod` = `deviceCodeFlow` | `compliantDevice`, `domainJoinedDevice` | The authenticating device *"can't provide its device state to the device that is providing a code"* |
| `devicePlatform` not iOS/Android | `approvedApplication` | *"Only supports the iOS and Android for device platform condition"* |
| `devicePlatform` not Windows | `domainJoinedDevice` | *"Only supports domain-joined Windows"* devices |
| `devicePlatform` macOS/Linux | `compliantApplication` | App protection policy is unsupported there |
| `deviceInfo.isCompliant` = `$false` | `compliantDevice` | The device is not compliant |
| `deviceInfo.trustType` ≠ `serverAD` | `domainJoinedDevice` | Entra joined is not hybrid joined |
| Strength with empty `allowedCombinations` | that strength | It admits nobody |

**One inference deliberately not made.** It is tempting to say a strength allowing
only `windowsHelloForBusiness` cannot be satisfied on iOS. That is wrong: the
combination is documented as *"Windows Hello for Business **or platform
credential**"* and now covers macOS Platform SSO, so the name does not name a
platform. No `allowedCombinations` value carries a documented platform
restriction, so none is asserted — there is a test pinning that this stays
`Unknown`.

Three deliberate restraints:

- **A blocking rule beats a satisfying one.** A compliant, hybrid-joined device
  reached over Exchange ActiveSync still cannot satisfy `compliantDevice`,
  because the client type never passes the device state.
- **`easSupported` is not treated as legacy** — it names the EAS clients that
  *do* support modern authentication, which is why Microsoft keeps it separate.
- **Unknown is the default and the common answer.** Whether a user has
  registered a method or accepted terms of use is not in the request, and
  `compliantApplication` on Windows is left unknown because app protection there
  is in preview for Edge and nothing names the browser. A missed lockout is a
  finding this module fails to make; an invented one teaches the reader to ignore
  the field.

An `OR` clause is only unsatisfiable when every alternative is. Each finding
carries `Reasons` alongside `Blockers`, so the summary reads *"cannot satisfy
BLOCK - Corp devices only - a legacy authentication client passes no device
state"* rather than naming the control and leaving you to work out why.

## Using it with Maester

See
[`Examples/ContosoCaOutcome.Tests.ps1.template`](./Examples/ContosoCaOutcome.Tests.ps1.template)
for a drop-in custom test. Copy it into Maester's `Custom` folder, drop the
`.template` extension, and the findings land in the existing Maester HTML report
and GitHub Action alongside everything else — no fork, no separate reporting.

It asserts three things Maester's built-in Conditional Access tests do not: that
promoting the report-only policies would lock no persona out, that the break
glass account survives both worlds, and — the one that stops the others passing
vacuously — that a report-only policy applied to at least one persona in the
first place.

The `.template` extension keeps this repository's CI from running it: the gate
executes every `*.Tests.ps1` with `Should.DisableV5` set, and these assertions
use the Pester 5 form because that is what Maester runs.

The `Mt` prefix is Maester's, so these cmdlets deliberately do not use it.

## Testing

```powershell
Invoke-Pester -Path .\Tests
```

210 tests at 98.7% coverage. 204 of them need no tenant and run anywhere; the six
under `Tests/Integration` exercise the one path a fixture cannot — the default
request handler that calls `Invoke-MgGraphRequest` — and skip themselves unless
the session is connected to Graph with a Conditional Access read scope. Without a
connection the suite reports 204 passed, 6 skipped, 98.65% covered.

The fixtures under `Tests/Fixtures` are genuine
What If responses from a tenant carrying nine enabled and four report-only
policies, with directory object ids rewritten to synthetic ones — Microsoft's own
well-known ids are preserved, because rewriting them would make the fixture
describe a tenant that cannot exist.

Keeping the fixtures real matters here more than anywhere else: every shape that
caused a defect during development came from the API rather than from
imagination — `grantControls` with an empty `builtInControls` array,
`sessionControls` padded with nulls, two policies disagreeing about persistent
browser on the same sign-in.

## Limitations

- **The What If API is beta** and its shape may change. Everything read here is
  documented for `whatIfAnalysisResult`, but a beta response is not a contract.
  The transport is not in this module, so an API change costs you one file.
- **Policy applicability is not policy satisfaction.** Without
  `-SignInCondition` the module reports what is required, not whether the user
  can produce it. With it, the rules in the table above are decided and
  everything else is honestly reported as unknown.
- **Session control precedence is documented in general, not in detail.** Where
  Microsoft gives no ordering, the conflict is reported rather than resolved.
- **Scenarios run serially, one API call each.** The endpoint publishes no
  throttling limits and a matrix run is the traffic shape that finds an
  unpublished one, so there is no parallelism and `-DelayMillisecond` exists to
  pace a large run.
- **A baseline is only as good as its matrix.** Nothing here discovers the
  personas worth checking; a population left out of the matrix is a population
  no assertion covers, and the run still reports green.

## Version

- **0.5.1** — an unresolved session conflict now picks a deterministic winner, so
  a baseline stays stable across runs
- **0.5.0** — authentication strength combinations carried through the fold,
  so a silently edited custom strength is caught as drift
- **0.4.0** — satisfiability widened to legacy auth, device code flow and
  platform limits, each finding carrying its reason
- **0.3.0** — scenario matrix runner and outcome baselining
- **0.2.0** — matrix expansion and the request-handler seam
- **0.1.0** — effective control folding, promotion diff, satisfiability
