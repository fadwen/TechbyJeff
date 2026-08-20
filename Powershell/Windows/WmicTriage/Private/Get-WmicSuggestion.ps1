function Get-WmicSuggestion {
    <#
    .SYNOPSIS
        Fills a rule's suggestion template from the parsed command

    .DESCRIPTION
        Substitutes the placeholders in a rule's Suggestion with what was actually read from the
        call, so the advice names the class and properties in front of the reader rather than
        describing the shape of an answer.

        Nothing here applies anything, and nothing here is claimed to be correct. The output goes
        into a column marked advisory, and for the Wrapped tier the template deliberately says to
        restructure rather than offering a command, because a one-liner would be a lie about work
        that spans a block. That restraint is what lets the substitution be printed at all - a
        tool that offered to apply these would have to be right, and on the Semantic tier nothing
        can be.

        A placeholder with nothing behind it becomes an angle-bracketed name rather than an empty
        string, so the reader gets Get-CimInstance -ClassName <class> and can see at a glance that
        the tool could not work the class out, instead of a command that looks complete and is not.

    .PARAMETER Template
        [System.String] (Mandatory, No Pipeline Support)

        The rule's Suggestion text.

    .PARAMETER Detail
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The parsed command from Get-WmicCommandDetail.

    .OUTPUTS
        System.String - the filled suggestion.

    .EXAMPLE
        Get-WmicSuggestion -Template 'Get-CimInstance -ClassName {Class}' -Detail $detail

        DESCRIPTION: Fills the baseline Mechanical suggestion
        OUTPUT: Get-CimInstance -ClassName Win32_QuickFixEngineering
        USE CASE: The SuggestedReplacement column of the report

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Template,

        [Parameter(Mandatory)]
        [hashtable]$Detail
    )

    if ([string]::IsNullOrWhiteSpace($Template)) { return '' }

    $properties = '*'
    if ($Detail.Properties -and $Detail.Properties.Count -gt 0) {
        $properties = ($Detail.Properties -join ', ')
    }

    $replacements = @{
        '{Class}'      = if ($Detail.Class) { $Detail.Class } else { '<class>' }
        '{Alias}'      = if ($Detail.Alias) { $Detail.Alias } else { '<alias>' }
        '{Properties}' = $properties
        '{Node}'       = if ($Detail.Node) { $Detail.Node } else { '<computer>' }
        '{Verb}'       = if ($Detail.Verb) { $Detail.Verb } else { '<verb>' }
        '{Method}'     = if ($Detail.Method) { $Detail.Method } else { '<method>' }
        '{Filter}'     = if ($Detail.Filter) { $Detail.Filter } else { '<filter>' }
    }

    $result = $Template
    foreach ($placeholder in $replacements.Keys) {
        $result = $result.Replace($placeholder, [string]$replacements[$placeholder])
    }

    return $result
}
