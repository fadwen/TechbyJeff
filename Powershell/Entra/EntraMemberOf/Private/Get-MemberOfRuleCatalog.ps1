function Get-MemberOfRuleCatalog {
    <#
    .SYNOPSIS
        Loads Data/MemberOfRules.psd1 once and returns it in a shape built for lookups

    .DESCRIPTION
        The data file is written for a person to read and diff against the Learn page. The
        scanner wants sets and hashtables: the retired property names in lower case, the Review
        reasons keyed by code, the remediation sentence keyed by object kind. This reads the
        file on first call, checks that no Review code appears twice, and caches the result in
        the module scope.

    .OUTPUTS
        EntraMemberOf.Catalog

    .EXAMPLE
        (Get-MemberOfRuleCatalog).RetiredProperties -contains 'user.memberof'

        True.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Catalog')]
    param()

    if ($script:RuleCatalog) { return $script:RuleCatalog }

    $dataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data\MemberOfRules.psd1'
    $data = Import-PowerShellDataFile -Path $dataPath -ErrorAction Stop

    # The data file wraps its sentences in here-strings for reading; one space per line break
    $flatten = { param($Text) (([string]$Text) -replace '\s+', ' ').Trim() }

    $review = @{}
    foreach ($entry in $data.Review) {
        $code = [string]$entry.Code
        if ($review.ContainsKey($code)) {
            throw "MemberOfRules.psd1 lists Review code '$code' twice."
        }
        $review[$code] = & $flatten $entry.Reason
    }

    $remediation = @{}
    foreach ($kind in $data.Remediation.Keys) {
        $remediation[$kind] = & $flatten $data.Remediation[$kind]
    }

    $script:RuleCatalog = [PSCustomObject]@{
        PSTypeName         = 'EntraMemberOf.Catalog'
        SourceUrl          = [string]$data.SourceUrl
        SourceDate         = [string]$data.SourceDate
        VerifiedOn         = [string]$data.VerifiedOn
        MessageCenterId    = [string]$data.MessageCenterId
        RetirementDate     = [string]$data.RetirementDate
        RetirementEffect   = & $flatten $data.RetirementEffect
        RetiredProperties  = @($data.Retired.Properties | ForEach-Object { ([string]$_).ToLowerInvariant() })
        SourceProperty     = ([string]$data.Retired.SourceProperty).ToLowerInvariant()
        DocumentedQuantifier = ([string]$data.Retired.Quantifier).ToLowerInvariant()
        DocumentedOperator = ([string]$data.Retired.Operator).ToLowerInvariant()
        Limits             = $data.Limits
        Review             = $review
        Remediation        = $remediation
    }

    return $script:RuleCatalog
}
