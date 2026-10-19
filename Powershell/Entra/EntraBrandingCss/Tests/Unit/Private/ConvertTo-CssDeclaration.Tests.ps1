#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The parser, one behavior per test, with inline CSS. The fixture files under
    Tests/Fixtures are exercised through the public command; these pin the parser's own
    contract so a scanner failure can be told from a parser failure.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'EntraBrandingCss.psd1') -Force
}

AfterAll {
    Remove-Module EntraBrandingCss -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-CssDeclaration' -Tag 'Unit', 'Private' {

    Context 'declarations' {

        It 'emits one object per declaration with the selector' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.ext-footer { color: red; display: none; }')
                $result.Count | Should-Be 2
                $result.Property | Should-BeCollection @('color', 'display')
                $result | Should-All { $_.Selector -eq '.ext-footer' }
            }
        }

        It 'lower-cases the property name and trims it' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css ".a {`n   DISPLAY   :  none  ;`n}")
                $result[0].Property | Should-Be 'display'
                $result[0].RawProperty | Should-Be 'DISPLAY'
                $result[0].Value | Should-Be 'none'
            }
        }

        It 'separates !important from the value, with or without a space' {
            InModuleScope EntraBrandingCss {
                $css = '.a { display: none !important; top: 0!important; left:0 ! important }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result | Should-All { $_.Important }
                $result.Value | Should-BeCollection @('none', '0', '0')
            }
        }

        It 'keeps a final declaration that has no semicolon' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { color: red; display: none }')
                $result.Property | Should-BeCollection @('color', 'display')
            }
        }

        It 'keeps a declaration at end of text with no closing brace' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { display: none')
                $result.Count | Should-Be 1
                $result[0].Property | Should-Be 'display'
            }
        }

        It 'marks custom properties so the scanner can skip them' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { --display: none; color: var(--display); }')
                $result[0].Property | Should-Be '--display'
                $result[0].IsCustomProperty | Should-BeTrue
                $result[1].IsCustomProperty | Should-BeFalse
            }
        }

        It 'treats the first colon outside parentheses as the separator' {
            InModuleScope EntraBrandingCss {
                $css = '.a { filter: progid:DXImageTransform.Microsoft.Alpha(Opacity=50); }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result[0].Property | Should-Be 'filter'
                $result[0].Value | Should-Be 'progid:DXImageTransform.Microsoft.Alpha(Opacity=50)'
            }
        }
    }

    Context 'what is not a declaration' {

        It 'returns nothing for null, empty or whitespace' {
            InModuleScope EntraBrandingCss {
                @(ConvertTo-CssDeclaration -Css '').Count | Should-Be 0
                @(ConvertTo-CssDeclaration -Css "  `n  ").Count | Should-Be 0
                @(ConvertTo-CssDeclaration -Css $null).Count | Should-Be 0
            }
        }

        It 'ignores a segment with no colon' {
            InModuleScope EntraBrandingCss {
                @(ConvertTo-CssDeclaration -Css '.a { display; none }').Count | Should-Be 0
            }
        }

        It 'ignores at-rule statements such as @import and @charset' {
            InModuleScope EntraBrandingCss {
                $css = '@charset "utf-8"; @import url("https://x/y.css"); .a { color: red }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result.Count | Should-Be 1
                $result[0].Property | Should-Be 'color'
            }
        }

        It 'ignores a name containing whitespace, which is not a property' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { font family: serif; color: red }')
                $result.Property | Should-BeCollection @('color')
            }
        }
    }

    Context 'comments' {

        It 'skips a commented-out declaration' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { /* display: none; */ color: red; }')
                $result.Property | Should-BeCollection @('color')
            }
        }

        It 'skips a multi-line comment holding several declarations' {
            InModuleScope EntraBrandingCss {
                $css = ".a {`n/*`n position: absolute;`n top: 0;`n*/`n opacity: 1;`n}"
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result.Property | Should-BeCollection @('opacity')
                $result[0].Line | Should-Be 6
            }
        }

        It 'treats a comment between the name and the colon as whitespace' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { display/* x */: none; }')
                $result[0].Property | Should-Be 'display'
            }
        }

        It 'does not start a comment inside a string' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { content: "/*"; display: none; }')
                $result.Property | Should-BeCollection @('content', 'display')
            }
        }

        It 'survives an unterminated comment' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { color: red; } /* display: none')
                $result.Property | Should-BeCollection @('color')
            }
        }
    }

    Context 'strings and parentheses' {

        It 'does not end a declaration at a semicolon or brace inside a string' {
            InModuleScope EntraBrandingCss {
                $css = '.a { content: "x; } .b { display: none"; color: red; }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result.Property | Should-BeCollection @('content', 'color')
                $result[0].Value | Should-Be '"x; } .b { display: none"'
            }
        }

        It 'honors a backslash-escaped quote inside a string' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { content: "a\"; display: none"; color: red }')
                $result.Property | Should-BeCollection @('content', 'color')
            }
        }

        It 'does not end a declaration inside url() with a data URI' {
            InModuleScope EntraBrandingCss {
                $css = '.a { background: url(data:image/png;base64,AAAA); color: red }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result.Property | Should-BeCollection @('background', 'color')
            }
        }

        It 'reports transform, not scale, for transform: scale()' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { transform: scale(1.2) }')
                $result.Property | Should-BeCollection @('transform')
            }
        }
    }

    Context 'nesting and at-rules' {

        It 'finds declarations inside @media and records the at-rule' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '@media (max-width: 600px) { .a { display: none } }')
                $result.Count | Should-Be 1
                $result[0].Selector | Should-Be '.a'
                $result[0].AtRule | Should-Be '@media (max-width: 600px)'
            }
        }

        It 'chains nested at-rules outermost first' {
            InModuleScope EntraBrandingCss {
                $css = '@media screen { @supports (display: grid) { .a { display: grid } } }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result[0].AtRule | Should-Be '@media screen > @supports (display: grid)'
            }
        }

        It 'does not treat the at-rule prelude as a declaration' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '@supports (position: sticky) { .a { color: red } }')
                $result.Property | Should-BeCollection @('color')
            }
        }

        It 'handles @container and @layer' {
            InModuleScope EntraBrandingCss {
                $css = '@container x (min-width: 1px) { .a { top: 0 } } @layer base { .b { left: 0 } }'
                $result = @(ConvertTo-CssDeclaration -Css $css)
                $result.AtRule | Should-BeCollection @('@container x (min-width: 1px)', '@layer base')
            }
        }

        It 'uses the innermost selector for CSS nesting' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { color: red; & .b { display: none } }')
                $result[1].Selector | Should-Be '& .b'
                $result[0].Selector | Should-Be '.a'
            }
        }

        It 'collapses a multi-line selector list onto one line' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css ".a,`n.b,`r`n   .c { display: none }")
                $result[0].Selector | Should-Be '.a, .b, .c'
            }
        }

        It 'survives a stray closing brace' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '} .a { display: none }')
                $result.Property | Should-BeCollection @('display')
            }
        }
    }

    Context 'positions and encodings' {

        It 'reports the line and column of the property name' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css ".a {`n    color: red;`n    display: none;`n}")
                $result[1].Line | Should-Be 3
                $result[1].Column | Should-Be 5
            }
        }

        It 'counts CRLF as one line break and does not count the CR in the column' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css ".a {`r`n    color: red;`r`n    display: none;`r`n}")
                $result[1].Line | Should-Be 3
                $result[1].Column | Should-Be 5
            }
        }

        It 'strips a byte order mark and counts columns from the first real character' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css ("{0}.a {{ display: none }}" -f [char]0xFEFF))
                $result[0].Column | Should-Be 6
                $result[0].Selector | Should-Be '.a'
            }
        }

        It 'parses minified CSS on one line' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a{color:red;display:none!important}.b{top:0}')
                $result.Property | Should-BeCollection @('color', 'display', 'top')
                $result[1].Important | Should-BeTrue
                $result[2].Selector | Should-Be '.b'
            }
        }
    }

    Context 'CSS escapes' {

        It 'decodes <Raw> to <Expected>' -ForEach @(
            @{ Raw = '\70 osition'; Expected = 'position' }
            @{ Raw = '\000070osition'; Expected = 'position' }
            @{ Raw = 'd\69 splay'; Expected = 'display' }
            @{ Raw = 'o\pacity'; Expected = 'opacity' }
            @{ Raw = 'z-\69ndex'; Expected = 'z-index' }
            @{ Raw = 'plain'; Expected = 'plain' }
        ) {
            InModuleScope EntraBrandingCss -Parameters @{ Raw = $Raw; Expected = $Expected } {
                param($Raw, $Expected)
                ConvertFrom-CssEscape -Text $Raw | Should-Be $Expected
            }
        }

        It 'replaces a null or out-of-range code point with U+FFFD' {
            InModuleScope EntraBrandingCss {
                ConvertFrom-CssEscape -Text '\0 x' | Should-Be ("{0}x" -f [char]0xFFFD)
                ConvertFrom-CssEscape -Text '\110000 x' | Should-Be ("{0}x" -f [char]0xFFFD)
            }
        }

        It 'reports an escaped property under its decoded name and flags it' {
            InModuleScope EntraBrandingCss {
                $result = @(ConvertTo-CssDeclaration -Css '.a { \70 osition: absolute; color: red }')
                $result[0].Property | Should-Be 'position'
                $result[0].RawProperty | Should-Be '\70 osition'
                $result[0].IsEscaped | Should-BeTrue
                $result[1].IsEscaped | Should-BeFalse
            }
        }
    }
}
