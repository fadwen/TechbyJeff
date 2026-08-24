#Requires -Version 7.6

function Get-KrbPrincipalEtype {
    <#
    .SYNOPSIS
        Reads the configured Kerberos encryption type posture of Active Directory principals

    .DESCRIPTION
        Returns, for each account, everything in the directory that determines which
        encryption types the KDC will use for it - decoded, and with the interactions between
        attributes made explicit.

        Four attributes decide the answer, and reading any one of them alone gives a wrong
        result:

        - msDS-SupportedEncryptionTypes is the primary control. Unset and zero both mean
          "use the domain default", which is not the same as "supports nothing" and not the
          same as "supports RC4 only".

        - userAccountControl carries USE_DES_KEY_ONLY, which overrides the encryption-type
          attribute entirely, and the delegation bits, which determine how far a failure
          propagates.

        - pwdLastSet decides which key material actually exists. Kerberos keys are derived
          when the password is set, so an account whose password has not changed since the
          domain supported AES has no AES key regardless of what its attributes claim.
          Setting such an account to AES-only does not harden it, it breaks it - the KDC has
          nothing to encrypt with and returns KDC_ERR_NULL_KEY.

        - servicePrincipalName decides whether the account is a service at all, and therefore
          whether it appears in 4769 events as a target rather than only as a requester.

        Business value: this is the configuration half of the assessment. Combined with the
        observational half from Get-KrbEvent, it produces the statement that matters - not
        "this account is configured for RC4" but "this account is configured for RC4, has
        never presented anything else, holds no AES key, and twelve clients depend on it".

    .PARAMETER Identity
        [System.String[]] (Mandatory in the Identity set, Pipeline: ByValue and ByPropertyName)

        Accounts to read, by sAMAccountName, distinguished name, SID or GUID.

    .PARAMETER ServicePrincipalName
        [System.String[]] (Mandatory in the ServicePrincipalName set, Pipeline: ByValue and ByPropertyName)

        Service principal names to resolve back to their owning accounts. This is how a
        service name taken from a 4769 event becomes an account whose configuration can be
        read.

        For bulk work, prefer -All and index the results locally. Resolving several thousand
        SPNs one directory query at a time is the slowest thing this module can be asked to
        do; one enumeration and an in-memory index is what Get-KrbEtypeRisk does instead.

    .PARAMETER All
        [System.Management.Automation.SwitchParameter] (Mandatory in the All set, No Pipeline Support)

        Enumerate every user and computer account in the domain.

    .PARAMETER ServiceAccountOnly
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Restrict an -All enumeration to accounts that have at least one service principal
        name. These are the accounts whose encryption types appear in service ticket requests
        and therefore the ones a hardening change can break for other people.

    .PARAMETER IncludeDisabled
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Include disabled accounts in an -All enumeration. Excluded by default: a disabled
        account cannot authenticate, so counting it as a risk inflates the report without
        adding a single action.

    .PARAMETER DomainDefaultEncryptionTypes
        [System.Int32] (Optional, No Pipeline Support)

        The bitmask applied when msDS-SupportedEncryptionTypes is unset or zero. Defaults to
        the Windows default of 0x27. Pass the real value from Get-KrbDomainEtypeContext when
        the domain controllers have DefaultDomainSupportedEncTypes configured, otherwise
        every account inheriting the default is described against the wrong baseline.

    .PARAMETER Server
        [System.String] (Optional, No Pipeline Support)

        Domain controller to query. Defaults to whichever the ActiveDirectory module selects.

    .PARAMETER Credential
        [System.Management.Automation.PSCredential] (Optional, No Pipeline Support)

        Credentials for the directory query. Read access to the listed attributes is
        sufficient; no write permission is required or requested.

    .EXAMPLE
        PS> Get-KrbPrincipalEtype -Identity 'svc-legacyapp'

        DESCRIPTION: Reads one service account's complete encryption type posture
        OUTPUT: Decoded supported types, account control flags, password age, and SPNs
        USE CASE: Investigating a single account before changing it

    .EXAMPLE
        PS> Get-KrbPrincipalEtype -All -ServiceAccountOnly |
                Where-Object { $_.EncryptionTypes.SupportsRc4 -and -not $_.EncryptionTypes.SupportsAes }

        DESCRIPTION: Finds every service account that can only use RC4
        OUTPUT: The accounts an RC4 removal will definitely affect
        USE CASE: Scoping a hardening project
        DURATION: Under a minute in a domain of a few thousand accounts

    .EXAMPLE
        PS> Get-KrbPrincipalEtype -All | Where-Object { $_.AccountControl.UseDesKeyOnly }

        DESCRIPTION: Finds accounts pinned to single DES by userAccountControl
        OUTPUT: Accounts whose encryption-type attribute the KDC is ignoring
        USE CASE: Catching the accounts an attribute-only assessment reports as healthy

    .EXAMPLE
        PS> Get-KrbEvent -EventId 4769 -MaxEvents 20000 |
                Select-Object -ExpandProperty ServiceName -Unique |
                Get-KrbPrincipalEtype -ServicePrincipalName -ErrorAction SilentlyContinue

        DESCRIPTION: Resolves the services actually observed in the log back to their accounts
        OUTPUT: Configuration for exactly the accounts that are in use
        USE CASE: Assessing what is live rather than what merely exists in the directory

    .INPUTS
        System.String. Accepts identities or service principal names from the pipeline.

    .OUTPUTS
        KrbEtypeInsight.Principal

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        Requires the ActiveDirectory module. Read-only throughout - this function never
        modifies a directory object.

        Group managed service accounts are returned like any other account. Their passwords
        are rotated by the KDC every 30 days by default, so they are among the few account
        types whose key material can be assumed current.

        TROUBLESHOOTING:
        - SPN resolution failures: .\Troubleshooting\Common\SPN-Resolution.md
        - Accounts with no AES key: .\Troubleshooting\Common\Missing-AES-Keys.md
        - Query performance: .\Troubleshooting\Performance\Directory-Queries.md

    .LINK
        https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-kile/6cfc7b50-11ed-4b4d-846d-6f08f0812919
    #>
    # Two false positives from PSReviewUnusedParameter, suppressed with the reasoning here
    # because a SuppressMessageAttribute Justification must be a single unwrappable literal.
    #
    # -All is a parameter set discriminator. It is never read by name because the switch on
    # $PSCmdlet.ParameterSetName is what consumes it; removing it would remove the only way
    # to select the enumeration set.
    #
    # -DomainDefaultEncryptionTypes is used inside the $newPrincipal script block, which the
    # analyzer does not follow into. Removing it would silently judge every account with an
    # unset encryption type attribute against the wrong baseline.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All',
        Justification = 'Parameter set discriminator. See comment above.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DomainDefaultEncryptionTypes',
        Justification = 'Used in the newPrincipal script block. See comment above.')]
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType('KrbEtypeInsight.Principal')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Identity')]
        [ValidateNotNullOrEmpty()]
        [Alias('SamAccountName', 'DistinguishedName')]
        [string[]]$Identity,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName,
            ParameterSetName = 'ServicePrincipalName')]
        [ValidateNotNullOrEmpty()]
        [Alias('ServiceName', 'Spn')]
        [string[]]$ServicePrincipalName,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(ParameterSetName = 'All')]
        [switch]$ServiceAccountOnly,

        [Parameter(ParameterSetName = 'All')]
        [switch]$IncludeDisabled,

        [Parameter()]
        [int]$DomainDefaultEncryptionTypes = 0x27,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        if (-not (Get-Module -Name ActiveDirectory)) {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
            }
            catch {
                Write-Error ('The ActiveDirectory module is required and could not be loaded. ' +
                    "Install RSAT or run from a domain controller. Error: $($_.Exception.Message)") `
                    -ErrorAction Stop
                return
            }
        }

        # The full property set every path needs. Named explicitly rather than using
        # -Properties * because the wildcard pulls constructed and back-linked attributes
        # that cost the directory real work - memberOf and tokenGroups among them - for data
        # this function never reads.
        $properties = @(
            # sAMAccountName is NOT one of Get-ADObject's default properties - that set is
            # DistinguishedName, Name, ObjectClass and ObjectGUID only. Omitting it here
            # produces principal objects whose SamAccountName is silently empty, which then
            # becomes an empty key in the risk engine's account index and quietly loses the
            # correlation between events and directory configuration for every account.
            'sAMAccountName'
            'msDS-SupportedEncryptionTypes'
            'userAccountControl'
            'servicePrincipalName'
            'pwdLastSet'
            'whenCreated'
            'lastLogonTimestamp'
            'displayName'
            'description'
            'objectClass'
            'objectSid'
        )

        $adArgs = @{ ErrorAction = 'Stop' }
        if ($Server) { $adArgs['Server'] = $Server }
        if ($Credential) { $adArgs['Credential'] = $Credential }

        $now = Get-Date

        # Local function so the three parameter sets share one construction. Anything that
        # produces a Principal object goes through here, which is what keeps the output
        # schema identical no matter how the account was found.
        $newPrincipal = {
            param($adObject)

            $rawEtypes = $adObject.'msDS-SupportedEncryptionTypes'
            $spns = @($adObject.'servicePrincipalName')

            # pwdLastSet arrives as a FILETIME integer from Get-ADObject and as a DateTime
            # from Get-ADUser. Both shapes reach this function, so both are handled - a
            # missing conversion here silently produces a null password age, which reads in
            # the report as "age unknown" on precisely the accounts whose age matters most.
            $passwordLastSet = $null
            $raw = $adObject.'pwdLastSet'
            if ($raw -is [datetime]) {
                $passwordLastSet = $raw
            }
            elseif ($raw -and $raw -gt 0) {
                $passwordLastSet = [datetime]::FromFileTime([long]$raw)
            }

            $lastLogon = $null
            $rawLogon = $adObject.'lastLogonTimestamp'
            if ($rawLogon -is [datetime]) { $lastLogon = $rawLogon }
            elseif ($rawLogon -and $rawLogon -gt 0) { $lastLogon = [datetime]::FromFileTime([long]$rawLogon) }

            $control = ConvertFrom-KrbAccountControl -UserAccountControl $adObject.'userAccountControl'

            $etypes = ConvertFrom-KrbEtype -SupportedEncryptionTypes $rawEtypes `
                -DomainDefaultEncryptionTypes $DomainDefaultEncryptionTypes

            # objectClass is multi-valued and ordered least to most specific, so the last
            # entry is the one that names what the object actually is. Taking the first
            # returns 'top' for every object in the directory.
            $classes = @($adObject.objectClass)
            $objectClass = if ($classes) { $classes[-1] } else { $null }

            [PSCustomObject]@{
                PSTypeName        = 'KrbEtypeInsight.Principal'

                SamAccountName    = $adObject.SamAccountName
                DistinguishedName = $adObject.DistinguishedName
                Sid               = if ($adObject.objectSid) { $adObject.objectSid.Value } else { $null }
                ObjectClass       = $objectClass
                DisplayName       = $adObject.displayName
                Description       = $adObject.description

                # Enabled is derived from the account control bit rather than the ADAccount
                # Enabled property, because Get-ADObject does not supply that property and
                # this function must return the same schema whichever cmdlet found the object.
                Enabled           = if ($null -ne $control.Disabled) { -not $control.Disabled } else { $null }

                SupportedEncryptionTypesRaw = $rawEtypes
                EncryptionTypes   = $etypes
                AccountControl    = $control

                ServicePrincipalNames = $spns
                HasSpn            = ($spns.Count -gt 0)

                PasswordLastSet   = $passwordLastSet
                PasswordAgeDays   = if ($passwordLastSet) {
                    [int]($now - $passwordLastSet).TotalDays
                } else { $null }
                WhenCreated       = $adObject.whenCreated
                LastLogonTimestamp = $lastLogon

                # krbtgt is called out because its encryption types govern TGT issuance for
                # the entire domain. It is never a per-account finding and must never be
                # treated as one, but a report that omits it entirely has skipped the single
                # most consequential object in the assessment.
                IsKrbtgt          = ($adObject.SamAccountName -eq 'krbtgt' -or
                                     $adObject.SamAccountName -like 'krbtgt_*')

                CorrelationId     = $correlationId
            }
        }
    }

    process {
        try {
            switch ($PSCmdlet.ParameterSetName) {

                'Identity' {
                    foreach ($id in $Identity) {
                        if (-not $id.Trim()) {
                            Write-Error 'Identity cannot be empty or whitespace'
                            continue
                        }

                        try {
                            $found = Get-ADObject -Identity $id.Trim() -Properties $properties @adArgs
                        }
                        catch {
                            # Get-ADObject -Identity only accepts a DN or GUID. A
                            # sAMAccountName is the form an administrator actually has to
                            # hand, so fall back to a search rather than making the caller
                            # know the difference.
                            $escaped = ConvertTo-KrbLdapFilterValue -Value $id.Trim()
                            $found = @(Get-ADObject -LDAPFilter "(sAMAccountName=$escaped)" `
                                    -Properties $properties @adArgs)

                            if (-not $found) {
                                Write-Error "No account found matching identity '$id'"
                                continue
                            }
                        }

                        foreach ($item in @($found)) { & $newPrincipal $item }
                    }
                }

                'ServicePrincipalName' {
                    foreach ($spn in $ServicePrincipalName) {
                        if (-not $spn.Trim()) {
                            Write-Error 'ServicePrincipalName cannot be empty or whitespace'
                            continue
                        }

                        $escaped = ConvertTo-KrbLdapFilterValue -Value $spn.Trim()
                        $found = @(Get-ADObject -LDAPFilter "(servicePrincipalName=$escaped)" `
                                -Properties $properties @adArgs)

                        if (-not $found) {
                            # A 4769 ServiceName is frequently a bare account name rather
                            # than a full SPN - that is how the KDC writes it when the
                            # request named the account directly - so retry as one before
                            # giving up.
                            $found = @(Get-ADObject -LDAPFilter "(sAMAccountName=$escaped)" `
                                    -Properties $properties @adArgs)
                        }

                        if (-not $found) {
                            Write-Error ("No account owns service principal name '$spn'. An SPN in " +
                                'the event log with no owner in the directory usually means the ' +
                                'account was deleted or the SPN was moved.')
                            continue
                        }

                        if ($found.Count -gt 1) {
                            # Duplicate SPNs are a real and damaging misconfiguration: the KDC
                            # returns KDC_ERR_PRINCIPAL_NOT_UNIQUE and the service fails for
                            # everyone. Worth surfacing here even though it is not an
                            # encryption-type problem, because an assessment is when it gets found.
                            Write-Warning ("Service principal name '$spn' is registered on " +
                                "$($found.Count) accounts, which will cause authentication failures " +
                                'independently of any encryption type change.')
                        }

                        foreach ($item in $found) { & $newPrincipal $item }
                    }
                }

                'All' {
                    $clauses = [System.Collections.Generic.List[string]]::new()
                    $clauses.Add('(|(objectCategory=person)(objectCategory=computer))')

                    if ($ServiceAccountOnly) { $clauses.Add('(servicePrincipalName=*)') }

                    # userAccountControl:1.2.840.113556.1.4.803: is the LDAP_MATCHING_RULE_BIT_AND
                    # operator. Filtering disabled accounts server-side keeps a large domain's
                    # tombstoned service accounts out of the result set entirely rather than
                    # transferring them to be discarded locally.
                    if (-not $IncludeDisabled) {
                        $clauses.Add('(!(userAccountControl:1.2.840.113556.1.4.803:=2))')
                    }

                    $ldapFilter = '(&' + ($clauses -join '') + ')'
                    Write-Verbose "Enumerating principals with filter: $ldapFilter"

                    $found = Get-ADObject -LDAPFilter $ldapFilter -Properties $properties @adArgs

                    $count = 0
                    foreach ($item in $found) {
                        $count++
                        if ($count % 500 -eq 0) {
                            Write-Progress -Activity 'Reading principal encryption types' `
                                -Status "$count accounts processed"
                        }
                        & $newPrincipal $item
                    }

                    Write-Progress -Activity 'Reading principal encryption types' -Completed
                    Write-Verbose "Enumerated $count principal(s)"
                }
            }
        }
        catch {
            $errorDetails = @{
                CorrelationId = $correlationId
                Function      = $MyInvocation.MyCommand.Name
                ErrorMessage  = $_.Exception.Message
                Line          = $_.InvocationInfo.ScriptLineNumber
                ParameterSet  = $PSCmdlet.ParameterSetName
            }
            Write-Verbose ('Directory query failure detail: ' + ($errorDetails | ConvertTo-Json -Compress))
            Write-Error "Directory query failed: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"
    }
}
