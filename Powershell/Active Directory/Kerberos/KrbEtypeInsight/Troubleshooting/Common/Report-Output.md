# Report output

## Formats and when to use each

| Format | Shape | Use |
|---|---|---|
| `Html` | Single self-contained file | The artefact to circulate or attach to a change record |
| `Csv` | One row per **finding** | Triage in a spreadsheet, pivoting by code or severity |
| `Json` | Full object graph, all evidence | Baseline for comparison against the next run |

```powershell
$risks | Export-KrbEtypeReport -Path .\krb.html
$risks | Export-KrbEtypeReport -Path .\krb.csv  -Format Csv
$risks | Export-KrbEtypeReport -Path .\krb.json -Format Json
```

## HTML

Self-contained by design: no external stylesheet, script or font. It works when emailed, dropped
on a share, or opened on an isolated machine - which is the machine most people open a security
report on. It renders in both light and dark themes.

Include the domain context, or a reader who was not in the room cannot tell whether the baseline
was measured or assumed:

```powershell
$context = Get-KrbDomainEtypeContext
$risks | Export-KrbEtypeReport -Path .\krb.html -DomainContext $context -Title 'Phase 1'
```

Long evidence lists are truncated at 400 characters in the HTML for readability. The JSON export
carries the complete set, and the report says so where it truncates.

## CSV is one row per finding

Deliberately. A principal with four findings is four rows, which is what makes the file
pivotable; one row per principal forces the findings into a single joined cell and defeats the
point of choosing CSV. List columns are flattened with semicolons.

## JSON depth

Serialised at depth 8, which reaches through `Risk` to `Findings` to `Evidence` and into the
nested arrays inside `Evidence`. At `ConvertTo-Json`'s default depth of 2 the evidence renders
as the string `System.Collections.Hashtable` - and the format that exists specifically to
preserve the working preserves none of it.

## Comparing runs

```powershell
$now = Get-Content .\krb-2026-Q3.json -Raw | ConvertFrom-Json
$then = Get-Content .\krb-2026-Q2.json -Raw | ConvertFrom-Json

$nowCodes  = $now.Findings.Code  | Group-Object | Select-Object Name, Count
$thenCodes = $then.Findings.Code | Group-Object | Select-Object Name, Count

Compare-Object $thenCodes $nowCodes -Property Name, Count
```

Finding codes are stable across releases precisely so this works.

## Untrusted content

Every name in a report originates in the event log, where the requesting client chose it. A
service principal name can contain markup. All interpolated content is HTML-encoded, so a
crafted name is displayed as text rather than executed in the reader's browser - the report ships
no JavaScript of its own, so any script tag in the output would have come from input data.

Encoding is not redaction. The value is still disclosed, which is correct - an administrator
investigating a hostile SPN needs to see it.

## Handling

Reports name accounts, service principal names and client addresses. Treat them as internal
documents; do not attach one to a vendor case without redaction.

## Related

- [Finding codes](Finding-Codes.md)
- [Event log permissions](../Security/Event-Log-Permissions.md)
