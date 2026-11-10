<#
One-shot converter written for the OrphanedSid test suite's move from Pester 3.4 to Pester 6.
It is published as the example behind https://techbyjeff.net/migrating-2400-tests-from-pester-3-to-6/
and is not a general-purpose migration tool. Run it on a clean working tree and review the diff.

Known limits:
  - Comments between moved statements stay where they were, so they end up stacked above the new BeforeAll.
  - It does not rewrite $MyInvocation.MyCommand.Path. Inside a BeforeAll that path is empty; use
    $PSScriptRoot and $PSCommandPath instead.
  - Mock -Scope It is left in place. Pester 6 has no -Scope on Mock, so remove it by hand.
  - Assertions are rewritten by regex, one pass. Operators outside the list below are left alone.

Converts Pester 3.4 test files to Pester 5/6 structure and syntax.
  1. Drops 'Import-Module Pester -RequiredVersion 3.4.0' lines.
  2. Moves every top-level statement that is not a Describe into one BeforeAll before the first Describe.
  3. Inside Describe/Context bodies, wraps runs of statements that are not It/Context/Describe/Before*/After*
     into BeforeAll blocks at the same position.
  4. Rewrites 'Should X' to 'Should -X', 'Should Not X' to 'Should -Not -X', Assert-MockCalled to Should -Invoke,
     Assert-VerifiableMocks to Should -InvokeVerifiable, Set-TestInconclusive to Set-ItResult -Inconclusive,
     -Tags to -Tag, and the #Requires line.
  5. 'Should -Throw "literal"' without wildcards becomes 'Should -Throw "*literal*"' (v3 matched substrings; v5 uses -like).
#>
param(
    [Parameter(Mandatory)]
    [string[]]$Path,

    [switch]$WhatIf
)

$blockCommands = 'Describe', 'Context', 'It', 'BeforeAll', 'BeforeEach', 'AfterAll', 'AfterEach', 'BeforeDiscovery'

function Get-CommandName {
    param([System.Management.Automation.Language.StatementAst]$Statement)
    if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and $Statement.PipelineElements.Count -eq 1) {
        $c = $Statement.PipelineElements[0]
        if ($c -is [System.Management.Automation.Language.CommandAst]) { return $c.GetCommandName() }
    }
    return $null
}

function Get-BodyScriptBlock {
    param([System.Management.Automation.Language.StatementAst]$Statement)
    $c = $Statement.PipelineElements[0]
    $last = $c.CommandElements[-1]
    if ($last -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $last.ScriptBlock }
    return $null
}

function Get-Indent {
    param([string]$Text, [int]$Offset)
    $lineStart = $Text.LastIndexOf("`n", [Math]::Max(0, $Offset - 1)) + 1
    return [regex]::Match($Text.Substring($lineStart), '^[ \t]*').Value
}

function Add-WrapEdit {
    param($Run, [string]$Text, [string]$Nl, $Edits)
    if ($Run.Count -eq 0) { return }
    $start = $Run[0].Extent.StartOffset
    $end = $Run[-1].Extent.EndOffset
    $indent = Get-Indent -Text $Text -Offset $start
    $body = $Text.Substring($start, $end - $start)
    $bodyLines = ($body -split "\r?\n") | ForEach-Object { if ($_.Length) { '    ' + $_ } else { $_ } }
    $new = 'BeforeAll {' + $Nl + ($bodyLines -join $Nl) + $Nl + $indent + '}'
    $Edits.Add(@{ Start = $start; End = $end; Text = $new })
}

function Visit-Body {
    param($ScriptBlockAst, [string]$Text, [string]$Nl, $Edits)
    $run = @()
    foreach ($s in @($ScriptBlockAst.EndBlock.Statements)) {
        $name = Get-CommandName -Statement $s
        if ($name -in $blockCommands) {
            Add-WrapEdit -Run $run -Text $Text -Nl $Nl -Edits $Edits
            $run = @()
            if ($name -in 'Describe', 'Context') {
                $inner = Get-BodyScriptBlock -Statement $s
                if ($inner) { Visit-Body -ScriptBlockAst $inner -Text $Text -Nl $Nl -Edits $Edits }
            }
        }
        else {
            $run += $s
        }
    }
    Add-WrapEdit -Run $run -Text $Text -Nl $Nl -Edits $Edits
}

