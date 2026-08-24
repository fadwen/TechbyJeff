#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The correlation engine, driven entirely by the captured fixtures and by synthetic
    directory objects. No domain is contacted.

    What is being tested is not "does the function run" but "does it reach the right
    conclusion from the evidence", and specifically that it does not reach a comfortable
    conclusion from missing evidence. The engine's value is entirely in its findings being
    trustworthy; a risk report that is confidently wrong is worse than no report, because it
    gets acted on.

    The four properties that matter most, in order:

    1. KRB005 names the right clients. "This service only ever gets RC4" is a fact about the
       service. "These twelve named machines advertise no AES and will fail" is the thing an
       application owner can act on. The engine must attribute a legacy client to the
       services it actually used, and must not smear it across services it did not.

    2. KRB002 fires on available-key evidence, not on configuration. An account configured
       for AES that holds no AES key is the commonest cause of a hardening rollback, and it
       is invisible to any assessment that reads only msDS-SupportedEncryptionTypes.

    3. A principal with no usable evidence is reported as unassessed (KRB015), not as safe
       (KRB009). These two look identical to a careless engine and mean opposite things.

    4. Nothing about a healthy principal produces a finding. False positives are how a report
       gets ignored, which costs more than the findings it contained were worth.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    $script:FixtureRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'Fixtures'

    function Get-FixtureEvent {
        <#
            Decodes the named fixtures into event objects. Named rather than wholesale so
            each test assembles exactly the evidence its scenario describes - feeding the
            entire fixture set into every test would make it impossible to tell which
            fixture produced which finding.
        #>
        param([Parameter(Mandatory)][string[]]$Name)

        foreach ($item in $Name) {
            $path = Join-Path -Path $script:FixtureRoot -ChildPath $item
            $raw = Get-Content -Path $path -Raw

            InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw -SourceName 'fixture'
            }
        }
    }

    function New-TestPrincipal {

        <#
            Builds a directory principal in the shape Get-KrbPrincipalEtype returns, without
            a directory. Constructed through the module's own ConvertFrom-KrbEtype and
            ConvertFrom-KrbAccountControl so that the decoded sub-objects are the real ones -
            a hand-written stub would let a decoder regression pass unnoticed here.
        #>
        # A SuppressMessageAttribute binds to the function it sits INSIDE, ahead of the param
        # block. Placed above the function keyword it attaches to nothing and the finding
        # stands. This helper builds an in-memory object and changes no system state.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture builder; constructs an object, changes no state.')]
        param(
            [Parameter(Mandatory)][string]$SamAccountName,
            [object]$SupportedEncryptionTypes = $null,
            [int]$UserAccountControl = 512,
            [string[]]$ServicePrincipalNames = @(),
            [int]$PwdAgeDays = 30,
            [string]$ObjectClass = 'user'
        )

        $etypes = ConvertFrom-KrbEtype -SupportedEncryptionTypes $SupportedEncryptionTypes
        $control = InModuleScope KrbEtypeInsight -Parameters @{ Uac = $UserAccountControl } {
            ConvertFrom-KrbAccountControl -UserAccountControl $Uac
        }

        [PSCustomObject]@{
            PSTypeName        = 'KrbEtypeInsight.Principal'
            SamAccountName    = $SamAccountName
            DistinguishedName = "CN=$SamAccountName,CN=Users,DC=ad,DC=techbyjeff,DC=net"
            Sid               = 'S-1-5-21-1-1-1-1001'
            ObjectClass       = $ObjectClass
            DisplayName       = $SamAccountName
            Description       = ''
            Enabled           = -not $control.Disabled
            SupportedEncryptionTypesRaw = $SupportedEncryptionTypes
            EncryptionTypes   = $etypes
            AccountControl    = $control
            ServicePrincipalNames = $ServicePrincipalNames
            HasSpn            = ($ServicePrincipalNames.Count -gt 0)
            PasswordLastSet   = (Get-Date).AddDays(-$PwdAgeDays)
            PasswordAgeDays   = $PwdAgeDays
            WhenCreated       = (Get-Date).AddDays(-400)
            LastLogonTimestamp = (Get-Date).AddDays(-1)
            IsKrbtgt          = ($SamAccountName -eq 'krbtgt')
            CorrelationId     = [guid]::NewGuid()
        }
    }
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbEtypeRisk' -Tag 'Unit', 'Public', 'Correlation' {

    Context 'Naming the clients a change will break' {

        BeforeAll {
            # svc-payroll is used by two clients: one that advertises AES and one that does
            # not. This is the scenario the module exists for.
            $script:PayrollEvents = @(Get-FixtureEvent @(
                '4769-v2-healthy-aes.xml'              # WKS-FINANCE-04$ -> svc-payroll, AES
                '4768-v2-legacy-client.xml'            # APPLIANCE-SCAN01$ TGT, advertises no AES
                '4769-v2-legacy-client-to-service.xml' # APPLIANCE-SCAN01$ -> svc-payroll, RC4
            ))

            $script:PayrollRisk = @($script:PayrollEvents | Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'
        }

        It 'identifies both clients of the service' {
            $script:PayrollRisk.ClientCount | Should-Be 2
            @($script:PayrollRisk.Clients) | Should-ContainCollection @('WKS-FINANCE-04$')
            @($script:PayrollRisk.Clients) | Should-ContainCollection @('APPLIANCE-SCAN01$')
        }

        It 'names only the client that cannot do AES' {
            # The precision that makes the finding usable. Naming both would be as useless as
            # naming neither - the owner cannot tell which machine to fix.
            @($script:PayrollRisk.ClientsWithoutAesSupport) | Should-BeCollection @('APPLIANCE-SCAN01$')
        }

        It 'raises KRB005 against the service, where the owner will see it' {
            @($script:PayrollRisk.FindingCodes) | Should-ContainCollection @('KRB005')

            $finding = $script:PayrollRisk.Findings | Where-Object Code -eq 'KRB005'
            $finding.Severity | Should-Be 'Critical'
            @($finding.Evidence.Clients) | Should-BeCollection @('APPLIANCE-SCAN01$')
        }

        It 'marks the service as one that will break' {
            $script:PayrollRisk.WillBreakOnHardening | Should-BeTrue
        }

        It 'reports the mixed encryption types it observed' {
            @($script:PayrollRisk.ObservedTicketEtypeNames) |
                Should-ContainCollection @('AES256-CTS-HMAC-SHA1-96')
            @($script:PayrollRisk.ObservedTicketEtypeNames) |
                Should-ContainCollection @('RC4-HMAC')
        }

        It 'does not attribute the legacy client to a service it never used' {
            # A client's incapability is a property of the client. Smearing it across every
            # service in the collection would make the report unactionable at scale.
            $desRisk = @($script:PayrollEvents + (Get-FixtureEvent '4769-v2-des-ticket.xml') |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-desonly'

            @($desRisk.ClientsWithoutAesSupport) | Should-NotContainCollection @('APPLIANCE-SCAN01$')
        }
    }

    Context 'Available key material as evidence' {

        BeforeAll {
            $script:NoKeyRisk = @(Get-FixtureEvent '4769-v2-service-no-aes-key.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -like 'MSSQLSvc*'
        }

        It 'raises KRB002 when the KDC reports no AES key' {
            # The account's own supported types include AES. Only the available-key field
            # reveals that no AES key was ever derived, and it is the difference between a
            # successful hardening and an outage.
            @($script:NoKeyRisk.FindingCodes) | Should-ContainCollection @('KRB002')

            $finding = $script:NoKeyRisk.Findings | Where-Object Code -eq 'KRB002'
            $finding.Severity | Should-Be 'Critical'
            $finding.Detail | Should-MatchString 'KDC_ERR_NULL_KEY'
        }

        It 'recommends a password reset rather than an attribute change' {
            # Changing the attribute alone on an account with no AES key does not harden it,
            # it breaks it. The recommendation has to say so or it will be followed literally.
            $finding = $script:NoKeyRisk.Findings | Where-Object Code -eq 'KRB002'
            $finding.RecommendedAction | Should-MatchString 'password'
        }

        It 'carries the observed keys as evidence' {
            $finding = $script:NoKeyRisk.Findings | Where-Object Code -eq 'KRB002'
            @($finding.Evidence.AvailableKeys) | Should-BeCollection @('RC4')
        }

        It 'does not raise KRB002 for a service that does hold AES keys' {
            $healthy = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($healthy.FindingCodes) | Should-NotContainCollection @('KRB002')
        }
    }

    Context 'Failures that have already happened' {

        It 'raises KRB011 for KDC_ERR_ETYPE_NOTSUPP' {
            $risk = @(Get-FixtureEvent '4771-etype-notsupp.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'APPLIANCE-SCAN01$'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB011')
            ($risk.Findings | Where-Object Code -eq 'KRB011').Severity | Should-Be 'Critical'
        }

        It 'raises KRB011 for KDC_ERR_NULL_KEY' {
            $risk = @(Get-FixtureEvent '4771-null-key.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-batchjob'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB011')
        }

        It 'does not raise KRB011 for an ordinary bad password' {
            # Every domain produces a steady background of these. Counting them as
            # encryption-type breakage would bury the signal entirely.
            $risk = @(Get-FixtureEvent '4768-v2-failed-0xffffffff.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-expired'

            @($risk.FindingCodes) | Should-NotContainCollection @('KRB011')
        }
    }

    Context 'DES detection' {

        It 'raises KRB007 when a DES ticket was issued' {
            $risk = @(Get-FixtureEvent '4769-v2-des-ticket.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-desonly'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB007')
            ($risk.Findings | Where-Object Code -eq 'KRB007').Severity | Should-Be 'Critical'
        }
    }

    Context 'Absence of evidence is not evidence of safety' {

        It 'reports a legacy-schema principal as unassessed, not as healthy' {
            # The distinction this context exists for. A version 0 event records none of the
            # fields that would reveal a problem, so "nothing found" means "nothing could
            # have been found". Reporting KRB009 here would give false assurance about
            # exactly the principals the module understood least.
            # The version 1 TGT request. Its client role carries no pre-authentication etype
            # and no session key etype - version 1 has neither field - so the engine finds
            # nothing, and must say that it found nothing rather than that there is nothing.
            $risk = @(Get-FixtureEvent '4768-v1-legacy-schema.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'WKS-LEGACY-11$'

            $risk | Should-NotBeNull
            @($risk.FindingCodes) | Should-ContainCollection @('KRB015')
            @($risk.FindingCodes) | Should-NotContainCollection @('KRB009')
            $risk.RiskLevel | Should-Be 'Low'
        }

        It 'reports a fully evidenced healthy principal as healthy' {
            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-BeCollection @('KRB009')
            $risk.RiskLevel | Should-Be 'Info'
            $risk.WillBreakOnHardening | Should-BeFalse
        }

        It 'records why confidence is reduced on a legacy-schema principal' {
            $risk = @(Get-FixtureEvent '4769-v0-legacy-schema.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-fileshare'

            @($risk.ConfidenceNotes).Count | Should-BeGreaterThan 0
            ($risk.ConfidenceNotes -join ' ') | Should-MatchString 'KB5021131'
            $risk.EventSchemaVersion2 | Should-BeFalse
        }

        It 'omits healthy principals unless asked for them' {
            # The default output is a work list, not an inventory. A report that opens with
            # four thousand rows saying "nothing wrong" does not get read.
            $withHealthy = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)
            $workListOnly = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline)

            @($withHealthy).Count | Should-BeGreaterThan @($workListOnly).Count
        }
    }

    Context 'Modelling a specific target configuration' {

        It 'reports no critical impact when RC4 is retained' {
            # Target 0x1C keeps RC4 alongside AES - the intermediate step of a staged
            # rollout. If this produces Critical findings, the step is not as safe as it is
            # usually assumed to be, which is worth knowing before it is scheduled.
            $risk = @(Get-FixtureEvent '4769-v2-legacy-client-to-service.xml' |
                Get-KrbEtypeRisk -Offline -TargetEncryptionTypes 0x1C -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-NotContainCollection @('KRB001')
        }

        It 'reports the same service as breaking when RC4 is removed' {
            $risk = @(Get-FixtureEvent '4769-v2-legacy-client-to-service.xml' |
                Get-KrbEtypeRisk -Offline -TargetEncryptionTypes 0x18 -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB001')
        }

        It 'refuses a target that enables no cipher at all' {
            # Every principal would be reported as broken. True, and useless.
            {
                Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                    Get-KrbEtypeRisk -Offline -TargetEncryptionTypes 0
            } | Should-Throw
        }

        It 'carries the target configuration on every risk object' {
            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)[0]

            $risk.TargetEncryptionTypes.EffectiveHex | Should-Be '0x18'
        }
    }

    Context 'Directory correlation' {

        It 'raises KRB004 when USE_DES_KEY_ONLY overrides the encryption type attribute' {
            # 0x200000 plus a normal account. The bit supersedes msDS-SupportedEncryptionTypes
            # entirely, so an attribute-only assessment reports this account as healthy.
            $principals = @(New-TestPrincipal -SamAccountName 'svc-payroll' `
                -SupportedEncryptionTypes 0x1C -UserAccountControl (512 -bor 0x200000))

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB004')
        }

        It 'raises KRB003 when AES is explicitly excluded' {
            $principals = @(New-TestPrincipal -SamAccountName 'svc-payroll' -SupportedEncryptionTypes 4)

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB003')
        }

        It 'does not raise KRB003 for an account merely inheriting the domain default' {
            # Most accounts in any domain have an unset attribute. Treating that as a
            # deliberate exclusion would put the entire directory in the report.
            $principals = @(New-TestPrincipal -SamAccountName 'svc-payroll' -SupportedEncryptionTypes $null)

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-NotContainCollection @('KRB003')
        }

        It 'raises KRB013 for a delegation-enabled principal' {
            $principals = @(New-TestPrincipal -SamAccountName 'svc-payroll' `
                -SupportedEncryptionTypes 0x1C -UserAccountControl (512 -bor 0x80000))

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB013')
        }

        It 'resolves a service principal name to its owning account' {
            # The 4769 names a full SPN; the finding must be attributed to the account, or
            # the report lists the same account several times under different SPNs.
            $principals = @(New-TestPrincipal -SamAccountName 'svc-legacydb' `
                -SupportedEncryptionTypes 0x1C `
                -ServicePrincipalNames @('MSSQLSvc/legacydb01.ad.techbyjeff.net:1433'))

            $risk = @(Get-FixtureEvent '4769-v2-service-no-aes-key.xml' |
                Get-KrbEtypeRisk -Principal $principals -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-legacydb'

            $risk | Should-NotBeNull
            $risk.ResolvedInDirectory | Should-BeTrue
            $risk.DistinguishedName | Should-MatchString 'svc-legacydb'
        }

        It 'flags a quiet DES-only account that produced no events at all' {
            # An observational engine is blind to an account used by a quarterly batch job.
            # Being blind in this direction is dangerous: the account still blocks hardening.
            $principals = @(
                New-TestPrincipal -SamAccountName 'svc-quarterly' -SupportedEncryptionTypes 3
                New-TestPrincipal -SamAccountName 'svc-payroll' -SupportedEncryptionTypes 0x1C
            )

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals) |
                Where-Object PrincipalName -eq 'svc-quarterly'

            $risk | Should-NotBeNull
            $risk.RequestCount | Should-Be 0
            @($risk.Roles) | Should-BeCollection @('Unobserved')
            @($risk.FindingCodes) | Should-ContainCollection @('KRB007')
        }

        It 'does not report a quiet but healthy account' {
            $principals = @(
                New-TestPrincipal -SamAccountName 'svc-quiet-healthy' -SupportedEncryptionTypes 0x18
                New-TestPrincipal -SamAccountName 'svc-payroll' -SupportedEncryptionTypes 0x1C
            )

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals) |
                Where-Object PrincipalName -eq 'svc-quiet-healthy'

            $risk | Should-BeNull
        }

        It 'does not report a quiet DES-only account that is disabled' {
            # A disabled account cannot authenticate and cannot break. Counting it inflates
            # the report without adding an action.
            $principals = @(
                New-TestPrincipal -SamAccountName 'svc-disabled' -SupportedEncryptionTypes 3 `
                    -UserAccountControl (512 -bor 0x2)
                New-TestPrincipal -SamAccountName 'svc-payroll' -SupportedEncryptionTypes 0x1C
            )

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Principal $principals) |
                Where-Object PrincipalName -eq 'svc-disabled'

            $risk | Should-BeNull
        }
    }

    Context 'Scoring and ordering' {

        It 'scores a service that will break above one that merely has a weakness' {
            $risks = @(Get-FixtureEvent @(
                '4769-v2-healthy-aes.xml'
                '4769-v2-service-no-aes-key.xml'
            ) | Get-KrbEtypeRisk -Offline -IncludeHealthy)

            $broken = $risks | Where-Object PrincipalName -like 'MSSQLSvc*'
            $healthy = $risks | Where-Object PrincipalName -eq 'svc-payroll'

            $broken.RiskScore | Should-BeGreaterThan $healthy.RiskScore
            $broken.RiskLevel | Should-Be 'Critical'
        }

        It 'never exceeds a score of 100' {
            $risks = @(Get-FixtureEvent @(
                '4769-v2-des-ticket.xml'
                '4771-etype-notsupp.xml'
                '4768-v2-legacy-client.xml'
                '4769-v2-legacy-client-to-service.xml'
            ) | Get-KrbEtypeRisk -Offline -IncludeHealthy)

            foreach ($risk in $risks) {
                $risk.RiskScore | Should-BeLessThanOrEqual 100
            }
        }
    }

    Context 'Input handling' {

        It 'warns rather than returning silently when given no events' {
            # An empty result must not read as a clean domain. It means nothing was measured,
            # and the two are indistinguishable in the output unless the function says so.
            #
            # Piping an empty collection is the only way to reach this path: the parameter is
            # mandatory, so passing @() directly fails binding instead. An empty pipeline
            # skips the process block entirely and lands in end with an empty buffer, which
            # is exactly the real-world case of a collection that matched nothing.
            $captured = @(@() | Get-KrbEtypeRisk -Offline 3>&1)

            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
            "$($warnings[0])" | Should-MatchString 'nothing was measured'
        }

        It 'accepts events through the -Event alias' {
            # The parameter cannot be named Event - $Event is an automatic variable - but the
            # alias is what reads naturally at the console and is what the examples use.
            $events = @(Get-FixtureEvent '4769-v2-healthy-aes.xml')
            $risk = @(Get-KrbEtypeRisk -Event $events -Offline -IncludeHealthy)

            @($risk).Count | Should-BeGreaterThan 0
        }

        It 'emits the declared PSTypeName' {
            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)[0]

            $risk.PSTypeNames[0] | Should-Be 'KrbEtypeInsight.Risk'
        }
    }
}
