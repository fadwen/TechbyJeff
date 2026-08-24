#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The domain baseline, with every directory and registry call mocked.

    This function had no unit tests in the first two versions of the module and sat at 63%
    coverage on the strength of a single live run against a one-controller lab. That is the
    worst place in the module for a gap: the baseline it produces is what every per-account
    finding is judged against, so an error here is not one wrong row, it is every row about an
    account whose encryption type attribute is unset - which in a real domain is most of them.

    The paths a single-controller lab structurally cannot reach are the ones worth having:

    - Controllers disagreeing about DefaultDomainSupportedEncTypes. It is a per-controller
      registry value, not a replicated attribute, so disagreement is possible and produces
      authentication that varies by which controller a client reaches. Needs two controllers
      with different values, which a one-DC domain cannot supply.
    - The remote branch. Reading the local machine happens in-process; every other controller
      goes through Invoke-Command, and that code had never run.
    - A controller that cannot be reached at all.
    - Trusts. A lab with no trusts never evaluates IsCrossRealmRc4Risk.
    - A domain functional level below Windows Server 2008, where no account in the domain has
      an AES key and the whole assessment is moot.
#>

# Script-level suppressions. A SuppressMessageAttribute on a param() block at the top of a
# script applies to the whole file.
#
# ReviewUnusedParameter: Set-DirectoryMock reads its parameters inside GetNewClosure() script
# blocks, which the analyzer does not follow into. Removing them would silently stop the mocks
# varying and every test in the file would assert against one fixed domain.
#
# ComputerNameHardcoded: the names are mock domain controllers that exist only in this file.
#
# ConvertToSecureStringWithPlainText: a throwaway literal for a credential that is never
# authenticated with - the test asserts only that the parameter is forwarded.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Read inside GetNewClosure script blocks the analyzer does not follow.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingComputerNameHardcoded', '',
    Justification = 'Mock domain controller names that exist only within this test file.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Throwaway literal for a credential that is never authenticated with.')]
param()

