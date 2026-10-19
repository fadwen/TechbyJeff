function Get-EntraBrandingCssProperty {
    <#
    .EXTERNALHELP EntraBrandingCss-Help.xml
    .SYNOPSIS
        Lists the CSS property names the scanner reports, with where each one was announced
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Property')]
    param(
        [Parameter()]
        [ValidateSet('Retired', 'Review')]
        [string[]]$Level = @('Retired', 'Review')
    )

    $catalog = Get-CssPropertyCatalog

    $entries = @()
    if ($Level -contains 'Retired') { $entries += $catalog.RetiredList }
    if ($Level -contains 'Review') { $entries += $catalog.ReviewList }

    foreach ($entry in $entries) {
        [PSCustomObject]@{
            PSTypeName    = 'EntraBrandingCss.Property'
            Property      = $entry.Property
            Level         = $entry.Level
            Bullet        = $entry.Bullet
            FirstListedIn = $entry.FirstListedIn
            Reason        = $entry.Reason
            SourceUrl     = $catalog.SourceUrl
            SourceDate    = $catalog.SourceDate
        }
    }
}
