function Import-EntraMemberOfRuleFile {
    <#
    .SYNOPSIS
        Reads an exported CSV or JSON file into the records the scanner takes

    .DESCRIPTION
        Learn's own migration step for groups is to export dynamic membership groups from the
        admin center and look for rules that contain memberOf, so an exported file is a real
        input. Exports do not agree on column names, and a JSON file might be a saved Graph
        response, so columns are matched by a short list of names each, case-insensitively:

            Rule         membershipRule, rule
            Id           id, objectId
            DisplayName  displayName, name
            ObjectKind   objectKind, kind, objectType, type
            ProcessingState  membershipRuleProcessingState, processingState

        A row with no recognizable rule column is an error for the file, because a file of
        groups with no rule column cannot be scanned and should not come back clean. A row
        with no object kind is taken as a Group, which is what the admin center export holds,
        and the result's note says so.

        A JSON file may be an array of objects, or an object whose value property is that
        array, which is the shape of a saved Graph response.

    .PARAMETER Path
        One resolved file path, .csv or .json.

    .OUTPUTS
        PSCustomObject records with ObjectKind, Id, DisplayName, AccessPackageName, Rule,
        ProcessingState and Note.

    .EXAMPLE
        Import-EntraMemberOfRuleFile -Path .\dynamic-groups.csv

        One record per row.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $rows = switch ($extension) {
        '.csv' { @(Import-Csv -LiteralPath $Path -ErrorAction Stop) }
        '.json' {
            $parsed = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
            $inner = Get-EntraMemberOfValue -InputObject $parsed -Name 'value'
            if ($inner.Present) { @($inner.Value) } else { @($parsed) }
        }
        default { throw "$Path is not a .csv or .json file." }
    }

    $columns = @{
        Rule              = @('membershipRule', 'rule')
        Id                = @('id', 'objectId')
        DisplayName       = @('displayName', 'name')
        ObjectKind        = @('objectKind', 'kind', 'objectType', 'type')
        ProcessingState   = @('membershipRuleProcessingState', 'processingState')
        AccessPackageName = @('accessPackageName', 'accessPackage')
    }
    $kindNames = @{
        group                = 'Group'
        groups               = 'Group'
        administrativeunit   = 'AdministrativeUnit'
        administrativeunits  = 'AdministrativeUnit'
        autoassignmentpolicy = 'AutoAssignmentPolicy'
        policy               = 'AutoAssignmentPolicy'
        accesspackageassignmentpolicy = 'AutoAssignmentPolicy'
        rule                 = 'Rule'
    }

    $pick = {
        param($Row, $Names)
        foreach ($name in $Names) {
            $found = Get-EntraMemberOfValue -InputObject $Row -Name $name
            if ($found.Present) { return $found }
        }
        [PSCustomObject]@{ Present = $false; Value = $null }
    }

    $index = 0
    foreach ($row in $rows) {
        $index++
        $rule = & $pick $row $columns.Rule
        if (-not $rule.Present) {
            throw "$Path row $index has no rule column (expected one of: $($columns.Rule -join ', '))."
        }

        $note = $null
        $kindValue = [string](& $pick $row $columns.ObjectKind).Value
        $kind = $kindNames[$kindValue.Trim().ToLowerInvariant()]
        if (-not $kind) {
            $kind = 'Group'
            $note = if ($kindValue) { "Object kind '$kindValue' was not recognized; scanned as a Group." }
            else { 'The file gives no object kind; scanned as a Group.' }
        }

        $packageValue = (& $pick $row $columns.AccessPackageName).Value
        $packageIsObject = $packageValue -is [System.Collections.IDictionary] -or
            ($packageValue -and $packageValue.PSObject.Properties['displayName'])
        if ($packageIsObject) {
            $packageValue = (Get-EntraMemberOfValue -InputObject $packageValue -Name 'displayName').Value
        }

        [PSCustomObject]@{
            ObjectKind        = $kind
            Id                = [string](& $pick $row $columns.Id).Value
            DisplayName       = [string](& $pick $row $columns.DisplayName).Value
            AccessPackageName = $(if ($null -ne $packageValue) { [string]$packageValue } else { $null })
            Rule              = $(if ($null -ne $rule.Value) { [string]$rule.Value } else { $null })
            ProcessingState   = $(if ($null -ne ($state = (& $pick $row $columns.ProcessingState).Value) -and
                    -not [string]::IsNullOrEmpty([string]$state)) { [string]$state } else { $null })
            Note              = $note
        }
    }
}
