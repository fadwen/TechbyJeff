#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Regression cover for six defects found reviewing the first implementation, plus the four
    finding codes that had no test at all - which is why two of the six survived a suite of
    296 passing tests.

    The two serious ones shared a shape, and it is the shape worth guarding against here:
    the engine produced Critical findings out of absent or unfamiliar information. For a tool
    whose entire value is that its findings can be trusted, a false Critical is worse than a
    missed one - it gets acted on, it wastes an application team's afternoon, and it is the
    reason the next report goes unread.

    Every test in this file is written to fail against the original implementation.
#>

BeforeDiscovery {
    $script:UncoveredCodes = @('KRB006', 'KRB008', 'KRB012', 'KRB014')
}

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    # Every directory call below is mocked, but Pester cannot attach a mock to a command
    # that does not exist. On a host without RSAT the stub supplies the names; on a domain
    # controller the real cmdlets win, because the stub path is appended, not prepended.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-KrbTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    $script:FixtureRoot = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'Fixtures'

    function Get-FixtureEvent {
        param([Parameter(Mandatory)][string[]]$Name)

        foreach ($item in $Name) {
            $raw = Get-Content -Path (Join-Path $script:FixtureRoot $item) -Raw
            InModuleScope KrbEtypeInsight -Parameters @{ Raw = $raw } {
                ConvertFrom-KrbEventRecord -Xml $Raw -SourceName 'fixture'
            }
        }
    }

    function New-TestPrincipal {
        # The attribute binds to the enclosing function only when it sits inside it, ahead of
        # param(). Builds an in-memory object and changes no system state.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture builder; constructs an object, changes no state.')]
        param(
            [Parameter(Mandatory)][string]$SamAccountName,
            [object]$SupportedEncryptionTypes = $null,
            [int]$UserAccountControl = 512,
            [string[]]$Spn = @(),
            [int]$PwdAgeDays = 30
        )

        $control = InModuleScope KrbEtypeInsight -Parameters @{ Uac = $UserAccountControl } {
            ConvertFrom-KrbAccountControl -UserAccountControl $Uac
        }

        [PSCustomObject]@{
            PSTypeName        = 'KrbEtypeInsight.Principal'
            SamAccountName    = $SamAccountName
            DistinguishedName = "CN=$SamAccountName,CN=Users,DC=ad,DC=techbyjeff,DC=net"
            Sid               = 'S-1-5-21-1-1-1-1001'
            ObjectClass       = 'user'
            DisplayName       = $SamAccountName
            Enabled           = -not $control.Disabled
            SupportedEncryptionTypesRaw = $SupportedEncryptionTypes
            EncryptionTypes   = ConvertFrom-KrbEtype -SupportedEncryptionTypes $SupportedEncryptionTypes
            AccountControl    = $control
            ServicePrincipalNames = $Spn
            HasSpn            = ($Spn.Count -gt 0)
            PasswordLastSet   = (Get-Date).AddDays(-$PwdAgeDays)
            PasswordAgeDays   = $PwdAgeDays
            LastLogonTimestamp = (Get-Date).AddDays(-1)
            IsKrbtgt          = $false
        }
    }

    function New-TestDomainContext {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture builder; constructs an object, changes no state.')]
        param([int]$TrustEncryptionTypes = 4)

        $etypes = ConvertFrom-KrbEtype -SupportedEncryptionTypes $TrustEncryptionTypes

        [PSCustomObject]@{
            PSTypeName = 'KrbEtypeInsight.DomainContext'
            DomainName = 'ad.techbyjeff.net'
            DomainDefaultEncryptionTypes = 0x27
            # Named for the realm the referral fixture actually targets. Trusts and
            # TrustsWithRc4Only both carry it: the first is what referral detection confirms
            # against, the second is what raises KRB014.
            Trusts = @(
                [PSCustomObject]@{
                    PSTypeName = 'KrbEtypeInsight.TrustContext'
                    Name       = 'LAB.CONTOSO.TEST'
                    Target     = 'LAB.CONTOSO.TEST'
                    EncryptionTypes = $etypes
                    IsCrossRealmRc4Risk = $true
                }
            )
            TrustsWithRc4Only = @(
                [PSCustomObject]@{
                    PSTypeName = 'KrbEtypeInsight.TrustContext'
                    Name       = 'LAB.CONTOSO.TEST'
                    Target     = 'LAB.CONTOSO.TEST'
                    Direction  = 'Bidirectional'
                    TrustType  = 'Forest'
                    EncryptionTypes = $etypes
                    IsCrossRealmRc4Risk = $true
                }
            )
        }
    }
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbEtypeRisk regressions' -Tag 'Unit', 'Public', 'Regression' {

    Context 'Defect 1 - encryption stronger than the target must not be reported as removed' {

        # The default target 0x18 authorises etypes 17 and 18, the AES-SHA1 pair. It does not
        # name 19 and 20, the RFC 8009 AES-SHA2 types Windows Server 2025 issues. An
        # exact-membership comparison therefore classified the strongest cipher Windows
        # produces as "an encryption type the change removes" and raised findings against the
        # most modern machines in the estate - by default, on every run.

        It 'does not flag a client presenting AES-SHA2 against the default target' {
            $risk = @(Get-FixtureEvent '4768-v2-sha2-aes-client.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'WS2025-APP01$'

            $risk | Should-NotBeNull
            $risk.RiskLevel | Should-Be 'Info'
            $risk.WillBreakOnHardening | Should-BeFalse
            @($risk.FindingCodes) | Should-NotContainCollection @('KRB008')
            @($risk.FindingCodes) | Should-NotContainCollection @('KRB005')
        }

        It 'still flags RC4, which the target genuinely removes' {
            $risk = @(Get-FixtureEvent '4769-v2-service-no-aes-key.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -like 'MSSQLSvc*'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB001')
        }

        It 'still flags DES, which the target genuinely removes' {
            $risk = @(Get-FixtureEvent '4769-v2-des-ticket.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-desonly'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB001')
            @($risk.FindingCodes) | Should-ContainCollection @('KRB007')
        }

        It 'rejects a target that authorises a session key but no ticket encryption' {
            # 0x20 alone passes a naive cipher-bit check and then authorises nothing that can
            # encrypt a ticket, so every principal in the domain would come back broken.
            {
                Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                    Get-KrbEtypeRisk -Offline -TargetEncryptionTypes 0x20 -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*no ticket encryption type*'
        }
    }

    Context 'Lab finding - the RFC 8009 SHA-2 bits are not honoured by Windows' {

        # Measured on a Windows Server 2025 KDC, build 26100, in a two-controller lab. The
        # module previously mapped 0x40 and 0x80 to etypes 19 and 20 on the strength of
        # MS-KILE. The KDC does not agree, and the direction of the error was dangerous:
        # SupportsAes came back true for an account that could not obtain a ticket at all, so
        # the risk engine reported a dead account as safe.
        #
        # Each expectation below is one row of the lab's own results table.

        It 'reports an account carrying only SHA-2 bits as having no usable AES' {
            # Lab: msDS-SupportedEncryptionTypes 0x80 -> KDC_ERR_ETYPE_NOTSUPP, no ticket.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x80

            $result.SupportsAes | Should-BeFalse
            @($result.TicketEtypes) | Should-BeCollection -Count 0
            $result.CarriesUnhonouredSha2Bits | Should-BeTrue
        }

        It 'reports both SHA-2 bits together as still unusable' {
            # Lab: 0xC0 -> KDC_ERR_ETYPE_NOTSUPP.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0xC0

            $result.SupportsAes | Should-BeFalse
            @($result.TicketEtypes) | Should-BeCollection -Count 0
        }

        It 'reports SHA-2 alongside AES256-SHA1 as usable, via the SHA1 type only' {
            # Lab: 0x90 (0x80|0x10) -> ticket issued at 0x12, the 0x80 bit ignored. Etype 18
            # is 0x12, so the module must name exactly that and nothing else.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x90

            $result.SupportsAes | Should-BeTrue
            @($result.TicketEtypes) | Should-BeCollection @(18)
            $result.CarriesUnhonouredSha2Bits | Should-BeTrue
        }

        It 'still names the SHA-2 bits so a report does not hide them' {
            # Excluded from capability, not from view. An operator reading the assessment
            # needs to see that the bits are set even though the KDC ignores them.
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0xC0

            @($result.CipherNames) | Should-ContainCollection @('AES256-CTS-HMAC-SHA384-192')
            @($result.CipherNames) | Should-ContainCollection @('AES128-CTS-HMAC-SHA256-128')
        }

        It 'does not flag an ordinary AES-SHA1 account as carrying SHA-2 bits' {
            $result = ConvertFrom-KrbEtype -SupportedEncryptionTypes 0x18

            $result.SupportsAes | Should-BeTrue
            $result.CarriesUnhonouredSha2Bits | Should-BeFalse
        }

        It 'treats a SHA-2-only service as broken by an AES target' {
            # The consequence that matters. Such an account cannot get a ticket, so the risk
            # engine must not clear it.
            $principal = New-TestPrincipal -SamAccountName 'svc-sha2only' -SupportedEncryptionTypes 0x80

            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -IncludeHealthy -Principal @($principal)) |
                Where-Object PrincipalName -eq 'svc-sha2only'

            $risk | Should-NotBeNull
            $risk.ConfiguredEncryptionTypes.SupportsAes | Should-BeFalse
        }
    }

    Context 'Lab finding - a cross-realm referral names the bare realm' {

        # Measured on a real bidirectional forest trust, both directions:
        #
        #   logged on the LAB forest  ServiceName = AD.TECHBYJEFF.NET  status 0x0  etype 0x17
        #   logged on the TBJ forest  ServiceName = LAB.CONTOSO.TEST   status 0xC000019B
        #
        # The module originally looked for a 'krbtgt/REALM' prefix, which appears in neither.
        # The literal 'krbtgt' is what LOCAL TGT renewals carry - 116 of them in one capture -
        # so the old rule matched the wrong thing entirely and every referral was filed as an
        # ordinary unresolved service.

        It 'recognises a bare realm name as a probable referral' {
            $result = @(Get-FixtureEvent '4769-v2-crossrealm-referral.xml')[0]

            $result.ServiceName | Should-Be 'LAB.CONTOSO.TEST'
            $result.IsProbableRealmName | Should-BeTrue
        }

        It 'does not mistake a service, a machine or an SPN for a realm' -ForEach @(
            @{ Fixture = '4769-v2-healthy-aes.xml' }           # svc-payroll
            @{ Fixture = '4769-v2-service-no-aes-key.xml' }    # MSSQLSvc/... - has a slash
            @{ Fixture = '4769-v2-krbtgt-renewal.xml' }        # bare krbtgt
        ) {
            @(Get-FixtureEvent $Fixture)[0].IsProbableRealmName | Should-BeFalse
        }

        It 'does not create a service row for a referral when the trust is known' {
            # With a domain context the realm is confirmed against the real trust names, so
            # the referral is attributed to the trust rather than becoming a phantom principal
            # named after the remote realm.
            $risks = @(Get-FixtureEvent '4769-v2-crossrealm-referral.xml' |
                Get-KrbEtypeRisk -IncludeHealthy -Principal @() `
                    -DomainContext (New-TestDomainContext))

            $phantom = $risks | Where-Object {
                $_.PrincipalName -eq 'LAB.CONTOSO.TEST' -and @($_.Roles) -contains 'Service'
            }

            $phantom | Should-BeNull
        }

        It 'attaches the observed referral etype to the trust finding' {
            # This is what the correction buys. KRB014 stops being a statement about an
            # attribute and becomes an observation: RC4 is what the KDC actually issued for
            # cross-realm traffic over this trust.
            $risk = @(Get-FixtureEvent '4769-v2-crossrealm-referral.xml' |
                Get-KrbEtypeRisk -IncludeHealthy -Principal @() `
                    -DomainContext (New-TestDomainContext)) |
                Where-Object { $_.Roles -contains 'Trust' }

            $risk | Should-NotBeNull
            $finding = $risk.Findings | Where-Object Code -eq 'KRB014'

            $finding.Evidence.ObservedReferrals | Should-Be 1
            @($finding.Evidence.ObservedReferralEtypes) | Should-ContainCollection @('RC4-HMAC')
        }

        It 'falls back to the shape test when no trust list is available' {
            # Offline, against archived logs, there is no domain context to confirm against.
            # The referral must still be recognised rather than becoming a service row.
            $risks = @(Get-FixtureEvent '4769-v2-crossrealm-referral.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)

            $phantom = $risks | Where-Object {
                $_.PrincipalName -eq 'LAB.CONTOSO.TEST' -and @($_.Roles) -contains 'Service'
            }

            $phantom | Should-BeNull
        }
    }

    Context 'Lab finding - NTSTATUS values appear in the Status field' {

        It 'resolves STATUS_TRUSTED_DOMAIN_FAILURE' {
            # 0xC000019B, observed four times on a real cross-forest 4769. The catalog stopped
            # at 0x3C, so StatusName came back null and the suite's own live assertion caught
            # it. Kerberos result codes and NTSTATUS values share this field and do not
            # collide - the latter are large negatives as int32.
            InModuleScope KrbEtypeInsight {
                $entry = (Get-KrbProtocolCatalog).KdcStatus[-1073741413]

                $entry | Should-NotBeNull
                $entry.Name | Should-Be 'STATUS_TRUSTED_DOMAIN_FAILURE'
                $entry.IsEtypeRelated | Should-BeTrue
            }
        }

        It 'resolves the common NTSTATUS logon failures' -ForEach @(
            @{ Code = 0xC000006D; Name = 'STATUS_LOGON_FAILURE' }
            @{ Code = 0xC0000234; Name = 'STATUS_ACCOUNT_LOCKED_OUT' }
            @{ Code = 0xC0000133; Name = 'STATUS_TIME_DIFFERENCE_AT_DC' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Code = $Code; Name = $Name } {
                (Get-KrbProtocolCatalog).KdcStatus[$Code].Name | Should-Be $Name
            }
        }

        It 'still resolves the RFC 4120 codes it always did' {
            InModuleScope KrbEtypeInsight {
                (Get-KrbProtocolCatalog).KdcStatus[0x0E].Name | Should-Be 'KDC_ERR_ETYPE_NOTSUPP'
                (Get-KrbProtocolCatalog).KdcStatus[0x00].Name | Should-Be 'KDC_ERR_NONE'
            }
        }
    }

    Context 'Defect 2 - an unrecognised cipher is unknown, not legacy' {

        It 'does not call an advertisement legacy-only when no name was recognised' {
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @('AES512-CTS-HMAC-SHA3-256', 'SOME-FUTURE')

            $result.LegacyOnly | Should-BeFalse
            @($result.UnrecognizedNames) | Should-BeCollection -Count 2
        }

        It 'does not call an advertisement legacy-only when only some names were recognised' {
            # RC4 plus something unknown. The unknown one could be AES; nothing here
            # establishes that the client cannot do AES.
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @('RC4-HMAC-NT', 'SOME-FUTURE')

            $result.LegacyOnly | Should-BeFalse
        }

        It 'still calls a fully understood non-AES advertisement legacy-only' {
            $result = ConvertFrom-KrbEtype -AdvertizedEtype @('RC4-HMAC-NT', 'RC4-HMAC-OLD', 'RC4-MD4')

            $result.LegacyOnly | Should-BeTrue
        }

        It 'does not raise KRB005 against a client advertising only unknown ciphers' {
            $risk = @(Get-FixtureEvent '4768-v2-unknown-cipher-client.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'FUTURE-CLIENT01$'

            $risk | Should-NotBeNull
            @($risk.FindingCodes) | Should-NotContainCollection @('KRB005')
            $risk.WillBreakOnHardening | Should-BeFalse
        }

        It 'still raises KRB005 against a genuinely legacy client' {
            $risk = @(Get-FixtureEvent '4768-v2-legacy-client.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'APPLIANCE-SCAN01$'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB005')
        }

        It 'counts a client of unknown capability as unknown, not as capable' {
            # An indeterminate client must land in ClientsWithUnknownSupport. The original
            # bucketing tested AdvertisedAny before AdvertisedAes and dropped such clients
            # into neither list, so the report neither warned about them nor counted them as
            # unmeasured.
            $risk = @(Get-FixtureEvent @(
                '4768-v2-unknown-cipher-client.xml'
                '4769-v2-healthy-aes.xml'
            ) | Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'svc-payroll'

            $total = @($risk.ClientsWithoutAesSupport).Count +
                     @($risk.ClientsWithUnknownSupport).Count
            $accountedFor = $total -le $risk.ClientCount

            $accountedFor | Should-BeTrue
        }
    }

    Context 'Defect 3 - every emit path produces the same schema' {

        BeforeAll {
            # Drives all three paths at once: observed principals, an unobserved dangerous
            # account, and a trust.
            $script:AllPaths = @(Get-FixtureEvent @(
                '4769-v2-healthy-aes.xml'
                '4769-v2-service-no-aes-key.xml'
            ) | Get-KrbEtypeRisk -IncludeHealthy `
                -Principal @(New-TestPrincipal -SamAccountName 'svc-quiet-des' -SupportedEncryptionTypes 3) `
                -DomainContext (New-TestDomainContext))
        }

        It 'exercises all three emit paths' {
            @($script:AllPaths | Where-Object { $_.Roles -contains 'Service' }) |
                Should-BeCollection -Count 2
            @($script:AllPaths | Where-Object { $_.Roles -contains 'Unobserved' }) |
                Should-BeCollection -Count 1
            @($script:AllPaths | Where-Object { $_.Roles -contains 'Trust' }) |
                Should-BeCollection -Count 1
        }

        It 'gives every risk object an identical property set' {
            $shapes = @($script:AllPaths |
                ForEach-Object { ($_.PSObject.Properties.Name | Sort-Object) -join '|' } |
                Sort-Object -Unique)

            $shapes | Should-BeCollection -Count 1
        }

        It 'never leaves a collection property null' {
            # @($null).Count is 1, not 0. A missing collection property therefore renders as
            # one phantom item - which is how a trust row came to report an AES-incapable
            # client that did not exist.
            #
            # Asserted without the pipeline. Piping an EMPTY array to Should-NotBeNull sends
            # nothing down the pipeline at all, so the assertion receives $null and fails on
            # exactly the values this test is trying to prove are correct.
            foreach ($risk in $script:AllPaths) {
                foreach ($name in 'ClientsWithoutAesSupport', 'ClientsWithUnknownSupport',
                                  'Clients', 'ClientAddresses', 'ServiceNames',
                                  'ObservedTicketEtypes', 'ObservedTicketEtypeNames',
                                  'Findings', 'FindingCodes', 'ConfidenceNotes', 'Roles') {

                    $property = $risk.PSObject.Properties[$name]
                    $property | Should-NotBeNull -Because "$($risk.PrincipalName) must declare $name"

                    ($null -eq $property.Value) |
                        Should-BeFalse -Because "$($risk.PrincipalName).$name must not be null"
                }
            }
        }

        It 'reports zero AES-incapable clients on a trust row' {
            $trust = $script:AllPaths | Where-Object { $_.Roles -contains 'Trust' }

            @($trust.ClientsWithoutAesSupport) | Should-BeCollection -Count 0
            @($trust.ObservedTicketEtypeNames) | Should-BeCollection -Count 0
        }
    }

    Context 'Defect 5 - krbtgt is a domain property, not a service' {

        It 'does not create a service row from a TGT renewal' {
            # A 4769 whose ServiceName is the bare string krbtgt. Excluding only 4768 was not
            # enough, and the original test for this filtered to 4768 - where no service rows
            # are created at all - so it passed regardless of the behaviour it claimed to guard.
            $risks = @(Get-FixtureEvent '4769-v2-krbtgt-renewal.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)

            $asService = $risks | Where-Object {
                $_.PrincipalName -eq 'krbtgt' -and @($_.Roles) -contains 'Service'
            }

            $asService | Should-BeNull
        }

        It 'does not turn a cross-realm referral into a service row' {
            # This assertion originally required the OPPOSITE: it expected a principal named
            # 'krbtgt/CONTOSO.NET' to be assessed as a service, on the assumption that a
            # referral is logged with a krbtgt/ prefix. A real forest trust showed it is not -
            # ServiceName carries the bare realm - so the referral is attributed to the trust
            # and produces no principal row of its own.
            $risks = @(Get-FixtureEvent '4769-v2-crossrealm-referral.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy)

            @($risks | Where-Object { @($_.Roles) -contains 'Service' }) |
                Should-BeCollection -Count 0
        }
    }

    Context 'Finding codes that previously had no test at all' {

        It 'raises KRB014 for a trust that permits no AES' {
            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -IncludeHealthy -Principal @() `
                    -DomainContext (New-TestDomainContext -TrustEncryptionTypes 4)) |
                Where-Object { $_.Roles -contains 'Trust' }

            $risk | Should-NotBeNull
            @($risk.FindingCodes) | Should-ContainCollection @('KRB014')
            $risk.RiskLevel | Should-Be 'High'
            $risk.WillBreakOnHardening | Should-BeTrue
        }

        It 'raises KRB012 for an explicitly non-AES account with no traffic' {
            $risk = @(Get-FixtureEvent '4769-v2-healthy-aes.xml' |
                Get-KrbEtypeRisk -IncludeHealthy `
                    -Principal @(New-TestPrincipal -SamAccountName 'svc-dormant' -SupportedEncryptionTypes 4)) |
                Where-Object PrincipalName -eq 'svc-dormant'

            $risk | Should-NotBeNull
            @($risk.FindingCodes) | Should-ContainCollection @('KRB012')
            $risk.RiskLevel | Should-Be 'Medium'
            $risk.RequestCount | Should-Be 0

            # Medium, not Critical: there is no evidence either way, which is a different
            # statement from evidence that it is broken.
            $risk.WillBreakOnHardening | Should-BeFalse
        }

        It 'raises KRB008 when pre-authentication only ever used a removed type' {
            $risk = @(Get-FixtureEvent '4768-v2-legacy-client.xml' |
                Get-KrbEtypeRisk -Offline -IncludeHealthy) |
                Where-Object PrincipalName -eq 'APPLIANCE-SCAN01$'

            @($risk.FindingCodes) | Should-ContainCollection @('KRB008')
            ($risk.Findings | Where-Object Code -eq 'KRB008').Severity | Should-Be 'High'
        }

        It 'raises KRB006 when key material cannot be confirmed on a legacy schema' {
            # Version 0 events carry no available-key field, so the engine can only infer.
            # KRB006 is the inference, rated below the KRB002 observation deliberately.
            $risk = @(Get-FixtureEvent '4769-v0-legacy-schema.xml' |
                Get-KrbEtypeRisk -IncludeHealthy `
                    -Principal @(New-TestPrincipal -SamAccountName 'svc-fileshare' `
                        -SupportedEncryptionTypes 0x1C -PwdAgeDays 900)) |
                Where-Object PrincipalName -eq 'svc-fileshare'

            $risk | Should-NotBeNull
            @($risk.FindingCodes) | Should-ContainCollection @('KRB006')
            ($risk.Findings | Where-Object Code -eq 'KRB006').Severity | Should-Be 'High'
            @($risk.FindingCodes) | Should-NotContainCollection @('KRB002')
        }

        It 'leaves no finding code emitted by the engine without a test' {
            # The check that would have caught two of these defects. Every -Code literal in
            # the risk engine must appear somewhere in the test suite.
            $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
            $engine = Get-Content -Raw -Path (Join-Path $moduleRoot 'Public\Get-KrbEtypeRisk.ps1')

            $emitted = @([regex]::Matches($engine, "-Code '(KRB\d{3})'") |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

            $testCorpus = (Get-ChildItem -Path (Join-Path $moduleRoot 'Tests') -Recurse -Filter '*.Tests.ps1' |
                Get-Content -Raw) -join "`n"

            $uncovered = @($emitted | Where-Object { $testCorpus -notmatch [regex]::Escape($_) })

            $uncovered | Should-BeCollection -Count 0 -Because "uncovered: $($uncovered -join ', ')"
        }
    }
}

Describe 'Get-KrbEtypeRisk graceful degradation' -Tag 'Unit', 'Public', 'Regression' {

    # The documented promise that a partial assessment reported honestly beats no assessment.
    # Both of these paths existed from the first version and neither had ever executed.

    Context 'Directory unavailable mid-assessment' {

        It 'continues with the Windows default when the domain baseline cannot be collected' {
            Mock -ModuleName KrbEtypeInsight Get-KrbDomainEtypeContext { throw 'server not operational' }
            Mock -ModuleName KrbEtypeInsight Get-KrbPrincipalEtype { @() }

            $captured = @(Get-FixtureEvent '4769-v2-service-no-aes-key.xml' |
                Get-KrbEtypeRisk -IncludeHealthy 3>&1)

            $risks = @($captured | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $warnings = @($captured | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            # The assessment still happened, and it said what it lost.
            $risks.Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'Windows default'
        }

        It 'continues with event evidence only when principals cannot be enumerated' {
            Mock -ModuleName KrbEtypeInsight Get-KrbDomainEtypeContext {
                [PSCustomObject]@{
                    PSTypeName = 'KrbEtypeInsight.DomainContext'
                    DomainDefaultEncryptionTypes = 0x27
                    TrustsWithRc4Only = @()
                }
            }
            Mock -ModuleName KrbEtypeInsight Get-KrbPrincipalEtype { throw 'access denied' }

            $captured = @(Get-FixtureEvent '4769-v2-service-no-aes-key.xml' |
                Get-KrbEtypeRisk -IncludeHealthy 3>&1)

            $risks = @($captured | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $warnings = @($captured | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $risks.Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'event evidence only'

            # Nothing resolved, so nothing may claim to have been.
            foreach ($risk in $risks) { $risk.ResolvedInDirectory | Should-BeFalse }
        }
    }
}

Describe 'Get-KrbEvent regressions' -Tag 'Unit', 'Public', 'Regression' {

    Context 'Defect 4 - a healthy source must not be reported as unaudited' {

        BeforeAll {
            # A source that returns events, none of them failures - which is what a healthy
            # controller looks like during post-change verification.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
        }

        It 'does not warn about audit policy when events were read but none were failures' {
            $healthy = Get-FixtureEvent '4769-v2-healthy-aes.xml'

            # -RemoveParameterType is required on the decoder. Its -Record parameter is typed
            # [EventLogRecord], a class with no public constructor, so the stand-in record the
            # Get-WinEvent mock returns cannot bind to it. Pester strips the type constraint
            # so the mock can be reached at all.
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { 'stand-in-record' }
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' -MockWith { $healthy }.GetNewClosure()

            $captured = @(Get-KrbEvent -IncludeFailureOnly 3>&1)
            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            # The healthy fixture is a successful ticket request, so -IncludeFailureOnly
            # emits nothing. That is a clean domain, not an unaudited one.
            @($warnings).Count | Should-Be 0
        }

        It 'still warns when a source genuinely produced nothing' {
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            $captured = @(Get-KrbEvent 3>&1)
            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'audit subcategories'
        }
    }

    Context 'Boot-time forwarded-TGT requests must not count as client capability' {

        # The defect this guards was found by running against a real domain and then proved
        # on the wire. A machine with SupportedEncryptionTypes = 0x4 (RC4 only) emits, on
        # every normal boot, exactly one TGS-REQ for krbtgt/REALM advertising AES256 alone,
        # kdc-options 0x60810010. Seven instrumented boots across two unrelated machines:
        # 6 of 7 showed it, always identical, and 0 of 19 AS-REQs ever advertised AES.
        #
        # Client capability was accumulated as a union - one AES advertisement anywhere meant
        # "this client can do AES". That single boot-time request therefore marked EVERY
        # rebooted Windows client as AES-capable. With a 30-day default collection window
        # almost every client boots at least once, so KRB005 - the named list of machines a
        # hardening change will break, which is the module's entire deliverable - could not
        # fire for the population it exists to describe.
        #
        # The fixtures are modelled on the captured packets rather than invented.

        It 'fires KRB005 for a client whose only AES advertisement is a krbtgt request' {
            $events = Get-FixtureEvent -Name @(
                '4769-v2-rc4client-service-request.xml'
                '4769-v2-boottime-forwarded-tgt-aes256.xml'
            )

            $risk = @($events | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue)
            $service = $risk | Where-Object { $_.PrincipalName -eq 'svc-legacyapp' }

            $service | Should-NotBeNull
            $service.Findings.Code | Should-ContainCollection 'KRB005'
            @($service.ClientsWithoutAesSupport) | Should-ContainCollection 'RC4CLIENT$'
        }

        It 'reports how much evidence stood behind the finding' {
            $events = Get-FixtureEvent -Name @(
                '4769-v2-rc4client-service-request.xml'
                '4769-v2-boottime-forwarded-tgt-aes256.xml'
            )

            $risk = @($events | Get-KrbEtypeRisk -Offline -WarningAction SilentlyContinue)
            $finding = ($risk | Where-Object { $_.PrincipalName -eq 'svc-legacyapp' }).Findings |
                Where-Object Code -eq 'KRB005'

            # A count survives a mechanism nobody has characterised yet; a bare boolean does not.
            $finding.Evidence.NoAesAdvertisements | Should-Be 1
            $finding.Evidence.ExcludedTgtServiceEvents | Should-Be 1
            $finding.Detail | Should-MatchString 'forwarded-TGT'
        }

        It 'still trusts an AES advertisement made on an ordinary service request' {
            # The exclusion must be narrow. A client that advertises AES while asking for a
            # real service is genuinely AES-capable, and condemning it would be the false
            # positive this module cannot afford.
            $events = Get-FixtureEvent -Name @(
                '4769-v2-healthy-aes.xml'
                '4769-v2-rc4client-service-request.xml'
            )

            # -IncludeHealthy, because a service with nothing wrong emits no risk object by
            # default and the absence of a finding is exactly what is being asserted.
            $risk = @($events | Get-KrbEtypeRisk -Offline -IncludeHealthy -WarningAction SilentlyContinue)
            $healthy = $risk | Where-Object { $_.PrincipalName -eq 'svc-payroll' }

            $healthy | Should-NotBeNull
            @($healthy.ClientsWithoutAesSupport) | Should-NotContainCollection 'WKS-FINANCE-04$'
            $healthy.Findings.Code | Should-NotContainCollection 'KRB005'
        }
    }
}
