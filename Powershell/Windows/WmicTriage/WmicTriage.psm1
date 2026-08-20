#Requires -Version 5.1

# WmicTriage PowerShell Module
# Finds deprecated WMIC usage across a codebase and classifies each hit by the effort its
# replacement will take, rather than reporting a flat list of matches. PSScriptAnalyzer and a
# grep both already tell you whether WMIC is present. Neither tells you that this particular
# call sits inside a for /f block whose tokens= spec silently stops meaning anything once the
# command returns objects, and that is the hit which costs a day rather than a minute.

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing WmicTriage module from: $ModuleRoot"

$script:ModuleRoot = $ModuleRoot

# Import Private functions
$privateFunctions = Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $privateFunctions) {
    Write-Verbose "Loading private function: $($function.Name)"
    . $function.FullName
}

# Import Public functions
$publicFunctions = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $publicFunctions) {
    Write-Verbose "Loading public function: $($function.Name)"
    . $function.FullName
}

# The tier ordering. This is an ordering of effort, not of severity, and the difference matters
# because it is what the escalation rule means: when several rules match one call, the finding
# takes the highest rank, so a mechanical one-liner inside a WinPE script is reported as
# Environmental. The substitution really is trivial; the question of whether PowerShell exists in
# that boot image is not, and it has to be answered first.
$script:TierRank = [ordered]@{
    Mechanical    = 1
    Wrapped       = 2
    Semantic      = 3
    Environmental = 4
}

# Which tiers a CI job should fail on. Mechanical and Wrapped are mechanically checkable: a human
# has nothing to decide, so a build can insist they be fixed. Semantic and Environmental both end
# in a judgment call, and failing a build on a judgment call teaches people to bypass the check.
# This module never calls exit - a module that terminates its host is a module you cannot use from
# another script - so the verdict rides on each finding's FailsBuild property and on the SARIF
# severity level instead.
$script:FailingTiers = @('Mechanical', 'Wrapped')

# Extension to reader mapping. .bat and .cmd lead because they are the gap: PSScriptAnalyzer never
# sees them, so they are where an inventory is most likely to be wrong.
$script:FileTypeMap = @{
    '.bat'  = 'Batch'
    '.cmd'  = 'Batch'
    '.ps1'  = 'PowerShell'
    '.psm1' = 'PowerShell'
    '.vbs'  = 'VBScript'
    '.vbe'  = 'VBScript'
    '.wsf'  = 'VBScript'
    '.js'   = 'JScript'
    '.py'   = 'Python'
    '.xml'  = 'TaskSequence'
}

# Per-language knowledge the readers and the invocation finder need: what a comment looks like,
# what quotes a string, what capturing output looks like, and what launching a process looks like.
#
# QuoteCharacter is the one that bites. An apostrophe delimits a string in PowerShell, JScript and
# Python, and is just an apostrophe in batch - where treating it as a quote would run every echoed
# "don't" into the command on the following line. Getting this wrong does not throw; it produces a
# command in the report with half the host language stapled to the end of it.
#
# This table lives here rather than in Data\ on purpose. Data\ holds the ruleset - the part meant
# to be edited by whoever is doing a migration, and the part that makes a second deprecated command
# a data change. This is engine internals: adding a language means writing a reader as well, so
# presenting it as configuration would be a lie about how extensible it is.
$script:LanguageProfile = @{
    PowerShell = @{
        LineComment       = @('#')
        BlockCommentStart = '<#'
        BlockCommentEnd   = '#>'
        QuoteCharacter    = @('"', "'")
        # Only used by the fallback reader; the AST gives better answers when the file parses
        Capture           = @{ Variable = '(?i)(\$\w+\s*=[^=]|\$\(|@\()' }
        Invocation        = @{ ProcessLauncher = '(?i)\b(Start-Process|Invoke-Expression|iex)\b' }
    }
    VBScript   = @{
        LineComment       = @("'", 'rem')
        BlockCommentStart = $null
        BlockCommentEnd   = $null
        # Only the double quote: VBScript uses the apostrophe to start a comment, not a string
        QuoteCharacter    = @('"')
        # .Exec returns an object whose StdOut is read; .Run does not, so only Exec is a capture
        Capture           = @{ Variable = '(?i)\.Exec\s*\(' }
        Invocation        = @{ ProcessLauncher = '(?i)(WScript\.Shell|\.Run\b|\.Exec\b)' }
    }
    JScript    = @{
        LineComment       = @('//')
        BlockCommentStart = '/*'
        BlockCommentEnd   = '*/'
        QuoteCharacter    = @('"', "'")
        Capture           = @{ Variable = '(?i)\.Exec\s*\(' }
        Invocation        = @{ ProcessLauncher = '(?i)(WScript\.Shell|ActiveXObject|\.Run\b|\.Exec\b)' }
    }
    Python     = @{
        LineComment       = @('#')
        BlockCommentStart = $null
        BlockCommentEnd   = $null
        QuoteCharacter    = @('"', "'")
        Capture           = @{ Variable = '(?i)(check_output|popen|communicate|capture_output\s*=\s*True)' }
        Invocation        = @{ ProcessLauncher = '(?i)(subprocess\.|os\.system|os\.popen)' }
    }
    Batch      = @{
        LineComment       = @('rem', '::')
        BlockCommentStart = $null
        BlockCommentEnd   = $null
        QuoteCharacter    = @('"')
        Capture           = @{}
        Invocation        = @{ ProcessLauncher = '(?i)\b(start)\s' }
    }
    TaskSequence = @{
        LineComment       = @()
        BlockCommentStart = $null
        BlockCommentEnd   = $null
        QuoteCharacter    = @('"')
        Capture           = @{}
        Invocation        = @{}
    }
}

# Cache for the parsed ruleset, populated on first use by Get-WmicRuleSet
$script:RuleSet = $null

# Default table view. Without this a finding prints twenty-odd columns and wraps into porridge;
# the four below are the ones that decide what a reader does next.
Update-TypeData -TypeName 'WmicTriage.Finding' -DefaultDisplayPropertySet @(
    'Tier', 'RelativePath', 'Line', 'Command'
) -Force -ErrorAction SilentlyContinue

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-WmicScan',
    'Export-WmicScanReport',
    'Get-WmicRule'
)

# Module cleanup on removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up WmicTriage module"
    Remove-Variable -Name RuleSet -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name TierRank -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name FailingTiers -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name FileTypeMap -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name LanguageProfile -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ModuleRoot -Scope Script -ErrorAction SilentlyContinue
}
