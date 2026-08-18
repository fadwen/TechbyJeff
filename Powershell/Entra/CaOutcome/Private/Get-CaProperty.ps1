function Get-CaProperty {
    <#
    .SYNOPSIS
        Reads a property from an object that may be a hashtable or a PSObject

    .DESCRIPTION
        Graph responses reach this module as either hashtables or PSObjects depending on the
        OutputType the caller asked for, and the two are not interchangeable: indexing a
        PSObject with a key silently returns nothing, and PSObject.Properties does not exist on
        a hashtable. Every read in this module goes through here so that the folding logic does
        not have to care, and so that a caller switching OutputType does not quietly get an
        outcome computed from properties that all read as null.

        Missing properties return null rather than throwing. A policy result legitimately omits
        grantControls when a policy sets only session controls, so absence is normal input, not
        an error.

    .PARAMETER InputObject
        The hashtable or object to read from.

    .PARAMETER Name
        The property name.

    .OUTPUTS
        The property value, or null when the object is null or has no such property.

    .EXAMPLE
        $state = Get-CaProperty -InputObject $policy -Name 'state'

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    if ($InputObject.PSObject -and $InputObject.PSObject.Properties[$Name]) {
        return $InputObject.PSObject.Properties[$Name].Value
    }

    return $null
}
