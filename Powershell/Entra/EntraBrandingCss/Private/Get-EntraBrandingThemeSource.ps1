function Get-EntraBrandingThemeSource {
    <#
    .SYNOPSIS
        Reads every branding theme localization's custom CSS from a tenant over Graph beta

    .DESCRIPTION
        Branding themes exist only in the beta API. Everything beta lives in this one file so
        the dependency is easy to see, update when the endpoints move, or delete if the theme
        API never reaches v1.0 and the module should stop touching beta altogether.

        Endpoints, from the Graph beta reference for organizationalBrandingTheme and
        organizationalBrandingThemeLocalization:

            GET /beta/organization/{id}/branding/themes
            GET /beta/organization/{id}/branding/themes/{themeId}/localizations
            GET /beta/organization/{id}/branding/themes/{themeId}/localizations/{locale}/customCSS

        One source object comes out per theme localization. A theme localization whose stream
        request fails for any reason other than 404 is emitted with Error set.

        Everything here is a GET.

    .PARAMETER OrganizationId
        The tenant id. Required here: Get-EntraBrandingSource has already discovered it.

    .PARAMETER RequestHandler
        Passed through to Invoke-EntraBrandingRequest. Supplied by tests.

    .OUTPUTS
        EntraBrandingCss.Source

    .EXAMPLE
        Get-EntraBrandingThemeSource -OrganizationId $tenantId

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Source')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string]$OrganizationId,

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    $base = "https://graph.microsoft.com/beta/organization/$OrganizationId/branding/themes"

    $themes = @()
    try {
        $list = Invoke-EntraBrandingRequest -Uri $base -RequestHandler $RequestHandler
        $themes = @((Get-EntraBrandingValue -InputObject $list -Name 'value').Value)
    } catch {
        if (Test-EntraBrandingNotFound -ErrorRecord $_) {
            Write-Verbose "Tenant $OrganizationId has no branding themes."
            return
        }
        throw
    }
    Write-Verbose "Branding themes: $($themes.Count)"

    foreach ($theme in $themes) {
        $themeId = [string](Get-EntraBrandingValue -InputObject $theme -Name 'id').Value
        if ([string]::IsNullOrEmpty($themeId)) { continue }
        $themeName = [string](Get-EntraBrandingValue -InputObject $theme -Name 'name').Value
        $themeUri = "$base/$([uri]::EscapeDataString($themeId))"

        $localizations = @()
        try {
            $list = Invoke-EntraBrandingRequest -Uri "$themeUri/localizations" -RequestHandler $RequestHandler
            $localizations = @((Get-EntraBrandingValue -InputObject $list -Name 'value').Value)
        } catch {
            if (-not (Test-EntraBrandingNotFound -ErrorRecord $_)) { throw }
        }

        foreach ($localization in $localizations) {
            # The theme localization resource keys on locale; id is read as a fallback in case
            # the beta shape changes
            $locale = [string](Get-EntraBrandingValue -InputObject $localization -Name 'locale').Value
            if ([string]::IsNullOrEmpty($locale)) {
                $locale = [string](Get-EntraBrandingValue -InputObject $localization -Name 'id').Value
            }
            if ([string]::IsNullOrEmpty($locale)) { continue }

            $relativeUrl = Get-EntraBrandingValue -InputObject $localization -Name 'customCSSRelativeUrl'
            $listCss = Get-EntraBrandingValue -InputObject $localization -Name 'customCSS'
            $listCarriedCss = $listCss.Present -and -not [string]::IsNullOrWhiteSpace([string]$listCss.Value)

            $css = $null
            $errorMessage = $null
            try {
                $css = Invoke-EntraBrandingRequest -AsText -RequestHandler $RequestHandler `
                    -Uri "$themeUri/localizations/$([uri]::EscapeDataString($locale))/customCSS"
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
                Kind                 = 'Theme'
                Path                 = "$OrganizationId/branding/themes/$themeId/localizations/$locale"
                Name                 = "$themeName ($locale)"
                Css                  = $css
                CustomCssRelativeUrl = $relativeUrl.Value
                ListCarriedCss       = $listCarriedCss
                Error                = $errorMessage
            }
        }
    }
}
