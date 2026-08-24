#Requires -Version 7.6

function New-KrbRiskObject {
    <#
    .SYNOPSIS
        Constructs a KrbEtypeInsight.Risk object with the complete, uniform property set

    .DESCRIPTION
        The single place a risk object is built. Get-KrbEtypeRisk emits from three code paths
        - observed principals, principals whose configuration is dangerous but which produced
        no events, and trusts - and before this function existed each path assembled its own
        literal. They drifted, as parallel literals do.

        The consequence was not a missing value in a rarely-read field. The format file
        computes the NoAES column as @($_.ClientsWithoutAesSupport).Count, and in PowerShell
        @($null).Count is 1, not 0. A trust row that simply omitted the property therefore
        rendered as though one AES-incapable client depended on it. The number was invented by
        the absence of a property, which is the kind of defect that survives review because
        every individual line is correct.

        Every property is declared here with a default, so a caller that does not supply one
        gets an explicit empty collection rather than a missing member. That distinction is
        what makes @() count as zero and keeps every consumer - the format file, the CSV
        exporter, the HTML renderer and anyone piping to Select-Object - reading the same
        schema regardless of which path produced the row.

    .PARAMETER PrincipalName
        [System.String] (Mandatory, No Pipeline Support)

        The key the assessment is reported against: an account name, an unresolved service
        name, or a trust name.

    .PARAMETER Finding
        [System.Object[]] (Mandatory, No Pipeline Support)

        The findings for this principal, from New-KrbRiskFinding.

    .PARAMETER Summary
        [System.Object] (Mandatory, No Pipeline Support)

        The level and score, from Measure-KrbRiskLevel.

    .PARAMETER Role
        [System.String[]] (Optional, No Pipeline Support)

        Which roles the principal was observed in: Service, Client, Unobserved or Trust.

    .PARAMETER Observation
        [System.Object] (Optional, No Pipeline Support)

        The accumulated per-principal observation record, when there is one. Supplies request
        counts, observed encryption types, client lists and first and last seen.

    .PARAMETER Principal
        [System.Object] (Optional, No Pipeline Support)

        The matching directory object from Get-KrbPrincipalEtype, when one was resolved.

    .PARAMETER TargetEncryptionTypes
        [System.Object] (Optional, No Pipeline Support)

        The decoded target configuration the assessment was made against.

    .PARAMETER ConfiguredEncryptionTypes
        [System.Object] (Optional, No Pipeline Support)

        Decoded configuration for the principal. Supplied directly for trusts, which have no
        directory principal object.

    .PARAMETER ClientsWithoutAesSupport
        [System.String[]] (Optional, No Pipeline Support)

        Clients confirmed incapable of AES. Defaults to an empty array, never to null.

    .PARAMETER ClientsWithUnknownSupport
        [System.String[]] (Optional, No Pipeline Support)

        Clients whose capability could not be established.

    .PARAMETER ConfidenceNote
        [System.String[]] (Optional, No Pipeline Support)

        What was not measurable, and why.

    .PARAMETER BreakingCode
        [System.String[]] (Optional, No Pipeline Support)

        Finding codes that mean the change breaks this principal, as opposed to merely noting
        a weakness in it. WillBreakOnHardening is set from the intersection of these and the
        finding codes actually present.

    .PARAMETER CorrelationId
        [System.String] (Optional, No Pipeline Support)

        Correlation identifier for the assessment run.

    .EXAMPLE
        PS> New-KrbRiskObject -PrincipalName 'svc-payroll' -Finding $findings -Summary $summary `
                -Role 'Service' -Observation $obs -TargetEncryptionTypes $target

        DESCRIPTION: Builds the risk object for an observed service
        OUTPUT: A KrbEtypeInsight.Risk object with the full property set
        USE CASE: Called by Get-KrbEtypeRisk for every emitted row

    .OUTPUTS
        KrbEtypeInsight.Risk

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Report output: .\Troubleshooting\Common\Report-Output.md
    #>
    # Constructs an in-memory object and changes no system state. The Justification on a
    # SuppressMessageAttribute must be a single unwrappable literal, so it carries a summary.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Object constructor; changes no state.')]
    [CmdletBinding()]
    [OutputType('KrbEtypeInsight.Risk')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PrincipalName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Finding,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Summary,

        [Parameter()]
        [string[]]$Role = @(),

        [Parameter()]
        [object]$Observation,

        [Parameter()]
        [object]$Principal,

        [Parameter()]
        [object]$TargetEncryptionTypes,

        [Parameter()]
        [object]$ConfiguredEncryptionTypes,

        [Parameter()]
        [string[]]$ClientsWithoutAesSupport = @(),

        [Parameter()]
        [string[]]$ClientsWithUnknownSupport = @(),

        [Parameter()]
        [string[]]$ConfidenceNote = @(),

        [Parameter()]
        [string[]]$BreakingCode = @('KRB001', 'KRB002', 'KRB004', 'KRB005', 'KRB007', 'KRB011'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId
    )

    $codes = @($Finding.Code)
    $obs = $Observation

    # Every collection is built by direct assignment, never by an if/else expression.
    #
    # This is not a style preference. In PowerShell an if used as an expression takes its
    # value from the pipeline, and @() writes nothing to the pipeline - so
    #
    #     $x = if ($cond) { @(1) } else { @() }
    #
    # assigns $null on the else branch, not an empty array. Written that way this constructor
    # reintroduced the exact defect it was created to fix: rows built without an observation
    # got $null for Clients, ServiceNames and the observed-etype collections, and every
    # consumer that counts them saw @($null).Count, which is 1. Direct assignment of @() to a
    # variable does produce an empty array, so the collections are established first and the
    # object literal only reads them.
    $serviceNames = @()
    if ($obs) { $serviceNames = @($obs.ServiceNames) }
    elseif ($Principal) { $serviceNames = @($Principal.ServicePrincipalNames) }

    $observedTicketEtypes = @()
    $observedSessionKeyEtypes = @()
    $observedPreAuthEtypes = @()
    $clients = @()
    $clientAddresses = @()
    $sources = @()

    if ($obs) {
        $observedTicketEtypes = @($obs.TicketEtypes | Sort-Object)
        $observedSessionKeyEtypes = @($obs.SessionKeyEtypes | Sort-Object)
        $observedPreAuthEtypes = @($obs.PreAuthEtypes | Sort-Object)
        $clients = @($obs.Clients)
        $clientAddresses = @($obs.ClientAddresses)
        $sources = @($obs.Sources)
    }

    # Ticket etypes are decoded to names here rather than at each call site, so the two
    # representations cannot disagree about which etypes a row observed.
    $observedNames = @(
        foreach ($etype in $observedTicketEtypes) {
            (ConvertFrom-KrbEtype -TicketEtype $etype).DisplayName
        }
    )

    # Scalars are safe in an if/else because a scalar branch does write to the pipeline.
    $availableKeys = $null
    if ($obs -and $obs.AvailableKeysKnown) { $availableKeys = @($obs.AvailableKeys) }

    $configured = $null
    if ($ConfiguredEncryptionTypes) { $configured = $ConfiguredEncryptionTypes }
    elseif ($Principal) { $configured = $Principal.EncryptionTypes }

    [PSCustomObject]@{
        PSTypeName        = 'KrbEtypeInsight.Risk'

        PrincipalName     = $PrincipalName
        Roles             = @($Role)
        SamAccountName    = if ($Principal) { $Principal.SamAccountName } else { $null }
        DistinguishedName = if ($Principal) { $Principal.DistinguishedName } else { $null }
        ObjectClass       = if ($Principal) { $Principal.ObjectClass } else { $null }
        Enabled           = if ($Principal) { $Principal.Enabled } else { $null }
        ResolvedInDirectory = [bool]$Principal

        RiskLevel         = $Summary.Level
        RiskScore         = $Summary.Score
        Findings          = @($Finding)
        FindingCodes      = $codes

        # True when at least one finding says the change breaks this principal, as opposed to
        # merely noting a weakness in it.
        WillBreakOnHardening = @($codes | Where-Object { $_ -in $BreakingCode }).Count -gt 0

        ServiceNames      = $serviceNames

        RequestCount      = if ($obs) { $obs.RequestCount } else { 0 }
        FailureCount      = if ($obs) { $obs.FailureCount } else { 0 }
        FirstSeen         = if ($obs) { $obs.FirstSeen } else { $null }
        LastSeen          = if ($obs) { $obs.LastSeen } else { $null }

        ObservedTicketEtypes     = $observedTicketEtypes
        ObservedTicketEtypeNames = $observedNames
        ObservedSessionKeyEtypes = $observedSessionKeyEtypes
        ObservedPreAuthEtypes    = $observedPreAuthEtypes

        # Null rather than @() when unknown: an empty key list means the principal holds no
        # keys at all, which is a finding, and must stay distinguishable from not having been
        # told. This is the one collection on the object where null is meaningful.
        AvailableKeys     = $availableKeys

        ConfiguredEncryptionTypes = $configured
        TargetEncryptionTypes = $TargetEncryptionTypes

        ClientCount       = if ($obs) { $obs.Clients.Count } else { 0 }
        Clients           = $clients
        ClientAddresses   = $clientAddresses
        ClientsWithoutAesSupport  = @($ClientsWithoutAesSupport)
        ClientsWithUnknownSupport = @($ClientsWithUnknownSupport)

        EventSchemaVersion2 = if ($obs) { $obs.SawV2 } else { $false }
        ConfidenceNotes   = @($ConfidenceNote)
        Sources           = $sources

        AssessedAt        = Get-Date
        CorrelationId     = $CorrelationId
    }
}
