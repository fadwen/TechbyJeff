# Identifying the clients behind a finding

`KRB005` names client accounts. Turning those into machines somebody can act on.

## What the module gives you

```powershell
$risk = Get-KrbEvent | Get-KrbEtypeRisk | Where-Object PrincipalName -eq 'svc-payroll'

$risk.Clients                     # every client account that requested tickets
$risk.ClientsWithoutAesSupport    # those that advertise no AES - the ones that break
$risk.ClientsWithUnknownSupport   # those with no TGT request in the window
$risk.ClientAddresses             # distinct source addresses
```

`ClientsWithoutAesSupport` is built by indexing what every client advertised in its own 4768
events, then looking up each client of the service. It is direct evidence of incapability, not
an inference from what the KDC happened to choose.

## Address normalisation

The KDC writes client addresses in whichever form the socket presented - `::ffff:10.20.30.40`
over a v6 socket, `10.20.30.40` over v4, `::1` for a request made on the controller itself. The
module unwraps IPv4-mapped IPv6 addresses so that one host counts once; left unnormalised, a
single legacy application server appears as two or three affected clients and every blast-radius
number is inflated.

The raw value is preserved on `IpAddressRaw` if you need it.

## From a client account to a machine

A client account ending in `$` is a computer account, and the name is the machine name:

```powershell
Get-ADComputer -Identity 'APPLIANCE-SCAN01' -Properties OperatingSystem, OperatingSystemVersion,
    LastLogonDate, Description, DNSHostName
```

The operating system tells you most of what you need. A pre-2008 Windows build, or an appliance
reporting a generic OS string, is a client that cannot do AES and will not learn.

For a user account, the addresses are the lead:

```powershell
$risk.ClientAddresses | ForEach-Object {
    [PSCustomObject]@{
        Address = $_
        Name    = try { [System.Net.Dns]::GetHostEntry($_).HostName } catch { 'no reverse record' }
    }
}
```

## Clients with unknown capability

`ClientsWithUnknownSupport` lists clients that requested a service ticket but had no TGT request
in the collection window - so nothing recorded what they advertise. They are not confirmed safe;
they are unmeasured.

Two ways to close the gap:

- Extend the window, so a full TGT lifecycle for each client falls inside it
- Collect 4768 explicitly, which some estates filter out for volume reasons

```powershell
Get-KrbEvent -EventId 4768 -StartTime (Get-Date).AddDays(-45)
```

## Non-Windows clients

Linux, macOS, Java and appliance Kerberos stacks all advertise their own etype lists, and they
show up in `ClientAdvertizedNames` exactly as sent. A Java client on an old JDK, or an appliance
with a bundled MIT Kerberos build, is a frequent source of `KRB005` - and the fix is a vendor
conversation rather than a directory change.

```powershell
Get-KrbEvent -EventId 4768 -MaxEvents 20000 |
    Where-Object ClientAdvertizedLegacyOnly |
    Group-Object ClientAccount |
    Select-Object Count, Name,
        @{ n = 'Advertised'; e = { ($_.Group[0].ClientAdvertizedNames) -join ', ' } }
```

## Related

- [Finding codes](Finding-Codes.md)
- [Event schema versions](Event-Schema-Versions.md)
