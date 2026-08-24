# Domain controllers disagree on the encryption type default

`Get-KrbDomainEtypeContext` warned that controllers do not agree on
`DefaultDomainSupportedEncTypes`, or `ControllersDisagreeOnDefault` is `$true`.

## Why this matters more than it looks

`DefaultDomainSupportedEncTypes` is a **registry value on each controller**, not a replicated
directory attribute. Nothing keeps them in step.

It is the value the KDC falls back to whenever `msDS-SupportedEncryptionTypes` is unset or zero
- which, in a typical domain, is the great majority of accounts. So when controllers disagree,
those accounts authenticate differently depending on which controller a client happens to reach.

That produces the worst class of fault: intermittent failures that cannot be reproduced on
demand. The same user, the same application, the same workstation - working, then not, then
working again, according to which controller the DC locator picked. Investigations of this
routinely go on for weeks and end up blaming the network.

## Finding the outliers

```powershell
$context = Get-KrbDomainEtypeContext

$context.DomainControllers |
    Select-Object Name, Site, RegistryReachable, DefaultDomainSupportedEncTypes,
                  AgreesWithDomainDefault |
    Sort-Object AgreesWithDomainDefault, Name
```

`AgreesWithDomainDefault = $false` marks the controllers to look at. Note the `Site` column -
drift usually follows a site, because it usually followed a build image or a local policy.

The module resolves the effective domain default by majority, and says which:

```powershell
$context.DomainDefaultEncryptionTypes    # the value in force for most controllers
$context.DomainDefaultSource             # 'Registry' or 'WindowsDefault'
```

Picking the first controller's value instead would make the entire assessment depend on which
controller answered first.

## Reading the value directly

```powershell
Invoke-Command -ComputerName dc01, dc02, dc03 {
    $v = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc' `
        -Name 'DefaultDomainSupportedEncTypes' -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        Value    = if ($v) { '0x{0:X}' -f $v.DefaultDomainSupportedEncTypes } else { 'not set (0x27 applies)' }
    }
}
```

The value lives **directly under the KDC service key**, not under a `Parameters` subkey.
Reading the wrong path returns null, which is indistinguishable from "not configured" - and
"not configured" is the answer that makes an assessment assume `0x27`.

## Fixing it

Set the value identically on every controller, through Group Policy on the Domain Controllers
OU rather than by hand, or the next build reintroduces the drift.

`DefaultDomainSupportedEncTypes` has no default entry - if it has never been written, the KDC
uses `0x27`, which is DES + RC4 + the AES256 session-key bit. Accounts inheriting it are
therefore **not** the RC4-only accounts a naive reading suggests, and they are also not AES-ready.

A reasonable staged target:

| Stage | Value | Meaning |
|---|---|---|
| Current default | `0x27` | DES, RC4, AES256 session key |
| Add AES | `0x1F` | DES, RC4, AES128, AES256 |
| Remove DES | `0x1C` | RC4, AES128, AES256 |
| Remove RC4 | `0x18` | AES128, AES256 |

Model each stage before scheduling it:

```powershell
Get-KrbEvent | Get-KrbEtypeRisk -TargetEncryptionTypes 0x1C | Where-Object WillBreakOnHardening
```

The KDC service must be restarted, or the controller rebooted, for a change to take effect.

## When the registry cannot be read

Controllers with `RegistryReachable = $false` contribute nothing to the baseline, and the module
says so on the object rather than assuming they agree. See
[Remote registry access](../Integration/Remote-Registry-Access.md).

## Related

- [The two numbering systems](Etype-Numbering-Systems.md)
- [Remote registry access](../Integration/Remote-Registry-Access.md)
