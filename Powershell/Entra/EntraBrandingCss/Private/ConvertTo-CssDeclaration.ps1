function ConvertTo-CssDeclaration {
    <#
    .SYNOPSIS
        Parses CSS text into one object per declaration, with selector, at-rule and position

    .DESCRIPTION
        A small tokenizer that walks the text once and emits every property: value declaration
        it finds, wherever it sits. It is not a full CSS parser and does not try to be; it only
        has to answer "which property names are declared, where, and under what selector".

        What it gets right, because the scanner depends on it:
        - /* */ comments are skipped, including multi-line ones, so a commented-out declaration
          is not a declaration.
        - Quoted strings and the inside of any parentheses, which covers url(...) and
          data: URIs, never start or end a declaration. A colon or semicolon in there is data.
        - Blocks nest. @media, @supports, @container, @layer and CSS nesting all push a prelude
          onto a stack, so a declaration knows its nearest selector and the chain of at-rules
          above it.
        - CSS escapes in property names are decoded, so "\70 osition" is reported as position.
          The Entra sign-in page sanitizer decodes them the same way; an escaped name would
          otherwise hide from a text search.
        - Line and column are tracked for the first character of the property name, and CRLF
          counts as one line break.

        Custom properties (--name) are emitted with IsCustomProperty set so the caller can skip
        them; they are declarations, but "--display: none" is not display.

    .PARAMETER Css
        The CSS text. A leading byte order mark is removed. Empty text yields nothing.

    .OUTPUTS
        EntraBrandingCss.Declaration

    .EXAMPLE
        ConvertTo-CssDeclaration -Css '.ext-footer { display: none !important; }'

        Emits one declaration: Property display, Value none, Important true, Selector .ext-footer.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Declaration')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Css
    )

    process {
        if ([string]::IsNullOrEmpty($Css)) { return }

        $text = $Css
        if ($text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

        # Offsets where each line starts, so a character offset maps to line and column after
        # the walk instead of being counted on every character.
        $lineStarts = [System.Collections.Generic.List[int]]::new()
        $lineStarts.Add(0)
        for ($k = 0; $k -lt $text.Length; $k++) {
            if ($text[$k] -eq "`n") { $lineStarts.Add($k + 1) }
        }

        $stack = [System.Collections.Generic.List[object]]::new()
        $buffer = [System.Text.StringBuilder]::new()
        $bufferStart = -1      # offset of the first non-whitespace character in the buffer
        $colonIndex = -1       # index in the buffer of the first colon outside parentheses
        $parenDepth = 0
        $length = $text.Length
        $i = 0

        while ($i -lt $length) {
            $ch = $text[$i]

            # Comment: skip it entirely, leaving one space so tokens on either side stay apart
            if ($ch -eq '/' -and ($i + 1) -lt $length -and $text[$i + 1] -eq '*') {
                $end = $text.IndexOf('*/', $i + 2)
                if ($end -lt 0) { $i = $length } else { $i = $end + 2 }
                [void]$buffer.Append(' ')
                continue
            }

            # String: copy through to the closing quote, honoring backslash escapes. An
            # unterminated string ends at the line break, which is what browsers do.
            if ($ch -eq '"' -or $ch -eq "'") {
                if ($bufferStart -lt 0) { $bufferStart = $i }
                $quote = $ch
                [void]$buffer.Append($ch)
                $i++
                while ($i -lt $length) {
                    $c = $text[$i]
                    if ($c -eq '\' -and ($i + 1) -lt $length) {
                        [void]$buffer.Append($c)
                        [void]$buffer.Append($text[$i + 1])
                        $i += 2
                        continue
                    }
                    [void]$buffer.Append($c)
                    $i++
                    if ($c -eq $quote -or $c -eq "`n") { break }
                }
                continue
            }

            if ($ch -eq '(') {
                $parenDepth++
            } elseif ($ch -eq ')') {
                if ($parenDepth -gt 0) { $parenDepth-- }
            } elseif ($parenDepth -eq 0) {
                if ($ch -eq '{') {
                    # A selector list written one per line is one selector; keep it on one line
                    $prelude = ($buffer.ToString() -replace '\s+', ' ').Trim()
                    $stack.Add([PSCustomObject]@{
                        Prelude  = $prelude
                        IsAtRule = $prelude.StartsWith('@')
                    })
                    [void]$buffer.Clear()
                    $bufferStart = -1
                    $colonIndex = -1
                    $i++
                    continue
                }
                if ($ch -eq ';' -or $ch -eq '}') {
                    $record = ConvertTo-CssDeclarationRecord -Text $buffer.ToString() -ColonIndex $colonIndex `
                        -Offset $bufferStart -LineStarts $lineStarts -Stack $stack
                    if ($record) { $record }
                    [void]$buffer.Clear()
                    $bufferStart = -1
                    $colonIndex = -1
                    if ($ch -eq '}' -and $stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
                    $i++
                    continue
                }
                if ($ch -eq ':' -and $colonIndex -lt 0) {
                    $colonIndex = $buffer.Length
                }
            }

            if ($bufferStart -lt 0 -and -not [char]::IsWhiteSpace($ch)) { $bufferStart = $i }
            [void]$buffer.Append($ch)
            $i++
        }

        # A final declaration with no semicolon and no closing brace is still a declaration
        $record = ConvertTo-CssDeclarationRecord -Text $buffer.ToString() -ColonIndex $colonIndex `
            -Offset $bufferStart -LineStarts $lineStarts -Stack $stack
        if ($record) { $record }
    }
}


function ConvertTo-CssDeclarationRecord {
    <#
    .SYNOPSIS
        Turns one buffered "name: value" segment into a declaration object, or nothing

    .DESCRIPTION
        Called by ConvertTo-CssDeclaration at every semicolon, closing brace and end of text.
        Returns null for anything that is not a declaration: no colon, an empty name, a name
        with whitespace in it (a malformed selector), or an at-rule statement such as @import.

    .PARAMETER Text
        The buffered segment, comments already removed.

    .PARAMETER ColonIndex
        Index in Text of the first colon outside parentheses, or -1.

    .PARAMETER Offset
        Offset in the original CSS of the first non-whitespace character of Text.

    .PARAMETER LineStarts
        Offsets where each line of the original CSS begins.

    .PARAMETER Stack
        The open block preludes, outermost first.

    .OUTPUTS
        EntraBrandingCss.Declaration, or nothing.
    #>

    [CmdletBinding()]
    [OutputType('EntraBrandingCss.Declaration')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$ColonIndex,

        [Parameter(Mandatory)]
        [int]$Offset,

        [Parameter(Mandatory)]
        [System.Collections.Generic.List[int]]$LineStarts,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Stack
    )

    if ($ColonIndex -lt 0 -or $Offset -lt 0) { return $null }

    $rawName = $Text.Substring(0, $ColonIndex).Trim()
    if ($rawName.Length -eq 0 -or $rawName.StartsWith('@')) { return $null }

    # Decode before the whitespace check: "\70 osition" has a space in it and is still position
    $decodedName = ConvertFrom-CssEscape -Text $rawName
    if ($decodedName -match '\s') { return $null }
    $property = $decodedName.ToLowerInvariant()

    $value = $Text.Substring($ColonIndex + 1).Trim()
    $important = $false
    if ($value -match '!\s*important\s*$') {
        $important = $true
        $value = ($value -replace '!\s*important\s*$', '').Trim()
    }

    $selector = ''
    $atRules = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Stack) {
        if ($entry.IsAtRule) { $atRules.Add($entry.Prelude) }
    }
    for ($s = $Stack.Count - 1; $s -ge 0; $s--) {
        if (-not $Stack[$s].IsAtRule) { $selector = $Stack[$s].Prelude; break }
    }

    # Line is the count of line starts at or before the offset; column counts from that start
    $line = 1
    for ($l = $LineStarts.Count - 1; $l -ge 0; $l--) {
        if ($LineStarts[$l] -le $Offset) { $line = $l + 1; break }
    }
    $column = $Offset - $LineStarts[$line - 1] + 1

    [PSCustomObject]@{
        PSTypeName       = 'EntraBrandingCss.Declaration'
        Property         = $property
        RawProperty      = $rawName
        IsEscaped        = ($decodedName -ne $rawName)
        IsCustomProperty = $property.StartsWith('--')
        Value            = $value
        Important        = $important
        Selector         = $selector
        AtRule           = ($atRules -join ' > ')
        Line             = $line
        Column           = $column
    }
}


function ConvertFrom-CssEscape {
    <#
    .SYNOPSIS
        Decodes CSS backslash escapes in an identifier

    .DESCRIPTION
        A backslash followed by one to six hex digits and an optional single whitespace is a
        code point; a backslash followed by anything else is that character. Null, surrogate
        and out-of-range code points become U+FFFD, as the CSS Syntax specification requires.

    .PARAMETER Text
        The identifier to decode.

    .OUTPUTS
        System.String

    .EXAMPLE
        ConvertFrom-CssEscape -Text '\70 osition'

        Returns position.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($Text.IndexOf('\') -lt 0) { return $Text }

    $evaluator = {
        param([System.Text.RegularExpressions.Match]$Match)
        $sequence = $Match.Groups[1].Value
        if ($sequence -match '^[0-9a-fA-F]') {
            $code = [Convert]::ToInt32(($sequence.TrimEnd()), 16)
            if ($code -eq 0 -or $code -gt 0x10FFFF -or ($code -ge 0xD800 -and $code -le 0xDFFF)) {
                return [string][char]0xFFFD
            }
            return [char]::ConvertFromUtf32($code)
        }
        return $sequence
    }

    return [regex]::Replace($Text, '\\([0-9a-fA-F]{1,6}\s?|[\s\S])', $evaluator)
}
