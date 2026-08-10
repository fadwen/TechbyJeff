#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys an SSH public key to remote hosts for passwordless authentication

.DESCRIPTION
    A Windows-friendly equivalent of ssh-copy-id.

    Core Functionality:
    - Creates an ed25519 (or RSA 4096) key pair at -KeyPath when one is missing, which
      defaults to %USERPROFILE%\.ssh\id_ed25519
    - Hardens the private key ACL so Windows OpenSSH will accept it
    - Detects whether each target runs a POSIX or a Windows OpenSSH server and installs
      the key the way that platform expects
    - Appends the public key idempotently to ~/.ssh/authorized_keys on POSIX hosts, or to
      administrators_authorized_keys on Windows hosts where the account is an administrator
    - Runs the POSIX install through sh, so an account whose login shell is csh, tcsh or
      fish is handled rather than failing on shell syntax
    - Relabels the file for SELinux where restorecon exists, which is what makes a restored
      or migrated home directory work without manual intervention
    - Verifies passwordless access before and after installation, confirming from ssh's own
      report that the key being deployed is the one the server accepted rather than some
      other identity the client config also offers
    - Reports what the remote host said when that verification fails
    - Honours the SSH client config: a Host block's User and Port are used rather than
      overridden, so an alias written by -UpdateSshConfig works on the next run
    - Emits a result object per host for reporting and pipeline consumption

    Coming from ssh-copy-id:
    The target is positional, so "Deploy-SshKey.ps1 root@server1" reads the same way
    "ssh-copy-id root@server1" does. Every option has an equivalent:

        ssh-copy-id     here                            short form
        -i FILE         -KeyPath                        -i, -IdentityFile
        -o OPTION       -SshOption                      -o, -Option
        -p PORT         -Port                           -p
        -t PATH         -RemoteAuthorizedKeysPath       -TargetPath
        -F FILE         -SshConfigFile                  -ConfigFile
        -s              -UseSftp                        -Sftp
        -x              -TraceRemoteCommand             -x
        -f              -ForceInstall                   (none - see below)
        -n              -WhatIf                         (none - a common parameter)
        (no -i)         -UseAgentKeys

    Four single-letter flags - -f, -F, -t and -s - are deliberately left unbound, because
    PowerShell would resolve each into something other than what an ssh-copy-id user means:
    - -f and -F are one and the same parameter here, since PowerShell parameter names are
      not case-sensitive. ssh-copy-id's distinction between "force" and "config file"
      cannot survive that, so neither letter is bound
    - -t would silently bind -RemoteAuthorizedKeysPath, so "-t Windows" - the obvious way
      to ask for a Windows target - would install to a relative path named Windows
    - -s would bind the -UseSftp switch and leave the next word to be read as a hostname
    Left unbound, each fails with PowerShell's "parameter name is ambiguous" error listing
    the real candidates, which is the safe outcome. Use the full names instead.

    One difference in meaning is worth knowing: ssh-copy-id's -f forces the install, and
    the equivalent here is -ForceInstall. This script's -Force is a different and
    destructive thing - it deletes the key pair at -KeyPath and generates a new one.

    Business Value:
    - Removes interactive password entry from routine administration and automation
    - Provides a repeatable, auditable key-distribution process for mixed Windows/Linux estates
    - Supports unattended job accounts without storing reusable passwords in scripts

    Use Cases:
    - Onboarding a new Linux, Unix or Windows Server host into an existing automation fleet
    - Rotating an administrator key across a group of servers listed in a host file
    - Re-establishing passwordless access after a host rebuild

    Dependencies:
    - Windows OpenSSH client (ssh.exe and ssh-keygen.exe) available on PATH
    - Password authentication temporarily enabled on each target host
    - Network access to each target host on the configured SSH port
    - POSIX targets need base64 only when the client cannot escape quotes in a native
      command line - Windows PowerShell 5.1, PowerShell 6.0-7.1, or 7.2+ set to Legacy
      argument passing. On 7.2+ with default settings the script is sent as an ordinary
      shell command and the target needs nothing beyond a POSIX shell. See -PosixTransport
    - sftp.exe locally and the sftp subsystem remotely, only when -UseSftp is used

    Performance Considerations:
    - Sequential processing; roughly 2-5 seconds per host plus password entry time
    - One install session per host, plus a probe before and after it for every key being
      deployed: three sessions for a single key, and 2N+1 when -UseAgentKeys carries N
    - One ssh -G per host when a client config exists, which reads that config and opens
      no network connection
    - One unauthenticated TCP banner read per host when the platform is auto-detected
    - Negligible memory footprint regardless of host count

    Side Effects:
    - Creates %USERPROFILE%\.ssh and a key pair when none exists
    - Replaces the private key ACL with a single full-control entry for the current user
    - Creates or appends ~/.ssh/authorized_keys on each POSIX target and sets 700/600 permissions
    - On Windows targets, creates or appends %ProgramData%\ssh\administrators_authorized_keys
      (administrators) or %USERPROFILE%\.ssh\authorized_keys, and resets that file's ACL
    - With -UpdateSshConfig, creates or edits the local SSH client config
    - With -CreateSampleHostFile, writes a host-list template and performs no deployment

.PARAMETER ComputerName
    [System.String[]] (Optional, Accepts Pipeline Input ByValue and ByPropertyName)
    Aliases: -Hosts

    One or more target hosts. Each entry may be "host", "user@host", or an IP address.
    Entries without "user@" are combined with the -User value.

    Pipeline Behaviour:
    - Strings bind directly; objects bind through a ComputerName or Hosts property
    - Hosts are gathered as they arrive and deployed once collection finishes, so the key
      is prepared a single time and one summary covers the whole run
    - A pipeline-driven run never prompts for hosts, even when the pipeline is empty

    Validation Rules:
    - Normalized entries must match ^[A-Za-z0-9._-]+(@[A-Za-z0-9._-]+)*@[A-Za-z0-9._:\[\]-]+$
    - The repeated group allows a UPN login such as admin@corp.example@server1, because ssh
      splits user@host on the LAST '@' and that is a normal account name on AD-joined hosts
    - The host part also accepts ':' and brackets, so an IPv6 literal is a valid target in
      either the bracketed or the bare form
    - Entries beginning with '-' are rejected so they cannot be parsed as ssh options
    - Invalid entries are reported as warnings and skipped, not treated as fatal

    Business Context: Accepts the same shorthand administrators already use with ssh,
    so existing inventory lists can be pasted in without reformatting.

    Examples: "server1", "admin@server2", "10.0.0.15", "admin@corp.example@dc01"

.PARAMETER HostFile
    [System.String] (Optional, No Pipeline Support)

    Path to a text file containing one host (or user@host) per line. Blank lines and
    lines beginning with '#' are ignored.

    Business Context: Allows host inventories to be version-controlled and reused
    across deployment runs rather than retyped on the command line.

    Examples: ".\hosts.txt", "C:\Inventory\linux-servers.txt"

.PARAMETER User
    [System.String] (Optional, No Pipeline Support)

    Default username applied to any host that does not already specify "user@".
    Defaults to the current Windows username.

    Business Context: Most estates use a consistent administrative account name, so a
    single default avoids repeating it for every host.

    Examples: "jeff", "ansible", "root"

.PARAMETER Port
    [System.Int32] (Optional, No Pipeline Support)
    Aliases: -p

    SSH port used for every target host. Valid range is 1-65535. Default is 22.

    Validation Rules:
    - Sent to ssh as -p only when the parameter is named explicitly. Left unset, ssh resolves
      the port itself, which is what allows a Host block in the client config to specify one
    - When named, it applies to every host in the run and overrides any config value

    Business Context: Supports estates that relocate SSH off port 22 as a hardening measure.
    Leaving it unset is what makes "ssh <alias>" and this script agree on the same port.

    Examples: 22, 2222

.PARAMETER TargetPlatform
    [System.String] (Optional, No Pipeline Support)

    Selects the installation method. Valid values are 'Auto' (default), 'Linux' and 'Windows'.

    Validation Rules:
    - 'Auto' reads each server's SSH identification banner, which is sent before
      authentication, and treats an OpenSSH_for_Windows banner as a Windows target
    - A host whose banner cannot be read is reported and treated as POSIX
    - An explicit value applies to every host in the run and performs no probe

    Business Context: Mixed estates can be deployed from one host list without splitting
    it by operating system, while an explicit value covers hosts behind a proxy or a
    banner-suppressing appliance.

    Examples: "Auto", "Windows", "Linux"

.PARAMETER WindowsKeyLocation
    [System.String] (Optional, No Pipeline Support)

    Chooses which authorized_keys file receives the key on a Windows target. Valid values
    are 'Auto' (default), 'Administrators' and 'UserProfile'. Ignored for POSIX targets.

    Validation Rules:
    - 'Auto' uses %ProgramData%\ssh\administrators_authorized_keys when the remote account
      belongs to the local Administrators group, and %USERPROFILE%\.ssh\authorized_keys otherwise
    - 'Administrators' falls back to the user file, with a message, when the SSH session
      lacks the rights to write under %ProgramData%
    - Group membership is evaluated by SID, matching how sshd itself resolves its
      "Match Group administrators" rule

    Business Context: The default sshd_config shipped by Microsoft ignores an administrator's
    profile authorized_keys file, so a key written there silently fails to work. Sites that
    have removed that Match block need 'UserProfile' instead.

    Examples: "Auto", "Administrators", "UserProfile"

.PARAMETER KeyPath
    [System.String] (Optional, No Pipeline Support)
    Aliases: -i, -IdentityFile

    Path to the private key. The public key is expected at <KeyPath>.pub. Defaults to
    %USERPROFILE%\.ssh\id_ed25519.

    Validation Rules:
    - A path ending in .pub is treated as the public half and the private key beside it is
      used, matching the habit ssh-copy-id -i encourages
    - A path containing a double quote is rejected, because it reaches ssh-keygen inside a
      pre-quoted argument string
    - When the private key is missing but its .pub exists, the run stops rather than letting
      ssh-keygen overwrite a public key whose private half lives in an agent or on a token
    - When neither exists, a new key is generated unless -RequireExistingKey is specified

    Business Context: Lets you maintain separate keys per environment (production,
    lab, customer) instead of reusing a single identity everywhere.

    Examples: "C:\Users\jeff\.ssh\id_ed25519", "D:\Keys\prod_admin"

.PARAMETER RemoteAuthorizedKeysPath
    [System.String] (Optional, No Pipeline Support)
    Aliases: -TargetPath

    Absolute path to the authorized_keys file on the target, overriding the default choice
    for that platform. Equivalent to ssh-copy-id's -t.

    Validation Rules:
    - Must match ^[A-Za-z0-9._~/\\:%+-]+$ so it cannot carry shell or PowerShell syntax
    - A leading ~/ is translated to $HOME/ for POSIX targets, which do not expand a tilde
      inside the quoted assignment the install command uses
    - The directory is created if missing, but is not chmod 700'd: a shared location such as
      /etc/ssh/authorized_keys would then deny every other account its own keys
    - On a Windows target this replaces both candidate files, and the automatic fallback from
      administrators_authorized_keys to the profile file is disabled

    Business Context: Hardened builds frequently move AuthorizedKeysFile out of the user's
    profile. Without this the key installs into a file sshd never reads, and the run reports
    a failure that looks like a permissions problem.

    Examples: "/etc/ssh/authorized_keys/jeff", "~/.ssh/automation_keys"

.PARAMETER SshOption
    [System.String[]] (Optional, No Pipeline Support)
    Aliases: -o, -Option

    Additional ssh options in Name=Value form, passed through as -o to every session this
    script opens.

    Validation Rules:
    - Each entry must match ^[A-Za-z][A-Za-z0-9]*=[^\r\n]+$
    - Entries are placed ahead of this script's own options, because ssh keeps the first
      value it obtains for a setting. That ordering is what allows them to override defaults

    ProxyJump needs the jump host's own identity arranged separately:
    - "-SshOption ProxyJump=bastion" on its own is usually NOT enough. ssh applies -i and
      IdentitiesOnly to the FINAL destination; the connection to the jump host is resolved
      independently and never sees the key named by -KeyPath
    - The visible symptom is a run that appears to hang. ssh is waiting for the jump host's
      password on the console, and with -Credential it is not even that: the credential
      answers the destination, not the hop
    - Give the bastion an IdentityFile in a config and point -SshConfigFile at it. Then both
      legs authenticate by key and the run is unattended:

        Host bastion
            HostName bastion.example.com
            User jump
            IdentityFile C:\keys\id_ed25519

        Host app01
            HostName 10.0.0.15
            User deploy
            ProxyJump bastion

        .\Deploy-SshKey.ps1 -ComputerName app01 -SshConfigFile .\estate.ssh_config

    - An agent holding the jump host's key works equally well, since ssh consults the agent
      for the hop

    Business Context: The only way to reach a host through a bastion, or to pin an
    authentication method. Without it, an estate that requires a jump host cannot be
    deployed to at all.

    Examples: "ProxyJump=bastion.example.com", "PreferredAuthentications=password"

.PARAMETER StrictHostKeyChecking
    [System.String] (Optional, No Pipeline Support)

    Host key policy for every session. Valid values are 'accept-new' (default), 'yes',
    'no' and 'ask'.

    Validation Rules:
    - 'accept-new' trusts an unknown host on first contact, which is convenient but means
      the account password is typed into whatever answered
    - 'yes' refuses an unknown host outright and requires known_hosts to be pre-populated
    - 'ask' prompts, and cannot be used in an unattended run

    Business Context: First contact is exactly when a man-in-the-middle would capture the
    password being used to install the key. Deployments across an untrusted network should
    pre-populate known_hosts and pass 'yes'.

    Examples: "accept-new", "yes"

.PARAMETER PosixTransport
    [System.String] (Optional, No Pipeline Support)

    How the install script reaches a POSIX target. Valid values are 'Auto' (default),
    'Direct' and 'Encoded'. Not consulted at all for a Windows target, which always uses
    powershell.exe -EncodedCommand, nor with -UseSftp, which sends a file and no command.

    Validation Rules:
    - 'Direct' sends an ordinary shell command and needs nothing on the target beyond a
      POSIX shell, but depends on this PowerShell escaping embedded double quotes correctly
    - 'Encoded' sends the script base64-encoded, which no client-side quoting can damage,
      at the cost of requiring base64 on the target
    - 'Auto' picks Direct when this host escapes quotes correctly and Encoded when it does
      not. That is a capability test, not a version test: PowerShell only gained correct
      escaping in 7.2, and 7.2+ can be put back into the old behaviour by setting
      $PSNativeCommandArgumentPassing to 'Legacy'
    - 'Direct' is refused outright on a client that mangles quotes. The command would still
      run there, but each key would arrive split into fragments and be appended as several
      bogus entries while the run reported success

    Business Context: Windows PowerShell 5.1 shreds the quoting of any native command line
    containing double quotes, which made the direct form unusable there. Rather than impose
    the base64 dependency on everyone, the encoded form is used only where it is needed.

    Examples: "Auto", "Encoded"

.PARAMETER KeyType
    [System.String] (Optional, No Pipeline Support)

    Algorithm used when generating a new key. Valid values are 'ed25519' (default)
    and 'rsa', which generates a 4096-bit key. Ignored when a key already exists.

    Business Context: ed25519 is preferred for modern hosts; rsa remains available for
    legacy appliances that have not adopted Ed25519 support.

    Examples: "ed25519", "rsa"

.PARAMETER Comment
    [System.String] (Optional, No Pipeline Support)

    Comment embedded in a newly generated public key. Defaults to
    <username>@<computername>. Restricted to letters, digits, spaces and . _ - @
    so the value cannot break out of the ssh-keygen argument string.

    Business Context: The comment is what appears in authorized_keys on every target
    host, so it is the primary way auditors attribute a key to its owner.

    Examples: "jeff@admin-ws", "automation@build-server"

.PARAMETER Force
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Overrides the safeguard for whichever operation is running:
    - Normally: regenerates the key pair even when one exists at KeyPath, deleting the
      existing private and public keys first
    - With -CreateSampleHostFile: overwrites an existing file without prompting

    Business Context: Used for scheduled key rotation or after a suspected compromise.
    Destructive: any host still trusting the old key will stop accepting it.

    Examples: -Force, -Force:$false

.PARAMETER RequireExistingKey
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Fails rather than generating a key pair when none exists at -KeyPath.

    Business Context: Generating on demand is convenient for a first run and dangerous for
    every run after it. A mistyped -KeyPath, or a default that does not match the key the
    operator actually uses, otherwise mints a brand new identity, deploys it, and reports
    success - leaving an unaccounted-for key trusted across the estate. ssh-copy-id has no
    equivalent hazard because it never generates. Use this in automation.

    Examples: -RequireExistingKey

.PARAMETER ForceInstall
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Installs the key even when the host already accepts it, skipping the pre-check.
    Equivalent to ssh-copy-id's -f.

    Validation Rules:
    - Implied by -RemoteAuthorizedKeysPath. The pre-check answers "does this key already
      grant access", not "is it in the file you named", so on a host reachable through some
      other authorized_keys file it would otherwise skip the install that was asked for
    - The remote install remains idempotent, so a redundant run adds no duplicate entry

    Business Context: Needed when the destination file matters as much as the access - for
    example moving a key from a profile file into administrators_authorized_keys, or
    seeding a second file before sshd_config is repointed at it.

    Examples: -ForceInstall

.PARAMETER UseAgentKeys
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Installs every identity the ssh agent currently holds, instead of the single key at
    -KeyPath. This is what ssh-copy-id does when it is given no -i.

    Validation Rules:
    - Fails when the agent holds nothing, rather than quietly falling back to a file
    - No key is generated, read from disk, or ACL-hardened; the agent is the only source
    - Each identity is probed separately, so a host already trusting some of them receives
      only the remainder
    - -UpdateSshConfig is skipped with a warning: a Host block records one IdentityFile,
      and there is no single file to name
    - On a Windows target the whole set must fit one 8191-character command line, so a few
      ed25519 keys are fine where several RSA 4096 keys are not

    Business Context: An administrator with a laptop key, a YubiKey and a break-glass key
    otherwise has to run the script three times per host. It also covers keys whose private
    half is on a token and so has no file for -KeyPath to point at.

    Examples: -UseAgentKeys

.PARAMETER UseSftp
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)
    Aliases: -Sftp

    Installs the key over the SFTP subsystem instead of running a command on the target.
    Equivalent to ssh-copy-id's -s. Ignored, with a message, for Windows targets.

    Validation Rules:
    - Requires sftp.exe on PATH and the sftp subsystem enabled on the target
    - The merge that the shell would normally do remotely happens locally instead, so the
      whole file is downloaded, updated and written back
    - Two sftp sessions are used, because a single batch cannot pause for that merge, and a
      third only when the read taken immediately before the overwrite shows the file has
      changed and that change has to be merged back in. With password authentication each
      session is a prompt, so expect two, or three when a conflict is repaired
    - If the upload fails, the copy downloaded beforehand is written to a temp file and its
      path reported, because rewriting a whole file cannot be made atomic here
    - Replacing the whole file means anything written by someone else in between - another
      run, or a person editing by hand - would be destroyed. Two checks ride along in the
      existing batches, at no extra session cost: the file is read once more immediately
      before the overwrite, and if it has changed that version is merged and rewritten; and
      it is read back afterwards to confirm the keys are actually present. A key that is
      not there is reported as a failure rather than a success
    - Those checks narrow the window but cannot close it. A writer that replaces the file
      after this run's final read is invisible to it, so heavy concurrent use of -UseSftp
      against one file can still lose an entry. The exec path has no such window, because
      it appends
    - Ignored for Windows targets: sftp can write the file but cannot set the ACL sshd
      insists on for administrators_authorized_keys, so the key would install and still fail

    Business Context: Reaches accounts that cannot execute a command at all - a restricted
    shell, a ForceCommand internal-sftp, or a shell of /usr/sbin/nologin. The default exec
    path fails outright on those, which is the case ssh-copy-id -s exists for.

    Examples: -UseSftp

