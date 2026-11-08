# Security Descriptor Retrieval - Troubleshooting Guide

## Overview

This guide covers `Private\Security\Get-SecurityDescriptor.ps1`, which reads the access rules of
each Active Directory object. `Get-ObjectAccessRule -ADObject <object>` tries three strategies in
order and returns the first non-empty result:

1. **Get-Acl**: `Get-SecurityDescriptorFromGetAcl` calls `Get-Acl -Path "AD:\<DN>"`.
2. **Binary descriptor**: `Get-SecurityDescriptorFromBinary` reads the object's
   `nTSecurityDescriptor` property. An `ActiveDirectorySecurity` instance is used directly; a byte
   array or Base64 string is converted by `ConvertTo-SecurityDescriptor` through
   `SetSecurityDescriptorBinaryForm`.
3. **Fresh query**: `Invoke-FreshADQuery` runs
   `Get-ADObject -Identity <DN> -Properties nTSecurityDescriptor` and processes the result the same
   way.

Without `-IncludeInherited`, every strategy filters out entries where `IsInherited` is true.
Objects are supplied by `Get-ADObjectFromSearchBase`, which always requests
`nTSecurityDescriptor`; `Find-OrphanedSIDsInObject` skips objects where that property is empty
before calling `Get-ObjectAccessRule`.

The functions are private. To call them in a session, dot-source
`Private\Core\Import-LoggingSystem.ps1` and `Private\Security\Get-SecurityDescriptor.ps1`, then
run `Initialize-LoggingSystem -LogLevel Debug`.

## Common Issues and Solutions

### 1. Get-Acl failures

#### Symptom

- Debug log line `Get-Acl failed for <DN>: Cannot find path 'AD:\<DN>' because it does not exist.`
- Processing continues through the binary and fresh-query strategies.

#### Root causes

- The `AD:` drive is not available: the ActiveDirectory module was not imported in this session,
  or the drive was removed.
- The account lacks `Read Permissions` on the object.
- The object was deleted or moved between discovery and ACL retrieval.
- The domain controller is unreachable.

#### Solutions

```powershell
# Verify the AD provider drive
if (-not (Get-PSDrive -Name AD -ErrorAction SilentlyContinue)) {
    Import-Module ActiveDirectory -Force
}

# Verify connectivity
try {
    Get-ADDomainController -ErrorAction Stop | Select-Object HostName, Site
} catch {
    Write-Error "AD connectivity issue: $($_.Exception.Message)"
}

# Verify the object still exists and read its ACL directly
$dn = "CN=Example,OU=Users,DC=contoso,DC=com"
Get-ADObject -Identity $dn -ErrorAction SilentlyContinue
(Get-Acl -Path "AD:\$dn").Access.Count
```

The main script imports the module itself; this failure mode mostly affects interactive use of the
private functions.

### 2. Binary descriptor conversion failures

#### Symptom

- Warning log line `Failed to convert binary security descriptor for <DN> : <exception>`.
- Debug line `Binary security descriptor processing failed for <DN>: <exception>`.

#### Root causes

- The `nTSecurityDescriptor` value is not an `ActiveDirectorySecurity`, byte array or Base64
  string, so the `[byte[]]` cast fails.
- Damaged descriptor data rejected by `SetSecurityDescriptorBinaryForm`.

#### Solutions

```powershell
$obj = Get-ADObject -Identity $dn -Properties nTSecurityDescriptor
$obj.nTSecurityDescriptor.GetType().FullName      # expected: System.DirectoryServices.ActiveDirectorySecurity

# Validate raw bytes if the property is binary
function Test-BinarySecurityDescriptor {
    param([Parameter(Mandatory)][object]$BinaryData)
    try {
        if ($BinaryData -is [byte[]] -and $BinaryData.Length -gt 0) {
            $sd = [System.DirectoryServices.ActiveDirectorySecurity]::new()
            $sd.SetSecurityDescriptorBinaryForm($BinaryData)
            return $true
        }
        return $false
    } catch {
        Write-Warning "Binary data validation failed: $($_.Exception.Message)"
        return $false
    }
}
```

When the Get-Acl strategy succeeds, the binary path is never reached, so this warning usually
appears together with a Get-Acl failure for the same object.

### 3. Objects with no security descriptor

#### Symptom

- Debug log line `No security descriptor found for <DN>` from `Find-OrphanedSIDsInObject`, or
  `No nTSecurityDescriptor property found for <DN>` from the binary strategy.
- The object is counted as processed but yields no results.

#### Root causes

- The account cannot read the descriptor, so the attribute comes back empty.
- Rare object classes that expose no `nTSecurityDescriptor` to the caller.

