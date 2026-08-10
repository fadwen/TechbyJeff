# Troubleshooting Deploy-SshKey.ps1

Companion to [Deploy-SshKey.ps1](./Deploy-SshKey.ps1). The script's comment-based help
describes what each parameter does and what the tool will not do; this file covers what to do
when a run misbehaves, and records why the script is shaped the way it is.

`Get-Help .\Deploy-SshKey.ps1 -Full` remains the reference for parameters, examples and the
result object.

---

## First moves

Almost every report resolves to one of four questions. Answer them in order.

| # | Question | How to answer it |
|---|---|---|
| 1 | Did it fail, or is it waiting? | A hang is nearly always a password prompt you cannot see. See [Runs that hang](#runs-that-hang). |
| 2 | What did the host actually say? | Re-run with `-TraceRemoteCommand`. It returns the remote command trace. |
| 3 | Which key does the server accept? | `ssh -v -i <key> -o IdentitiesOnly=yes user@host true 2>&1 \| Select-String 'Server accepts key'` |
| 4 | Is the failure the client's or the server's? | `Status=Failed` with `ExitCode 255` is transport or authentication. A host that returned `KEY_INSTALLED_OK` and still fails is an sshd-side problem. |

The result object is the record of what happened. `Status`, `Verified`, `KeysInstalled`,
`RemoteKeyFile` and `RemoteMessage` are all populated deliberately, and `RemoteMessage`
carries warnings that also went to the console, so a CSV export keeps them.

**`Status` means what it says.** `Installed` is never reported for a key that was missing when
the script last looked - that case is `Failed`. It is a statement about the moment the run
finished, not a promise about the future.

---

## Runs that hang

A run producing no further output is almost never a crash. Something is waiting for input on a
console you are not looking at.

### A jump host is asking for a password

**Symptom:** `-SshOption ProxyJump=bastion` and the run stops after `Processing ...`.

**Cause:** ssh applies `-i` and `IdentitiesOnly` to the **final destination only**. The
connection to the jump host is resolved independently and never sees the key from `-KeyPath`,
so it falls back to a password prompt. `-Credential` does not help either: it answers the
destination, not the hop.

**Fix:** give the bastion its own identity in a config and point `-SshConfigFile` at it.

```powershell
# estate.ssh_config
Host bastion
    HostName bastion.example.com
    User jump
    IdentityFile C:\keys\id_ed25519

Host app01
    HostName 10.0.0.15
    User deploy
    ProxyJump bastion

.\Deploy-SshKey.ps1 -ComputerName app01 -SshConfigFile .\estate.ssh_config
```

An agent holding the bastion's key works equally well, since ssh consults the agent for the hop.

### No hosts were supplied and there is no console

**Symptom:** a scheduled task or CI job stalls, or dies complaining about the console.

**Cause:** with no `-ComputerName`, `-HostFile` or pipeline input, an interactive run asks for
hosts.

**Fix:** a pipeline-driven run never prompts - it fails with `No hosts were specified` instead.
If you are invoking it without a pipeline, pass `-HostFile` or `-ComputerName` explicitly.
Where a console genuinely is absent the prompt is skipped rather than thrown from.

### The target is prompting for a password you meant to supply

**Symptom:** `-Credential` was passed and the run still waits.

**Cause:** the credential reaches ssh through `SSH_ASKPASS`, which needs the helper to be
found and run. If `SSH_ASKPASS_REQUIRE` has been overridden in the environment, ssh may ignore
it.

**Fix:** check for a pre-existing `SSH_ASKPASS` / `SSH_ASKPASS_REQUIRE` in the session. The
script sets both on the child process only and does not modify the parent, so a hostile value
in the parent is inherited by everything else it runs.

---

## Remote command failures

### `base64: illegal option -- d`

**Symptom:** POSIX target, `Status=Failed`, nothing installed, and the host echoes a `base64`
usage message.

**Cause:** BSD and macOS spell the decode flag `-D`; GNU coreutils uses `-d`. The script only
sends base64 at all when the client cannot escape quotes in a native command line - Windows
PowerShell 5.1, PowerShell 6.0-7.1, or 7.2+ forced to `Legacy` argument passing.

**Fix:** run the same deployment from PowerShell 7.2 or later. It sends a plain shell command
and needs nothing on the target beyond a POSIX shell. The script recognises this failure and
says so rather than offering the generic sshd hint.

There is no portable single-pipeline form: choosing between `-d` and `-D` needs a shell
variable, and that is Bourne-only, which would break the csh/tcsh/fish compatibility the
current form is built for.

### `base64: not found`

Same class, simpler cause - the target has no `base64` at all. Same fix: deploy from
PowerShell 7.2+, which imposes no such dependency.

### `-PosixTransport Direct` is refused

**Symptom:** `Direct transport needs a PowerShell that escapes quotes...`

**Cause:** the client mangles embedded quotes. Forcing `Direct` there would word-split each key
into fragments, appending several bogus entries while reporting success. Refusing is the only
honest outcome.

**Fix:** use `Auto` (the default) or `Encoded`, or run from PowerShell 7.2+.

### The host says the key was written, but sshd will not read it

**Symptom:** `Status=Failed`, and the script reports `The host confirmed the key was written to
<path>, so sshd is not reading it.`

**Causes, in the order worth checking:**

1. `PubkeyAuthentication yes` is not set in `sshd_config`.
2. Permissions - `~/.ssh` must be `700`, `authorized_keys` `600`, both owned by the user.
3. SELinux context. The script runs `restorecon` where it exists; if it does not, run
   `restorecon -R ~/.ssh` on the server.
4. `AuthorizedKeysFile` points somewhere else. Use `-RemoteAuthorizedKeysPath` (alias
   `-TargetPath`) to write the file sshd actually reads.
5. On Windows, an administrator's profile `authorized_keys` is ignored by the default
   `Match Group administrators` block. See below.

---

## Windows targets

### `administrators_authorized_keys` was refused

**Symptom:** `RemoteMessage` reports the refusal and the key was written to the profile file
instead. For an administrator the run then reports `Failed`.

**Cause:** the session's token lacks an enabled Administrators group, or the file's ACL has
been hardened.

**What is normal:** Windows OpenSSH grants an *unfiltered* token even to an account UAC would
filter at interactive logon. Verified on Server 2022 with `EnableLUA=1`, both as the built-in
Administrator and as an ordinary member of `BUILTIN\Administrators` - `whoami /groups` reports
Administrators as `Enabled group`, not `Group used for deny only`, and the write succeeds. So a
refusal here is a real anomaly, not the expected case.

**Fix:** the key has to be added on the server itself, or the file's ACL corrected. The
fallback to the profile file does not help an administrator, because sshd's
`Match Group administrators` block reads only the `%ProgramData%` file for them. If that block
has been removed from your `sshd_config`, pass `-WindowsKeyLocation UserProfile`.

### The command is too long

**Symptom:** `Remote command is N characters ...; cmd.exe cannot receive it.`

**Cause:** the Windows install is one cmd.exe command line, capped at 8191 characters. An
RSA-4096 key spends roughly 6900 of them.

**Fix:** deploy fewer keys per run, or use ed25519.

### `-TraceRemoteCommand` returns XML instead of a trace

**Symptom:** `<Objs Version="1.1.0.1" ...><S S="debug">` instead of readable `DEBUG:` lines.

**Cause:** only when combined with `-Credential`. `Set-PSDebug` writes to the debug stream, and
`powershell.exe` serialises non-output streams as CLIXML whenever they are redirected - which
the credential path does by design, so the password can be given to that one child alone.

**Fix:** none needed - the trace is all there, XML-escaped. Drop `-Credential` and type the
password to get plain text. POSIX targets are unaffected: `set -x` writes ordinary text.

---

## Authentication and lockouts

### Connections start being refused part-way through a run

**Symptom:** early hosts work, then `kex_exchange_identification: read: Unknown error` or
`Connection closed by <host>`, and the host refuses you for minutes.

**Cause:** OpenSSH 9.8 and later enable `PerSourcePenalties` by default. Every authentication
failure penalises the **client address** - `authfail:5` seconds, accumulating to as much as
600. Observed on Debian running OpenSSH 9.9.

**Fix:** stop the run. Do not retry. A stale `-Credential` in a fleet deployment does not
merely fail - it can lock the deploying machine out of every host it touches. This is why the
script caps password prompts at one per host when a credential is supplied.

Check the target's policy with `sshd -T | grep -i persource`.

### `Status=Installed` but `Verified=False`

**Cause:** the key is passphrase-protected and no agent holds it. Every probe runs with
`BatchMode=yes`, which suppresses passphrase prompts as well as password prompts, so
reachability cannot be tested. Installation is taken from the host's own confirmation.

**Fix:** `ssh-add <key>` and re-run to get a real verification.

### A host reports `AlreadyConfigured` for a key it has never seen

This was a genuine defect, fixed in v1.5.0, and is worth understanding because the diagnosis is
counter-intuitive. `IdentitiesOnly=yes` governs which **agent** identities may be offered - it
does **not** stop an `IdentityFile` named in `ssh_config` from being offered alongside the `-i`
key. A host already trusting that config key answered "yes" to a question asked about a
different key.

The probe now matches the SHA256 fingerprint from `ssh -v`'s `Server accepts key` line. If you
see this symptom on an older copy, that is the cause.

---

## SFTP mode

### `dest open "...": Permission denied`

**Symptom:** `Status=Failed`, and `RemoteMessage` names a rescue file:
`The sftp upload failed; the file as it was before this run is saved at <path>`.

**Cause:** the target `authorized_keys` is not writable by the account. Note that a read-only
*directory* does not cause this - `put` to an existing file only needs write permission on the
**file**.

**Fix:** correct the permissions on the server. The rescue file holds the file exactly as it
was before the run; the remote file is untouched.

### Entries disappear under concurrent runs

**Cause:** `-UseSftp` replaces the whole file, because SFTP has no atomic append and no
compare-and-swap. Three checks bound this - a re-read immediately before the overwrite that
merges back any change found, a read-back afterwards that reports a missing key as a failure,
and the usual post-install verification - but they narrow the window rather than closing it.

**Fix:** avoid simultaneous `-UseSftp` runs against one file. The exec path appends and is not
affected. The runs that lose entries do report `Failed`.

For reference, `ssh-copy-id -s` has the same exposure with no detection at all: it downloads,
appends locally and uploads, with no re-read, no verification and no lock.

---

## Parameters that error instead of binding

`-f`, `-F`, `-t` and `-s` are deliberately **not** bound, and report PowerShell's ambiguity
error listing the real candidates. That is intentional:

| Flag | Why it is unbound |
|---|---|
| `-f` / `-F` | PowerShell matches parameter names case-insensitively, so ssh-copy-id's force/config-file distinction cannot survive. Binding either would silently give the other. |
| `-t` | Would bind `-RemoteAuthorizedKeysPath`, turning `-t Windows` - the obvious way to ask for a Windows target - into a relative path named `Windows`. |
| `-s` | Would bind the `-UseSftp` switch and leave the following word to be read as a hostname. |

Use the full names, or the safe short forms: `-i`, `-o`, `-p`, `-x`, `-TargetPath`,
`-ConfigFile`, `-Sftp`.

**Watch out for `-Force`.** ssh-copy-id's `-f` forces the *install*; that is `-ForceInstall`
here. This script's `-Force` is destructive - it deletes the key pair at `-KeyPath` and
generates a new one.

---

## Other symptoms worth knowing

Shorter entries, one per remaining documented limitation, so every one has somewhere to look.

### `Permission denied (publickey)` on the very first run

The target has password authentication disabled, so there is no way in to install the first
key. `-Credential` authenticates - it does not enrol. Either enable `PasswordAuthentication`
on the target for the duration, or deliver the first key another way (console, cloud-init,
configuration management, an existing trusted key).

The same applies to a host requiring keyboard-interactive MFA: the script cannot satisfy it and
does not try.

### The old key still works after rotating with `-Force`

Expected. `-Force` replaces the key pair at `-KeyPath` and installs the new one; it does not
remove the superseded entry from any `authorized_keys`. Remove the old key separately, and
remember that a host missed by the rotation run keeps trusting an identity you no longer hold.

### `-UpdateSshConfig` did nothing, and the run said so

Only with `-UseAgentKeys`. A `Host` block records one `IdentityFile` and the agent supplies
several, so there is no honest single value to write. The run warns and skips it. Write the
block by hand, or deploy a single key with `-KeyPath` when you want the config entry.

### A Windows host was treated as Linux

Platform detection reads the SSH identification banner before authentication. It fails when:

- the banner cannot be read - a protocol-aware proxy, or a filtered port
- the route goes through `ProxyJump`, since the probe opens a raw socket and cannot traverse it

Pass `-TargetPlatform Windows` explicitly. The symptom is a POSIX shell command sent to a
Windows host, which usually surfaces as the host never returning the sentinel.

### A Windows target fails with no useful output

The remote payload runs through `powershell.exe`. It must be present - the `DefaultShell`
setting does not matter, because the command names the interpreter itself. A Windows host
without Windows PowerShell cannot be a target.

### A setting from the system-wide `ssh_config` stopped applying

`-SshConfigFile` is ssh's own `-F`, and `-F` suppresses the system-wide configuration by
design. Anything you were inheriting from `/etc/ssh/ssh_config` or
`%ProgramData%\ssh\ssh_config` needs restating in the file you named.

---

## Verification recipes

```powershell
# Which key did the server actually accept?
ssh -v -i $key -o IdentitiesOnly=yes user@host true 2>&1 | Select-String 'Server accepts key'

# What did the target do during the install?
.\Deploy-SshKey.ps1 -ComputerName user@host -x

# What would be deployed, without touching anything?
.\Deploy-SshKey.ps1 -ComputerName user@host -WhatIf     # names each identity and fingerprint

# Prove a config alias resolves the way you think
ssh -F .\estate.ssh_config -G myalias | Select-String '^(hostname|user|port) '

# Confirm remote permissions
ssh user@host 'stat -c "%a %n" ~/.ssh ~/.ssh/authorized_keys'
```

---

## Lessons from building and testing this script

Recorded because each one cost real time, and several would otherwise be repeated.

### Test the generated artefact, never a hand-typed equivalent

A shell-syntax bug (`if X; then; ...`, produced by joining a step list with `"; "`) survived
review because the test was written by hand rather than extracted from the builder's output.
The remote shell hung. The suite now decodes the actual command the script emits and runs
`sh -n` over it. **If a test does not consume the real output, it is testing your intent.**

The same mistake recurred later in the CI workflow: the summary rows were validated with
equivalent-but-not-identical formatting, so a `-f` operator-precedence bug shipped and failed
both jobs on the first run. Extract and execute the literal text.

### A skip condition tied to the host's real behaviour means a branch never runs

Transport tests skipped based on whether *this* PowerShell escapes quotes correctly. Under
pwsh 7 the unsafe branch could never execute - and that is precisely the branch a 5.1 operator
depends on. `Test-NativeQuotingSafe` is a function, so both answers can be mocked, and every
transport test now runs everywhere. Zero skipped.

### A fixture must reproduce the real precondition

The ACL test created its file with `Set-Content`, which leaves only **inherited** ACEs -
cleaned up by `icacls /inheritance:r` alone. Real keys are created by `ssh-keygen`, which
writes **explicit** SYSTEM and Administrators entries that survived. The test passed for a long
time against code that could not do what its documentation claimed. The fixture now seeds
explicit ACEs and asserts it starts dirty.

### `-is [pscustomobject]` matches every PSObject

It resolves to `System.Management.Automation.PSObject`, so a filter using it matched
`InformationRecord` objects too and `[0]` picked the wrong one. Filter on
`$_.PSObject.TypeNames[0] -eq 'SshKeyDeploymentResult'`.

Related: `Write-Host` output does not appear in `2>&1`. Capturing it needs `*>&1`, which then
mixes in `InformationRecord` objects.

### A `.NET` line at the start of a help line silently destroys the whole help block

PowerShell reads `.WORD` at the start of a line inside comment-based help as a keyword.
`.NET` is not one, so the **entire block** was discarded and `Get-Help` fell back to
reflection - every `.PARAMETER` vanished while the file still parsed and every test passed.
Two guards now assert help is really parsed and that no unrecognised dot-keyword appears.

### Documentation drifts silently; assertions need re-checking against behaviour

An audit found several statements that had quietly stopped being true: the POSIX command was
described as "nothing but a base64 blob" long after the default transport stopped using
base64; the ACL was said to be reduced to one identity when it was three; `-PosixTransport`
was documented as ignored for Windows targets while it aborted such runs outright. Treat the
help as code that needs testing.

### Do not assume a documented caveat is true

The help warned that a UAC-filtered administrator "may be refused". Building one showed Windows
OpenSSH grants an unfiltered token, and the write succeeds. The caveat was inherited reasoning,
never measured. Measuring it made the documentation *less* alarming and more accurate.

### Windows PowerShell 5.1 is a different language for native commands

Two faults appear only there, and both corrupt data rather than failing loudly:

- It does not escape embedded double quotes, so `[ -n "$line" ]` arrived as `[ -n ]`, which
  POSIX `test` reports **true** - producing an unbounded loop that appended blank lines to
  `authorized_keys`.
- It prepends a UTF-8 BOM to anything piped into a native command, corrupting the first key.

Both are avoided by embedding data in the payload rather than piping it, and by base64-encoding
the payload where the client needs it. `ProcessStartInfo.ArgumentList` also does not exist on
.NET Framework, so the credential path builds the command line by hand to
`CommandLineToArgvW`'s rules - and a test asserts that hand-built line produces identical
`argv` to `ArgumentList` on hosts that have both.

### Killing a local ssh does not stop the remote command

When the runaway-loop bug fired, terminating ssh on the workstation left the remote shell
running. One target reached 1.85 million lines in `authorized_keys` and was still growing. If a
remote command may loop, check the target before assuming a local kill ended it.

### Clean up after testing, and verify the cleanup

Deleting a Windows account whose profile exists leaves the profile registered and its hive
`loaded=True`; `Remove-CimInstance Win32_UserProfile` will not take until it unloads. Proxmox's
`/root/.ssh/authorized_keys` is a symlink onto pmxcfs, so an in-place rewrite breaks it - copy
over it instead. Record a baseline (line count **and** checksum) before testing so restoration
can be proved rather than assumed.

### Failure modes worth knowing before you test authentication

`PerSourcePenalties` on OpenSSH 9.8+ turns a deliberate wrong-password test into a self-inflicted
lockout lasting minutes. Test the failure path last, or on a host you can afford to lose.

---

## Version history

Kept here rather than in the script's `.NOTES`, where it was maintenance-heavy and pushed the
useful help further down. Git history is the authority; this is the readable summary.

| Version | Change |
|---|---|
| 1.9.2 | Documented the ProxyJump authentication rule - `-SshOption ProxyJump=` alone does not authenticate the hop, and the run looks like a hang. |
| 1.9.1 | The `-Credential` password is no longer placed in this process's environment at all; each ssh/sftp child gets it in its own environment block. On 5.1 the command line is hand-built to `CommandLineToArgvW` rules, asserted equal to `ArgumentList`. |
| 1.9.0 | `-Credential` for unattended onboarding via `SSH_ASKPASS`. Password prompts capped at one per host. Only the password is taken from the credential; the account still comes from the target, config or `-User`. |
| 1.8.0 | `-ComputerName` accepts pipeline input by value and by property name, using real `begin`/`process`/`end` blocks. A pipeline-driven run never prompts for hosts. |
| 1.7.0 | Closed the last ssh-copy-id gaps: `-SshConfigFile` (`-F`), `-TraceRemoteCommand` (`-x`), `-WhatIf` naming the identities (`-n`). Added the short-form aliases; left `-f`, `-F`, `-t`, `-s` unbound on purpose. |
| 1.6.2 | Fixed the POSIX command being built for every host and discarded on Windows ones, which aborted `-TargetPlatform Windows -PosixTransport Direct`. Corrected several help statements that no longer matched the code. |
| 1.6.1 | `-UseSftp` notices a competing writer: re-reads before the overwrite and merges, re-reads after and reports a missing key as a failure. |
| 1.6.0 | Fixed two Windows PowerShell 5.1 faults - unescaped quotes producing an unbounded remote loop, and a BOM on piped stdin. Fixed IPv6 platform detection on 5.1. |
| 1.5.0 | `-UseAgentKeys`, `-UseSftp`, `-ForceInstall`. Fixed the probe treating "some key authenticates" as "this key authenticates". |
| 1.4.0 | `-SshOption`, `-RemoteAuthorizedKeysPath`, SELinux `restorecon`, `sh` wrapper for non-POSIX login shells, `-StrictHostKeyChecking`, `-RequireExistingKey`, client-config awareness, encrypted-key detection. |
| 1.3.0 | Windows OpenSSH Server support: `-TargetPlatform`, `-WindowsKeyLocation`. |
| 1.2.0 | `-CreateSampleHostFile`. |
| 1.1.0 | `-UpdateSshConfig` / `-ConfigAlias`. |
| 1.0.0 | Initial version. |

---

## Known-unverified areas

Stated so nobody assumes more coverage than exists.

- **PowerShell 6.0-7.1** - untested. The capability check treats them as unable to escape
  quotes and forces the encoded transport, which is the safe assumption.
- **`ssh -v` output parsing** - the `Server accepts key` line is not a stable interface. Verified
  against OpenSSH 9.5p2 (client) and 9.9 (server). A probe with no fingerprint to match falls
  back to "some key authenticated".
- **Concurrent `-UseSftp` against one file** - lossy by design, as described above. Detected and
  reported, not prevented.
