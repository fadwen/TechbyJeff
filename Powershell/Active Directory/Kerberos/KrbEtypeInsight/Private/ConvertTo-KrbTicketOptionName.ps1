#Requires -Version 7.6

function ConvertTo-KrbTicketOptionName {
    <#
    .SYNOPSIS
        Decodes the TicketOptions bit field of a Kerberos audit event into option names

    .DESCRIPTION
        TicketOptions carries the KDCOptions flags the client requested, as a hex string such
        as '0x40810010'. Naming the bits matters to an encryption-type assessment for one
        specific reason: a principal that appears in the report with an unexpectedly large
        client count is often a delegation target, where each hop generates its own service
        ticket request. Seeing Forwardable and Forwarded on those requests explains the count
        without a separate investigation.

        Unrecognised bits are not reported. The field is preserved verbatim alongside this
        decoding on every event object, so nothing is lost, and listing every reserved bit a
        Windows client happens to set would bury the three that carry meaning.

    .PARAMETER Value
        [System.String] (Mandatory, Pipeline: ByValue)

        The raw TicketOptions field text.

    .EXAMPLE
        PS> ConvertTo-KrbTicketOptionName -Value '0x40810010'

        DESCRIPTION: Decodes a typical workstation ticket request
        OUTPUT: @('Forwardable', 'Renewable', 'Canonicalize', 'Renewable-OK')
        USE CASE: Explaining why a delegation target shows an inflated request count

    .OUTPUTS
        System.String[] or $null

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Interpreting ticket options: .\Troubleshooting\Common\KDC-Status-Codes.md
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    begin {
        $catalog = Get-KrbProtocolCatalog
        $optionTable = $catalog.TicketOption

        # Already in descending order from the catalog. Sorting here instead would repeat
        # the work on every event in the collection for an answer that never changes.
        $orderedBits = $catalog.SortedTicketOptionKeys
    }

    process {
        $bits = ConvertTo-KrbInt32 -Value $Value
        if ($null -eq $bits) { return $null }

        # High-order flags first, which is the order an administrator reading a report
        # expects them in.
        , @(
            foreach ($bit in $orderedBits) {
                if ($bits -band $bit) { $optionTable[$bit] }
            }
        )
    }
}