#### Solutions

```powershell
Get-ADObject -Identity $dn -Properties nTSecurityDescriptor |
    Select-Object DistinguishedName, ObjectClass, @{ Name = 'HasSD'; Expression = { $null -ne $_.nTSecurityDescriptor } }
```

Run as an account with read access to the security descriptor, or exclude the container from
`-SearchBase`.

### 4. Fresh query failures

#### Symptom

- Warning `Fresh AD query failed for <DN>: <exception>` or
  `Fresh AD query returned no security descriptor for <DN>`.
- Followed by Warning `All security descriptor retrieval methods failed for <DN>`.

#### Root causes

- Insufficient permissions.
- Domain controller timeout on an object with a very large ACL.
- The object disappeared mid-run.

#### Solutions

The fresh query inside `Get-ObjectAccessRule` is a single attempt without retry. Test it by hand
with a specific server and a retry loop:

```powershell
function Get-ADObjectWithRetry {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [int]$MaxRetries = 3,
        [int]$BaseDelayMs = 1000,
        [string]$Server = (Get-ADDomain).PDCEmulator
    )
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            return Get-ADObject -Identity $Identity -Properties nTSecurityDescriptor -Server $Server -ErrorAction Stop
        } catch {
            if ($i -eq $MaxRetries - 1) { throw }
            $delay = $BaseDelayMs * [Math]::Pow(2, $i)
            Write-Verbose "Retry $($i + 1) after $delay ms"
            Start-Sleep -Milliseconds $delay
        }
    }
}
```

If the fresh query succeeds here but fails in the run, the cause is load during the run; re-run
the affected search base alone.

## Performance Notes

- Each object costs one `Get-Acl` call in the normal case. The binary and fresh-query strategies
  add work only when Get-Acl returns nothing.
- `-IncludeInherited` increases the number of rules returned per object, often several-fold on
  deep OU trees, and each extra rule is a SID lookup downstream.
- `ConvertTo-SecurityDescriptor` and `Invoke-FreshADQuery` null their `ActiveDirectorySecurity`
  reference after extracting the rules; `Find-OrphanedSIDsInObject` nulls the rule array after each
  object and collects every 100 rules.

```powershell
# Measure ACL retrieval for a sample of objects
$objects = Get-ADObject -SearchBase "OU=Users,DC=contoso,DC=com" -Filter * -Properties nTSecurityDescriptor -ResultSetSize 100
(Measure-Command { $objects | ForEach-Object { Get-ObjectAccessRule -ADObject $_ } }).TotalSeconds
```

## Debugging Techniques

### Trace one object

```powershell
$obj = Get-ADObject -Identity $dn -Properties nTSecurityDescriptor
$correlationId = [guid]::NewGuid().ToString()
$rules = Get-ObjectAccessRule -ADObject $obj -CorrelationId $correlationId -Verbose
$rules.Count
$rules | Select-Object IdentityReference, ActiveDirectoryRights, IsInherited -First 10
```

### Test each strategy

```powershell
Get-SecurityDescriptorFromGetAcl -ADObject $obj
Get-SecurityDescriptorFromBinary -ADObject $obj
Invoke-FreshADQuery -ADObject $obj
```

Each returns the rule array or `$null`; compare the counts to see which strategy the run would
have used.

## Log Messages

| Message | Level | Meaning |
|---|---|---|
| `Get-Acl failed for <DN>: <error>` | Debug | Strategy 1 failed; falling back |
| `Get-Acl returned null or empty access list for <DN>` | Debug | Object has no explicit ACEs, or no ACL readable |
| `No nTSecurityDescriptor property found for <DN>` | Debug | Strategy 2 has nothing to parse |
| `Failed to convert binary security descriptor for <DN> : <error>` | Warning | Strategy 2 conversion failed |
| `Fresh AD query returned no security descriptor for <DN>` | Warning | Strategy 3 found the object but no descriptor |
| `Fresh AD query failed for <DN>: <error>` | Warning | Strategy 3 query failed |
| `All security descriptor retrieval methods failed for <DN>` | Warning | Object skipped |
| `Successfully retrieved access rules using <method> for <DN>` | Debug | Which strategy succeeded |

Debug lines reach the log file only with `-LogLevel Debug`.

## Related Documentation

- [Identity Resolution Issues](./Identity-Resolution-Issues.md)
- [Orphaned SID Issues](./Orphaned-SID-Issues.md)
- [Security Descriptor Warnings](../Common/Security-Descriptor-Warnings.md)
- [SID Processing Orchestration Issues](../Common/SID-Processing-Orchestration-Issues.md)
- [Performance Tuning](../Performance/Performance-Tuning.md)
