function Read-WmicPowerShellRegion {
    <#
    .SYNOPSIS
        Splits a PowerShell script into regions, using the parser rather than regexes

    .DESCRIPTION
        Parses the file and reports WMIC calls found in the syntax tree, which is worth doing
        here and nowhere else in this module: PowerShell is the one language in scope that ships
        its own parser, so capture detection can be exact instead of guessed.

        That matters for the Wrapped tier. Whether output is consumed is a question about the
        shape of the statement, not about the characters near it - $x = wmic ..., (wmic ...),
        wmic ... | Select-String and wmic ... > out.txt are four different syntactic positions
        that a regex has to guess at and the tree simply knows. Guessing wrong in either
        direction is expensive: a missed capture is a silently wrong migration, and an invented
        one sends somebody to restructure a line that only needed swapping.

        Strings are searched as well as commands, because a WMIC call reached through
        Start-Process, Invoke-Expression or a scheduled task definition is a call site even
        though the parser sees only an argument. Those are reported against their enclosing
        command, so the launcher is visible in the finding rather than a bare quoted fragment.

        A file that will not parse falls back to the line-oriented reader. Half a scan of a
        broken file beats none, and the fallback is noted in verbose output so a surprisingly
        thin result is explainable.

    .PARAMETER Content
        [System.String] (Mandatory, No Pipeline Support)

        The full text of the .ps1 or .psm1 file.

    .OUTPUTS
        Region hashtables carrying Kind, Structure, Text, Snippet, StartLine, EndLine, Lines and
        Detail. Detail.Capture holds what the tree says about how the output is consumed.

    .EXAMPLE
        $regions = Read-WmicPowerShellRegion -Content (Get-Content .\Inventory.ps1 -Raw)

        DESCRIPTION: Finds WMIC calls in a PowerShell script, with exact capture information
        OUTPUT: One region per call, comment and WMIC-bearing string
        USE CASE: Scanning the half of an estate that PSScriptAnalyzer already covers, for the
                  wrapping it does not report

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
        [string]$Content
    )

    $lines = $Content -split "`r?`n"
    $tokens = $null
    $errors = $null
    $ast = $null

    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Content, [ref]$tokens, [ref]$errors)
    }
    catch {
        Write-Verbose "PowerShell parse threw, falling back to line reader: $($_.Exception.Message)"
    }

    if ($null -eq $ast -or ($errors -and $errors.Count -gt 0)) {
        Write-Verbose 'PowerShell file did not parse cleanly; using the line-oriented reader'
        Read-WmicScriptRegion -Content $Content -FileType 'PowerShell'
        return
    }

    $wmicPattern = '(?i)(?<![\w.])wmic(\.exe)?(?![\w])'
    $commandNamePattern = '(?i)(^|[\\/])wmic(\.exe)?$'

    # Comments live in the token stream rather than the tree
    foreach ($token in $tokens) {
        if ($token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) { continue }
        if ($token.Text -notmatch $wmicPattern) { continue }

        [PSCustomObject]@{
            Kind      = 'Comment'
            Structure = 'Line'
            Text      = $token.Text
            Snippet   = $token.Text
            StartLine = $token.Extent.StartLineNumber
            EndLine   = $token.Extent.EndLineNumber
            Lines     = Get-WmicExtentLine -Line $lines -Start $token.Extent.StartLineNumber `
                -End $token.Extent.EndLineNumber
            Detail    = @{}
        }
    }

    $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

    $reportedCommands = [System.Collections.Generic.List[object]]::new()

    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        if ([string]::IsNullOrEmpty($name) -or $name -notmatch $commandNamePattern) { continue }

        $reportedCommands.Add($command)

        [PSCustomObject]@{
            Kind      = 'Code'
            Structure = 'Line'
            Text      = $command.Extent.Text
            Snippet   = $command.Extent.Text
            StartLine = $command.Extent.StartLineNumber
            EndLine   = $command.Extent.EndLineNumber
            Lines     = Get-WmicExtentLine -Line $lines -Start $command.Extent.StartLineNumber `
                -End $command.Extent.EndLineNumber
            Detail    = @{ Capture = @(Get-WmicAstCapture -Command $command) }
        }
    }

    # Strings holding a WMIC call: Start-Process, Invoke-Expression, a task definition. Reported
    # against the command that contains them so the launcher shows up in the finding.
    $strings = $ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
            $node.Extent.Text -match '(?i)wmic'
        }, $true)

    foreach ($string in $strings) {
        if ($string.Extent.Text -notmatch $wmicPattern) { continue }

        # The command name element of a call already reported above
        $isCommandName = $false
        foreach ($reported in $reportedCommands) {
            if ($reported.CommandElements.Count -gt 0 -and
                $reported.CommandElements[0].Extent.StartOffset -eq $string.Extent.StartOffset) {
                $isCommandName = $true
                break
            }
        }
        if ($isCommandName) { continue }

        $owner = $string
        $walk = $string.Parent
        $depth = 0
        while ($null -ne $walk -and $depth -lt 6) {
            if ($walk -is [System.Management.Automation.Language.CommandAst]) {
                $owner = $walk
                break
            }
            $walk = $walk.Parent
            $depth++
        }

        $capture = @()
        if ($owner -is [System.Management.Automation.Language.CommandAst]) {
            $capture = @(Get-WmicAstCapture -Command $owner)
        }

        [PSCustomObject]@{
            Kind      = 'Code'
            Structure = 'Line'
            Text      = $owner.Extent.Text
            Snippet   = $owner.Extent.Text
            StartLine = $owner.Extent.StartLineNumber
            EndLine   = $owner.Extent.EndLineNumber
            Lines     = Get-WmicExtentLine -Line $lines -Start $owner.Extent.StartLineNumber `
                -End $owner.Extent.EndLineNumber
            Detail    = @{ Capture = $capture }
        }
    }
}
