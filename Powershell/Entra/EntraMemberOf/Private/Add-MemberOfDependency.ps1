function Add-MemberOfDependency {
    <#
    .SYNOPSIS
        Fills in source group names and memberOf-on-memberOf chains across a set of results

    .DESCRIPTION
        A single rule scan only knows the ids inside its own memberOf expression. Two things
        need the whole set: the display name of each source group, and whether a source group
        is itself a Retired memberOf group, which Learn lists as unsupported and which means the
        group breaks twice on the retirement date, once for its own rule and once for its
        source. Both are set here, on the Retired results, after every object has been scanned.

        Names come from the Names map when one is given, which tenant mode builds with
        Resolve-EntraMemberOfGroupName. When no map is given, as in file mode, a source group's
        name is taken from the scanned set itself when the id is in it, and stays null
        otherwise. SourceGroupNames is always aligned with SourceGroupIds, null for an unknown
        id, so a caller can zip the two.

    .PARAMETER Result
        The results of one scan, all kinds. Modified in place and returned.

    .PARAMETER Names
        A hashtable from lower-case group id to display name, null for an id that no longer
        exists. Optional.

    .OUTPUTS
        EntraMemberOf.Result, the same objects, in the same order.

    .EXAMPLE
        $results = Add-MemberOfDependency -Result $results -Names $names

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Result')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result,

        [Parameter()]
        [hashtable]$Names
    )

    $retiredGroups = @{}
    $knownNames = @{}
    foreach ($item in $Result) {
        if ([string]::IsNullOrEmpty($item.Id)) { continue }
        $key = $item.Id.ToLowerInvariant()
        if ($item.ObjectKind -eq 'Group') {
            $knownNames[$key] = $item.DisplayName
            if ($item.Level -eq 'Retired') { $retiredGroups[$key] = $item }
        }
    }

    foreach ($item in $Result) {
        if ($item.Level -ne 'Retired') { continue }
        $ids = @($item.SourceGroupIds)
        $dependsOn = [System.Collections.Generic.List[string]]::new()
        $missing = [System.Collections.Generic.List[string]]::new()
        $resolved = foreach ($id in $ids) {
            $key = $id.ToLowerInvariant()
            if ($retiredGroups.ContainsKey($key)) { $dependsOn.Add($id) }
            # The lookup wins when it found a name; a group the scan itself read is next; a
            # lookup that came back empty for an id nothing else knows is a deleted group
            if ($Names -and $Names.ContainsKey($key) -and $null -ne $Names[$key]) { $Names[$key] }
            elseif ($knownNames.ContainsKey($key)) { $knownNames[$key] }
            elseif ($Names -and $Names.ContainsKey($key)) { $missing.Add($id); $null }
            else { $null }
        }
        $item.SourceGroupNames = @($resolved)
        $item.DependsOn = $dependsOn.ToArray()
        $item.DependsOnMemberOfGroup = $dependsOn.Count -gt 0
        if ($dependsOn.Count -gt 0) {
            $chainNote = "Depends on $($dependsOn.Count) group(s) that use memberOf themselves"
            # Learn states the nesting limit for groups; for a unit or a policy the dependency
            # is still real but the page makes no claim about it
            $chainNote += $(if ($item.ObjectKind -eq 'Group') { ', which Learn lists as unsupported.' }
                else { '.' })
            $item.Note = $(if ($item.Note) { "$($item.Note) $chainNote" } else { $chainNote })
        }
        if ($Names) {
            if ($missing.Count -gt 0) {
                $missingNote = "$($missing.Count) source group id(s) were not found in the tenant: " +
                    "$($missing -join ', ')."
                $item.Note = $(if ($item.Note) { "$($item.Note) $missingNote" } else { $missingNote })
            }
        }
    }

    foreach ($item in $Result) { $item }
}
