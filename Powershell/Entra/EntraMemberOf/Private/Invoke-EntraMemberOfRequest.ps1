function Invoke-EntraMemberOfRequest {
    <#
    .SYNOPSIS
        Sends one GET to Microsoft Graph, through an injectable handler

    .DESCRIPTION
        The single point where this module talks to anything outside the process. There is no
        Method parameter because the module has no business sending anything but GET: a reader
        that cannot write is easier to trust than one that promises not to.

        The handler is a parameter so a test can supply a scriptblock and never touch the
        network. The default handler calls Invoke-MgGraphRequest, checked for at run time
        rather than with #Requires, so rule text mode and the whole unit suite work on a host
        that has never installed the Graph SDK.

    .PARAMETER Uri
        The full Graph URI to GET. Only graph.microsoft.com v1.0 or beta is accepted.

    .PARAMETER Headers
        Extra request headers. The dynamic group filter needs ConsistencyLevel eventual.

    .PARAMETER RequestHandler
        A scriptblock taking the URI and a headers hashtable, returning what the default
        handler would: the parsed JSON body as a PSObject or hashtable. Supplied by tests;
        callers normally leave it unset.

    .OUTPUTS
        The parsed response body.

    .EXAMPLE
        Invoke-EntraMemberOfRequest -Uri 'https://graph.microsoft.com/v1.0/directory/administrativeUnits'

        The first page of administrative units for the connected tenant.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://graph\.microsoft\.com/(v1\.0|beta)/')]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    if (-not $RequestHandler) {
        if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
            throw ('Invoke-MgGraphRequest was not found. Install Microsoft.Graph.Authentication and run ' +
                'Connect-MgGraph -Scopes Group.Read.All, AdministrativeUnit.Read.All, ' +
                'EntitlementManagement.Read.All, or pass your own -RequestHandler.')
        }

        $RequestHandler = {
            param($RequestUri, $RequestHeaders)
            $splat = @{ Method = 'GET'; Uri = $RequestUri; OutputType = 'PSObject'; ErrorAction = 'Stop' }
            if ($RequestHeaders -and $RequestHeaders.Count -gt 0) { $splat.Headers = $RequestHeaders }
            Invoke-MgGraphRequest @splat
        }
    }

    Write-Verbose "GET $Uri"
    & $RequestHandler $Uri $Headers
}


function Get-EntraMemberOfCollection {
    <#
    .SYNOPSIS
        GETs every page of a Graph collection and returns the items

    .DESCRIPTION
        Follows @odata.nextLink until there is none, collecting each page's value array. The
        page size is whatever the first URI asked for; Graph puts the rest of the paging in the
        link it returns, which is used as is.

    .PARAMETER Uri
        The first page's URI.

    .PARAMETER Headers
        Sent with every page. ConsistencyLevel has to go on every request of an advanced query.

    .PARAMETER RequestHandler
        Passed through to Invoke-EntraMemberOfRequest.

    .OUTPUTS
        The items, as one array.

    .EXAMPLE
        Get-EntraMemberOfCollection -Uri 'https://graph.microsoft.com/v1.0/directory/administrativeUnits'

        Every administrative unit in the tenant.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    $pages = 0
    while ($next) {
        $page = Invoke-EntraMemberOfRequest -Uri $next -Headers $Headers -RequestHandler $RequestHandler
        $pages++
        foreach ($item in @((Get-EntraMemberOfValue -InputObject $page -Name 'value').Value)) {
            if ($null -ne $item) { $items.Add($item) }
        }
        $next = [string](Get-EntraMemberOfValue -InputObject $page -Name '@odata.nextLink').Value
        if ($pages -gt 1000) { throw "More than 1000 pages from $Uri; stopping rather than looping." }
    }
    Write-Verbose "$($items.Count) items in $pages page(s) from $Uri"
    return $items.ToArray()
}


function Get-EntraMemberOfValue {
    <#
    .SYNOPSIS
        Reads one property from a Graph response item whether it is a PSObject or a hashtable

    .DESCRIPTION
        The default handler returns PSObjects, but a caller-supplied handler may return the
        hashtables Invoke-MgGraphRequest produces by default. Both shapes are read here so the
        rest of the module does not care which it got. Present tells absent from null, which
        matters for automaticRequestSettings: Learn says the property is only present on an
        auto-assignment policy.

    .PARAMETER InputObject
        The response item.

    .PARAMETER Name
        The property name, matched case-insensitively.

    .OUTPUTS
        A PSCustomObject with Present and Value.

    .EXAMPLE
        (Get-EntraMemberOfValue -InputObject $group -Name 'membershipRule').Value
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
