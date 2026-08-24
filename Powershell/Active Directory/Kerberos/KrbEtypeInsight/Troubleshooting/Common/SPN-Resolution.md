# Service principal name resolution

A finding names a service by its raw SPN rather than by an account, or
`Get-KrbPrincipalEtype -ServicePrincipalName` reports that no account owns it.

## Why a name in the log may not resolve

The `ServiceName` field of a 4769 event is whatever the client asked for. Several things follow:

**It may be a bare account name, not a full SPN.** The KDC writes `svc-payroll` when the request
named the account directly, and `MSSQLSvc/db01.contoso.net:1433` when it named an SPN. The module
tries both lookups before giving up.

**The owning account may have been deleted.** An SPN in the log with no owner in the directory
usually means exactly that, or that the SPN was moved to another account after the event was
written. Both are worth knowing.

**It may be from another realm.** A cross-realm service ticket names a principal that does not
exist in this domain at all. See [trust encryption types](Trust-Encryption-Types.md).

**It may be hostile.** A service principal name is chosen by whoever makes the request, so it is
attacker-influenceable by construction. The module escapes every value per RFC 4515 before
interpolating it into an LDAP filter - unescaped, a crafted name either widens the search or,
worse because it is silent, narrows it to nothing so that a risky principal is quietly absent
from the report.

## Duplicate SPNs

If a name is registered on more than one account the module warns, because the KDC returns
`KDC_ERR_PRINCIPAL_NOT_UNIQUE` and the service fails for everyone - independently of any
encryption type change. An assessment is a good moment to find this.

```powershell
setspn -X
```

## Unresolved names in a risk report

The correlation engine keys on the account name when it can resolve one, and on the raw service
name when it cannot. An unresolved entry still carries all its event evidence - request counts,
observed encryption types, client lists - and is worth acting on; it simply has no directory
configuration attached, and `ResolvedInDirectory` is `$false`.

```powershell
Get-KrbEvent | Get-KrbEtypeRisk | Where-Object { -not $_.ResolvedInDirectory }
```

## Resolving by hand

```powershell
# By SPN
Get-KrbPrincipalEtype -ServicePrincipalName 'MSSQLSvc/db01.contoso.net:1433'

# Directly, to see what the directory holds
Get-ADObject -LDAPFilter '(servicePrincipalName=MSSQLSvc/db01.contoso.net:1433)' `
    -Properties servicePrincipalName, msDS-SupportedEncryptionTypes
```

For bulk work prefer `-All` and index locally - see
[directory query performance](../Performance/Directory-Queries.md).

## Related

- [Directory query performance](../Performance/Directory-Queries.md)
- [Trust encryption types](Trust-Encryption-Types.md)