BeforeAll {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

    # Every directory call below is mocked, but Pester cannot attach a mock to a command
    # that does not exist. On a host without RSAT the stub supplies the names; on a domain
    # controller the real cmdlets win, because the stub path is appended, not prepended.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-KrbTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    # Named so they never match the local machine, which forces the remote Invoke-Command
    # branch - the half of the registry collection a single-controller run never exercises.
    function New-MockDc {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture builder; constructs an object, changes no state.')]
        param(
            [string]$Name = 'MOCKDC01',
            [string]$Site = 'Default-First-Site-Name',
            [string]$OperatingSystem = 'Windows Server 2022 Standard',
            [string]$OperatingSystemVersion = '10.0 (20348)',
            [bool]$IsReadOnly = $false
        )

        [PSCustomObject]@{
            Name       = $Name
            HostName   = "$Name.ad.techbyjeff.net"
            Site       = $Site
            OperatingSystem = $OperatingSystem
            OperatingSystemVersion = $OperatingSystemVersion
            IsReadOnly = $IsReadOnly
        }
    }

    function Set-DirectoryMock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Configures Pester mocks; changes no system state.')]
        param(
            [string]$DomainMode = 'Windows2016Domain',
            [object]$KrbtgtEtypes = 0,
            [int]$KrbtgtPasswordAgeDays = 380,
            [object[]]$Trust = @()
        )

        $trustList = $Trust

        Mock -ModuleName KrbEtypeInsight Get-ADDomain {
            [PSCustomObject]@{
                DNSRoot     = 'ad.techbyjeff.net'
                NetBIOSName = 'TECHBYJEFF'
                DomainSID   = [PSCustomObject]@{ Value = 'S-1-5-21-1-1-1' }
                DomainMode  = $DomainMode
            }
        }.GetNewClosure()

        Mock -ModuleName KrbEtypeInsight Get-ADForest {
            [PSCustomObject]@{ Name = 'ad.techbyjeff.net'; ForestMode = 'Windows2016Forest' }
        }

        Mock -ModuleName KrbEtypeInsight Get-ADUser {
            [PSCustomObject]@{
                Name = 'krbtgt'
                'msDS-SupportedEncryptionTypes' = $KrbtgtEtypes
                pwdLastSet = (Get-Date).AddDays(-$KrbtgtPasswordAgeDays)
                userAccountControl = 514
            }
        }.GetNewClosure()

        Mock -ModuleName KrbEtypeInsight Get-ADTrust { $trustList }.GetNewClosure()
    }
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbDomainEtypeContext' -Tag 'Unit', 'Public', 'Domain' {

    Context 'Baseline shape' {

        BeforeAll {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }
        }

        It 'returns a domain context object' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context | Should-NotBeNull
            $context.PSTypeNames[0] | Should-Be 'KrbEtypeInsight.DomainContext'
            $context.DomainName | Should-Be 'ad.techbyjeff.net'
        }

        It 'decodes the krbtgt encryption types' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.KrbtgtEncryptionTypes | Should-NotBeNull
            $context.KrbtgtPasswordAgeDays | Should-Be 380
        }

        It 'falls back to the documented Windows default when no controller has the value set' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.DomainDefaultEncryptionTypes | Should-Be 0x27
            $context.DomainDefaultSource | Should-Be 'WindowsDefault'
        }

        It 'records the controller build so a missing audit field can be explained' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue
            $dc = @($context.DomainControllers)[0]

            $dc.OperatingSystemBuild | Should-Be 20348
            $dc.SupportsSha2Etypes | Should-BeFalse
        }

        It 'marks a Windows Server 2025 controller as capable of SHA-2 encryption types' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                New-MockDc -OperatingSystem 'Windows Server 2025 Datacenter' `
                    -OperatingSystemVersion '10.0 (26100)'
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue
            @($context.DomainControllers)[0].SupportsSha2Etypes | Should-BeTrue
        }
    }

    Context 'Functional level' {

        It 'reports AES key derivation as supported at a modern functional level' {
            Set-DirectoryMock -DomainMode 'Windows2016Domain'
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            (Get-KrbDomainEtypeContext -WarningAction SilentlyContinue).SupportsAesKeyDerivation |
                Should-BeTrue
        }

        It 'reports AES key derivation as unsupported below Windows Server 2008' {
            # A whole-domain blocker that outranks every per-account finding: below this level
            # the KDC never derived an AES key for anything, so an AES-only change breaks
            # every account at once.
            Set-DirectoryMock -DomainMode 'Windows2003Domain'
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            (Get-KrbDomainEtypeContext -WarningAction SilentlyContinue).SupportsAesKeyDerivation |
                Should-BeFalse
        }
    }

    Context 'Per-controller registry collection' {

        It 'reads the configured value and reports the source as the registry' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = 0x18 }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.DomainDefaultEncryptionTypes | Should-Be 0x1C
            $context.DomainDefaultSource | Should-Be 'Registry'
            @($context.DomainControllers)[0].PolicySupportedEncryptionTypes | Should-Be 0x18
        }

        It 'decodes both registry values it read' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = 0x18 }
            }

            $dc = @((Get-KrbDomainEtypeContext -WarningAction SilentlyContinue).DomainControllers)[0]

            $dc.DefaultDomainSupportedEncTypesDecoded.SupportsRc4 | Should-BeTrue
            $dc.PolicySupportedEncryptionTypesDecoded.SupportsRc4 | Should-BeFalse
        }

        It 'skips the registry entirely when asked, and says the baseline was assumed' {
            # The escape hatch for estates without remoting. It must be visible in the output
            # that the baseline was assumed rather than measured, because every conclusion
            # about an unset attribute inherits that assumption.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command { throw 'must not be called' }

            $context = Get-KrbDomainEtypeContext -SkipRegistry -WarningAction SilentlyContinue

            Should-NotInvoke Invoke-Command -ModuleName KrbEtypeInsight
            $context.DomainDefaultSource | Should-Be 'WindowsDefault'
            $context.DomainDefaultEncryptionTypes | Should-Be 0x27
            @($context.DomainControllers)[0].RegistryReachable | Should-BeFalse
        }

        It 'degrades rather than failing when a controller cannot be reached' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command { throw 'WinRM cannot complete the operation' }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context | Should-NotBeNull
            $dc = @($context.DomainControllers)[0]
            $dc.RegistryReachable | Should-BeFalse
            $dc.RegistryError | Should-MatchString 'WinRM'
        }

        It 'warns when a controller cannot be reached' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command { throw 'WinRM cannot complete the operation' }

            $captured = @(Get-KrbDomainEtypeContext 3>&1)
            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
        }

        It 'restricts collection to the named controllers' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -ComputerName 'MOCKDC02' -WarningAction SilentlyContinue

            @($context.DomainControllers) | Should-BeCollection -Count 1
            @($context.DomainControllers)[0].Name | Should-Be 'MOCKDC02'
        }

        It 'errors when no named controller matches' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc -Name 'MOCKDC01' }

            {
                Get-KrbDomainEtypeContext -ComputerName 'NOT-A-DC' -ErrorAction Stop
            } | Should-Throw
        }
    }

    Context 'Reading the local controller in-process' {

        # Every test above names its controllers so they never match this machine, which
        # forces the remote branch and mocks Invoke-Command. That leaves the registry reads
        # themselves - the two Get-ItemProperty calls inside the policy scriptblock - never
        # executed by the suite at all, because a mocked Invoke-Command never runs the
        # scriptblock it is handed. Coverage showed them as the only uncovered lines in the
        # function's happy path.
        #
        # This matters more than a coverage number. These two reads are what separates a
        # MEASURED domain baseline from an ASSUMED one, and every finding about an account
        # whose msDS-SupportedEncryptionTypes is unset - most of a real domain - inherits
        # whichever it was. Naming the controller after the local machine takes the in-process
        # branch, which exists so that running on a controller does not require WinRM to
        # localhost.

        It 'reads both registry values without remoting when the controller is this machine' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc -Name $env:COMPUTERNAME }
            Mock -ModuleName KrbEtypeInsight Invoke-Command { throw 'the local branch must not remote' }
            Mock -ModuleName KrbEtypeInsight Get-ItemProperty {
                if ($Name -eq 'DefaultDomainSupportedEncTypes') {
                    return [PSCustomObject]@{ DefaultDomainSupportedEncTypes = 0x1C }
                }
                return [PSCustomObject]@{ SupportedEncryptionTypes = 0x18 }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue
            $dc = @($context.DomainControllers)[0]

            $dc.RegistryReachable | Should-BeTrue
            $dc.DefaultDomainSupportedEncTypes | Should-Be 0x1C
            $dc.PolicySupportedEncryptionTypes | Should-Be 0x18
            $context.DomainDefaultSource | Should-Be 'Registry'

            Should-Invoke Get-ItemProperty -ModuleName KrbEtypeInsight -Times 2 -Exactly
            Should-NotInvoke Invoke-Command -ModuleName KrbEtypeInsight
        }

        It 'reads the KDC value from the service key rather than a Parameters subkey' {
            # KB5021131 places DefaultDomainSupportedEncTypes directly under the Kdc service
            # key. Reading a Parameters subkey instead returns null, which is
            # indistinguishable from "not configured" - and "not configured" is the answer
            # that silently substitutes the assumed 0x27 default.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc -Name $env:COMPUTERNAME }
            Mock -ModuleName KrbEtypeInsight Get-ItemProperty {
                [PSCustomObject]@{ DefaultDomainSupportedEncTypes = 0x1C; SupportedEncryptionTypes = 0x18 }
            }

            Get-KrbDomainEtypeContext -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-ItemProperty -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter {
                    $Path -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc' -and
                    $Name -eq 'DefaultDomainSupportedEncTypes'
                }
        }

        It 'treats an absent registry value as not configured rather than as zero' {
            # A missing value and a value of 0 both mean "fall through to the domain
            # default", but only one of them should report the baseline as measured. If an
            # absent read were recorded as 0 the report would claim it had read a controller
            # that had never been configured.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc -Name $env:COMPUTERNAME }
            Mock -ModuleName KrbEtypeInsight Get-ItemProperty { $null }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue
            $dc = @($context.DomainControllers)[0]

            $null -eq $dc.DefaultDomainSupportedEncTypes | Should-BeTrue
            $null -eq $dc.PolicySupportedEncryptionTypes | Should-BeTrue
            $context.DomainDefaultSource | Should-Be 'WindowsDefault'

            # The read succeeded; it simply found nothing. That is a different fact from a
            # controller that could not be reached, and the two must not collapse.
            $dc.RegistryReachable | Should-BeTrue
        }
    }

    Context 'Controllers that disagree' {

        BeforeAll {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(
                    New-MockDc -Name 'MOCKDC01' -Site 'HQ'
                    New-MockDc -Name 'MOCKDC02' -Site 'HQ'
                    New-MockDc -Name 'MOCKDC03' -Site 'Branch'
                )
            }

            # Two controllers on 0x1C, one drifted to 0x04. A domain in this state
            # authenticates differently depending on which controller a client reaches, which
            # produces intermittent failures nobody can reproduce.
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                $value = if ($ComputerName -like 'MOCKDC03*') { 0x04 } else { 0x1C }
                @{ DefaultDomainSupportedEncTypes = $value; PolicySupportedEncryptionTypes = $null }
            }
        }

        It 'resolves the domain default by majority, not by whichever answered first' {
            # Taking the first controller's value would make the entire assessment depend on
            # enumeration order.
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.DomainDefaultEncryptionTypes | Should-Be 0x1C
        }

        It 'reports the disagreement' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.ControllersDisagreeOnDefault | Should-BeTrue
        }

        It 'identifies which controller is the outlier' {
            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $outliers = @($context.DomainControllers | Where-Object { -not $_.AgreesWithDomainDefault })

            $outliers | Should-BeCollection -Count 1
            $outliers[0].Name | Should-Be 'MOCKDC03'
            $outliers[0].Site | Should-Be 'Branch'
        }

        It 'warns about the disagreement' {
            $captured = @(Get-KrbDomainEtypeContext 3>&1)
            $text = ($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            }) -join ' '

            $text | Should-MatchString 'do not agree'
        }

        It 'detects disagreement when one controller is set and the other is unset' {
            # The shape a real two-controller lab actually produced, and the shape this file
            # originally failed to test: every mocked controller carried an explicit value, so
            # the set-versus-unset case - by far the commonest in the field, since the value
            # is not written by default - was never exercised.
            #
            # An unset controller is not abstaining. Its KDC falls back to 0x27, which is a
            # position. Counting only explicitly-configured controllers left a single vote,
            # so the group count was 1 and disagreement read as FALSE while the controllers
            # genuinely disagreed.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                $value = if ($ComputerName -like 'MOCKDC02*') { 0x1C } else { $null }
                @{ DefaultDomainSupportedEncTypes = $value; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.ControllersDisagreeOnDefault | Should-BeTrue
        }

        It 'names the controller holding the divergent value as the outlier' {
            # The second half of the same defect. With the domain default resolved from the
            # only counted vote, the UNSET controller failed the agreement test and was named
            # as the outlier, while the controller actually holding the divergent value was
            # reported as agreeing - precisely backwards.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02'; New-MockDc -Name 'MOCKDC03')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                # Two unset, one divergent. The majority position is the Windows default.
                $value = if ($ComputerName -like 'MOCKDC03*') { 0x1C } else { $null }
                @{ DefaultDomainSupportedEncTypes = $value; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.DomainDefaultEncryptionTypes | Should-Be 0x27
            $outliers = @($context.DomainControllers | Where-Object { $_.AgreesWithDomainDefault -eq $false })

            $outliers | Should-BeCollection -Count 1
            $outliers[0].Name | Should-Be 'MOCKDC03'
        }

        It 'resolves a two-controller tie toward the Windows default' {
            # The real pair: one unset, one on 0x1C. That is 1-1 with no majority, and taking
            # whichever group sorted first named the UNSET controller as the outlier - it
            # failed an agreement test against a default derived solely from the other
            # controller's explicit value. Measured on the live two-DC domain, where the
            # three-controller test above did not reach because 2 beats 1 there.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                $value = if ($ComputerName -like 'MOCKDC02*') { 0x1C } else { $null }
                @{ DefaultDomainSupportedEncTypes = $value; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.ControllersDisagreeOnDefault | Should-BeTrue
            $context.DomainDefaultEncryptionTypes | Should-Be 0x27

            $outliers = @($context.DomainControllers | Where-Object { $_.AgreesWithDomainDefault -eq $false })
            $outliers | Should-BeCollection -Count 1
            $outliers[0].Name | Should-Be 'MOCKDC02'
        }

        It 'resolves a tie deterministically when neither value is the Windows default' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                $value = if ($ComputerName -like 'MOCKDC02*') { 0x1C } else { 0x18 }
                @{ DefaultDomainSupportedEncTypes = $value; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.ControllersDisagreeOnDefault | Should-BeTrue
            # Lowest wins - arbitrary but stable, so the same domain always reports the same way.
            $context.DomainDefaultEncryptionTypes | Should-Be 0x18
        }

        It 'scores an unreachable controller as unknown rather than agreeing' {
            # A controller whose registry could not be read has no known position. Scoring it
            # $true let a firewalled or RPC-blocked controller read as consensus - agreement
            # assembled partly from controllers nobody managed to ask.
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                if ($ComputerName -like 'MOCKDC02*') { throw 'Access is denied' }
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue
            $unreachable = $context.DomainControllers | Where-Object Name -eq 'MOCKDC02'

            $unreachable.RegistryReachable | Should-BeFalse
            $unreachable.AgreesWithDomainDefault | Should-BeNull
            $unreachable.RegistryError | Should-MatchString 'Access is denied'
        }

        It 'does not let an unreachable controller vote on the domain default' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(New-MockDc -Name 'MOCKDC01'; New-MockDc -Name 'MOCKDC02')
            }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                if ($ComputerName -like 'MOCKDC02*') { throw 'The RPC server is unavailable' }
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            # One reachable controller on 0x1C, one unknown. No disagreement is provable.
            $context.DomainDefaultEncryptionTypes | Should-Be 0x1C
            $context.ControllersDisagreeOnDefault | Should-BeFalse
        }

        It 'does not report disagreement when every controller matches' {
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context.ControllersDisagreeOnDefault | Should-BeFalse
            @($context.DomainControllers | Where-Object { -not $_.AgreesWithDomainDefault }) |
                Should-BeCollection -Count 0
        }
    }

    Context 'Trusts' {

        It 'flags an external trust that permits no AES' {
            # The usual reason a domain that has "finished" removing RC4 keeps issuing it.
            Set-DirectoryMock -Trust @(
                [PSCustomObject]@{
                    Name = 'contoso.net'; Target = 'contoso.net'
                    Direction = 'Bidirectional'; TrustType = 'Forest'
                    IntraForest = $false; SelectiveAuthentication = $false
                    'msDS-SupportedEncryptionTypes' = 4
                }
            )
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            @($context.Trusts) | Should-BeCollection -Count 1
            @($context.TrustsWithRc4Only) | Should-BeCollection -Count 1
            @($context.TrustsWithRc4Only)[0].Name | Should-Be 'contoso.net'
        }

        It 'does not flag an external trust that permits AES' {
            Set-DirectoryMock -Trust @(
                [PSCustomObject]@{
                    Name = 'fabrikam.net'; Target = 'fabrikam.net'
                    Direction = 'Bidirectional'; TrustType = 'Forest'
                    IntraForest = $false; SelectiveAuthentication = $false
                    'msDS-SupportedEncryptionTypes' = 0x1C
                }
            )
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            @($context.TrustsWithRc4Only) | Should-BeCollection -Count 0
        }

        It 'does not flag an intra-forest trust' {
            # An intra-forest trust inherits the forest's behaviour and is rarely the problem.
            # Flagging it would put an unactionable item at High in every forest with a child
            # domain.
            Set-DirectoryMock -Trust @(
                [PSCustomObject]@{
                    Name = 'child.ad.techbyjeff.net'; Target = 'child.ad.techbyjeff.net'
                    Direction = 'Bidirectional'; TrustType = 'Uplevel'
                    IntraForest = $true; SelectiveAuthentication = $false
                    'msDS-SupportedEncryptionTypes' = 4
                }
            )
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = 0x1C; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            @($context.Trusts) | Should-BeCollection -Count 1
            @($context.TrustsWithRc4Only) | Should-BeCollection -Count 0
        }

        It 'continues when trust enumeration fails' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADTrust { throw 'access denied' }
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            $context = Get-KrbDomainEtypeContext -WarningAction SilentlyContinue

            $context | Should-NotBeNull
            @($context.TrustsWithRc4Only) | Should-BeCollection -Count 0
        }
    }

    Context 'Credentials and server targeting' {

        It 'passes an explicit server to the directory queries' {
            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            Get-KrbDomainEtypeContext -Server 'dc02.ad.techbyjeff.net' -WarningAction SilentlyContinue |
                Out-Null

            Should-Invoke Get-ADDomain -ModuleName KrbEtypeInsight `
                -ParameterFilter { $Server -eq 'dc02.ad.techbyjeff.net' }
        }

        It 'passes credentials to the directory queries and to the remote registry read' {
            # Never exercised before. An assessment run from a workstation in another forest
            # supplies -Credential for everything, and a parameter that is silently dropped
            # produces an access-denied that looks like a permissions problem on the target.
            $credential = [PSCredential]::new('TECHBYJEFF\svc-audit',
                (ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force))

            Set-DirectoryMock
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { New-MockDc }
            Mock -ModuleName KrbEtypeInsight Invoke-Command {
                @{ DefaultDomainSupportedEncTypes = $null; PolicySupportedEncryptionTypes = $null }
            }

            Get-KrbDomainEtypeContext -Credential $credential -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-ADDomain -ModuleName KrbEtypeInsight `
                -ParameterFilter { $null -ne $Credential }
            Should-Invoke Invoke-Command -ModuleName KrbEtypeInsight `
                -ParameterFilter { $null -ne $Credential }
        }
    }

    Context 'Error handling' {

        It 'fails with a clear error when the domain cannot be read' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomain { throw 'The server is not operational' }

            {
                Get-KrbDomainEtypeContext -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*domain encryption type context*'
        }
    }
}
