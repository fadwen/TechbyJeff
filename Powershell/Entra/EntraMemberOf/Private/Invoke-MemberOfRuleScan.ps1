function Invoke-MemberOfRuleScan {
    <#
    .SYNOPSIS
        Scans one membership rule and returns a result that says whether it uses memberOf

    .DESCRIPTION
        The one place rule text mode and tenant mode meet. Takes a rule and what is known about
        the object it belongs to, tokenizes the rule with ConvertTo-MembershipRuleToken, and
        returns one EntraMemberOf.Result whose Level keeps three statements apart:

            Retired   the rule uses user.memberOf or device.memberOf as an identifier outside a
                      quoted string. Per Learn, the object stops updating on the retirement date.
            Review    the rule mentions memberOf some other way, or could not be tokenized to
                      the end, so a person has to read it. ReviewCode names which.
            Clean     the rule was read to the end and does not use memberOf.

        A Retired result also carries what the operator was applied to: the rule kind (user or
        device), the quantifier and operator used, and every source group id found inside the
        memberOf expression. Learn documents -any and -in; a rule that uses something else is
        still Retired, with a note. A rule that combines memberOf with other expressions, which
        Learn lists as unsupported, is noted too.

        Source group names, and whether a source group is itself a memberOf dynamic group, are
        filled in afterwards by the caller, because they need the whole tenant.

    .PARAMETER Rule
        The membership rule text. Null or empty gives a Clean result with a note, because an
        object with no rule has nothing that can use memberOf.

    .PARAMETER ObjectKind
        Group, AdministrativeUnit, AutoAssignmentPolicy, or Rule for text with no object behind
        it. Picks the remediation sentence.

    .PARAMETER Id
        The object id, when known.

    .PARAMETER DisplayName
        The object's display name, when known.

    .PARAMETER AccessPackageName
        For a policy, the access package it belongs to.

    .PARAMETER ProcessingState
        On, Paused, or null when the object has no such property or the source did not carry it.
        A paused object is reported like any other: Learn does not exempt it.

    .PARAMETER Source
        Where the rule came from, for the result: Tenant, RuleText, or a file path.

    .OUTPUTS
        EntraMemberOf.Result

    .EXAMPLE
        Invoke-MemberOfRuleScan -Rule 'user.memberOf -any (group.objectId -in [''a''])' -ObjectKind Rule `
            -Source RuleText

        A Retired result with RuleKind user, Quantifier any, Operator in and one source group id.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
    #>

    [CmdletBinding()]
    [OutputType('EntraMemberOf.Result')]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Rule,

        [Parameter(Mandatory)]
        [ValidateSet('Group', 'AdministrativeUnit', 'AutoAssignmentPolicy', 'Rule')]
        [string]$ObjectKind,

        [Parameter()]
        [AllowNull()]
        [string]$Id,

        [Parameter()]
        [AllowNull()]
        [string]$DisplayName,

        [Parameter()]
        [AllowNull()]
        [string]$AccessPackageName,

        [Parameter()]
        [AllowNull()]
        [string]$ProcessingState,

        [Parameter(Mandatory)]
        [string]$Source
    )

    $catalog = Get-MemberOfRuleCatalog
    $notes = [System.Collections.Generic.List[string]]::new()

    $level = 'Clean'
    $reviewCode = $null
    $ruleKind = $null
    $quantifier = $null
    $operator = $null
    $sourceIds = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace($Rule)) {
        $notes.Add('No rule text.')
    } else {
        $tokens = @(ConvertTo-MembershipRuleToken -Rule $Rule)
        $problems = @($tokens | Where-Object { $_.Kind -in @('Unknown', 'Unterminated') })
        $hits = @($tokens | Where-Object {
                $_.Kind -eq 'Word' -and $catalog.RetiredProperties -contains $_.Text.ToLowerInvariant()
            })

        if ($hits.Count -gt 0) {
            $level = 'Retired'
            $kinds = @($hits | ForEach-Object { $_.Text.Split('.')[0].ToLowerInvariant() } | Select-Object -Unique)
            $ruleKind = $kinds[0]
            if ($kinds.Count -gt 1) {
                $notes.Add("The rule mixes $($kinds -join ' and ') memberOf, which cannot both apply to one " +
                    'object.')
            }

            # Which token indexes belong to a memberOf expression, so that an -and or -or
            # outside them can be recognized as combining memberOf with something else.
            $inExpression = [bool[]]::new($tokens.Count)
            foreach ($hit in $hits) {
                $start = [array]::IndexOf($tokens, $hit)
                $inExpression[$start] = $true
                $depth = 0
                $sawObjectId = $false
                for ($k = $start + 1; $k -lt $tokens.Count; $k++) {
                    $token = $tokens[$k]
                    $isAnotherHit = $token.Kind -eq 'Word' -and
                        $catalog.RetiredProperties -contains $token.Text.ToLowerInvariant()
                    if ($isAnotherHit) { break }
                    if ($token.Kind -eq 'CloseParen') {
                        if ($depth -eq 0) { break }
                        $depth--
                    }
                    $inExpression[$k] = $true
                    if ($token.Kind -eq 'OpenParen') { $depth++; continue }
                    if ($token.Kind -eq 'Operator') {
                        if ($depth -eq 0 -and $token.Text -in @('and', 'or')) {
                            # memberOf -any (...) -and ... : the -and belongs to the outer rule
                            $inExpression[$k] = $false
                            break
                        }
                        if ($null -eq $quantifier -and $k -eq $start + 1) { $quantifier = $token.Text; continue }
                        if ($sawObjectId -and $null -eq $operator) { $operator = $token.Text; continue }
                        continue
                    }
                    if ($token.Kind -eq 'Word' -and $token.Text.ToLowerInvariant() -eq $catalog.SourceProperty) {
                        $sawObjectId = $true
                        continue
                    }
                    if ($token.Kind -eq 'String') {
                        $sourceIds.Add($token.Text)
                    }
                }
            }

            if ($null -eq $quantifier) {
                $notes.Add('No quantifier follows memberOf; the documented form is -any.')
            } elseif ($quantifier -ne $catalog.DocumentedQuantifier) {
                $notes.Add("Quantifier -$quantifier is not the documented -$($catalog.DocumentedQuantifier).")
            }
            if ($null -eq $operator) {
                $notes.Add("No $($catalog.SourceProperty) comparison was found inside the memberOf expression.")
            } elseif ($operator -ne $catalog.DocumentedOperator) {
                $notes.Add("Operator -$operator is not the documented -$($catalog.DocumentedOperator).")
            }

            if ($sourceIds.Count -eq 0) {
                $notes.Add('No source group id was found inside the memberOf expression.')
            } else {
                $guidPattern = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
                $notGuid = @($sourceIds | Where-Object { $_ -notmatch $guidPattern })
                if ($notGuid.Count -gt 0) {
                    $notes.Add("Not every source value is an object id: $($notGuid -join ', ').")
                }
                if ($sourceIds.Count -gt [int]$catalog.Limits.SourceGroupsPerGroup) {
                    $notes.Add("$($sourceIds.Count) source groups, over the documented limit of " +
                        "$($catalog.Limits.SourceGroupsPerGroup).")
                }
            }

            $outside = @(for ($k = 0; $k -lt $tokens.Count; $k++) {
                    if (-not $inExpression[$k] -and $tokens[$k].Kind -eq 'Operator' -and
                        $tokens[$k].Text -in @('and', 'or', 'not')) { $tokens[$k] }
                })
            if ($outside.Count -gt 0) {
                $notes.Add('memberOf is combined with other expressions, which Learn lists as unsupported.')
            }
            if ($problems.Count -gt 0) {
                $notes.Add("The rule also has text the tokenizer could not read: " +
                    "$(($problems | ForEach-Object Raw | Select-Object -Unique) -join ' ').")
            }
        } elseif ($problems.Count -gt 0) {
            $level = 'Review'
            $reviewCode = 'UnparsedRule'
            $shown = @($problems | ForEach-Object Raw | Select-Object -Unique -First 5)
            $notes.Add("$($catalog.Review['UnparsedRule']) Unreadable: $($shown -join ' ') at index " +
                "$($problems[0].Index).")
        } else {
            $asOperator = @($tokens | Where-Object { $_.Kind -eq 'Operator' -and $_.Text -eq 'memberof' })
            $unqualified = @($tokens | Where-Object { $_.Kind -eq 'Word' -and $_.Text -match '(?i)memberof' })
            $inString = @($tokens | Where-Object { $_.Kind -eq 'String' -and $_.Text -match '(?i)memberof' })

            if ($asOperator.Count -gt 0) {
                $level = 'Review'
                $reviewCode = 'MemberOfAsOperator'
                $notes.Add("$($catalog.Review['MemberOfAsOperator']) Written as $($asOperator[0].Raw).")
            } elseif ($unqualified.Count -gt 0) {
                $level = 'Review'
                $reviewCode = 'UnqualifiedMemberOf'
                $notes.Add("$($catalog.Review['UnqualifiedMemberOf']) Written as $($unqualified[0].Raw).")
            } elseif ($inString.Count -gt 0) {
                $level = 'Review'
                $reviewCode = 'StringLiteral'
                $notes.Add("$($catalog.Review['StringLiteral']) Value: $($inString[0].Raw).")
            }
        }
    }

    $remediation = $null
    if ($level -eq 'Retired') {
        $remediation = [string]$catalog.Remediation[$ObjectKind]
    }

    [PSCustomObject]@{
        PSTypeName             = 'EntraMemberOf.Result'
        ObjectKind             = $ObjectKind
        Id                     = $Id
        DisplayName            = $DisplayName
        AccessPackageName      = $AccessPackageName
        RuleKind               = $ruleKind
        Level                  = $level
        ReviewCode             = $reviewCode
        ProcessingState        = $ProcessingState
        Rule                   = $Rule
        Quantifier             = $quantifier
        Operator               = $operator
        SourceGroupIds         = $sourceIds.ToArray()
        SourceGroupNames       = @()
        DependsOnMemberOfGroup = $false
        DependsOn              = @()
        Remediation            = $remediation
        Note                   = $(if ($notes.Count -gt 0) { $notes -join ' ' } else { $null })
        Source                 = $Source
        Error                  = $null
    }
}
