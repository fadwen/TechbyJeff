#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    LDAP filter escaping, per RFC 4515 section 3.

    This matters more here than the usual "escape your inputs" hygiene, because of where the
    values come from. The module resolves service principal names taken out of the event log,
    and an SPN in a 4769 event is a string the CLIENT chose - anyone able to request a service
    ticket can put whatever they like in it.

    Two failure modes, and the second is worse:

    - An unescaped '*' or '(' widens the filter, and the lookup for one account returns many.
      Noisy, obvious, gets noticed.
    - An unescaped sequence that makes the filter match nothing means a genuinely risky
      principal is silently absent from the assessment. The report comes back shorter and
      cleaner, and nobody asks why.

    The ordering test is the one that actually catches regressions: escaping the backslash
    after the other four double-escapes the backslashes those four introduce.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-KrbLdapFilterValue' -Tag 'Unit', 'Private', 'Security' {

    Context 'RFC 4515 escaping' {

        It 'escapes <Description>' -ForEach @(
            @{ Value = '*';  Expected = '\2a'; Description = 'the asterisk' }
            @{ Value = '(';  Expected = '\28'; Description = 'the opening parenthesis' }
            @{ Value = ')';  Expected = '\29'; Description = 'the closing parenthesis' }
            @{ Value = '\';  Expected = '\5c'; Description = 'the backslash' }
        ) {
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value; Expected = $Expected } {
                ConvertTo-KrbLdapFilterValue -Value $Value | Should-Be $Expected
            }
        }

        It 'escapes the backslash first so the others are not double-escaped' {
            # Reverse the order and '*' becomes '\5c2a' rather than '\2a', which no longer
            # means asterisk and no longer matches the account it was meant to find.
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbLdapFilterValue -Value '\*' | Should-Be '\5c\2a'
            }
        }

        It 'escapes a null byte' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbLdapFilterValue -Value ("a" + [char]0 + "b") | Should-Be 'a\00b'
            }
        }
    }

    Context 'Ordinary service principal names' {

        It 'leaves <Value> unchanged' -ForEach @(
            @{ Value = 'MSSQLSvc/db01.contoso.com:1433' }
            @{ Value = 'HOST/WKS-FINANCE-04' }
            @{ Value = 'HTTP/intranet.contoso.com' }
            @{ Value = 'WS22-EV-01$' }
            @{ Value = 'svc-payroll' }
            @{ Value = 'krbtgt/AD.CONTOSO.COM' }
        ) {
            # Slashes, colons, dollars and dots are not LDAP metacharacters. Escaping them
            # anyway would break every legitimate SPN lookup in the module.
            InModuleScope KrbEtypeInsight -Parameters @{ Value = $Value } {
                ConvertTo-KrbLdapFilterValue -Value $Value | Should-Be $Value
            }
        }
    }

    Context 'Hostile input from the event log' {

        It 'neutralises a filter injection attempt' {
            InModuleScope KrbEtypeInsight {
                $hostile = 'HOST/*)(objectClass=*'
                $escaped = ConvertTo-KrbLdapFilterValue -Value $hostile

                # No unescaped metacharacter survives, so the value cannot terminate the
                # filter clause it is interpolated into.
                $escaped | Should-NotMatchString '(?<!\\5c)[*()]'
                $escaped | Should-Be 'HOST/\2a\29\28objectClass=\2a'
            }
        }

        It 'produces a filter that still parses as a single clause' {
            InModuleScope KrbEtypeInsight {
                $escaped = ConvertTo-KrbLdapFilterValue -Value 'HOST/*)(objectClass=*'
                $filter = "(servicePrincipalName=$escaped)"

                # Balanced and singular: exactly one opening and one closing parenthesis
                # survive, and they are the ones this code wrote.
                ([regex]::Matches($filter, '(?<!\\5c)\(')).Count | Should-Be 1
                ([regex]::Matches($filter, '(?<!\\5c)\)')).Count | Should-Be 1
            }
        }

        It 'handles the fixture SPN that carries both LDAP and HTML payloads' {
            InModuleScope KrbEtypeInsight {
                $escaped = ConvertTo-KrbLdapFilterValue -Value 'HOST/*)(objectClass=*)<script>alert(1)</script>'

                $escaped | Should-NotMatchString '(?<!\\5c)[*()]'

                # Angle brackets are not LDAP metacharacters and are deliberately left alone -
                # they are the report renderer's problem, and encoding them here would corrupt
                # the value for every other consumer.
                $escaped | Should-MatchString '<script>'
            }
        }
    }

    Context 'Edge cases' {

        It 'returns an empty string for empty input' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbLdapFilterValue -Value '' | Should-Be ''
            }
        }

        It 'returns a string' {
            InModuleScope KrbEtypeInsight {
                ConvertTo-KrbLdapFilterValue -Value 'svc-test' | Should-HaveType ([string])
            }
        }
    }
}
