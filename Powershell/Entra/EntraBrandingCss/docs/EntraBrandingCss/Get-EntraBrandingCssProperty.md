---
document type: cmdlet
external help file: EntraBrandingCss-Help.xml
HelpUri: https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template
Locale: en-US
Module Name: EntraBrandingCss
ms.date: 10/19/2026
PlatyPS schema version: 2024-05-01
title: Get-EntraBrandingCssProperty
---

# Get-EntraBrandingCssProperty

## SYNOPSIS

Lists the CSS property names the scanner reports, with where each one was announced

## SYNTAX

### __AllParameterSets

```
Get-EntraBrandingCssProperty [[-Level] <string[]>]
```

## DESCRIPTION

Returns the contents of Data/RetiredProperties.psd1 as objects: the 58 retired names Microsoft
lists on the CSS template reference page, counting the longhands it folds into the position and
margin bullets, and the short Review list of near misses the scanner flags for a person to read.

FirstListedIn says where a retired name was first announced, which is the point of the command.
Message Center post MC1435782 (July 2026) carried 19 names; MC1458474 (August 2026) added 28; 11
more, including display and visibility, appear only on the Learn page. A tenant checked against
the first post alone can have a false all-clear.

## EXAMPLES

### Example 1: Count the retired names

```powershell
Get-EntraBrandingCssProperty -Level Retired | Measure-Object | Select-Object Count
```

```Output
Count
-----
   58
```

Confirms the list a scan is using: 49 bullets on the Learn page, plus the 5 and 4 longhands it
folds under position and margin.

### Example 2: How many names each announcement introduced

```powershell
Get-EntraBrandingCssProperty -Level Retired | Group-Object FirstListedIn | Select-Object Name, Count
```

```Output
Name      Count
----      -----
MC1435782    19
Learn        11
MC1458474    28
```

Shows why a check against the first Message Center post alone misses 39 names. Review entries
have no FirstListedIn, which is why -Level Retired is passed here.

### Example 3: The near misses and why each is listed

```powershell
Get-EntraBrandingCssProperty -Level Review | Format-List Property, Reason
```

```Output
Property : -webkit-filter
Reason   : Vendor form of filter, which is retired. Microsoft lists only the unprefixed name.

Property : all
Reason   : Shorthand that resets every property, including display and visibility, which are retired.
```

The Review list is deliberately short and never reported as Retired. Reading the reason is how to
decide whether a Review finding needs action.

## PARAMETERS

### -Level

[String[]] (Optional)

Retired, Review, or both. Defaults to both.

```yaml
Type: System.String[]
DefaultValue: "@('Retired', 'Review')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
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

### None

This command takes no pipeline input.

## OUTPUTS

### EntraBrandingCss.Property

One per name: Property, Level (Retired or Review), Bullet (the Learn bullet the name came from,
Retired only), FirstListedIn (MC1435782, MC1458474 or Learn; Retired only), Reason (Review
only), SourceUrl and SourceDate.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

## RELATED LINKS

- [Test-EntraBrandingCss]()
- [CSS template reference guide](https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template)
