function Get-CaControlSatisfiability {
    <#
    .SYNOPSIS
        Says whether the simulated sign-in could satisfy a given grant control, and why not when
        it could not

    .DESCRIPTION
        The What If API answers whether a policy applies, not whether the user gets in. Those
        differ whenever an applying policy demands something the simulated sign-in cannot
        produce, and that gap is where the most useful finding lives: a report-only policy
        requiring a compliant device applies to a non-compliant device just the same, and the
        API reports it as applying, which reads as a mild extra requirement when it is in fact
        a lockout.

        Every rule here comes from a documented Microsoft constraint rather than from
        inference, because the cost of being wrong is asymmetric. A missed lockout is a finding
        this module fails to make; an invented one is a finding that sends somebody to
        investigate a policy that is fine, and two of those teach the reader to ignore the
        field. So Unknown is the default and the common answer, and the caller must read it as
        "no evidence", never as "satisfiable".

        The rules, and the documentation each rests on:

        Legacy authentication clients - the Other clients and Exchange ActiveSync client app
        types - "don't support multifactor authentication (MFA) and don't pass device state
        information, so they're blocked by Conditional Access grant controls, like requiring
        MFA or compliant devices". Microsoft is explicit for Exchange ActiveSync that where
        "Multifactor authentication, Terms of use, or custom controls are required, affected
        users are blocked, because basic authentication doesn't support these controls". That
        one condition therefore decides most of the interesting controls at once, and it is the
        rule that fires most often in practice. easSupported is deliberately not included: it
        names EAS clients that do support modern authentication.

        Device code flow - "the required grant control for the managed device or a device state
        condition isn't supported. This is because the device that is performing authentication
        can't provide its device state to the device that is providing a code."

        Require approved client app - "Only supports the iOS and Android for device platform
        condition." That grant retired in March 2026 - Entra now refuses to create or
        update a policy using it, saying such policies "can only be disabled or deleted",
        which this was told directly when trying to build one. The rule stays because
        existing policies carrying the control still evaluate, so a tenant part-way
        through migrating to Require app protection policy still needs the answer.

        Require app protection policy - generally available for iOS and Android and in preview
        for Microsoft Edge on Windows, and macOS and Linux are documented as unsupported. So
        Windows is left Unknown rather than called a lockout.

        Require Microsoft Entra hybrid joined device - "Only supports domain-joined Windows
        down-level and Windows current devices."

        Require device to be marked as compliant - "Only supports Windows 10+, iOS, Android,
        macOS, and Linux Ubuntu devices."

        Require password change - "The user must complete multifactor authentication and then
        change their password", so anything that rules out MFA rules this out too.

        Authentication strengths get exactly one rule, and the rule deliberately does not look
        at the platform. It is tempting to say that a strength allowing only
        windowsHelloForBusiness cannot be satisfied on iOS, and that inference is wrong: the
        built-in combination is documented as "Windows Hello for Business or platform
        credential" and now covers macOS Platform SSO, so the combination name does not name a
        platform. No allowedCombinations value carries a documented platform restriction, so
        none is asserted here. What is safe is the degenerate case - a strength that allows no
        combination at all admits nobody.

        What deliberately stays Unknown: whether a user has registered a method, accepted terms
        of use, or is running an approved app on a platform that supports one. Nothing in the
        request describes any of it.

    .PARAMETER Control
        The control string from a grant requirement clause - a built-in control such as
        compliantDevice, or a prefixed one such as authenticationStrength:Passwordless MFA.

    .PARAMETER SignInCondition
        The signInConditions object that was sent to the evaluate endpoint.

    .PARAMETER ControlDetail
        The detail behind the control, where the control string is not the whole story. Only
        authentication strengths have one today, carrying their allowed combinations.

    .OUTPUTS
        PSCustomObject with Verdict - Satisfiable, Unsatisfiable or Unknown - and Reason, which
        is populated only for Unsatisfiable.

    .EXAMPLE
        Get-CaControlSatisfiability -Control 'mfa' -SignInCondition @{ clientAppType = 'other' }

        Returns Unsatisfiable, because a legacy authentication client cannot perform MFA.

    .EXAMPLE
        Get-CaControlSatisfiability -Control 'approvedApplication' `
            -SignInCondition @{ devicePlatform = 'windows' }

        Returns Unsatisfiable - the control only supports iOS and Android.

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.4.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Control,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$SignInCondition,

        [Parameter()]
        [AllowNull()]
        [object]$ControlDetail
    )

    # A scriptblock rather than a nested function, so that no local helper has to carry a verb.
    # Every verb that reads correctly here - New, Set - is one PSScriptAnalyzer treats as
    # state-changing and demands ShouldProcess for, which this decidedly is not.
    $verdict = {
        param([string]$Result, [string]$Because)
        [PSCustomObject]@{
            PSTypeName = 'CaOutcome.Satisfiability'
            Control    = $Control
            Verdict    = $Result
            Reason     = $Because
        }
    }

    if ($null -eq $SignInCondition) {
        return & $verdict 'Unknown'
    }

    $deviceInfo = Get-CaProperty -InputObject $SignInCondition -Name 'deviceInfo'
    $platform = [string](Get-CaProperty -InputObject $SignInCondition -Name 'devicePlatform')
    $clientApp = [string](Get-CaProperty -InputObject $SignInCondition -Name 'clientAppType')

    $authFlow = Get-CaProperty -InputObject $SignInCondition -Name 'authenticationFlow'
    $transferMethod = [string](Get-CaProperty -InputObject $authFlow -Name 'transferMethod')

    # 'all' and an absent value both mean "unconstrained", so no platform rule may fire on them
    $platformKnown = -not [string]::IsNullOrWhiteSpace($platform) -and $platform -ne 'all'

    # easSupported is excluded on purpose: it names the EAS clients that DO support modern
    # authentication, which is the whole point of the distinction
    $isLegacyClient = @('other', 'exchangeActiveSync') -contains $clientApp
    $isDeviceCodeFlow = $transferMethod -eq 'deviceCodeFlow'

    $legacyReason = 'a legacy authentication client cannot perform interactive authentication'
    $legacyDeviceReason = 'a legacy authentication client passes no device state'

    # Controls that need the user to do something interactively. Legacy clients cannot, and the
    # prefixed forms are matched by prefix because their suffix is a name or an id.
    $isInteractive = $Control -in @('mfa', 'passwordChange') -or
        $Control -like 'authenticationStrength:*' -or
        $Control -like 'termsOfUse:*' -or
        $Control -like 'customAuthenticationFactor:*'

    if ($isInteractive -and $isLegacyClient) {
        return & $verdict 'Unsatisfiable' $legacyReason
    }

    # A strength that allows no combination admits nobody. Deliberately the only rule here -
    # see the description for why the platform of a combination is not inferred.
    if ($Control -like 'authenticationStrength:*' -and $null -ne $ControlDetail) {
        $combinations = @(Get-CaProperty -InputObject $ControlDetail -Name 'AllowedCombinations')
        if ($combinations.Count -eq 0) {
            return & $verdict 'Unsatisfiable' `
                'the authentication strength allows no combination of methods'
        }
    }

    switch -Wildcard ($Control) {

        'compliantDevice' {
            if ($isLegacyClient) {
                return & $verdict 'Unsatisfiable' $legacyDeviceReason
            }
            if ($isDeviceCodeFlow) {
                return & $verdict 'Unsatisfiable' `
                    'device code flow cannot pass device state to the authenticating device'
            }
            if ($platformKnown -and @('windows', 'iOS', 'android', 'macOS', 'linux') -notcontains $platform) {
                return & $verdict 'Unsatisfiable' `
                    "device compliance is not supported on $platform"
            }

            $isCompliant = Get-CaProperty -InputObject $deviceInfo -Name 'isCompliant'
            if ($null -eq $isCompliant) { return & $verdict 'Unknown' }
            if ($isCompliant) { return & $verdict 'Satisfiable' }
            return & $verdict 'Unsatisfiable' 'the simulated device is not compliant'
        }

        'domainJoinedDevice' {
            if ($isLegacyClient) {
                return & $verdict 'Unsatisfiable' $legacyDeviceReason
            }
            if ($isDeviceCodeFlow) {
                return & $verdict 'Unsatisfiable' `
                    'device code flow cannot pass device state to the authenticating device'
            }
            if ($platformKnown -and $platform -ne 'windows') {
                return & $verdict 'Unsatisfiable' `
                    "hybrid join is a Windows-only control and this sign-in is $platform"
            }

            # serverAD is the hybrid join this control means; azureAD is Entra joined and does
            # not satisfy it
            $trustType = [string](Get-CaProperty -InputObject $deviceInfo -Name 'trustType')
            if ([string]::IsNullOrWhiteSpace($trustType)) { return & $verdict 'Unknown' }
            if ($trustType -eq 'serverAD') { return & $verdict 'Satisfiable' }
            return & $verdict 'Unsatisfiable' `
                "the simulated device is $trustType joined, not hybrid joined"
        }

        'approvedApplication' {
            if ($platformKnown -and @('iOS', 'android') -notcontains $platform) {
                return & $verdict 'Unsatisfiable' `
                    "approved client app supports only iOS and Android, not $platform"
            }
            return & $verdict 'Unknown'
        }

        'compliantApplication' {
            # Windows is left Unknown rather than called a lockout: app protection policy is in
            # preview there for Microsoft Edge, and nothing in the request names the browser
            if ($platformKnown -and @('macOS', 'linux', 'windowsPhone') -contains $platform) {
                return & $verdict 'Unsatisfiable' `
                    "app protection policy is not supported on $platform"
            }
            return & $verdict 'Unknown'
        }
    }

    return & $verdict 'Unknown'
}