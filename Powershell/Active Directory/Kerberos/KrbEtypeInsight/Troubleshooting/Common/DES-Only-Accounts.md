# DES-only accounts

Finding `KRB004` (`USE_DES_KEY_ONLY` set) or `KRB007` (DES observed or configured).

## Two different ways to be DES-only

**`USE_DES_KEY_ONLY` in `userAccountControl` (0x200000).** This bit overrides
`msDS-SupportedEncryptionTypes` **entirely**. The attribute can say RC4 and AES and the KDC will
ignore it. An assessment that reads only the encryption type attribute reports these accounts as
healthy - which is precisely why the module decodes `userAccountControl` as well.

**`msDS-SupportedEncryptionTypes` set to 1, 2 or 3.** Bits `0x1` and `0x2` are DES-CBC-CRC and
DES-CBC-MD5. A value of 3 is both and nothing else.

## Why they are usually already broken

Windows Server 2008 R2 and later refuse DES by default. An account in either state is therefore
either failing already, or being kept alive by an explicit domain-wide DES allowance - which any
hardening will remove.

If it is failing already, you will see it:

```powershell
Get-KrbEvent -IncludeFailureOnly | Where-Object StatusIsEtypeRelated |
    Group-Object ClientAccount, StatusName
```

## Finding them

```powershell
# Configured for DES
Get-KrbPrincipalEtype -All | Where-Object {
    $_.EncryptionTypes.SupportsDes -and -not $_.EncryptionTypes.SupportsAes
}

# Pinned by userAccountControl
Get-KrbPrincipalEtype -All | Where-Object { $_.AccountControl.UseDesKeyOnly }
```

Both appear in a risk assessment even when the account produced no events at all - a quarterly
batch job generates nothing in a 30-day window and still blocks the change:

```powershell
Get-KrbEvent | Get-KrbEtypeRisk | Where-Object { $_.FindingCodes -contains 'KRB007' }
```

## Fixing them

Clearing the bit is **not sufficient on its own**. The account has no non-DES key material,
because none was ever derived - so it needs both changes:

```powershell
# 1. Understand what uses the account first. lastLogonTimestamp is a floor, not a truth -
#    it replicates lazily and lags by up to 14 days.
Get-KrbPrincipalEtype -Identity 'svc-ancient' |
    Select-Object SamAccountName, Description, LastLogonTimestamp, PasswordAgeDays,
                  @{ n = 'DesOnly'; e = { $_.AccountControl.UseDesKeyOnly } }

# 2. Clear USE_DES_KEY_ONLY
$uac = (Get-ADUser -Identity 'svc-ancient' -Properties userAccountControl).userAccountControl
Set-ADUser -Identity 'svc-ancient' -Replace @{ userAccountControl = ($uac -band -bnot 0x200000) }

# 3. Widen the encryption type attribute
Set-ADUser -Identity 'svc-ancient' -Replace @{ 'msDS-SupportedEncryptionTypes' = 0x1C }

# 4. Reset the password - this is what actually creates the AES keys
```

Step 4 is the one that gets skipped, and skipping it leaves the account with no usable key at
all. See [missing AES keys](Missing-AES-Keys.md).

## A domain-wide variant

If DES is working anywhere in the domain, something is permitting it - either
`DefaultDomainSupportedEncTypes` carries `0x3`, or the "Network security: Configure encryption
types allowed for Kerberos" policy does. Both are worth finding before they are removed by
accident.

```powershell
(Get-KrbDomainEtypeContext).DomainDefaultDecoded | Select-Object EffectiveHex, CipherNames, SupportsDes
```

## Related

- [Missing AES keys](Missing-AES-Keys.md)
- [Controller policy drift](Controller-Policy-Drift.md)
