#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The directory reader, with Get-ADObject mocked so the tests describe attribute handling
    rather than the contents of whatever domain happens to be nearby.

    Four behaviours carry real consequences:

    - sAMAccountName has to be requested explicitly. It is not one of Get-ADObject's default
      properties, and omitting it produces principal objects whose SamAccountName is silently
      empty. Those become empty keys in the risk engine's account index, and every
      correlation between an event and a directory record is quietly lost - with no error and
      no missing rows, just findings that never mention configuration.

    - pwdLastSet arrives as a FILETIME integer from Get-ADObject and as a DateTime from
      Get-ADUser. Both shapes reach this function. A missing conversion yields a null password
      age, which reads in the report as "age unknown" on precisely the accounts whose age
      decides whether they hold AES keys.

    - objectClass is multi-valued and ordered least to most specific. Taking the first entry
      returns 'top' for every object in the directory.

    - Values interpolated into LDAP filters are escaped. The SPNs this function is asked to
      resolve come out of the event log, where the client chose them.
#>

# Script-level suppressions. A SuppressMessageAttribute on a param() block at the top of a
# script applies to the whole file.
#
# ConvertToSecureStringWithPlainText: these are throwaway literals used to construct a
# PSCredential that is never authenticated with - the tests assert only that the parameter is
# forwarded. There is no secret here to protect.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Throwaway literal for a credential that is never authenticated with.')]
param()

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    # Every directory call below is mocked, but Pester cannot attach a mock to a command
    # that does not exist. On a host without RSAT the stub supplies the names; on a domain
    # controller the real cmdlets win, because the stub path is appended, not prepended.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-KrbTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force

    function New-MockAdObject {

        <#
            Builds an object shaped like what Get-ADObject returns, including the awkward
            details: objectClass as an ordered multi-value, pwdLastSet as a FILETIME, and
            attribute names carrying their real LDAP casing.
        #>
        # The attribute binds to the enclosing function only when it sits inside it, ahead of
        # param(). This helper builds a stand-in object and changes no system state.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test fixture builder; constructs an object, changes no state.')]
        param(
            [string]$SamAccountName = 'svc-test',
            [object]$SupportedEncryptionTypes = $null,
            [int]$UserAccountControl = 512,
            [string[]]$Spn = @(),
            [int]$PwdAgeDays = 30,
            [string[]]$ObjectClass = @('top', 'person', 'organizationalPerson', 'user')
        )

        [PSCustomObject]@{
            SamAccountName    = $SamAccountName
            DistinguishedName = "CN=$SamAccountName,CN=Users,DC=ad,DC=techbyjeff,DC=net"
            objectClass       = $ObjectClass
            objectSid         = [PSCustomObject]@{ Value = 'S-1-5-21-1-1-1-1001' }
            displayName       = $SamAccountName
            description       = ''
            'msDS-SupportedEncryptionTypes' = $SupportedEncryptionTypes
            userAccountControl = $UserAccountControl
            servicePrincipalName = $Spn
            pwdLastSet        = (Get-Date).AddDays(-$PwdAgeDays).ToFileTime()
            whenCreated       = (Get-Date).AddDays(-400)
            lastLogonTimestamp = (Get-Date).AddDays(-1).ToFileTime()
        }
    }
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbPrincipalEtype' -Tag 'Unit', 'Public', 'Directory' {

    Context 'Attribute retrieval' {

        BeforeAll {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }
        }

        It 'requests sAMAccountName explicitly' {
            # Not a default property of Get-ADObject. Omitted, every principal comes back
            # with an empty name, becomes an empty key in the risk engine's index, and the
            # correlation between events and configuration disappears without an error.
            Get-KrbPrincipalEtype -All | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight `
                -ParameterFilter { $Properties -contains 'sAMAccountName' }
        }

        It 'requests every attribute the assessment depends on' {
            Get-KrbPrincipalEtype -All | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -ParameterFilter {
                $Properties -contains 'msDS-SupportedEncryptionTypes' -and
                $Properties -contains 'userAccountControl' -and
                $Properties -contains 'servicePrincipalName' -and
                $Properties -contains 'pwdLastSet'
            }
        }

        It 'does not request every attribute with a wildcard' {
            # -Properties * pulls constructed and back-linked attributes - memberOf and
            # tokenGroups among them - which cost the directory real work for data this
            # function never reads.
            Get-KrbPrincipalEtype -All | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight `
                -ParameterFilter { $Properties -notcontains '*' }
        }
    }

    Context 'Attribute decoding' {

        BeforeAll {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -SamAccountName 'svc-legacy' -SupportedEncryptionTypes 4 `
                    -Spn @('MSSQLSvc/db01:1433') -PwdAgeDays 900
            }
        }

        It 'returns the account name' {
            (Get-KrbPrincipalEtype -All).SamAccountName | Should-Be 'svc-legacy'
        }

        It 'decodes the encryption type attribute' {
            $result = Get-KrbPrincipalEtype -All

            $result.EncryptionTypes.SupportsRc4 | Should-BeTrue
            $result.EncryptionTypes.SupportsAes | Should-BeFalse
        }

        It 'converts pwdLastSet from a FILETIME to a password age' {
            # A missing conversion yields a null age, which reads in the report as "unknown"
            # on exactly the accounts whose age determines whether AES keys exist.
            $result = Get-KrbPrincipalEtype -All

            $result.PasswordAgeDays | Should-Be 900
            $result.PasswordLastSet | Should-HaveType ([datetime])
        }

        It 'takes the most specific objectClass, not the first' {
            # objectClass is ordered least to most specific. The first entry is 'top' for
            # every object in the directory.
            (Get-KrbPrincipalEtype -All).ObjectClass | Should-Be 'user'
        }

        It 'reports the service principal names' {
            $result = Get-KrbPrincipalEtype -All

            $result.HasSpn | Should-BeTrue
            @($result.ServicePrincipalNames) | Should-BeCollection @('MSSQLSvc/db01:1433')
        }

        It 'emits the declared PSTypeName' {
            (Get-KrbPrincipalEtype -All).PSTypeNames[0] | Should-Be 'KrbEtypeInsight.Principal'
        }
    }

    Context 'userAccountControl interpretation' {

        It 'derives Enabled from the account control bit' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -UserAccountControl (512 -bor 0x2)
            }

            (Get-KrbPrincipalEtype -All).Enabled | Should-BeFalse
        }

        It 'detects USE_DES_KEY_ONLY, which overrides the encryption type attribute' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -SupportedEncryptionTypes 0x1C -UserAccountControl (512 -bor 0x200000)
            }

            $result = Get-KrbPrincipalEtype -All

            # The attribute says RC4 and AES; the bit means the KDC ignores it. An
            # attribute-only assessment reports this account as healthy.
            $result.EncryptionTypes.SupportsAes | Should-BeTrue
            $result.AccountControl.UseDesKeyOnly | Should-BeTrue
        }

        It 'detects delegation flags' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -UserAccountControl (512 -bor 0x80000)
            }

            (Get-KrbPrincipalEtype -All).AccountControl.TrustedForDelegation | Should-BeTrue
        }

        It 'detects accounts that do not require pre-authentication' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -UserAccountControl (512 -bor 0x400000)
            }

            (Get-KrbPrincipalEtype -All).AccountControl.DontRequirePreAuth | Should-BeTrue
        }
    }

    Context 'Domain default baseline' {

        It 'judges an unset attribute against the supplied domain default' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -SupportedEncryptionTypes $null
            }

            $withAesDefault = Get-KrbPrincipalEtype -All -DomainDefaultEncryptionTypes 0x18
            $withWindowsDefault = Get-KrbPrincipalEtype -All -DomainDefaultEncryptionTypes 0x27

            # The same account, judged against two different baselines, is a different
            # finding. Assuming the baseline is how a report misjudges the majority of a
            # domain, since most accounts have this attribute unset.
            $withAesDefault.EncryptionTypes.SupportsAes | Should-BeTrue
            $withWindowsDefault.EncryptionTypes.SupportsAes | Should-BeFalse
        }

        It 'marks an unset attribute as inheriting the default' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -SupportedEncryptionTypes $null
            }

            $result = Get-KrbPrincipalEtype -All

            $result.EncryptionTypes.IsUnset | Should-BeTrue
            $result.EncryptionTypes.UsesDomainDefault | Should-BeTrue
        }
    }

    Context 'Enumeration filtering' {

        BeforeAll {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }
        }

        It 'excludes disabled accounts server-side by default' {
            # Filtering locally would transfer every tombstoned service account in a large
            # domain only to discard it.
            Get-KrbPrincipalEtype -All | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -ParameterFilter {
                $LDAPFilter -match '1\.2\.840\.113556\.1\.4\.803:=2'
            }
        }

        It 'includes disabled accounts when asked' {
            Get-KrbPrincipalEtype -All -IncludeDisabled | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -ParameterFilter {
                $LDAPFilter -notmatch '1\.2\.840\.113556\.1\.4\.803:=2'
            }
        }

        It 'restricts to accounts with a service principal name when asked' {
            Get-KrbPrincipalEtype -All -ServiceAccountOnly | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -ParameterFilter {
                $LDAPFilter -match 'servicePrincipalName=\*'
            }
        }
    }

    Context 'Service principal name resolution' {

        It 'escapes a hostile service principal name before building the filter' {
            # The SPN comes out of the event log, where the client chose it. Unescaped, a
            # crafted value either widens the search or - worse, because it is silent -
            # narrows it to nothing, dropping a risky principal from the assessment.
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }

            Get-KrbPrincipalEtype -ServicePrincipalName 'HOST/*)(objectClass=*' | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -ParameterFilter {
                $LDAPFilter -match '\\2a' -and $LDAPFilter -notmatch 'objectClass=\*\)$'
            }
        }

        It 'falls back to a bare account name when the SPN matches nothing' {
            # The KDC writes ServiceName as a bare account name as often as a full SPN.
            $script:CallCount = 0
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                if ($LDAPFilter -match 'servicePrincipalName') { return $null }
                New-MockAdObject -SamAccountName 'svc-payroll'
            }

            $result = Get-KrbPrincipalEtype -ServicePrincipalName 'svc-payroll'

            $result.SamAccountName | Should-Be 'svc-payroll'
            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight -Times 2 -Exactly
        }

        It 'errors when an SPN in the log has no owner in the directory' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { $null }

            {
                Get-KrbPrincipalEtype -ServicePrincipalName 'HOST/ghost' -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*No account owns*'
        }

        It 'warns when a service principal name is registered on more than one account' {
            # A duplicate SPN makes the KDC return KDC_ERR_PRINCIPAL_NOT_UNIQUE and the
            # service fails for everyone, independently of any encryption type change. An
            # assessment is when it gets found.
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                @(
                    New-MockAdObject -SamAccountName 'svc-one'
                    New-MockAdObject -SamAccountName 'svc-two'
                )
            }

            $captured = @(Get-KrbPrincipalEtype -ServicePrincipalName 'HOST/shared' 3>&1)
            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'registered on 2 accounts'
        }
    }

    Context 'Identity lookup' {

        It 'falls back to a search when Identity is a sAMAccountName' {
            # Get-ADObject -Identity accepts only a DN or GUID, but a sAMAccountName is what
            # an administrator actually has to hand.
            Mock -ModuleName KrbEtypeInsight Get-ADObject -ParameterFilter { $Identity } {
                throw 'Cannot find an object with identity'
            }
            Mock -ModuleName KrbEtypeInsight Get-ADObject -ParameterFilter { $LDAPFilter } {
                New-MockAdObject -SamAccountName 'svc-payroll'
            }

            $result = Get-KrbPrincipalEtype -Identity 'svc-payroll'
            $result.SamAccountName | Should-Be 'svc-payroll'
        }

        It 'marks krbtgt, whose encryption types are a domain-wide property' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                New-MockAdObject -SamAccountName 'krbtgt'
            }

            (Get-KrbPrincipalEtype -Identity 'krbtgt').IsKrbtgt | Should-BeTrue
        }
    }

    Context 'Timestamp shapes' {

        It 'accepts pwdLastSet as a DateTime, as Get-ADUser returns it' {
            # Get-ADObject hands back a FILETIME integer; Get-ADUser hands back a DateTime.
            # Both shapes reach this function through the Identity fallback path, and the
            # DateTime branch had never been executed by a test. A missing conversion yields
            # a null password age, which reads in the report as "age unknown" on exactly the
            # accounts whose age decides whether AES keys exist.
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                $object = New-MockAdObject -SamAccountName 'svc-datetime'
                $object.pwdLastSet = (Get-Date).AddDays(-450)
                $object.lastLogonTimestamp = (Get-Date).AddDays(-2)
                $object
            }

            $result = Get-KrbPrincipalEtype -All

            $result.PasswordLastSet | Should-HaveType ([datetime])
            $result.PasswordAgeDays | Should-Be 450
            $result.LastLogonTimestamp | Should-HaveType ([datetime])
        }

        It 'reports a null password age when pwdLastSet has never been set' {
            # A value of zero means the password has never been set. Converting it as a
            # FILETIME would date the account to the year 1601.
            Mock -ModuleName KrbEtypeInsight Get-ADObject {
                $object = New-MockAdObject -SamAccountName 'svc-never'
                $object.pwdLastSet = 0
                $object
            }

            $result = Get-KrbPrincipalEtype -All

            $result.PasswordLastSet | Should-BeNull
            $result.PasswordAgeDays | Should-BeNull
        }
    }

    Context 'Server and credential targeting' {

        BeforeAll {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }
        }

        It 'passes an explicit server through to the directory query' {
            Get-KrbPrincipalEtype -All -Server 'dc02.ad.techbyjeff.net' | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight `
                -ParameterFilter { $Server -eq 'dc02.ad.techbyjeff.net' }
        }

        It 'passes credentials through to the directory query' {
            # Silently dropping -Credential produces an access-denied that looks like a
            # permission problem on the target rather than a parameter that never arrived.
            $credential = [PSCredential]::new('TECHBYJEFF\svc-audit',
                (ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force))

            Get-KrbPrincipalEtype -All -Credential $credential | Out-Null

            Should-Invoke Get-ADObject -ModuleName KrbEtypeInsight `
                -ParameterFilter { $null -ne $Credential }
        }
    }

    Context 'Input validation' {

        It 'errors on a whitespace-only identity rather than querying for it' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }

            { Get-KrbPrincipalEtype -Identity '   ' -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*empty or whitespace*'
        }

        It 'errors on a whitespace-only service principal name' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject }

            { Get-KrbPrincipalEtype -ServicePrincipalName '   ' -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*empty or whitespace*'
        }

        It 'errors when an identity matches nothing' {
            Mock -ModuleName KrbEtypeInsight Get-ADObject -ParameterFilter { $Identity } {
                throw 'Cannot find an object with identity'
            }
            Mock -ModuleName KrbEtypeInsight Get-ADObject -ParameterFilter { $LDAPFilter } { $null }

            { Get-KrbPrincipalEtype -Identity 'no-such-account' -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*No account found*'
        }

        It 'continues past one bad identity to process the rest' {
            # A batch of identities from a spreadsheet will contain a blank row. One bad entry
            # must not abandon the others.
            Mock -ModuleName KrbEtypeInsight Get-ADObject { New-MockAdObject -SamAccountName 'svc-good' }

            $result = @(Get-KrbPrincipalEtype -Identity '   ', 'svc-good' -ErrorAction SilentlyContinue)

            $result | Should-BeCollection -Count 1
            $result[0].SamAccountName | Should-Be 'svc-good'
        }
    }

    Context 'Read-only guarantee' {

        It 'calls no directory command that modifies an object' {
            # This function is used during a security assessment against production. It must
            # be demonstrably incapable of changing anything.
            $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot `
                        -Parent) -Parent) -Parent
            $source = Get-Content -Raw -Path (
                Join-Path -Path $moduleRoot -ChildPath 'Public\Get-KrbPrincipalEtype.ps1')

            $source | Should-NotMatchString 'Set-AD\w+'
            $source | Should-NotMatchString 'New-AD\w+'
            $source | Should-NotMatchString 'Remove-AD\w+'
        }
    }
}
