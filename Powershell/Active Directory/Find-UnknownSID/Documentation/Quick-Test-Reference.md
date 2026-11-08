# Quick Test Reference

How to run the Find-UnknownSID Pester suite and what the latest run produced. The structure of
the suite (one table per folder, with the function or class each file covers) is in
[Tests/Pester-Test-Mapping.md](../Tests/Pester-Test-Mapping.md).

## Requirements

- Windows PowerShell 5.1
- Pester 3.4.0, the version that ships with Windows. The tests use Pester 3 syntax
  (`Should Be`, `Assert-MockCalled`) and do not run under Pester 4 or later.
- No Active Directory domain and no RSAT `ActiveDirectory` module. Every test that touches an
  AD cmdlet mocks it. On a machine without RSAT, `Tests\TestHelpers\ADCmdletStubs.ps1` defines
  placeholder cmdlets so that Pester has something to mock.

Load Pester 3.4.0 explicitly first. A machine with a newer Pester installed for the current user
would otherwise autoload that version and fail every assertion.

## Run the suite

Run from the project root, one suite folder per `Invoke-Pester` call. Pester 3.4 recurses a
directory on its own; it has no `-Recurse` parameter, and passing several paths in one call is
unreliable on that version.

```powershell
Import-Module Pester -RequiredVersion 3.4.0 -Force

Invoke-Pester -Path .\Tests\Unit
Invoke-Pester -Path .\Tests\Integration
Invoke-Pester -Path .\Tests\Performance
```

Run one file the same way:

```powershell
Invoke-Pester -Path .\Tests\Unit\Private\Security\Test-PathTraversal.Tests.ps1
```

`-PassThru` returns the result object, with `PassedCount`, `FailedCount`, `SkippedCount`, and
`PendingCount` properties, for scripted gates.

## Latest recorded run

Windows 11, Windows PowerShell 5.1, Pester 3.4.0, no RSAT `ActiveDirectory` module, not elevated.

| Suite | Run | Passed | Failed | Skipped | Inconclusive | Wall time |
| --- | --- | --- | --- | --- | --- | --- |
| `Tests\Unit` | 1940 | 1938 | 0 | 1 | 1 | about 3.5 minutes |
| `Tests\Integration` | 216 | 216 | 0 | 0 | 0 | about 21 seconds |
| `Tests\Performance` | 170 | 170 | 0 | 0 | 0 | about 9 seconds |
| Total | 2326 | 2324 | 0 | 1 | 1 | about 4 minutes |

The two results that are not passes depend on the environment, not on the code:

- Skipped: `Get-BackupMetadata.Tests.ps1`, "Should not expose sensitive information in error
  messages". The `It` carries `-Skip` in the file.
- Inconclusive: `Initialize-LogDirectory.Tests.ps1`, the test that creates a log file in the
  drive root. Writing to the root of the system drive needs elevation on a default Windows
  install; the test reports `Set-TestInconclusive` when it cannot. Run the Unit suite from an
  elevated prompt to exercise it.

The executed count is lower than the number of `It` blocks in the files (2412 in `Tests\Unit`,
see the mapping document) because some `It` blocks sit inside helper functions or inside guarded
blocks that only run under certain conditions, and Pester 3.4 counts an `It` with `-TestCases`
once in its totals regardless of how many cases it expands to. The executed numbers above are the
status; the per-file `It` counts describe the structure.

## Reading the output

Pester 3.4 prints `[+]` for a pass, `[-]` for a failure, `[!]` for a skipped test, and `[?]`
for a pending or inconclusive one. The run ends with two summary lines:

```text
Tests completed in 3.5m
Passed: 1938 Failed: 0 Skipped: 1 Pending: 0 Inconclusive: 1
```

Tests that exercise failure paths mock the logging functions rather than letting them write.
`Private\Security\Test-PathTraversal.ps1` and three test files also check the `PESTER_TESTING`
environment variable, which the tests set, to hold back warnings that are expected during a run.
