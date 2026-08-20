function Get-WmicAstCapture {
    <#
    .SYNOPSIS
        Reads from the syntax tree how a command's output is consumed

    .DESCRIPTION
        Answers the question the Wrapped tier turns on: does anything downstream read this
        command's output? Three answers are possible and they are not exclusive - output can be
        piped, redirected and assigned at once.

        The tree is used rather than the text because the four positions that matter look almost
        identical as characters and not at all as syntax. This is the one language in scope where
        that distinction is free, so it is taken.

        The walk upwards stops at a statement block. Without that stop, a WMIC call anywhere
        inside a function whose whole result is assigned would be reported as captured, which is
        true of the function and false of the call - and a Wrapped tier that fires on ordinary
        calls inside assigned functions would be noise within a week of anyone using it.

    .PARAMETER Command
        [System.Management.Automation.Language.CommandAst] (Mandatory, No Pipeline Support)

        The command to inspect.

    .OUTPUTS
        System.String[] - any of Pipe, Redirect, Variable. Empty when the output goes to the host.

    .EXAMPLE
        $capture = Get-WmicAstCapture -Command $commandAst

        DESCRIPTION: Classifies how the output of a parsed call is consumed
        OUTPUT: @('Variable') for $serial = wmic bios get serialnumber
        USE CASE: Deciding between the Mechanical and Wrapped tiers

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command
    )

    $capture = @()

    if ($Command.Redirections -and $Command.Redirections.Count -gt 0) {
        $capture += 'Redirect'
    }

    $pipeline = $Command.Parent
    if ($pipeline -is [System.Management.Automation.Language.PipelineAst]) {
        $elements = $pipeline.PipelineElements
        if ($elements.Count -gt 1 -and $elements[$elements.Count - 1] -ne $Command) {
            $capture += 'Pipe'
        }
    }

    $node = $pipeline
    $depth = 0
    while ($null -ne $node -and $depth -lt 8) {
        if ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -or
            $node -is [System.Management.Automation.Language.ParenExpressionAst] -or
            $node -is [System.Management.Automation.Language.SubExpressionAst] -or
            $node -is [System.Management.Automation.Language.ArrayExpressionAst] -or
            $node -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $capture += 'Variable'
            break
        }

        # A statement block means the enclosing construct is a scope, not a consumer
        if ($node -is [System.Management.Automation.Language.StatementBlockAst] -or
            $node -is [System.Management.Automation.Language.NamedBlockAst] -or
            $node -is [System.Management.Automation.Language.ScriptBlockAst]) {
            break
        }

        $node = $node.Parent
        $depth++
    }

    return @($capture | Select-Object -Unique)
}
