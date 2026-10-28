function ConvertTo-MembershipRuleToken {
    <#
    .SYNOPSIS
        Splits a dynamic membership rule into tokens, so the scanner matches operators and not text

    .DESCRIPTION
        A membership rule is a small expression language: identifiers such as user.department
        or group.objectId, operators written -eq or eq, string values in double or single
        quotes, arrays in square brackets, and parentheses. The one question this module asks
        of a rule is whether the memberOf operator is used, and a text search answers it
        wrongly in both directions: user.displayName -eq "memberOf" contains the word and does
        not use the operator, and the rule can be split across lines, written in any case, or
        wrapped in parentheses a regex has to guess at.

        So the rule is walked once, character by character, and comes back as a list of tokens
        with their Kind, Text and position. Quoted strings are one token each, with the escapes
        Learn documents already undone: a backtick before a double quote, and a doubled single
        quote. Operators are returned with their name in lower case and without the dash,
        whether they were written -eq, eq, or with the en dash some Learn examples carry.
        Anything the tokenizer does not recognize comes back as an Unknown token, and an
        unclosed quote as Unterminated, so the caller can say the rule was not fully read
        instead of calling it clean.

        It is not a parser for the whole language and does not need to be. It never evaluates
        a rule.

    .PARAMETER Rule
        The rule text. Empty text gives no tokens.

    .OUTPUTS
        EntraMemberOf.Token, one per token, in order. Kind is one of String, Operator, Word,
        OpenParen, CloseParen, OpenBracket, CloseBracket, Comma, Unknown, Unterminated.

    .EXAMPLE
        ConvertTo-MembershipRuleToken -Rule 'user.memberOf -any (group.objectId -in [''a''])'

        Nine tokens: Word, Operator any, OpenParen, Word, Operator in, OpenBracket, String a,
        CloseBracket, CloseParen.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Token')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Rule
    )

    # Every operator Learn documents for membership rules, plus the date arithmetic words. A
    # bare word in this set is an operator too, because Learn allows the dash to be omitted.
    $operatorNames = @(
        'eq', 'ne', 'startswith', 'notstartswith', 'endswith', 'notendswith', 'contains',
        'notcontains', 'match', 'notmatch', 'in', 'notin', 'any', 'all', 'and', 'or', 'not',
        'le', 'ge', 'lt', 'gt', 'plus', 'minus'
    )

    # A lookup rather than a switch: inside a switch statement, continue applies to the switch
    # and not to the enclosing while, so the character would fall through and be read twice.
    $punctuation = @{
        '(' = 'OpenParen'
        ')' = 'CloseParen'
        '[' = 'OpenBracket'
        ']' = 'CloseBracket'
        ',' = 'Comma'
    }

    $tokens = [System.Collections.Generic.List[object]]::new()
    $length = $Rule.Length
    $i = 0

    $newToken = {
        param($Kind, $Text, $Raw, $Index)
        [PSCustomObject]@{
            PSTypeName = 'EntraMemberOf.Token'
            Kind       = $Kind
            Text       = $Text
            Raw        = $Raw
            Index      = $Index
        }
    }

    while ($i -lt $length) {
        $ch = $Rule[$i]

        if ([char]::IsWhiteSpace($ch)) {
            $i++
            continue
        }

        # Double-quoted string. Learn: escape a double quote inside it with a backtick.
        if ($ch -eq '"') {
            $value = [System.Text.StringBuilder]::new()
            $j = $i + 1
            $closed = $false
            while ($j -lt $length) {
                $c = $Rule[$j]
                if ($c -eq '`' -and ($j + 1) -lt $length -and $Rule[$j + 1] -eq '"') {
                    [void]$value.Append('"')
                    $j += 2
                    continue
                }
                if ($c -eq '"') { $closed = $true; $j++; break }
                [void]$value.Append($c)
                $j++
            }
            $kind = if ($closed) { 'String' } else { 'Unterminated' }
            $tokens.Add((& $newToken $kind $value.ToString() $Rule.Substring($i, $j - $i) $i))
            $i = $j
            continue
        }

        # Single-quoted string, the form the memberOf examples use for ids. Learn: escape a
        # single quote by doubling it.
        if ($ch -eq "'") {
            $value = [System.Text.StringBuilder]::new()
            $j = $i + 1
            $closed = $false
            while ($j -lt $length) {
                $c = $Rule[$j]
                if ($c -eq "'") {
                    if (($j + 1) -lt $length -and $Rule[$j + 1] -eq "'") {
                        [void]$value.Append("'")
                        $j += 2
                        continue
                    }
                    $closed = $true
                    $j++
                    break
                }
                [void]$value.Append($c)
                $j++
            }
            $kind = if ($closed) { 'String' } else { 'Unterminated' }
            $tokens.Add((& $newToken $kind $value.ToString() $Rule.Substring($i, $j - $i) $i))
            $i = $j
            continue
        }

        $kindName = $punctuation[[string]$ch]
        if ($kindName) {
            $tokens.Add((& $newToken $kindName ([string]$ch) ([string]$ch) $i))
            $i++
            continue
        }

        # An operator: a dash, or the en dash that appears in some Learn examples, followed by
        # letters. Returned by name, in lower case, without the dash.
        $isDash = $ch -eq '-' -or $ch -eq [char]0x2013
        if ($isDash -and ($i + 1) -lt $length -and [char]::IsLetter($Rule[$i + 1])) {
            $j = $i + 1
            while ($j -lt $length -and [char]::IsLetter($Rule[$j])) { $j++ }
            $raw = $Rule.Substring($i, $j - $i)
            $tokens.Add((& $newToken 'Operator' $raw.Substring(1).ToLowerInvariant() $raw $i))
            $i = $j
            continue
        }

        # A word: an identifier such as user.memberOf or group.objectId, a keyword such as
        # null, or an unquoted value such as a number or a datetime. A word that starts with a
        # digit may carry the dashes and colons of a datetime (2020-06-10T18:13:20Z); one that
        # starts with a letter or underscore may not, so "user.department-eq" never fuses.
        if ([char]::IsLetterOrDigit($ch) -or $ch -eq '_') {
            $startsWithDigit = [char]::IsDigit($ch)
            $j = $i
            while ($j -lt $length) {
                $c = $Rule[$j]
                $wordChar = [char]::IsLetterOrDigit($c) -or $c -eq '_' -or $c -eq '.'
                if (-not $wordChar -and $startsWithDigit) { $wordChar = $c -eq '-' -or $c -eq ':' -or $c -eq '+' }
                if (-not $wordChar) { break }
                $j++
            }
            $raw = $Rule.Substring($i, $j - $i)
            $kind = 'Word'
            $text = $raw
            if ($operatorNames -contains $raw.ToLowerInvariant()) {
                $kind = 'Operator'
                $text = $raw.ToLowerInvariant()
            }
            $tokens.Add((& $newToken $kind $text $raw $i))
            $i = $j
            continue
        }

        $tokens.Add((& $newToken 'Unknown' ([string]$ch) ([string]$ch) $i))
        $i++
    }

    return $tokens.ToArray()
}