.PARAMETER CreateSampleHostFile
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Writes a commented host-list template and exits without deploying anything.
    The template is written to the -HostFile path when one is supplied, otherwise to
    .\hosts.example.txt in the current directory.

    Validation Rules:
    - Every sample entry is commented out, so the generated file targets no hosts
    - An existing file at the target path prompts before being overwritten
    - -Force overwrites without prompting

    Business Context: Documents the accepted entry formats and validation rules at the
    point of use, so operators building a host list do not have to read the script.

    Examples: -CreateSampleHostFile, -CreateSampleHostFile -HostFile .\hosts.txt

.PARAMETER UpdateSshConfig
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Adds a Host block to the SSH client config for every host that ends the run
    reachable, recording the user, port and identity file so plain "ssh <host>"
    connects correctly without repeating "user@".

    Validation Rules:
    - Hosts that finish with Status 'Failed' are skipped
    - An existing block matching the host prompts for confirmation before replacement
    - Answering No leaves the existing block untouched and reports it

    Business Context: Without this, "ssh <host>" falls back to the local Windows
    username, which fails on hosts where the administrative account differs.

    Examples: -UpdateSshConfig

.PARAMETER ConfigAlias
    [System.String] (Optional, No Pipeline Support)

    Short name to add alongside the host in the generated Host block, letting you
    connect with "ssh <alias>". Only valid for a single target; ignored with a warning
    when multiple hosts are processed. Requires -UpdateSshConfig.

    Validation Rules:
    - Must match ^[A-Za-z0-9._-]+$

    Business Context: Memorable aliases ('pve', 'build01') are faster and less
    error-prone than IP addresses for hosts administrators touch daily.

    Examples: "pve", "build01"

.PARAMETER ForceConfigUpdate
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

    Replaces a conflicting Host block without asking for confirmation. Requires
    -UpdateSshConfig. Unrelated blocks in the file are still preserved.

    Business Context: Unattended runs cannot answer a prompt, and without this the
    script deliberately leaves existing entries alone. Use it only where overwriting
    is the intended, reviewed behaviour.

    Examples: -ForceConfigUpdate

.PARAMETER SshConfigPath
    [System.String] (Optional, No Pipeline Support)

    Path the -UpdateSshConfig Host block is written to. Defaults to %USERPROFILE%\.ssh\config.
    The file and its parent directory are created when missing.

    Validation Rules:
    - This is a write target only. Host resolution always reads %USERPROFILE%\.ssh\config,
      because that is the file ssh itself reads; pointing ssh at another one with -F would
      also suppress the system-wide config, and would fail outright on a file -UpdateSshConfig
      has not created yet

    Business Context: Allows the entry to be staged into a non-default config for
    review, or written to a profile used by a service account, without changing which
    configuration the run itself resolves against.

    Examples: "C:\Users\jeff\.ssh\config"

.PARAMETER SshConfigFile
    [System.String] (Optional, No Pipeline Support)
    Aliases: -ConfigFile

    Client config that every ssh and sftp session in this run reads, instead of the default
    %USERPROFILE%\.ssh\config. Reaches ssh as -F, and is the equivalent of ssh-copy-id's -F.

    Validation Rules:
    - The file must already exist. ssh exits 255 on a -F path it cannot open, which surfaces
      as an unexplained transport failure, so the run stops here with a clear message instead
    - -F is ssh's own semantics, so naming a file also suppresses the system-wide config.
      That is the point of the option, but it means a setting inherited from
      /etc/ssh/ssh_config or %ProgramData%\ssh\ssh_config no longer applies
    - This is the file the run READS. -SshConfigPath is the file -UpdateSshConfig WRITES.
      Supplying only this one points both at it, since using one config for a run and then
      recording the result in another is almost never what was meant
    - Host, User and Port resolution consults this file too, so an alias defined in it
      resolves exactly as it would for plain ssh

    Business Context: Lets a run be driven by a purpose-built config - a customer's jump-host
    definitions, a service account's profile, or a reviewed file in source control - without
    disturbing the operator's own ~/.ssh/config. Without it a shared workstation has to have
    its real config edited before every deployment.

    Examples: "D:\Configs\customer-a.ssh_config", "C:\Automation\deploy.ssh_config"

.PARAMETER TraceRemoteCommand
    [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)
    Aliases: -x

    Turns on command tracing inside the install script on the target and echoes the trace
    back with the rest of the remote output. Equivalent to ssh-copy-id's -x.

    Validation Rules:
    - POSIX targets run the install body under 'set -x', so every command appears on stderr
      as it executes
    - Windows targets run it under 'Set-PSDebug -Trace 1', which prefixes each statement
      with DEBUG:
    - With -UseSftp there is no remote script to trace, so sftp itself is put into verbose
      mode with -v instead
    - Tracing echoes the public keys being installed. They are public, but the trace also
      names paths and home directories, so it is diagnostic output rather than something to
      leave on in a logged pipeline

    Business Context: When a host reports the key was written and sshd still refuses it, the
    remaining possibilities - wrong file, wrong permissions, a failed restorecon - are all
    invisible from the client. This is the one switch that shows what the target actually did.

    Examples: -TraceRemoteCommand

.PARAMETER Credential
    [System.Management.Automation.PSCredential] (Optional, No Pipeline Support)

    Password used to authenticate the install session on hosts that do not yet trust the
    key. Supplying it is what makes an unattended run possible: without it ssh stops at its
    own password prompt, which no amount of piping can answer.

    Validation Rules:
    - Only the password is used. The account is already decided per host by "user@host", the
      client config, or -User, and letting a credential override that would silently retarget
      a different account on every host in the run
    - The pre-check and post-check are unaffected. Both keep BatchMode=yes, so a password can
      never make verification pass; the question they ask is whether the KEY works
    - Password prompts are limited to one per host. The helper answers with the same value
      every time, so the default of three turns a wrong password into a threefold delay and
      three failed logins against whatever counts them
    - Accepts a user name instead of a credential object, in which case PowerShell prompts
      for the password. That is a convenience for interactive use and defeats the purpose in
      automation, where a fully populated credential should be passed

    How the password reaches ssh:
    - ssh reads passwords from the console device, never from stdin. OpenSSH's own escape
      hatch is SSH_ASKPASS: it runs a named program and reads one line of output. This script
      writes that helper to a temporary directory and points ssh at it
    - The helper contains no password. It echoes an environment variable whose name is
      generated per run, so nothing secret is written to disk
    - That variable is never set on this process. Each ssh and sftp session is started
      through ProcessStartInfo with the value placed in the CHILD's environment block only,
      so no other child this script starts can inherit it and it cannot be read out of this
      process at all. The credential is carried as a SecureString until the moment a child
      is launched
    - The plaintext therefore exists in exactly one place: the ssh process that needs it,
      and the helper ssh spawns to ask, for the length of that one session

    Residual exposure, stated plainly:
    - The password still exists in the memory of the ssh process, and briefly as a .NET
      string in this one while the child is being started. An attacker already running code
      as this user can read either. Nothing can remove that - ssh has to receive the
      password somehow - but at that point they can equally read the private key being
      deployed, so the password is not the weak link
    - Credential Guard does not apply. It isolates LSASS-held domain secrets; a password
      this script holds was never in LSASS, so it is a different mechanism protecting a
      different asset, not a control that covers this
    - Prefer a bootstrap key, cloud-init, or a configuration-management channel where one
      exists. Use this where a password really is the only way in, and rotate it afterwards
    - Store it in SecretManagement rather than a script. Get-Secret returns exactly the type
      this parameter takes

    Business Context: Onboarding and CI/CD are precisely the cases where nobody is present
    to type a password, and also the cases where a new host has never seen the key. Without
    this, automation can only re-run against hosts that already trust it.

    Examples: -Credential (Get-Secret -Name 'onboarding'), -Credential (Get-Credential root)

