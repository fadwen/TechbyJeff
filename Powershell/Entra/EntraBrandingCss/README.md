# EntraBrandingCss

A read-only PowerShell module that finds the CSS properties Microsoft Entra ID is retiring from
company branding custom CSS. It reads a downloaded `.css` file, or every branding localization in
a tenant through Microsoft Graph, parses the CSS into declarations, and reports each one that uses
a retired property with its selector, at-rule context, line and column.

Version 0.1.0. Not on the PowerShell Gallery; import it from this folder.

## Why this exists

Microsoft is retiring the layout and positioning properties in Entra ID company branding custom
CSS. The dates, from Message Center:

| Date | What happens | Source |
| --- | --- | --- |
| January 5, 2026 | Tenants created after this date have no custom CSS for company branding | Learn page |
| July 21, 2026 | Older tenants not already using custom CSS can no longer configure it | MC1435782, Learn page |
| October 26, 2026 | Retired properties stop being honored; the action-by date | MC1435782, MC1458474 |
| Late November 2026 | Rollout of the block completes worldwide | MC1435782 |
| 2027 | Microsoft plans to move toward retiring custom CSS entirely, with notice | MC1458474 |

Retired properties are blocked and stop working. Microsoft states there is no supported migration
or replacement for them. Branding themes are in scope as well as company branding. Microsoft Entra
External ID tenants are not affected.

The Learn page itself gives no calendar date for the block; it says "Later" and "Eventually". The
October 26, 2026 date comes from the two Message Center posts.

### The list grew, and most coverage has the short one

The first Message Center post, and most of the news written from it, lists ten bullets. The
current Learn page lists 49. Anyone who checked their CSS against the short list may have an
all-clear that is wrong. That gap is the reason this module exists.

The names, by where each was first announced:

| First listed in | Published | Names | Examples |
| --- | --- | --- | --- |
| MC1435782 | July 21, 2026 | 19 | `position`, `margin`, `transform`, `opacity`, `overflow` |
| Learn page only | by August 18, 2026 | 11 | `display`, `visibility`, `inset`, `zoom`, `-webkit-transform` |
| MC1458474 | August 21, 2026 | 28 | `margin-block`, `grid-area`, `overflow-x`, `clip`, `mask` |

`display` and `visibility` are the ones that matter most in practice. Hiding "Can't access your
account?" or the footer links with `display: none` is the most common thing a branding file does,
and it is on the list.

### How 49 becomes 58

The Learn page shows 49 bullets. Two of them fold other names in: "`position` (including `top`,
`right`, `bottom`, `left`, and `z-index`)" and "`margin` (including `margin-top`,
`margin-bottom`, `margin-left`, and `margin-right`)". A declaration uses one name, so the scanner
matches on names: 49 bullets plus 5 plus 4 included longhands is 58. `Get-EntraBrandingCssProperty`
shows all 58 with the bullet each came from.

