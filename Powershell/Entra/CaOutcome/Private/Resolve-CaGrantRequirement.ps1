function Resolve-CaGrantRequirement {
    <#
    .SYNOPSIS
        Turns one policy's grantControls into a requirement clause

    .DESCRIPTION
        A policy's grant controls are a clause, not a list: the operator says whether the user
        must satisfy all of the controls or any one of them. Flattening that to a bare list of
        strings is the mistake that makes every naive What If summary wrong, because
        "MFA or compliant device" and "MFA and compliant device" collapse to the same thing.
        The clause is kept intact here and only reduced later, where the reduction can be
        explained.

        Four kinds of control live in different properties of the same object and all four
        count towards the clause:

        - builtInControls, the familiar mfa, compliantDevice, domainJoinedDevice, block
        - authenticationStrength, an object rather than a string, which is how a modern MFA
          policy expresses itself - the tenant this was built against has a policy whose
          builtInControls array is empty and whose only requirement is a Passwordless MFA
          strength, so treating an empty builtInControls as "no requirement" would report that
          policy as toothless
        - termsOfUse, a list of agreement ids
        - customAuthenticationFactors, a list of factor ids

        Controls are rendered as strings so that two worlds can be compared by value. The
        prefixed forms - authenticationStrength:, termsOfUse:, customAuthenticationFactor: -
        keep them from colliding with a built-in control of the same name.

        A string is not enough for an authentication strength, though, and ControlDetail exists
        for that. A custom strength is editable, and editing one silently changes what every
        policy referencing it requires: add "password plus something the user has" to a custom
        phishing-resistant strength and every policy using it weakens at once, without
        anyone editing a policy, and the requirement still names the same strength.
        Comparing display names would see nothing.

        Graph does inline the strength object inside each referencing policy, so a policy
        export is not byte-identical afterwards - it shows N policies whose embedded blob
        moved, rather than one strength weakened and who it reaches.

        So the allowed combinations travel with the control, which is what lets a baseline
        notice.

        combinationConfigurations are counted rather than expanded. They carry the FIDO2 AAGUID
        allowlists and the certificate issuer and policy OID restrictions, which also change
        what satisfies the strength without touching a policy - so their presence has to be
        visible, but reproducing their contents here would put a second copy of somebody else's
        schema in this module.

        Block is reported separately rather than as a control, because block is not something a
        user can satisfy. A policy carrying block ends the evaluation.

    .PARAMETER Policy
        A single whatIfAnalysisResult, or anything else carrying id, displayName and
        grantControls.

    .OUTPUTS
        PSCustomObject with PolicyId, PolicyName, Operator, Controls, ControlDetail and IsBlock.
        Null when the policy has no grant controls at all, which is the normal case for a
        session-only policy.

    .EXAMPLE
        $clause = Resolve-CaGrantRequirement -Policy $policyResult
        if ($clause.IsBlock) { 'access denied' }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy
    )

    $grantControls = Get-CaProperty -InputObject $Policy -Name 'grantControls'
    if ($null -eq $grantControls) {
        return $null
    }

    $controls = New-Object System.Collections.Generic.List[string]
    $controlDetail = [ordered]@{}
    $isBlock = $false

    foreach ($builtIn in @(Get-CaProperty -InputObject $grantControls -Name 'builtInControls')) {
        if ([string]::IsNullOrWhiteSpace($builtIn)) { continue }
        if ($builtIn -eq 'block') {
            $isBlock = $true
            continue
        }
        $controls.Add([string]$builtIn)
    }

    $strength = Get-CaProperty -InputObject $grantControls -Name 'authenticationStrength'
    if ($null -ne $strength) {
        $strengthName = Get-CaProperty -InputObject $strength -Name 'displayName'
        if ([string]::IsNullOrWhiteSpace($strengthName)) {
            $strengthName = Get-CaProperty -InputObject $strength -Name 'id'
        }
        if (-not [string]::IsNullOrWhiteSpace($strengthName)) {
            $control = "authenticationStrength:$strengthName"
            $controls.Add($control)

            # Sorted so that Graph reordering the array is not mistaken for the strength being
            # edited, which is the whole thing this detail exists to detect
            $combinations = @(Get-CaProperty -InputObject $strength -Name 'allowedCombinations' |
                Where-Object { $_ } | Sort-Object)
            $configurations = @(Get-CaProperty -InputObject $strength `
                -Name 'combinationConfigurations' | Where-Object { $null -ne $_ })

            $controlDetail[$control] = [PSCustomObject]@{
                PSTypeName                    = 'CaOutcome.AuthenticationStrength'
                Control                       = $control
                Id                            = [string](Get-CaProperty -InputObject $strength -Name 'id')
                DisplayName                   = [string]$strengthName
                PolicyType                    = [string](Get-CaProperty -InputObject $strength -Name 'policyType')
                AllowedCombinations           = $combinations
                CombinationConfigurationCount = $configurations.Count
            }
        }
    }

    foreach ($terms in @(Get-CaProperty -InputObject $grantControls -Name 'termsOfUse')) {
        if ([string]::IsNullOrWhiteSpace($terms)) { continue }
        $controls.Add("termsOfUse:$terms")
    }

    foreach ($factor in @(Get-CaProperty -InputObject $grantControls -Name 'customAuthenticationFactors')) {
        if ([string]::IsNullOrWhiteSpace($factor)) { continue }
        $controls.Add("customAuthenticationFactor:$factor")
    }

    if (-not $isBlock -and $controls.Count -eq 0) {
        return $null
    }

    $operator = Get-CaProperty -InputObject $grantControls -Name 'operator'
    if ([string]::IsNullOrWhiteSpace($operator)) {
        # Graph omits the operator on a block-only policy. AND is the safe reading: with one
        # control it means the same as OR, and it never understates what the user must satisfy.
        $operator = 'AND'
    }

    return [PSCustomObject]@{
        PSTypeName    = 'CaOutcome.GrantRequirement'
        PolicyId      = [string](Get-CaProperty -InputObject $Policy -Name 'id')
        PolicyName    = [string](Get-CaProperty -InputObject $Policy -Name 'displayName')
        Operator      = ([string]$operator).ToUpperInvariant()
        Controls      = $controls.ToArray()
        ControlDetail = $controlDetail
        IsBlock       = $isBlock
    }
}