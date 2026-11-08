# Identity Resolution - Troubleshooting Guide

## Overview

This guide covers `Private\SID\Resolve-SIDIdentity.ps1`, the module that turns each access rule's
`IdentityReference` into a SID string, validates it, and decides whether it is orphaned. The
functions involved are:

| Function | Role |
|---|---|
| `Test-AccessRuleForOrphanedSID` | Entry point per access rule; returns an `OrphanedSIDResult` or `$null` |
| `Resolve-IdentityReference` | Routes `SecurityIdentifier`, `NTAccount` and other identity types to a SID string |
| `Convert-NTAccountToSID` | Translates an `NTAccount`; a failed translation returns the marker `ORPHANED_ACCOUNT:<name>` |
| `Get-StringFromIdentityReference` | Extracts a string from other identity types: `Value` property, then `ToString()`, then `[string]` cast |
| `Test-SIDValidityAndType` | `Test-SIDFormat` followed by `Test-WellKnownSID`; well-known SIDs are excluded |

Downstream, `Test-OrphanedSID` (in `Test-OrphanedSID.ps1`) performs the directory lookups and
`Get-SIDAnalysis` categorises the SID for the result object.

All of these are private functions; see [Loading the functions in a session](#loading-the-functions-in-a-session).

## Common Issues and Solutions

### 1. NTAccount references that fail to translate

#### Symptom

- `-LogLevel Information` log lines of the form
  `ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount 'DOMAIN\name' to SID - likely orphaned: Some or all identity references could not be translated.`
- The account does not appear in the results CSV.

#### Why

`Get-Acl` on the `AD:` drive normally returns `IdentityReference` as `SecurityIdentifier` for
unresolvable principals, so NTAccount translation failures are rare. When one does occur,
`Convert-NTAccountToSID` returns the string `ORPHANED_ACCOUNT:<name>`. That string then fails
`Test-SIDFormat` inside `Test-SIDValidityAndType`, so `Test-AccessRuleForOrphanedSID` logs
`SID validation failed or well-known SID detected` at Debug level and returns `$null`. The entry is
logged but not reported as an orphaned SID.

#### Resolution

Search the log for the Information line above to find the affected objects and account names:

```powershell
$log = Get-ChildItem .\Logs\Find-UnknownSID_*.log | Sort-Object LastWriteTime | Select-Object -Last 1
Select-String -Path $log.FullName -Pattern 'ORPHANED ACCOUNT DETECTED'
```

Verify the translation manually:

```powershell
function Test-NTAccountTranslation {
    param(
        [Parameter(Mandatory)][string]$AccountName,
        [string]$DomainName = $env:USERDOMAIN
    )
    try {
        $ntAccount = [System.Security.Principal.NTAccount]::new($DomainName, $AccountName)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        "SUCCESS: $DomainName\$AccountName -> $($sid.Value)"
        $true
    } catch {
        Write-Warning "FAILED: $DomainName\$AccountName - $($_.Exception.Message)"
        $false
    }
}
```

A failure for a name that should resolve points at trust or connectivity problems rather than at
an orphan:

```powershell
function Test-DomainConnectivity {
    param([Parameter(Mandatory)][string]$DomainName)
    try {
        $context = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new('Domain', $DomainName)
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($context)
        "Domain $DomainName is accessible; trusts: $($domain.GetAllTrustRelationships().Count)"
        $true
    } catch {
        Write-Error "Domain connectivity failed: $($_.Exception.Message)"
        $false
    }
}
```

### 2. SecurityIdentifier objects with no value

#### Symptom

Debug log lines `SecurityIdentifier object has null Value property for <DN>` and the rule is
skipped.

#### Why

`Resolve-IdentityReference` returns `$null` when a `SecurityIdentifier` has an empty `Value`. This
indicates a damaged ACE rather than an orphan.

#### Resolution

Read the raw ACL and look for the entry:

```powershell
$acl = Get-Acl -Path "AD:\CN=Example,OU=Users,DC=contoso,DC=com"
$acl.Access | Where-Object { [string]::IsNullOrWhiteSpace($_.IdentityReference.Value) }
```

If an entry has no identity, repair the ACL outside this script; `Find-UnknownSID.ps1` never
removes an ACE it could not resolve.

### 3. Identity references of other types

#### Symptom

Debug log lines `Extracted string is not a valid SID format: <text> (Type: <TypeName>) for <DN>`.

#### Why

For identity references that are neither `SecurityIdentifier` nor `NTAccount`,
`Get-StringFromIdentityReference` tries the `Value` property, then `ToString()`, then a `[string]`
cast, and the result must pass `Test-SIDFormat` (`^S-1-\d+-\d+` and a successful
`SecurityIdentifier` construction). Anything else is skipped.

#### Resolution

Check what type the AD provider is returning for the object:

```powershell
$acl = Get-Acl -Path "AD:\CN=Example,OU=Users,DC=contoso,DC=com"
$acl.Access | Group-Object { $_.IdentityReference.GetType().FullName } | Select-Object Name, Count
```

Expected types are `System.Security.Principal.SecurityIdentifier` and
`System.Security.Principal.NTAccount`. Any other type indicates a wrapper the module does not
unwrap; report the type name and the object DN.

### 4. Valid-looking SIDs rejected or well-known SIDs reported

#### Symptom

- A SID you expect to see is absent: Debug line `Skipping well-known SID: <SID>`.
- A SID you expect to be excluded appears in results.

#### Why

`Test-SIDValidityAndType` excludes anything `Test-WellKnownSID` recognises: configuration
`WellKnownSIDPatterns`, configuration `ProtectedSIDs`, every `S-1-5-32-*` built-in, a fixed list of
universal and NT Authority SIDs, service-SID prefixes `S-1-5-80/90/96`, and domain RIDs 512, 518
and 519. Domain SIDs with other RIDs are not well-known and go on to `Test-OrphanedSID`.

#### Resolution

```powershell
Test-SIDFormat -SID 'S-1-5-21-1234567890-1234567890-1234567890-1001'   # True
Test-WellKnownSID -SID 'S-1-5-21-1234567890-1234567890-1234567890-512' # True (Domain Admins)
Test-WellKnownSID -SID 'S-1-5-21-1234567890-1234567890-1234567890-1001' # False
```

To exclude additional SIDs, add patterns or exact SIDs through `-ConfigPath`; see
[Security-Validation-Guide.md](./Security-Validation-Guide.md#customising-the-lists).

## Debugging Techniques

### Loading the functions in a session

The module depends on the logging system, the result class and the sibling SID modules:

```powershell
Set-Location "<path to Find-UnknownSID>"
. .\Private\Core\Import-LoggingSystem.ps1
. .\Classes\OrphanedSIDResult.ps1
. .\Classes\SIDAnalysisResult.ps1
. .\Private\SID\Test-SIDFormat.ps1
. .\Private\ActiveDirectory\Invoke-ADOperationWithRetry.ps1
. .\Private\Operations\Invoke-OperationWithRetry.ps1
. .\Private\SID\Test-OrphanedSID.ps1
. .\Private\SID\Get-SIDAnalysis.ps1
. .\Private\SID\New-SIDResult.ps1
. .\Private\SID\Resolve-SIDIdentity.ps1
Initialize-LoggingSystem -LogLevel Debug
```

### Trace one access rule

```powershell
$dn = "CN=Example,OU=Users,DC=contoso,DC=com"
$acl = Get-Acl -Path "AD:\$dn"
$rule = $acl.Access | Select-Object -First 1
$correlationId = [guid]::NewGuid().ToString()

Test-AccessRuleForOrphanedSID -AccessRule $rule -ObjectDN $dn -ObjectClass 'user' -CorrelationId $correlationId -Verbose
```

### Test the components separately

```powershell
$identity = $rule.IdentityReference
$identity.GetType().Name                                           # SecurityIdentifier or NTAccount
$sid = Resolve-IdentityReference -IdentityReference $identity -ObjectDN $dn
$sid
Test-SIDFormat -SID $sid
Test-WellKnownSID -SID $sid
Test-OrphanedSID -SID $sid -CorrelationId $correlationId
```

## Log Messages

All messages are written by `Write-StructuredLog`; Debug lines reach the file only with
`-LogLevel Debug`.

| Message | Level | Meaning |
|---|---|---|
| `Skipping access rule with missing or null IdentityReference for <DN>` | Debug | ACE has no identity; skipped |
| `Failed to resolve identity reference to SID for <DN>` | Debug | No SID string could be produced |
| `ORPHANED ACCOUNT DETECTED: Failed to translate NTAccount '<name>' ...` | Information | NTAccount translation failed; entry is not reported |
| `Invalid SID format: <SID>` | Debug | Failed `Test-SIDFormat` |
| `Skipping well-known SID: <SID>` | Debug | Excluded by `Test-WellKnownSID` |
| `ORPHANED SID DETECTED: <SID> on <DN>` | Verbose | Result object will be created |
| `SID <SID> is valid (found in AD)` | Debug | Not orphaned |
| `Unable to extract string value from identity reference for <DN> : ...` | Debug | All three extraction methods failed |
| `Error testing access rule for orphaned SID on <DN> : ...` | Warning | Unexpected exception; rule skipped |

## Related Documentation

- [Orphaned SID Issues](./Orphaned-SID-Issues.md)
- [SID Format Issues](./SID-Format-Issues.md)
- [SID Analysis Issues](./SID-Analysis-Issues.md)
- [Security Descriptor Issues](./Security-Descriptor-Issues.md)
- [Security Validation Guide](./Security-Validation-Guide.md)
