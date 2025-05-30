function Find-MatchingBrace {
    param(
        [string]$Code,
        [int]$Position
    )

    # First check if the position actually contains a brace
    if ($Position -ge $Code.Length -or ($Code[$Position] -ne '{' -and $Code[$Position] -ne '}')) {
        Write-Host "Position $Position does not contain a brace character" -ForegroundColor Red
        return $null
    }

    # Parse the code into AST
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)

    # Find all tokens that are braces
    $braceTokens = $tokens | Where-Object {
        $_.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly -or
        $_.Kind -eq [System.Management.Automation.Language.TokenKind]::RCurly
    }

    Write-Host "Debug: Found $($braceTokens.Count) brace tokens" -ForegroundColor Cyan
    foreach ($token in $braceTokens) {
        $braceChar = if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly) { "{" } else { "}" }
        $color = if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly) { "Green" } else { "Magenta" }
        Write-Host "  Token at position $($token.Extent.StartOffset): '$braceChar' (Kind: $($token.Kind))" -ForegroundColor $color
    }

    # Create a stack to match braces
    $braceStack = @()
    $braceMap = @{}

    foreach ($token in $braceTokens | Sort-Object { $_.Extent.StartOffset }) {
        $tokenPos = $token.Extent.StartOffset

        if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly) {
            # Opening brace - push to stack
            $braceStack += $tokenPos
        }
        elseif ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::RCurly) {
            # Closing brace - pop from stack and create mapping
            if ($braceStack.Count -gt 0) {
                $matchingOpen = $braceStack[-1]
                $braceStack = $braceStack[0..($braceStack.Count-2)]

                # Create bidirectional mapping
                $braceMap[$matchingOpen] = $tokenPos
                $braceMap[$tokenPos] = $matchingOpen
            }
        }
    }

    Write-Host "Debug: Brace mapping:" -ForegroundColor Cyan
    foreach ($key in $braceMap.Keys | Sort-Object) {
        $keyChar = $Code[$key]
        $valueChar = $Code[$braceMap[$key]]

        if ($keyChar -eq '{') {
            Write-Host "  Position " -NoNewline
            Write-Host "$key" -ForegroundColor Green -NoNewline
            Write-Host " ($keyChar) -> Position " -NoNewline
            Write-Host "$($braceMap[$key])" -ForegroundColor Magenta -NoNewline
            Write-Host " ($valueChar)"
        }
    }

    # Check if our position has a match
    if ($braceMap.ContainsKey($Position)) {
        $matchingPos = $braceMap[$Position]
        $isOpening = $Code[$Position] -eq '{'

        # Find the AST node that contains this brace for additional context
        $containingNode = $ast.FindAll({
            $node = $args[0]
            $node.Extent.StartOffset -le $Position -and $node.Extent.EndOffset -gt $Position
        }, $true) | Where-Object {
            $_ -is [System.Management.Automation.Language.ScriptBlockAst] -or
            $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or
            $_ -is [System.Management.Automation.Language.HashtableAst] -or
            $_ -is [System.Management.Automation.Language.ArrayLiteralAst]
        } | Select-Object -First 1

        return @{
            Type = if ($isOpening) { 'Opening' } else { 'Closing' }
            Position = $Position
            MatchingPosition = $matchingPos
            BlockType = if ($containingNode) { $containingNode.GetType().Name } else { 'Unknown' }
            Character = $Code[$Position]
            MatchingCharacter = $Code[$matchingPos]
        }
    }

    return $null
}

# Helper function to find all brace positions
function Find-BracePositions {
    param([string]$Code)

    Write-Host "Code with position markers:" -ForegroundColor Yellow
    Write-Host "==========================" -ForegroundColor Yellow

    # Show the code with position numbers
    $lines = $Code -split "`n"
    $position = 0

    for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
        $line = $lines[$lineNum]
        Write-Host ("Line {0,2}: " -f ($lineNum + 1)) -ForegroundColor Gray -NoNewline
        Write-Host $line -ForegroundColor White

        # Show positions of braces in this line
        for ($charPos = 0; $charPos -lt $line.Length; $charPos++) {
            if ($line[$charPos] -eq '{' -or $line[$charPos] -eq '}') {
                $absolutePos = $position + $charPos
                $braceColor = if ($line[$charPos] -eq '{') { "Green" } else { "Magenta" }
                Write-Host "         Brace " -ForegroundColor Gray -NoNewline
                Write-Host "'$($line[$charPos])'" -ForegroundColor $braceColor -NoNewline
                Write-Host " at position " -ForegroundColor Gray -NoNewline
                Write-Host "$absolutePos" -ForegroundColor $braceColor
            }
        }

        $position += $line.Length + 1  # +1 for newline character
    }
    Write-Host ""
}

# Example usage
$sampleCode = @'
Get-Process | Where-Object {
    $_.CPU -gt 100 -and
    $_.WorkingSet -gt 50MB
} | ForEach-Object {
    Write-Host "High CPU process: $($_.Name)"
}
'@

Write-Host "Sample code:" -ForegroundColor Yellow
Write-Host $sampleCode -ForegroundColor White
Write-Host ""

# First, let's see where the braces actually are
Find-BracePositions -Code $sampleCode

Write-Host "Testing brace matching:" -ForegroundColor Yellow
Write-Host "=====================" -ForegroundColor Yellow

# Find all brace positions and test them
for ($i = 0; $i -lt $sampleCode.Length; $i++) {
    if ($sampleCode[$i] -eq '{' -or $sampleCode[$i] -eq '}') {
        $braceColor = if ($sampleCode[$i] -eq '{') { "Green" } else { "Magenta" }

        Write-Host "Testing position " -ForegroundColor Gray -NoNewline
        Write-Host "$i" -ForegroundColor $braceColor -NoNewline
        Write-Host " (character: " -ForegroundColor Gray -NoNewline
        Write-Host "'$($sampleCode[$i])'" -ForegroundColor $braceColor -NoNewline
        Write-Host ")" -ForegroundColor Gray

        $result = Find-MatchingBrace -Code $sampleCode -Position $i

        if ($result) {
            $matchColor = if ($result.MatchingCharacter -eq '{') { "Green" } else { "Magenta" }
            Write-Host "  ✓ Found " -ForegroundColor Green -NoNewline
            Write-Host "$($result.Type)" -ForegroundColor $braceColor -NoNewline
            Write-Host " brace at position " -ForegroundColor Green -NoNewline
            Write-Host "$($result.Position)" -ForegroundColor $braceColor

            Write-Host "  ✓ Matching brace is at position " -ForegroundColor Green -NoNewline
            Write-Host "$($result.MatchingPosition)" -ForegroundColor $matchColor

            Write-Host "  ✓ Block type: " -ForegroundColor Green -NoNewline
            Write-Host "$($result.BlockType)" -ForegroundColor Cyan
        } else {
            Write-Host "  ✗ No match found" -ForegroundColor Red
        }
        Write-Host ""
    }
}