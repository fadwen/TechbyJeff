# OktaTestEnvironment

[![License](https://img.shields.io/badge/license-GPL--3.0-green)](https://github.com/fadwen/TechbyJeff/blob/main/LICENSE)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)

## 📖 Purpose

**OktaTestEnvironment** seeds a realistic Okta identity environment you can point scripts at, and
tears it down again cleanly.

One number shapes the whole design. An Okta trial org licenses **ten active
users**, and your own admin account is one of them, so this module seeds **eight**. Most test-data
generators lean on volume; here the eleventh user is a licence error.

So each of the eight has to earn its place by being awkward in a way that breaks scripts, and the
complexity that would normally come from headcount moves into the parts of Okta that are *not*
licence-capped — which is nearly all of them:

| | Count | Why it is there |
|---|---|---|
| Users | 8 | The only licence-capped object. Ten minus your admin account. |
| Groups | 17 | Overlapping, empty and rule-driven membership shapes |
| Group rules | 3 | Dynamic membership from three different attribute kinds |
| App integrations | 8 | Turns "who exists" into **who has access to what** |
| Custom attributes | 10 | Five data types, across **two** user schemas |
| User types | 2 | A second schema most scripts never look at |
| Network zones | 2 | Allow and blocklist, for policies to condition on |
| Policies | 3 | Overlapping sign-on precedence, plus a password policy |
| Trusted origins | 2 | Differing scopes; a fresh org has none |
| Event hooks | 2 | Outbound webhooks; a fresh org has none |
| Linked objects | 1 pair | Okta's real relationship primitive, distinct from `manager` |

**Key differentiators:**

- ✅ **Fits the licence** — headroom is checked before anything is created, so you get a clear
  refusal up front rather than a half-seeded tenant and an error partway through the loop
- ✅ **Bootstraps its own auth** — you supply an SSWS token once; it creates an OAuth service
  app with a private key, and every run after that authenticates as the app
- ✅ **Teardown that proves ownership** — nothing is deleted for merely looking like test data
- ✅ **No dependencies** — no gallery modules, no Okta SDK, works on a stock 5.1 host
- ✅ **Verified against a live tenant** — every API shape here was exercised for real, and the
  gotchas below are things that actually happened rather than things the docs imply

## 🚀 Quick Start

```powershell
# 1. Import the module
Import-Module .\OktaTestEnvironment.psd1

# 2. Connect with an SSWS token from Security > API > Tokens in the admin console
$token = Read-Host 'SSWS token' -AsSecureString
Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ApiToken $token

# 3. See what it would do before it does it
New-OktaTestEnvironment -WhatIf

# 4. Seed it
New-OktaTestEnvironment

# 5. From now on, authenticate as the app it created
Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ServiceApp
```

### Expected results

```
✅ Environment creation complete
📊 Created: 2 user types, 10 custom attributes, 8 users, 17 groups, 3 group rules, 8 apps,
            1 linked object pair, 2 network zones, 3 policies, 2 trusted origins,
            2 event hooks, 1 service app
🔑 Private key: C:\Users\you\.oktatestenvironment\trial-123456.okta.com.serviceapp.json
⏱️  Total time: one to two minutes
```

Once step 5 works, **revoke the SSWS token**. It has done its only job.

## 📋 Prerequisites

| Requirement | Minimum | Notes |
|---|---|---|
| **PowerShell** | 5.1 | Desktop and Core; verified on Windows PowerShell 5.1 and pwsh 7.4 on Debian |
| **Okta org** | Trial org | Or any org; raise `-ActiveUserLimit` on a paid plan |
| **SSWS API token** | Super admin | Only for the first run |
| **Free user slots** | 8 | Checked before anything is created |
| **Modules** | none | Deliberately zero dependencies |

Nothing to install. Every call goes through `Invoke-WebRequest`, the JWT is signed with the in-box
.NET crypto types, and the key is encrypted with DPAPI. That is a deliberate constraint rather than
an accident: a lab module that first requires you to install an SDK is one more thing to get
working before you can start.

`RequiredModules` is empty and a contract test enforces it. `-UseSecretStore` is the one path that
needs gallery modules, and it installs them on demand under that explicit opt-in — so nobody pays
for a vault they never asked for.

## 🔐 The two authentication modes

This is the part worth understanding, because the order matters.

| | SSWS API token | OAuth service app |
|---|---|---|
| Where it comes from | Pasted from the admin console | Created by `New-OktaTestServiceApp` |
| What is transmitted | The token itself, on every request | Only a short-lived signed assertion |
| Scope | Everything its creator can do | Exactly the granted `okta.*` scopes |
| Expiry | Never, until revoked | Access token lasts an hour, renewed automatically |
| Revocation | Delete the token | Delete one app |

```powershell
# First run only
Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ApiToken $token

# Every run afterwards
Connect-OktaTestEnvironment -OrgUrl https://trial-123456.okta.com -ServiceApp

# Or mint a token to hand to something else
$bearer = Get-OktaTestAccessToken -AsPlainText
```

The private key is generated locally, in memory, and only its public half is sent to Okta.

### Where the key is stored, and how it is protected

```
~\.oktatestenvironment\<org-host>.serviceapp.json
```

That location is outside the repository on purpose: a path under the module folder would sit
inside a working tree, one `.gitignore` mistake away from being pushed. The file's ACL is
replaced — inheritance broken, one entry for your account — and if that fails you get a warning
and the key still exists, because an app registered in Okta with no usable key on disk is worse
than a key with a loud warning attached.

The file is **always** written, in all three modes, so the org-to-credential mapping lives in one
predictable place. What changes is where the key itself goes:

| `Protection` | Key lives in | Encrypted at rest | Dependencies |
|---|---|---|---|
| **`DPAPI`** (default) | The file, encrypted | ✅ bound to this user **and** this machine | none |
| **`SecretStore`** (`-UseSecretStore`) | An encrypted vault; the file holds only a pointer | ✅ AES, password-protected | 2 gallery modules, auto-installed |
| **`None`** | The file, plaintext | ❌ file permissions only | none |

`None` is only reached where DPAPI does not exist — today that means Linux and macOS without
`-UseSecretStore`. It warns loudly rather than failing, and records itself honestly so
`Get-OktaTestAppCredential` can tell you. It is never chosen in preference to encryption.

> **On Linux and macOS, use `-UseSecretStore` if you want the key encrypted.** `ConvertFrom-SecureString`
> does not throw off Windows and does not encrypt either — it returns the UTF-16 bytes of the
> plaintext as hex. Verified on PowerShell 7.4/Debian, where `SECRETKEYMATERIAL` came back as
> `5300450043…` and decoded straight back. The module now detects the platform and reports
> `Protection: None` with a warning, rather than claiming DPAPI over what is effectively
> plaintext. File permissions are still applied (`600` on the file, `700` on the folder).

```powershell
# What have I got, and is it encrypted?
Get-OktaTestAppCredential

# Vault instead of DPAPI - the cross-platform option
New-OktaTestServiceApp -UseSecretStore
New-OktaTestEnvironment -UseSecretStore -VaultName MyLab
```

Because DPAPI keys the secret to your account *and* this machine, copying the file elsewhere makes
it undecryptable. For a lab credential that is a feature. The error says so explicitly rather than
surfacing a raw `CryptographicException`.

**Rotating the key requires an SSWS token**, not the app itself. Registering a client goes through
`/oauth2/v1/clients`, which is gated by `okta.clients.manage` — a scope deliberately withheld from
the seeded app, because an app that can register further OAuth clients can escalate its own
privileges. Verified against a live tenant: attempting it as the app returns a bare `403`.

Credential files written by earlier builds (schema version 1, plaintext) are still read, with a
warning naming the command that replaces them:

```powershell
New-OktaTestServiceApp -Force   # mints a new key, DPAPI-encrypted, and deletes the old app
```

### Retiring the SSWS token

Once the app works, the SSWS token is redundant. The module will retire it for you, but **only
if you name it**:

```powershell
New-OktaTestServiceApp -RevokeApiToken 'bootstrap'
New-OktaTestEnvironment -RevokeApiToken 'bootstrap'   # runs last, after everything else
```

It is not automatic, and it cannot be. **The module has no way to identify the token it is
authenticating with.** Verified against a live tenant:

- `GET /api/v1/api-tokens/current` returns **404** — that endpoint does not exist on a standard org.
- `GET /api/v1/api-tokens` returns ids, names and timestamps, but **never the token value**, so an
  SSWS string in hand cannot be matched to a row.

Orgs routinely hold several tokens serving Terraform, Postman and CI. The tenant this was
developed against held two. Anything that guessed would eventually revoke a working credential
belonging to something else.

Three interlocks, because revocation is permanent — Okta cannot restore a token or recreate one
with the same value:

| Interlock | Behaviour |
|---|---|
| **Proof before destruction** | Nothing is revoked unless the new app has successfully issued a token. A failed verification warns and leaves the token alone. |
| **No guessing** | Exact id or exact name only. No prefix, no wildcard. Two matches is an error naming both, never "pick the first". |
| **Preview** | `-WhatIf` names the token and revokes nothing. |

Keep at least one API token, or accept that a replacement is made by hand. Rotating the app's key
needs one, because `okta.clients.manage` is withheld from the app on purpose.

## 💡 Core functions

### Connection
- **`Connect-OktaTestEnvironment`** — establishes the connection every other function uses
  - `OrgUrl`, `ApiToken`, `ServiceApp`, `CredentialPath`, `Prefix`, `EmailDomain`,
    `ActiveUserLimit`, `PassThru`
  - The admin host (`-admin.okta.com`) is normalised to the API host, because pasting the
    address bar is the most common way to get this wrong and the resulting failure is a 404 on
    every call that names nothing.
- **`Disconnect-OktaTestEnvironment`** — clears the stored credential without unloading the module

### Environment
- **`New-OktaTestEnvironment`** — the orchestrator, twelve steps in dependency order
  - `Skip[]`, `UserCount`, `AccountPassword`, `SkipLifecycleStates`, `ServiceAppLabel`,
    `ServiceAppScope`, `CredentialPath`, `RevokeApiToken`, `UseSecretStore`, `VaultName`,
    `VaultPassword`, `ActiveUserLimit`, `Force`, `ShowProgress`, `PassThru`
- **`Remove-OktaTestEnvironment`** — teardown
  - `Keep[]`, `RemoveCredentialFile`, `Force`, `PassThru`

`-Skip` and `-Keep` take the same twelve names: `UserTypes`, `Schema`, `Users`, `Groups`,
`GroupRules`, `Apps`, `LinkedObjects`, `NetworkZones`, `Policies`, `TrustedOrigins`, `EventHooks`,
`ServiceApp`.

```powershell
# Directory objects only - no policies, hooks or origins
New-OktaTestEnvironment -Skip NetworkZones, Policies, TrustedOrigins, EventHooks

# Rebuild just the access-management layer over an existing directory
New-OktaTestEnvironment -Skip UserTypes, Schema, Users, Groups, GroupRules
```

### Components

Each runs standalone, and `New-OktaTestEnvironment` runs them in the order listed — which is the
only order that works, because each depends on the last.

- **`New-OktaTestUserType`** — creates the second user type. First, because a type must exist
  before its schema can be extended or a user assigned to it.
  - `TypeName[]`, `PassThru`
- **`New-OktaTestProfileAttribute`** — adds (or with `-Remove`, deletes) the custom attributes, on
  every user type's schema
  - `Attribute[]`, `Remove`, `PassThru`
- **`New-OktaTestUser`** — creates the eight users
- **`New-OktaTestGroup`** — creates the groups and assigns members
- **`New-OktaTestGroupRule`** — creates and activates the group rules
- **`New-OktaTestApp`** — creates the app integrations and assigns groups and users
  - `AppName[]`, `SkipAssignment`, `PassThru`
- **`New-OktaTestLinkedObject`** — creates the mentor/mentee definition and links users
  - `SkipLinks`, `PassThru`
- **`New-OktaTestNetworkZone`** — creates the IP zones policies condition on
  - `ZoneName[]`, `PassThru`
- **`New-OktaTestPolicy`** — creates the sign-on and password policies, with their rules
  - `PolicyName[]`, `PassThru`
- **`New-OktaTestTrustedOrigin`** — creates the CORS/redirect allowlist entries
  - `OriginName[]`, `PassThru`
- **`New-OktaTestEventHook`** — creates the outbound webhooks
  - `HookName[]`, `PassThru`
- **`New-OktaTestServiceApp`** — registers the OAuth app and stores its key
  - `Label`, `Scope[]`, `AdminRole[]`, `CredentialPath`, `UseSecretStore`, `VaultName`,
    `VaultPassword`, `KeySize`, `RevokeApiToken`, `Force`, `PassThru`
- **`Get-OktaTestAccessToken`** — client credentials + `private_key_jwt` → access token
- **`Get-OktaTestAppCredential`** — where the key is stored and whether it is encrypted
  - `CredentialPath`, `OrgUrl`, `VaultPassword`, `IncludePrivateKey`
  - The key is **not** returned by default. Nothing in normal use needs it in a variable, and a
    function that hands one back by default puts one in transcripts. `-IncludePrivateKey` asks
    for confirmation first.
- **`Get-OktaTestEnvironmentReport`** — Console, JSON, HTML or CSV
  - Covers every object type the module creates, and reads **every** user type's schema rather
    than only the default — reading only the default is the exact mistake the second user type
    exists to expose.
  - It asks Okta for each app's group and user assignments separately, so a full report is
    around forty calls. On a trial org's low per-minute ceiling that can trip a
    `429`; the retry handles it, but the report takes noticeably longer when it does.

## 📊 Test data inventory

### Users (8)

Source: `Data\OktaUsers.csv`. Every one differs along an axis that actually breaks scripts.

| Login | Name | Department | State | Why this one |
|---|---|---|---|---|
| `awhitfield` | Ada Whitfield | Executive | Active | Top of the manager chain, no manager of her own |
| `jnino` | José Niño | Engineering | Active | Non-ASCII name, ASCII login |
| `zmueller` | Zoë Müller | Engineering | Active | Non-ASCII, and a risk score of **zero** |
| `mbell` | Marcus Bell | Sales | **Suspended** | Contractor, with an end date |
| `praghunathan` | Priya Raghunathan | Finance | Active | Three entitlements, high clearance |
| `talvarez` | Tomás Álvarez | IT | Active | Non-ASCII, and in **two** departments |
| `hkobayashi` | Hana Kobayashi | HR | Active | **No** entitlements — the empty array case |
| `ofitzgerald` | Owen Fitzgerald | Sales | **Staged** | Never activated; invisible to group rules |

- **Non-ASCII names, ASCII logins.** That is what a real directory looks like. Windows
  PowerShell writes CSV as ASCII unless told otherwise and silently replaces those characters
  with `?`, so without them that data loss is invisible to every export script.
- **A risk score of zero.** Zero is falsy in PowerShell, so `if ($value) { ... }` drops it
  silently. The attribute is only a test if a user actually carries the value.
- **Three lifecycle states.** A staged user has never signed in and has no established
  credentials, but — verified against a live tenant — it still consumes an active user licence
  slot and it is still evaluated by group rules. Both are the opposite of what people assume,
  and the licence one is why eight is the right number rather than a soft target.

### Groups (17)

Source: `Data\OktaGroups.csv`. Okta groups do not nest — there is no group-inside-a-group to model,
so if you are coming from a directory that has them, group rules are the nearest equivalent.

| Category | Groups |
|---|---|
| Organisational | All Employees |
| Department | Engineering, Sales, Finance, Human Resources, IT |
| Region | AMER, EMEA, APAC |
| Site / function | **Zürich** Site Access, **Ingénierie Réseau** |
| Entitlement | Application Administrators, Application Users |
| Lifecycle | Offboarding Hold — **deliberately empty** |
| Automatic | Contractors, High Clearance, Engineering — **rule-driven only** |

- **The empty group is the point.** A group that is empty and a group that failed to resolve look
  identical in most reports.
- **Overlapping membership.** Tomás is in Engineering *and* IT, so anything assuming one
  department per user is wrong about him.
- **Rule groups get no manual members.** If a rule stops working its group empties out while the
  manually assigned ones do not, which makes the failure visible rather than ambiguous.

### Group rules (3)

Source: `Data\OktaGroupRules.csv`.

| Rule | Expression | Reads |
|---|---|---|
| Contractors | `user.labIsContractor == true` | a boolean custom attribute |
| High-Clearance | `user.labClearanceLevel == "High"` | an enumerated custom attribute |
| Engineering | `String.stringContains(user.department, "Engineering")` | a base attribute, via a function |

> **Rules reach staged and suspended users too.** Verified against a live tenant: the contractor
> rule picks up both seeded contractors even though one has never been activated and the other is
> suspended. That is the opposite of what most people assume, and it means a rule granting an
> entitlement reaches accounts nobody has ever signed into. Rules also apply asynchronously, so a
> report run immediately after activation can understate membership.

### App integrations (8)

Source: `Data\OktaApps.csv`. Users and groups answer *who*; apps are what turn that into **who has
access to what** — the question Okta exists to answer, and the one most scripts written against it
are trying to report on. Like groups, apps are not licence-capped, so this is free complexity.

| App | Sign-on mode | Assignment shape it creates |
|---|---|---|
| Intranet Portal | Bookmark | Everyone — a report returning nobody is obviously wrong |
| Expense Portal | Bookmark | **Two overlapping groups**, which a naive union double-counts |
| Engineering Wiki | Bookmark | **A direct assignee not in the assigned group** |
| **Zeitplan Übersicht** | Bookmark | Non-ASCII label, for app inventories |
| Sales CRM | SWA (password-vaulted) | Two groups; behaves differently from federated apps |
| Payroll Portal | SWA | **A user assigned both directly and via a group** |
| Analytics Console | OIDC (real client + secret) | Administrators only |
| Unassigned Legacy Tool | Bookmark | **Nobody at all** — what access reviews exist to find |

The two bolded middle rows are the valuable ones. Marcus is in Sales, the Wiki is assigned to
Engineering, and he is assigned to it directly — so a group-only access report misses him entirely.
That is the most common access-review bug there is, and it is not reproducible without an app.

> **No custom SAML apps.** Okta does not permit creating them through the API — `saml_2_0`,
> `template_saml_2_0`, `saml_2_0_custom` and `custom_saml_2_0` all return 404, verified against a
> live tenant. Make them in the admin console if you need one.

> **Okta discards the app profile on everything except OIDC.** The `POST` succeeds, the response
> omits it, and a follow-up `PUT` does not help. So the seed marker for apps is the label prefix
> **plus** a URL under the seed domain, which every app type does preserve. Keying teardown on the
> profile alone found one app out of eight and silently abandoned the other seven.

### User types (2) and custom profile attributes (10)

Sources: `Data\OktaUserTypes.csv`, `Data\OktaProfileAttributes.csv`.

Every Okta org has a default user type, and almost every script written against Okta assumes it is
the only one. A second type is the cheapest way to prove otherwise, because **each type has its own
independent schema**. The two contractors sit on the `Contractor` type and carry two attributes
that simply do not exist on the default schema — so an export reading
`/api/v1/meta/schemas/user/default` genuinely cannot see them.

> **Do not confuse this with `profile.userType`.** The seeded users carry that too, and it is
> unrelated: a free-text string on the profile, versus a real object with its own id and schema.
> Okta named them almost identically. A report that mixes them up looks right and is wrong.

Attributes are chosen for type coverage rather than realism — a schema of nothing but strings will
not tell you that your export flattens an array to `System.Object[]`.

| Attribute | Type | On which schema | What it exercises |
|---|---|---|---|
| `labSeedTag` | string | both | Infrastructure: how teardown proves a user is ours |
| `labBadgeId` | string | both | Length validation at both bounds |
| `labClearanceLevel` | string + enum | both | `enum`/`oneOf` handling, and group rule input |
| `labIsContractor` | boolean | both | The non-string branch of anything that stringifies a profile |
| `labRiskScore` | integer | both | Numeric typing, including the falsy value zero |
| `labContractEndDate` | string | both | ISO 8601 dates, which is how Okta actually stores them |
| `labEntitlements` | array of string | both | Multi-valued data, where flat exports break |
| `labCostCenterOwner` | string | both | A display name that has to be resolved, not an id |
| `labAgencyName` | string | **Contractor only** | Invisible to a default-schema export |
| `labPurchaseOrder` | string | **Contractor only** | Invisible to a default-schema export |

A blank `UserType` column means "every schema", not "the default one". That distinction cost a
bug: a type's schema is independent rather than an extension, so contractors created with only the
two type-specific attributes were rejected for all eight shared ones — including `labSeedTag`,
which teardown depends on.

> Editing the default user type's schema affects **every** user in the tenant, including your own
> admin account. On a shared tenant, prefer a dedicated user type.

### Network zones (2) and policies (3)

Sources: `Data\OktaNetworkZones.csv`, `Data\OktaPolicies.csv`. Policies are where an identity
environment stops being a list of objects and starts having behaviour.

| Zone | Usage | Ranges |
|---|---|---|
| Corporate-Egress | `POLICY` | `198.51.100.0/24`, `203.0.113.0/24` |
| Suspect-Range | `BLOCKLIST` | `192.0.2.0/24` |

| Policy | Type | Scope | What it demonstrates |
|---|---|---|---|
| Admin-Session | Sign-on | Application Administrators | A rule permitting sign-in **only from Corporate-Egress** |
| Standard-Session | Sign-on | All Employees | Anywhere, longer session — **overlaps** the above |
| Contractor-Password | Password | Automatic Contractors | Longer minimum, shorter maximum age |

The overlap is the interesting part. A user in both groups is governed by the higher-priority
policy, and Okta assigns priority by creation order, newest first. A report that lists policies
without their order tells you nothing about what actually applies.

All ranges are IANA documentation blocks, reserved so they can appear in examples without belonging
to anybody. That matters more than tidiness here: a lab zone containing a real address range is a
policy that could really lock somebody out.

> **These govern real sign-in behaviour.** On a shared tenant, an admin who is only in the
> administrators group and is not on a listed IP range will be denied. A policy that resolves no
> groups is refused rather than created, because an unscoped Okta policy applies org-wide.

### Linked objects (1 pair)

Source: `Data\OktaLinkedObjects.csv`. A named, directional, queryable association between two
users — `labMentor` / `labMentee`, with three links among the seeded users.

The seeded users *also* carry a `manager` profile string, and the difference is the whole point.
The string is just text: nothing validates it, nothing indexes it, nothing stops it naming somebody
who left two years ago. A linked object is a real reference Okta maintains on both sides, and it
disappears when either user does.

The mentoring links deliberately **do not** mirror the management chain, so a script that conflates
the two produces a visibly different answer than one that does not.

### Trusted origins (2) and event hooks (2)

Sources: `Data\OktaTrustedOrigins.csv`, `Data\OktaEventHooks.csv`. A fresh org has **none of
either**, so anything auditing outbound integrations or CORS allowlists has nothing to find until
these exist.

| Object | Detail |
|---|---|
| Lab-Portal | Trusted origin, `CORS` **and** `REDIRECT` |
| Lab-Widget-Host | Trusted origin, `CORS` only — a report assuming both gets this wrong |
| Lifecycle-Watcher | Event hook on user create, suspend and delete |
| Group-Watcher | Event hook on group membership add and remove |

Both hooks subscribe to events this lab genuinely generates — the group hook fires on membership
changes the group rules produce on their own. Nothing is listening at the far end, so deliveries
fail. That is expected, and itself worth having: a hook whose deliveries fail is a state monitoring
should notice.

> **Event hook URLs must resolve.** Okta validates the hostname and rejects one that does not:
> `https://hooks.oktalab.example.com/events` fails with "Invalid URL provided", while
> `https://example.com/...` is accepted. Verified against a live tenant. `example.com` is the only
> address that is both IANA-reserved and resolvable, which is why the hooks point there rather than
> at the lab domain everything else uses.

## 🧹 Teardown

```powershell
# Always worth running first
Remove-OktaTestEnvironment -WhatIf

# Do it
Remove-OktaTestEnvironment -Force

# Clear the data but keep the app you authenticate with, ready for an immediate re-seed
Remove-OktaTestEnvironment -Keep ServiceApp, Schema -Force
```

**Ownership is proven, not assumed.** A deleted Okta user cannot be restored — there is no
recycle bin — so nothing is deleted for merely looking like test data:

- **Users** must carry `profile.labSeedTag` matching the prefix, *or* sit under the seed email
  domain. Either is enough. The domain fallback exists because an interrupted teardown can
  remove the schema attribute before the users, and without it those users would be
  unrecoverable by the tool that created them.
- **Groups** must have both the name prefix *and* the seed marker in their description.
  Requiring both matters: a real group could plausibly match either one alone.
- **Apps** must have the label prefix *and* either the profile marker (OIDC only — Okta drops it
  elsewhere) *or* a URL under the seed domain. The tenant this was built against already held apps
  called `Google Workspace` and `Postman api`; a prefix match alone is how one of those gets
  deleted.

- **Policies, zones, origins and hooks** are matched on the name prefix alone. They carry no field
  that could hold a second marker, but they are also objects nobody creates by accident with a
  matching name.

`Apps` and `ServiceApp` are separate `-Keep` values on purpose. `-Keep ServiceApp` means "keep the
credential I authenticate with" and should not also strand eight lab apps you asked to be rid of.

The order is forced by Okta's own dependencies and runs in reverse of creation:

1. **Event hooks, trusted origins, policies, network zones** — first, because Okta refuses to
   delete a zone a policy rule still points at.
2. **Group rules** — a rule holding a group open blocks the group's deletion.
3. **Users** — deactivated, then deleted. Okta needs both.
4. **Groups**, then **app integrations**, then the **service app**.
5. **Linked objects** — after the users, since removing a definition removes every link made with
   it.
6. **Custom attributes** — removing one that users still carry destroys their data, and it is what
   identifies them.
7. **User types** — genuinely last. A type cannot be deleted while a user is on it.

`-WhatIf` beats `-Force`. If both are passed, nothing is deleted.

> **Do not tear down and immediately re-seed the schema.** Okta's deletion of schema-bearing
> objects is asynchronous: the DELETE returns success, the object vanishes from every listing, and
> the name stays reserved by a background job for some seconds afterwards. The module retries on
> that specific signature — up to 90s for attributes, 240s for a user type, which is what a live
> tenant actually needed. See the gotcha below for why the user type failure is so misleading.

## 🔍 Gotchas worth knowing

**A single `DELETE` on an active user only deactivates it.** Okta deletes in two steps. Teardown
always deactivates explicitly first, so the `DELETE` is reliably the second step whatever state
the user was in. A teardown that skips this reports success and leaves the user holding a licence
slot.

**Scopes and roles are different things.** Scopes say which APIs the app may call; the admin role
says which objects it may touch. An app with scopes and no role authenticates successfully and is
authorised for nothing. `New-OktaTestServiceApp` assigns both, and warns loudly if the role
assignment fails — which it will if the SSWS token does not belong to a super admin.

**`SUPER_ADMIN` is the default role.** Managing the user schema is a super admin operation and
the target is a disposable tenant. On anything you care about, pass
`-AdminRole USER_ADMIN, APP_ADMIN` and accept that `-Skip Schema` becomes mandatory.

**The org authorisation server, not the default one.** Tokens carrying `okta.*` scopes only come
from `/oauth2/v1/token`. A token from `/oauth2/default/v1/token` is issued happily and then
rejected by every management API call.

**Users are always created with a password.** Creating an Okta user without credentials makes
Okta send a real activation email to the address on the profile. The seeded addresses are under
`example.com`, which RFC 2606 reserves so test data cannot reach a real recipient, but the tenant
would still record eight bounced activations.

**"The request body was not well-formed" can mean "wait a bit".** Creating a user type inside the
window where a previous one of the same name is still being deleted returns a bare `E0000003` that
names nothing and sends you hunting for a malformed payload. The identical body succeeds a minute
later. Custom attributes at least say so explicitly — *"the deletion process for an attribute with
the same variable name is incomplete"* — but a user type gives you nothing. Both are retried on
those signatures alone; a `400` that means what it says still fails immediately.

**Each user type's schema is independent, not an extension of the default.** Attributes you want
on every user have to be written to every type's schema. A user created on a second type with only
that type's attributes is rejected for every shared one.

## 🧪 Tests

Pester 6 unit tests live in `Tests\Unit\`. Every Okta call is mocked, so the suite reaches no
tenant, burns none of the ten user slots, and is safe to run on a workstation.

```powershell
Import-Module Pester -MinimumVersion 6.0.0
Invoke-Pester -Path .\Tests

# One area at a time
Invoke-Pester -Path .\Tests -TagFilter 'Contract'    # manifest, exports, layout, seed data
Invoke-Pester -Path .\Tests -TagFilter 'Destructive' # the teardown paths
```

| File | Covers |
|---|---|
| `Module.Contract.Tests.ps1` | Manifest validity, `.psd1`/`.psm1` export agreement, one function per file, no cmdlet shadowing, and the shape of the seed data |
| `Private\ConvertTo-OktaTestBase64Url.Tests.ps1` | Padding, URL-unsafe characters, and byte-exact round trips including leading zeros |
| `Private\New-OktaTestClientAssertion.Tests.ps1` | That the JWT verifies against its own public key, and that every claim Okta checks is present |
| `Private\Invoke-OktaTestRequest.Tests.ps1` | UTF-8 on both sides, query encoding, error surfacing, retry policy, and pagination |
| `Private\Get-OktaTestSeededUser.Tests.ps1` | That teardown finds our users and, more importantly, nobody else's |
| `Private\Get-OktaTestUserHeadroom.Tests.ps1` | The licence gate, including that already-seeded users count as reusable |
| `Private\Protect-OktaTestSecret.Tests.ps1` | That the key is unreadable on disk, round-trips exactly, still signs afterwards, and that v1 files are still accepted |
| `Private\Resolve-OktaTestApiToken.Tests.ps1` | That token revocation never guesses: no prefix match, no wildcard, ambiguity refused, and nothing revoked until the new app has proven itself |
| `Public\New-OktaTestUser.Tests.ps1` | The seed tag, the activate flag, that a password is always sent, and that only the contractors get the second user type and its exclusive attributes |
| `Public\New-OktaTestApp.Tests.ps1` | The assignment shapes, and that app teardown finds bookmark apps by URL rather than by the profile Okta throws away |
| `Public\New-OktaTestPolicy.Tests.ps1` | That a policy is never created unscoped, and that a missing zone costs you the restriction loudly rather than silently |
| `Public\New-OktaTestUserType.Tests.ps1` | The type's own schema path, the retry for the reserved-name window, and that shared attributes reach every schema while type-specific ones do not |
| `Public\New-OktaTestNetworkZone.Tests.ps1` | Zones, trusted origins, event hooks and linked objects — gateway type inference, scope splitting, and that a link is set on the associated user naming the primary |
| `Public\Connect-OktaTestEnvironment.Tests.ps1` | Credential validation before storage, that the Authorization header never leaves in `-PassThru`, admin-host rewriting, plus the group and rule seeders |
| `Public\Get-OktaTestEnvironmentReport.Tests.ps1` | That the report covers every object type the Data folder defines, reads every user type's schema, and survives a 403 on one object's membership — plus the credential accessor |
| `Public\Get-OktaTestAccessToken.Tests.ps1` | That the request goes to the **org** authorisation server, carries no Authorization header, and asks for the scopes the app actually holds |
| `Public\Disconnect-OktaTestEnvironment.Tests.ps1` | That the credential is really cleared, kept under `-WhatIf`, and that disconnecting when nothing is connected is a no-op rather than an error |
| `Public\New-OktaTestEnvironment.Tests.ps1` | Step ordering, `-Skip`, failure isolation, and a backstop that fails loudly if any step escapes the mocks and reaches a real tenant |
| `Public\Remove-OktaTestEnvironment.Tests.ps1` | That `-WhatIf` wins over `-Force`, and that `-Force` alone still works |

Every `Describe` is tagged, so `Invoke-Pester -TagFilter 'None'` should find nothing.

These are aimed at where defects actually occur rather than at a coverage percentage. Three of
them are regressions for bugs found while building the module:

- A missing empty field shifted six rows of `OktaUsers.csv` by one column. `Import-Csv` reports
  nothing at all, and the blank lifecycle state that resulted happened to fall through to
  "create it active", so nothing failed.
- `New-Object System.Exception($a + $b, $inner)` does not call the `(message, inner)`
  constructor. PowerShell binds the parenthesised list as one array argument, so every API
  failure message absorbed the inner exception's whole stack trace and `InnerException` was
  never set.
- Okta will return a `Link rel="next"` pointing at the page you just fetched, and `-Paginate`
  spun on it forever without a comparison against the current URL.

Six more came out of running it against a live tenant, which no amount of mocking would have
found:

- Group rules apply to **staged and suspended** users, not only active ones. The documentation
  said the opposite.
- The licence check counted the module's own users against the ceiling, so it refused to re-run
  against the environment it had just built.
- `/oauth2/v1/clients` is gated by `okta.clients.manage`, not `okta.apps.manage`, so the warning
  about creating an app while connected as one named the wrong scope.
- Okta **discards the app profile** on every sign-on mode except OIDC, so teardown keyed on that
  marker found one app out of eight and abandoned the other seven.
- Deleting schema-bearing objects is **asynchronous**, so the module's own tear-down-then-re-seed
  workflow failed every time until the retries were added.
- A user type's schema is **independent**, not an extension of the default, so contractors were
  rejected for every shared attribute including the one teardown identifies them by.

Two came from running it on a **non-Windows host** (pwsh 7.4 on Debian), and neither was reachable
from Windows at all:

- `ConvertFrom-SecureString` silently returns hex-encoded plaintext off Windows instead of
  throwing, so the module recorded `Protection: DPAPI` and `Encrypted: True` over a credential
  anyone could read. The guard that was supposed to catch this only compared the output to the
  plaintext, which a hex encoding passes.
- `Get-Command chmod` returns **two** matches on Debian (`/usr/bin/chmod` and `/bin/chmod`), so
  `.Source` was an array and the invocation silently did nothing. The credential file kept mode
  `644` while the function reported success.

One more is a test-suite defect rather than an Okta one, and worth naming because it undermined the
suite's central promise: adding the Apps step to the orchestrator without mocking it meant those
tests **made real network calls**. `New-OktaTestEnvironment.Tests.ps1` now carries a backstop mock
that throws on any request escaping the mocks, so the next step added cannot silently reach a
tenant.

## 📊 Module information

- **Version**: 1.0.0
- **Author**: Jeffrey Stuhr (EntraVantage LLC)
- **PowerShell**: 5.1+ (Desktop/Core compatible)
- **Dependencies**: none
- **Module GUID**: f3a7c619-2d84-4b51-9e6a-8c0d5f2b7e14
- **License**: [GPL-3.0](https://github.com/fadwen/TechbyJeff/blob/main/LICENSE)
- **Source**: [Powershell/Okta/OktaTestEnvironment](https://github.com/fadwen/TechbyJeff/tree/main/Powershell/Okta/OktaTestEnvironment)

## 📞 Support & contact

- **Author**: Jeffrey Stuhr
- **Company**: EntraVantage LLC
- **Blog**: https://www.techbyjeff.net
- **LinkedIn**: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For issues, feature requests, or contributions, please use the repository's issue tracker.