The list was diffed against the Learn page source on October 19, 2026 (page `ms.date` 08/18/2026)
and matched it exactly. An opt-in test re-does that diff; see [Tests](#tests).

## Quick start

```powershell
Import-Module .\EntraBrandingCss.psd1

# A file downloaded from the Entra admin center: Company branding > Edit > Layout > Custom CSS
Test-EntraBrandingCss -Path .\custom-styles.css

# The connected tenant, every company branding localization and every branding theme
Connect-MgGraph -Scopes OrganizationalBranding.Read.All
Test-EntraBrandingCss -Tenant -IncludeTheme
```

Output from file mode against the demo fixture in this repository, which hides the
"Can't access your account?" link and the footer links the way many real branding files do:

```text
PS> Test-EntraBrandingCss -Path .\Tests\Fixtures\demo-branding.css

Name                         SourceType   Status       Retired Review Declarations
----                         ----------   ------       ------- ------ ------------
demo-branding.css            File         Retired            2      0           15

PS> (Test-EntraBrandingCss -Path .\Tests\Fixtures\demo-branding.css).Findings

Level   Property             Value                    Selector                                 AtRule                 Line
-----   --------             -----                    --------                                 ------                 ----
Retired display              none                     #cantAccessAccount, .ext-sign-in-box a[h…                        38
Retired display              none                     .ext-footer-links                                                43
```

Everything is on the objects; the tables are only the default view. `Format-List` or
`Select-Object *` shows the rest.

## What comes back

One `EntraBrandingCss.Result` per source. Its `Status` keeps two statements apart that are easy
to collapse:

| Status | Meaning |
| --- | --- |
| `NoCustomCss` | There was nothing to scan: an empty file, or a tenant locale with no custom CSS |
| `Clean` | There was custom CSS and nothing in it is retired or worth a look |
| `Review` | Nothing retired, but at least one near miss a person should read |
| `Retired` | At least one declaration uses a retired property |
| `Error` | Tenant mode only: the locale's CSS could not be read; `Error` holds the message |

`NoCustomCss` and `Clean` are different answers. One says nobody looked because there was
nothing to look at; the other says somebody looked and it is fine.

Result properties: `Source` (file path, or the Graph path under the tenant id), `SourceType`
(`File`, `Localization`, `Theme`), `Name`, `Status`, `HasCustomCss`, `RetiredCount`,
`ReviewCount`, `DeclarationCount`, `Length`, `CustomCssRelativeUrl` (tenant mode), `Findings`,
`Error`.

Each `EntraBrandingCss.Finding` has `Source`, `Level`, `Property`, `Value`, `Important`,
`Selector`, `AtRule`, `Line`, `Column`, `FirstListedIn` and `Note`.

### Retired and Review

**Retired** is an exact match, case-insensitive, against the 58 names. That list is never
extended by judgment.

**Review** is a short list of near misses that are not on Microsoft's list but can do the same
job as something that is. They are reported so a person reads them, never as Retired:

- `-webkit-filter` and `-webkit-clip-path`: vendor forms of `filter` and `clip-path`
- `all`: a shorthand that resets every property, `display` and `visibility` included
- `inset-block`, `inset-inline` and their `-start`/`-end` longhands: logical forms of `top`,
  `right`, `bottom` and `left`

Each entry's reason is in `Data/RetiredProperties.psd1` and on the finding's `Note`.

## How matching works

The scanner parses declarations rather than searching text, because a text search is wrong in
both directions: `overflow-wrap` contains `overflow`, and `/* display: none */` contains
`display`.

- `/* */` comments are removed first, multi-line ones included.
- Quoted strings and anything inside parentheses, which covers `url(...)` and data URIs, never
  start or end a declaration.
- Declarations inside `@media`, `@supports`, `@container`, `@layer` and CSS nesting are found,
  and the finding records the chain of at-rules above it.
- The property name is matched whole after trimming. `overflow-wrap`, `backdrop-filter`,
  `grid-row-gap`, `offset-anchor`, `transform-origin` and similar do not match.
- Values are never matched. `transform: scale(1.2)` reports `transform` and not `scale`.
- Custom properties such as `--display` are ignored.
- CSS escapes in a property name are decoded, so `\70 osition` is reported as `position` with a
  note. The sign-in page's own sanitizer decodes them the same way; a scanner that did not would
  call a file clean that is about to break.
- `!important`, minified single-line files, CRLF and LF, UTF-8 with and without a byte order
  mark, and empty files are all handled. Line and column point at the property name.

It is not a full CSS parser and does not need to be. It answers one question: which property
names are declared, where, and under what selector.

## Tenant mode

`Test-EntraBrandingCss -Tenant` needs `Microsoft.Graph.Authentication` and an existing
`Connect-MgGraph` session. The rest of the Graph SDK is not used. The module has no
`RequiredModules`, so file mode and the unit tests run on a machine that has never installed it.

Every request is a GET. The function that sends requests has no way to send anything else. The
module never writes to a tenant and never uploads anything.

### What it calls

Company branding, all on v1.0:

```text
GET /v1.0/organization?$select=id                                       tenant id, unless -OrganizationId is given
GET /v1.0/organization/{id}/branding/localizations                       every locale, including the default (id 0)
GET /v1.0/organization/{id}/branding/localizations/{localeId}/customCSS  the CSS, one request per locale
```

`customCSS` is a Stream property. Graph does not return stream properties in a list; the list
carries `customCSSRelativeUrl` (and `cdnList`) instead, and the CSS itself comes from the
stream endpoint on the third line. Each result keeps the `customCSSRelativeUrl` the list reported
so the two signals can be compared, and the integration test asserts they agree. A 404 from the
stream endpoint, or an empty body, means no custom CSS and comes out as `NoCustomCss`.

The Learn page's own procedure pastes the list response into a browser-based inspector. That
works because the inspector does not look for CSS in the response either: it builds a URL from
`cdnList` and `customCSSRelativeUrl` and fetches the CSS from the public branding CDN. This
module reads it through Graph instead, so it needs a token but does not depend on the CDN.

Branding themes, with `-IncludeTheme`, on beta:

```text
GET /beta/organization/{id}/branding/themes
GET /beta/organization/{id}/branding/themes/{themeId}/localizations
GET /beta/organization/{id}/branding/themes/{themeId}/localizations/{locale}/customCSS
```

Themes exist only in the beta API, which Microsoft says may change. Every beta call lives in one
file, `Private/Get-EntraBrandingThemeSource.ps1`, so it can be updated or removed without touching
the rest. It is opt-in for the same reason.

### Permissions

Microsoft documents `OrganizationalBranding.Read.All` as the least privileged permission that
covers every call above, for both delegated and application access. For the v1.0 calls the
documentation also lists `User.Read` as sufficient for delegated access, and for the beta theme
calls it lists only `OrganizationalBranding.Read.All`. With delegated access the signed-in user
also needs a role: Global Reader or Organizational Branding Administrator are the least
privileged ones documented.

```powershell
Connect-MgGraph -Scopes OrganizationalBranding.Read.All
```

### Verified against a tenant

This section records what was observed on a real tenant rather than what the documentation says.
It is filled in from the first tenant run; until then, the statements above about the list
response and the stream endpoint are from the Graph reference.

## Compatibility

- PowerShell 7.6: file mode and tenant mode. All tests run here.
- Windows PowerShell 5.1: file mode is tested; the fixture results are identical to 7.6. Tenant
  mode is not tested on 5.1. `Microsoft.Graph.Authentication` supports 5.1, so it is expected to
  work, but that is an expectation and not a result.
- Linux and macOS: not tested. Nothing in the module is Windows-specific.

## Tests

Pester 6.2 or later. From this folder:

```powershell
Invoke-Pester -Path .\Tests
```

What runs by default is the unit suite: the module contract and data file, the parser against
inline CSS, and the public command against the fixtures under `Tests/Fixtures` in file mode and
against a scripted request handler in tenant mode. No test reaches Graph.

Two suites are opt-in:

- `Tests/Integration/Tenant.Tests.ps1` runs tenant mode for real and skips itself unless the
  session is already connected with `Connect-MgGraph`. It asserts nothing tenant-specific; a
  tenant with no custom CSS anywhere is a valid result.
- `Tests/Integration/LearnPage.Tests.ps1` fetches the current Learn page source and fails if its
  "Deprecated properties" bullets no longer match `Data/RetiredProperties.psd1`. Set
  `ENTRABRANDINGCSS_ONLINE=1` to run it. When it fails, Microsoft changed the list.

The fixtures are the specification. Each file's leading comment says what it expects, and
`Tests/Fixtures/.gitattributes` stops git from normalizing the CRLF and BOM files.

## Updating the list

Edit `Data/RetiredProperties.psd1`. It is the only file that names a property. Update
`SourceDate` to the page's `ms.date`, `VerifiedOn` to today, and the counts in this README and
in `Tests/Unit/Module.Contract.Tests.ps1`, then run the online test to confirm.

## Limitations

- The Review list is a judgment call and deliberately short. It is not a claim about what
  Microsoft will block next.
- The scanner does not produce a cleaned copy of the CSS. Removing a declaration changes what the
  page looks like, and that is a decision to make with the file open, not one to automate.
- Branding themes come from the beta API and could change shape.
- A tenant with several organization objects needs `-OrganizationId`.

## References

- [CSS template reference guide](https://learn.microsoft.com/entra/fundamentals/reference-company-branding-css-template),
  the source of the retired list
- [organizationalBrandingLocalization](https://learn.microsoft.com/graph/api/resources/organizationalbrandinglocalization?view=graph-rest-1.0)
  and [Get organizationalBrandingLocalization](https://learn.microsoft.com/graph/api/organizationalbrandinglocalization-get?view=graph-rest-1.0)
- [organizationalBrandingTheme (beta)](https://learn.microsoft.com/graph/api/resources/organizationalbrandingtheme?view=graph-rest-beta)
  and [organizationalBrandingThemeLocalization (beta)](https://learn.microsoft.com/graph/api/resources/organizationalbrandingthemelocalization?view=graph-rest-beta)
- Message Center MC1435782 (July 21, 2026) and MC1458474 (August 21, 2026), in the Microsoft 365
  admin center
