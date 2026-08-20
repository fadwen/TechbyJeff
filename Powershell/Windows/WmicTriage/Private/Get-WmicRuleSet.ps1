function Get-WmicRuleSet {
    <#
    .SYNOPSIS
        Loads and validates the three data files that make up the ruleset

    .DESCRIPTION
        Reads Data\WmicRules.psd1, Data\WmicAliases.psd1 and Data\WmicProperties.psd1, checks
        them, and returns them as one object with the lookups the matcher needs already built.
        The result is cached for the module's lifetime, because a scan over a deployment share
        calls this once per file and the files never change mid-run.

        Validation is not decoration here. The whole design premise is that a new detection is a
        data change rather than a code change, which means a typo in the data file is the most
        likely way this module ever breaks. A rule with an unknown tier, or a Match key the
        engine does not implement, would otherwise fail open - it would simply never match, and
        the report would be quietly short by however many findings that rule was meant to catch.
        A scanner that undercounts is worse than one that does not run, so both are errors.

        The property index is inverted at load time: the data file lists properties by group,
        and the matcher needs to ask which groups a given property belongs to.

    .PARAMETER Force
        Rebuild the cache rather than returning it. Only useful in tests, and when editing the
        data files in a session that has already run a scan.

    .OUTPUTS
        A WmicTriage.RuleSet object carrying Rules, Aliases, Groups and PropertyIndex.

    .EXAMPLE
        $ruleSet = Get-WmicRuleSet

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType('WmicTriage.RuleSet')]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:RuleSet -and -not $Force) {
        return $script:RuleSet
    }

    $dataRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Data'

    $files = [ordered]@{
        Rules      = Join-Path -Path $dataRoot -ChildPath 'WmicRules.psd1'
        Aliases    = Join-Path -Path $dataRoot -ChildPath 'WmicAliases.psd1'
        Properties = Join-Path -Path $dataRoot -ChildPath 'WmicProperties.psd1'
    }

    $data = @{}
    foreach ($key in $files.Keys) {
        $path = $files[$key]
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Ruleset file is missing: $path. The module cannot scan without it."
        }
        try {
            $data[$key] = Import-PowerShellDataFile -LiteralPath $path -ErrorAction Stop
        }
        catch {
            throw "Ruleset file $path could not be parsed: $($_.Exception.Message)"
        }
    }

    # The Match keys the engine actually implements. Anything else in a rule is a typo, and a
    # typo that fails open produces an undercount rather than an error.
    $knownMatchKeys = @(
        'Region', 'Structure', 'Invocation', 'Capture', 'Verb', 'Switch',
        'Alias', 'AliasNonObvious', 'PropertyGroup', 'Context', 'Pattern', 'Snippet'
    )

    $groups = $data.Properties.Groups
    $seenIds = @{}
    $rules = @()

    foreach ($rule in $data.Rules.Rules) {
        foreach ($required in 'Id', 'Name', 'Reason', 'Suggestion') {
            if (-not $rule.ContainsKey($required) -or -not $rule[$required]) {
                throw "Rule '$($rule.Id)' is missing a $required. Every rule needs one - the report prints it."
            }
        }

        # Reason and Suggestion are prose, and prose does not fit the repository's 115-character
        # line limit. A .psd1 is restricted language, so the usual fix - concatenating with + -
        # is rejected by Import-PowerShellDataFile outright. Writing them as an array of lines
        # and joining here is what is left, and it also indents properly in the data file, which
        # a here-string would not: its terminator has to sit at column zero.
        $reason = if ($rule.Reason -is [array]) { $rule.Reason -join ' ' } else { [string]$rule.Reason }
        $suggestion = if ($rule.Suggestion -is [array]) {
            $rule.Suggestion -join ' '
        }
        else {
            [string]$rule.Suggestion
        }

        if ($seenIds.ContainsKey($rule.Id)) {
            throw "Rule id '$($rule.Id)' is used twice. Ids appear in SARIF output and must be unique."
        }
        $seenIds[$rule.Id] = $true

        if ($rule.ContainsKey('Tier') -and -not $script:TierRank.Contains($rule.Tier)) {
            throw ("Rule '$($rule.Id)' names tier '$($rule.Tier)', which is not one of " +
                ($script:TierRank.Keys -join ', ') + '.')
        }

        if (-not $rule.ContainsKey('Match')) {
            throw "Rule '$($rule.Id)' has no Match. Use an empty hashtable to match every invocation."
        }

        foreach ($matchKey in $rule.Match.Keys) {
            if ($knownMatchKeys -notcontains $matchKey) {
                throw ("Rule '$($rule.Id)' matches on '$matchKey', which the engine does not " +
                    'implement, so it would never fire. Known keys: ' + ($knownMatchKeys -join ', ') + '.')
            }
        }

        # A rule referencing a property group that does not exist would also fail open
        if ($rule.Match.ContainsKey('PropertyGroup')) {
            foreach ($groupName in $rule.Match.PropertyGroup) {
                if (-not $groups.ContainsKey($groupName)) {
                    throw ("Rule '$($rule.Id)' references property group '$groupName', which is " +
                        'not defined in WmicProperties.psd1.')
                }
            }
        }

        # Regexes are compiled once here so a bad pattern fails at load rather than on the one
        # unlucky file that happened to reach it
        foreach ($patternKey in 'Pattern', 'Snippet') {
            if ($rule.Match.ContainsKey($patternKey)) {
                try {
                    $null = [regex]::new($rule.Match[$patternKey])
                }
                catch {
                    throw "Rule '$($rule.Id)' has an invalid $patternKey regex: $($_.Exception.Message)"
                }
            }
        }

        $rules += [PSCustomObject]@{
            PSTypeName = 'WmicTriage.Rule'
            Id         = $rule.Id
            Name       = $rule.Name
            Kind       = if ($rule.ContainsKey('Kind')) { $rule.Kind } else { 'Deprecation' }
            Tier       = if ($rule.ContainsKey('Tier')) { $rule.Tier } else { $null }
            Rank       = if ($rule.ContainsKey('Tier')) { $script:TierRank[$rule.Tier] } else { 0 }
            Match      = $rule.Match
            Reason     = $reason
            Suggestion = $suggestion
        }
    }

    # Aliases are matched case-insensitively; WMIC never cared about case and neither did anyone
    # writing these scripts
    $aliases = @{}
    foreach ($name in $data.Aliases.Aliases.Keys) {
        $entry = $data.Aliases.Aliases[$name]
        $aliases[$name.ToLowerInvariant()] = [PSCustomObject]@{
            Alias      = $name
            Class      = $entry.Class
            NonObvious = [bool]($entry.ContainsKey('NonObvious') -and $entry.NonObvious)
        }
    }

    # Inverted: the data file is written by group because that is how a human maintains it, and
    # read by property because that is how the matcher asks
    $propertyIndex = @{}
    foreach ($groupName in $groups.Keys) {
        foreach ($property in $groups[$groupName]) {
            $key = $property.ToLowerInvariant()
            if (-not $propertyIndex.ContainsKey($key)) {
                $propertyIndex[$key] = @()
            }
            $propertyIndex[$key] += $groupName
        }
    }

    $script:RuleSet = [PSCustomObject]@{
        PSTypeName    = 'WmicTriage.RuleSet'
        SchemaVersion = $data.Rules.SchemaVersion
        Rules         = $rules
        Aliases       = $aliases
        Groups        = $groups
        PropertyIndex = $propertyIndex
    }

    Write-Verbose ("Loaded $($rules.Count) rules, $($aliases.Count) aliases, " +
        "$($propertyIndex.Count) indexed properties")

    return $script:RuleSet
}
