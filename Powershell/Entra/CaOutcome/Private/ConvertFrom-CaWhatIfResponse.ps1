function ConvertFrom-CaWhatIfResponse {
    <#
    .SYNOPSIS
        Normalises the several shapes a What If response arrives in into one array of policy
        results

    .DESCRIPTION
        The same evaluation comes back looking different depending on who fetched it.
        Invoke-MgGraphRequest -OutputType Json hands back a string, -OutputType PSObject hands
        back an envelope with a value property, Maester's Test-MtConditionalAccessWhatIf hands
        back the collection already unwrapped, and a fixture on disk is whatever was saved.
        Every one of those is the same whatIfAnalysisResult collection underneath.

        Normalising here rather than in the public function is what lets the folding logic be
        written against a single shape, and what lets the tests feed it a file without
        pretending to be Graph.

        A hashtable is treated as a single result rather than as a collection, because Graph
        deserialises to hashtables under -OutputType Hashtable and a lone policy result is a
        legitimate thing to fold.

    .PARAMETER InputObject
        The response in any of its forms: a JSON string, an envelope with a value property, an
        array of results, or a single result.

    .OUTPUTS
        Object[] of policy result objects. An empty array if the response held none.

    .EXAMPLE
        $results = ConvertFrom-CaWhatIfResponse -InputObject (Get-Content .\whatif.json -Raw)

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
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    $candidate = $InputObject

    # A JSON string, from -OutputType Json or from a file read raw
    if ($candidate -is [string]) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            return @()
        }
        try {
            $candidate = $candidate | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "The input is a string but not valid JSON: $($_.Exception.Message)"
        }
    }

    # The OData envelope, from -OutputType PSObject or Hashtable
    if ($candidate -isnot [System.Collections.IEnumerable] -or $candidate -is [hashtable]) {
        $valueProperty = $null
        if ($candidate -is [hashtable]) {
            if ($candidate.ContainsKey('value')) { $valueProperty = $candidate['value'] }
        } elseif ($candidate.PSObject.Properties['value']) {
            $valueProperty = $candidate.PSObject.Properties['value'].Value
        }

        if ($null -ne $valueProperty) {
            return @($valueProperty)
        }
    }

    # An array that is itself the envelope, which happens when a caller splats one in
    if ($candidate -is [System.Collections.IEnumerable] -and $candidate -isnot [string]) {
        $items = @($candidate)
        if ($items.Count -eq 1 -and $null -ne $items[0]) {
            $single = $items[0]
            $hasValue = $false
            if ($single -is [hashtable]) {
                $hasValue = $single.ContainsKey('value')
            } elseif ($single.PSObject -and $single.PSObject.Properties['value']) {
                $hasValue = $true
            }
            if ($hasValue) {
                return ConvertFrom-CaWhatIfResponse -InputObject $single
            }
        }
        return $items
    }

    return @($candidate)
}
