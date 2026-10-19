function Invoke-CssScan {
    <#
    .SYNOPSIS
        Scans one piece of CSS and returns a result with its findings and counts

    .DESCRIPTION
        The one place file mode and tenant mode meet. Takes the CSS text for a single source,
        parses it with ConvertTo-CssDeclaration, matches every declaration's property name
        against the catalog, and returns one EntraBrandingCss.Result.

        The result's Status keeps two different statements apart on purpose:

            NoCustomCss   there was no CSS to scan (null, empty or whitespace)
            Clean         there was CSS, and nothing in it is retired or worth a look
            Review        nothing retired, but at least one near miss to read
            Retired       at least one declaration uses a retired property

        A file that is empty and a tenant locale that has no custom CSS both come out as
        NoCustomCss. Collapsing that into Clean would turn "we never looked" into "we looked
        and it is fine".

    .PARAMETER Css
        The CSS text. Null or empty gives a NoCustomCss result.

    .PARAMETER Source
        How to name this source in findings: a file path, or a Graph-style path for a tenant
        localization or theme.

    .PARAMETER SourceType
        File, Localization or Theme.

    .PARAMETER Name
        A short display name: the file name, the locale id, or the theme and locale.

    .PARAMETER CustomCssRelativeUrl
        Tenant mode only: the customCSSRelativeUrl the localizations list reported, kept on
        the result so it can be compared with what the stream actually returned.

    .OUTPUTS
        EntraBrandingCss.Result

    .EXAMPLE
        Invoke-CssScan -Css '.ext-footer { display: none; }' -Source 'inline' -SourceType File

        A Retired result with one finding.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Result')]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Css,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateSet('File', 'Localization', 'Theme')]
        [string]$SourceType,

        [Parameter()]
        [string]$Name,

        # Untyped on purpose: [string] would turn the null a file scan passes into ''
        [Parameter()]
        [AllowNull()]
        $CustomCssRelativeUrl
    )

    if (-not $Name) { $Name = $Source }

    $catalog = Get-CssPropertyCatalog

    $hasCss = -not [string]::IsNullOrWhiteSpace($Css)
    $declarations = @()
    if ($hasCss) {
        $declarations = @(ConvertTo-CssDeclaration -Css $Css)
    }

    $findings = foreach ($declaration in $declarations) {
        if ($declaration.IsCustomProperty) { continue }

        $entry = $null
        if ($catalog.Retired.ContainsKey($declaration.Property)) {
            $entry = $catalog.Retired[$declaration.Property]
        } elseif ($catalog.Review.ContainsKey($declaration.Property)) {
            $entry = $catalog.Review[$declaration.Property]
        }
        if (-not $entry) { continue }

        $note = $entry.Reason
        if ($declaration.IsEscaped) {
            $escapedNote = "Written as '$($declaration.RawProperty)' and decoded from CSS escapes."
            if ($note) { $note = "$note $escapedNote" } else { $note = $escapedNote }
        }

        [PSCustomObject]@{
            PSTypeName    = 'EntraBrandingCss.Finding'
            Source        = $Source
            Level         = $entry.Level
            Property      = $declaration.Property
            Value         = $declaration.Value
            Important     = $declaration.Important
            Selector      = $declaration.Selector
            AtRule        = $declaration.AtRule
            Line          = $declaration.Line
            Column        = $declaration.Column
            FirstListedIn = $entry.FirstListedIn
            Note          = $note
        }
    }
    $findings = @($findings)

    $retiredCount = @($findings | Where-Object Level -eq 'Retired').Count
    $reviewCount = @($findings | Where-Object Level -eq 'Review').Count

    $status = 'NoCustomCss'
    if ($hasCss) {
        if ($retiredCount -gt 0) {
            $status = 'Retired'
        } elseif ($reviewCount -gt 0) {
            $status = 'Review'
        } else {
            $status = 'Clean'
        }
    }

    [PSCustomObject]@{
        PSTypeName           = 'EntraBrandingCss.Result'
        Source               = $Source
        SourceType           = $SourceType
        Name                 = $Name
        Status               = $status
        HasCustomCss         = $hasCss
        RetiredCount         = $retiredCount
        ReviewCount          = $reviewCount
        DeclarationCount     = $declarations.Count
        Length               = $(if ($null -eq $Css) { 0 } else { $Css.Length })
        CustomCssRelativeUrl = $CustomCssRelativeUrl
        Findings             = $findings
        Error                = $null
    }
}
