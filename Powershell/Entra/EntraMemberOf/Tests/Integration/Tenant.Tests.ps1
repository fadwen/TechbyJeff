#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The one path the unit tests cannot reach: the default request handler, which is this
    module's only contact with Microsoft.Graph.Authentication, and the shape of what a real
    tenant returns.

    Skipped unless the session is already connected with Connect-MgGraph. Nothing
    tenant-specific is asserted: a tenant with no dynamic groups is a valid answer, and a kind
    the token cannot read is a valid answer too, as long as the summary says so instead of
    calling the tenant clean.

    An app-only (certificate) session has ContextScope Process, so Connect-MgGraph and
    Invoke-Pester must run in the same PowerShell process for this file to run.

    Read-only: every request is a GET.
#>

#pester:no-parallel

$script:CanReachGraph = $false
try {
    if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) {
        $script:CanReachGraph = [bool](Get-MgContext)
    }
} catch {
    $script:CanReachGraph = $false
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'EntraMemberOf.psd1') -Force

    $script:CanReachGraph = $false
    try {
        if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) {
            $script:CanReachGraph = [bool](Get-MgContext)
        }
    } catch {
        $script:CanReachGraph = $false
    }
}

AfterAll {
    Remove-Module EntraMemberOf -Force -ErrorAction SilentlyContinue
}

Describe 'Test-EntraMemberOfRule against the connected tenant' `
    -Tag 'Integration', 'RequiresTenant' -Skip:(-not $script:CanReachGraph) {

    BeforeAll {
        $script:Stream = @(Test-EntraMemberOfRule -Tenant -Verbose 4>&1 -ErrorAction SilentlyContinue `
            -ErrorVariable script:Errors)
        $ofType = { param($Name) @($script:Stream | Where-Object { $_.PSObject.TypeNames -contains $Name }) }
        $script:Results = & $ofType 'EntraMemberOf.Result'
        $script:Summary = (& $ofType 'EntraMemberOf.Summary')[0]
        $script:VerboseLines = @($script:Stream |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
    }

    It 'always returns a summary' {
        $script:Summary | Should-NotBeNull
        $script:Summary.Mode | Should-Be 'Tenant'
        @('Retired', 'Review', 'Incomplete', 'Clean') | Should-ContainCollection $script:Summary.Outcome
    }

    It 'gives every result a known level and kind' {
        $script:Results | Should-All { $_.Level -in @('Retired', 'Review', 'Clean') }
        $script:Results | Should-All { $_.ObjectKind -in @('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy') }
        $script:Results | Should-All { $_.Source -eq 'Tenant' }
    }

    It 'reports a kind it could not read as incomplete, never as clean' {
        $failed = @($script:Errors | Where-Object { "$_" -like 'Could not read *' })
        if ($failed.Count -gt 0) {
            $script:Summary.Coverage | Should-Be 'Incomplete'
            $script:Summary.IncompleteKinds.Count | Should-BeGreaterThanOrEqual 1
        } else {
            $script:Summary.Coverage | Should-Be 'Complete'
        }
    }

    It 'counts what it scanned consistently' {
        ($script:Summary.Groups.Scanned + $script:Summary.AdministrativeUnits.Scanned +
            $script:Summary.AutoAssignmentPolicies.Scanned) | Should-Be $script:Results.Count
    }

    It 'only ever sent GET requests' {
        $script:VerboseLines | Where-Object { $_ -match '^(GET|POST|PATCH|PUT|DELETE) ' } |
            Should-All { $_ -like 'GET *' }
    }
}
