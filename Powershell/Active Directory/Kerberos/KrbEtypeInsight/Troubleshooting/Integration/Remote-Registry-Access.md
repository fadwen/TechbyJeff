# Remote registry access

`Get-KrbDomainEtypeContext` warned that it could not read the Kerberos policy from a controller,
or `DomainDefaultSource` is `WindowsDefault` when you expected `Registry`.

## What is being read

Two values, from each domain controller:

| Path | Value |
|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Services\Kdc` | `DefaultDomainSupportedEncTypes` |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters` | `SupportedEncryptionTypes` |

The first is the KDC's fallback for accounts whose attribute is unset. The second is what the
"Network security: Configure encryption types allowed for Kerberos" policy writes; applied to a
controller it constrains the KDC itself.

## Why it degrades rather than fails

If the registry cannot be read, the module falls back to the documented Windows default of
`0x27` and records `DomainDefaultSource = 'WindowsDefault'` on the returned object. Every
finding about an account with an unset attribute then rests on that assumption, and the HTML
report states it in the baseline section.

A partial baseline reported honestly is more useful than no assessment. A partial baseline
presented as measured is worse than none.

## Requirements

Collection uses PowerShell remoting, except for the local machine which is read in-process -
remoting to localhost would otherwise require WinRM to be configured even when the script is
running on the controller itself.

```powershell
Test-WSMan -ComputerName dc01
Enter-PSSession -ComputerName dc01   # confirm interactively
```

What has to be true:

- The `WinRM` service running on each controller
- TCP 5985 (HTTP) or 5986 (HTTPS) reachable
- The account a member of `Remote Management Users`, or an administrator on the controller

```powershell
Enable-PSRemoting -Force        # on each controller, if not already configured
```

## Alternative credentials

```powershell
$cred = Get-Credential
Get-KrbDomainEtypeContext -Credential $cred
```

## Running without it

If remoting is not available and will not be:

```powershell
Get-KrbDomainEtypeContext -SkipRegistry
```

This skips the collection entirely and reports the Windows default as the baseline, with
`DomainDefaultSource = 'WindowsDefault'`. Preferable to a run that appears to have measured
something it did not.

Better still, gather the values by any means you do have and pass the real number down:

```powershell
Get-KrbPrincipalEtype -All -DomainDefaultEncryptionTypes 0x1F
Get-KrbEvent | Get-KrbEtypeRisk -DomainContext $context
```

## Verifying which controllers answered

```powershell
$context = Get-KrbDomainEtypeContext
$context.DomainControllers | Select-Object Name, RegistryReachable, RegistryError
```

`RegistryError` carries the underlying exception message, which usually names the cause -
WinRM not listening, access denied, or the host being unreachable at all.

## Related

- [Controller policy drift](../Common/Controller-Policy-Drift.md)
- [Event log permissions](../Security/Event-Log-Permissions.md)
