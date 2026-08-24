# Event log permissions

`Get-KrbEvent` reports "Failed to read Kerberos events from <controller>" or access is denied.

## The right permission

Membership of **Event Log Readers** on each domain controller is sufficient. This is a built-in
domain local group.

```powershell
Add-ADGroupMember -Identity 'Event Log Readers' -Members 'svc-krbaudit'
```

**Domain Admin is not required and should not be used.** This module is read-only by design, and
running a read-only assessment with write authority discards that property for no benefit. The
integration suite asserts that no principal's `msDS-SupportedEncryptionTypes` changes across a
full assessment run, which is a guarantee worth keeping meaningful.

Group membership changes affect the security token, so the account needs a new logon - or a new
Kerberos ticket - before they take effect:

```powershell
klist purge
```

## Remote access requirements

`Get-WinEvent -ComputerName` uses RPC over the Windows Event Log service, not WinRM. What has to
be reachable:

- TCP 135 (endpoint mapper)
- The dynamic RPC range (49152-65535 by default)
- The `Windows Event Log` service running on the target

```powershell
Test-NetConnection -ComputerName dc01 -Port 135
Get-Service -ComputerName dc01 -Name EventLog
```

A firewall permitting only 445 and 389 - common between sites - will fail here while everything
else about the domain appears healthy.

## Alternative credentials

```powershell
$cred = Get-Credential
Get-KrbEvent -Credential $cred
```

`-Credential` is ignored for `-Path`, which reads a file with the current process identity.

## When remote access is not available

Export locally on each controller and process the files. This needs no network access to the
controller at all, and is the recommended pattern for large estates regardless:

```powershell
wevtutil epl Security C:\Temp\krb.evtx "/q:*[System[(EventID=4768 or EventID=4769 or EventID=4771)]]"
```

See [Event volume](../Performance/Event-Volume.md).

## Handling the output

A completed assessment names accounts, service principal names, client IP addresses and, in the
JSON export, full evidence including client lists. Treat reports as internal documents:

- Do not attach a raw report to a vendor support case without redaction
- Exported `.evtx` slices contain the same data in bulk - clean them up
- The HTML report HTML-encodes all content, so a hostile service principal name cannot execute
  in the reader's browser, but it is still disclosed as text

## Related

- [No events collected](../Common/No-Events-Collected.md)
- [Event volume](../Performance/Event-Volume.md)

## Event Log Readers is NOT enough for the domain baseline

This guide covers `Get-KrbEvent`, and for that function Event Log Readers genuinely is
sufficient. It is not sufficient for the module as a whole, and an earlier revision of the
README said otherwise.

`Get-KrbDomainEtypeContext` reads `DefaultDomainSupportedEncTypes` out of each controller's
registry over PowerShell remoting. Event Log Readers grants **neither** WinRM access **nor**
registry read. Under that group alone the function still succeeds — it is built to degrade
rather than fail — but every controller comes back:

```text
RegistryReachable       : False
RegistryError           : ...Access is denied / WinRM cannot process the request...
AgreesWithDomainDefault :            <- null, meaning unknown
DomainDefaultSource     : WindowsDefault
```

That last line is the one that matters. The baseline was **assumed**, not measured, and every
finding about an account whose `msDS-SupportedEncryptionTypes` is unset — most of a real
domain — rests on that assumption.

Verified in a two-controller lab: the same collection run under an S4U session with no ticket
reported both controllers unreachable, and run under an account in Administrators read both
registries first time.

### What to do

Either supply an administrative credential for the baseline only:

```powershell
$context = Get-KrbDomainEtypeContext -Credential (Get-Credential)
Get-KrbEvent | Get-KrbEtypeRisk -DomainContext $context     # collection stays low-privilege
```

Or accept the documented default and confirm the output says so:

```powershell
(Get-KrbDomainEtypeContext -SkipRegistry).DomainDefaultSource   # WindowsDefault
```

Never assume it was measured. Check `DomainDefaultSource`.

## Remote Event Log Management must also be enabled

Rights are not the only gate. `Get-WinEvent -ComputerName` uses Event Log RPC, whose firewall
rules are off by default on a fresh install — see
[No events collected](../Common/No-Events-Collected.md), section 5. An account with perfect
rights still reads nothing through a closed firewall.