.PARAMETER CorrelationId
    [System.String] (Optional, No Pipeline Support)

    Identifier used to correlate verbose output, warnings, errors and result objects
    from a single execution. A new GUID is generated when not supplied.

    Business Context: Pass an existing identifier when this script runs as one step of
    a larger orchestration so all activity shares a single audit trail.

    Examples: "8f14e45f-ceea-467a-9f8b-1a2b3c4d5e6f"

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName server1, admin@server2 -User jeff

    DESCRIPTION: Installs the default key on two hosts, using 'jeff' for server1 and
                 'admin' for server2
    OUTPUT: One SshKeyDeploymentResult object per host with Status of Installed,
            AlreadyConfigured or Failed
    DURATION: Approximately 5-10 seconds per host plus password entry
    USE CASE: Onboarding a small number of new servers into an automation fleet

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 root@server1 -i D:\Keys\prod_admin -p 2222 -o ConnectTimeout=10

    DESCRIPTION: The same line an ssh-copy-id user would already write. The target is
                 positional and the short forms mean the equivalent command needs almost
                 no translation
    OUTPUT: One result object for server1
    USE CASE: Anyone arriving from ssh-copy-id who would rather not learn new spellings

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\hosts.txt -Port 2222 -KeyPath D:\Keys\prod_admin

    DESCRIPTION: Deploys a dedicated production key to every host listed in hosts.txt
                 over a non-standard SSH port, generating the key if it does not exist
    OUTPUT: Result objects for each host in the file; invalid lines raise warnings
    USE CASE: Bulk enablement of passwordless access for a hardened estate

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\hosts.txt -KeyPath D:\Keys\prod_admin -Force

    DESCRIPTION: Key rotation. -Force deletes the pair at -KeyPath and generates a new one
                 before deploying it, so run it against the whole estate in one pass or
                 some hosts will trust an identity you no longer hold
    OUTPUT: Result objects showing KeysInstalled = 1 for each host that took the new key
    USE CASE: Scheduled rotation, or replacing a key after a suspected compromise
    NOTE: Destructive, and it does not tidy up. The superseded key stays in every
          authorized_keys until it is removed separately, and -Force is NOT ssh-copy-id's
          -f, which is -ForceInstall here

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\hosts.txt -WhatIf

    DESCRIPTION: Previews the deployment without generating keys or modifying any host
    OUTPUT: ShouldProcess messages for each key generation and installation, and per host
            the identities that would have been added with their fingerprints, which is
            what ssh-copy-id -n reports
    USE CASE: Change-management review before executing against production hosts

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -CreateSampleHostFile -HostFile .\hosts.txt

    DESCRIPTION: Writes a commented host-list template and exits without deploying
    OUTPUT: .\hosts.txt containing the accepted formats and validation rules
    USE CASE: First run, before building an inventory to deploy against

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName root@10.20.30.40 -UpdateSshConfig -ConfigAlias pve

    DESCRIPTION: Deploys the key and records a Host block so both "ssh pve" and
                 "ssh 10.20.30.40" connect as root without prompting for a username
    OUTPUT: Result object with SshConfigUpdated = True
    USE CASE: Standing up day-to-day access to a hypervisor or jump host

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName Administrator@fs01 -TargetPlatform Windows

    DESCRIPTION: Deploys to a Windows Server running OpenSSH Server, skipping the banner
                 probe and writing to administrators_authorized_keys because the account
                 is a local administrator
    OUTPUT: Result object with Platform = Windows and Status of Installed
    USE CASE: Enabling key-based automation against a Windows file or application server

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\mixed-estate.txt -UpdateSshConfig

    DESCRIPTION: Deploys to a host list containing both Linux and Windows servers,
                 detecting each host's platform from its SSH banner
    OUTPUT: One result object per host, each reporting the platform that was detected
    USE CASE: Single-pass key rollout across a mixed estate

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName app01 -SshOption 'ProxyJump=bastion.example.com'

    DESCRIPTION: Deploys through a jump host to a target with no direct route from here
    OUTPUT: Result object for app01; the banner probe cannot traverse the proxy, so the
            platform falls back to POSIX unless -TargetPlatform is stated
    USE CASE: Estates where production is only reachable through a bastion

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\prod.txt -RequireExistingKey `
            -StrictHostKeyChecking yes -KeyPath D:\Keys\prod_admin

    DESCRIPTION: Unattended rollout that refuses to invent a key and refuses to trust an
                 unknown host key, so known_hosts must already be populated
    OUTPUT: Result objects per host; the run fails fast if the key or a host key is missing
    USE CASE: Scheduled key distribution where silent surprises are unacceptable

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName jeff@rhel9 -RemoteAuthorizedKeysPath /etc/ssh/authorized_keys/jeff

    DESCRIPTION: Installs into a site-wide AuthorizedKeysFile location instead of the
                 profile, leaving the shared directory's permissions alone
    OUTPUT: Result object with RemoteKeyFile reporting the path the host wrote
    USE CASE: Hardened builds that move authorized_keys out of the user's home directory

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\hosts.txt -UseAgentKeys

    DESCRIPTION: Installs every identity currently loaded in the ssh agent, probing each
                 one separately so hosts already trusting some receive only the rest
    OUTPUT: Result objects whose KeysInstalled reports the entries each host appended
    USE CASE: An administrator with a laptop key, a token and a break-glass key who would
              otherwise run the script once per key

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName backup@vault01 -UseSftp

    DESCRIPTION: Installs over the SFTP subsystem for an account whose shell will not run a
                 command, downloading and rewriting authorized_keys rather than appending
    OUTPUT: Result object with RemoteKeyFile set to the path that was written
    USE CASE: Accounts restricted with ForceCommand internal-sftp or a nologin shell

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\customer-a.txt -SshConfigFile D:\Configs\customer-a.ssh_config

    DESCRIPTION: Drives the whole run from a purpose-built client config, so aliases and
                 jump hosts defined only in that file resolve, and the operator's own
                 ~/.ssh/config is neither read nor changed
    OUTPUT: Result objects whose Port reflects whatever that config resolved
    USE CASE: Managing several customers or environments from one workstation without
              editing a shared ~/.ssh/config before every deployment

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -ComputerName jeff@rhel9 -TraceRemoteCommand

    DESCRIPTION: Runs the remote install under set -x and echoes the trace back, showing
                 which file was chosen, whether the key was already present, and how the
                 chmod and restorecon fared
    OUTPUT: The remote command trace interleaved with the usual status lines
    USE CASE: A host that reports the key was written while sshd still refuses it, where
              the remaining causes are all invisible from the client

.EXAMPLE
    PS> Get-Content .\new-estate.txt |
            .\Deploy-SshKey.ps1 -RequireExistingKey -Credential (Get-Secret -Name 'onboarding')

    DESCRIPTION: Fully unattended onboarding. The credential answers the password prompt on
                 hosts that have never seen the key, which is the one thing that otherwise
                 stops an automated run dead
    OUTPUT: Result objects; hosts that already trusted the key never use the password
    USE CASE: A scheduled or pipeline-triggered job enrolling newly built hosts

.EXAMPLE
    PS> Get-Content .\new-estate.txt | .\Deploy-SshKey.ps1 -RequireExistingKey

    DESCRIPTION: Streams hosts in rather than naming a file, which is what lets an
                 inventory come from anywhere - a CMDB query, a build artifact, a
                 previous pipeline stage
    OUTPUT: One result object per host, emitted after every host has been processed
    USE CASE: Onboarding automation where the host list is produced by an earlier step

.EXAMPLE
    PS> Get-ADComputer -Filter { OperatingSystem -like '*Server*' } |
            Select-Object @{ Name = 'ComputerName'; Expression = { $_.DNSHostName } } |
            .\Deploy-SshKey.ps1 -RequireExistingKey -StrictHostKeyChecking yes |
            Where-Object Status -eq 'Failed' |
            ForEach-Object { New-RemediationTicket -Host $_.ComputerName -Trace $_.CorrelationId }

    DESCRIPTION: Binds by property name straight from a directory query, refuses to invent
                 a key, refuses an unknown host key, and turns each failure into a ticket
                 carrying the run's correlation id
    OUTPUT: Result objects; only the failures reach the ticket step
    USE CASE: Scheduled lifecycle enforcement across a domain, where the run is unattended
              and must never stop to ask a question

.EXAMPLE
    PS> .\Deploy-SshKey.ps1 -HostFile .\hosts.txt |
            Where-Object Status -eq 'Failed' |
            Export-Csv .\ssh-key-failures.csv -NoTypeInformation

    DESCRIPTION: Pipeline integration that captures only the hosts needing follow-up
    OUTPUT: CSV report of failed hosts including the shared CorrelationId
    BUSINESS CASE: Feeds remediation tickets directly from the deployment run

.INPUTS
    System.String[]

    Target hosts, bound to -ComputerName. Strings are taken directly, and objects carrying a
    ComputerName or Hosts property bind by property name, so an inventory can be piped in
    without being reshaped first:

        Get-Content .\hosts.txt | .\Deploy-SshKey.ps1
        Get-ADComputer -Filter { OperatingSystem -like '*Server*' } |
            Select-Object @{ Name = 'ComputerName'; Expression = { $_.DNSHostName } } |
            .\Deploy-SshKey.ps1 -RequireExistingKey

    Every host is collected before anything is deployed, so one key is prepared, hosts are
    processed in the order they arrived, and a single summary is written at the end.

    A run fed by the pipeline never prompts. Supplying no hosts interactively asks for them;
    supplying none through a pipeline - an inventory query that matched nothing, say - fails
    with "No hosts were specified" instead, because there is nobody to answer.

    -CorrelationId is unrelated to any of this. It is an audit-trail identifier rather than a
    transport: it ties this run's verbose output, warnings, errors and result objects to one
    another, and accepts an existing value so a run forming one step of a larger
    orchestration shares that orchestration's trace.

.OUTPUTS
    SshKeyDeploymentResult

    A [PSCustomObject] per processed host containing:
    - ComputerName     [String]   Normalized user@host target
    - Platform         [String]   Linux or Windows, as detected or specified
    - Status           [String]   Installed, AlreadyConfigured, Failed or Skipped
    - Verified         [Boolean]  Whether passwordless access was proven with the deployed key
    - KeyPath          [String]   Private key used for the deployment
    - KeysInstalled    [Int32]    Entries the host actually appended, which is 0 on a forced
                                  run against a file that already held them
    - RemoteKeyFile    [String]   The file the host reported writing, when it reported one
    - Port             [Int32]    Port used, after the client config was consulted
    - RemoteMessage    [String]   Any warning the remote install returned, otherwise empty
    - SshConfigUpdated [Boolean]  Whether a Host block was written for this host
    - CorrelationId    [String]   Identifier shared by all output from this run
    - Timestamp        [DateTime] Completion time for the host

    Status and Verified are separate on purpose. A passphrase-protected key that no agent
    holds cannot be probed, because every probe runs with BatchMode. Installation is then
    taken from the remote host's own confirmation, giving Status 'Installed' with Verified
    false. 'Skipped' means -WhatIf declined the install, which is neither success nor failure.

    Status 'Installed' means the key was in the file and, unless Verified is false, working
    at the moment the run finished. It is not a claim about the future: another writer can
    remove the key afterwards. A run never reports 'Installed' for a key that was already
    missing when it checked - that case is reported as 'Failed'.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    PowerShell Version: 5.1+ (Windows PowerShell), 7.x+ (PowerShell)

    TROUBLESHOOTING:
    - Symptoms, causes and fixes: .\Troubleshoot-Deploy-SshKey.md
    - That file also carries the version history and the reasoning behind the design
      decisions that are not obvious from the code

    Windows PowerShell 5.1 is a deliberate floor, not an oversight. This is a workstation
    tool for administering mixed estates, and the machines that most need an ssh-copy-id
    equivalent are the ones that have never had pwsh installed. Everything here runs on
    both; where 5.1 behaves differently the script detects it rather than assuming.

    Security Considerations:
    - Generated keys have no passphrase; protect the workstation profile accordingly
    - The private key ACL is reduced to the current user's SID only, which is correct for
      Entra-joined and Microsoft-account logins where USERDOMAIN\USERNAME is not the account
    - StrictHostKeyChecking defaults to accept-new, which trusts a host key on first contact -
      the moment the account password is about to be typed. Pass -StrictHostKeyChecking yes
      with a pre-populated known_hosts when deploying across an untrusted network
    - Target entries are allowlist-validated to prevent ssh option injection from host files
    - Without -Credential, passwords are typed directly into the ssh client and are never
      held by this script at all
    - With -Credential, the password is handed to ssh through SSH_ASKPASS. The helper file
      holds no secret, only the name of a per-run environment variable, so nothing is written
      to disk. That variable is set on the ssh child's environment block and never on this
      process, so no other child inherits it and it cannot be read from here. What remains -
      the password in ssh's own memory - is unavoidable when handing a password to a child,
      and is the reason a bootstrap key is preferable wherever one exists. Note that
      Credential Guard is not a control here: it isolates LSASS-held domain secrets, which
      this is not
    - The Windows install command is sent as a base64 -EncodedCommand, so no value in it is
      re-parsed by cmd.exe and no quoting can be broken out of. Inside that payload the key
      and any remote path are single-quoted PowerShell literals with quotes doubled, and a
      multi-line value is refused outright rather than escaped
    - The POSIX install command has two forms and neither lets a key reach a shell as code.
      The encoded form carries nothing but a base64 blob, so neither the login shell nor the
      local command-line builder sees a quote, a space or a key; the keys are embedded in the
      decoded script as single-quoted literals using the '\'' idiom. The direct form, sent
      only from a client proven to escape quotes correctly, hands the keys to sh as positional
      parameters, so the script body itself holds no key text and the login shell sees each
      key as one single-quoted word. Either way a multi-line key is refused, not escaped
    - Keys written to a Windows target have inheritance removed and are granted only to
      SYSTEM plus either the Administrators group or the receiving account
    - -UpdateSshConfig never silently overwrites: an existing Host block is displayed and
      replaced only after explicit confirmation
    - -SshOption values reach ssh as separate arguments and are never passed through a shell,
      but they are operator input rather than host-file input and are not allowlisted beyond
      requiring Name=Value form

    Performance Characteristics:
    - Sequential host processing keeps password prompts readable and ordered
    - Three short-lived SSH sessions per host for a single key, and 2N+1 when -UseAgentKeys
      deploys N identities, because each one is probed separately before and after
    - Memory usage is independent of host count

    Known Limitations:
    (Causes and fixes for each of these are in .\Troubleshoot-Deploy-SshKey.md)
    - Requires password authentication to be enabled on the target during installation
    - Cannot deploy unattended to a host that needs a password unless -Credential supplies
      it. ssh reads its prompt from the console rather than stdin, so a run without it stops
      and waits no matter how the script was invoked
    - -Credential authenticates; it does not enrol. A host whose sshd refuses passwords
      outright still needs its first key delivered some other way
    - A wrong password can lock the deploying machine out of the target. OpenSSH 9.8+ enables
      PerSourcePenalties by default, which penalises the client ADDRESS for up to 600 seconds
      per source. A stale credential in a fleet run does this on every host it touches
    - Does not remove superseded keys from authorized_keys when using -Force
    - Cannot deploy to hosts that require keyboard-interactive MFA
    - -UseSftp needs two sftp sessions, so password authentication prompts twice, and three
      times when a competing change is found and merged back in
    - -UseSftp replaces the whole file rather than appending, because SFTP has no atomic
      append and no compare-and-swap. A competing writer can therefore be overwritten. Three
      checks bound this - a re-read before the overwrite that merges any change found, a
      read-back afterwards, and the post-install verification - so a run never reports
      Installed for a key that was already gone. They narrow the window rather than closing
      it: simultaneous -UseSftp runs against one file will lose entries, and the runs that
      lose them report Failed. The exec path appends and is unaffected
    - Identifying which key a server accepted relies on ssh -v naming it. That output is not
      a stable interface, though the line has been unchanged for many OpenSSH releases. A
      probe with no fingerprint to match falls back to "some key authenticated"
    - -TraceRemoteCommand against a WINDOWS target returns the trace as CLIXML markup when
      combined with -Credential, because that path redirects the child's streams by design.
      The trace is all there, just XML-escaped. POSIX targets are unaffected
    - A POSIX target needs base64 on PATH only when the client requires the encoded
      transport, and one whose base64 wants -D rather than -d (BSD, macOS) fails there too.
      Running the same deployment from PowerShell 7.2+ avoids the dependency entirely
    - With -UseSftp the verification settles for the server accepting the key, because an
      account restricted to sftp cannot run the sentinel command that would prove more
    - -UseAgentKeys cannot be combined with -UpdateSshConfig, because a Host block records a
      single IdentityFile and the agent supplies several
    - The client config is consulted only when one exists - %USERPROFILE%\.ssh\config, or
      whatever -SshConfigFile names - and only for the User, HostName and Port of a host.
      Other settings are left to ssh itself
    - -SshConfigFile is ssh's own -F, so naming a file also suppresses the system-wide
      config. That is what -F means, but a setting inherited from ssh_config stops applying
    - The banner probe opens a raw socket, so it cannot traverse a ProxyJump given through
      -SshOption. Such hosts fall back to POSIX unless -TargetPlatform is stated
    - -SshOption ProxyJump=... alone does not authenticate the hop. ssh applies -i only to
      the final destination, so the jump host falls back to a password prompt and the run
      appears to hang. Name the bastion's IdentityFile in a config and pass -SshConfigFile,
      or load that key into an agent; the -SshOption help has a worked example
    - A passphrase-protected key cannot be verified unless an agent holds it, because every
      probe uses BatchMode. Those runs report Verified false rather than a false failure
    - Windows targets need powershell.exe present; the DefaultShell setting does not matter
    - The Windows install is one cmd.exe command line, so the whole payload must fit in 8191
      characters. An RSA 4096 key uses roughly 6900 of them; the run refuses rather than
      letting cmd.exe truncate silently
    - Writing administrators_authorized_keys needs a token in which the Administrators group
      is enabled. Windows OpenSSH grants one even to an account UAC filters at interactive
      logon, so this normally succeeds; verified on Server 2022 with UAC on. Where it is
      refused, the key goes to the profile file, the reason is reported on the console and on
      RemoteMessage, and the run reports Failed - because sshd's "Match Group administrators"
      block reads only the ProgramData file for an administrator
    - Platform auto-detection needs the SSH banner; hosts behind a protocol-aware proxy
      may need -TargetPlatform stated explicitly

.LINK
    https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement

.LINK
    https://man.openbsd.org/ssh-copy-id
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Colour-coded console status is intentional; results are returned as objects.')]
[CmdletBinding(SupportsShouldProcess)]
[OutputType('SshKeyDeploymentResult')]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('Hosts')]
    [string[]]$ComputerName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$HostFile,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$User = $env:USERNAME,

    [Parameter()]
    [Alias('p')]
    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [Parameter()]
    [ValidateSet('Auto', 'Linux', 'Windows')]
    [string]$TargetPlatform = 'Auto',

    [Parameter()]
    [ValidateSet('Auto', 'Administrators', 'UserProfile')]
    [string]$WindowsKeyLocation = 'Auto',

    [Parameter()]
    [Alias('TargetPath')]
    [ValidatePattern('^[A-Za-z0-9._~/\\:%+-]+$')]
    [string]$RemoteAuthorizedKeysPath,

    [Parameter()]
    [Alias('o', 'Option')]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]*=[^\r\n]+$')]
    [string[]]$SshOption,

    [Parameter()]
    [ValidateSet('accept-new', 'yes', 'no', 'ask')]
    [string]$StrictHostKeyChecking = 'accept-new',

    [Parameter()]
    [ValidateSet('Auto', 'Direct', 'Encoded')]
    [string]$PosixTransport = 'Auto',

    [Parameter()]
    [Alias('i', 'IdentityFile')]
    [ValidateNotNullOrEmpty()]
    [string]$KeyPath = (Join-Path $env:USERPROFILE '.ssh\id_ed25519'),

    [Parameter()]
    [ValidateSet('ed25519', 'rsa')]
    [string]$KeyType = 'ed25519',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9 ._@-]+$')]
    [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$RequireExistingKey,

    [Parameter()]
    [switch]$ForceInstall,

    [Parameter()]
    [switch]$UseAgentKeys,

    [Parameter()]
    [Alias('Sftp')]
    [switch]$UseSftp,

    [Parameter()]
    [switch]$CreateSampleHostFile,

    [Parameter()]
    [switch]$UpdateSshConfig,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ConfigAlias,

    [Parameter()]
    [switch]$ForceConfigUpdate,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SshConfigPath = (Join-Path $env:USERPROFILE '.ssh\config'),

    [Parameter()]
    [Alias('ConfigFile')]
    [ValidateNotNullOrEmpty()]
    [string]$SshConfigFile,

    [Parameter()]
    [Alias('x')]
    [switch]$TraceRemoteCommand,

    [Parameter()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
)

# Named blocks are required for -ComputerName to accept pipeline input: without them the
# whole body is an implicit end block, and only the LAST piped host would ever bind.
# Everything therefore lives inside begin/process/end - PowerShell forbids loose
# statements alongside named blocks.
begin {

    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    # Carry the user's Yes-to-All / No-to-All choice across hosts within a single run
    $script:SshConfigYesToAll = $false
    $script:SshConfigNoToAll = $false


    function Write-Info {
        param([string]$Message)

        Write-Host "[*] $Message" -ForegroundColor Cyan
    }


    function Write-Ok {
        param([string]$Message)

        Write-Host "[+] $Message" -ForegroundColor Green
    }


    function Write-Note {
        param([string]$Message)

        Write-Host "[!] $Message" -ForegroundColor Yellow
    }


    function Write-Bad {
        param([string]$Message)

        Write-Host "[x] $Message" -ForegroundColor Red
    }


    function Write-RemediationHint {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
            Justification = 'Hint is used as a mass noun here; the function emits guidance text.')]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Platform
        )

        if ($Platform -eq 'Windows') {
            $lines = @(
                '     Check PubkeyAuthentication yes in %ProgramData%\ssh\sshd_config.'
                '     Administrators normally need the key in'
                '     %ProgramData%\ssh\administrators_authorized_keys, which the ssh session may'
                '     lack the rights to write. Add it locally on the server, or retry with'
                '     -WindowsKeyLocation UserProfile if the Match Group administrators block'
                '     has been removed from sshd_config.'
            )
        }
        else {
            $lines = @(
                '     Check PubkeyAuthentication yes, ~/.ssh perms (700/600),'
                '     and SELinux (restorecon -R ~/.ssh) on the server.'
            )
        }

        foreach ($line in $lines) {
            Write-Host $line -ForegroundColor Gray
        }
    }


    function Get-OpenSshTool {
        [CmdletBinding()]
        [OutputType('OpenSshToolPath')]
        param()

        $ssh = Get-Command 'ssh' -ErrorAction SilentlyContinue
        $sshKeygen = Get-Command 'ssh-keygen' -ErrorAction SilentlyContinue

        if (-not $ssh -or -not $sshKeygen) {
            Write-Bad 'OpenSSH client tools were not found on PATH.'
            $capability = 'OpenSSH.Client~~~~0.0.1.0'
            Write-Host "    Enable them with: Add-WindowsCapability -Online -Name $capability" `
                -ForegroundColor Gray
            Write-Error 'Required OpenSSH tools are missing.' -ErrorAction Stop
        }

        # sftp is only needed for -UseSftp, so a missing one is reported at the point of use
        # rather than blocking every run
        $sftp = Get-Command 'sftp' -ErrorAction SilentlyContinue
        $sftpPath = ''
        if ($sftp) {
            $sftpPath = $sftp.Source
        }

        return [pscustomobject]@{
            PSTypeName = 'OpenSshToolPath'
            Ssh        = $ssh.Source
            SshKeygen  = $sshKeygen.Source
            Sftp       = $sftpPath
        }
    }


    function ConvertTo-SftpArgument {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$SshArgument
        )

        # sftp takes the same -i and -o as ssh, but spells the port -P. Passing ssh's lower-case
        # -p would be read as "preserve modification times" and the port would be lost silently.
        $converted = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in $SshArgument) {
            if ($argument -ceq '-p') {
                $converted.Add('-P')
                continue
            }
            $converted.Add($argument)
        }

        return [string[]]$converted.ToArray()
    }


    function ConvertTo-NativeArgumentString {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            # An empty element is a legitimate argument - it reaches the far side as ""
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$ArgumentList
        )

        # Windows PowerShell 5.1 runs on .NET Framework, where ProcessStartInfo exposes only
        # Arguments - one flat string - and not the ArgumentList collection that .NET Core
        # added. Handing ssh a command line therefore means quoting it the way the C runtime
        # will parse it back, because CommandLineToArgvW is what actually splits it:
        #
        #   - a run of N backslashes before a double quote becomes 2N+1 backslashes, so the
        #     quote is escaped rather than treated as a delimiter
        #   - a run of N backslashes at the end of a quoted argument becomes 2N, so a trailing
        #     backslash cannot escape the closing quote - "C:\dir\" would otherwise swallow it
        #   - backslashes anywhere else are literal and must not be doubled, or every Windows
        #     path in the command line would gain extra separators
        #
        # Getting this wrong is the same class of fault that once split a public key into
        # fragments, so a test asserts this agrees with ArgumentList on hosts that have both.
        $quoted = [System.Collections.Generic.List[string]]::new()

        foreach ($argument in $ArgumentList) {
            if ($argument -eq '') {
                $quoted.Add('""')
                continue
            }

            # Nothing a delimiter could latch onto, so the argument stands as written
            if ($argument -notmatch '[ \t"]') {
                $quoted.Add($argument)
                continue
            }

            $builder = [System.Text.StringBuilder]::new()
            [void]$builder.Append('"')
            $backslashes = 0

            foreach ($character in $argument.ToCharArray()) {
                if ($character -eq '\') {
                    $backslashes++
                    continue
                }

                if ($character -eq '"') {
                    [void]$builder.Append('\', ($backslashes * 2) + 1)
                    [void]$builder.Append('"')
                }
                else {
                    [void]$builder.Append('\', $backslashes)
                    [void]$builder.Append($character)
                }

                $backslashes = 0
            }

            [void]$builder.Append('\', $backslashes * 2)
            [void]$builder.Append('"')
            $quoted.Add($builder.ToString())
        }

        return ($quoted -join ' ')
    }


    function New-SshAskPassHelper {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType('SshAskPassHelper')]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.PSCredential]$Credential
        )

        # ssh reads a password from the console device, never from stdin, so no amount of
        # piping will answer its prompt - which is why an unattended run against a host that
        # does not yet trust the key simply stops. SSH_ASKPASS is OpenSSH's own answer: ssh
        # runs the named program and reads one line from its stdout. SSH_ASKPASS_REQUIRE=force
        # is what makes it apply even when a console does exist; without it ssh consults
        # SSH_ASKPASS only when there is no tty, which is not the case under most CI runners.
        #
        # The helper file deliberately contains no secret. It echoes an environment variable,
        # so the password reaches only this process's environment - inherited by ssh, and by
        # the helper ssh spawns - and never touches disk, where it would outlive the run.
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("sshkeyaskpass-" + [Guid]::NewGuid().ToString('N'))
        $helperPath = Join-Path $directory 'askpass.cmd'

        # A fresh name per helper, so two runs in one session cannot read each other's value
        $variableName = 'DEPLOY_SSHKEY_PW_' + [Guid]::NewGuid().ToString('N')

        if (-not $PSCmdlet.ShouldProcess($helperPath, 'Create SSH password helper')) {
            return $null
        }

        New-Item -ItemType Directory -Path $directory -Force | Out-Null

        # ASCII and CRLF: cmd.exe is the interpreter, and a BOM on the first line would be
        # read as part of the @echo directive
        [System.IO.File]::WriteAllText(
            $helperPath,
            "@echo off`r`necho %$variableName%`r`n",
            [System.Text.ASCIIEncoding]::new())

        # Deliberately sets no environment variable on THIS process. The password is placed
        # directly into each child's environment block at launch instead - see
        # Invoke-SshClient - so it is never inherited by anything except the ssh or sftp
        # process that needs it, and never readable from this process at all. The credential
        # is carried here still wrapped in its SecureString; plaintext is produced only at
        # the moment a child is started.
        return [pscustomobject]@{
            PSTypeName   = 'SshAskPassHelper'
            Path         = $helperPath
            Directory    = $directory
            VariableName = $variableName
            Credential   = $Credential
        }
    }


    function Remove-SshAskPassHelper {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [psobject]$Helper
        )

        if (-not $PSCmdlet.ShouldProcess($Helper.Path, 'Remove SSH password helper')) {
            return
        }

        # Only the helper script has to be cleaned up: no environment variable was ever set
        # on this process, so there is nothing here to unset or restore.
        Remove-Item -Path $Helper.Directory -Recurse -Force -ErrorAction SilentlyContinue
    }


    function Invoke-SshClient {
        [CmdletBinding()]
        [OutputType('SshProcessResult')]
        param(
            [Parameter(Mandatory)]
            [string]$FilePath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$ArgumentList,

            # Supplied only when -Credential is in play. Its presence is what switches this
            # from "let ssh use the console" to "answer ssh from an isolated environment".
            [Parameter()]
            [psobject]$AskPass
        )

        if (-not $AskPass) {
            # No credential: ssh keeps this console, because that is how the operator types a
            # password. Redirecting here would make interactive use impossible.
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $raw = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })

                # $LASTEXITCODE does not exist until a native command has run in this session,
                # and Set-StrictMode makes reading an undefined variable terminating.
                $exitCode = $null
                if (Test-Path -Path 'Variable:LASTEXITCODE') {
                    $exitCode = $LASTEXITCODE
                }
            }
            finally {
                $ErrorActionPreference = $previous
            }

            return [pscustomobject]@{
                PSTypeName = 'SshProcessResult'
                ExitCode   = $exitCode
                Output     = [string[]]$raw
            }
        }

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        # ArgumentList quotes each element correctly and is the reference implementation, but
        # .NET Framework - and therefore Windows PowerShell 5.1 - does not have it. There the
        # command line is assembled by hand to the same rules.
        if ($startInfo.PSObject.Properties.Name -contains 'ArgumentList') {
            foreach ($argument in $ArgumentList) {
                $startInfo.ArgumentList.Add($argument)
            }
        }
        else {
            $startInfo.Arguments = ConvertTo-NativeArgumentString -ArgumentList $ArgumentList
        }

        # This is the whole point of the isolation. The password is written into the CHILD's
        # environment block only - the parent never holds it, so it cannot be read out of
        # this process, and no other child this script starts can inherit it.
        $startInfo.EnvironmentVariables[$AskPass.VariableName] =
        $AskPass.Credential.GetNetworkCredential().Password
        $startInfo.EnvironmentVariables['SSH_ASKPASS'] = $AskPass.Path
        $startInfo.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        try {
            $null = $process.Start()

            # Both pipes are drained concurrently. Reading one to the end while the other
            # fills its buffer is the classic way to deadlock a redirected child, and ssh
            # writes to both - diagnostics to stderr, sentinels to stdout.
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $standardOutput = $outputTask.GetAwaiter().GetResult()
            $standardError = $errorTask.GetAwaiter().GetResult()

            $process.WaitForExit()
            $exitCode = $process.ExitCode
        }
        finally {
            $process.Dispose()
        }

        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($stream in @($standardOutput, $standardError)) {
            if (-not $stream) {
                continue
            }
            foreach ($line in ($stream -split "`r?`n")) {
                $lines.Add($line)
            }
        }

        return [pscustomobject]@{
            PSTypeName = 'SshProcessResult'
            ExitCode   = $exitCode
            Output     = $lines.ToArray()
        }
    }


    function Merge-AuthorizedKeyContent {
        [CmdletBinding()]
        [OutputType('SshAuthorizedKeyMerge')]
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$ExistingContent,

            [Parameter(Mandatory)]
            [string[]]$PublicKey
        )

        # In sftp mode the whole file is rewritten, so the merge that the POSIX shell command
        # does remotely has to happen here instead: same CR-normalized duplicate check, same
        # guarantee that the last line is terminated before anything is appended.
        $lines = [System.Collections.Generic.List[string]]::new()
        if ($ExistingContent) {
            foreach ($line in ($ExistingContent -split "`r?`n")) {
                $lines.Add($line)
            }

            # A split on a trailing terminator leaves an empty final element; drop it so the
            # rebuild does not accumulate a blank line on every run
            while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
                $lines.RemoveAt($lines.Count - 1)
            }
        }

        $normalized = @($lines | ForEach-Object { $_.Trim() })
        $added = 0

        foreach ($key in $PublicKey) {
            $candidate = "$key".Trim()
            if (-not $candidate) {
                continue
            }
            if ($normalized -contains $candidate) {
                continue
            }

            $lines.Add($candidate)
            $normalized += $candidate
            $added++
        }

        # LF endings: this file is read by sshd, and a CR at the end of a key is exactly the
        # taint the exec path goes to the trouble of stripping
        $content = ''
        if ($lines.Count -gt 0) {
            $content = ($lines -join "`n") + "`n"
        }

        return [pscustomobject]@{
            PSTypeName = 'SshAuthorizedKeyMerge'
            Content    = $content
            KeysAdded  = $added
        }
    }


    function Resolve-TargetList {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter()]
            [string[]]$ProvidedHosts,

            [Parameter()]
            [string]$ProvidedHostFile,

            [Parameter(Mandatory)]
            [string]$DefaultUser,

            # Consulted only for entries that carry no "user@". Lets the caller answer with the
            # account ssh itself would pick for that host, which is what makes a config alias work.
            [Parameter()]
            [scriptblock]$UserResolver,

            # Whether an empty host list may be resolved by asking. False for any run driven
            # by a pipeline or a scheduler, where there is nobody to answer.
            [Parameter()]
            [switch]$AllowPrompt
        )

        $targets = [System.Collections.Generic.List[string]]::new()

        if ($ProvidedHosts) {
            foreach ($hostEntry in $ProvidedHosts) {
                if ($hostEntry -and $hostEntry.Trim()) {
                    $targets.Add($hostEntry.Trim())
                }
            }
        }

        if ($ProvidedHostFile) {
            if (-not (Test-Path -Path $ProvidedHostFile)) {
                Write-Error "Host file not found: $ProvidedHostFile" -ErrorAction Stop
            }

            foreach ($line in Get-Content -Path $ProvidedHostFile) {
                $cleanLine = $line.Trim()
                if ($cleanLine -and -not $cleanLine.StartsWith('#')) {
                    $targets.Add($cleanLine)
                }
            }
        }

        if ($targets.Count -eq 0 -and $AllowPrompt) {
            $prompt = 'Enter target host(s), space- or comma-separated (for example: server1 admin@server2)'

            # Read-Host throws where there is no console to read - a scheduled task, a CI
            # runner, a remoting session. That is not an error worth reporting on its own:
            # the real problem is simply that no hosts were supplied, which the check below
            # states plainly. Anything else buries the cause in a console-handle message.
            $entry = ''
            try {
                $entry = Read-Host $prompt
            }
            catch {
                Write-Verbose "No console available to prompt for hosts: $($_.Exception.Message)"
            }

            if ($entry) {
                foreach ($hostEntry in ($entry -split '[,\s]+')) {
                    if ($hostEntry -and $hostEntry.Trim()) {
                        $targets.Add($hostEntry.Trim())
                    }
                }
            }
        }

        if ($targets.Count -eq 0) {
            Write-Error 'No hosts were specified. Nothing to do.' -ErrorAction Stop
        }

        $normalizedTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($target in $targets) {
            if ($target -match '@') {
                $normalizedTargets.Add($target)
                continue
            }

            $entryUser = $DefaultUser
            if ($UserResolver) {
                try {
                    $resolved = "$(& $UserResolver $target)".Trim()
                    if ($resolved) {
                        $entryUser = $resolved
                    }
                }
                catch {
                    Write-Verbose "User resolution failed for ${target}: $($_.Exception.Message)"
                }
            }

            $normalizedTargets.Add("$entryUser@$target")
        }

        return $normalizedTargets | Select-Object -Unique
    }


    function Test-ValidTarget {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter()]
            [string]$Target
        )

        if ([string]::IsNullOrWhiteSpace($Target)) {
            return $false
        }

        # A leading dash would be consumed by ssh as an option (for example -oProxyCommand=...)
        if ($Target.StartsWith('-')) {
            return $false
        }

        # Allowlist: user@host, where the user may itself be a UPN (admin@corp.example) because
        # that is a normal login name on AD-joined hosts, and the host may be a name, IPv4, or a
        # bracketed/bare IPv6 literal. Each '@'-separated segment must be non-empty.
        return $Target -match '^[A-Za-z0-9._-]+(@[A-Za-z0-9._-]+)*@[A-Za-z0-9._:\[\]-]+$'
    }


    function Get-SshTargetPart {
        [CmdletBinding()]
        [OutputType('SshTargetPart')]
        param(
            [Parameter(Mandatory)]
            [string]$Target
        )

        # ssh splits user@host on the LAST '@'. Splitting on the first would resolve a UPN
        # login (admin@corp.example@server1) to the account 'admin' on the host
        # 'corp.example@server1', which is not a host at all.
        $separator = $Target.LastIndexOf('@')

        if ($separator -lt 0) {
            return [pscustomobject]@{
                PSTypeName  = 'SshTargetPart'
                User        = ''
                HostAddress = $Target
            }
        }

        return [pscustomobject]@{
            PSTypeName  = 'SshTargetPart'
            User        = $Target.Substring(0, $separator)
            HostAddress = $Target.Substring($separator + 1)
        }
    }


    function Test-PrivateKeyEncrypted {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$KeyPath
        )

        # This matters because every reachability probe runs with BatchMode=yes, which suppresses
        # passphrase prompts as well as password prompts. An encrypted key that is not loaded into
        # an agent therefore fails both probes, and the run would report Failed for a host where
        # the key works perfectly.
        if (-not (Test-Path -LiteralPath $KeyPath)) {
            return $false
        }

        try {
            $text = Get-Content -LiteralPath $KeyPath -Raw -ErrorAction Stop
        }
        catch {
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            return $false
        }

        # Legacy PEM keys advertise encryption in cleartext
        if ($text -match 'Proc-Type:\s*4,ENCRYPTED') {
            return $true
        }

        if ($text -notmatch 'BEGIN OPENSSH PRIVATE KEY') {
            return $false
        }

        # openssh-key-v1 layout: the 15-byte magic "openssh-key-v1\0" is followed immediately by
        # a length-prefixed cipher name. Anything other than "none" means a passphrase is set.
        try {
            $body = [regex]::Replace($text, '-----[^-]*-----', '')
            $bytes = [System.Convert]::FromBase64String(($body -replace '\s', ''))
        }
        catch {
            return $false
        }

        $offset = 15
        if ($bytes.Length -lt ($offset + 4)) {
            return $false
        }

        $length = ([int]$bytes[$offset] -shl 24) -bor ([int]$bytes[$offset + 1] -shl 16) -bor
            ([int]$bytes[$offset + 2] -shl 8) -bor [int]$bytes[$offset + 3]

        if ($length -le 0 -or ($offset + 4 + $length) -gt $bytes.Length) {
            return $false
        }

        return ([System.Text.Encoding]::ASCII.GetString($bytes, $offset + 4, $length) -ne 'none')
    }


    function Test-SshAgentHasKey {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$PublicKeyLine
        )

        # An encrypted key is still usable without prompting when the agent holds it, so the
        # BatchMode probes stay valid. ssh-add lists the agent's identities as public key lines.
        $sshAdd = Get-Command 'ssh-add' -ErrorAction SilentlyContinue
        if (-not $sshAdd) {
            return $false
        }

        $wanted = @($PublicKeyLine -split '\s+')
        if ($wanted.Count -lt 2) {
            return $false
        }

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $listed = @(& $sshAdd.Source -L 2>&1 | ForEach-Object { "$_" })
        }
        catch {
            return $false
        }
        finally {
            $ErrorActionPreference = $previous
        }

        foreach ($line in $listed) {
            # Compare algorithm and key body only: the comment differs between the file and
            # whatever label the key was added to the agent under.
            $parts = @($line -split '\s+')
            if ($parts.Count -ge 2 -and $parts[0] -eq $wanted[0] -and $parts[1] -eq $wanted[1]) {
                return $true
            }
        }

        return $false
    }


    function New-KeyCandidate {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Builds a descriptor object; nothing is created or changed.')]
        [CmdletBinding()]
        [OutputType('SshCandidateKey')]
        param(
            [Parameter(Mandatory)]
            [string]$Line,

            # What -i is given when probing this key. For a key on disk that is the private key;
            # for an agent identity it is a scratch copy of the public half, which is enough for
            # ssh to ask the agent for the matching private key.
            [Parameter(Mandatory)]
            [string]$IdentityPath,

            [Parameter()]
            [AllowEmptyString()]
            [string]$Fingerprint
        )

        $parts = @($Line -split '\s+')
        $label = $Line
        if ($parts.Count -ge 3) {
            $label = '{0} {1}' -f $parts[0], ($parts[2..($parts.Count - 1)] -join ' ')
        }
        elseif ($parts.Count -ge 1) {
            $label = $parts[0]
        }

        return [pscustomobject]@{
            PSTypeName   = 'SshCandidateKey'
            Line         = $Line
            IdentityPath = $IdentityPath
            Fingerprint  = $Fingerprint
            Label        = $label
        }
    }


    function Get-AgentPublicKey {
        [CmdletBinding()]
        [OutputType([string[]])]
        param()

        # ssh-copy-id with no -i installs every identity the agent holds, which is how a user
        # with several keys distributes all of them in one pass. ssh-add -L prints them as
        # public key lines, which is exactly the form authorized_keys wants.
        $sshAdd = Get-Command 'ssh-add' -ErrorAction SilentlyContinue
        if (-not $sshAdd) {
            return [string[]]@()
        }

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $listed = @(& $sshAdd.Source -L 2>$null | ForEach-Object { "$_".Trim() })
        }
        catch {
            Write-Verbose "ssh-add -L failed: $($_.Exception.Message)"
            return [string[]]@()
        }
        finally {
            $ErrorActionPreference = $previous
        }

        # An empty agent answers with prose ("The agent has no identities."), so match the shape
        # of a key line rather than trusting the exit code
        return [string[]]@($listed | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)\S*\s+\S+' })
    }


    function Select-UninstalledKey {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Filters a list by probing; nothing is changed on any host.')]
        [CmdletBinding()]
        [OutputType('SshCandidateKey')]
        param(
            [Parameter(Mandatory)]
            [string]$SshPath,

            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [object[]]$Candidate,

            [Parameter(Mandatory)]
            [string[]]$CommonArgs,

            [Parameter()]
            [switch]$KeyAuthOnly
        )

        # ssh-copy-id decides what to install by asking the host which keys already authenticate,
        # one key at a time, rather than by reading the remote file. Same approach here: it is the
        # only check that accounts for the file sshd actually reads.
        $pending = [System.Collections.Generic.List[object]]::new()

        foreach ($key in $Candidate) {
            $identityArgs = @($CommonArgs) + @('-i', $key.IdentityPath, '-o', 'IdentitiesOnly=yes')

            $accepted = Test-PasswordlessAccess -SshPath $SshPath -Target $Target `
                -CommonArgs $identityArgs -Fingerprint $key.Fingerprint -KeyAuthOnly:$KeyAuthOnly

            if ($accepted) {
                Write-Verbose "Already accepted by ${Target}: $($key.Label)"
                continue
            }

            $pending.Add($key)
        }

        return $pending.ToArray()
    }


    function Get-SshEffectiveConfig {
        [CmdletBinding()]
        [OutputType('SshEffectiveConfig')]
        param(
            [Parameter(Mandatory)]
            [string]$SshPath,

            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$SshArgument = @()
        )

        # "ssh -G" prints the configuration ssh would actually use for this destination, after
        # ~/.ssh/config, the system config and the command line have all been applied. It makes
        # no network connection. Without it a Host block that sets Port or User is invisible
        # here, and the run silently contacts the wrong port as the wrong account.
        $settings = @{}

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $lines = @(& $SshPath @SshArgument -G $Target 2>$null)
        }
        catch {
            Write-Verbose "ssh -G failed for ${Target}: $($_.Exception.Message)"
            $lines = @()
        }
        finally {
            $ErrorActionPreference = $previous
        }

        foreach ($line in $lines) {
            if ("$line" -notmatch '^\s*(\S+)\s+(.*?)\s*$') {
                continue
            }

            # ssh -G prints the winning value first, so the first occurrence is the effective one
            $setting = $Matches[1].ToLowerInvariant()
            if (-not $settings.ContainsKey($setting)) {
                $settings[$setting] = $Matches[2]
            }
        }

        $resolvedPort = 0
        if ($settings.ContainsKey('port')) {
            $parsedPort = 0
            if ([int]::TryParse($settings['port'], [ref]$parsedPort)) {
                $resolvedPort = $parsedPort
            }
        }

        $resolvedUser = ''
        if ($settings.ContainsKey('user')) {
            $resolvedUser = $settings['user']
        }

        $resolvedHost = ''
        if ($settings.ContainsKey('hostname')) {
            $resolvedHost = $settings['hostname']
        }

        return [pscustomobject]@{
            PSTypeName = 'SshEffectiveConfig'
            HostName   = $resolvedHost
            User       = $resolvedUser
            Port       = $resolvedPort
        }
    }


    function Get-RemoteSshBanner {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$HostAddress,

            [Parameter(Mandatory)]
            [int]$Port,

            [Parameter()]
            [int]$TimeoutMs = 5000
        )

        # An SSH server sends its identification string before any authentication, so the
        # platform can be established without a password prompt or a second login.
        $client = $null
        try {
            # The parameterless constructor is IPv4-only on .NET Framework, so under Windows
            # PowerShell 5.1 it cannot dial an IPv6 literal at all - it throws "None of the
            # discovered or specified addresses match the socket address family" and the host is
            # silently assumed to be POSIX. .NET Core happens to default to dual-mode, which is
            # why this only shows up on 5.1. Asking for it explicitly works on both.
            try {
                $client = [System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetworkV6)
                $client.Client.DualMode = $true
            }
            catch {
                # IPv6 disabled on this machine; an IPv4-only socket is still better than nothing
                Write-Verbose "Dual-mode socket unavailable, falling back to IPv4: $($_.Exception.Message)"
                $client = [System.Net.Sockets.TcpClient]::new()
            }

            $connectTask = $client.ConnectAsync($HostAddress.Trim('[', ']'), $Port)
            if (-not $connectTask.Wait($TimeoutMs)) {
                return ''
            }

            $stream = $client.GetStream()
            $stream.ReadTimeout = $TimeoutMs

            $buffer = [byte[]]::new(255)
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                return ''
            }

            return [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
        }
        catch {
            Write-Verbose "SSH banner probe failed for ${HostAddress}: $($_.Exception.Message)"
            return ''
        }
        finally {
            if ($client) {
                $client.Dispose()
            }
        }
    }


    function Resolve-RemotePlatform {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter(Mandatory)]
            [int]$Port,

            [Parameter(Mandatory)]
            [ValidateSet('Auto', 'Linux', 'Windows')]
            [string]$Preference,

            # The address ssh resolved for this target. A Host block's HostName means the name in
            # the target is an alias that DNS cannot resolve, and the raw socket probe would fail.
            [Parameter()]
            [AllowEmptyString()]
            [string]$ResolvedHostAddress
        )

        if ($Preference -ne 'Auto') {
            return $Preference
        }

        $hostAddress = $ResolvedHostAddress
        if (-not $hostAddress) {
            $hostAddress = (Get-SshTargetPart -Target $Target).HostAddress
        }

        $banner = Get-RemoteSshBanner -HostAddress $hostAddress -Port $Port

        if (-not $banner) {
            Write-Note "Could not read the SSH banner from $hostAddress; assuming a POSIX target."
            Write-Note 'Pass -TargetPlatform Windows if this host runs Windows OpenSSH Server.'
            return 'Linux'
        }

        Write-Verbose "SSH banner for ${hostAddress}: $banner"

        # Microsoft's port identifies itself as OpenSSH_for_Windows_x.y. Cygwin and MSYS
        # builds report a plain OpenSSH banner and genuinely want the POSIX command.
        # Matching a bare 'Windows' anywhere in the banner was too loose: a POSIX host is free
        # to advertise a product name containing that word, and would then be misdetected.
        if ($banner -match 'OpenSSH_for_Windows') {
            return 'Windows'
        }

        return 'Linux'
    }


    function Initialize-KeyPair {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$KeyPath,

            [Parameter(Mandatory)]
            [string]$KeyType,

            [Parameter(Mandatory)]
            [string]$Comment,

            [Parameter(Mandatory)]
            [string]$SshKeygenPath,

            [Parameter()]
            [switch]$Force,

            [Parameter()]
            [switch]$RequireExistingKey
        )

        $pubPath = "$KeyPath.pub"

        # -Comment is allowlist-validated because it reaches ssh-keygen inside a pre-quoted
        # argument string. KeyPath reaches the same string, so it needs the same guarantee.
        if ($KeyPath.Contains('"')) {
            Write-Error "KeyPath may not contain a double quote: $KeyPath" -ErrorAction Stop
        }

        $sshDir = Split-Path -Path $KeyPath -Parent
        if (-not $sshDir) {
            $sshDir = $env:USERPROFILE
        }

        if (-not (Test-Path -Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        if ($Force -and (Test-Path -Path $KeyPath)) {
            if ($PSCmdlet.ShouldProcess($KeyPath, 'Remove existing key pair')) {
                Write-Note "-Force specified: removing existing key at $KeyPath"
                Remove-Item -Path $KeyPath, $pubPath -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -Path $KeyPath) {
            Write-Info "Using existing key: $KeyPath"

            if (-not (Test-Path -Path $pubPath)) {
                if ($PSCmdlet.ShouldProcess($pubPath, 'Derive public key from private key')) {
                    Write-Info 'Public key is missing; deriving it from the private key.'
                    & $SshKeygenPath -y -f $KeyPath | Set-Content -Path $pubPath -Encoding ascii
                }
            }

            return $pubPath
        }

        # Reaching here means the private key is absent, so the next step would generate one.
        # ssh-copy-id never does that: it fails with "No identities found" instead. Generating
        # silently turns a mistyped -KeyPath, or a default that does not match the key the
        # operator actually uses, into a brand new identity that deploys and reports success.
        if ($RequireExistingKey) {
            Write-Error "No private key at $KeyPath and -RequireExistingKey was specified." `
                -ErrorAction Stop
        }

        if (Test-Path -Path $pubPath) {
            # ssh-keygen only checks the private key before writing, so it would overwrite this
            # public key without a word. An orphaned .pub is a real configuration - the private
            # half lives in an agent, on a smartcard, or on another machine.
            Write-Bad "A public key exists at $pubPath but its private key is missing."
            Write-Host '    Generating here would overwrite that public key.' -ForegroundColor Gray
            Write-Host '    Restore the private key, choose another -KeyPath, or delete the .pub file.' `
                -ForegroundColor Gray
            Write-Error "Refusing to overwrite an existing public key: $pubPath" -ErrorAction Stop
        }

        if (-not $PSCmdlet.ShouldProcess($KeyPath, "Generate new $KeyType key pair")) {
            return $pubPath
        }

        Write-Note "No key found at $KeyPath; generating a new identity."
        Write-Info "Generating new $KeyType key (no passphrase): $KeyPath"

        $keyBits = ''
        if ($KeyType -eq 'rsa') {
            $keyBits = ' -b 4096'
        }

        # Start-Process joins an ArgumentList array and silently drops empty elements, which
        # turns -N '' into -N -C and makes ssh-keygen fail. Passing one pre-quoted string
        # preserves the empty passphrase on both Windows PowerShell 5.1 and PowerShell 7.
        $argTemplate = '-t {0}{1} -f "{2}" -N "" -C "{3}" -q'
        $argString = $argTemplate -f $KeyType, $keyBits, $KeyPath, $Comment

        $startParams = @{
            FilePath     = $SshKeygenPath
            ArgumentList = $argString
            NoNewWindow  = $true
            Wait         = $true
            PassThru     = $true
        }
        $process = Start-Process @startParams

        if ($process.ExitCode -ne 0 -or -not (Test-Path -Path $KeyPath)) {
            Write-Error "Key generation failed (exit code $($process.ExitCode))." -ErrorAction Stop
        }

        Write-Ok 'Key created.'
        return $pubPath
    }


    function Set-PrivateKeyAcl {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [string]$KeyPath
        )

        if (-not (Test-Path -Path $KeyPath)) {
            Write-Note "Skipping permission hardening; private key not found: $KeyPath"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($KeyPath, 'Restrict private-key permissions')) {
            return
        }

        # A SID rather than USERDOMAIN\USERNAME: that pair is wrong for Entra-joined and
        # Microsoft-account logins, where the account is AzureAD\user while USERDOMAIN reports
        # the machine name. The remote half of this script already resolves by SID.
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $identitySid = $currentIdentity.User.Value
        $identity = $currentIdentity.Name

        # icacls is a native command: it signals failure through its exit code rather than a
        # terminating error, so $LASTEXITCODE must be inspected. A try/catch never fires here.
        #
        # Three steps, and the first is not optional. /grant:r replaces the entry for ONE
        # identity and leaves every other explicit ACE untouched - and ssh-keygen writes its
        # own SYSTEM and Administrators entries, while a key created by some other tool can
        # carry entries for anyone at all. Without /reset this claimed to reduce the ACL to
        # the current user and did not: SYSTEM, Administrators and any inherited-then-made-
        # explicit account all survived. /reset drops the explicit entries back to inherited,
        # /inheritance:r then removes those, and /grant:r adds the one that should remain.
        $null = & icacls $KeyPath /reset
        $resetExit = $LASTEXITCODE

        $null = & icacls $KeyPath /inheritance:r
        $inheritanceExit = $LASTEXITCODE

        $null = & icacls $KeyPath /grant:r "*${identitySid}:F"
        $grantExit = $LASTEXITCODE

        if ($resetExit -ne 0 -or $inheritanceExit -ne 0 -or $grantExit -ne 0) {
            Write-Note ("Could not harden $KeyPath (icacls exit codes: " +
                "$resetExit / $inheritanceExit / $grantExit).")
            Write-Note 'Windows OpenSSH may refuse the key until its permissions are corrected.'
            return
        }

        Write-Info "Private-key permissions restricted to $identity."
    }


    function Test-PasswordlessAccess {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$SshPath,

            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter(Mandatory)]
            [string[]]$CommonArgs,

            # SHA256 fingerprint of the key this probe is about. Supplying it turns the question
            # from "can we get in at all" into "does THIS key get us in", which are different
            # questions on any host that already trusts another key.
            [Parameter()]
            [AllowEmptyString()]
            [string]$Fingerprint,

            # An account restricted to sftp refuses to run the sentinel command, so requiring it
            # would report a perfectly good key as failed. Key acceptance is the question being
            # asked; whether a shell also works is a different one.
            [Parameter()]
            [switch]$KeyAuthOnly
        )

        # BatchMode suppresses password AND passphrase prompts, so this can never block. That
        # also means an encrypted key which is not loaded into an agent always fails here, which
        # the caller has to account for rather than reading as a rejection by the host.
        if (-not $Fingerprint) {
            $result = & $SshPath @CommonArgs -o BatchMode=yes $Target 'echo AUTH_OK' 2>$null

            # A Windows target answering through cmd.exe can return the sentinel with a trailing CR
            return (@($result | ForEach-Object { "$_".Trim() }) -contains 'AUTH_OK')
        }

        # IdentitiesOnly=yes governs what the AGENT may add; it does not stop an IdentityFile in
        # ssh_config from being offered alongside the -i key. ssh tries the command-line identity
        # first and stops at the first one the server accepts, so a host that already trusts the
        # config key answers "yes" to a question asked about a key it has never seen - and the
        # key the operator asked to deploy is silently skipped. -v is the only place ssh says
        # which key was actually accepted.
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $result = @(& $SshPath @CommonArgs -v -o BatchMode=yes $Target 'echo AUTH_OK' 2>&1 |
                    ForEach-Object { "$_" })
        }
        catch {
            Write-Verbose "Key probe failed for ${Target}: $($_.Exception.Message)"
            return $false
        }
        finally {
            $ErrorActionPreference = $previous
        }

        if (-not $KeyAuthOnly -and -not (@($result | ForEach-Object { $_.Trim() }) -contains 'AUTH_OK')) {
            return $false
        }

        foreach ($line in $result) {
            if ($line -match 'Server accepts key' -and $line -match [regex]::Escape($Fingerprint)) {
                return $true
            }
        }

        return $false
    }


    function Get-PublicKeyFingerprint {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$SshKeygenPath
        )

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& $SshKeygenPath -lf $Path 2>&1 | ForEach-Object { "$_" })
        }
        catch {
            return ''
        }
        finally {
            $ErrorActionPreference = $previous
        }

        # "256 SHA256:<base64> comment (ED25519)" - the hash is what ssh -v prints too
        foreach ($line in $output) {
            if ($line -match '(SHA256:[A-Za-z0-9+/=]+)') {
                return $Matches[1]
            }
        }

        return ''
    }


    function Test-NativeQuotingSafe {
        [CmdletBinding()]
        [OutputType([bool])]
        param()

        # Answers one question: will this host escape an embedded double quote when it builds a
        # native command line? If not, a remote command containing "$f" arrives with its quoting
        # stripped and the far side runs something other than what was written.
        #
        # Deliberately a capability check rather than a version check. PowerShell only gained
        # correct escaping with $PSNativeCommandArgumentPassing in 7.2, so 5.1 and 6.0-7.1 are
        # all unsafe - and 7.2+ can be put back into the broken behaviour by a single line in a
        # profile, which a version test would never notice.
        $mode = Get-Variable -Name 'PSNativeCommandArgumentPassing' -ValueOnly -ErrorAction SilentlyContinue
        if (-not $mode) {
            return $false
        }

        # 'Windows' uses the legacy rules only for cmd.exe, .bat, .cmd, cscript and wscript.
        # ssh.exe is not in that list, so it gets the standard, correctly-escaped treatment.
        return ($mode -ne 'Legacy')
    }


    function New-PosixInstallCommand {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Builds a command string; nothing is executed or changed here.')]
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string[]]$PublicKey,

            [Parameter()]
            [AllowEmptyString()]
            [string]$RemotePath,

            # 'Encoded' sends the script base64'd, which no client-side quoting can damage but
            # needs base64 on the target. 'Direct' sends it as a shell command, which needs
            # nothing extra remotely but relies on this host escaping quotes correctly.
            [Parameter()]
            [ValidateSet('Auto', 'Direct', 'Encoded')]
            [string]$Transport = 'Auto',

            [Parameter()]
            [switch]$Trace
        )

        $keyFile = '$HOME/.ssh/authorized_keys'
        $hardenDirectory = $true

        if ($RemotePath) {
            # Inside double quotes sh expands $HOME but not ~, so the shorthand is translated
            $keyFile = $RemotePath -replace '^~/', '$HOME/'

            # A site-wide AuthorizedKeysFile (/etc/ssh/authorized_keys/<user> and friends) is
            # shared, so the 0700 that sshd demands on ~/.ssh would lock every other account
            # out of its own keys.
            $hardenDirectory = $false
        }

        $keyList = @($PublicKey | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        if ($keyList.Count -eq 0) {
            Write-Error 'No public key was supplied.' -ErrorAction Stop
        }

        foreach ($line in $keyList) {
            if ($line -match '[\r\n]') {
                Write-Error 'Each public key must be a single line.' -ErrorAction Stop
            }
        }

        $quotingSafe = Test-NativeQuotingSafe

        # Refused rather than attempted. On a client that strips quotes the body still parses -
        # the loop is bounded - but "$@" degrades to word splitting, so one key arrives as
        # several fragments, each appended as its own entry, and the run reports success over a
        # corrupted authorized_keys. Failing here is the only honest outcome.
        if ($Transport -eq 'Direct' -and -not $quotingSafe) {
            Write-Error ('-PosixTransport Direct needs a PowerShell that escapes quotes in native ' +
                'command lines. This one does not, so keys would be split into fragments. Use ' +
                "'Auto' or 'Encoded'.") -ErrorAction Stop
        }

        $useEncoded = switch ($Transport) {
            'Encoded' { $true }
            'Direct' { $false }
            default { -not $quotingSafe }
        }

        $steps = [System.Collections.Generic.List[string]]::new()

        # ssh-copy-id -x does exactly this. Every command is echoed to stderr as it runs, which
        # is the only way to see which file the target really wrote, and why a chmod or a
        # restorecon failed. First in the list so it covers the whole body.
        if ($Trace) {
            $steps.Add('set -x')
        }

        $steps.Add('f="{0}"' -f $keyFile)
        $steps.Add('umask 077')
        $steps.Add('d=$(dirname "$f")')
        $steps.Add('[ -d "$d" ] || mkdir -p "$d"')
        $steps.Add('[ -f "$f" ] || touch "$f"')
        $steps.Add('n=0')

        # Kept to one line so the step list can be joined with either a newline or a semicolon.
        # sh functions share the caller's scope, so the counter survives without a subshell.
        #
        #  - the file is CR-normalized before comparing, or a key written by an earlier run from
        #    a Windows client never matches and gets appended a second time
        #  - appending to a file whose last line has no terminator splices the new key onto the
        #    end of the previous entry and destroys both, so the terminator is checked
        $steps.Add('addkey() { ' +
            'if tr -d "\r" < "$f" | grep -qxF "$1"; then return 0; fi; ' +
            'if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then echo >> "$f"; fi; ' +
            'echo "$1" >> "$f"; ' +
            'n=$((n+1)); ' +
            '}')

        if ($useEncoded) {
            # Single quotes make the key opaque to sh; the '\'' idiom closes, escapes and
            # reopens the literal, which is the only way to carry a quote through one.
            foreach ($line in $keyList) {
                $steps.Add("addkey '{0}'" -f $line.Replace("'", "'\''"))
            }
        }
        else {
            # Keys arrive as positional parameters instead, so the body itself holds no key text
            $steps.Add('for k in "$@"; do addkey "$k"; done')
        }

        if ($hardenDirectory) {
            $steps.Add('chmod 700 "$d"')
        }

        $steps.Add('chmod 600 "$f"')

        # SELinux denies sshd access to a correctly-permissioned authorized_keys whose label is
        # wrong, which is routine after a home directory is restored, migrated, or created by a
        # tool that does not set contexts. ssh-copy-id relabels for exactly this reason.
        $steps.Add('if command -v restorecon >/dev/null 2>&1; then restorecon -F "$d" "$f" >/dev/null 2>&1; fi')

        $steps.Add('echo "KEY_FILE=$f"')
        $steps.Add('echo "KEYS_ADDED=$n"')
        $steps.Add('echo KEY_INSTALLED_OK')

        if (-not $useEncoded) {
            # The body is single-quoted, so the login shell hands it to sh untouched, and the
            # keys follow as separate single-quoted words that become "$@". Nothing here is
            # base64, so the target needs no tool beyond a POSIX shell.
            $body = $steps -join '; '
            if ($body.Contains("'")) {
                Write-Error 'The direct install command cannot contain a single quote.' -ErrorAction Stop
            }

            $quotedKeys = @($keyList | ForEach-Object { "'" + $_.Replace("'", "'\''") + "'" })
            return "exec sh -c '$body' sh " + ($quotedKeys -join ' ')
        }

        # Encoded form. The command line carries nothing but a base64 blob, which is what makes
        # it survive a client that mangles quotes - Windows PowerShell 5.1, or any PowerShell
        # running with $PSNativeCommandArgumentPassing = 'Legacy'. Embedding the keys also keeps
        # stdin free, which matters because 5.1 prepends a UTF-8 BOM to anything piped into a
        # native command. This mirrors what the Windows path already does.
        $script = ($steps -join "`n") + "`n"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script))

        # The pipeline itself parses in every login shell - sh, bash, csh, tcsh and fish alike -
        # and the decoded body is executed by sh regardless of what the account's shell is.
        return "echo $encoded | base64 -d | sh"
    }


    function New-WindowsInstallCommand {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Builds a command string; nothing is executed or changed here.')]
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string[]]$PublicKey,

            [Parameter(Mandatory)]
            [ValidateSet('Auto', 'Administrators', 'UserProfile')]
            [string]$KeyLocation,

            [Parameter()]
            [AllowEmptyString()]
            [string]$RemotePath,

            [Parameter()]
            [switch]$Trace
        )

        # Both values are embedded in single-quoted PowerShell literals on the far side. Doubling
        # is the escape PowerShell defines for that context, and it cannot be broken out of - but
        # a newline would still split the line, and the compaction below strips lines, so a
        # multi-line value has to be refused outright rather than escaped.
        foreach ($line in $PublicKey) {
            if ($line -match '[\r\n]') {
                Write-Error 'Each public key must be a single line.' -ErrorAction Stop
            }
        }

        $keyList = @($PublicKey | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($keyList.Count -eq 0) {
            Write-Error 'No public key was supplied.' -ErrorAction Stop
        }

        $keyLiteral = ($keyList | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
        $pathLiteral = ''
        if ($RemotePath) {
            if ($RemotePath -match '[\r\n]') {
                Write-Error 'RemoteAuthorizedKeysPath must be a single line.' -ErrorAction Stop
            }
            $pathLiteral = $RemotePath.Replace("'", "''")
        }

        # Resolving these at build time rather than shipping a switch and a chain of ifs keeps the
        # remote script short. That matters: the whole command has to fit in cmd.exe's 8191
        # characters, and an RSA 4096 key already spends a quarter of that budget.
        $useAdminExpression = switch ($KeyLocation) {
            'Administrators' { '$true' }
            'UserProfile' { '$false' }
            default { '$inAdminGroup' }
        }

        $adminFileExpression = "Join-Path `$env:ProgramData 'ssh\administrators_authorized_keys'"
        $keyFileExpression = "if (`$useAdminFile) { $adminFileExpression } else { `$userPath }"
        $fallbackExpression = '$useAdminFile'

        if ($RemotePath) {
            # An explicitly requested path wins over both candidates, and has no sensible
            # fallback: writing somewhere else would quietly ignore what the operator asked for.
            $keyFileExpression = "'$pathLiteral'"
            $fallbackExpression = '$false'
        }

        # Windows OpenSSH hands the command to whatever DefaultShell the host is configured
        # with - cmd.exe out of the box, sometimes powershell.exe or pwsh.exe. Routing through
        # powershell.exe -EncodedCommand behaves identically under all three and removes every
        # layer of shell quoting, which is what makes a single command string safe to send.
        # The key is embedded rather than piped for the same reason: no stdin, no quoting.
        $remoteScript = @'
$ErrorActionPreference = 'Stop'

# Progress records are serialized as CLIXML when the streams are pipes rather than a
# console, which reaches the operator as markup. Observed once from module-load progress
# on a cold analysis cache; silencing the stream costs nothing and removes the class.
$ProgressPreference = 'SilentlyContinue'
__TRACE__

$keys = @(__KEYS__)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()

# sshd resolves "Match Group administrators" by group membership, so this must too.
# IsInRole() would answer a different question: whether the token is elevated. The
# built-in Administrator gets a full token and would agree, but a UAC-filtered admin
# account carries the group as deny-only and would be sent to the wrong file.
#
# Member enumeration rather than a ForEach-Object pipeline: identical result, but
# -TraceRemoteCommand traces every pipeline element, so the pipeline form buried the
# trace under one repeated line per group the token carries - about seventy of them.
$inAdminGroup = @($identity.Groups.Value) -contains 'S-1-5-32-544'
$useAdminFile = __USE_ADMIN_FILE__

function Add-AuthorizedKey {
    param([string]$Path)

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $added = 0
    foreach ($k in $keys) {
        $existing = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim() })
        if ($existing -contains $k) { continue }

        # Appending to a file whose last line has no terminator splices the new key onto
        # the end of the previous entry and destroys both.
        $raw = [IO.File]::ReadAllText($Path)
        if ($raw.Length -gt 0 -and $raw[-1] -ne "`n") {
            [IO.File]::AppendAllText($Path, "`r`n")
        }

        Add-Content -LiteralPath $Path -Value $k -Encoding ascii
        $added++
    }

    return $added
}

