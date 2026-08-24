# Directory query performance

## Enumerate once, index in memory

`Get-KrbPrincipalEtype -ServicePrincipalName` issues one directory query per name. Resolving
several thousand service principal names that way is the slowest thing this module can be asked
to do.

`Get-KrbEtypeRisk` does not do that. It enumerates every principal once and builds two in-memory
lookup tables - by account name and by SPN - then resolves locally. If you are writing your own
correlation, do the same:

```powershell
$principals = Get-KrbPrincipalEtype -All

$bySpn = @{}
foreach ($p in $principals) {
    foreach ($spn in $p.ServicePrincipalNames) { $bySpn[$spn] = $p }
}
```

## Named properties, never a wildcard

`-Properties *` pulls constructed and back-linked attributes - `memberOf` and `tokenGroups`
among them - which cost the directory real work for data nothing reads. The module names the
eleven attributes it needs.

One of them is easy to omit and expensive to get wrong: **`sAMAccountName` is not one of
`Get-ADObject`'s default properties.** The defaults are `DistinguishedName`, `Name`,
`ObjectClass` and `ObjectGUID` only. Leave it out and every principal comes back with an empty
name, which then becomes an empty key in the correlation index - so the join between events and
directory configuration silently disappears, with no error and no missing rows.

## Filter server-side

Disabled accounts are excluded by an LDAP bit filter, not locally:

```text
(!(userAccountControl:1.2.840.113556.1.4.803:=2))
```

In a domain with years of tombstoned service accounts this is the difference between
transferring them all and discarding them, and never transferring them.

Likewise `-ServiceAccountOnly` adds `(servicePrincipalName=*)` to the filter rather than
filtering the pipeline.

## Scoping to what is actually in use

The directory holds accounts nothing has authenticated as in years. To assess only what is live:

```powershell
Get-KrbEvent -EventId 4769 -MaxEvents 20000 |
    Select-Object -ExpandProperty ServiceName -Unique |
    Get-KrbPrincipalEtype -ServicePrincipalName -ErrorAction SilentlyContinue
```

Bear in mind the trade-off: this deliberately misses the quarterly batch job that produces no
events in the window and still blocks hardening. `Get-KrbEtypeRisk` covers that separately by
reporting unobserved principals whose configuration is dangerous on its face - see `KRB012`.

## Targeting one controller

```powershell
Get-KrbPrincipalEtype -All -Server 'dc02.ad.contoso.net'
```

Useful for keeping assessment load off a controller carrying an FSMO role, or for reading from
the same replica the event data came from.

## Related

- [Event volume](Event-Volume.md)
- [SPN resolution](../Common/SPN-Resolution.md)
