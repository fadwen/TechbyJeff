# EntraMemberOf

A read-only PowerShell module that finds every dynamic membership rule using the `memberOf`
operator before Microsoft Entra ID retires it. It scans rule text, an exported CSV or JSON file,
or a whole tenant through Microsoft Graph, parses each rule rather than searching its text, and
reports what each object depends on and what to do about it.

Version 0.1.0. Not on the PowerShell Gallery; import it from this folder.

## Why this exists

The public preview of the `memberOf` rule operator is ending. From the Learn page (`ms.date`
08/04/2026) and Message Center MC1448379:

| Date | What happens |
| --- | --- |
| November 3, 2026 | Dynamic membership groups, dynamic administrative units and entitlement management auto-assignment policies that use `memberOf` stop updating and stay in their last known state |

Nothing is deleted and nothing errors. Membership just freezes, which the Learn page says "can
lead to stale access and enforcement gaps, including outdated Teams and SharePoint access,
Conditional Access targeting, group-based licensing, and access package assignments." The
auto-assignment policy page says those policies are "quarantined": they remain, assignment
processing stops, and nothing is added or removed until `memberOf` is taken out of the rule.

Three kinds of object can carry the rule, and Microsoft's own migration guidance finds them three
different ways: export groups from the admin center and look for the word, use Graph PowerShell
for administrative units, and run a script that `-match`es `(?i)memberof` for policies. All
three are text searches. `user.jobTitle -eq "memberOf coordinator"` matches a text search and
does not use the operator; a rule split across lines or written `user.memberof` in lower case
(as the Learn page's own examples are) may or may not, depending on the search. This module reads
the rule the way the rule engine does.

## Quick start

```powershell
Import-Module .\EntraMemberOf.psd1

# A rule somebody pasted into a ticket
Test-EntraMemberOfRule -Rule "user.memberOf -any (group.objectId -in ['<source group id>'])"

# The admin center's dynamic group export
Test-EntraMemberOfRule -Path .\dynamic-groups.csv

# The whole tenant
Connect-MgGraph -Scopes Group.Read.All, AdministrativeUnit.Read.All, EntitlementManagement.Read.All
Test-EntraMemberOfRule -Tenant
```

Output from file mode against the export fixture in this repository:

```text
PS> Test-EntraMemberOfRule -Path .\Tests\Fixtures\dynamic-groups-export.csv

ObjectKind           DisplayName                    Level   RuleKind State  Chain SourceGroups
----------           -----------                    -----   -------- -----  ----- ------------
Group                All Sales                      Clean            On
Group                All Marketing                  Clean            On
Group                Sales and Marketing            Retired user     On           All Sales, All Marketing
Group                Field Devices                  Retired device   On           11111111-0000-4000-8000-000000000005
Group                Rollup of Rollups              Retired user     Paused yes   Sales and Marketing
Group                Says memberOf                  Review           On
Group                Broken rule                    Review           On
Group                Assigned group                 Clean

Outcome                : Retired
Coverage               : Complete
Mode                   : File
Groups                 : Complete: 8 scanned, 3 retired, 2 review
AdministrativeUnits    : NotRequested: 0 scanned, 0 retired, 0 review
AutoAssignmentPolicies : NotRequested: 0 scanned, 0 retired, 0 review
Rules                  : NotRequested: 0 scanned, 0 retired, 0 review
MemberOfGroupCount     : 3
MemberOfGroupLimit     : 500
DependencyChainCount   : 1
RetiredCount           : 3
ReviewCount            : 2
RetirementDate         : 2026-11-03
IncompleteKinds        : {}
Message                : 3 object(s) use memberOf and stop updating after November 3, 2026; 2 more need a look.
```

`Field Devices` shows a bare id because its source group is not in the file; in tenant mode the
name is looked up, and a group that no longer exists is reported as not found.

Everything is on the objects; the tables are only the default view. `Format-List` or
`Select-Object *` shows the rest, including `Rule`, `SourceGroupIds`, `Note` and `Remediation`.

## What comes back

One `EntraMemberOf.Result` per rule-bearing object, then, in file and tenant mode, one
`EntraMemberOf.Summary`.

### Result levels

| Level | Meaning |
| --- | --- |
| `Retired` | The rule uses `user.memberOf` or `device.memberOf` as an identifier outside a quoted string. The object stops updating on November 3, 2026 |
| `Review` | The rule mentions `memberOf` some other way, or could not be read to the end. `ReviewCode` says which; a person has to look |
| `Clean` | The rule was read to the end and does not use `memberOf` |

Review codes: `StringLiteral` (`memberOf` only inside a quoted value), `UnparsedRule` (the
tokenizer hit something it could not read, such as an unclosed quote), `UnqualifiedMemberOf`
(an identifier contains `memberOf` but is not one of the two documented forms),
`MemberOfAsOperator` (written `-memberOf`, which is not defined anywhere).

A `Retired` result also carries `RuleKind` (`user` or `device`), the `Quantifier` and `Operator`
used (Learn documents `-any` and `-in`; anything else is noted), `SourceGroupIds`,
`SourceGroupNames` (aligned with the ids, null for a group that no longer exists),
`DependsOnMemberOfGroup` and `DependsOn` (source groups that are themselves `memberOf` groups,
which Learn says cannot be nested), `ProcessingState` (`On` or `Paused`; a paused object is not
exempt), the `Remediation` sentence for its kind, and a `Note` for anything the scanner saw that
the documented form does not cover: more than 50 source groups, a value that is not an object id,
`memberOf` combined with another expression (also unsupported), unreadable text.

### Summary

The summary says what the scan means, and keeps "nothing found" apart from "not everything was
read":

| Outcome | Meaning |
| --- | --- |
| `Retired` | At least one object uses `memberOf` |
| `Review` | Nothing uses it as documented, but some rules need reading |
| `Incomplete` | Nothing found, but at least one kind could not be read, so this is not an all-clear |
| `Clean` | Every requested kind was read to the end and nothing uses `memberOf` |

Per kind it reports `Coverage` (`Complete`, `Incomplete`, `NotRequested`) and counts, plus
`MemberOfGroupCount` against the documented limit of 500 per tenant, `DependencyChainCount`,
`IncompleteKinds` and a one-sentence `Message`.

## How matching works

A membership rule is a small expression language. The module tokenizes it: identifiers such as
`user.memberOf` or `group.objectId`, operators written `-eq` or `eq` (or with the en dash some
Learn examples carry), strings in double quotes (backtick escape) or single quotes (doubled
quote escape), arrays in brackets, parentheses. Then:

- `Retired` requires a Word token equal to `user.memberof` or `device.memberof`, compared
  case-insensitively. A string token containing the word is not a match.
- Inside the `memberOf` expression it records the quantifier that follows, the operator that
  follows `group.objectId`, and every string value, which are the source group ids.
- An `-and`, `-or` or `-not` outside that expression means `memberOf` is combined with other
  rules, which the Learn page lists as unsupported; the result says so.
- Any Unknown or Unterminated token makes a rule without `memberOf` a `Review`, never a `Clean`,
  because a rule the scanner could not finish reading is not a rule it can vouch for.

It is not a parser for the whole language, does not evaluate rules, and does not need to.

## Tenant mode

`Test-EntraMemberOfRule -Tenant` needs `Microsoft.Graph.Authentication` and an existing
`Connect-MgGraph` session. The rest of the Graph SDK is not used, and the module has no
`RequiredModules`, so rule text and file mode run on a machine that has never installed it.

Every request is a GET. The function that sends requests has no way to send anything else.

### What it calls

```text
GET /v1.0/groups?$filter=groupTypes/any(s:s eq 'DynamicMembership')&$select=...&$count=true&$top=999
    with ConsistencyLevel: eventual on every page
GET /v1.0/directory/administrativeUnits?$select=...            dynamic ones picked out by membershipType
GET /v1.0/identityGovernance/entitlementManagement/assignmentPolicies?$expand=accessPackage&$top=50
    auto-assignment policies are the ones with automaticRequestSettings; their rules are the
    attributeRuleMembers entries of specificAllowedTargets, one result per rule
GET /v1.0/groups?$filter=id in ('...')&$select=id,displayName   source group names, 15 ids per request
```

`@odata.nextLink` is followed on every collection. The policy read matches the script on
Microsoft's auto-assignment policy page step for step, except that the rule is parsed instead of
`-match`ed.

A kind that cannot be read (a missing permission, most often) is reported with `Write-Error`, the
other kinds are still scanned, and the summary's `Coverage` and `IncompleteKinds` say what was
missed. `-ObjectKind` limits the scan to some kinds; `-SkipGroupNameLookup` skips the name
resolution.

### Permissions

Microsoft documents these as the least privileged permissions for the list calls:

| Call | Delegated | Application |
| --- | --- | --- |
| Groups | `GroupMember.Read.All` or `Group.Read.All` | `GroupMember.Read.All` or `Group.Read.All` |
| Administrative units | `AdministrativeUnit.Read.All` | `AdministrativeUnit.Read.All` |
| Assignment policies | `EntitlementManagement.Read.All` | `EntitlementManagement.Read.All` |

```powershell
Connect-MgGraph -Scopes Group.Read.All, AdministrativeUnit.Read.All, EntitlementManagement.Read.All
```

### Verified against a tenant

Tested on October 27 and 28, 2026 (UTC) with Microsoft.Graph.Authentication 2.40.0 against a
development tenant, app-only with a certificate. The tenant had one dynamic group and no
`memberOf` rules, so three groups were created by hand for the test: a plain security group, a
`memberOf` dynamic group whose source is that group, and a second `memberOf` group whose sources
are the first `memberOf` group and an id that does not exist.

```text
PS> Test-EntraMemberOfRule -Tenant

ObjectKind           DisplayName                    Level   RuleKind State  Chain SourceGroups
----------           -----------                    -----   -------- -----  ----- ------------
Group                EntraMemberOf-Rollup           Retired user     On           EntraMemberOf-Source
Group                EntraMemberOf-Nested           Retired user     On     yes   EntraMemberOf-Rollup, 00000000-0000-4000-8000-00000000000...
Group                SC300-myDynamicGroup           Clean            On

Outcome                : Retired
Coverage               : Complete
Mode                   : Tenant
Groups                 : Complete: 3 scanned, 2 retired, 0 review
AdministrativeUnits    : Complete: 0 scanned, 0 retired, 0 review
AutoAssignmentPolicies : Complete: 0 scanned, 0 retired, 0 review
Rules                  : NotRequested: 0 scanned, 0 retired, 0 review
MemberOfGroupCount     : 2
MemberOfGroupLimit     : 500
DependencyChainCount   : 1
RetiredCount           : 2
ReviewCount            : 0
RetirementDate         : 2026-11-03
IncompleteKinds        : {}
Message                : 2 object(s) use memberOf and stop updating after November 3, 2026.

PS> ($r | Where-Object DisplayName -eq 'EntraMemberOf-Nested').Note
Depends on 1 group(s) that use memberOf themselves, which Learn lists as unsupported. 1 source group
id(s) were not found in the tenant: 00000000-0000-4000-8000-000000000000.
```

What that run showed, beyond the module working:

- **Graph still accepts new `memberOf` rules a week before the retirement.** `POST /groups` with
  a `memberOf` membership rule succeeded on October 28, 2026, and so did the nested one whose
  source is another `memberOf` group, which the Learn page says cannot be done. Nothing at the API
  stops an admin creating, today, an object that freezes on November 3.
- **A scan run seconds after a change can miss it.** The dynamic-group list is an advanced query
  (`$filter` on `groupTypes` with `ConsistencyLevel: eventual`), served from an index that lags
  the directory. The first scan after creation listed one of the two new groups; the second, a
  minute later, listed both. The same lag made the source-group name lookup return 404 for a
  group created moments earlier; the module reported that as a warning and kept the ids, and the
  next run resolved the names. Wait a minute after changing a group before trusting a scan of it.
- All three list calls succeeded on a token that held `Group.ReadWrite.All` and
  `Directory.ReadWrite.All` and none of the three documented read permissions by name; a
  least-privilege app was not tested.
- An app-only session has `ContextScope` `Process`; run `Connect-MgGraph` and the scan in the
  same session.

The three test groups are still in that tenant at the time of writing.

## Compatibility

PowerShell 7.4 or later, `Core` edition. Tested on 7.6. Windows PowerShell 5.1 was not tested and
is not claimed. Nothing in the module is Windows-specific; Linux and macOS were not tested.

## Tests

Pester 6.2 or later. From this folder:

```powershell
Invoke-Pester -Path .\Tests
```

The default run is the unit suite: the module contract and data file, the tokenizer, the scanner,
and the public command in rule text mode, file mode against the fixtures under `Tests/Fixtures`,
and tenant mode against a scripted request handler. No test reaches Graph.

Two suites are opt-in:

- `Tests/Integration/Tenant.Tests.ps1` runs tenant mode for real and skips itself unless the
  session is already connected with `Connect-MgGraph`. It asserts nothing tenant-specific.
- `Tests/Integration/LearnPage.Tests.ps1` fetches the current Learn pages and fails if the
  retirement date, the documented rule forms, the limits or the page's `ms.date` no longer match
  `Data/MemberOfRules.psd1`. Set `ENTRAMEMBEROF_ONLINE=1` to run it.

## Updating the data

Edit `Data/MemberOfRules.psd1`. It holds every date, limit, Review reason and remediation
sentence; nothing else in the module names one. It is a data file, so strings are literals
(here-strings for the long ones). Update `SourceDate` to the page's `ms.date` and `VerifiedOn`
to today, then run the online test.

## Limitations

- The scanner reads the rule, not the tenant's behavior. A rule the engine would reject for
  some other reason still comes back as whatever the scanner finds in it.
- The CSV columns the admin center exports are matched by name (`membershipRule`, `rule`, `id`,
  `objectId`, `displayName`, `name`, an optional kind column). An export with different headings
  needs them renamed, and a file with no rule column is an error on purpose.
- Source group names in file mode come only from the file itself.
- The dynamic-group list is served from an eventually consistent index; a group created or
  changed seconds before a scan may not appear until the next one.

## References

- [Dynamic membership groups with the memberOf attribute](https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-member-of),
  the source of the dates, limits and remediation guidance
- [Automatic assignment policies](https://learn.microsoft.com/entra/id-governance/entitlement-management-access-package-auto-assignment-policy),
  including Microsoft's script for finding policies that use `memberOf`
- [List groups](https://learn.microsoft.com/graph/api/group-list?view=graph-rest-1.0),
  [List administrativeUnits](https://learn.microsoft.com/graph/api/directory-list-administrativeunits?view=graph-rest-1.0),
  [List assignmentPolicies](https://learn.microsoft.com/graph/api/entitlementmanagement-list-assignmentpolicies?view=graph-rest-1.0)
- Message Center MC1448379, in the Microsoft 365 admin center
