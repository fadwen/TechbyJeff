#Requires -Version 7.6

function ConvertTo-KrbLdapFilterValue {
    <#
    .SYNOPSIS
        Escapes a value for safe inclusion in an LDAP search filter

    .DESCRIPTION
        Applies RFC 4515 section 3 escaping to a string before it is interpolated into an
        LDAP filter.

        This module builds filters from values that originate in the event log - service
        principal names and account names written by whatever client made the request. Those
        are attacker-influenceable in the ordinary case: anyone who can request a service
        ticket can choose the SPN string that lands in a 4769 event, including one containing
        LDAP filter metacharacters.

        Unescaped, a crafted SPN turns a lookup for one account into a filter that matches
        every account in the directory, or into one that silently matches nothing so that a
        risky principal is omitted from the report. The second outcome is the more dangerous
        of the two, because it fails quietly.

        The five characters RFC 4515 requires escaping are the NUL byte, the opening and
        closing parentheses, the asterisk, and the backslash. The backslash is replaced first;
        replacing it later would double-escape the backslashes introduced by the other four
        substitutions.

    .PARAMETER Value
        [System.String] (Mandatory, Pipeline: ByValue)

        The raw value to escape.

    .EXAMPLE
        PS> ConvertTo-KrbLdapFilterValue -Value 'MSSQLSvc/db01.contoso.com:1433'

        DESCRIPTION: Escapes an ordinary SPN, which needs no changes
        OUTPUT: MSSQLSvc/db01.contoso.com:1433
        USE CASE: Resolving a service principal name to its account

    .EXAMPLE
        PS> ConvertTo-KrbLdapFilterValue -Value 'HOST/*)(objectClass=*'

        DESCRIPTION: Neutralises a value crafted to break out of the filter
        OUTPUT: HOST/\2a\29\28objectClass=\2a
        USE CASE: Preventing a hostile SPN in the event log from widening a directory search

    .OUTPUTS
        System.String

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - SPN resolution failures: .\Troubleshooting\Common\SPN-Resolution.md

    .LINK
        https://www.rfc-editor.org/rfc/rfc4515#section-3
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Value
    )

    process {
        if ([string]::IsNullOrEmpty($Value)) { return '' }

        # Backslash first. Reversing this order would escape the backslashes that the
        # subsequent replacements introduce, turning '*' into '\5c2a' rather than '\2a'.
        $escaped = $Value.Replace('\', '\5c')
        $escaped = $escaped.Replace('*', '\2a')
        $escaped = $escaped.Replace('(', '\28')
        $escaped = $escaped.Replace(')', '\29')
        $escaped = $escaped.Replace([string][char]0, '\00')

        return $escaped
    }
}
