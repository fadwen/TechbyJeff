function Resolve-CaSessionControl {
    <#
    .SYNOPSIS
        Extracts the session controls one policy actually turns on

    .DESCRIPTION
        Graph returns the sessionControls object fully populated with nulls - a policy that sets
        only a persistent browser session still comes back carrying nine other properties set to
        null. Counting those as controls would report every policy as configuring everything, so
        the extraction here keeps only what the policy really asserts.

        Two kinds of "off" have to be told apart. A null property is a control the policy never
        configured. A property present with isEnabled false is a control someone configured and
        then switched off, which is also not in force. Both are dropped, but only the second is
        a deliberate act, and dropping it is what stops a disabled sign-in frequency from
        appearing to compete with a live one from another policy.

        Each surviving control is rendered to a canonical string so that two policies asserting
        the same thing compare equal by value, and so that a conflict between two policies is
        detectable without walking object graphs. The raw object is carried alongside for
        callers that need the detail.

        RestrictivenessRank is a number, lower being more restrictive, and only set for the two
        controls where Microsoft's own semantics give an ordering that can be defended: sign-in
        frequency, where a shorter interval is stricter and every time is strictest, and
        persistent browser, where never is stricter than always. Every other control gets null,
        which is the signal to Merge-CaSessionControl that a disagreement cannot be resolved and
        must be reported instead.

    .PARAMETER Policy
        A single whatIfAnalysisResult, or anything else carrying id, displayName and
        sessionControls.

    .OUTPUTS
        Object[] of PSCustomObject with Control, Value, Raw, RestrictivenessRank, PolicyId and
        PolicyName. Empty when the policy sets no session controls.

    .EXAMPLE
        $contributions = Resolve-CaSessionControl -Policy $policyResult

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy
    )

    $sessionControls = Get-CaProperty -InputObject $Policy -Name 'sessionControls'
    if ($null -eq $sessionControls) {
        return @()
    }

    $policyId = [string](Get-CaProperty -InputObject $Policy -Name 'id')
    $policyName = [string](Get-CaProperty -InputObject $Policy -Name 'displayName')

    $names = @()
    if ($sessionControls -is [System.Collections.IDictionary]) {
        $names = @($sessionControls.Keys)
    } elseif ($sessionControls.PSObject) {
        $names = @($sessionControls.PSObject.Properties | Select-Object -ExpandProperty Name)
    }

    $contributions = New-Object System.Collections.Generic.List[object]

    foreach ($name in $names) {
        if ($name -like '@odata*') { continue }

        $value = Get-CaProperty -InputObject $sessionControls -Name $name
        if ($null -eq $value) { continue }

        # A control switched off is not in force, and must not compete with a live one
        $isEnabled = Get-CaProperty -InputObject $value -Name 'isEnabled'
        if ($null -ne $isEnabled -and -not $isEnabled) { continue }

        $rendered = ConvertTo-CaSessionControlValue -Control $name -Value $value
        if ($null -eq $rendered) { continue }

        $contributions.Add([PSCustomObject]@{
            PSTypeName          = 'CaOutcome.SessionContribution'
            Control             = $name
            Value               = $rendered.Value
            Raw                 = $value
            RestrictivenessRank = $rendered.RestrictivenessRank
            PolicyId            = $policyId
            PolicyName          = $policyName
        })
    }

    # ToArray rather than @(), which throws "Argument types do not match" on a
    # List[object] under PowerShell 7.6.4
    return $contributions.ToArray()
}

