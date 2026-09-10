# OktaTestEnvironment

> **This module has moved.** It is now the Okta provider of
> [TestEnvironment](https://github.com/fadwen/TestEnvironment) — one module that seeds and tears
> down Entra ID, Active Directory and Okta test environments — and it ships from the PowerShell
> Gallery:
>
> ```powershell
> Install-PSResource -Name TestEnvironment
> ```
>
> The code that used to live in this folder was the version the post below was written against.
> It is no longer maintained here; the repository above is where the current code, the tests and
> the issue tracker are.

## The post this folder backed

- [Seeding an Okta Test Tenant When You Only Get Ten Users](https://techbyjeff.net/seeding-an-okta-test-tenant-when-you-only-get-ten-users/)

## What the commands are called now

The component commands dropped their `Test` infix, because Okta ships no PowerShell cmdlets of its
own to collide with. The commands that drive the whole environment became provider-agnostic, and
the connect step now names the provider:

| In the post | Now |
|---|---|
| `Import-Module .\OktaTestEnvironment.psd1` | `Import-Module TestEnvironment` |
| `Connect-OktaTestEnvironment -OrgUrl … -ApiToken $token` | `Connect-TestEnvironment -Provider Okta -OrgUrl … -ApiToken $token` |
| `Connect-OktaTestEnvironment -OrgUrl … -ServiceApp` | `Connect-TestEnvironment -Provider Okta -OrgUrl … -ServiceApp` |
| `New-OktaTestEnvironment -Skip NetworkZones, Policies` | `New-TestEnvironment -Skip NetworkZones, Policies` |
| `Get-OktaTestEnvironmentReport` | `Get-TestEnvironmentReport` |
| `Remove-OktaTestEnvironment` | `Remove-TestEnvironment` |
| `New-OktaTestUser`, `New-OktaTestGroup`, … | `New-OktaUser`, `New-OktaGroup`, … |

The ten-user ceiling, the eight awkward users, the seed tag and the bootstrap from an API token to
an OAuth service app are all as the post describes.
