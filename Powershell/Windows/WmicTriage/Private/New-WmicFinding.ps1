function New-WmicFinding {
    <#
    .SYNOPSIS
        Assembles one finding object from everything the pipeline worked out about a call

    .DESCRIPTION
        The single place a finding is constructed, so every property exists on every finding
        whatever path produced it. A report that has to test for the presence of a column is a
        report nobody automates against, and Export-Csv in particular takes its headers from the
        first object it sees and silently drops anything the later ones added.

        FailsBuild is computed here rather than left to the caller. It is the module's answer to
        the exit-code question, and answering it in one place stops it drifting: true for a
        Mechanical or Wrapped finding in real code, false for Semantic and Environmental because
        both end in a judgment a build cannot make, and false for anything found in a comment
        because a comment does not run. A module must not call exit - terminating the host of
        whatever imported you is not a decision a library gets to make - so a caller reads this
        property and decides.

    .PARAMETER File
        [System.Object] (Mandatory, No Pipeline Support)

        The scan file record, for its path and type.

    .PARAMETER Region
        [System.Object] (Mandatory, No Pipeline Support)

        The region the call sits in.

    .PARAMETER Invocation
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The invocation from Get-WmicInvocation.

    .PARAMETER Detail
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The parsed command.

    .PARAMETER Evaluation
        [System.Collections.Hashtable] (Mandatory, No Pipeline Support)

        The result from Resolve-WmicTier.

    .PARAMETER Rule
        [System.Object] (Optional, No Pipeline Support)

        Overrides the rule the finding reports. Used for security findings, which are raised
        against their own rule rather than the one that set the tier.

    .PARAMETER Kind
        [System.String] (Optional, No Pipeline Support)

        Deprecation or Security. Defaults to Deprecation.

    .PARAMETER Context
        [System.String[]] (Optional, No Pipeline Support)

        The contexts that applied.

    .OUTPUTS
        A WmicTriage.Finding object.

    .EXAMPLE
        $finding = New-WmicFinding -File $file -Region $region -Invocation $call `
            -Detail $detail -Evaluation $evaluation

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    # New is the approved verb for building an object, and PSScriptAnalyzer cannot tell that from
    # a New that provisions something. This function composes a PSCustomObject in memory and
    # touches nothing, so there is no state for ShouldProcess to guard.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object; changes no state')]
    [CmdletBinding()]
    [OutputType('WmicTriage.Finding')]
    param(
        [Parameter(Mandatory)]
        [object]$File,

        [Parameter(Mandatory)]
        [object]$Region,

        [Parameter(Mandatory)]
        [hashtable]$Invocation,

        [Parameter(Mandatory)]
        [hashtable]$Detail,

        [Parameter(Mandatory)]
        [hashtable]$Evaluation,

        [Parameter()]
        [AllowNull()]
        [object]$Rule,

        [Parameter()]
        [ValidateSet('Deprecation', 'Security')]
        [string]$Kind = 'Deprecation',

        [Parameter()]
        [AllowNull()]
        [string[]]$Context
    )

    $tier = $Evaluation.Tier
    $ruleId = $Evaluation.RuleId
    $ruleName = $Evaluation.Rule
    $reason = $Evaluation.Reason
    $template = $Evaluation.Suggestion

    if ($Rule) {
        $ruleId = $Rule.Id
        $ruleName = $Rule.Name
        $reason = $Rule.Reason
        $template = $Rule.Suggestion
        if ($Rule.Tier) { $tier = $Rule.Tier }
    }

    $failsBuild = ($Region.Kind -eq 'Code') -and ($script:FailingTiers -contains $tier)

    # A security finding is never the reason a build fails on WMIC deprecation - it is a separate
    # problem reported at the same time, and conflating them lets one hide the other
    if ($Kind -eq 'Security') { $failsBuild = $false }

    $stepName = $null
    $forOptions = $null
    if ($Region.Detail) {
        if ($Region.Detail.ContainsKey('StepName')) { $stepName = $Region.Detail.StepName }
        if ($Region.Detail.ContainsKey('ForOptions')) { $forOptions = $Region.Detail.ForOptions }
    }

    [PSCustomObject]@{
        PSTypeName           = 'WmicTriage.Finding'
        Tier                 = $tier
        Kind                 = $Kind
        RelativePath         = $File.RelativePath
        Path                 = $File.Path
        Line                 = $Invocation.Line
        StartLine            = $Region.StartLine
        EndLine              = $Region.EndLine
        FileType             = $File.FileType
        Region               = $Region.Kind
        Structure            = $Region.Structure
        RuleId               = $ruleId
        Rule                 = $ruleName
        RuleIds              = @($Evaluation.RuleIds)
        Command              = $Invocation.CommandText
        Alias                = $Detail.Alias
        TargetClass          = $Detail.Class
        Verb                 = $Detail.Verb
        Method               = $Detail.Method
        Properties           = @($Detail.Properties)
        PropertyGroup        = @($Detail.PropertyGroup)
        Node                 = $Detail.Node
        Filter               = $Detail.Filter
        Invocation           = @($Invocation.Invocation)
        Capture              = @($Invocation.Capture)
        Context              = @($Context)
        StepName             = $stepName
        ForOptions           = $forOptions
        Reason               = $reason
        SuggestedReplacement = Get-WmicSuggestion -Template $template -Detail $Detail
        Advisory             = $true
        FailsBuild           = $failsBuild
        Snippet              = $Region.Snippet
    }
}
