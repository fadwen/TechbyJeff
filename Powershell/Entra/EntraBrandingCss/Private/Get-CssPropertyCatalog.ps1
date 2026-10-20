function Get-CssPropertyCatalog {
    <#
    .SYNOPSIS
        Loads Data/RetiredProperties.psd1 once and returns it in a shape built for lookups

    .DESCRIPTION
        The data file is a list, which is the right shape for a human to edit and diff against
        the Learn page. The scanner wants a set. This reads the file on first call, validates
        that no name appears twice or on both lists, and caches a catalog with a hashtable per
        level keyed by lower-case property name.

    .OUTPUTS
        EntraBrandingCss.Catalog

    .EXAMPLE
        (Get-CssPropertyCatalog).Retired.ContainsKey('display')

        True.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Catalog')]
    param()

    if ($script:PropertyCatalog) { return $script:PropertyCatalog }

    $dataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data\RetiredProperties.psd1'
    $data = Import-PowerShellDataFile -Path $dataPath -ErrorAction Stop

    # A hashtable for lookups and a list for anything that shows the file in its own order
    $retired = @{}
    $retiredList = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $data.Retired) {
        $name = ([string]$entry.Property).Trim().ToLowerInvariant()
        if ($retired.ContainsKey($name)) {
            throw "RetiredProperties.psd1 lists '$name' twice."
        }
        $retired[$name] = [PSCustomObject]@{
            Property      = $name
            Level         = 'Retired'
            Bullet        = [string]$entry.Bullet
            FirstListedIn = [string]$entry.FirstListedIn
            Reason        = $null
        }
        $retiredList.Add($retired[$name])
    }

    $review = @{}
    $reviewList = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $data.Review) {
        $name = ([string]$entry.Property).Trim().ToLowerInvariant()
        if ($retired.ContainsKey($name) -or $review.ContainsKey($name)) {
            throw "RetiredProperties.psd1 lists '$name' twice."
        }
        $review[$name] = [PSCustomObject]@{
            Property      = $name
            Level         = 'Review'
            Bullet        = $null
            FirstListedIn = $null
            Reason        = [string]$entry.Reason
        }
        $reviewList.Add($review[$name])
    }

    $script:PropertyCatalog = [PSCustomObject]@{
        PSTypeName  = 'EntraBrandingCss.Catalog'
        SourceUrl   = [string]$data.SourceUrl
        SourceDate  = [string]$data.SourceDate
        VerifiedOn  = [string]$data.VerifiedOn
        Retired     = $retired
        Review      = $review
        RetiredList = $retiredList.ToArray()
        ReviewList  = $reviewList.ToArray()
    }

    return $script:PropertyCatalog
}