function Set-AuthorizedKeyAcl {
    param([string]$Path, [bool]$AdminFile)

    # SIDs rather than names: this must work on non-English installations too.
    $null = icacls $Path /inheritance:r
    if ($AdminFile) {
        $null = icacls $Path /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'
    }
    else {
        $null = icacls $Path /grant ('*{0}:F' -f $identity.User.Value) /grant '*S-1-5-18:F'
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "ACL_WARNING=$Path"
    }
}

$userPath = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
$keyFile = __KEY_FILE__

try {
    $added = Add-AuthorizedKey -Path $keyFile
    Set-AuthorizedKeyAcl -Path $keyFile -AdminFile $useAdminFile
}
catch {
    if (-not (__ALLOW_FALLBACK__)) { throw }

    # Writing under ProgramData needs elevation the ssh session may not have. The user
    # file is the only remaining option; it works when the sshd_config Match block for
    # the administrators group has been removed, and the verification step proves it.
    Write-Output "ADMIN_KEYFILE_FAILED=$($_.Exception.Message)"
    $keyFile = $userPath
    $added = Add-AuthorizedKey -Path $keyFile
    Set-AuthorizedKeyAcl -Path $keyFile -AdminFile $false
}

Write-Output "KEY_FILE=$keyFile"
Write-Output "KEYS_ADDED=$added"
Write-Output 'KEY_INSTALLED_OK'
'@

        # The POSIX equivalent of 'set -x'. An empty replacement leaves a blank line, which the
        # compaction below removes, so the untraced payload is byte-for-byte what it always was.
        $traceExpression = ''
        if ($Trace) {
            $traceExpression = 'Set-PSDebug -Trace 1'
        }

        $remoteScript = $remoteScript.Replace('__TRACE__', $traceExpression)
        $remoteScript = $remoteScript.Replace('__KEYS__', $keyLiteral)
        $remoteScript = $remoteScript.Replace('__USE_ADMIN_FILE__', $useAdminExpression)
        $remoteScript = $remoteScript.Replace('__KEY_FILE__', $keyFileExpression)
        $remoteScript = $remoteScript.Replace('__ALLOW_FALLBACK__', $fallbackExpression)

        # UTF-16 then base64 costs 2.7 characters per source character, and cmd.exe stops
        # reading at 8191. Comment and blank lines are stripped before encoding so the script
        # above can stay readable without spending the budget an RSA-4096 key needs.
        # Only whole-line comments are used above, so this cannot truncate a live statement.
        $compact = @($remoteScript -split "`r?`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') }) -join "`n"

        # -EncodedCommand expects UTF-16LE, which is what [Encoding]::Unicode produces
        # -OutputFormat Text pins stdout to plain text. It does not govern the error and
        # progress streams, which is why the script itself silences progress.
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($compact))
        $command = "powershell -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encoded"

        # cmd.exe truncates at 8191 characters, and a truncated command would fail obscurely
        if ($command.Length -gt 8000) {
            $advice = 'Deploy fewer keys per run, or use a shorter key type than RSA.'
            if ($keyList.Count -eq 1) {
                $advice = 'The key or its comment is too large for a single remote command line.'
            }

            Write-Error ("Remote command is $($command.Length) characters for $($keyList.Count) " +
                "key(s); cmd.exe cannot receive it. $advice") -ErrorAction Stop
        }

        return $command
    }


    function Install-PublicKey {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType('SshKeyInstallResult')]
        param(
            [Parameter(Mandatory)]
            [string]$SshPath,

            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter(Mandatory)]
            [string]$RemoteCommand,

            [Parameter(Mandatory)]
            [string[]]$CommonArgs,

            [Parameter()]
            [psobject]$AskPass
        )

        if (-not $PSCmdlet.ShouldProcess($Target, 'Install SSH public key')) {
            return [pscustomobject]@{
                PSTypeName = 'SshKeyInstallResult'
                Attempted  = $false
                ExitCode   = $null
                Reported   = $false
                KeyFile    = ''
                KeysAdded  = 0
                Warning    = @()
                Output     = @()
            }
        }

        # The install session used to be fire-and-forget, which left the verification step as the
        # only signal. That conflates three different outcomes - wrong password, unreachable host,
        # and a remote install that reported a specific problem - and it discarded the KEY_FILE
        # and ACL markers the remote scripts go to the trouble of emitting.
        #
        # Nothing is piped: both platform commands carry their keys inside themselves. That is
        # deliberate - Windows PowerShell 5.1 prepends a UTF-8 BOM to anything piped into a
        # native command, which corrupted the first key on the wire.
        #
        # Invoke-SshClient decides how to launch: with a console attached so the operator can
        # type a password, or - when a credential was supplied - as an isolated child whose
        # environment carries the password and whose streams are captured.
        $run = Invoke-SshClient -FilePath $SshPath `
            -ArgumentList (@($CommonArgs) + @($Target, $RemoteCommand)) -AskPass $AskPass

        $exitCode = $run.ExitCode
        $lines = @($run.Output | ForEach-Object { "$_".TrimEnd() })
        $warnings = [System.Collections.Generic.List[string]]::new()
        $reported = $false
        $keyFile = ''

        # How many entries the host actually appended, as opposed to how many were sent. They
        # differ whenever a key was already present in the file but not yet accepted by sshd.
        $added = 0

        foreach ($line in $lines) {
            if ($line -eq 'KEY_INSTALLED_OK') {
                $reported = $true
            }
            elseif ($line -match '^KEY_FILE=(.+)$') {
                $keyFile = $Matches[1]
            }
            elseif ($line -match '^KEYS_ADDED=(\d+)$') {
                $added = [int]$Matches[1]
            }
            elseif ($line -match '^ACL_WARNING=(.+)$') {
                $warnings.Add("The remote ACL could not be tightened on $($Matches[1]).")
            }
            elseif ($line -match '^ADMIN_KEYFILE_FAILED=(.+)$') {
                $warnings.Add(
                    "administrators_authorized_keys was refused ($($Matches[1])); " +
                    'the key was written to the profile file instead.')
            }
            elseif ($line) {
                # Everything else is diagnostic output from ssh or the far side. It is the only
                # clue an operator gets when a host rejects the install, so it must stay visible.
                Write-Host "    $line" -ForegroundColor Gray
            }
        }

        foreach ($warning in $warnings) {
            Write-Note $warning
        }

        return [pscustomobject]@{
            PSTypeName = 'SshKeyInstallResult'
            Attempted  = $true
            ExitCode   = $exitCode
            Reported   = $reported
            KeyFile    = $keyFile
            KeysAdded  = $added
            Warning    = $warnings.ToArray()
            Output     = $lines
        }
    }


    function Install-PublicKeySftp {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType('SshKeyInstallResult')]
        param(
            [Parameter(Mandatory)]
            [string]$SftpPath,

            [Parameter(Mandatory)]
            [string]$Target,

            [Parameter(Mandatory)]
            [string[]]$PublicKey,

            [Parameter(Mandatory)]
            [string[]]$CommonArgs,

            [Parameter()]
            [AllowEmptyString()]
            [string]$RemotePath,

            [Parameter()]
            [switch]$Trace,

            [Parameter()]
            [psobject]$AskPass
        )

        # ssh-copy-id -s exists for hosts that will not execute a command at all: a restricted
        # shell, a ForceCommand, or an account whose shell is nologin. The file transfer protocol
        # is the only way in, so the merge that the shell would have done happens locally and the
        # whole file is written back.
        $remoteFile = '.ssh/authorized_keys'
        $remoteDir = '.ssh'
        if ($RemotePath) {
            $remoteFile = $RemotePath -replace '\\', '/'
            $remoteDir = ''
            if ($remoteFile.Contains('/')) {
                $remoteDir = $remoteFile.Substring(0, $remoteFile.LastIndexOf('/'))
            }
        }

        $empty = [pscustomobject]@{
            PSTypeName = 'SshKeyInstallResult'
            Attempted  = $false
            ExitCode   = $null
            Reported   = $false
            KeyFile    = ''
            KeysAdded  = 0
            Warning    = @()
            Output     = @()
        }

        if (-not $PSCmdlet.ShouldProcess($Target, 'Install SSH public key over sftp')) {
            return $empty
        }

        # sftp turns BatchMode on by itself whenever -b is used, which disables password AND
        # passphrase prompts. That would make it impossible to install a key on a host that still
        # needs a password - the whole reason this path exists - so it is turned back off. The
        # option goes first because ssh keeps the first value it obtains for a setting.
        $sftpArgs = @('-o', 'BatchMode=no') + (ConvertTo-SftpArgument -SshArgument $CommonArgs)

        # This path sends a file, never a script, so there is no remote body to put under set -x.
        # Tracing the transfer is the nearest equivalent and answers the same question: which
        # file was touched, and what did the server say about it.
        if ($Trace) {
            $sftpArgs = @('-v') + $sftpArgs
        }
        $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("sshkeydeploy-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

        $downloadPath = Join-Path $workDirectory 'authorized_keys.remote'
        $uploadPath = Join-Path $workDirectory 'authorized_keys.merged'
        $lines = [System.Collections.Generic.List[string]]::new()
        $warnings = [System.Collections.Generic.List[string]]::new()
        $conflictDetected = $false
        $keyLost = $false

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            # Two sessions, because a single batch cannot pause for the merge. sftp's "!" shell
            # escape would avoid that, but it hands the line to the local shell, which is exactly
            # the class of quoting the rest of this script works to eliminate.
            $getBatch = Join-Path $workDirectory 'get.batch'
            [System.IO.File]::WriteAllText($getBatch,
                "-get `"$remoteFile`" `"$downloadPath`"`n", [System.Text.UTF8Encoding]::new($false))

            $getRun = Invoke-SshClient -FilePath $SftpPath `
                -ArgumentList (@($sftpArgs) + @('-b', $getBatch, $Target)) -AskPass $AskPass
            $lines.AddRange([string[]]@($getRun.Output | ForEach-Object { "$_".TrimEnd() }))

            $existing = ''
            if (Test-Path -LiteralPath $downloadPath) {
                $existing = [System.IO.File]::ReadAllText($downloadPath)
            }
            else {
                # Absent is the normal first-run case, not an error
                Write-Verbose "No existing $remoteFile on $Target; a new one will be created."
            }

            $merge = Merge-AuthorizedKeyContent -ExistingContent $existing -PublicKey $PublicKey
            [System.IO.File]::WriteAllText($uploadPath, $merge.Content, [System.Text.UTF8Encoding]::new($false))

            # sftp runs batch commands in order, so this second get captures the file as it stood
            # immediately before the upload overwrote it. Comparing it with the first read is the
            # only way to notice that something else - another run, or a person with an editor
            # open - changed the file inside our read-modify-write window. Folding it into the
            # put batch keeps the session count unchanged.
            $verifyPath = Join-Path $workDirectory 'authorized_keys.preupload'

            $putCommands = [System.Collections.Generic.List[string]]::new()
            if ($remoteDir) {
                # Leading '-' tells sftp to carry on when the directory already exists
                $putCommands.Add("-mkdir `"$remoteDir`"")
            }
            $putCommands.Add("-get `"$remoteFile`" `"$verifyPath`"")
            $putCommands.Add("put `"$uploadPath`" `"$remoteFile`"")
            $putCommands.Add("-chmod 600 `"$remoteFile`"")
            if ($remoteDir -and -not $RemotePath) {
                $putCommands.Add("-chmod 700 `"$remoteDir`"")
            }

            # Read the file back inside the same session. Costs nothing extra and is the only
            # way to notice that a third writer replaced the file between our put and now -
            # the case where this run would otherwise report a key it no longer owns.
            $postPath = Join-Path $workDirectory 'authorized_keys.postupload'
            $putCommands.Add("-get `"$remoteFile`" `"$postPath`"")

            $putBatch = Join-Path $workDirectory 'put.batch'
            [System.IO.File]::WriteAllText($putBatch, (($putCommands -join "`n") + "`n"),
                [System.Text.UTF8Encoding]::new($false))

            $putRun = Invoke-SshClient -FilePath $SftpPath `
                -ArgumentList (@($sftpArgs) + @('-b', $putBatch, $Target)) -AskPass $AskPass
            $lines.AddRange([string[]]@($putRun.Output | ForEach-Object { "$_".TrimEnd() }))

            $exitCode = $putRun.ExitCode

            $preUpload = ''
            if (Test-Path -LiteralPath $verifyPath) {
                $preUpload = [System.IO.File]::ReadAllText($verifyPath)
            }

            # Whole-file replacement cannot be made atomic over sftp, so the honest response to a
            # detected conflict is to fold the other party's version in and write again. Doing
            # nothing would leave their content destroyed and this run reporting success.
            $succeededSoFar = ($null -ne $exitCode -and $exitCode -eq 0)

            if ($preUpload -ne $existing -and $succeededSoFar) {
                Write-Note 'The file changed while this update was being prepared; merging that change back in.'
                $merge = Merge-AuthorizedKeyContent -ExistingContent $preUpload -PublicKey $PublicKey
                [System.IO.File]::WriteAllText($uploadPath, $merge.Content,
                    [System.Text.UTF8Encoding]::new($false))

                $rewriteBatch = Join-Path $workDirectory 'rewrite.batch'
                [System.IO.File]::WriteAllText($rewriteBatch,
                    "put `"$uploadPath`" `"$remoteFile`"`n-chmod 600 `"$remoteFile`"`n" +
                    "-get `"$remoteFile`" `"$postPath`"`n",
                    [System.Text.UTF8Encoding]::new($false))

                $rewriteRun = Invoke-SshClient -FilePath $SftpPath `
                    -ArgumentList (@($sftpArgs) + @('-b', $rewriteBatch, $Target)) -AskPass $AskPass
                $lines.AddRange([string[]]@($rewriteRun.Output | ForEach-Object { "$_".TrimEnd() }))

                $exitCode = $rewriteRun.ExitCode
                $succeededSoFar = ($null -ne $exitCode -and $exitCode -eq 0)

                $conflictDetected = $true
            }

            # Whatever else happened, the file as it stands must actually contain the keys this
            # run was asked to install. Without this, a run whose upload was overwritten a moment
            # later reports a key it does not own - which is exactly what four concurrent runs
            # produced before this check existed.
            if ($succeededSoFar -and (Test-Path -LiteralPath $postPath)) {
                $postContent = [System.IO.File]::ReadAllText($postPath)
                $postLines = @($postContent -split "`r?`n" | ForEach-Object { $_.Trim() })

                $absent = @($PublicKey | ForEach-Object { "$_".Trim() } |
                        Where-Object { $_ -and $postLines -notcontains $_ })

                if ($absent.Count -gt 0) {
                    $keyLost = $true
                    Write-Bad "$($absent.Count) key(s) were not present after the upload."
                }
            }
        }
        finally {
            $ErrorActionPreference = $previous

            # Removed here rather than after the block: an exception on the way through -
            # a full disk while writing the merge, say - would otherwise leave the download
            # and the batch files behind. Everything still needed below is already in
            # memory, so deleting the directory now is safe.
            Remove-Item -Path $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Both batches lead the tolerant commands with '-', so sftp reports their failure and
        # carries on. Those two are the normal first-run case - no authorized_keys yet, and a
        # home directory that already exists - and showing them reads as though something broke.
        $expected = @(
            '^File ".*" not found\.?$'
            '^remote mkdir ".*": (Failure|File exists)$'
            '^Couldn''t stat remote file: No such file or directory$'
            '^(sftp>|Connected to|Fetching|Uploading|Changing mode|Remote working directory)'
        ) -join '|'

        foreach ($line in $lines) {
            if ($line -and $line -notmatch $expected) {
                Write-Host "    $line" -ForegroundColor Gray
            }
        }

        # A lost key is a failed install, however cleanly sftp itself exited. Reporting success
        # for a key that is not in the file is the one outcome that must never happen.
        $succeeded = ($null -ne $exitCode -and $exitCode -eq 0 -and -not $keyLost)

        if ($keyLost) {
            $warnings.Add('The key was not in the file after the upload, so another writer ' +
                'replaced it. Nothing was installed by this run; retry when the file is quiet.')
            Write-Note $warnings[$warnings.Count - 1]
        }

        if ($conflictDetected) {
            # Recorded on the result so it survives into RemoteMessage and any CSV the operator
            # exports. Whole-file replacement over sftp has no compare-and-swap, so the window
            # cannot be closed entirely - only narrowed, detected, and repaired.
            $warnings.Add('Another writer changed this file during the update; their version was ' +
                'merged and rewritten. Re-check the file if anything else was editing it.')
        }

        if (-not $succeeded -and $existing) {
            # The upload rewrites the whole file, so a failure mid-transfer could leave it short.
            # The copy that was downloaded first is the operator's way back.
            $rescue = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("authorized_keys.rescue-" + [Guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText($rescue, $existing, [System.Text.UTF8Encoding]::new($false))

            # "The upload failed" would be untrue in the lost-key case, where it succeeded and was
            # then replaced. They also call for different handling: this copy predates the other
            # writer's change, so restoring it there would destroy their work along with ours.
            if ($keyLost) {
                $warnings.Add('Another writer replaced the file after this run wrote it. The copy ' +
                    "taken before the change is at $rescue - compare before restoring it, because " +
                    'it predates their change as well.')
            }
            else {
                $warnings.Add('The sftp upload failed; the file as it was before this run is ' +
                    "saved at $rescue.")
            }

            Write-Note $warnings[$warnings.Count - 1]
        }

        return [pscustomobject]@{
            PSTypeName = 'SshKeyInstallResult'
            Attempted  = $true
            ExitCode   = $exitCode
            Reported   = $succeeded
            KeyFile    = $remoteFile
            KeysAdded  = $(if ($succeeded) { $merge.KeysAdded } else { 0 })
            Warning    = $warnings.ToArray()
            Output     = $lines.ToArray()
        }
    }


    function Format-SshConfigBlock {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory)]
            [string]$HostPattern,

            [Parameter(Mandatory)]
            [string]$HostAddress,

            [Parameter(Mandatory)]
            [string]$User,

            [Parameter(Mandatory)]
            [string]$KeyPath,

            [Parameter(Mandatory)]
            [int]$Port,

            [Parameter()]
            [switch]$IncludeHostName
        )

        # ssh_config takes a quoted path when it contains spaces
        $identityFile = $KeyPath
        if ($identityFile -match '\s') {
            $identityFile = '"{0}"' -f $identityFile
        }

        $block = [System.Collections.Generic.List[string]]::new()
        $block.Add("Host $HostPattern")

        if ($IncludeHostName) {
            $block.Add("    HostName $HostAddress")
        }

        $block.Add("    User $User")
        $block.Add("    Port $Port")
        $block.Add("    IdentityFile $identityFile")

        return $block.ToArray()
    }


    function Find-SshConfigBlock {
        [CmdletBinding()]
        [OutputType('SshConfigBlockMatch')]
        param(
            # Blank separator lines are ordinary content here, so empty elements must bind
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line,

            [Parameter(Mandatory)]
            [string[]]$Token
        )

        $startIndex = -1

        for ($i = 0; $i -lt $Line.Count; $i++) {
            if ($Line[$i] -notmatch '^\s*Host\s+(.+?)\s*$') {
                continue
            }

            $patterns = @($Matches[1] -split '\s+')
            if (@($patterns | Where-Object { $Token -contains $_ }).Count -gt 0) {
                $startIndex = $i
                break
            }
        }

        if ($startIndex -lt 0) {
            return $null
        }

        # A block runs until the next Host/Match keyword, or the end of the file
        $endIndex = $Line.Count - 1
        for ($j = $startIndex + 1; $j -lt $Line.Count; $j++) {
            if ($Line[$j] -match '^\s*(Host|Match)\s+') {
                $endIndex = $j - 1
                break
            }
        }

        # Leave any blank separator lines in place so replacement keeps the file's spacing
        while ($endIndex -gt $startIndex -and [string]::IsNullOrWhiteSpace($Line[$endIndex])) {
            $endIndex--
        }

        return [pscustomobject]@{
            PSTypeName = 'SshConfigBlockMatch'
            StartIndex = $startIndex
            EndIndex   = $endIndex
        }
    }


    function Set-SshConfigContent {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        if (-not $PSCmdlet.ShouldProcess($Path, 'Write ssh config file')) {
            return
        }

        # LF endings only: OpenSSH reads this file, and stray CRs have already caused
        # one round of trouble in authorized_keys
        $content = ($Line -join "`n") + "`n"
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
    }


    function Update-SshConfigEntry {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$ConfigPath,

            [Parameter(Mandatory)]
            [string]$HostAddress,

            [Parameter(Mandatory)]
            [string]$User,

            [Parameter(Mandatory)]
            [string]$KeyPath,

            [Parameter(Mandatory)]
            [int]$Port,

            [Parameter()]
            [AllowEmptyString()]
            [string]$Alias,

            [Parameter()]
            [switch]$Force
        )

        $tokens = @($HostAddress)
        $hostPattern = $HostAddress
        $includeHostName = $false

        if ($Alias) {
            # One block serving both names, so "ssh <alias>" and "ssh <host>" both resolve
            $tokens = @($Alias, $HostAddress)
            $hostPattern = "$Alias $HostAddress"
            $includeHostName = $true
        }

        $blockParams = @{
            HostPattern     = $hostPattern
            HostAddress     = $HostAddress
            User            = $User
            KeyPath         = $KeyPath
            Port            = $Port
            IncludeHostName = $includeHostName
        }
        $newBlock = Format-SshConfigBlock @blockParams

        $configDir = Split-Path -Path $ConfigPath -Parent
        if ($configDir -and -not (Test-Path -Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        $existingLines = @()
        if (Test-Path -Path $ConfigPath) {
            $existingLines = @(Get-Content -Path $ConfigPath)
        }

        $match = Find-SshConfigBlock -Line $existingLines -Token $tokens
        $output = [System.Collections.Generic.List[string]]::new()

        if (-not $match) {
            if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Add ssh config entry for $HostAddress")) {
                return $false
            }

            if ($existingLines.Count -gt 0) {
                $output.AddRange([string[]]$existingLines)
                if (-not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
                    $output.Add('')
                }
            }

            $output.AddRange([string[]]$newBlock)
            Set-SshConfigContent -Path $ConfigPath -Line $output.ToArray()
            Write-Ok "Added ssh config entry: Host $hostPattern"
            return $true
        }

        Write-Note "An ssh config entry already exists for '$HostAddress':"
        foreach ($current in $existingLines[$match.StartIndex..$match.EndIndex]) {
            Write-Host "      $current" -ForegroundColor Gray
        }

        if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Replace ssh config entry for $HostAddress")) {
            return $false
        }

        $query = "Replace it with: Host $hostPattern / User $User / Port $Port ?"
        $caption = "Overwrite existing ssh config entry for $HostAddress"
        $replace = $false

        if ($Force) {
            Write-Note 'Overwrite confirmation bypassed by request.'
            $replace = $true
        }
        else {
            # ShouldContinue throws when the host has no console input left to read (scheduled
            # task, CI, or because ssh already consumed stdin). Confirmation is impossible there,
            # so deny rather than aborting a run that has already installed keys.
            try {
                $replace = $PSCmdlet.ShouldContinue(
                    $query,
                    $caption,
                    [ref]$script:SshConfigYesToAll,
                    [ref]$script:SshConfigNoToAll)
            }
            catch {
                Write-Note 'Cannot prompt for confirmation in this session; leaving the entry alone.'
                Write-Note "Re-run interactively, or pass -ForceConfigUpdate, to replace it."
                return $false
            }
        }

        if (-not $replace) {
            Write-Note "Kept the existing entry for '$HostAddress'; config not modified."
            return $false
        }

        if ($match.StartIndex -gt 0) {
            $output.AddRange([string[]]$existingLines[0..($match.StartIndex - 1)])
        }

        $output.AddRange([string[]]$newBlock)

        if ($match.EndIndex -lt ($existingLines.Count - 1)) {
            $tailStart = $match.EndIndex + 1
            $output.AddRange([string[]]$existingLines[$tailStart..($existingLines.Count - 1)])
        }

        Set-SshConfigContent -Path $ConfigPath -Line $output.ToArray()
        Write-Ok "Replaced ssh config entry: Host $hostPattern"
        return $true
    }


    function New-SampleHostFile {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$DefaultUser,

            [Parameter()]
            [switch]$Force
        )

        $exists = Test-Path -Path $Path
        $action = 'Create sample host file'
        if ($exists) {
            $action = 'Overwrite existing file with sample host file'
        }

        if (-not $PSCmdlet.ShouldProcess($Path, $action)) {
            return $false
        }

        if ($exists) {
            if ($Force) {
                Write-Note 'Overwrite confirmation bypassed by request.'
            }
            else {
                Write-Note "A file already exists at: $Path"

                # Same reasoning as the ssh config prompt: when confirmation is impossible,
                # decline rather than destroying a host list the user may have curated.
                try {
                    $overwrite = $PSCmdlet.ShouldContinue(
                        'Overwrite it with the sample template?',
                        "Overwrite $Path")
                }
                catch {
                    Write-Note 'Cannot prompt for confirmation in this session; leaving the file alone.'
                    Write-Note 'Re-run interactively, or pass -Force, to overwrite it.'
                    return $false
                }

                if (-not $overwrite) {
                    Write-Note 'Kept the existing file; nothing was written.'
                    return $false
                }
            }
        }

        $parent = Split-Path -Path $Path -Parent
        if ($parent -and -not (Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        # Every example is commented out on purpose: a freshly generated file should never
        # send the script at hosts the user has not chosen.
        $sample = @(
            '# Host list for Deploy-SshKey.ps1'
            '#'
            '# One target per line. Blank lines and lines beginning with # are ignored.'
            '#'
            '# Accepted formats:'
            "#   server1          uses the -User value (currently: $DefaultUser)"
            '#   admin@server2    overrides the user for that one host'
            '#   10.0.0.15        IP addresses are fine'
            '#'
            '# Linux and Windows OpenSSH servers may be mixed freely; each host is detected'
            '# from its SSH banner. Use -TargetPlatform to state it explicitly.'
            '#'
            '# Rules enforced by the script:'
            '#   - No spaces inside an entry'
            '#   - An entry must not begin with a dash, which ssh would read as an option'
            '#   - Each entry, once combined with the user, must match:'
            '#       ^[A-Za-z0-9._-]+(@[A-Za-z0-9._-]+)*@[A-Za-z0-9._:\[\]-]+$'
            '#     The repeated group allows a UPN login (admin@corp.example@dc01); the host'
            '#     part allows ":" and brackets, so an IPv6 literal is also a valid target'
            '#'
            '# Then run:'
            '#   .\Deploy-SshKey.ps1 -HostFile .\hosts.txt'
            '#'
            '# Uncomment and edit the lines below, or replace them with your own.'
            '#server1'
            '#admin@server2'
            '#10.0.0.15'
        )

        [System.IO.File]::WriteAllText(
            $Path,
            (($sample -join "`n") + "`n"),
            [System.Text.UTF8Encoding]::new($false))

        Write-Ok "Sample host file written: $Path"
        Write-Info 'Edit it, uncomment the hosts you want, then re-run with -HostFile.'
        return $true
    }


    function Invoke-DeploySshKey {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
            Justification = 'Emits PSCustomObjects tagged with PSTypeName SshKeyDeploymentResult.')]
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType('SshKeyDeploymentResult')]
        param(
            [Parameter()]
            [string[]]$ComputerName,

            [Parameter()]
            [string]$HostFile,

            [Parameter(Mandatory)]
            [string]$User,

            [Parameter(Mandatory)]
            [int]$Port,

            [Parameter(Mandatory)]
            [string]$KeyPath,

            [Parameter(Mandatory)]
            [string]$KeyType,

            [Parameter(Mandatory)]
            [string]$Comment,

            [Parameter(Mandatory)]
            [string]$CorrelationId,

            [Parameter(Mandatory)]
            [string]$SshConfigPath,

            [Parameter()]
            [ValidateSet('Auto', 'Linux', 'Windows')]
            [string]$TargetPlatform = 'Auto',

            [Parameter()]
            [ValidateSet('Auto', 'Administrators', 'UserProfile')]
            [string]$WindowsKeyLocation = 'Auto',

            [Parameter()]
            [AllowEmptyString()]
            [string]$RemoteAuthorizedKeysPath,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$SshOption = @(),

            [Parameter()]
            [ValidateSet('accept-new', 'yes', 'no', 'ask')]
            [string]$StrictHostKeyChecking = 'accept-new',

            [Parameter()]
            [ValidateSet('Auto', 'Direct', 'Encoded')]
            [string]$PosixTransport = 'Auto',

            [Parameter()]
            [AllowEmptyString()]
            [string]$ConfigAlias,

            [Parameter()]
            [switch]$Force,

            [Parameter()]
            [switch]$RequireExistingKey,

            [Parameter()]
            [switch]$ForceInstall,

            [Parameter()]
            [switch]$UseAgentKeys,

            [Parameter()]
            [switch]$UseSftp,

            [Parameter()]
            [switch]$UpdateSshConfig,

            [Parameter()]
            [switch]$ForceConfigUpdate,

            [Parameter()]
            [AllowEmptyString()]
            [string]$SshConfigFile,

            [Parameter()]
            [switch]$TraceRemoteCommand,

            # The askpass descriptor, when -Credential was supplied. Carries the credential
            # still wrapped in its SecureString; plaintext appears only inside a child's
            # environment block, never in this process.
            [Parameter()]
            [psobject]$AskPass,

            # Set when the caller named the parameter explicitly. Without this the script cannot
            # tell "-Port 22" from the default, and would force 22 onto a host whose ssh config
            # block specifies another port - overriding the very file -UpdateSshConfig writes.
            [Parameter()]
            [switch]$PortSpecified,

            [Parameter()]
            [switch]$UserSpecified,

            # The client config ssh reads for itself, which is not the same file as -SshConfigPath:
            # that one is only ever written to. Separate parameter so tests can point it elsewhere.
            [Parameter()]
            [AllowEmptyString()]
            [string]$ClientConfigPath,

            # Set by the entry point only when the run is interactive. A pipeline-driven or
            # scheduled run must fail on an empty host list rather than stop to ask.
            [Parameter()]
            [switch]$AllowPrompt
        )

        Write-Verbose "Deployment started - CorrelationId: $CorrelationId"

        $tools = Get-OpenSshTool

        if ($UseSftp -and -not $tools.Sftp) {
            Write-Error 'sftp.exe was not found on PATH, so -UseSftp cannot be used.' -ErrorAction Stop
        }

        # ssh-copy-id is given the public key; the private half is what this script needs. Accept
        # the habit rather than hunting for a nonexistent <name>.pub.pub.
        if ($KeyPath -like '*.pub') {
            $KeyPath = $KeyPath.Substring(0, $KeyPath.Length - 4)
            Write-Note "-KeyPath named a public key; using the private key at $KeyPath."
        }

        # ssh-copy-id -F. Checked here rather than left to ssh, which exits 255 on a config file
        # it cannot open - a code this script otherwise reports as a transport or authentication
        # failure, sending the operator to look at passwords and firewalls over a typo in a path.
        if ($SshConfigFile) {
            if (-not (Test-Path -LiteralPath $SshConfigFile)) {
                Write-Error "SSH config file not found: $SshConfigFile" -ErrorAction Stop
            }

            # -F is the file ssh reads, so User/HostName/Port resolution must read the same one
            $ClientConfigPath = $SshConfigFile
        }

        # Caller-supplied options come first because ssh takes the FIRST value it obtains for a
        # setting. That ordering is what lets -SshOption override the defaults below rather than
        # being silently discarded by them.
        $sshArgs = [System.Collections.Generic.List[string]]::new()

        # Named before everything else so there is no doubt which file the run resolves against.
        # -o values on the command line still beat anything inside it, which is ssh's own rule.
        if ($SshConfigFile) {
            $sshArgs.Add('-F')
            $sshArgs.Add($SshConfigFile)
        }

        foreach ($option in $SshOption) {
            if ($option) {
                $sshArgs.Add('-o')
                $sshArgs.Add($option)
            }
        }

        if ($PortSpecified) {
            $sshArgs.Add('-p')
            $sshArgs.Add("$Port")
        }

        # -SshConfigPath is deliberately NOT what gets passed as -F. It is a write target that
        # -UpdateSshConfig may be about to create, and ssh exits 255 on a config file that does
        # not exist yet, so pointing -F at it would break the very case it exists for. The read
        # side is -SshConfigFile above, which is validated before use. With neither supplied, no
        # -F is sent at all and ssh reads its own defaults, including the system-wide config that
        # any -F would suppress.

        $sshArgs.AddRange([string[]]@(
                '-o', "StrictHostKeyChecking=$StrictHostKeyChecking"
                '-o', 'ConnectTimeout=15'
            ))

        if ($AskPass) {
            # One attempt. The helper returns the same value every time it is asked, so the
            # default three prompts turn a wrong password into three identical rejections
            # and a threefold delay - and, on OpenSSH 9.8+, a threefold PerSourcePenalties
            # charge, which can lock this machine out of the target for minutes.
            $sshArgs.AddRange([string[]]@('-o', 'NumberOfPasswordPrompts=1'))
        }

        # Deliberately no -i here. Each key is probed with its own "-i <identity> -o
        # IdentitiesOnly=yes" so the answer is about that key rather than whatever the agent
        # offers first, which is what makes installing several identities in one pass possible.
        $baseArgs = $sshArgs.ToArray()

        # The install session is a different question: it only has to authenticate somehow. In
        # single-key mode it is pinned to the key being deployed, matching previous behaviour.
        # With -UseAgentKeys any identity the agent already holds may authenticate it, which
        # spares a password prompt on a host that accepts one of the keys but not the others.
        $commonArgs = $baseArgs
        if (-not $UseAgentKeys) {
            $commonArgs = @($baseArgs) + @('-i', $KeyPath, '-o', 'IdentitiesOnly=yes')
        }

        # Reading the client config costs one extra ssh process per host, so it is only consulted
        # when there is a config to read. It answers what ssh itself would use for a bare host
        # name, which is the only way an alias written by -UpdateSshConfig works on the next run.
        $consultConfig = $ClientConfigPath -and (Test-Path -Path $ClientConfigPath)

        $userResolver = $null
        if ($consultConfig -and -not $UserSpecified) {
            $userResolver = {
                param($HostEntry)

                (Get-SshEffectiveConfig -SshPath $tools.Ssh -Target $HostEntry `
                        -SshArgument $commonArgs).User
            }
        }

        $resolveParams = @{
            ProvidedHosts    = $ComputerName
            ProvidedHostFile = $HostFile
            DefaultUser      = $User
            UserResolver     = $userResolver
            AllowPrompt      = $AllowPrompt
        }
        $targetCandidates = @(Resolve-TargetList @resolveParams)

        $targets = [System.Collections.Generic.List[string]]::new()
        foreach ($targetCandidate in $targetCandidates) {
            if (Test-ValidTarget -Target $targetCandidate) {
                $targets.Add($targetCandidate)
                continue
            }

            Write-Warning ("Rejected target '$targetCandidate': not a valid user@host value " +
                "- CorrelationId: $CorrelationId")
        }

        if ($targets.Count -eq 0) {
            Write-Error 'No valid target hosts were provided.' -ErrorAction Stop
        }

        $candidates = [System.Collections.Generic.List[object]]::new()
        $scratchDirectory = ''

        # Sweep anything an interrupted run left behind, whichever path created it - the sftp
        # working directory and the agent scratch directory share this prefix. Done for every
        # run rather than only in agent mode, because a run that dies hard cannot tidy up
        # after itself and would otherwise accumulate until someone happened to use
        # -UseAgentKeys. An hour is well clear of any legitimate in-flight run, and the
        # contents are public keys, so this is housekeeping rather than hygiene.
        Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter 'sshkeydeploy-*' `
            -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -lt (Get-Date).AddHours(-1) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        if ($UseAgentKeys) {
            # ssh-copy-id's no--i behaviour: the agent is the source of identities, and no key
            # file is read, generated or hardened, because none is involved.
            $agentKeys = @(Get-AgentPublicKey)
            if ($agentKeys.Count -eq 0) {
                Write-Error 'No identities found in the ssh agent. Load one with ssh-add, or drop -UseAgentKeys.' `
                    -ErrorAction Stop
            }

            # ssh needs a file to point -i at when probing a single agent identity. The public
            # half is enough; the agent supplies the private key that matches it.
            $scratchDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("sshkeydeploy-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $scratchDirectory -Force | Out-Null

            $index = 0
            foreach ($agentKey in $agentKeys) {
                $index++
                $scratchPath = Join-Path $scratchDirectory "agent$index.pub"
                [System.IO.File]::WriteAllText($scratchPath, $agentKey + "`n",
                    [System.Text.UTF8Encoding]::new($false))

                $agentFingerprint = Get-PublicKeyFingerprint -Path $scratchPath `
                    -SshKeygenPath $tools.SshKeygen
                $candidates.Add((New-KeyCandidate -Line $agentKey -IdentityPath $scratchPath `
                            -Fingerprint $agentFingerprint))
            }

            Write-Info "Agent holds $($candidates.Count) identity/identities:"
            foreach ($candidate in $candidates) {
                Write-Host "    $($candidate.Label)" -ForegroundColor Gray
            }
        }
        else {
            $keyParams = @{
                KeyPath            = $KeyPath
                KeyType            = $KeyType
                Comment            = $Comment
                SshKeygenPath      = $tools.SshKeygen
                Force              = $Force
                RequireExistingKey = $RequireExistingKey
            }
            $pubPath = Initialize-KeyPair @keyParams
            Set-PrivateKeyAcl -KeyPath $KeyPath

            if (-not (Test-Path -Path $pubPath)) {
                Write-Note "Public key not present: $pubPath"
                Write-Note 'This is expected with -WhatIf; no hosts were contacted.'
                return
            }

            $pubContent = Get-Content -Path $pubPath -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($pubContent)) {
                Write-Error "Public key is empty or unreadable: $pubPath" -ErrorAction Stop
            }
            $pubLine = $pubContent.Trim()

            # A .pub file holds exactly one key. More than one line means the wrong file was
            # named, or two keys were concatenated into it - either way, piping it to a POSIX
            # host would append a broken entry, and embedding it in the Windows script would
            # split a statement.
            if ($pubLine -match '[\r\n]') {
                Write-Error "Public key file contains more than one line: $pubPath" -ErrorAction Stop
            }

            Write-Info "Public key: $pubPath"
            $fingerprint = & $tools.SshKeygen -lf $pubPath
            Write-Info "Fingerprint: $fingerprint"

            $keyFingerprint = Get-PublicKeyFingerprint -Path $pubPath -SshKeygenPath $tools.SshKeygen
            $candidates.Add((New-KeyCandidate -Line $pubLine -IdentityPath $KeyPath `
                        -Fingerprint $keyFingerprint))
        }

        # Every reachability probe runs with BatchMode, which refuses to prompt for a passphrase
        # just as it refuses to prompt for a password. An encrypted key that no agent holds
        # therefore fails both probes, and the run would report Failed for hosts where the key
        # works. Establish that once, up front, instead of misreporting every host.
        # -UseAgentKeys is exempt by definition: every identity comes from the agent already.
        $canProbe = $true
        if (-not $UseAgentKeys -and (Test-PrivateKeyEncrypted -KeyPath $KeyPath)) {
            if (Test-SshAgentHasKey -PublicKeyLine $candidates[0].Line) {
                Write-Info 'The key is passphrase-protected but loaded in the agent; probes still work.'
            }
            else {
                $canProbe = $false
                Write-Note 'The private key is passphrase-protected and is not loaded into an ssh agent.'
                Write-Note 'Reachability cannot be probed without prompting, so installation will be'
                Write-Note "taken from the remote host's own confirmation and Verified will be False."
                Write-Host ("    Run: ssh-add `"$KeyPath`"   then re-run to verify properly.") `
                    -ForegroundColor Gray
            }
        }

        # Both commands embed the keys, so both are built per host from whatever that host is
        # still missing rather than once up front.

        $results = [System.Collections.Generic.List[object]]::new()

        foreach ($target in $targets) {
            Write-Host ''
            Write-Info "Processing $target ..."

            # The banner probe opens a raw socket, so it resolves neither the port nor the address
            # the way ssh does. A Host block can supply both, and an alias is frequently a name
            # DNS knows nothing about. Ask ssh what it resolved before assuming anything.
            $effectivePort = $Port
            $resolvedAddress = ''
            if ($consultConfig) {
                $effective = Get-SshEffectiveConfig -SshPath $tools.Ssh -Target $target `
                    -SshArgument $commonArgs

                $resolvedAddress = $effective.HostName
                if ($resolvedAddress -and $resolvedAddress -ne (Get-SshTargetPart -Target $target).HostAddress) {
                    Write-Info "ssh config resolves this host to $resolvedAddress."
                }

                if (-not $PortSpecified -and $effective.Port -gt 0) {
                    $effectivePort = $effective.Port
                    if ($effective.Port -ne $Port) {
                        Write-Info "ssh config resolves this host to port $($effective.Port)."
                    }
                }
            }

            $platformParams = @{
                Target              = $target
                Port                = $effectivePort
                Preference          = $TargetPlatform
                ResolvedHostAddress = $resolvedAddress
            }
            $platform = Resolve-RemotePlatform @platformParams
            Write-Info "Target platform: $platform"

            # The pre-check answers "does this key already grant access", not "is it in the file
            # you asked for". Naming a specific file makes those different questions, so the
            # check must not be allowed to skip the install that was explicitly requested.
            $skipPreCheck = $ForceInstall -or $RemoteAuthorizedKeysPath

            # Which keys this host still needs, decided one key at a time. ssh-copy-id filters the
            # same way, and it is the only check that reflects the file sshd actually reads.
            # An sftp-only account cannot run the sentinel command, so both probes have to settle
            # for "the server accepted this key", which is the thing actually being asked about.
            $keyAuthOnly = [bool]($UseSftp -and $platform -ne 'Windows')

            $pending = @($candidates)
            if ($canProbe -and -not $skipPreCheck) {
                $pending = @(Select-UninstalledKey -SshPath $tools.Ssh -Target $target `
                        -Candidate $candidates.ToArray() -CommonArgs $baseArgs -KeyAuthOnly:$keyAuthOnly)
            }

            if ($pending.Count -eq 0) {
                $plural = if ($candidates.Count -eq 1) { 'this key' } else { "all $($candidates.Count) keys" }
                Write-Ok "$target already accepts $plural - skipping."
                $results.Add([pscustomobject]@{
                    PSTypeName       = 'SshKeyDeploymentResult'
                    ComputerName     = $target
                    Platform         = $platform
                    Status           = 'AlreadyConfigured'
                    Verified         = $true
                    KeyPath          = $KeyPath
                    KeysInstalled    = 0
                    RemoteKeyFile    = ''
                    Port             = $effectivePort
                    RemoteMessage    = ''
                    SshConfigUpdated = $false
                    CorrelationId    = $CorrelationId
                    Timestamp        = Get-Date
                })
                continue
            }

            if ($candidates.Count -gt 1) {
                Write-Info "$($pending.Count) of $($candidates.Count) key(s) still need installing."
            }

            Write-Note "You'll be asked for $target's password once to install the key(s)."
            $pendingLines = @($pending | ForEach-Object { $_.Line })

            if ($UseSftp -and $platform -eq 'Windows') {
                # sftp can write the file but cannot set the ACL sshd insists on for
                # administrators_authorized_keys, so the key would install and still be refused.
                Write-Note 'Ignoring -UseSftp for this Windows target; it cannot set the required ACL.'
            }

            # Each branch builds only the command it is about to send. The POSIX builder used to
            # run for every host and have its result thrown away on a Windows target, which was
            # not merely wasteful: it refuses a -PosixTransport this client cannot honour, so
            # "-TargetPlatform Windows -PosixTransport Direct" aborted the whole run on a client
            # that mangles quotes - over a setting documented as not applying to Windows at all.
            # The sftp path sends no shell command, so it builds neither.
            if ($UseSftp -and $platform -ne 'Windows') {
                $install = Install-PublicKeySftp -SftpPath $tools.Sftp -Target $target `
                    -PublicKey $pendingLines -CommonArgs $commonArgs `
                    -RemotePath $RemoteAuthorizedKeysPath -Trace:$TraceRemoteCommand `
                    -AskPass $AskPass
            }
            else {
                if ($platform -eq 'Windows') {
                    $remoteCommand = New-WindowsInstallCommand -PublicKey $pendingLines `
                        -KeyLocation $WindowsKeyLocation -RemotePath $RemoteAuthorizedKeysPath `
                        -Trace:$TraceRemoteCommand
                }
                else {
                    $remoteCommand = New-PosixInstallCommand -PublicKey $pendingLines `
                        -RemotePath $RemoteAuthorizedKeysPath -Transport $PosixTransport `
                        -Trace:$TraceRemoteCommand
                }

                $install = Install-PublicKey -SshPath $tools.Ssh -Target $target `
                    -RemoteCommand $remoteCommand -CommonArgs $commonArgs -AskPass $AskPass
            }

            # Verify the keys that were just installed, not merely that some connection works.
            # With several identities in play, "one of them authenticates" is not the question.
            $verified = $false
            if ($canProbe) {
                $stillMissing = @(Select-UninstalledKey -SshPath $tools.Ssh -Target $target `
                        -Candidate $pending -CommonArgs $baseArgs -KeyAuthOnly:$keyAuthOnly)
                $verified = ($stillMissing.Count -eq 0)

                if (-not $verified -and $stillMissing.Count -lt $pending.Count) {
                    Write-Note "$($stillMissing.Count) of $($pending.Count) key(s) are still not accepted:"
                    foreach ($missing in $stillMissing) {
                        Write-Host "    $($missing.Label)" -ForegroundColor Gray
                    }
                }
            }

            if (-not $install.Attempted) {
                # -WhatIf declined the install, so neither Installed nor Failed is honest.
                #
                # ssh-copy-id -n names the keys it would have added. The ShouldProcess message
                # alone does not, and "which identity would this actually deploy" is the entire
                # question a dry run is asked - particularly here, where the key may have been
                # generated moments ago or pulled from an agent holding several.
                Write-Note "Would have added $($pending.Count) key(s) to ${target}:"
                foreach ($wouldAdd in $pending) {
                    $detail = $wouldAdd.Label
                    if ($wouldAdd.Fingerprint) {
                        $detail = '{0}  {1}' -f $wouldAdd.Label, $wouldAdd.Fingerprint
                    }
                    Write-Host "    $detail" -ForegroundColor Gray
                }

                $status = 'Skipped'
            }
            elseif ($verified) {
                $what = if ($pending.Count -eq 1) { 'Passwordless SSH' } else { "All $($pending.Count) keys" }
                Write-Ok "$what confirmed for $target."

                # A forced run against a file that already held the key adds nothing, and saying
                # so is the difference between "it worked" and "it did what you expected"
                if ($install.KeysAdded -eq 0) {
                    Write-Note 'No new entry was needed; the key was already in that file.'
                }
                elseif ($install.KeysAdded -gt 1) {
                    Write-Ok "$($install.KeysAdded) key(s) added to $($install.KeyFile)."
                }

                $status = 'Installed'
            }
            elseif (-not $canProbe -and $install.Reported) {
                Write-Ok "$target reported the key was installed."
                Write-Note 'Passwordless access was not verified; the key needs a passphrase.'
                $status = 'Installed'
            }
            else {
                Write-Bad "Key not confirmed for $target."

                # The install session is the only place that distinguishes "could not connect or
                # authenticate" from "wrote the key, but sshd will not read it". Without this the
                # operator gets the same generic hint for both.
                if ($install.Reported) {
                    $written = $install.KeyFile
                    if (-not $written) {
                        $written = 'the authorized_keys file'
                    }
                    Write-Note "The host confirmed the key was written to $written, so sshd is not reading it."
                }
                elseif ($null -ne $install.ExitCode -and $install.ExitCode -eq 255) {
                    Write-Note 'ssh exited 255: a transport or authentication failure, not a key problem.'
                    Write-Note 'Check the password, the port, and that password authentication is enabled.'
                }
                elseif ($null -ne $install.ExitCode -and $install.ExitCode -ne 0) {
                    Write-Note ("The install session exited with code $($install.ExitCode) " +
                        'and never confirmed success.')
                }
                else {
                    Write-Note 'The host never returned the installation sentinel.'
                }

                # The encoded transport needs base64 on the target, and BSD and macOS spell
                # its decode flag -D where GNU uses -d. Both that and an absent base64 land
                # here, where the generic hint would send the operator to inspect sshd
                # permissions over what is really a decoder mismatch on the far side.
                $base64Trouble = @($install.Output | Where-Object {
                        $_ -match 'base64' -and
                        $_ -match 'illegal option|invalid option|unrecognized option|not found|command not found'
                    })

                if ($base64Trouble.Count -gt 0) {
                    Write-Note 'That failure came from base64 on the target, not from sshd.'
                    Write-Host '     BSD and macOS spell the decode flag -D; GNU coreutils uses -d.' `
                        -ForegroundColor Gray
                    Write-Host '     base64 is only needed because this PowerShell cannot escape quotes' `
                        -ForegroundColor Gray
                    Write-Host '     in a native command line. Running the same deployment from' `
                        -ForegroundColor Gray
                    Write-Host '     PowerShell 7.2 or later sends a plain shell command instead and' `
                        -ForegroundColor Gray
                    Write-Host '     needs nothing on the target beyond a POSIX shell.' -ForegroundColor Gray
                }
                else {
                    Write-RemediationHint -Platform $platform
                }
                Write-Verbose "Install verification failed for $target - CorrelationId: $CorrelationId"
                $status = 'Failed'
            }

            $results.Add([pscustomobject]@{
                PSTypeName       = 'SshKeyDeploymentResult'
                ComputerName     = $target
                Platform         = $platform
                Status           = $status
                Verified         = $verified
                KeyPath          = $KeyPath
                # What the host actually appended, not what was sent. They differ whenever a key
                # was already in the file but not yet accepted - a forced re-run, or a file sshd
                # is not reading.
                KeysInstalled    = $install.KeysAdded
                RemoteKeyFile    = $install.KeyFile
                Port             = $effectivePort
                RemoteMessage    = ($install.Warning -join ' ')
                SshConfigUpdated = $false
                CorrelationId    = $CorrelationId
                Timestamp        = Get-Date
            })
        }

        if ($UpdateSshConfig -and $UseAgentKeys) {
            # A Host block records one IdentityFile. With the agent supplying several identities
            # there is no single file to name, and writing an arbitrary one would be a lie.
            Write-Warning '-UpdateSshConfig needs a single identity file; skipping it for -UseAgentKeys.'
        }
        elseif ($UpdateSshConfig) {
            Write-Host ''
            Write-Info "Updating ssh config: $SshConfigPath"

            $effectiveAlias = $ConfigAlias
            if ($ConfigAlias -and $targets.Count -gt 1) {
                Write-Warning "-ConfigAlias suits a single host; ignoring it for $($targets.Count) targets."
                $effectiveAlias = ''
            }

            foreach ($result in $results) {
                if ($result.Status -in 'Failed', 'Skipped') {
                    Write-Note "Skipping ssh config entry for $($result.ComputerName); nothing was deployed."
                    continue
                }

                $parts = Get-SshTargetPart -Target $result.ComputerName
                $entryParams = @{
                    ConfigPath  = $SshConfigPath
                    HostAddress = $parts.HostAddress
                    User        = $parts.User
                    KeyPath     = $KeyPath
                    Port        = $result.Port
                    Alias       = $effectiveAlias
                    Force       = $ForceConfigUpdate
                }
                $result.SshConfigUpdated = Update-SshConfigEntry @entryParams
            }
        }

        $okCount = @($results | Where-Object { $_.Status -in 'Installed', 'AlreadyConfigured' }).Count
        Write-Host ''
        Write-Ok "$okCount / $($results.Count) host(s) ready for passwordless SSH."

        if ($UseAgentKeys) {
            Write-Host "Try it:  ssh $($targets[0])" -ForegroundColor Gray
        }
        else {
            Write-Host "Try it:  ssh -i `"$KeyPath`" $($targets[0])" -ForegroundColor Gray
        }

        if ($scratchDirectory -and (Test-Path -Path $scratchDirectory)) {
            Remove-Item -Path $scratchDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Verbose "Deployment completed - CorrelationId: $CorrelationId"

        return $results
    }


    # Dot-sourcing this file (". .\Deploy-SshKey.ps1") loads the functions without running a
    # deployment, so Pester can exercise the real implementations instead of copies of them.
    # Dot-sourcing this file (". .\Deploy-SshKey.ps1") loads the functions without running
    # a deployment, so Pester exercises the real implementations rather than copies of
    # them. Every block repeats the check, because returning from one named block does
    # not stop the ones after it.
    if ($MyInvocation.InvocationName -eq '.') {
        return
    }

    # Hosts stream in through process; the deployment itself runs once, in end
    $collectedTarget = [System.Collections.Generic.List[string]]::new()
}


