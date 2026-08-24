#Requires -Version 7.6

function Get-KrbProtocolCatalog {
    <#
    .SYNOPSIS
        Returns reference tables for Kerberos result codes, pre-authentication types and ticket options

    .DESCRIPTION
        Supplies the non-cipher lookup tables the event decoder needs:

        - KdcStatus: RFC 4120 result codes as written into the Status field of events 4768,
          4769 and 4771. The one this module cares most about is 0x0E,
          KDC_ERR_ETYPE_NOTSUPP, which is the exact error a client receives when it offers no
          encryption type the KDC will accept. After a hardening change, a rise in 4771 events
          carrying 0x0E is the breakage, observed directly.

        - PreAuthType: RFC 4120 and MS-KILE padata types from the PreAuthType field. Relevant
          here because type 0 - no pre-authentication - and type 2 - encrypted timestamp -
          have different exposure to etype removal from the PKINIT and FAST types.

        - TicketOption: KDC option bit flags from the TicketOptions field. Included so a
          report can distinguish a delegation or renewal request from an ordinary one when
          explaining why a particular principal appears more often than expected.

        Cached per session in the same manner as Get-KrbEtypeCatalog, and equally free of any
        AD or event-log dependency.

    .EXAMPLE
        PS> (Get-KrbProtocolCatalog).KdcStatus[0x0E]

        DESCRIPTION: Resolves the result code that indicates encryption type negotiation failure
        OUTPUT: A record naming KDC_ERR_ETYPE_NOTSUPP
        USE CASE: Detecting post-hardening breakage in 4771 events

    .OUTPUTS
        System.Collections.Hashtable

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Interpreting KDC result codes: .\Troubleshooting\Common\KDC-Status-Codes.md

    .LINK
        https://www.rfc-editor.org/rfc/rfc4120#section-7.5.9
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:KrbProtocolCatalog) {
        return $script:KrbProtocolCatalog
    }

    Write-Verbose 'Building Kerberos protocol catalog (first call this session)'

    # Row builders, so each entry stays inside the 115-character line limit. The alternative
    # is a table 200 characters wide that the quality gate rejects and that cannot be read in
    # a side-by-side diff.
    $status = {
        param([string]$Name, [string]$Description, [bool]$EtypeRelated = $false)
        @{ Name = $Name; Description = $Description; IsEtypeRelated = $EtypeRelated }
    }

    $padata = {
        param([string]$Name, [string]$Description)
        @{ Name = $Name; Description = $Description }
    }

    # IsEtypeRelated marks the codes that an encryption-type change can plausibly cause.
    # It is what lets a post-change report separate "these failures are our doing" from the
    # constant background of expired passwords and clock skew that every domain produces.
    $kdcStatus = @{
        0x00 = & $status 'KDC_ERR_NONE' 'No error - request succeeded'
        0x01 = & $status 'KDC_ERR_NAME_EXP' 'Client principal entry has expired'
        0x02 = & $status 'KDC_ERR_SERVICE_EXP' 'Server principal entry has expired'
        0x06 = & $status 'KDC_ERR_C_PRINCIPAL_UNKNOWN' 'Client principal not found in the database'
        0x07 = & $status 'KDC_ERR_S_PRINCIPAL_UNKNOWN' (
            'Service principal not found - usually a missing or duplicate SPN')
        0x08 = & $status 'KDC_ERR_PRINCIPAL_NOT_UNIQUE' (
            'Multiple principal entries match - duplicate SPN')

        # NULL_KEY is etype-related in a way that surprises people: it is what a KDC returns
        # when the account has no key of a usable type, which is exactly the state an account
        # reaches when it is set to AES-only but its password has not been changed since, so
        # no AES key was ever derived.
        0x09 = & $status 'KDC_ERR_NULL_KEY' (
            'Account has no key of a usable type - commonly an AES-only account whose ' +
            'password predates the change') $true

        0x0A = & $status 'KDC_ERR_CANNOT_POSTDATE' 'Ticket is not eligible for postdating'
        0x0C = & $status 'KDC_ERR_POLICY' (
            'Rejected by policy - logon hours, workstation restriction, or authentication policy')
        0x0D = & $status 'KDC_ERR_BADOPTION' (
            'Requested option is not honoured - often unconstrained delegation being refused')

        # The headline code for this module.
        0x0E = & $status 'KDC_ERR_ETYPE_NOTSUPP' (
            'KDC has no encryption type in common with the client - the direct signature ' +
            'of etype hardening breakage') $true

        0x0F = & $status 'KDC_ERR_SUMTYPE_NOSUPP' (
            'KDC has no checksum type in common with the client') $true
        0x10 = & $status 'KDC_ERR_PADATA_TYPE_NOSUPP' (
            'KDC does not support the pre-authentication type offered - seen when PKINIT ' +
            'or FAST is unavailable') $true
        0x11 = & $status 'KDC_ERR_TRTYPE_NOSUPP' 'KDC does not support the transited type'
        0x12 = & $status 'KDC_ERR_CLIENT_REVOKED' 'Account is disabled, locked out, or expired'
        0x13 = & $status 'KDC_ERR_SERVICE_REVOKED' 'Service account credentials have been revoked'
        0x17 = & $status 'KDC_ERR_KEY_EXPIRED' 'Password has expired'
        0x18 = & $status 'KDC_ERR_PREAUTH_FAILED' (
            'Pre-authentication failed - normally a wrong password')
        0x19 = & $status 'KDC_ERR_PREAUTH_REQUIRED' (
            'Additional pre-authentication required - a normal first-leg response, not a failure')
        0x1A = & $status 'KDC_ERR_SERVER_NOMATCH' 'KDC does not know about the requested server'
        0x1B = & $status 'KDC_ERR_MUST_USE_USER2USER' (
            'Server principal requires user-to-user Kerberos')
        0x1F = & $status 'KRB_AP_ERR_BAD_INTEGRITY' (
            'Integrity check on the decrypted field failed - can follow a key mismatch ' +
            'after an etype change') $true
        0x20 = & $status 'KRB_AP_ERR_TKT_EXPIRED' 'Ticket has expired'
        0x21 = & $status 'KRB_AP_ERR_TKT_NYV' 'Ticket is not yet valid'
        0x22 = & $status 'KRB_AP_ERR_REPEAT' 'Request is a replay'
        0x25 = & $status 'KRB_AP_ERR_SKEW' 'Clock skew between client and KDC is too great'
        0x29 = & $status 'KRB_AP_ERR_MODIFIED' (
            'Message stream modified - frequently a key mismatch, including one caused ' +
            'by an etype change') $true
        0x34 = & $status 'KRB_ERR_RESPONSE_TOO_BIG' (
            'Response too large for UDP - the client should retry over TCP')
        0x3C = & $status 'KRB_ERR_GENERIC' 'Generic error'
    }

    # The Status field does not only carry RFC 4120 Kerberos result codes. Windows also writes
    # NTSTATUS values into it, and nothing in the field distinguishes the two - they simply do
    # not collide, because Kerberos codes are small positive integers and NTSTATUS failure
    # values all begin 0xC0000000, which reads as a large negative int32.
    #
    # This was found by a live cross-forest lab. Four 4769 events carried 0xC000019B, the
    # catalog had no entry above 0x3C, and StatusName came back null - caught by the suite's
    # own assertion that every status from a real KDC must resolve to a name. Until a trust
    # existed in the domain, no status in this range had ever been produced.
    #
    # Keys are the signed int32 the converter yields, which is what PowerShell's own 8-digit
    # hex literals evaluate to, so 0xC000019B here and the decoded -1073741413 are the same key.
    $ntStatus = @{
        0xC0000064 = & $status 'STATUS_NO_SUCH_USER' 'The named user does not exist'
        0xC000006A = & $status 'STATUS_WRONG_PASSWORD' 'Incorrect password'
        0xC000006D = & $status 'STATUS_LOGON_FAILURE' 'Logon failure - bad user name or password'
        0xC000006E = & $status 'STATUS_ACCOUNT_RESTRICTION' (
            'Account restriction prevented logon - logon hours, workstation, or policy')
        0xC000006F = & $status 'STATUS_INVALID_LOGON_HOURS' 'Logon outside permitted hours'
        0xC0000070 = & $status 'STATUS_INVALID_WORKSTATION' 'Logon from a workstation not permitted'
        0xC0000071 = & $status 'STATUS_PASSWORD_EXPIRED' 'Password has expired'
        0xC0000072 = & $status 'STATUS_ACCOUNT_DISABLED' 'Account is disabled'
        0xC00000DC = & $status 'STATUS_INVALID_SERVER_STATE' (
            'Server is not in a valid state to service the request')
        0xC0000133 = & $status 'STATUS_TIME_DIFFERENCE_AT_DC' 'Clock skew between the client and the controller'
        0xC000018B = & $status 'STATUS_NO_TRUST_SAM_ACCOUNT' (
            'The trust account for this domain does not exist or is unusable')

        # Marked encryption-type related deliberately. A trust whose supported encryption
        # types do not intersect with the requesting realm's fails here, which is exactly the
        # cross-realm RC4 condition KRB014 exists to warn about - so this code needs to reach
        # the post-change failure view rather than being filtered out as background noise.
        0xC000019B = & $status 'STATUS_TRUSTED_DOMAIN_FAILURE' (
            'The trust relationship with the target domain failed - can follow a trust whose ' +
            'supported encryption types do not intersect with the requesting realm') $true

        0xC000019C = & $status 'STATUS_TRUSTED_RELATIONSHIP_FAILURE' (
            'The trust relationship between this workstation and the domain failed')
        0xC0000192 = & $status 'STATUS_NETLOGON_NOT_STARTED' 'The Netlogon service was not started'
        0xC0000193 = & $status 'STATUS_ACCOUNT_EXPIRED' 'Account has expired'
        0xC0000224 = & $status 'STATUS_PASSWORD_MUST_CHANGE' 'The password must be changed at next logon'
        0xC0000234 = & $status 'STATUS_ACCOUNT_LOCKED_OUT' 'Account is locked out'
    }

    foreach ($code in $ntStatus.Keys) { $kdcStatus[$code] = $ntStatus[$code] }

    $preAuthType = @{
        0   = & $padata 'None' (
            'No pre-authentication - the account has "Do not require Kerberos ' +
            'preauthentication" set, which is also the AS-REP roasting exposure')
        2   = & $padata 'PA-ENC-TIMESTAMP' (
            'Encrypted timestamp - the standard pre-authentication method, and the one ' +
            'whose encryption type this module tracks')
        11  = & $padata 'PA-ETYPE-INFO' 'Encryption type information supplied by the KDC'
        15  = & $padata 'PA-PK-AS-REP_OLD' 'Smart card logon, legacy PKINIT'
        16  = & $padata 'PA-PK-AS-REQ' 'Smart card logon, PKINIT request'
        17  = & $padata 'PA-PK-AS-REP' 'Smart card logon, PKINIT reply'
        19  = & $padata 'PA-ETYPE-INFO2' (
            'Encryption type information, version 2 - carries salt and s2kparams')
        20  = & $padata 'PA-SVR-REFERRAL-INFO' 'Cross-realm referral information'
        138 = & $padata 'PA-ENCRYPTED-CHALLENGE' 'FAST armoured pre-authentication'
    }

    # KDC option bits, as carried in the TicketOptions field. Only the ones worth naming in a
    # report are listed; the field is reported in full as hex regardless.
    $ticketOption = @{
        0x40000000 = 'Forwardable'
        0x20000000 = 'Forwarded'
        0x10000000 = 'Proxiable'
        0x08000000 = 'Proxy'
        0x04000000 = 'Allow-Postdate'
        0x02000000 = 'Postdated'
        0x00800000 = 'Renewable'
        0x00010000 = 'Canonicalize'
        0x00008000 = 'Request-Anonymous'
        0x00000010 = 'Renewable-OK'
        0x00000008 = 'Enc-Tkt-in-Skey'
        0x00000002 = 'Renew'
        0x00000001 = 'Validate'
    }

    $script:KrbProtocolCatalog = @{
        KdcStatus    = $kdcStatus
        PreAuthType  = $preAuthType
        TicketOption = $ticketOption

        # Descending order, precomputed. Sorting thirteen keys is trivial in isolation, but
        # the ticket options are decoded on every event, and a Sort-Object pipeline per event
        # is a measurable share of a multi-hundred-thousand-event collection.
        SortedTicketOptionKeys = [int[]]@($ticketOption.Keys | Sort-Object -Descending)
    }

    return $script:KrbProtocolCatalog
}
