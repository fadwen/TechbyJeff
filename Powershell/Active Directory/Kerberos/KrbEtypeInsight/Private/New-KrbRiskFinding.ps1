#Requires -Version 7.6

function New-KrbRiskFinding {
    <#
    .SYNOPSIS
        Creates a single structured finding for inclusion in a risk assessment

    .DESCRIPTION
        Every conclusion the risk engine reaches is expressed as one of these objects rather
        than as a formatted string, for three reasons:

        - A finding carries the evidence that produced it. "This account will break" is an
          assertion; "this account will break, and here are the 412 service ticket requests
          in 30 days that were all RC4, and here are the 12 distinct clients that made them"
          is something the owning application team can act on or dispute. Assessments that
          cannot show their working do not survive contact with an application owner.

        - Severity is a property, not a prefix in a message, so a report can be filtered and
          sorted without parsing text.

        - The code is stable. An organisation running this quarterly needs to say
          "KRB002 is down from 40 accounts to 3", and that requires an identifier that does
          not change when the wording is improved.

        Severity means specifically:

        - Critical: hardening will break this, and there is direct evidence.
        - High:     hardening will probably break this, or it is already broken.
        - Medium:   a real weakness that hardening does not itself break.
        - Low:      worth knowing, no action required before the change.
        - Info:     context, including confirmation that something is already safe.

    .PARAMETER Code
        [System.String] (Mandatory, No Pipeline Support)

        Stable identifier, of the form KRB followed by three digits.

    .PARAMETER Severity
        [System.String] (Mandatory, No Pipeline Support)

        One of Critical, High, Medium, Low or Info.

    .PARAMETER Title
        [System.String] (Mandatory, No Pipeline Support)

        One-line statement of the finding.

    .PARAMETER Detail
        [System.String] (Mandatory, No Pipeline Support)

        Explanation of what was observed and what follows from it.

    .PARAMETER RecommendedAction
        [System.String] (Optional, No Pipeline Support)

        What to do about it. Findings that describe a safe state legitimately have none.

    .PARAMETER Evidence
        [System.Collections.Hashtable] (Optional, No Pipeline Support)

        The observations supporting the finding - counts, etype names, client lists, dates.

    .EXAMPLE
        PS> New-KrbRiskFinding -Code 'KRB002' -Severity 'Critical' `
                -Title 'Service account holds no AES key material' `
                -Detail 'Every observed ticket was RC4 and the KDC reported no AES key.' `
                -RecommendedAction 'Reset the password to derive AES keys before hardening.' `
                -Evidence @{ ObservedTickets = 412; AvailableKeys = @('RC4') }

        DESCRIPTION: Builds the finding for the most common hardening failure mode
        OUTPUT: A KrbEtypeInsight.Finding object
        USE CASE: Emitted by Get-KrbEtypeRisk when available-key evidence contradicts configuration

    .OUTPUTS
        KrbEtypeInsight.Finding

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Finding code reference: .\Troubleshooting\Common\Finding-Codes.md
    #>
    # Justification must be a single string literal - PSScriptAnalyzer rejects a concatenated
    # expression with "All the arguments of the Suppress Message Attribute should be string
    # constants", and does so as an analyzer error rather than as a finding on the file. It
    # therefore cannot be wrapped, so the reasoning lives here in the comment and the
    # attribute carries only a summary short enough to fit the line limit.
    #
    # Full reasoning: this constructs an in-memory object and changes no system state.
    # SupportsShouldProcess would make an object constructor prompt, and under -WhatIf it
    # would return nothing - silently emptying the Findings collection on every risk object,
    # and reporting a broken domain as clean.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Object constructor; changes no state. See comment above.')]
    [CmdletBinding()]
    [OutputType('KrbEtypeInsight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^KRB\d{3}$')]
        [string]$Code,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Detail,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RecommendedAction,

        [Parameter()]
        [hashtable]$Evidence = @{}
    )

    # Weights are deliberately spread so that no accumulation of Medium findings can reach
    # the score of a single Critical. A dozen accounts each with a stale password is a
    # housekeeping problem; one account with no AES key and 400 dependent requests is an
    # outage, and a scoring scheme that lets the first outrank the second inverts the
    # remediation order.
    $weight = switch ($Severity) {
        'Critical' { 40 }
        'High'     { 20 }
        'Medium'   { 10 }
        'Low'      { 4 }
        'Info'     { 0 }
    }

    [PSCustomObject]@{
        PSTypeName        = 'KrbEtypeInsight.Finding'
        Code              = $Code
        Severity          = $Severity
        Weight            = $weight
        Title             = $Title
        Detail            = $Detail

        # $null rather than the empty string an unbound [string] parameter defaults to.
        # Findings that describe a safe state legitimately have no action, and an empty
        # string renders in the JSON export as "RecommendedAction": "" - which reads as an
        # action that was meant to be filled in and was not.
        RecommendedAction = if ($RecommendedAction) { $RecommendedAction } else { $null }

        Evidence          = $Evidence
    }
}