process {
    if ($MyInvocation.InvocationName -eq '.') {
        return
    }

    # Runs once per piped object, and exactly once - carrying whatever -ComputerName
    # held - when nothing is piped. Collecting here therefore covers both forms with
    # no special case, and preserves the order the caller supplied.
    foreach ($pipedTarget in $ComputerName) {
        if ($pipedTarget -and $pipedTarget.Trim()) {
            $collectedTarget.Add($pipedTarget.Trim())
        }
    }
}


end {
    if ($MyInvocation.InvocationName -eq '.') {
        return
    }

    # Declared out here so the finally below can always reach it, however the try exits
    $askPassHelper = $null

    try {
        if ($CreateSampleHostFile) {
            # Scaffolding only: write the template and stop, so the user can edit it before
            # anything touches a key or a remote host.
            $samplePath = $HostFile
            if (-not $samplePath) {
                $samplePath = Join-Path (Get-Location).Path 'hosts.example.txt'
            }

            $null = New-SampleHostFile -Path $samplePath -DefaultUser $User -Force:$Force
            return
        }

        # Naming a config to read but not one to write points both at it. Resolving a run
        # against one file and then recording the result in a different one is almost never
        # what was meant, and the mistake is invisible until someone wonders why "ssh <alias>"
        # does not work.
        $effectiveConfigPath = $SshConfigPath
        if ($SshConfigFile -and -not $PSBoundParameters.ContainsKey('SshConfigPath')) {
            $effectiveConfigPath = $SshConfigFile
        }

        $deployParams = @{
            # What process collected, not the raw parameter: after a pipeline run the
            # parameter holds only the object that arrived last.
            ComputerName             = $collectedTarget.ToArray()
            HostFile                 = $HostFile

            # A caller who piped hosts in is by definition not sitting at a prompt. Without
            # this, an empty pipeline - "Get-Content hosts.txt" against a file that turned
            # out to be empty - would stop and ask, which in CI means hanging a job or
            # failing with an error about the console rather than about the host list.
            AllowPrompt              = (-not $MyInvocation.ExpectingInput)
            User                     = $User
            Port                     = $Port
            KeyPath                  = $KeyPath
            KeyType                  = $KeyType
            Comment                  = $Comment
            CorrelationId            = $CorrelationId
            SshConfigPath            = $effectiveConfigPath
            SshConfigFile            = $SshConfigFile
            TraceRemoteCommand       = $TraceRemoteCommand
            TargetPlatform           = $TargetPlatform
            WindowsKeyLocation       = $WindowsKeyLocation
            RemoteAuthorizedKeysPath = $RemoteAuthorizedKeysPath
            SshOption                = $SshOption
            StrictHostKeyChecking    = $StrictHostKeyChecking
            PosixTransport           = $PosixTransport
            ConfigAlias              = $ConfigAlias
            Force                    = $Force
            RequireExistingKey       = $RequireExistingKey
            ForceInstall             = $ForceInstall
            UseAgentKeys             = $UseAgentKeys
            UseSftp                  = $UseSftp
            UpdateSshConfig          = $UpdateSshConfig
            ForceConfigUpdate        = $ForceConfigUpdate

            # Only the entry point can see which parameters the caller actually named,
            # which is what separates an explicit "-Port 22" from the default
            PortSpecified            = $PSBoundParameters.ContainsKey('Port')
            UserSpecified            = $PSBoundParameters.ContainsKey('User')

            # What ssh reads for itself, as opposed to -SshConfigPath, which is written to
            ClientConfigPath         = (Join-Path $env:USERPROFILE '.ssh\config')
        }

        if ($Credential) {
            # Creates the helper script only. No environment variable is set on this process -
            # the password is placed directly into each ssh or sftp child's environment block
            # at launch, so it is never inherited by any other child and cannot be read out of
            # this process at all.
            $askPassHelper = New-SshAskPassHelper -Credential $Credential
        }

        $deployParams['AskPass'] = $askPassHelper

        Invoke-DeploySshKey @deployParams
    }
    catch {
        $errorDetails = [ordered]@{
            CorrelationId = $CorrelationId
            Script        = $MyInvocation.MyCommand.Name
            ErrorMessage  = $_.Exception.Message
            Category      = $_.CategoryInfo.Category.ToString()
            StackTrace    = $_.ScriptStackTrace
            Timestamp     = (Get-Date).ToString('o')
        }
        Write-Debug ($errorDetails | ConvertTo-Json -Compress)

        $failure = "Deployment failed: $($_.Exception.Message) - CorrelationId: $CorrelationId"
        Write-Error $failure -ErrorAction Stop
    }
    finally {
        # Runs whether the deployment succeeded, threw, or was interrupted. Leaving the
        # password in this session's environment after the run is the one failure mode this
        # feature must not have, so the teardown lives here rather than on the success path.
        if ($askPassHelper) {
            Remove-SshAskPassHelper -Helper $askPassHelper
        }
    }
}