function ConvertTo-CaSessionControlValue {
    <#
    .SYNOPSIS
        Renders one session control to a comparable string and, where it can be defended, a
        restrictiveness rank

    .DESCRIPTION
        Split out from Resolve-CaSessionControl so the per-control knowledge sits in one place
        and can be tested directly. Controls this module has no specific knowledge of still get
        a value, from a compact JSON rendering of their non-null properties, so a new control
        Microsoft adds is surfaced rather than silently dropped - it simply arrives without a
        restrictiveness rank and so is reported as an unresolved conflict if two policies
        disagree about it.

    .PARAMETER Control
        The session control property name, for example signInFrequency.

    .PARAMETER Value
        The control's value object.

    .OUTPUTS
        PSCustomObject with Value and RestrictivenessRank, or null if there is nothing to say.

    .EXAMPLE
        ConvertTo-CaSessionControlValue -Control 'persistentBrowser' -Value @{ mode = 'never' }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Control,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    switch ($Control) {
        'signInFrequency' {
            $interval = [string](Get-CaProperty -InputObject $Value -Name 'frequencyInterval')
            $type = [string](Get-CaProperty -InputObject $Value -Name 'type')
            $number = Get-CaProperty -InputObject $Value -Name 'value'
            $authType = [string](Get-CaProperty -InputObject $Value -Name 'authenticationType')

            $rank = $null
            if ($interval -eq 'everyTime') {
                $text = 'everyTime'
                $rank = 0
            } elseif ($null -ne $number -and -not [string]::IsNullOrWhiteSpace($type)) {
                $text = "$number $type"
                switch ($type) {
                    'hours' { $rank = [double]$number * 60 }
                    'days'  { $rank = [double]$number * 1440 }
                    default { $rank = $null }
                }
            } else {
                return $null
            }

            if (-not [string]::IsNullOrWhiteSpace($authType)) {
                $text = "$text ($authType)"
            }
            return [PSCustomObject]@{ Value = $text; RestrictivenessRank = $rank }
        }

        'persistentBrowser' {
            $mode = [string](Get-CaProperty -InputObject $Value -Name 'mode')
            if ([string]::IsNullOrWhiteSpace($mode)) { return $null }
            # never keeps nothing across a browser restart, always keeps the session alive
            $rank = $null
            if ($mode -eq 'never') { $rank = 0 } elseif ($mode -eq 'always') { $rank = 1 }
            return [PSCustomObject]@{ Value = $mode; RestrictivenessRank = $rank }
        }

        'cloudAppSecurity' {
            $type = [string](Get-CaProperty -InputObject $Value -Name 'cloudAppSecurityType')
            if ([string]::IsNullOrWhiteSpace($type)) { $type = 'enabled' }
            return [PSCustomObject]@{ Value = $type; RestrictivenessRank = $null }
        }

        'continuousAccessEvaluation' {
            $mode = [string](Get-CaProperty -InputObject $Value -Name 'mode')
            if ([string]::IsNullOrWhiteSpace($mode)) { return $null }
            return [PSCustomObject]@{ Value = $mode; RestrictivenessRank = $null }
        }
    }

    # A bare scalar, such as disableResilienceDefaults
    $isScalar = $Value -is [bool] -or $Value -is [string] -or $Value -is [int] -or
                $Value -is [long] -or $Value -is [double]
    if ($isScalar) {
        if ($Value -is [bool] -and -not $Value) { return $null }
        return [PSCustomObject]@{ Value = [string]$Value; RestrictivenessRank = $null }
    }

    # An object this module has no specific knowledge of. isEnabled alone means "on"; anything
    # richer is rendered from its non-null properties so the detail is not lost.
    $detail = @{}
    $names = @()
    if ($Value -is [System.Collections.IDictionary]) {
        $names = @($Value.Keys)
    } elseif ($Value.PSObject) {
        $names = @($Value.PSObject.Properties | Select-Object -ExpandProperty Name)
    }
    foreach ($name in $names) {
        if ($name -eq 'isEnabled' -or $name -like '@odata*') { continue }
        $inner = Get-CaProperty -InputObject $Value -Name $name
        if ($null -ne $inner) { $detail[$name] = $inner }
    }

    if ($detail.Count -eq 0) {
        return [PSCustomObject]@{ Value = 'enabled'; RestrictivenessRank = $null }
    }

    $text = ($detail.Keys | Sort-Object | ForEach-Object { "$_=$($detail[$_])" }) -join ';'
    return [PSCustomObject]@{ Value = $text; RestrictivenessRank = $null }
}
