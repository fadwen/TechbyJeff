#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Drift gate for the data file: fetches the current Learn page source and compares its
    "Deprecated properties" bullets with Data/RetiredProperties.psd1.

    Opt-in, because it needs the network and the page can change under it: set
    ENTRABRANDINGCSS_ONLINE=1 to run it. When it fails, Microsoft changed the list; update the
    data file, SourceDate and the README count, in that order.
#>

#pester:no-parallel

$script:Online = $env:ENTRABRANDINGCSS_ONLINE -eq '1'

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:DataPath = Join-Path $script:ModuleRoot 'Data\RetiredProperties.psd1'
    $script:RawUrl = 'https://github.com/MicrosoftDocs/entra-docs/raw/refs/heads/main/' +
        'docs/fundamentals/reference-company-branding-css-template.md'
}

Describe 'RetiredProperties.psd1 against the live Learn page' `
    -Tag 'Integration', 'Online' -Skip:(-not $script:Online) {

    BeforeAll {
        $script:Markdown = (Invoke-WebRequest -Uri $script:RawUrl -UseBasicParsing).Content
        $script:Data = Import-PowerShellDataFile $script:DataPath

        # Bullets between "### Deprecated properties" and the next heading. Each is
        # "- `name`" with an optional "(including `a`, `b`, and `c`)".
        $section = [regex]::Match($script:Markdown, '(?s)### Deprecated properties(.*?)\n###').Groups[1].Value
        $script:Bullets = @([regex]::Matches($section, '(?m)^- `([^`]+)`(.*)$') | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.Groups[1].Value
                Included = @([regex]::Matches($_.Groups[2].Value, '`([^`]+)`') |
                    ForEach-Object { $_.Groups[1].Value })
            }
        })
        $script:LiveNames = @($script:Bullets | ForEach-Object { @($_.Name) + $_.Included })
        $script:MsDate = [regex]::Match($script:Markdown, '(?m)^ms\.date:\s*(\S+)').Groups[1].Value
    }

    It 'found the section' {
        $script:Bullets.Count | Should-BeGreaterThan 0
    }

    It 'lists exactly the names in the data file' {
        $expected = @($script:Data.Retired | ForEach-Object Property | Sort-Object)
        @($script:LiveNames | Sort-Object) | Should-BeCollection $expected
    }

    It 'folds the same longhands under the same bullets' {
        foreach ($bullet in $script:Bullets) {
            $inData = @($script:Data.Retired | Where-Object Bullet -eq $bullet.Name |
                ForEach-Object Property | Sort-Object)
            $onPage = @(@($bullet.Name) + $bullet.Included | Sort-Object)
            $inData | Should-BeCollection $onPage
        }
    }

    It 'has the ms.date the data file records' {
        $live = [datetime]::ParseExact($script:MsDate, 'MM/dd/yyyy', [cultureinfo]::InvariantCulture)
        $live.ToString('yyyy-MM-dd') | Should-Be $script:Data.SourceDate
    }
}
