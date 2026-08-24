# No events collected

The module returned nothing, or warned that a source matched no events.

This is the most dangerous failure mode in the whole tool, because an empty collection looks
exactly like a clean domain. An assessment built on it will describe a domain with no RC4 in
it - not because there is none, but because nothing was measured. Every warning the module
emits about an empty result exists to make that distinction impossible to miss.

## 0. Success is enabled but Failure is not

The variant that fools people, because the collection is not empty — it is *selectively*
empty, and only of the events that would have shown a problem.

Both Kerberos subcategories can be set to `Success` without `Failure`. In that state the KDC
logs no 4771 at all and no failed 4769, so a post-change verification returns nothing and
reads as "the change broke nothing". Nothing capable of recording breakage was ever switched
on.

```powershell
auditpol /get /subcategory:"Kerberos Authentication Service"
auditpol /get /subcategory:"Kerberos Service Ticket Operations"
```

Both must report **`Success and Failure`**. If either says only `Success`:

```powershell
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```

`Get-KrbEvent` infers this and warns when a collection returns a substantial number of events
and not one failure, including zero 4771s. That is a heuristic, not proof — confirm with
`auditpol` before trusting a clean post-change result.

This was found by running the module against a domain in exactly that state: a service ticket
request that the KDC rejected with `KDC_ERR_ETYPE_NOTSUPP` produced **no event whatsoever**
until Failure auditing was enabled.

## 1. Kerberos auditing is not enabled

By far the most common cause. The two subcategories are not on by default in every
configuration, and a domain can run for years without them.

```powershell
auditpol /get /subcategory:"Kerberos Authentication Service"
auditpol /get /subcategory:"Kerberos Service Ticket Operations"
```

Both should report `Success and Failure`. To enable them:

```powershell
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```

Set this through Group Policy on the Domain Controllers OU rather than locally, or the next
policy refresh reverts it. Then wait - the collection window has to contain events that were
logged *after* auditing was turned on, so a 30-day assessment started today measures nothing
useful until tomorrow.

## 2. The window is outside the log retention

A busy controller can roll the Security log in hours. If the log holds four hours and the
default window is 30 days, the query is mostly reaching for records that no longer exist.

```powershell
Get-WinEvent -ListLog Security | Select-Object MaximumSizeInBytes, FileSize, RecordCount

# The oldest record actually present
(Get-WinEvent -LogName Security -MaxEvents 1 -Oldest).TimeCreated
```

Either raise the log size, or narrow the window and collect more often. See
[Event volume](../Performance/Event-Volume.md) for the archiving pattern.

## 3. Reading the wrong machine

`Get-KrbEvent` with no `-ComputerName` discovers every controller in the current domain. On a
member server with RSAT it will find them; on a workstation without it, discovery fails and the
error names the fix.

Kerberos audit events are written by the KDC, so they exist **only on domain controllers**.
Pointing the module at a member server returns nothing and is not a fault.

## 4. Access denied rather than empty

An access failure is reported as a non-terminating error naming the controller, not as an empty
result. If you filtered errors away you will see the empty-collection warning instead. Re-run
without `-ErrorAction SilentlyContinue`, and see
[Event log permissions](../Security/Event-Log-Permissions.md).

## Confirming the module is not at fault

```powershell
# Bypass the module entirely
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4769 } -MaxEvents 5
```

If that returns nothing, the problem is auditing or retention. If it returns events but
`Get-KrbEvent` does not, open an issue with the output of:

```powershell
Get-KrbEvent -MaxEvents 5 -Verbose
```

## 5. "The RPC server is unavailable" — almost always the firewall

A domain controller that is reachable on every port you would think to test, replicating
cleanly, and answering WinRM perfectly can still return this for every event log call:

```text
Failed to read Kerberos events from DC02: The RPC server is unavailable.
```

`Get-WinEvent -ComputerName` does not use WinRM. It uses the legacy Event Log RPC protocol,
which needs TCP 135 **and** the dynamic RPC range (49152-65535). The firewall rules that open
that range — the **Remote Event Log Management** group — are **disabled by default** on a
fresh Windows install.

Measured on a freshly promoted Server 2025 controller: DNS resolved, ICMP answered, TCP 135,
445, 5985, 389 and 88 were all open, `Invoke-Command` worked with zero clock skew, and the
Security log held 6,703 records — while every single `Get-WinEvent -ComputerName` call against
it failed, including `-ListLog`. All three firewall rules were off.

Check:

```powershell
Invoke-Command -ComputerName DC02 {
    Get-NetFirewallRule -DisplayGroup 'Remote Event Log Management' |
        Select-Object DisplayName, Enabled
}
```

Fix:

```powershell
Invoke-Command -ComputerName DC02 {
    Enable-NetFirewallRule -DisplayGroup 'Remote Event Log Management'
}
```

Or avoid the RPC path entirely by archiving to `.evtx` on the controller and reading the file
— see [Event volume](../Performance/Event-Volume.md).

**Why this one is dangerous.** It surfaces as a non-terminating error, so a pipeline written
with `-ErrorAction SilentlyContinue` — which is common — drops the controller silently and
reports a confident assessment built over a fraction of the estate. `Get-KrbEvent` names the
likely cause in the error text for exactly that reason, but nothing can rescue an error that
was suppressed. Count your sources:

```powershell
$events = Get-KrbEvent -MaxEvents 5000
$events.Source | Sort-Object -Unique          # must list every controller you expect
```

## Related

- [Event volume](../Performance/Event-Volume.md)
- [Event log permissions](../Security/Event-Log-Permissions.md)
- [Event schema versions](Event-Schema-Versions.md)
