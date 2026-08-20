# WmicTriage

[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Pester](https://img.shields.io/badge/Tested_with-Pester_6-green?style=flat-square)](https://pester.dev)
[![SARIF](https://img.shields.io/badge/Output-SARIF_2.1.0-orange?style=flat-square)](https://sarifweb.azurewebsites.net/)

Finds deprecated WMIC usage across a codebase and sorts every hit by how hard it
will be to replace, rather than reporting a flat list of matches.

| Function | What it does |
|----------|--------------|
| `Invoke-WmicScan` | Scans files and returns one classified finding per call site |
| `Export-WmicScanReport` | Writes those findings as CSV or SARIF |
| `Get-WmicRule` | Lists the rules, so a classification can be argued with |

## The problem

Everyone already knows WMIC is deprecated. PSScriptAnalyzer answers the
yes-or-no question for PowerShell files and a grep answers it for everything
else. Neither answers the question a migration is actually scheduled against:
**which of these four hundred hits is a two-second swap, and which is a day?**

The inventory is the expensive part of retiring WMIC, and a flat list of four
hundred matches does not help anyone plan. So the output here is a
classification, not a match list.

## The tiers

Four named tiers, in increasing order of effort. Not severity — effort.

| Tier | Meaning | Example |
|------|---------|---------|
| **Mechanical** | Swap the command, done | `wmic bios get serialnumber` on its own line |
| **Wrapped** | Output is captured and parsed; the wrapper must be rewritten too | `for /f ... in ('wmic ...')` |
| **Semantic** | The correct translation is a judgment call, not a substitution | `wmic product`, anything touching a datetime or multi-value property |
| **Environmental** | PowerShell may not exist at the call site | WMIC inside `startnet.cmd` or a WinPE task sequence step |

### Wrapped is the reason this exists

No other tool detects it, and it is the case that produces silently wrong output
rather than a clean failure.

```batch
for /f "tokens=2 delims==" %%A in ('wmic os get caption /value') do set OSNAME=%%A
```

Swap the command for `Get-CimInstance` and nothing breaks. The `for /f` keeps
running, keeps setting `OSNAME` from whatever the token positions now land on,
and the report it feeds looks exactly as plausible as it did last week. The
`tokens=` spec — not the command — is the thing that has to be rewritten, and it
is not always on the same line, which is why a finding here spans the whole
block.

### Escalation, not first match

When several rules match one call, the finding takes the **hardest** tier, and
every rule that fired is kept in `RuleIds`. A mechanical one-liner sitting in a
WinPE script is reported as Environmental: the substitution really is trivial,
but whether the boot image has PowerShell at all is not, and that question has
to be answered first.

## Detection surface

Beyond the obvious `\bwmic\b`:

- **`for /f` blocks** — captured as a whole block, with the `tokens=`/`delims=`
  spec recorded, because that is what gets rewritten. Only the *in-clause* is
  Wrapped; a call sitting in the do-body merely runs there and stays Mechanical.
- **Output consumption** — `> file`, `/output:`, `/append:`, a pipe into
  `find`/`findstr`, assignment in PowerShell, `.Exec()` in VBScript.
- **Format switches implying a parser** — `/value`, `/format:csv`, `/format:list`.
- **`/node:`** — becomes a CIM session, which is a protocol change, not a swap.
  `/password:` on the same line is raised as a **separate security finding**.
- **Invocation without the literal string `wmic` at the front** — `%COMSPEC% /c`,
  a full path under `System32\wbem`, `Start-Process`, `WScript.Shell`,
  `subprocess`. These do not change the tier; they change whether the *count* can
  be trusted, so each is recorded.
- **`Win32_Product`** — its own rule, at Semantic, regardless of anything else.
  Enumerating it runs an MSI consistency check whichever command asks for it, so
  a like-for-like translation keeps the actual problem.
- **Non-obvious aliases** — the report names the target class, so nobody has to
  guess that `qfe` is `Win32_QuickFixEngineering` or `rdtoggle` is
  `Win32_TerminalServiceSetting`.

### File types

`.bat` and `.cmd` are the priority, because that is the gap — PSScriptAnalyzer
never opens them. Then `.ps1`, `.psm1`, `.vbs`, `.vbe`, `.wsf`, `.js`, `.py`,
and `.xml`.

Each gets the reader it deserves rather than one regex for all of them:

- **Batch** — joins `^` continuations, tracks comment state, balances
  parentheses across lines to find block extents.
- **PowerShell** — uses the actual parser. Capture detection is exact rather
  than guessed, because `$x = wmic`, `(wmic ...)`, `wmic ... |` and `wmic ... >`
  are four syntactic positions that a regex has to guess at and the tree simply
  knows.
- **Task sequence XML** — a real XML parser, not a regex, so a finding names the
  **step** rather than a line number nobody will ever edit. The `runIn`
  attribute (or the enclosing group names) decides whether the step is WinPE.

## Install

Nothing to install. No `RequiredModules`, no WMI calls, nothing Windows-only —
this is text and XML parsing over files on disk, so scanning a deployment share
from a Linux build agent works.

```powershell
Import-Module .\WmicTriage.psd1
```

## Try it first

[`Examples/DeploymentShare`](./Examples/DeploymentShare) is a small fake
deployment share — a collector carried forward from an XP rollout, a vendor file
nobody may edit, a WinPE startup script, a task sequence export, and a migration
somebody started and abandoned.

```powershell
Import-Module .\WmicTriage.psd1
Invoke-WmicScan -Path .\Examples\DeploymentShare
```

Nine files, 29 deprecation findings and one security finding: 6 Mechanical,
4 Wrapped, 15 Semantic, 4 Environmental. Only 6 of the 29 are the simple swap
that the whole job is usually assumed to be, which is the ratio the tool exists
to show you. [`Examples/README.md`](./Examples/README.md) walks through the
findings worth looking at.

## Usage

Scan a tree. Directories are walked in full; there is no `-Recurse` to
remember, because an inventory that silently covered only the top level is worse
than none — it will be believed.

```powershell
Invoke-WmicScan -Path '\\dp01\Deploy$'
```

```text
Tier          RelativePath      Line Command
----          ------------      ---- -------
Environmental Boot\startnet.cmd    3 wmic csproduct get uuid /value
Wrapped       Scripts\Inv.cmd      2 wmic os get caption /value
Semantic      Scripts\Apps.cmd    11 wmic product get name,version
Mechanical    Scripts\Inv.cmd     14 wmic bios get serialnumber
```

Isolate the work that will silently produce wrong answers if it is swapped
rather than restructured:

```powershell
Invoke-WmicScan -Path .\Scripts -Tier Wrapped |
    Format-List Command, ForOptions, Reason, SuggestedReplacement
```

Ask why something was classified the way it was:

```powershell
(Get-WmicRule -Id WMIC200).Reason
```

## Reports

```powershell
$findings = Invoke-WmicScan -Path .

# For whoever is planning the migration
$findings | Export-WmicScanReport -Path .\wmic.csv

# For a pipeline, so the tiers annotate the actual lines
$findings | Export-WmicScanReport -Path .\wmic.sarif -Format Sarif
```

The SARIF carries a `partialFingerprints` entry over path, rule and command —
deliberately **not** the line number. Add a comment at the top of a batch file
and every call below it moves; a fingerprint that included the line would close
two hundred findings and open two hundred identical ones, and the second report
anyone read would be noise.

## Using it in CI

Exit non-zero on Mechanical and Wrapped, where a machine can judge the work.
Zero with a warning on Semantic and Environmental, because both end in a
judgment call — and a build that fails on a judgment call is a build people
learn to bypass.

The module never calls `exit` itself. A library that terminates its host is a
library you cannot call from anything else, so the verdict rides on the
findings instead:

```powershell
$summary = Invoke-WmicScan -Path . -Summary
$summary.ByTier

if ($summary.FailsBuild) {
    Write-Error 'Mechanical or Wrapped WMIC usage found'
    exit 1
}
```

Every finding also carries `FailsBuild` individually, and the SARIF `level`
follows the same rule — `error` for Mechanical and Wrapped, `warning` for
Semantic and Environmental, `note` for anything in a comment.

Security findings are the one deliberate disagreement: a checked-in password is
surfaced as `error` because it is one by any reading, but it never fails the
build, since this gate is about WMIC deprecation and letting one problem close
the other helps nobody. `properties.kind` carries the distinction.

## Suggestions are advisory, always

Every finding has a `SuggestedReplacement`, and nothing in this module will ever
apply one. `Advisory` is `$true` on every finding, in every format.

That restraint is what makes printing them defensible. On the Wrapped tier the
honest suggestion is *"restructure this block"* rather than a command to paste,
because a one-line replacement for a block would be a confident lie. On the
Semantic tier no tool can be right, which is what the tier means.

## What it deliberately does not do

**It does not resolve variables.** A batch file that does this:

```batch
set WMICPATH=%SystemRoot%\System32\wbem\wmic.exe
"%WMICPATH%" os get caption
```

gets a Semantic finding on line 2 and **nothing on line 3**. Chasing the call
sites is an AST problem in PowerShell and unsolvable in batch, and it would eat
the whole project. So the finding says in as many words that the count is an
undercount until someone greps for that variable by hand — in the report, where
it gets read, rather than only in this file.

**It does not score confidence.** Four named tiers people can filter on beat a
0-100 number nobody calibrates.

**It does not skip comments by default.** A WMIC command in a `rem` line is
usually documentation that will mislead someone later, which is a real finding.
It never fails a build, and `-ExcludeComment` drops it entirely.

## Adding a rule

Every detection is one entry in `Data\WmicRules.psd1`. The engine holds no WMIC
knowledge of its own, so a rule that appears there is live — no code change.

```powershell
@{
    Id     = 'WMIC211'
    Name   = 'Something worth catching'
    Tier   = 'Semantic'
    Match  = @{ Alias = @('nicconfig'); Verb = @('call') }
    Reason = @( 'Why this is not a swap.' )
    Suggestion = @( 'What to do instead, with {Class} and {Properties} filled in.' )
}
```

`Reason` and `Suggestion` are arrays purely because a `.psd1` is restricted
language — it cannot concatenate strings, and a here-string would have to close
at column zero in the middle of a nested hashtable. They are joined with a
single space on load.

The loader validates hard, and that is deliberate. A rule with a typo in its
`Match` key would not throw — it would simply never fire, and the report would
come back quietly short. So an unknown match key, an unknown tier, a duplicate
id, and a reference to a property group that does not exist are all errors at
load time. See the header of `WmicRules.psd1` for the full match vocabulary.

The other two data files are worth editing too:

- `Data\WmicAliases.psd1` — alias to class, with `NonObvious` marking the ones
  the reader will not guess.
- `Data\WmicProperties.psd1` — the property groups behind the Semantic tier:
  `DateTime`, `Interval`, `MultiValue`, `Boolean`. Adding a property here is the
  cheapest way to make the scanner smarter.

## Testing

```powershell
Invoke-Pester -Path .\Tests
```

138 tests, 91% command coverage. The fixtures under `Tests\Fixtures` are
deliberately written the way legacy inventory scripts are written — they are
corpus, not examples.

## Notes

Targets Windows PowerShell 5.1 as well as PowerShell 7, unlike most new modules
in this repository. The estates that still run WMIC are the same estates whose
jump boxes and build servers never got `pwsh`, and a migration tool that cannot
run where the migration is happening is not much use.
