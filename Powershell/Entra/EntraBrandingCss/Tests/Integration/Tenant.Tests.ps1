#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The one path the unit tests cannot reach: the default request handler, which is this
    module's only contact with Microsoft.Graph.Authentication, and the shape of what a real
    tenant returns.

    Skipped unless the session is already connected with Connect-MgGraph. The skip is decided
    at discovery and has to survive a host with no Graph SDK at all, which is why the check is
    wrapped. Nothing tenant-specific is asserted: a tenant with no custom CSS anywhere is a
    valid answer, and the assertions are about the round trip and the result shape.

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
    Import-Module (Join-Path $script:ModuleRoot 'EntraBrandingCss.psd1') -Force

    # Recomputed: a discovery-scope value is not guaranteed to survive into the run pass
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
    Remove-Module EntraBrandingCss -Force -ErrorAction SilentlyContinue
}

Describe 'Test-EntraBrandingCss against the connected tenant' `
    -Tag 'Integration', 'RequiresTenant' -Skip:(-not $script:CanReachGraph) {

    BeforeAll {
        $script:Stream = @(Test-EntraBrandingCss -Tenant -IncludeTheme -Verbose 4>&1)
        $script:Results = @($script:Stream |
            Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
        $script:VerboseLines = @($script:Stream |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
    }

    It 'returns at least the default localization' {
        $script:Results.Count | Should-BeGreaterThanOrEqual 1
        @($script:Results | Where-Object SourceType -eq 'Localization' | ForEach-Object Name) |
            Should-ContainCollection '0'
    }

    It 'gives every result a known status and no error' {
        $script:Results | Should-All { $_.Status -in @('NoCustomCss', 'Clean', 'Review', 'Retired') }
        $script:Results | Should-All { $null -eq $_.Error }
    }

    It 'names every source by its Graph path under the tenant id' {
        $script:Results | Should-All {
            $_.Source -match '^[0-9a-f-]{36}/branding/(localizations/[^/]+|themes/[^/]+/localizations/[^/]+)$'
        }
    }

    It 'agrees with the list response about which locales have custom CSS' {
        # customCSSRelativeUrl on the list and a non-empty stream should say the same thing.
        # If this fails, the README's description of the two signals needs updating.
        $localizations = @($script:Results | Where-Object SourceType -eq 'Localization')
        $localizations | Should-All {
            [bool]$_.CustomCssRelativeUrl -eq [bool]$_.HasCustomCss
        }
    }

    It 'only ever sent GET requests' {
        $script:VerboseLines | Where-Object { $_ -match '^(GET|POST|PATCH|PUT|DELETE) ' } |
            Should-All { $_ -like 'GET *' }
    }
}
