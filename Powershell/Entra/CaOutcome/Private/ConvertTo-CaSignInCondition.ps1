function ConvertTo-CaSignInCondition {
    <#
    .SYNOPSIS
        Turns a matrix condition entry into the signInConditions object the API expects

    .DESCRIPTION
        The matrix is written in PascalCase because that is what the rest of PowerShell looks
        like, and the API wants camelCase. Translating in one place keeps the matrix readable
        without making the caller remember which convention applies where.

        The translation is a lowercase of the first letter, not a lookup table, and that is
        deliberate. Every documented signInConditions property - devicePlatform, clientAppType,
        signInRiskLevel, userRiskLevel, insiderRiskLevel, servicePrincipalRiskLevel,
        agentIdRiskLevel, country, ipAddress, deviceInfo, authenticationFlow - is the PascalCase
        name with its first letter lowered, so a rule beats a list: a property Microsoft adds
        tomorrow works today, where a lookup table would silently drop it.

        Because it is a rule rather than a list, a misspelled key is passed through to the API
        rather than caught here. That is the deliberate trade: Graph rejects an unknown property
        with a clear error, which is a better failure than this module refusing a property that
        is real and simply newer than it is.

        Name is dropped - it labels the row in the matrix and is not part of the sign-in. Nested
        values such as deviceInfo and authenticationFlow are passed through untouched, since
        their inner properties are already camelCase in any example worth copying.

    .PARAMETER Condition
        A condition entry from the matrix.

    .OUTPUTS
        Hashtable shaped for the signInConditions property of the evaluate request.

    .EXAMPLE
        ConvertTo-CaSignInCondition -Condition @{
            Name = 'unmanaged'; DevicePlatform = 'windows'; DeviceInfo = @{ isCompliant = $false }
        }

        Returns @{ devicePlatform = 'windows'; deviceInfo = @{ isCompliant = $false } }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Condition
    )

    $result = @{}
    if ($null -eq $Condition) {
        return $result
    }

    $names = @()
    if ($Condition -is [System.Collections.IDictionary]) {
        $names = @($Condition.Keys)
    } elseif ($Condition.PSObject) {
        $names = @($Condition.PSObject.Properties | Select-Object -ExpandProperty Name)
    }

    foreach ($name in $names) {
        if ($name -eq 'Name') { continue }

        $value = Get-CaProperty -InputObject $Condition -Name $name
        if ($null -eq $value) { continue }

        $camel = $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)
        $result[$camel] = $value
    }

    return $result
}
