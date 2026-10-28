function Test-EntraMemberOfRule {
    <#
    .EXTERNALHELP EntraMemberOf-Help.xml
    .SYNOPSIS
        Finds dynamic membership rules that use the memberOf operator before it is retired
    #>

    [CmdletBinding(DefaultParameterSetName = 'Rule')]
    [OutputType('EntraMemberOf.Result', 'EntraMemberOf.Summary')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Tenant',
        Justification = 'The switch selects the parameter set; the set name is what the body reads.')]
    param(
        [Parameter(ParameterSetName = 'Rule', Mandatory, Position = 0, ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [Alias('MembershipRule')]
        [AllowEmptyString()]
        [string[]]$Rule,

        [Parameter(ParameterSetName = 'Path', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Tenant', Mandatory)]
        [switch]$Tenant,

        [Parameter(ParameterSetName = 'Tenant')]
        [ValidateSet('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy')]
        [string[]]$ObjectKind = @('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy'),

        [Parameter(ParameterSetName = 'Tenant')]
        [switch]$SkipGroupNameLookup,

        [Parameter(ParameterSetName = 'Tenant')]
        [scriptblock]$RequestHandler
    )

    begin {
        $correlationId = [guid]::NewGuid()
        $mode = $PSCmdlet.ParameterSetName
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) ($mode) - CorrelationId: $correlationId"
        $records = [System.Collections.Generic.List[object]]::new()
        $fileCoverage = @{}
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Rule' {
                foreach ($text in $Rule) {
                    Invoke-MemberOfRuleScan -Rule $text -ObjectKind Rule -Source 'RuleText'
                }
            }
            'Path' {
                foreach ($item in $Path) {
                    # Ignore rather than SilentlyContinue: either of those would put Resolve-Path's
                    # own error in the caller's -ErrorVariable beside the one written here
                    $resolved = @(Resolve-Path -Path $item -ErrorAction Ignore)
                    if ($resolved.Count -eq 0) {
                        Write-Error "Path not found: $item - CorrelationId: $correlationId"
                        continue
                    }
                    foreach ($entry in $resolved) {
                        $fullPath = $entry.ProviderPath
                        try {
                            foreach ($record in @(Import-EntraMemberOfRuleFile -Path $fullPath)) {
                                $record | Add-Member -NotePropertyName Source -NotePropertyValue $fullPath
                                $records.Add($record)
                                $fileCoverage[$record.ObjectKind] = 'Complete'
                            }
                        } catch {
                            Write-Error ("Could not read $fullPath : $($_.Exception.Message) - " +
                                "CorrelationId: $correlationId")
                        }
                    }
                }
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Rule') { return }

        $coverage = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Tenant') {
            foreach ($kind in $ObjectKind) {
                try {
                    $sources = @(Get-EntraMemberOfSource -ObjectKind $kind -RequestHandler $RequestHandler)
                    foreach ($source in $sources) {
                        $source | Add-Member -NotePropertyName Source -NotePropertyValue 'Tenant' -Force
                        $source | Add-Member -NotePropertyName Note -NotePropertyValue $null -Force
                        $records.Add($source)
                    }
                    $coverage[$kind] = 'Complete'
                } catch {
                    $coverage[$kind] = 'Incomplete'
                    Write-Error ("Could not read $kind objects: $($_.Exception.Message) - " +
                        "CorrelationId: $correlationId")
                }
            }
        } else {
            $coverage = $fileCoverage
        }

        $results = @(foreach ($record in $records) {
                $scanSplat = @{
                    Rule              = $record.Rule
                    ObjectKind        = $record.ObjectKind
                    Id                = $record.Id
                    DisplayName       = $record.DisplayName
                    AccessPackageName = $record.AccessPackageName
                    ProcessingState   = $record.ProcessingState
                    Source            = $record.Source
                }
                $result = Invoke-MemberOfRuleScan @scanSplat
                if ($record.Note) {
                    $result.Note = $(if ($result.Note) { "$($record.Note) $($result.Note)" } else { $record.Note })
                }
                $result
            })

        $names = $null
        if ($PSCmdlet.ParameterSetName -eq 'Tenant' -and -not $SkipGroupNameLookup) {
            $ids = @($results | Where-Object Level -eq 'Retired' | ForEach-Object { $_.SourceGroupIds })
            if ($ids.Count -gt 0) {
                try {
                    $names = Resolve-EntraMemberOfGroupName -Id $ids -RequestHandler $RequestHandler
                } catch {
                    Write-Warning "Source group names were not resolved: $($_.Exception.Message)"
                }
            }
        }
        $results = @(Add-MemberOfDependency -Result $results -Names $names)

        foreach ($result in $results) { $result }
        $summaryMode = if ($PSCmdlet.ParameterSetName -eq 'Tenant') { 'Tenant' } else { 'File' }
        Get-MemberOfSummary -Result $results -Mode $summaryMode -Coverage $coverage

        Write-Verbose "Completed $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"
    }
}
