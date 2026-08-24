# Accounts with no AES key material

Finding `KRB002` (Critical) or `KRB006` (High).

## The failure

Kerberos keys are derived from the password **when the password is set**. They are not computed
on demand. An account whose password has not changed since the domain supported AES has no AES
key, no matter what `msDS-SupportedEncryptionTypes` claims.

Setting such an account to AES-only does not harden it. The KDC has nothing to encrypt the
ticket with and returns `KDC_ERR_NULL_KEY` (0x9). Authentication stops immediately and
completely.

This is the single most common cause of a hardening rollback, and it is invisible to any
assessment that reads only the encryption type attribute - the attribute will say AES, and the
account will still fail.

## How the module detects it

Version 2 events report the account's actual key material:

```xml
<Data Name='ServiceAvailableKeys'>RC4</Data>
```

That is ground truth from the KDC. If the target configuration requires AES and the available
keys contain none, the module raises `KRB002` regardless of what the attribute says.

```powershell
Get-KrbEvent | Get-KrbEtypeRisk | Where-Object { $_.FindingCodes -contains 'KRB002' } |
    Select-Object PrincipalName, AvailableKeys, RequestCount
```

Where the controllers emit a legacy schema the available-key field does not exist, and the
module falls back to `KRB006`: no AES ticket was observed and key material cannot be confirmed.
That is an inference, rated lower deliberately, and it says so.

## The fix

**Reset the password.** That is the whole remediation - key derivation happens at password set,
so a reset creates the AES keys.

```powershell
# 1. Confirm the current state
Get-KrbPrincipalEtype -Identity 'svc-legacyapp' |
    Select-Object SamAccountName, PasswordLastSet, PasswordAgeDays,
                  @{ n = 'Configured'; e = { $_.EncryptionTypes.EffectiveHex } }

# 2. Reset the password - coordinate with the application owner first,
#    the service's stored credential has to change with it

# 3. Confirm AES keys now exist, from the next events the account generates
Get-KrbEvent -MaxEvents 500 |
    Where-Object ServiceName -eq 'svc-legacyapp' |
    Select-Object -First 1 -ExpandProperty ServiceAvailableKeys
```

Only once `AES-SHA1` appears in the available keys should the encryption type attribute be
narrowed.

## Accounts that do not have this problem

- **Computer accounts** rotate their password every 30 days by default, so their key material
  is current.
- **Group managed service accounts** are rotated by the KDC, likewise.
- **krbtgt**, if it has been rotated since the domain reached a 2008 functional level.

The problem concentrates in user-object service accounts with `PasswordNeverExpires` set, which
is also the population least likely to have an owner who remembers what they do.

## A domain-wide variant

If the domain functional level is below Windows Server 2008, **no account in the domain** has an
AES key, because the KDC never derived one. `Get-KrbDomainEtypeContext` reports this as
`SupportsAesKeyDerivation = $false`, and it outranks every per-account finding an assessment
could produce.

## Related

- [KDC status codes](KDC-Status-Codes.md)
- [Event schema versions](Event-Schema-Versions.md)
- [DES-only accounts](DES-Only-Accounts.md)
