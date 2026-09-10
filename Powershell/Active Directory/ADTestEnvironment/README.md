# ADTestEnvironment

> **This module has moved.** It is now the Active Directory provider of
> [TestEnvironment](https://github.com/fadwen/TestEnvironment) — one module that seeds and tears
> down Entra ID, Active Directory and Okta test environments — and it ships from the PowerShell
> Gallery:
>
> ```powershell
> Install-PSResource -Name TestEnvironment
> ```
>
> The code that used to live in this folder was the version the posts below were written
> against. It is no longer maintained here; the repository above is where the current code,
> the tests and the issue tracker are.

## The posts this folder backed

- [Active Directory Test Data That Doesn't Suck](https://techbyjeff.net/active-directory-test-data-that-doesnt-suck/)
- [From Plain Text Passwords to PowerShell SecretStore: Securing Your AD Test Environment](https://techbyjeff.net/from-plain-text-passwords-to-powershell-secretstore-securing-your-ad-test-environment/)

## What the commands are called now

The provider commands kept their names — `New-ADTestUser`, `New-ADTestGroupPolicy`,
`Get-ADTestPasswordFromVault` and the rest — because `New-ADUser` and `New-ADGroup` are real RSAT
cmdlets and dropping the `Test` infix would have shadowed them. Only the three commands that drive
the whole environment became provider-agnostic, and there is now a connect step that names the
provider once:

| In the posts | Now |
|---|---|
| `Import-Module .\ADTestEnvironment.psd1` | `Import-Module TestEnvironment` |
| *(no connect step)* | `Connect-TestEnvironment -Provider AD` |
| `New-ADTestEnvironment -UseSecretStore` | `New-TestEnvironment -UseSecretStore` |
| `Get-ADTestEnvironmentReport -OutputFormat HTML` | `Get-TestEnvironmentReport -OutputFormat HTML` |
| `Remove-ADTestEnvironment -RemoveOUs -Force` | `Remove-TestEnvironment -RemoveOUs -Force` |

Everything the posts describe — the SecretStore vault, its default password, the ownership proof
before teardown — works the same way, and the parameters are the same because
`New-TestEnvironment` mirrors the provider command's own.
