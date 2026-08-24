# Finding code reference

Every conclusion the risk engine reaches is a structured finding with a stable code, a severity,
the evidence that produced it, and - where there is one - a recommended action.

The codes are stable so that an organisation running this quarterly can say "KRB002 is down from
40 accounts to 3". Wording may improve; codes do not change.

## Severity means specifically

| Severity | Meaning | Weight |
|---|---|---|
| Critical | Hardening will break this, and there is direct evidence | 40 |
| High | Hardening will probably break this, or it is already broken | 20 |
| Medium | A real weakness that hardening does not itself break | 10 |
| Low | Worth knowing, no action required before the change | 4 |
| Info | Context, including confirmation that something is already safe | 0 |

## The codes

### KRB001 - Every observed ticket used a removed encryption type (Critical)

All service ticket requests in the window were issued under encryption types the target
configuration removes. The service has no demonstrated ability to operate under the proposed
configuration.

**Action:** verify AES key material exists, move to RC4+AES (`0x1C`) first, confirm AES tickets
appear, then remove RC4.

### KRB002 - Principal holds no AES key material (Critical)

The KDC reported the principal's available keys, and no AES key is present. Applying an AES-only
configuration gives the KDC nothing to encrypt with and authentication fails with
`KDC_ERR_NULL_KEY`.

The most important finding in the module, and invisible to any configuration-only assessment.

**Action:** reset the password to derive AES keys, confirm AES appears in `AvailableKeys` on
subsequent events, and only then change the attribute. See [missing AES keys](Missing-AES-Keys.md).

### KRB003 - Attribute explicitly excludes AES (High)

`msDS-SupportedEncryptionTypes` is set to a value somebody chose deliberately that omits AES.
Whatever compatibility reason produced it needs to be understood before it is reversed.

### KRB004 - USE_DES_KEY_ONLY is set (Critical)

The bit confines the account to single DES and overrides the encryption type attribute entirely.
See [DES-only accounts](DES-Only-Accounts.md).

### KRB005 - Clients advertise no AES support (Critical)

**The finding the module exists to produce.** Named client accounts were observed requesting
tickets, and their own TGT requests advertised no AES encryption type at all. They are not merely
receiving RC4 - they are incapable of anything else.

The claim requires that **every** advertised name was recognised. A client offering an algorithm
this module has never heard of is reported as unknown, not as legacy - see
[unknown encryption types](Unknown-Encryption-Types.md). Unknown is not the same as incapable,
and treating it as such would raise a Critical against the most modern clients in the estate.

Raised against the *service*, where the owner will see it, with the client list in the evidence.

**Action:** patch or replace the listed clients. If any is an appliance or third-party product,
its vendor needs a support statement, and that is usually the longest lead time in the project.

### KRB006 - No AES ticket observed, key material unconfirmable (High)

No AES ticket in the window, and the controllers emit an event schema too old to report which
keys exist. The account may hold AES keys and never have negotiated them, or hold none.

Deliberately rated below `KRB002` because it is an inference, not an observation.

**Action:** update the controllers for version 2 events, or reset the password to guarantee AES
keys exist.

### KRB007 - Single DES observed or configured (Critical)

DES has been cryptographically broken for two decades and refused by default since Windows
Server 2008 R2. Treat as an immediate security finding independent of the RC4 project.

### KRB008 - Pre-authentication only ever used a removed type (High)

Pre-authentication is the first cryptographic step of a logon, so this account fails before it
obtains a TGT rather than at some later service.

### KRB009 - No impact predicted (Info)

All observed requests used surviving encryption types and no configuration override was found -
on adequate evidence. Contrast with `KRB015`.

### KRB010 - Mix of surviving and removed types (Medium)

Tickets were issued under both. The service can clearly do AES, but something in its client
population or negotiation is still selecting the weaker type.

### KRB011 - Encryption-type failures are already occurring (Critical)

Not a prediction. Events already carry `KDC_ERR_ETYPE_NOTSUPP`, `KDC_ERR_NULL_KEY` or a related
code, most likely absorbed by client retries or a fallback path. Hardening removes the fallback.

**Action:** investigate before making any further change. See [KDC status codes](KDC-Status-Codes.md).

### KRB012 - Explicitly non-AES, no traffic in the window (Medium)

The attribute deliberately excludes AES and no authentication was observed. There is no evidence
either way - which is a different statement from evidence that it is safe.

**Action:** extend the window, or check `lastLogonTimestamp` and the owning application's
schedule, before assuming the account is dormant.

### KRB013 - Delegation enabled (Medium)

An encryption type failure here does not stop at this service; it propagates to every backend the
service reaches on a user's behalf. Its true impact is larger than its client count suggests.

### KRB014 - Trust does not permit AES (High)

Every cross-realm ticket over the trust is pinned to RC4 regardless of what the accounts on
either side support. See [trust encryption types](Trust-Encryption-Types.md).

### KRB015 - Insufficient evidence to assess (Low)

The principal was seen, but only through the pre-KB5021131 schema, and could not be matched to a
directory object. Nothing was found wrong with it - and nothing would have been found wrong had
it been broken.

The distinction from `KRB009` is the point. Reporting this as "no impact predicted" gives false
assurance about exactly the principals the assessment understood least.

## Working with findings

```powershell
$risks = Get-KrbEvent | Get-KrbEtypeRisk

# Everything the change will actually break
$risks | Where-Object WillBreakOnHardening

# Count by code, for tracking across quarters
$risks.Findings | Group-Object Code | Sort-Object Count -Descending

# The full evidence behind one finding
($risks | Where-Object PrincipalName -eq 'svc-payroll').Findings |
    Where-Object Code -eq 'KRB005' | Select-Object -ExpandProperty Evidence
```

## Related

- [Risk scoring](Risk-Scoring.md)
- [Event schema versions](Event-Schema-Versions.md)
