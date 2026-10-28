function Get-EntraMemberOfSource {
    <#
    .SYNOPSIS
        Reads every rule-bearing object of one kind from the tenant over Graph v1.0

    .DESCRIPTION
        The three places Learn says memberOf can be used, each read with the list call Graph
        documents for it, every page followed:

            Group                 GET /groups filtered to groupTypes/any(s:s eq 'DynamicMembership'),
                                  with $select for the rule and its processing state. An advanced
                                  query, so ConsistencyLevel eventual and $count=true go with it.
            AdministrativeUnit    GET /directory/administrativeUnits with $select. The resource
                                  documents $filter only on id, displayName and description, so
                                  the dynamic ones (membershipType dynamic) are picked out here.
            AutoAssignmentPolicy  GET /identityGovernance/entitlementManagement/assignmentPolicies
                                  with $expand=accessPackage for the package name. A policy is an
                                  auto-assignment policy when automaticRequestSettings is present;
                                  its rules are the attributeRuleMembers entries of
                                  specificAllowedTargets, one source per rule.

        One EntraMemberOf.Source comes out per rule-bearing object. Everything here is a GET. A
        failure is thrown to the caller, which records it as incomplete coverage for that kind
        rather than as a clean result.

    .PARAMETER ObjectKind
        Which of the three to read.

    .PARAMETER RequestHandler
        Passed through to Invoke-EntraMemberOfRequest. Supplied by tests.

    .OUTPUTS
        EntraMemberOf.Source

    .EXAMPLE
        Get-EntraMemberOfSource -ObjectKind Group | Where-Object Rule -match 'memberOf'

        Every dynamic group whose rule text mentions memberOf, before any parsing.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Source')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy')]
        [string]$ObjectKind,

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    $base = 'https://graph.microsoft.com/v1.0'
    $advanced = @{ ConsistencyLevel = 'eventual' }

    $read = { param($Item, $Name) (Get-EntraMemberOfValue -InputObject $Item -Name $Name).Value }

    switch ($ObjectKind) {
        'Group' {
            $filter = [uri]::EscapeDataString("groupTypes/any(s:s eq 'DynamicMembership')")
            $select = 'id,displayName,groupTypes,membershipRule,membershipRuleProcessingState'
            $uri = "$base/groups?`$filter=$filter&`$select=$select&`$count=true&`$top=999"
            $groups = @(Get-EntraMemberOfCollection -Uri $uri -Headers $advanced -RequestHandler $RequestHandler)
            foreach ($group in $groups) {
                [PSCustomObject]@{
                    PSTypeName        = 'EntraMemberOf.Source'
                    ObjectKind        = 'Group'
                    Id                = [string](& $read $group 'id')
                    DisplayName       = [string](& $read $group 'displayName')
                    AccessPackageName = $null
                    Rule              = & $read $group 'membershipRule'
                    ProcessingState   = & $read $group 'membershipRuleProcessingState'
                }
            }
        }

        'AdministrativeUnit' {
            $select = 'id,displayName,membershipType,membershipRule,membershipRuleProcessingState'
            $uri = "$base/directory/administrativeUnits?`$select=$select"
            $units = @(Get-EntraMemberOfCollection -Uri $uri -RequestHandler $RequestHandler)
            foreach ($unit in $units) {
                $membershipType = [string](& $read $unit 'membershipType')
                if ($membershipType -ne 'dynamic') { continue }
                [PSCustomObject]@{
                    PSTypeName        = 'EntraMemberOf.Source'
                    ObjectKind        = 'AdministrativeUnit'
                    Id                = [string](& $read $unit 'id')
                    DisplayName       = [string](& $read $unit 'displayName')
                    AccessPackageName = $null
                    Rule              = & $read $unit 'membershipRule'
                    ProcessingState   = & $read $unit 'membershipRuleProcessingState'
                }
            }
        }

        'AutoAssignmentPolicy' {
            $uri = "$base/identityGovernance/entitlementManagement/assignmentPolicies?" +
                "`$expand=accessPackage&`$top=50"
            $policies = @(Get-EntraMemberOfCollection -Uri $uri -RequestHandler $RequestHandler)
            foreach ($policy in $policies) {
                $automatic = Get-EntraMemberOfValue -InputObject $policy -Name 'automaticRequestSettings'
                if (-not $automatic.Present -or $null -eq $automatic.Value) { continue }

                $package = & $read $policy 'accessPackage'
                $packageName = $null
                if ($null -ne $package) { $packageName = [string](& $read $package 'displayName') }

                $targets = @(& $read $policy 'specificAllowedTargets')
                $rules = @($targets | Where-Object {
                        ([string](& $read $_ '@odata.type')) -like '*attributeRuleMembers*'
                    })

                if ($rules.Count -eq 0) {
                    [PSCustomObject]@{
                        PSTypeName        = 'EntraMemberOf.Source'
                        ObjectKind        = 'AutoAssignmentPolicy'
                        Id                = [string](& $read $policy 'id')
                        DisplayName       = [string](& $read $policy 'displayName')
                        AccessPackageName = $packageName
                        Rule              = $null
                        ProcessingState   = $null
                    }
                    continue
                }

                foreach ($target in $rules) {
                    [PSCustomObject]@{
                        PSTypeName        = 'EntraMemberOf.Source'
                        ObjectKind        = 'AutoAssignmentPolicy'
                        Id                = [string](& $read $policy 'id')
                        DisplayName       = [string](& $read $policy 'displayName')
                        AccessPackageName = $packageName
                        Rule              = & $read $target 'membershipRule'
                        ProcessingState   = $null
                    }
                }
            }
        }
    }
}


