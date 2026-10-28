function Get-MemberOfSummary {
    <#
    .SYNOPSIS
        Builds the one-object summary of a scan from its results and what was covered

    .DESCRIPTION
        The results say what each object does; the summary says what the scan means, and
        keeps "nothing found" apart from "not everything was read". Outcome is Retired when any
        result is Retired, Review when none is Retired but some need a look, Incomplete when
        nothing was found but a kind could not be read, and Clean only when every requested
        kind was read to the end and nothing uses memberOf.

        Counts are per object kind, so a tenant with 300 dynamic groups and no administrative
        units reads as such. MemberOfGroupCount is the number of Retired groups, against the
        documented per-tenant limit, because that is the number Learn caps.

    .PARAMETER Result
        The results of one scan.

    .PARAMETER Mode
        Tenant, File or RuleText.

    .PARAMETER Coverage
        A hashtable from object kind to Complete, Incomplete or NotRequested.

    .OUTPUTS
        EntraMemberOf.Summary

    .EXAMPLE
        Get-MemberOfSummary -Result $results -Mode Tenant -Coverage @{ Group = 'Complete'; ... }

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Summary')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result,

        [Parameter(Mandatory)]
        [ValidateSet('Tenant', 'File', 'RuleText')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [hashtable]$Coverage
    )

    $catalog = Get-MemberOfRuleCatalog

    $count = {
        param($Kind)
        $items = @($Result | Where-Object ObjectKind -eq $Kind)
        $coverageValue = if ($Coverage.ContainsKey($Kind)) { $Coverage[$Kind] } else { 'NotRequested' }
        $counts = [PSCustomObject]@{
            PSTypeName = 'EntraMemberOf.KindCount'
            Coverage   = $coverageValue
            Scanned    = $items.Count
            Retired    = @($items | Where-Object Level -eq 'Retired').Count
            Review     = @($items | Where-Object Level -eq 'Review').Count
        }
        # When the summary follows a table of results, the table formatter falls back to a
        # property list and prints nested objects with ToString, so give it something to read
        $counts | Add-Member -MemberType ScriptMethod -Name ToString -Force -Value {
            "$($this.Coverage): $($this.Scanned) scanned, $($this.Retired) retired, $($this.Review) review"
        }
        $counts
    }

    $groups = & $count 'Group'
    $units = & $count 'AdministrativeUnit'
    $policies = & $count 'AutoAssignmentPolicy'
    $rules = & $count 'Rule'

    $retiredTotal = @($Result | Where-Object Level -eq 'Retired').Count
    $reviewTotal = @($Result | Where-Object Level -eq 'Review').Count
    $incomplete = @($Coverage.Keys | Where-Object { $Coverage[$_] -eq 'Incomplete' } | Sort-Object)
    $coverageWord = if ($incomplete.Count -gt 0) { 'Incomplete' } else { 'Complete' }

    $outcome = if ($retiredTotal -gt 0) { 'Retired' }
    elseif ($reviewTotal -gt 0) { 'Review' }
    elseif ($incomplete.Count -gt 0) { 'Incomplete' }
    else { 'Clean' }

    $invariant = [cultureinfo]::InvariantCulture
    $retirementDate = [datetime]::ParseExact($catalog.RetirementDate, 'yyyy-MM-dd', $invariant)
    $dateText = $retirementDate.ToString('MMMM d, yyyy', $invariant)
    $chains = @($Result | Where-Object DependsOnMemberOfGroup).Count
    $incompleteList = $incomplete -join ', '
    $incompleteTail = if ($incomplete.Count -gt 0) { ". Not every kind was read: $incompleteList." } else { '.' }

    $message = switch ($outcome) {
        'Retired' {
            "$retiredTotal object(s) use memberOf and stop updating after $dateText" +
            $(if ($reviewTotal -gt 0) { "; $reviewTotal more need a look" } else { '' }) + $incompleteTail
        }
        'Review' {
            "No rule uses memberOf as documented, but $reviewTotal need a person to read them" + $incompleteTail
        }
        'Incomplete' {
            'Nothing found, but these kinds could not be read, so this is not an all-clear: ' +
            "$incompleteList."
        }
        'Clean' {
            "No memberOf rules in $($Result.Count) object(s) scanned."
        }
    }

    [PSCustomObject]@{
        PSTypeName             = 'EntraMemberOf.Summary'
        Outcome                = $outcome
        Coverage               = $coverageWord
        Mode                   = $Mode
        Groups                 = $groups
        AdministrativeUnits    = $units
        AutoAssignmentPolicies = $policies
        Rules                  = $rules
        MemberOfGroupCount     = $groups.Retired
        MemberOfGroupLimit     = [int]$catalog.Limits.MemberOfGroupsPerTenant
        DependencyChainCount   = $chains
        RetiredCount           = $retiredTotal
        ReviewCount            = $reviewTotal
        RetirementDate         = $retirementDate.ToString('yyyy-MM-dd')
        IncompleteKinds        = $incomplete
        Message                = $message
    }
}
