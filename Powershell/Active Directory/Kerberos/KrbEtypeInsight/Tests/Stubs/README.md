# Test stubs

## Overview & Purpose

A stand-in for RSAT, so the `Tests/Unit` suites run on a host that does not have it.

The suites never touch a directory - every AD call is mocked, 129 of them at last count.
What blocks them on a workstation is narrower than it looks: **Pester cannot mock a command
that does not exist**. `Mock -ModuleName KrbEtypeInsight Get-ADDomain` throws
`CommandNotFoundException` where RSAT is absent, and a throw inside `BeforeAll` takes the
whole `Describe` block with it. Without this stub, 91 of the 402 unit tests fail on a
workstation and none of them are testing Active Directory.

`Add-KrbTestStubPath.ps1` **appends** this directory to `PSModulePath`. Appending rather
than prepending is deliberate: a domain controller with real RSAT keeps using it and the
suite exercises the true binding surface, while a workstation falls back to the stub.

The stub does not weaken the suites. Every command a test relies on is still mocked; the
stub only makes the command exist so the mock can be attached.

## Scope

Six cmdlets, exactly the ones the suites mock:

`Get-ADDomain`, `Get-ADDomainController`, `Get-ADForest`, `Get-ADObject`, `Get-ADTrust`,
`Get-ADUser`

The list is deliberately explicit rather than a wildcard over the AD module. A stub that
mirrors all of RSAT stops being a statement about what this module depends on.

`Get-WinEvent`, `Get-ItemProperty` and `Invoke-Command` are also mocked by the suites, but
they ship with Windows and need no stub.

## Provenance

The `.psm1` is **generated, not hand-written** - do not edit it directly. Each function is
empty and declares exactly the parameters the real cmdlet declares, so a call the real
cmdlet would reject fails here too. Parameter types are carried over wherever the type
ships with PowerShell itself; types that live in the AD assemblies are left off, since a
host without RSAT has no way to load them.

To regenerate, run `Update-KrbTestStub.ps1` on a host that has RSAT:

```powershell
.\Update-KrbTestStub.ps1 -OutputPath .
```

## Available Scripts

| Script Name | Description |
|-------------|-------------|
| [Add-KrbTestStubPath](./Add-KrbTestStubPath.ps1) | Appends this directory to PSModulePath so the stub is discoverable |
| [Update-KrbTestStub](./Update-KrbTestStub.ps1) | Regenerates the stub module from the real cmdlets on an RSAT host |
