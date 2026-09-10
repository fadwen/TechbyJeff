# TestEnvironment

Seeds a realistic identity test environment — Entra ID, Active Directory or Okta — and tears it
down again cleanly, proving ownership before deleting anything. It has its own repository and
ships from the PowerShell Gallery:

**https://github.com/fadwen/TestEnvironment**

```powershell
Install-PSResource -Name TestEnvironment
```

It replaced two modules that used to live in this repository, whose folders now point here:
[`ADTestEnvironment`](../Active%20Directory/ADTestEnvironment/) and
[`OktaTestEnvironment`](../Okta/OktaTestEnvironment/).