function Resolve-EntraMemberOfGroupName {
    <#
    .SYNOPSIS
        Looks up display names for a set of group ids with as few requests as possible

    .DESCRIPTION
        The ids inside memberOf rules are source groups, and a report that names them is the
        one an admin can act on. Rather than one GET per id, ids are looked up in batches with
        GET /groups?$filter=id in (...). Fifteen per request keeps the URI short. An id that
        comes back with no group, because the source group was deleted, maps to null, and the
        caller says so: Learn notes that a memberOf group's membership does not update when a
        child group is deleted.

    .PARAMETER Id
        The group ids. Duplicates and empty values are ignored.

    .PARAMETER RequestHandler
        Passed through to Invoke-EntraMemberOfRequest.

    .OUTPUTS
        A hashtable from id to display name, with null for an id Graph did not return.

    .EXAMPLE
        (Resolve-EntraMemberOfGroupName -Id $ids)[$ids[0]]

        The first source group's display name.
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Id,

        [Parameter()]
        [scriptblock]$RequestHandler
    )

    $base = 'https://graph.microsoft.com/v1.0'
    $names = @{}
    $wanted = @($Id | Where-Object { $_ -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' } |
        ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    foreach ($guid in $wanted) { $names[$guid] = $null }
    if ($wanted.Count -eq 0) { return $names }

    for ($offset = 0; $offset -lt $wanted.Count; $offset += 15) {
        $batch = @($wanted[$offset..([math]::Min($offset + 14, $wanted.Count - 1))])
        $list = ($batch | ForEach-Object { "'$_'" }) -join ','
        $filter = [uri]::EscapeDataString("id in ($list)")
        $uri = "$base/groups?`$filter=$filter&`$select=id,displayName"
        $found = @(Get-EntraMemberOfCollection -Uri $uri -RequestHandler $RequestHandler)
        foreach ($group in $found) {
            $groupId = ([string](Get-EntraMemberOfValue -InputObject $group -Name 'id').Value).ToLowerInvariant()
            if ($names.ContainsKey($groupId)) {
                $names[$groupId] = [string](Get-EntraMemberOfValue -InputObject $group -Name 'displayName').Value
            }
        }
    }

    return $names
}
