#Requires -Version 7.6

function ConvertFrom-KrbAccountControl {
    <#
    .SYNOPSIS
        Extracts the userAccountControl flags that affect Kerberos encryption type selection

    .DESCRIPTION
        userAccountControl carries several bits that change how the KDC treats an account's
        encryption types, and they are not visible in msDS-SupportedEncryptionTypes at all.
        An assessment that reads only the encryption-type attribute will misjudge every
        account that has one of these set.

        The four that matter here:

        - USE_DES_KEY_ONLY (0x200000). Overrides the encryption-type attribute entirely and
          confines the account to single DES. Windows Server 2008 R2 and later refuse DES by
          default, so an account carrying this bit is usually already broken or is being kept
          alive by a domain-wide DES allowance that hardening will remove. Clearing the bit
          is not sufficient on its own - the password must also be reset, because no AES key
          was ever derived.

        - NOT_DELEGATED, TRUSTED_FOR_DELEGATION and TRUSTED_TO_AUTH_FOR_DELEGATION. A
          delegation-enabled account fans an encryption-type failure out across every backend
          it reaches, so its blast radius is larger than its own client count suggests.

        - DONT_REQUIRE_PREAUTH (0x400000). Pre-authentication is where the client's chosen
          encryption type is exercised, so an account that skips it produces no
          PreAuthEncryptionType evidence and has to be assessed from service tickets alone.

        - ACCOUNTDISABLE (0x2). A disabled account cannot break anything, and including
          disabled accounts in a risk count is the fastest way to make a report look alarming
          and be ignored.

    .PARAMETER UserAccountControl
        [System.Object] (Mandatory, Pipeline: ByValue)

        The raw userAccountControl value.

    .EXAMPLE
        PS> ConvertFrom-KrbAccountControl -UserAccountControl 2097664

        DESCRIPTION: Decodes an account with USE_DES_KEY_ONLY set
        OUTPUT: UseDesKeyOnly true, alongside the other Kerberos-relevant flags
        USE CASE: Explaining why an account's encryption-type attribute is being ignored by the KDC

    .OUTPUTS
        KrbEtypeInsight.AccountControl

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - DES-only accounts: .\Troubleshooting\Common\DES-Only-Accounts.md

    .LINK
        MS-ADTS 2.2.16, userAccountControl bit values
        https://learn.microsoft.com/openspecs/windows_protocols/ms-adts/1446ae76-b9d5-4d4c-bf7f-1c7e26f47d9e
    #>
    [CmdletBinding()]
    [OutputType('KrbEtypeInsight.AccountControl')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$UserAccountControl
    )

    process {
        $uac = ConvertTo-KrbInt32 -Value $UserAccountControl

        if ($null -eq $uac) {
            # Absent means not read, not zero. Every flag comes back null so that a caller
            # cannot conclude "delegation is not enabled" from an attribute it never asked for.
            return [PSCustomObject]@{
                PSTypeName                = 'KrbEtypeInsight.AccountControl'
                Value                     = $null
                Disabled                  = $null
                UseDesKeyOnly             = $null
                DontRequirePreAuth        = $null
                TrustedForDelegation      = $null
                TrustedToAuthForDelegation = $null
                NotDelegated              = $null
                PasswordNeverExpires      = $null
                IsWorkstationTrust        = $null
                IsServerTrust             = $null
                IsInterdomainTrust        = $null
            }
        }

        [PSCustomObject]@{
            PSTypeName                 = 'KrbEtypeInsight.AccountControl'
            Value                      = $uac
            Disabled                   = [bool]($uac -band 0x0000002)
            UseDesKeyOnly              = [bool]($uac -band 0x0200000)
            DontRequirePreAuth         = [bool]($uac -band 0x0400000)
            TrustedForDelegation       = [bool]($uac -band 0x0080000)
            TrustedToAuthForDelegation = [bool]($uac -band 0x1000000)
            NotDelegated               = [bool]($uac -band 0x0100000)
            PasswordNeverExpires       = [bool]($uac -band 0x0010000)
            IsWorkstationTrust         = [bool]($uac -band 0x0001000)
            IsServerTrust              = [bool]($uac -band 0x0002000)
            IsInterdomainTrust         = [bool]($uac -band 0x0000800)
        }
    }
}
