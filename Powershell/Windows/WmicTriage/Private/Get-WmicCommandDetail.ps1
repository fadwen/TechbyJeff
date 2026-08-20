function Get-WmicCommandDetail {
    <#
    .SYNOPSIS
        Parses a WMIC command into the alias, class, verb, properties and switches it names

    .DESCRIPTION
        Takes the command text and returns what it actually asks the system for. Everything the
        Semantic tier depends on comes from here, because that tier is defined by what is being
        read rather than by how the call is shaped: a datetime property, an array property, a
        method call, a remote node.

        Switches are lifted out in a first pass, before anything positional is attempted. WMIC
        accepts them almost anywhere - wmic /node:PC1 os get caption and wmic os get caption
        /format:csv are both ordinary - so a positional parser that assumed they came first would
        mis-read the second and hand back nonsense for the alias.

        Where-clauses are removed before the verb is looked for, then mined for property names.
        Removal first, because a filter can contain a word that reads as a verb; mining second,
        because a filter names properties as surely as a get does. where "DHCPEnabled=TRUE" is the
        Boolean tier case exactly, and it never appears after a get.

        The parse is tolerant on purpose. This module reports on other people's decade-old scripts
        rather than validating them, so an unrecognised shape yields whatever could be read and
        nulls elsewhere. A command that cannot be parsed still deserves its baseline Mechanical
        finding - failing to classify is not a reason to fail to report.

    .PARAMETER CommandText
        [System.String] (Mandatory, No Pipeline Support)

        The command, starting at the WMIC token.

    .PARAMETER RuleSet
        [System.Object] (Mandatory, No Pipeline Support)

        The loaded ruleset, for the alias table and the property group index.

    .OUTPUTS
        A hashtable with Alias, Class, ClassKnown, NonObvious, Verb, Method, Properties,
        PropertyGroup, Switches, SwitchName, Node and Filter.

    .EXAMPLE
        $detail = Get-WmicCommandDetail -CommandText 'wmic nicconfig get IPAddress' -RuleSet $ruleSet

        DESCRIPTION: Parses a call that reads an array-valued property
        OUTPUT: Class Win32_NetworkAdapterConfiguration, PropertyGroup MultiValue
        USE CASE: Driving the Semantic tier and naming the target class in the suggestion

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CommandText,

        [Parameter(Mandatory)]
        [object]$RuleSet
    )

    $detail = @{
        Alias         = $null
        Class         = $null
        ClassKnown    = $false
        NonObvious    = $false
        Verb          = $null
        Method        = $null
        Properties    = @()
        PropertyGroup = @()
        Switches      = @{}
        SwitchName    = @()
        Node          = $null
        Filter        = $null
    }

    $rest = $CommandText -replace '^\s*\S*?wmic(\.exe)?\s*', ''
    if ([string]::IsNullOrWhiteSpace($rest)) { return $detail }

    # Switches first: WMIC takes them anywhere, so nothing positional is safe until they are gone
    $switchPattern = '(?<![\w])/(?<name>[A-Za-z]+)(?::(?<value>"[^"]*"|''[^'']*''|\S+))?'
    foreach ($match in [regex]::Matches($rest, $switchPattern)) {
        $name = $match.Groups['name'].Value.ToLowerInvariant()
        $value = $match.Groups['value'].Value.Trim('"', "'")
        $detail.Switches[$name] = if ($value) { $value } else { $true }
    }
    $detail.SwitchName = @($detail.Switches.Keys)
    if ($detail.Switches.ContainsKey('node')) { $detail.Node = [string]$detail.Switches['node'] }

    $rest = [regex]::Replace($rest, $switchPattern, ' ')

    # Where-clause out before the verb search, and mined for property names after
    $whereMatch = [regex]::Match($rest,
        '(?i)(?<![\w])where\s*(?<filter>\((?:[^()]|\([^()]*\))*\)|"[^"]*"|''[^'']*''|\S+)')
    $whereProperties = @()
    if ($whereMatch.Success) {
        $filter = $whereMatch.Groups['filter'].Value.Trim()
        $filter = $filter -replace '^\(', '' -replace '\)$', ''
        $detail.Filter = $filter.Trim('"', "'")

        foreach ($property in [regex]::Matches($detail.Filter,
                '(?i)(?<![\w])(?<name>[A-Za-z_]\w*)\s*(?:=|<>|<=|>=|<|>|\blike\b)')) {
            $whereProperties += $property.Groups['name'].Value
        }

        $rest = $rest.Remove($whereMatch.Index, $whereMatch.Length)
    }

    # Wrapped in @() because a function returning a one-element array hands back a bare string,
    # and indexing a string returns a char - so $tokens[$i].ToLowerInvariant() throws on any
    # command that parses down to a single token
    $tokens = @(Split-WmicCommandToken -Text $rest)
    if ($tokens.Count -eq 0) {
        $detail.Properties = @($whereProperties | Select-Object -Unique)
        $detail.PropertyGroup = @(Get-WmicPropertyGroup -Property $detail.Properties -RuleSet $RuleSet)
        return $detail
    }

    $verbs = @('get', 'list', 'call', 'set', 'create', 'delete', 'assoc', 'associators', 'references')
    $verbIndex = -1
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($verbs -contains $tokens[$i].ToLowerInvariant()) {
            $verbIndex = $i
            break
        }
    }

    # Wrapped in @() deliberately. A single-token head arrives as a bare string, and indexing a
    # string returns a char, so $head[0].ToLowerInvariant() throws on the most ordinary command
    # this module will ever see.
    $head = @(if ($verbIndex -ge 0) { $tokens[0..([Math]::Max(0, $verbIndex - 1))] } else { $tokens })
    if ($verbIndex -eq 0) { $head = @() }

    # An alias is a bare identifier. Anything else in this position is debris from the shell that
    # wrapped the call - a PowerShell parameter, a fragment of a quoted argument list - and
    # putting it in the report as the alias would be worse than admitting the class is unknown,
    # because a wrong class name reads as a fact rather than a gap.
    $identifierPattern = '^[A-Za-z][\w]*$'

    if ($head.Count -gt 0) {
        $first = $head[0].ToLowerInvariant()

        if (($first -eq 'path' -or $first -eq 'class') -and $head.Count -gt 1) {
            # \\.\root\cimv2:Win32_Service - the class is whatever follows the namespace, and the
            # namespace is why this token cannot be filtered as an identifier before it is split
            $target = $head[1]
            if ($target.Contains(':')) { $target = $target.Substring($target.LastIndexOf(':') + 1) }
            if ($target -match $identifierPattern) {
                $detail.Class = $target
                $detail.ClassKnown = $true
            }
        }
        elseif ($first -ne 'alias' -and $first -ne 'context') {
            $candidate = @($head | Where-Object { $_ -match $identifierPattern })[0]
            if ($candidate) {
                $detail.Alias = $candidate
                $known = $RuleSet.Aliases[$candidate.ToLowerInvariant()]
                if ($null -ne $known) {
                    $detail.Class = $known.Class
                    $detail.ClassKnown = $true
                    $detail.NonObvious = $known.NonObvious
                }
                else {
                    # An alias the table does not carry may still be a class name written directly
                    $detail.Class = $candidate
                }
            }
        }
    }

    $properties = @()

    if ($verbIndex -ge 0) {
        $detail.Verb = $tokens[$verbIndex].ToLowerInvariant()
        $arguments = @()
        if ($verbIndex + 1 -lt $tokens.Count) {
            $arguments = $tokens[($verbIndex + 1)..($tokens.Count - 1)]
        }

        switch ($detail.Verb) {
            'get' {
                foreach ($argument in $arguments) {
                    if ($argument.StartsWith('/')) { continue }
                    foreach ($name in ($argument -split ',')) {
                        if ($name.Trim()) { $properties += $name.Trim() }
                    }
                }
            }
            'set' {
                foreach ($argument in $arguments) {
                    $assignment = $argument -split '=', 2
                    if ($assignment[0].Trim()) { $properties += $assignment[0].Trim() }
                }
            }
            'call' {
                if ($arguments.Count -gt 0) { $detail.Method = $arguments[0] }
            }
            default {
                # list brief, list full, create, delete: the arguments are modes rather than
                # property names, and treating them as properties would poison the group lookup
            }
        }
    }

    $detail.Properties = @(($properties + $whereProperties) | Where-Object { $_ } | Select-Object -Unique)
    $detail.PropertyGroup = @(Get-WmicPropertyGroup -Property $detail.Properties -RuleSet $RuleSet)

    return $detail
}
