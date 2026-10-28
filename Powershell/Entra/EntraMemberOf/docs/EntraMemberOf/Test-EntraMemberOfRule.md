---
document type: cmdlet
external help file: EntraMemberOf-Help.xml
HelpUri: https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-member-of
Locale: en-US
Module Name: EntraMemberOf
ms.date: 10/27/2026
PlatyPS schema version: 2024-05-01
title: Test-EntraMemberOfRule
---

# Test-EntraMemberOfRule

## SYNOPSIS

Finds dynamic membership rules that use the memberOf operator before it is retired

## SYNTAX

### Rule (Default)

```
Test-EntraMemberOfRule [-Rule] <string[]>
```

### Path

```
Test-EntraMemberOfRule -Path <string[]>
```

### Tenant

```
Test-EntraMemberOfRule -Tenant [-ObjectKind <string[]>] [-SkipGroupNameLookup]
 [-RequestHandler <scriptblock>]
```

## DESCRIPTION

Microsoft Entra ID is retiring the memberOf operator in dynamic membership rules. After
November 3, 2026, dynamic membership groups, dynamic administrative units and entitlement
management auto-assignment policies that use it stop updating and stay in their last known state.
This command finds every rule that uses it, so an admin can replace the rule or convert the
object to assigned membership before that date.

Three sources feed the same scanner:

Rule text (-Rule) scans one or more rules given as strings, which is the quickest way to check a
rule before saving it.

File mode (-Path) scans a CSV or JSON export: the admin center's dynamic group export, or a saved
Graph response. Columns are matched by name (membershipRule or rule, id or objectId, displayName
or name, and an optional object kind), so most exports work as they are.

Tenant mode (-Tenant) reads every dynamic membership group, every dynamic administrative unit and
every auto-assignment policy in the connected tenant through Microsoft Graph, resolves the display
name of each source group, and reports groups whose source groups are themselves memberOf groups.
It needs Microsoft.Graph.Authentication and an existing Connect-MgGraph session; every call is a
GET and the command never writes to the tenant.

The scanner tokenizes each rule rather than searching its text, so a rule that only mentions
memberOf inside a quoted value is not reported as using the operator. Each result's Level is
Retired (the rule uses user.memberOf or device.memberOf), Review (memberOf appears some other
way, or the rule could not be read to the end; ReviewCode says which) or Clean. In tenant and
file mode a summary object follows the results, whose Outcome keeps "nothing found" apart from
"not everything was read".

## EXAMPLES

### Example 1: Check one rule

```powershell
Test-EntraMemberOfRule -Rule "user.memberOf -any (group.objectId -in ['a1b2c3d4-0000-4000-8000-000000000001'])" |
    Format-List Level, RuleKind, Quantifier, Operator, SourceGroupIds, Remediation
```

```Output
Level          : Retired
RuleKind       : user
Quantifier     : any
Operator       : in
SourceGroupIds : {a1b2c3d4-0000-4000-8000-000000000001}
Remediation    : Replace memberOf with a supported rule operator, or convert the object to assigned
                 membership, then validate the result.
```

Scans a rule given as text, for instance one pasted into a ticket, and reports what it uses.
Rule text mode emits one result per rule and no summary.

### Example 2: Scan the admin center's dynamic group export

```powershell
Test-EntraMemberOfRule -Path .\dynamic-groups.csv
```

```Output
ObjectKind           DisplayName                    Level   RuleKind State  Chain SourceGroups
----------           -----------                    -----   -------- -----  ----- ------------
Group                All Sales                      Clean            On
Group                Sales and Marketing            Retired user     On           All Sales, All Marketing
Group                Rollup of Rollups              Retired user     Paused yes   Sales and Marketing
Group                Says memberOf                  Review           On

Outcome                : Retired
Coverage               : Complete
Mode                   : File
Groups                 : Complete: 4 scanned, 2 retired, 1 review
...
Message                : 2 object(s) use memberOf and stop updating after November 3, 2026; 1 more need a look.
```

Every row becomes one result, then a summary follows. Source group names are taken from the file
itself when the source group is in it. Chain marks a memberOf group whose source is another
memberOf group, which the Learn page lists as unsupported.

### Example 3: Scan the whole tenant

```powershell
Connect-MgGraph -Scopes Group.Read.All, AdministrativeUnit.Read.All, EntitlementManagement.Read.All
Test-EntraMemberOfRule -Tenant
```

