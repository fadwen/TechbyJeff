# Risk scoring

Each risk object carries a `RiskLevel` and a `RiskScore`. They answer different questions and
are deliberately not derived from one another.

## Level - does this block the change?

The highest severity present among the findings.

```text
Critical > High > Medium > Low > Info > None
```

One Critical finding makes the principal Critical, however many Info findings accompany it.

## Score - how should the backlog be ordered?

The capped sum of finding weights, plus a blast-radius uplift.

```text
Score = min(100, sum(weights) + radiusUplift)
```

| Severity | Weight |
|---|---|
| Critical | 40 |
| High | 20 |
| Medium | 10 |
| Low | 4 |
| Info | 0 |

The weights are spread so that no accumulation of Mediums can reach a single Critical. A dozen
accounts with stale passwords is a housekeeping problem; one account with no AES key and 400
dependent requests is an outage, and a scheme that lets the first outrank the second inverts the
remediation order.

## Why not derive Level from Score?

Four Medium findings and one Critical can reach the same total. Treating them as equivalent puts
a tidy-up task ahead of an outage. Level answers "how bad is the worst thing here"; Score answers
"how much is wrong here". Both are needed.

## Blast radius

Distinct dependent clients scale the Score logarithmically:

| Clients | Uplift |
|---|---|
| 1 | 0 |
| 10 | +10 |
| 100 | +20 |
| 1000 | +30 |

Logarithmic because the difference between one client and ten is a change in kind, while the
difference between three hundred and three thousand is not - both are "the whole estate", and a
linear scale would let one popular service saturate the ranking.

Two properties this preserves:

**Radius never changes the Level.** A widely used healthy service must not outrank a broken
obscure one.

**A principal with no findings scores zero regardless of client count.** Blast radius multiplies
a problem; it cannot create one.

## Using it

```powershell
$risks = Get-KrbEvent | Get-KrbEtypeRisk

# What blocks the change
$risks | Where-Object RiskLevel -eq 'Critical' | Sort-Object RiskScore -Descending

# The single most useful filter in the module
$risks | Where-Object WillBreakOnHardening |
    Select-Object PrincipalName, RiskScore, ClientCount,
                  @{ n = 'Breaks'; e = { $_.ClientsWithoutAesSupport -join ', ' } }
```

`WillBreakOnHardening` is set by finding code - `KRB001`, `KRB002`, `KRB004`, `KRB005`,
`KRB007`, `KRB011`, and `KRB014` on a trust row - rather than by a score threshold, so it means
what it says rather than "scored above some number".

## Related

- [Finding codes](Finding-Codes.md)