foreach ($file in $Path) {
    $full = (Resolve-Path $file).Path
    $bytes = [IO.File]::ReadAllBytes($full)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors) {
        Write-Warning "$file : parse errors, skipped: $($errors[0].Message)"
        continue
    }

    $edits = [System.Collections.Generic.List[object]]::new()

    $topStatements = @($ast.EndBlock.Statements)
    $describes = @($topStatements | Where-Object { (Get-CommandName -Statement $_) -eq 'Describe' })
    foreach ($d in $describes) {
        $body = Get-BodyScriptBlock -Statement $d
        if ($body) { Visit-Body -ScriptBlockAst $body -Text $text -Nl $nl -Edits $edits }
    }

    $top = @($topStatements | Where-Object { (Get-CommandName -Statement $_) -notin $blockCommands })
    $dropped = @($top | Where-Object { $_.Extent.Text -match '^\s*Import-Module\s+Pester\b' })
    $moved = @($top | Where-Object { $_ -notin $dropped })
    foreach ($s in ($dropped + $moved)) {
        $end = $s.Extent.EndOffset
        while ($end -lt $text.Length -and ($text[$end] -eq "`r" -or $text[$end] -eq "`n")) { $end++ }
        $edits.Add(@{ Start = $s.Extent.StartOffset; End = $end; Text = '' })
    }
    if ($moved.Count -gt 0 -and $describes.Count -gt 0) {
        $insertAt = $describes[0].Extent.StartOffset
        $bodyText = ($moved | ForEach-Object { $_.Extent.Text }) -join ($nl + $nl)
        $bodyLines = ($bodyText -split "\r?\n") | ForEach-Object { if ($_.Length) { '    ' + $_ } else { $_ } }
        $block = 'BeforeAll {' + $nl + ($bodyLines -join $nl) + $nl + '}' + $nl + $nl
        $edits.Add(@{ Start = $insertAt; End = $insertAt; Text = $block })
    }

    $sb = [System.Text.StringBuilder]::new($text)
    foreach ($e in ($edits | Sort-Object { $_.Start } -Descending)) {
        $null = $sb.Remove($e.Start, $e.End - $e.Start).Insert($e.Start, $e.Text)
    }
    $out = $sb.ToString()

    $out = $out -replace '(?m)^#Requires -Modules? Pester\s*$', "#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }"
    $out = $out -replace '\bShould Not (Be|BeNullOrEmpty|Throw|Exist|Match|BeOfType|BeGreaterThan|BeLessThan|BeLike|BeExactly|Contain|BeIn)\b', 'Should -Not -$1'
    $out = $out -replace '\bShould (Be|BeNullOrEmpty|Throw|Exist|Match|BeOfType|BeGreaterThan|BeLessThan|BeLike|BeExactly|Contain|BeIn)\b', 'Should -$1'
    $out = $out -replace '\bAssert-MockCalled\b', 'Should -Invoke'
    $out = $out -replace '\bAssert-VerifiableMocks?\b', 'Should -InvokeVerifiable'
    $out = $out -replace '\bSet-TestInconclusive\s+-Message\b', 'Set-ItResult -Inconclusive -Because'
    $out = $out -replace '\bSet-TestInconclusive\b', 'Set-ItResult -Inconclusive'
    $out = $out -replace '(?m)^(\s*(?:Describe|Context|It)\b[^\r\n]*?)\s-Tags\s', '$1 -Tag '

    $throwPattern = 'Should -Throw\s+(["''])([^"''*\r\n]+)\1'
    $out = [regex]::Replace($out, $throwPattern, {
        param($m)
        $q = $m.Groups[1].Value
        $lit = $m.Groups[2].Value -replace '\[', '[[]'
        $lit = [regex]::Replace($lit, '(?<!\[)\](?!\])', '[]]')
        "Should -Throw $q*$lit*$q"
    })

    if ($WhatIf) {
        "$file : $($moved.Count) top-level statement(s) moved, $($dropped.Count) dropped, $($edits.Count) structural edits"
        continue
    }

    [IO.File]::WriteAllText($full, $out, [Text.UTF8Encoding]::new($hasBom))
    $t2 = $null
    $e2 = $null
    [System.Management.Automation.Language.Parser]::ParseInput($out, [ref]$t2, [ref]$e2) | Out-Null
    if ($e2) {
        Write-Warning "$file : converted output has parse errors: $($e2[0].Message) at line $($e2[0].Extent.StartLineNumber)"
    }
    else {
        "$file : converted ($($moved.Count) moved, $($edits.Count) edits)"
    }
}
