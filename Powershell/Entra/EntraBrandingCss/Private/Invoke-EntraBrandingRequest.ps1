function Invoke-EntraBrandingRequest {
    <#
    .SYNOPSIS
        Sends one GET to Microsoft Graph, through an injectable handler

    .DESCRIPTION
        The single point where this module talks to anything outside the process. There is no
        Method parameter because the module has no business sending anything but GET: a reader
        that cannot write is easier to trust than one that promises not to.

        The handler is a parameter so a test can supply a scriptblock and never touch the
        network. The default handler calls Invoke-MgGraphRequest, checked for at run time
        rather than with #Requires, so file mode and the whole unit suite work on a host that
        has never installed the Graph SDK.

        JSON responses come back as PSObjects. With -AsText the body is returned as a string,
        which is how the customCSS stream is read, and a 404 comes back as null because for a
        stream property "not set" is an answer rather than an error.

    .PARAMETER Uri
        The full Graph URI to GET.

    .PARAMETER AsText
        Return the response body as a string instead of parsing JSON.

    .PARAMETER RequestHandler
        A scriptblock taking the URI and a boolean for AsText, returning what the default
        handler would. Supplied by tests; callers normally leave it unset.

    .OUTPUTS
        System.Management.Automation.PSObject for JSON, System.String with -AsText, or null
        when a text request returns 404.

    .EXAMPLE
        Invoke-EntraBrandingRequest -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id'

        Returns the organization collection for the connected tenant.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject], [string])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://graph\.microsoft\.com/(v1\.0|beta)/')]
        [string]$Uri,

        [Parameter()]
        [switch]$AsText,

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    if (-not $RequestHandler) {
        if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
            throw ('Invoke-MgGraphRequest was not found. Install Microsoft.Graph.Authentication and run ' +
                'Connect-MgGraph -Scopes OrganizationalBranding.Read.All, or pass your own -RequestHandler.')
        }

        $RequestHandler = {
            param($RequestUri, $ReturnText)

            if (-not $ReturnText) {
                return Invoke-MgGraphRequest -Method GET -Uri $RequestUri -OutputType PSObject -ErrorAction Stop
            }

            # A Stream property is not JSON, so ask for the raw response and read the body.
            $response = Invoke-MgGraphRequest -Method GET -Uri $RequestUri -OutputType HttpResponseMessage `
                -ErrorAction Stop
            try {
                if ([int]$response.StatusCode -eq 404) { return $null }
                if (-not $response.IsSuccessStatusCode) {
                    throw "Graph returned $([int]$response.StatusCode) $($response.ReasonPhrase) for $RequestUri"
                }
                return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            } finally {
                $response.Dispose()
            }
        }
    }

    Write-Verbose "GET $Uri"
    & $RequestHandler $Uri $AsText.IsPresent
}


function Test-EntraBrandingNotFound {
    <#
    .SYNOPSIS
        Reports whether an error record is a Graph 404

    .DESCRIPTION
        Invoke-MgGraphRequest surfaces HTTP failures as exceptions whose shape has varied
        between SDK versions, so this checks the response status where one is attached and
        falls back to the message text. Used to tell "this locale has no custom CSS" from
        "the request failed".

    .PARAMETER ErrorRecord
        The record from a catch block.

    .OUTPUTS
        System.Boolean

    .EXAMPLE
        try { ... } catch { if (Test-EntraBrandingNotFound -ErrorRecord $_) { $css = $null } else { throw } }
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($exception) {
        $response = $null
        try { $response = $exception.PSObject.Properties['Response'].Value } catch { $response = $null }
        if ($response -and $null -ne $response.StatusCode -and [int]$response.StatusCode -eq 404) {
            return $true
        }
        if ($exception.Message -match '\b404\b|\bNotFound\b|\bNot Found\b|Request_ResourceNotFound') {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}


function Get-EntraBrandingValue {
    <#
    .SYNOPSIS
        Reads one property from a Graph response item whether it is a PSObject or a hashtable

    .DESCRIPTION
        The default handler returns PSObjects, but a caller-supplied handler may return the
        hashtables Invoke-MgGraphRequest produces by default. Both shapes are read here so the
        rest of the module does not care which it got. Returns null when the property is absent
        and sets Present so a caller can tell absent from null, which matters for checking
        whether the localizations list carried customCSS at all.

    .PARAMETER InputObject
        The response item.

    .PARAMETER Name
        The property name, matched case-insensitively.

    .OUTPUTS
        A PSCustomObject with Present and Value.

    .EXAMPLE
        (Get-EntraBrandingValue -InputObject $locale -Name 'customCSSRelativeUrl').Value
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $present = $false
    $value = $null

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -eq $Name) {
                $present = $true
                $value = $InputObject[$key]
                break
            }
        }
    } elseif ($null -ne $InputObject) {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($property) {
            $present = $true
            $value = $property.Value
        }
    }

    [PSCustomObject]@{ Present = $present; Value = $value }
}
