#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The public command, in both modes.

    File mode runs against the fixtures under Tests/Fixtures, each of which documents its own
    expected findings in a leading comment. Tenant mode runs against a scripted request
    handler, so no test here reaches Graph; the one file that does is under Tests/Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'EntraBrandingCss.psd1') -Force
    $script:Fixtures = Join-Path $script:ModuleRoot 'Tests\Fixtures'

    function Get-Fixture([string]$Name) { Join-Path $script:Fixtures $Name }
}

AfterAll {
    Remove-Module EntraBrandingCss -Force -ErrorAction SilentlyContinue
}

Describe 'Test-EntraBrandingCss file mode' -Tag 'Unit', 'Public', 'FileMode' {

    Context 'fixture summaries' {

        It 'reports <Name> as <Status> with <Retired> retired and <Review> review' -ForEach @(
            @{ Name = 'all-retired.css';           Status = 'Retired';     Retired = 58; Review = 0 }
            @{ Name = 'false-positives.css';       Status = 'Review';      Retired = 0;  Review = 2 }
            @{ Name = 'values-not-properties.css'; Status = 'Retired';     Retired = 1;  Review = 0 }
            @{ Name = 'comments.css';              Status = 'Retired';     Retired = 2;  Review = 0 }
            @{ Name = 'nested-at-rules.css';       Status = 'Retired';     Retired = 5;  Review = 0 }
            @{ Name = 'minified.css';              Status = 'Retired';     Retired = 5;  Review = 0 }
            @{ Name = 'crlf.css';                  Status = 'Retired';     Retired = 1;  Review = 0 }
            @{ Name = 'bom.css';                   Status = 'Retired';     Retired = 1;  Review = 0 }
            @{ Name = 'escaped.css';               Status = 'Retired';     Retired = 4;  Review = 0 }
            @{ Name = 'demo-branding.css';         Status = 'Retired';     Retired = 2;  Review = 0 }
            @{ Name = 'empty.css';                 Status = 'NoCustomCss'; Retired = 0;  Review = 0 }
        ) {
            $result = Test-EntraBrandingCss -Path (Get-Fixture $Name)

            $result.PSObject.TypeNames | Should-ContainCollection 'EntraBrandingCss.Result'
            $result.Name | Should-Be $Name
            $result.SourceType | Should-Be 'File'
            $result.Status | Should-Be $Status
            $result.RetiredCount | Should-Be $Retired
            $result.ReviewCount | Should-Be $Review
            @($result.Findings).Count | Should-Be ($Retired + $Review)
        }
    }

    Context 'the retired list' {

        It 'finds every one of the 58 retired names in all-retired.css, each exactly once' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'all-retired.css')
            $found = @($result.Findings | Where-Object Level -eq 'Retired' | ForEach-Object Property | Sort-Object)
            $expected = @(Get-EntraBrandingCssProperty -Level Retired | ForEach-Object Property | Sort-Object)

            $found | Should-BeCollection $expected
        }

        It 'reports zero retired findings for every required non-match' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'false-positives.css')
            @($result.Findings | Where-Object Level -eq 'Retired').Count | Should-Be 0
            $result.DeclarationCount | Should-BeGreaterThan 20
        }

        It 'flags the inset logical forms for review, and nothing else in that file' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'false-positives.css')
            @($result.Findings | ForEach-Object Property | Sort-Object) |
                Should-BeCollection @('inset-block', 'inset-inline')
            $result.Findings | Should-All { $_.Level -eq 'Review' -and -not [string]::IsNullOrWhiteSpace($_.Note) }
        }

        It 'never matches a retired name that appears only as a value, in a string or in url()' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'values-not-properties.css')
            @($result.Findings).Count | Should-Be 1
            $result.Findings[0].Property | Should-Be 'transform'
            $result.Findings[0].Line | Should-Be 6
        }

        It 'stamps where each retired name was first announced' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'demo-branding.css')
            $result.Findings | Should-All { $_.FirstListedIn -eq 'Learn' }
        }
    }

    Context 'finding detail' {

        It 'ignores commented-out declarations and reports the live ones with their lines' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'comments.css')
            $lines = @($result.Findings | ForEach-Object { "$($_.Property)@$($_.Line)" })
            $lines | Should-BeCollection @('opacity@12', 'display@22')
        }

        It 'records the at-rule chain for nested blocks' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'nested-at-rules.css')
            $byProperty = @{}
            foreach ($finding in $result.Findings) { $byProperty[$finding.Property] = $finding }

            $byProperty['display'].AtRule | Should-Be '@media (max-width: 600px)'
            $byProperty['position'].AtRule | Should-Be '@media (max-width: 600px) > @supports (position: sticky)'
            $byProperty['margin'].AtRule | Should-Be '@container sidebar (min-width: 400px)'
            $byProperty['opacity'].AtRule | Should-Be '@layer branding'
            $byProperty['visibility'].AtRule | Should-Be ''
            $byProperty['visibility'].Selector | Should-Be '& .ext-link'
        }

        It 'reports the selector, value and importance for the demo file' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'demo-branding.css')
            $result.Findings[0].Selector | Should-Be '#cantAccessAccount, .ext-sign-in-box a[href*="password"]'
            $result.Findings[0].Important | Should-BeFalse
            $result.Findings[1].Selector | Should-Be '.ext-footer-links'
            $result.Findings[1].Value | Should-Be 'none'
            $result.Findings[1].Important | Should-BeTrue
            $result.Findings | Should-All { $_.PSObject.TypeNames -contains 'EntraBrandingCss.Finding' }
            $result.Findings | Should-All { $_.Source -eq $result.Source }
        }

        It 'reports escaped names under their decoded name with a note' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'escaped.css')
            @($result.Findings | ForEach-Object Property) |
                Should-BeCollection @('position', 'display', 'margin', 'opacity')
            $result.Findings | Should-All { $_.Note -match 'decoded from CSS escapes' }
            $result.Findings[0].Note | Should-MatchString ([regex]::Escape('\70 osition'))
        }
    }

    Context 'encodings' {

        It 'keeps the CRLF fixture byte-exact and reports line 3' {
            $bytes = [System.IO.File]::ReadAllBytes((Get-Fixture 'crlf.css'))
            [System.Text.Encoding]::ASCII.GetString($bytes) | Should-MatchString "`r`n"

            $result = Test-EntraBrandingCss -Path (Get-Fixture 'crlf.css')
            $result.Findings[0].Line | Should-Be 3
            $result.Findings[0].Column | Should-Be 5
        }

        It 'keeps the BOM fixture byte-exact and reports line 1 at the right column' {
            $bytes = [System.IO.File]::ReadAllBytes((Get-Fixture 'bom.css'))
            @($bytes[0], $bytes[1], $bytes[2]) | Should-BeCollection @([byte]0xEF, [byte]0xBB, [byte]0xBF)

            $result = Test-EntraBrandingCss -Path (Get-Fixture 'bom.css')
            $result.Findings[0].Line | Should-Be 1
            $result.Findings[0].Column | Should-Be 15
        }

        It 'reports an empty file as NoCustomCss, not Clean' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'empty.css')
            $result.Status | Should-Be 'NoCustomCss'
            $result.HasCustomCss | Should-BeFalse
            $result.DeclarationCount | Should-Be 0
        }

        It 'reports a file with CSS and no findings as Clean' {
            $clean = Join-Path $TestDrive 'clean.css'
            Set-Content -Path $clean -Value '.ext-sign-in-box { color: #222; background-color: white; }'

            $result = Test-EntraBrandingCss -Path $clean
            $result.Status | Should-Be 'Clean'
            $result.HasCustomCss | Should-BeTrue
            $result.DeclarationCount | Should-Be 2
        }
    }

    Context 'input handling' {

        It 'takes Get-ChildItem output from the pipeline, one result per file' {
            $files = @(Get-ChildItem (Join-Path $script:Fixtures '*.css'))
            $results = @($files | Test-EntraBrandingCss)
            $results.Count | Should-Be 11
            $results | Should-All { $_.Source -like '*Tests?Fixtures?*.css' }
            @($results | ForEach-Object Name | Sort-Object) |
                Should-BeCollection @($files | ForEach-Object Name | Sort-Object)
        }

        It 'takes path strings from the pipeline' {
            $results = @((Get-Fixture 'bom.css'), (Get-Fixture 'crlf.css') | Test-EntraBrandingCss)
            $results.Count | Should-Be 2
        }

        It 'expands a wildcard path' {
            $results = @(Test-EntraBrandingCss -Path (Join-Path $script:Fixtures 'c*.css'))
            @($results | ForEach-Object Name | Sort-Object) | Should-BeCollection @('comments.css', 'crlf.css')
        }

        It 'writes a non-terminating error for a missing file and continues' {
            $paths = @((Join-Path $TestDrive 'missing.css'), (Get-Fixture 'bom.css'))
            $results = @(Test-EntraBrandingCss -Path $paths -ErrorAction SilentlyContinue -ErrorVariable err)

            $results.Count | Should-Be 1
            @($err).Count | Should-Be 1
            "$err" | Should-MatchString 'missing\.css'
        }

        It 'writes an error for a directory rather than scanning nothing silently' {
            Test-EntraBrandingCss -Path $script:Fixtures -ErrorAction SilentlyContinue -ErrorVariable err
            "$err" | Should-MatchString 'directory'
        }

        It 'has no tenant properties set in file mode' {
            $result = Test-EntraBrandingCss -Path (Get-Fixture 'bom.css')
            $result.CustomCssRelativeUrl | Should-BeNull
            $result.Error | Should-BeNull
        }
    }
}

