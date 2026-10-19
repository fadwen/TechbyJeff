---
document type: cmdlet
external help file: EntraBrandingCss-Help.xml
HelpUri: https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template
Locale: en-US
Module Name: EntraBrandingCss
ms.date: 10/19/2026
PlatyPS schema version: 2024-05-01
title: Test-EntraBrandingCss
---

# Test-EntraBrandingCss

## SYNOPSIS

Finds retired CSS properties in Entra ID company branding, from files or a tenant

## SYNTAX

### Path (Default)

```
Test-EntraBrandingCss [-Path] <string[]>
```

### Tenant

```
Test-EntraBrandingCss -Tenant [-OrganizationId <string>] [-IncludeTheme]
 [-RequestHandler <scriptblock>]
```

## DESCRIPTION

Microsoft Entra ID is retiring the layout and positioning properties in company branding custom
CSS. From October 26, 2026 they are blocked and stop working, with no supported replacement. This
command parses custom CSS into declarations and reports every one that uses a retired property,
so an admin can see what will break before it does.

Two sources feed the same scanner:

File mode (-Path) reads one or more .css files, which is where a download from the Entra admin
center lands, and takes pipeline input from Get-ChildItem.

Tenant mode (-Tenant) reads every company branding localization in the connected tenant through
Microsoft Graph, and with -IncludeTheme every branding theme localization as well. It needs
Microsoft.Graph.Authentication and an existing Connect-MgGraph session; the full Graph SDK is not
required. Every call is a GET. The command never writes to the tenant.

One result comes out per source, with a Status that keeps "no custom CSS present" (NoCustomCss)
separate from "custom CSS present and nothing found" (Clean), because those are different
statements. Retired means at least one declaration uses a retired property; Review means none did
but a near miss is worth reading; Error means a tenant source could not be read. The Findings
property holds one object per flagged declaration with its selector, at-rule context, line and
column.

Matching is on the property name after comments are stripped, strings and url(...) are skipped,
and CSS escapes are decoded. A value is never matched, so transform: scale(1.2) reports transform
and not scale, and custom properties such as --display are ignored. The retired list lives in
Data/RetiredProperties.psd1 beside its source URL; Get-EntraBrandingCssProperty shows it.

## EXAMPLES

### Example 1: Scan a downloaded file

```powershell
Test-EntraBrandingCss -Path .\custom-styles.css
```

```Output
Name                         SourceType   Status       Retired Review Declarations
----                         ----------   ------       ------- ------ ------------
custom-styles.css            File         Retired            2      0           15
```

Scans the CSS file downloaded from the Entra admin center (Company branding, Edit, Layout, Custom
CSS, Download). One result comes back with the status, the counts, and a Findings property holding
each flagged declaration. Use this to check a branding file before the October 26, 2026
retirement.

### Example 2: Every retired declaration across a folder

```powershell
Get-ChildItem .\branding\*.css | Test-EntraBrandingCss |
    Select-Object -ExpandProperty Findings |
    Where-Object Level -eq 'Retired' |
    Format-Table Source, Property, Value, Selector, Line
```

Get-ChildItem output binds to -Path through its FullName property, so a folder of branding files
kept for several tenants is scanned in one pipeline. Expanding Findings gives one row per retired
declaration with the file it came from.

### Example 3: Scan the connected tenant

```powershell
Connect-MgGraph -Scopes OrganizationalBranding.Read.All
Test-EntraBrandingCss -Tenant -IncludeTheme
```

```Output
Name                         SourceType   Status       Retired Review Declarations
----                         ----------   ------       ------- ------ ------------
0                            Localization NoCustomCss        0      0            0
fr-FR                        Localization Retired            1      0            4
Contoso (en-US)              Theme        Clean              0      0            9
```

Reads every company branding localization, and with -IncludeTheme every branding theme
localization, through Microsoft Graph. A locale with no custom CSS is reported as NoCustomCss so
it is not mistaken for a locale that was checked and found clean. Every request is a GET.

## PARAMETERS

### -IncludeTheme

[Switch] (Optional, tenant mode)

Also read branding theme localizations. Themes exist only in the Graph beta API, so this is
opt-in.

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

### -OrganizationId

[String] (Optional, tenant mode)

The tenant id, as a GUID. Discovered from GET /organization when omitted, which is the usual
case. Required when that call returns more than one organization.

```yaml
Type: System.String
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

### -Path

[String[]] (Mandatory in file mode, Pipeline: ByValue, ByPropertyName as FullName)

One or more .css files. Wildcards are allowed. Each file becomes one result; a file that cannot
be read, or a path that does not exist, is reported with Write-Error and the rest continue.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases:
- FullName
ParameterSets:
- Name: Path
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RequestHandler

[ScriptBlock] (Optional, tenant mode)

Replaces the Graph call. Receives the URI and a boolean for whether to return the body as text,
and returns what Invoke-MgGraphRequest would. Exists so tests can run tenant mode with no tenant;
production callers leave it unset.

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

### -Tenant

[Switch] (Mandatory in tenant mode)

Read the connected tenant's branding over Microsoft Graph instead of files. Requires a
Connect-MgGraph session with a scope that can read organizational branding;
OrganizationalBranding.Read.All is the least privileged one Microsoft documents for every call
this makes.

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

File paths, with wildcards allowed. Objects with a FullName property, such as the output of
Get-ChildItem, bind by property name.

## OUTPUTS

### EntraBrandingCss.Result

One per source scanned. Source, SourceType (File, Localization or Theme), Name, Status
(NoCustomCss, Clean, Review, Retired or Error), HasCustomCss, RetiredCount, ReviewCount,
DeclarationCount, Length, CustomCssRelativeUrl (tenant mode), Findings and Error. Each entry in
Findings is an EntraBrandingCss.Finding with Source, Level, Property, Value, Important, Selector,
AtRule, Line, Column, FirstListedIn and Note.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

SECURITY CONSIDERATIONS:
- Tenant mode is read-only. The module cannot send anything but GET.
- OrganizationalBranding.Read.All is the least privileged permission documented for every call
  made; delegated access also needs Global Reader or Organizational Branding Administrator.

TROUBLESHOOTING:
- See the README in the module folder.

## RELATED LINKS

- [Get-EntraBrandingCssProperty]()
- [CSS template reference guide](https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template)
