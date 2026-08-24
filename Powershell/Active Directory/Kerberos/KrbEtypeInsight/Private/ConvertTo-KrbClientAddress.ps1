#Requires -Version 7.6

function ConvertTo-KrbClientAddress {
    <#
    .SYNOPSIS
        Normalises the IpAddress field of a Kerberos audit event to a comparable form

    .DESCRIPTION
        The KDC writes client addresses in whichever form the socket presented, so the same
        physical client appears under several spellings across a collection:

        - '::ffff:10.20.30.40'  an IPv4-mapped IPv6 address
        - '10.20.30.40'         the same host over a v4 socket
        - '::1'                 a request originating on the domain controller itself
        - '-'                   no address recorded

        Counting "which clients will break" means counting distinct clients, so these have to
        collapse to one key per host before the group-by. Left unnormalised, a single legacy
        application server reports as two or three affected clients and every blast-radius
        number in the report is inflated.

        IPv6 addresses that are not v4-mapped are returned as-is; there is nothing to
        normalise and lowercasing is left to the caller's grouping, which is
        case-insensitive.

    .PARAMETER Value
        [System.String] (Mandatory, Pipeline: ByValue)

        The raw IpAddress field text.

    .EXAMPLE
        PS> ConvertTo-KrbClientAddress -Value '::ffff:10.20.30.40'

        DESCRIPTION: Unwraps an IPv4-mapped IPv6 address
        OUTPUT: 10.20.30.40
        USE CASE: Collapsing duplicate client entries before counting blast radius

    .EXAMPLE
        PS> ConvertTo-KrbClientAddress -Value '::1'

        DESCRIPTION: Recognises a request made on the domain controller itself
        OUTPUT: ::1
        USE CASE: Excluding DC-local traffic from a client impact count

    .OUTPUTS
        System.String or $null

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Client attribution: .\Troubleshooting\Common\Client-Identification.md
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

        $text = $Value.Trim()
        if ($text -eq '-') { return $null }

        # Only the ::ffff: form is unwrapped. The parser is deliberately narrow: a broader
        # "strip everything before the last colon" rule would mangle a genuine IPv6 address
        # into its final hextet.
        if ($text -match '^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$') {
            return $Matches[1]
        }

        return $text
    }
}
