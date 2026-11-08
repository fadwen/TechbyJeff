# Security Descriptor Access Warnings - Expected Behavior

## Overview

While `Find-UnknownSID.ps1` processes objects, the console may show lines such as:

```text
WARNING: [Warning] [General] All security descriptor retrieval methods failed for CN=Server01,OU=Servers,DC=contoso,DC=com
```

The log file records the same event as:

```text
[2025-07-02T10:36:31.123] [Warning] [General] [<CorrelationId>] All security descriptor retrieval methods failed for CN=Server01,OU=Servers,DC=contoso,DC=com
```

The message is written by `Get-ObjectAccessRule` in `Private\Security\Get-SecurityDescriptor.ps1`
after every retrieval strategy returned nothing for that object. The object is skipped, nothing is
counted as an error, and processing continues with the next object. A handful of these per run is
normal in most domains.

## How Retrieval Works

`Get-ObjectAccessRule` tries three strategies in order and stops at the first one that returns
access rules:

| Order | Strategy | Message when it fails | Level |
| --- | --- | --- | --- |
| 1 | `Get-Acl -Path "AD:\<DN>"` | `Get-Acl failed for <DN>: <message>` | Debug |
| 2 | Binary or deserialized `nTSecurityDescriptor` conversion | `Failed to process deserialized security descriptor for <DN> : <message>` or `Failed to convert binary security descriptor for <DN> : <message>` | Warning |
| 3 | Fresh `Get-ADObject -Identity <DN> -Properties nTSecurityDescriptor` | `Fresh AD query returned no security descriptor for <DN>` or `Fresh AD query failed for <DN>: <message>` | Warning |

Only when all three fail does the summary warning above appear. None of these calls is retried;
`Invoke-ADOperationWithRetry` wraps SID lookups and the ACL steps of `-Remove`, and `-MaxRetries`
drives the per-object retry loop in the main processing logic, which re-runs the whole object only
when processing it threw an exception. A retrieval failure is a skip, not an exception, so it is not
retried.

Two related Debug-level messages are not warnings and need no action:

- `No security descriptor found for <DN>` - the object came back without an `nTSecurityDescriptor`
  value.
- `No access rules retrieved for <DN>` - retrieval succeeded but produced no rules. Without
  `-IncludeInherited` only explicit (non-inherited) entries are kept, so an object whose ACL is
  entirely inherited is reported this way.

## Why These Warnings Occur

- **Read Permissions missing**: the running account cannot read the object's security descriptor.
  Common on objects protected by AdminSDHolder, the Deleted Objects container, and system
  containers under `CN=System` and `CN=Configuration`.
- **Transient connectivity**: the per-object `Get-Acl` call failed against the domain controller.
- **Replication state**: the object exists in the search results but its security descriptor is
  not yet readable on the responding domain controller.

Well-known SIDs such as `S-1-5-18`, `S-1-5-19` and `S-1-5-20` do not cause these warnings. They are
filtered later, per access rule, by `Test-WellKnownSID` (`Private\SID\Test-SIDFormat.ps1`), and
that filtering is logged at Debug level only.

## Expected Script Behavior

Correct behaviour when the warning appears:

- Processing continues with the next object.
- The object still counts in `Total objects processed` in the final summary.
- `Processing errors` in the summary is not incremented.
- The run completes and writes the summary normally.

Messages that indicate an actual problem rather than an expected skip:

- `[Error] [General] Unexpected error retrieving access rules for <DN>: <message>` - the catch
  block in `Get-ObjectAccessRule` fired; the object shape was not one the three strategies handle.
- `[Error] [General] Error in orchestrated processing for object <DN> : <message>` - the per-object
  workflow in `Find-OrphanedSIDsInObject` failed after retrieval.
- `[Error] [MainProcessing] Error processing object <DN>: <message>` followed by
  `Retry attempt N of M for object <DN>` - the main loop caught an exception and is retrying up to
  `-MaxRetries` times with a 2, 4, 6... second back-off.

## Troubleshooting

### Count affected objects

```powershell
$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Select-String -Path $log.FullName -Pattern 'All security descriptor retrieval methods failed for (.+)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
```

### Check one object by hand

```powershell
$dn = 'CN=Server01,OU=Servers,DC=contoso,DC=com'
Get-Acl -Path "AD:\$dn" | Select-Object -ExpandProperty Access | Measure-Object
Get-ADObject -Identity $dn -Properties nTSecurityDescriptor | Select-Object DistinguishedName, nTSecurityDescriptor
```

If both calls fail with access denied, the running account needs **Read Permissions** on that
object or its parent. If `Get-Acl` fails but `Get-ADObject` returns a descriptor, the AD: drive is
the problem; check that the `ActiveDirectory` module loaded in the same session.

### Make the cause visible

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'OU=Servers,DC=contoso,DC=com' -LogLevel Debug -WhatIf
```

With `-LogLevel Debug` the file receives the strategy-1 `Get-Acl failed for <DN>: <message>` line,
which carries the underlying exception text.

### Reduce console noise

`-LogLevel` filters what is written to the **file**; console output is not filtered, so warnings
still print. `-SuppressConsoleOutput` silences only security-event console lines
(`Write-SecurityStructuredLogEntry`), not these warnings. To keep the console quiet, redirect the
warning stream:

```powershell
.\Find-UnknownSID.ps1 -SearchBase 'OU=Servers,DC=contoso,DC=com' 3> $null
```

The warnings remain in the log file.

## Related Documentation

- Retrieval failures in depth: `.\Troubleshooting\Security\Security-Descriptor-Issues.md`
- Identity resolution after retrieval: `.\Troubleshooting\Security\Identity-Resolution-Issues.md`
- Per-object workflow: `.\Troubleshooting\Common\SID-Processing-Orchestration-Issues.md`