Describe 'Test-EntraBrandingCss tenant mode' -Tag 'Unit', 'Public', 'TenantMode' {

    BeforeAll {
        $script:TenantId = '11111111-2222-3333-4444-555555555555'
        $script:DemoCss = [System.IO.File]::ReadAllText((Get-Fixture 'demo-branding.css'))
        $script:V1 = "https://graph.microsoft.com/v1.0/organization/$script:TenantId/branding"
        $script:Beta = "https://graph.microsoft.com/beta/organization/$script:TenantId/branding"

        # A scripted tenant. The default locale has custom CSS, fr-FR has none (null stream),
        # de-DE has none (404), es-ES fails for another reason. One theme with two locales.
        #
        # Everything the handler reads is a local captured by GetNewClosure. A $script: variable
        # inside a closure refers to the closure's own dynamic module, not this file, and reads
        # as null.
        function Get-TenantHandler {
            param([switch]$AsHashtable)

            $calls = [System.Collections.Generic.List[string]]::new()
            $script:Calls = $calls
            $tenantId = $script:TenantId
            $demoCss = $script:DemoCss
            $asHashtable = $AsHashtable.IsPresent
            $notFound = 'Response status code does not indicate success: NotFound (Not Found).'
            $forbidden = 'Response status code does not indicate success: Forbidden (Forbidden).'
            $toObject = {
                param($Hashtable)
                if ($asHashtable) { return $Hashtable }
                return [PSCustomObject]$Hashtable
            }

            return {
                param($Uri)
                $calls.Add($Uri)

                switch -Regex ($Uri) {
                    '/v1\.0/organization\?' {
                        return & $toObject @{ value = @((& $toObject @{ id = $tenantId })) }
                    }
                    "/v1\.0/organization/$tenantId/branding/localizations$" {
                        return & $toObject @{ value = @(
                            (& $toObject @{
                                id = '0'
                                customCSSRelativeUrl = 'abc/logintenantbranding/0/customcss?ts=1'
                                cdnList = @('aadcdn.msauthimages.net')
                            })
                            (& $toObject @{ id = 'fr-FR'; customCSSRelativeUrl = $null; cdnList = @() })
                            (& $toObject @{ id = 'de-DE'; customCSSRelativeUrl = $null; cdnList = @() })
                            (& $toObject @{
                                id = 'es-ES'
                                customCSSRelativeUrl = 'abc/logintenantbranding/3082/customcss?ts=1'
                                cdnList = @()
                            })
                        ) }
                    }
                    '/localizations/0/customCSS$' { return $demoCss }
                    '/localizations/fr-FR/customCSS$' { return $null }
                    '/localizations/de-DE/customCSS$' { throw $notFound }
                    '/localizations/es-ES/customCSS$' { throw $forbidden }
                    "/beta/organization/$tenantId/branding/themes$" {
                        return & $toObject @{
                            value = @((& $toObject @{ id = 'theme-1'; name = 'Contoso'; isDefaultTheme = $true }))
                        }
                    }
                    '/themes/theme-1/localizations$' {
                        return & $toObject @{ value = @(
                            (& $toObject @{ locale = 'en-US'; customCSSRelativeUrl = 'abc/theme/customcss' })
                            (& $toObject @{ locale = 'nl-NL'; customCSSRelativeUrl = $null })
                        ) }
                    }
                    '/themes/theme-1/localizations/en-US/customCSS$' { return '.ext-header { margin: 0 }' }
                    '/themes/theme-1/localizations/nl-NL/customCSS$' { return '' }
                }
                throw "Unexpected request in test handler: $Uri"
            }.GetNewClosure()
        }
    }

    Context 'company branding localizations' {

        BeforeEach {
            $script:Results = @(Test-EntraBrandingCss -Tenant -RequestHandler (Get-TenantHandler) `
                -ErrorAction SilentlyContinue -ErrorVariable script:Errors)
        }

        It 'returns one result per localization, in list order' {
            @($script:Results | ForEach-Object Name) | Should-BeCollection @('0', 'fr-FR', 'de-DE', 'es-ES')
            $script:Results | Should-All { $_.SourceType -eq 'Localization' }
        }

        It 'names each source by its Graph path under the tenant' {
            $script:Results[0].Source | Should-Be "$script:TenantId/branding/localizations/0"
            $script:Results[1].Source | Should-Be "$script:TenantId/branding/localizations/fr-FR"
        }

        It 'scans the default locale and finds the demo file''s two retired declarations' {
            $script:Results[0].Status | Should-Be 'Retired'
            $script:Results[0].RetiredCount | Should-Be 2
            $script:Results[0].CustomCssRelativeUrl | Should-Be 'abc/logintenantbranding/0/customcss?ts=1'
        }

        It 'reports a locale whose stream is empty as NoCustomCss' {
            $script:Results[1].Status | Should-Be 'NoCustomCss'
            $script:Results[1].HasCustomCss | Should-BeFalse
        }

        It 'reports a locale whose stream returns 404 as NoCustomCss, not as an error' {
            $script:Results[2].Status | Should-Be 'NoCustomCss'
            $script:Results[2].Error | Should-BeNull
        }

        It 'reports any other stream failure as Error, with the message, and keeps going' {
            $script:Results[3].Status | Should-Be 'Error'
            $script:Results[3].Error | Should-MatchString 'Forbidden'
            $script:Results[3].HasCustomCss | Should-BeNull
            # -ErrorVariable also collects the exceptions thrown and caught further down, so
            # count only what this command wrote
            $written = @($script:Errors | Where-Object { "$_" -like 'Could not read *' })
            $written.Count | Should-Be 1
            "$written" | Should-MatchString 'es-ES'
            "$written" | Should-MatchString 'Forbidden'
        }

        It 'reads the organization, the list, and one stream per locale, all under v1.0' {
            $script:Calls.Count | Should-Be 6
            $script:Calls[0] | Should-MatchString '/v1\.0/organization\?\$select=id,displayName$'
            $script:Calls[1] | Should-Be "$script:V1/localizations"
            $script:Calls | Should-All { $_ -like 'https://graph.microsoft.com/v1.0/*' }
        }

        It 'does not touch the beta API unless asked' {
            $script:Calls | Should-All { $_ -notlike '*/beta/*' }
        }
    }

    Context 'branding themes' {

        BeforeEach {
            $script:Results = @(Test-EntraBrandingCss -Tenant -IncludeTheme -RequestHandler (Get-TenantHandler) `
                -ErrorAction SilentlyContinue)
        }

        It 'appends one result per theme localization after the company branding ones' {
            $themes = @($script:Results | Where-Object SourceType -eq 'Theme')
            $themes.Count | Should-Be 2
            @($themes | ForEach-Object Name) | Should-BeCollection @('Contoso (en-US)', 'Contoso (nl-NL)')
            $themes[0].Source | Should-Be "$script:TenantId/branding/themes/theme-1/localizations/en-US"
        }

        It 'scans theme CSS with the same scanner' {
            $themes = @($script:Results | Where-Object SourceType -eq 'Theme')
            $themes[0].Status | Should-Be 'Retired'
            $themes[0].Findings[0].Property | Should-Be 'margin'
            $themes[1].Status | Should-Be 'NoCustomCss'
        }

        It 'uses the documented beta endpoints and nothing else under beta' {
            $beta = @($script:Calls | Where-Object { $_ -like '*/beta/*' })
            $beta | Should-BeCollection @(
                "$script:Beta/themes"
                "$script:Beta/themes/theme-1/localizations"
                "$script:Beta/themes/theme-1/localizations/en-US/customCSS"
                "$script:Beta/themes/theme-1/localizations/nl-NL/customCSS"
            )
        }
    }

    Context 'options and failure modes' {

        It 'skips the organization lookup when -OrganizationId is given' {
            $handler = Get-TenantHandler
            $null = Test-EntraBrandingCss -Tenant -OrganizationId $script:TenantId -RequestHandler $handler `
                -ErrorAction SilentlyContinue
            $script:Calls[0] | Should-Be "$script:V1/localizations"
        }

        It 'rejects an organization id that is not a GUID' {
            $handler = Get-TenantHandler
            { Test-EntraBrandingCss -Tenant -OrganizationId 'contoso.com' -RequestHandler $handler } |
                Should-Throw
        }

        It 'reads hashtable responses as well as objects' {
            $results = @(Test-EntraBrandingCss -Tenant -RequestHandler (Get-TenantHandler -AsHashtable) `
                -ErrorAction SilentlyContinue)
            $results[0].Status | Should-Be 'Retired'
            $results[0].CustomCssRelativeUrl | Should-Be 'abc/logintenantbranding/0/customcss?ts=1'
        }

        It 'stops when the organization lookup returns more than one tenant' {
            $handler = {
                [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'a' }, [PSCustomObject]@{ id = 'b' }) }
            }
            { Test-EntraBrandingCss -Tenant -RequestHandler $handler } |
                Should-Throw -ExceptionMessage '*Pass -OrganizationId*'
        }

        It 'reports the tenant itself as NoCustomCss when the localizations list is <Shape>' -ForEach @(
            @{ Shape = 'empty'; ListThrows = $false }
            @{ Shape = '404';   ListThrows = $true }
        ) {
            # A tenant that never configured branding has no localizations. The observed shape
            # is an empty collection; 404 is handled the same way.
            $tenantId = $script:TenantId
            $listThrows = $ListThrows
            $handler = {
                param($Uri)
                if ($Uri -match '/organization\?') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = $tenantId; displayName = 'Contoso Dev' })
                    }
                }
                if ($Uri -like '*/branding/localizations' -and -not $listThrows) {
                    return [PSCustomObject]@{ value = @() }
                }
                throw 'Response status code does not indicate success: NotFound (Not Found).'
            }.GetNewClosure()
            $results = @(Test-EntraBrandingCss -Tenant -IncludeTheme -RequestHandler $handler)

            $results.Count | Should-Be 1
            $results[0].SourceType | Should-Be 'Tenant'
            $results[0].Status | Should-Be 'NoCustomCss'
            $results[0].HasCustomCss | Should-BeFalse
            $results[0].Source | Should-Be "$tenantId/branding"
            $results[0].Name | Should-Be 'Contoso Dev'
            $results[0].DeclarationCount | Should-Be 0
        }

        It 'explains what to install when no handler is given and the Graph SDK is absent' {
            InModuleScope EntraBrandingCss {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Invoke-MgGraphRequest' }
                { Invoke-EntraBrandingRequest -Uri 'https://graph.microsoft.com/v1.0/organization' } |
                    Should-Throw -ExceptionMessage '*Microsoft.Graph.Authentication*'
            }
        }

        It 'refuses a URI outside graph.microsoft.com' {
            InModuleScope EntraBrandingCss {
                { Invoke-EntraBrandingRequest -Uri 'https://example.com/x' -RequestHandler { 'x' } } | Should-Throw
            }
        }
    }
}
