function Get-EntraBrandingSource {
    <#
    .SYNOPSIS
        Reads every company branding localization's custom CSS from a tenant over Graph v1.0

    .DESCRIPTION
        Finds the tenant id if none was given, lists the branding localizations, and reads the
        customCSS stream for each one with its own request. The list call does not carry the
        CSS: customCSS is a Stream property, and Graph returns stream properties only through
        their own endpoint. What the list does carry is customCSSRelativeUrl, which is recorded
        on each source so a caller can compare the two signals.

        One source object comes out per localization, including the default locale, whose id
        is 0. A localization whose stream request fails for any reason other than 404 is still
        emitted, with Error set, so one bad locale does not hide the rest.

        Everything here is a GET.

    .PARAMETER OrganizationId
        The tenant id. Discovered from GET /organization when omitted.

    .PARAMETER RequestHandler
        Passed through to Invoke-EntraBrandingRequest. Supplied by tests.

    .OUTPUTS
        EntraBrandingCss.Source

    .EXAMPLE
        Get-EntraBrandingSource | Where-Object Css

        The localizations that have custom CSS, with the text on each.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Source')]
    param(
        [Parameter()]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string]$OrganizationId,

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    $base = 'https://graph.microsoft.com/v1.0'

    if (-not $OrganizationId) {
        $organization = Invoke-EntraBrandingRequest -Uri "$base/organization?`$select=id" `
            -RequestHandler $RequestHandler
        $ids = @((Get-EntraBrandingValue -InputObject $organization -Name 'value').Value |
            ForEach-Object { (Get-EntraBrandingValue -InputObject $_ -Name 'id').Value })
        if ($ids.Count -ne 1) {
            throw "Expected one organization from GET /organization and got $($ids.Count). Pass -OrganizationId."
        }
        $OrganizationId = [string]$ids[0]
        Write-Verbose "Organization id: $OrganizationId"
    }

    $localizations = @()
    try {
        $list = Invoke-EntraBrandingRequest -Uri "$base/organization/$OrganizationId/branding/localizations" `
            -RequestHandler $RequestHandler
        $localizations = @((Get-EntraBrandingValue -InputObject $list -Name 'value').Value)
    } catch {
        if (Test-EntraBrandingNotFound -ErrorRecord $_) {
            Write-Verbose "Tenant $OrganizationId has no branding localizations."
            return
        }
        throw
    }

    foreach ($localization in $localizations) {
        $id = [string](Get-EntraBrandingValue -InputObject $localization -Name 'id').Value
        if ([string]::IsNullOrEmpty($id)) { continue }

        $relativeUrl = Get-EntraBrandingValue -InputObject $localization -Name 'customCSSRelativeUrl'
        $listCss = Get-EntraBrandingValue -InputObject $localization -Name 'customCSS'
        $listCarriedCss = $listCss.Present -and -not [string]::IsNullOrWhiteSpace([string]$listCss.Value)
        Write-Verbose ("Localization {0}: list response {1} customCSS content; customCSSRelativeUrl={2}" -f $id,
            $(if ($listCarriedCss) { 'carried' } else { 'did not carry' }), $relativeUrl.Value)

        $path = "$OrganizationId/branding/localizations/$id"
        $streamUri = "$base/organization/$OrganizationId/branding/localizations/" +
            "$([uri]::EscapeDataString($id))/customCSS"
        $css = $null
        $errorMessage = $null
        try {
            $css = Invoke-EntraBrandingRequest -AsText -RequestHandler $RequestHandler -Uri $streamUri
        } catch {
            if (Test-EntraBrandingNotFound -ErrorRecord $_) {
                $css = $null
            } else {
                $errorMessage = $_.Exception.Message
            }
        }

        [PSCustomObject]@{
            PSTypeName           = 'EntraBrandingCss.Source'
            OrganizationId       = $OrganizationId
            Kind                 = 'Localization'
            Path                 = $path
            Name                 = $id
            Css                  = $css
            CustomCssRelativeUrl = $relativeUrl.Value
            ListCarriedCss       = $listCarriedCss
            Error                = $errorMessage
        }
    }
}
