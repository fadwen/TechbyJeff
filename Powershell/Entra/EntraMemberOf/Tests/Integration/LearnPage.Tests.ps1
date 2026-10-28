#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Drift gate for the data file: fetches the current Learn page sources and checks the facts
    Data/MemberOfRules.psd1 states against them: the retirement date, the documented rule
    forms, the limits, and the page's ms.date.

    Opt-in, because it needs the network and the pages change: set ENTRAMEMBEROF_ONLINE=1 to
    run it. When it fails, Microsoft changed something; update the data file and VerifiedOn.
#>

#pester:no-parallel

$script:Online = $env:ENTRAMEMBEROF_ONLINE -eq '1'

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Data = Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'Data\MemberOfRules.psd1')
    $script:RawBase = 'https://github.com/MicrosoftDocs/entra-docs/raw/refs/heads/main/docs/'
}

Describe 'MemberOfRules.psd1 against the live Learn pages' `
    -Tag 'Integration', 'Online' -Skip:(-not $script:Online) {

    BeforeAll {
        $script:MemberOfPage = (Invoke-WebRequest -UseBasicParsing `
            -Uri ($script:RawBase + 'identity/users/groups-dynamic-rule-member-of.md')).Content
        $policyPath = 'id-governance/entitlement-management-access-package-auto-assignment-policy.md'
        $script:PolicyPage = (Invoke-WebRequest -UseBasicParsing -Uri ($script:RawBase + $policyPath)).Content
        $script:RetirementText = ([datetime]::ParseExact($script:Data.RetirementDate, 'yyyy-MM-dd',
                [cultureinfo]::InvariantCulture)).ToString('MMMM d, yyyy', [cultureinfo]::InvariantCulture)
    }

    It 'still gives the retirement date the data file records' {
        $script:MemberOfPage | Should-MatchString ([regex]::Escape($script:RetirementText))
        $script:PolicyPage | Should-MatchString ([regex]::Escape($script:RetirementText))
    }

    It 'has the ms.date the data file records' {
        $msDate = [regex]::Match($script:MemberOfPage, '(?m)^ms\.date:\s*(\S+)').Groups[1].Value
        $live = [datetime]::ParseExact($msDate, 'MM/dd/yyyy', [cultureinfo]::InvariantCulture)
        $live.ToString('yyyy-MM-dd') | Should-Be $script:Data.SourceDate
    }

    It 'still shows the two documented rule forms' {
        $retired = $script:Data.Retired
        foreach ($property in $retired.Properties) {
            $pattern = [regex]::Escape($property.ToLowerInvariant()) + '\s+-' + $retired.Quantifier +
                '\s+\(' + [regex]::Escape($retired.SourceProperty) + '\s+-' + $retired.Operator
            $script:MemberOfPage.ToLowerInvariant() | Should-MatchString $pattern
        }
    }

    It 'still states the limits the data file records' {
        $perTenant = $script:Data.Limits.MemberOfGroupsPerTenant
        $script:MemberOfPage | Should-MatchString "limited to $perTenant dynamic groups"
        $script:MemberOfPage | Should-MatchString "up to $($script:Data.Limits.SourceGroupsPerGroup) member groups"
        $script:MemberOfPage | Should-MatchString 'quota of 15,000'
    }

    It 'still says the objects stop updating and stay in their last known state' {
        $script:MemberOfPage | Should-MatchString 'stop updating'
        $script:MemberOfPage | Should-MatchString 'last known state'
    }

    It 'still finds auto-assignment policies by automaticRequestSettings and attributeRuleMembers' {
        # Microsoft's own script on the policy page is the reference for how the module picks
        # auto-assignment policies out of the assignment policy list
        $script:PolicyPage | Should-MatchString 'automaticRequestSettings'
        $script:PolicyPage | Should-MatchString 'attributeRuleMembers'
    }
}
