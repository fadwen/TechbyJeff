#Requires -Version 7.6

function ConvertTo-KrbKeyNameList {
    <#
    .SYNOPSIS
        Splits an AvailableKeys event field into a normalised array of key family names

    .DESCRIPTION
        The AccountAvailableKeys, ServiceAvailableKeys and DCAvailableKeys fields of a
        version 2 4768 or 4769 event carry a comma-separated list such as 'AES-SHA1, RC4',
        or the literal 'N/A' when the KDC did not populate them.

        The distinction this function preserves is between an empty list and no list at all:

        - $null means the field was absent or 'N/A'. The event did not tell us which keys
          exist, most likely because the DC emits an older schema version.
        - @() means the field was present and named no keys. That is a principal with no
          usable key material at all.

        Collapsing those two into one value is how an assessment ends up asserting that every
        account on a Server 2016 domain controller has no AES key, when in truth the DC
        simply never wrote the field.

    .PARAMETER Value
        [System.String] (Mandatory, Pipeline: ByValue)

        The raw field text.

    .EXAMPLE
        PS> ConvertTo-KrbKeyNameList -Value 'AES-SHA1, RC4'

        DESCRIPTION: Splits a populated available-keys field
        OUTPUT: @('AES-SHA1', 'RC4')
        USE CASE: Determining that an account holds AES key material

    .EXAMPLE
        PS> ConvertTo-KrbKeyNameList -Value 'N/A'

        DESCRIPTION: Recognises the KDC's not-populated marker
        OUTPUT: $null
        USE CASE: Avoiding a false "no AES keys" finding on a legacy event schema

    .OUTPUTS
        System.String[] or $null

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Missing version 2 fields: .\Troubleshooting\Common\Event-Schema-Versions.md
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

        $text = $Value.Trim()
        if ($text -in 'N/A', '-') { return $null }

        # A plain loop, not '-split | ForEach-Object | Where-Object'. This runs three times
        # per event - once each for the account, service and DC key lists - and a two-stage
        # cmdlet pipeline costs roughly a millisecond per call, which measured as the single
        # largest remaining cost in the decode path once the obvious ones were gone. The
        # idiomatic form is the right default; at three invocations per record across a
        # multi-hundred-thousand-event collection it is not.
        $result = [System.Collections.Generic.List[string]]::new()

        foreach ($piece in $text.Split(',')) {
            $trimmed = $piece.Trim()
            if ($trimmed) { $result.Add($trimmed) }
        }

        # Unary comma so that a single-key result stays an array. Without it, a principal
        # holding only RC4 returns a bare string, and a downstream '-contains' test against
        # it becomes a substring test that matches nothing.
        , [string[]]$result
    }
}
