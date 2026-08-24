#Requires -Version 7.6

function ConvertTo-KrbInt32 {
    <#
    .SYNOPSIS
        Normalises the many textual forms of a Kerberos etype value into a signed 32-bit integer

    .DESCRIPTION
        Kerberos encryption-type values reach this module in at least six shapes, depending
        on which producer emitted them:

        - '0x12'                                  a 4768/4769 TicketEncryptionType field
        - '0x1F (DES, RC4, AES128-SHA96, ...)'    a version 2 *SupportedEncryptionTypes field,
                                                  where Windows appends its own decoding
        - '28'                                    msDS-SupportedEncryptionTypes read via LDAP
        - 28                                      the same attribute read via Get-ADObject
        - '0xffffffff'                            the KDC's no-ticket-issued sentinel
        - 'N/A' or '-'                            a field the KDC did not populate

        This function reduces all of them to an [int] or to $null, so that no downstream
        decode has to care which producer it is reading.

        The 0xffffffff case is the one that needs explaining. The KDC writes that value into
        TicketEncryptionType on failure events. Parsed as unsigned it is 4294967295, which
        overflows Int32 and throws; parsed with a plain [int] cast it throws as well. Read as
        a two's-complement bit pattern it is -1, which is what the KDC means and what
        [KrbTicketEtype]::NotApplicable is defined as. The bit-pattern reinterpretation below
        is deliberate, not a cast that happens to work.

    .PARAMETER Value
        [System.Object] (Mandatory, Pipeline: ByValue)

        The raw value to normalise. Accepts integers, hex strings with or without a trailing
        Windows-supplied description, decimal strings, and the null-ish markers 'N/A', '-',
        and the empty string.

    .EXAMPLE
        PS> ConvertTo-KrbInt32 -Value '0x12'

        DESCRIPTION: Parses a hex ticket encryption type
        OUTPUT: 18
        USE CASE: Decoding TicketEncryptionType from an event record

    .EXAMPLE
        PS> ConvertTo-KrbInt32 -Value '0x1F (DES, RC4, AES128-SHA96, AES256-SHA96)'

        DESCRIPTION: Strips the description Windows appends to version 2 event fields
        OUTPUT: 31
        USE CASE: Decoding AccountSupportedEncryptionTypes without hand-editing the string

    .EXAMPLE
        PS> ConvertTo-KrbInt32 -Value '0xffffffff'

        DESCRIPTION: Reinterprets the KDC no-ticket-issued sentinel
        OUTPUT: -1
        USE CASE: Recognising a failure event rather than reporting an exotic cipher

    .OUTPUTS
        System.Int32 or $null when the input carries no value

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Unparsable etype values: .\Troubleshooting\Common\Unknown-Encryption-Types.md
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) { return $null }

        # Integer-ish input needs no parsing, but still needs the 0xffffffff reinterpretation
        # because Get-ADObject can hand back a value that already overflowed into [long].
        if ($Value -is [int]) { return $Value }
        if ($Value -is [long] -or $Value -is [uint32]) {
            $wide = [long]$Value
            if ($wide -gt [int]::MaxValue) {
                return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$wide), 0)
            }
            return [int]$wide
        }

        $text = ([string]$Value).Trim()

        # The KDC populates absent fields with these rather than leaving them empty. They are
        # not zero - zero is a real, meaningful value for msDS-SupportedEncryptionTypes - so
        # they must come back as $null and not be coerced.
        if ([string]::IsNullOrWhiteSpace($text) -or $text -in 'N/A', '-', 'Unknown') {
            return $null
        }

        # Version 2 events render the value as '0x1F (DES, RC4, ...)'. Take the token before
        # the first space and discard Windows' own decoding; the module does its own, and
        # comparing the two is what the fixture tests do.
        $token = ($text -split '\s+', 2)[0]

        if ($token -match '^0[xX]([0-9a-fA-F]+)$') {
            $hex = $Matches[1]

            # Anything wider than 8 hex digits is not an etype value from any Windows
            # producer, and silently truncating it would fabricate a reading.
            if ($hex.Length -gt 8) {
                Write-Verbose "Hex value '$token' exceeds 32 bits and cannot be an encryption type"
                return $null
            }

            $unsigned = [Convert]::ToUInt32($hex, 16)
            return [BitConverter]::ToInt32([BitConverter]::GetBytes($unsigned), 0)
        }

        $parsed = 0
        if ([int]::TryParse($token, [ref]$parsed)) {
            return $parsed
        }

        # A [long]-ranged decimal reaches here only as the unsigned rendering of a negative
        # 32-bit value, which is exactly the 4294967295 sentinel written in decimal.
        $wideParsed = [long]0
        if ([long]::TryParse($token, [ref]$wideParsed) -and
            $wideParsed -ge 0 -and $wideParsed -le [uint32]::MaxValue) {
            return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$wideParsed), 0)
        }

        Write-Verbose "Value '$text' could not be parsed as a Kerberos encryption type"
        return $null
    }
}