```Output
ObjectKind           DisplayName                    Level   RuleKind State  Chain SourceGroups
----------           -----------                    -----   -------- -----  ----- ------------
Group                EntraMemberOf-Rollup           Retired user     On           EntraMemberOf-Source
Group                EntraMemberOf-Nested           Retired user     On     yes   EntraMemberOf-Rollup, 00000000-0000-4000-8000-00000000000...
Group                SC300-myDynamicGroup           Clean            On
AdministrativeUnit   EntraMemberOf-AU               Retired user     On           EntraMemberOf-Source

Outcome                : Retired
Coverage               : Complete
Mode                   : Tenant
Groups                 : Complete: 3 scanned, 2 retired, 0 review
AdministrativeUnits    : Complete: 1 scanned, 1 retired, 0 review
AutoAssignmentPolicies : Complete: 0 scanned, 0 retired, 0 review
...
Message                : 3 object(s) use memberOf and stop updating after November 3, 2026.
```

Reads every dynamic membership group, dynamic administrative unit and auto-assignment policy
rule through Microsoft Graph, following every page, then resolves source group names. Chain
marks a memberOf group whose source is itself a memberOf group; a source id that no longer
exists is kept and named in the Note. A kind that cannot be read is reported with Write-Error
and the summary's Coverage says Incomplete, so a missing permission never turns into a clean
result.

## PARAMETERS

### -ObjectKind

[String[]] (Optional, tenant mode)

Which kinds to read: Group, AdministrativeUnit, AutoAssignmentPolicy. Defaults to all three. A
kind that cannot be read is reported as incomplete coverage in the summary and with Write-Error;
the other kinds are still scanned.

```yaml
Type: System.String[]
DefaultValue: "@('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Tenant
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

[String[]] (Mandatory in file mode, Pipeline: ByPropertyName as FullName)

One or more .csv or .json files. Wildcards are allowed. Every row becomes one result; a file
with no recognizable rule column is an error, because it cannot be scanned and must not come
back clean.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases:
- FullName
ParameterSets:
- Name: Path
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RequestHandler

[ScriptBlock] (Optional, tenant mode)

Replaces the Graph call. Receives the URI and a headers hashtable and returns the parsed body.
Exists so tests can run tenant mode with no tenant; production callers leave it unset.

```yaml
Type: System.Management.Automation.ScriptBlock
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Tenant
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Rule

[String[]] (Mandatory in rule mode, Pipeline: ByValue, ByPropertyName as MembershipRule)

One or more membership rules as text. Each becomes one result of ObjectKind Rule.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- MembershipRule
ParameterSets:
- Name: Rule
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipGroupNameLookup

[Switch] (Optional, tenant mode)

Do not resolve source group display names. Saves one request per fifteen distinct source group
ids.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Tenant
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Tenant

[Switch] (Mandatory in tenant mode)

Read the connected tenant over Microsoft Graph. Needs a Connect-MgGraph session with
Group.Read.All, AdministrativeUnit.Read.All and EntitlementManagement.Read.All, or a subset
matching -ObjectKind.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Tenant
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

Rule text, bound by value to -Rule. Objects with a MembershipRule property, such as a group read
from Graph, bind to -Rule by property name; objects with a FullName property, such as the output
of Get-ChildItem, bind to -Path.

## OUTPUTS

### EntraMemberOf.Result

One per rule-bearing object. ObjectKind (Group, AdministrativeUnit, AutoAssignmentPolicy or
Rule), Id, DisplayName, AccessPackageName, RuleKind (user or device), Level (Retired, Review or
Clean), ReviewCode, ProcessingState, Rule, Quantifier, Operator, SourceGroupIds,
SourceGroupNames, DependsOnMemberOfGroup, DependsOn, Remediation, Note, Source and Error.

### EntraMemberOf.Summary

One per scan in tenant and file mode, after the results. Outcome (Retired, Review, Incomplete or
Clean), Coverage, Mode, per-kind Groups, AdministrativeUnits, AutoAssignmentPolicies and Rules
counts with their Coverage, MemberOfGroupCount, MemberOfGroupLimit, DependencyChainCount,
RetiredCount, ReviewCount, RetirementDate, IncompleteKinds and Message.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

SECURITY CONSIDERATIONS:
- Tenant mode is read-only. The module cannot send anything but GET.
- Group.Read.All, AdministrativeUnit.Read.All and EntitlementManagement.Read.All are the least
  privileged permissions documented for the three list calls.

TROUBLESHOOTING:
- See the README in the module folder.

## RELATED LINKS

- [Dynamic membership groups with the memberOf attribute](https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-member-of)
- [Automatic assignment policies](https://learn.microsoft.com/entra/id-governance/entitlement-management-access-package-auto-assignment-policy)
