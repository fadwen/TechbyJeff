@{
    # The ruleset. Every detection this module makes is one entry here; the engine holds no
    # knowledge of WMIC at all, which is what lets a second deprecated command ship as a data
    # file rather than a rewrite.
    #
    # HOW A RULE MATCHES
    # Every key present in Match must hold, and within one key any listed value will do - so
    # Match is an AND of ORs. An empty Match matches every invocation, which is how the baseline
    # Mechanical rule works. The match keys the engine understands:
    #
    #   Region          Code | Comment
    #   Structure       Line | ForBlock | Assignment | TaskSequenceStep
    #   Invocation      Literal | Path | ComSpec | ProcessLauncher
    #   Capture         Redirect | Pipe | Variable    (how the output is consumed)
    #   Verb            get | set | call | list | create | delete | assoc | path | class
    #   Switch          node | user | password | output | append | value | every | repeat
    #   Alias           a WMIC alias name from WmicAliases.psd1
    #   AliasNonObvious $true to match only aliases flagged NonObvious in that file
    #   PropertyGroup   a group name from WmicProperties.psd1
    #   Context         a file-level context from Get-WmicFileContext
    #   Pattern         regex against the command text
    #   Snippet         regex against the whole region, which for a ForBlock is the whole block
    #
    # HOW A TIER IS CHOSEN
    # Every matching rule contributes its Id, and the finding takes the highest tier any of them
    # named. Highest means hardest to fix, not most severe: Mechanical < Wrapped < Semantic <
    # Environmental. So a mechanical one-liner sitting in a WinPE script is reported as
    # Environmental, because the question of whether PowerShell exists there outranks the ease of
    # the substitution. A rule with no Tier is a signal - it annotates the finding and shapes the
    # suggestion without moving the tier.
    #
    # SUGGESTIONS ARE ADVISORY, ALWAYS
    # Suggestion is a template filled by Get-WmicSuggestion. {Class} {Alias} {Properties} {Node}
    # {Verb} {Method} {Filter} are substituted. Nothing in this module applies a suggestion, and
    # for the Wrapped tier the honest suggestion is to restructure the block rather than a
    # command to paste - a one-line replacement there would be a lie, because the parsing around
    # the call is the part that actually breaks.
    #
    # WHY REASON AND SUGGESTION ARE ARRAYS
    # They are prose, and prose does not fit a 115-character line. A .psd1 is restricted
    # language, so concatenating with + is rejected by Import-PowerShellDataFile, and a
    # here-string would have to close at column zero in the middle of a nested hashtable. An
    # array of lines is what is left; Get-WmicRuleSet joins it with a single space on load.

    SchemaVersion = 1

    Rules = @(

        #--- Baseline -----------------------------------------------------------------------

        @{
            Id     = 'WMIC001'
            Name   = 'WMIC invocation'
            Tier   = 'Mechanical'
            Match  = @{}
            Reason = @(
                'WMIC is deprecated and absent from recent Windows images. Nothing at this call'
                'site suggests the output is consumed, so the command can be swapped on its own.'
            )
            Suggestion = @(
                'Get-CimInstance -ClassName {Class} | Select-Object {Properties}'
            )
        }

        @{
            Id     = 'WMIC002'
            Name   = 'WMIC in a comment'
            Match  = @{ Region = @('Comment') }
            Reason = @(
                'Commented-out or documented WMIC. It will not fail, but it is the example the'
                'next person copies, so it outlives the code that was fixed.'
            )
            Suggestion = @(
                'Update or delete the comment when the surrounding code is migrated.'
            )
        }

        #--- Wrapped: the output is consumed, so the wrapper has to move too -----------------

        @{
            Id     = 'WMIC100'
            Name   = 'Output parsed by a for /f block'
            Tier   = 'Wrapped'
            Match  = @{ Structure = @('ForBlock') }
            Reason = @(
                'A for /f block parses this output by token position. Get-CimInstance returns'
                'objects rather than the padded table for /f was written against, so the tokens='
                'and delims= spec has to be replaced by property access, not adjusted.'
            )
            Suggestion = @(
                'Restructure the block. Replace the for /f and its tokens/delims spec with direct'
                'property access on the object: (Get-CimInstance {Class}).{Properties}'
            )
        }

        @{
            Id     = 'WMIC101'
            Name   = 'Output redirected to a file'
            Tier   = 'Wrapped'
            Match  = @{ Capture = @('Redirect') }
            Reason = @(
                'The output is written to a file, so something downstream reads it in the WMIC'
                'text layout. That reader has to change with the command.'
            )
            Suggestion = @(
                'Restructure. Find the reader of this file first, then choose a format it can'
                'keep using - Export-Csv is usually closer than the WMIC table was.'
            )
        }

        @{
            Id     = 'WMIC102'
            Name   = 'Output captured with /output: or /append:'
            Tier   = 'Wrapped'
            Match  = @{ Switch = @('output', 'append') }
            Reason = @(
                'WMIC is writing its own output file, which means a consumer exists somewhere for'
                'the WMIC layout specifically.'
            )
            Suggestion = @(
                'Restructure. There is no /output: equivalent - the pipeline decides where output'
                'goes, so locate the consumer before picking Export-Csv or Out-File.'
            )
        }

        @{
            Id     = 'WMIC103'
            Name   = 'Output piped to another command'
            Tier   = 'Wrapped'
            Match  = @{ Capture = @('Pipe') }
            Reason = @(
                'The output is piped into a text tool such as find or findstr, which matches'
                'against the WMIC table layout including its column padding.'
            )
            Suggestion = @(
                'Restructure. Replace the text filter with Where-Object on a real property:'
                'Get-CimInstance {Class} | Where-Object ...'
            )
        }

        @{
            Id     = 'WMIC104'
            Name   = 'Format switch implying downstream parsing'
            Tier   = 'Wrapped'
            Match  = @{ Pattern = '(?i)(/value\b|/format:\s*"?(csv|list|value|mof|xml|rawxml))' }
            Reason = @(
                'A machine-readable format switch is only worth using when something parses the'
                'result. That parser is written against the WMIC serialisation and does not'
                'survive the swap.'
            )
            Suggestion = @(
                'Restructure. The format switch exists for a parser - port the parser to property'
                'access and the switch has nothing left to do.'
            )
        }

        @{
            Id     = 'WMIC105'
            Name   = 'Output captured into a variable'
            Tier   = 'Wrapped'
            Match  = @{ Capture = @('Variable') }
            Reason = @(
                'The output is assigned rather than displayed, so the code reading that variable'
                'expects WMIC text and will keep running against something else.'
            )
            Suggestion = @(
                'Restructure. Assign the object instead of its text, then replace the string'
                'handling that follows with property access.'
            )
        }

        #--- Semantic: the correct translation is a judgment call ----------------------------

        @{
            Id     = 'WMIC200'
            Name   = 'Win32_Product enumeration'
            Tier   = 'Semantic'
            Match  = @{ Alias = @('product') }
            Reason = @(
                'Enumerating Win32_Product triggers an MSI consistency check on every installed'
                'product, which is slow and can reconfigure or repair packages as a side effect.'
                'Get-CimInstance Win32_Product does exactly the same thing, so a like-for-like'
                'swap keeps the real problem.'
            )
            Suggestion = @(
                'Do not translate this directly. Read the Uninstall registry keys instead, under'
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall and its Wow6432Node'
                'counterpart, or use Get-Package.'
            )
        }

        @{
            Id     = 'WMIC201'
            Name   = 'Datetime or interval property'
            Tier   = 'Semantic'
            Match  = @{ PropertyGroup = @('DateTime', 'Interval') }
            Reason = @(
                'WMIC prints these in DMTF form - 20250314093000.000000-300 - and Get-CimInstance'
                'returns a real DateTime or TimeSpan. Substring or arithmetic written against the'
                'DMTF text keeps running and produces a wrong answer rather than an error.'
            )
            Suggestion = @(
                'Judgment call. Get-CimInstance already converts these, so the DMTF parsing around'
                'the call should be deleted rather than ported. Check what the result is compared'
                'against.'
            )
        }

        @{
            Id     = 'WMIC202'
            Name   = 'Multi-value property'
            Tier   = 'Semantic'
            Match  = @{ PropertyGroup = @('MultiValue') }
            Reason = @(
                'WMIC renders arrays in braces. Get-CimInstance returns an array. Code that'
                'treated the braced text as one value now sees a collection, and code that took'
                'the whole field as the answer now takes a type name or only the first element.'
            )
            Suggestion = @(
                'Judgment call. Decide explicitly which element is wanted -'
                '(Get-CimInstance {Class}).{Properties}[0] is rarely right for an interface with'
                'more than one address.'
            )
        }

        @{
            Id     = 'WMIC203'
            Name   = 'Boolean property compared as text'
            Tier   = 'Semantic'
            Match  = @{ PropertyGroup = @('Boolean') }
            Reason = @(
                'WMIC prints TRUE and FALSE in upper case. PowerShell gives a bool that'
                'stringifies to True and False, so a case-sensitive comparison against TRUE stops'
                'matching - and a comparison that stops matching takes the other branch silently.'
            )
            Suggestion = @(
                'Judgment call. Compare the boolean directly rather than its text, and check which'
                'branch the call site takes when the comparison fails.'
            )
        }

        @{
            Id     = 'WMIC204'
            Name   = 'Remote invocation with /node:'
            Tier   = 'Semantic'
            Match  = @{ Switch = @('node') }
            Reason = @(
                'WMIC /node: opens a DCOM connection per invocation. The replacement is a CIM'
                'session, which is WSMan by default - a different protocol, different ports, and'
                'different failure modes on hosts where WinRM was never configured.'
            )
            Suggestion = @(
                'Judgment call. New-CimSession -ComputerName {Node} then Get-CimInstance'
                '-CimSession. Add -SessionOption (New-CimSessionOption -Protocol Dcom) only if'
                'WinRM is genuinely unavailable on the targets.'
            )
        }

        @{
            Id     = 'WMIC205'
            Name   = 'Method invocation'
            Tier   = 'Semantic'
            Match  = @{ Verb = @('call') }
            Reason = @(
                'This calls a WMI method rather than reading a property, so it changes state.'
                'Argument names and order differ between the WMIC call syntax and Invoke-CimMethod,'
                'and a wrongly bound argument executes rather than failing.'
            )
            Suggestion = @(
                'Judgment call. Invoke-CimMethod -ClassName {Class} -MethodName {Method}'
                '-Arguments @{}. Check the result - WMIC prints the return code, Invoke-CimMethod'
                'returns it as ReturnValue.'
            )
        }

        @{
            Id     = 'WMIC206'
            Name   = 'Property assignment'
            Tier   = 'Semantic'
            Match  = @{ Verb = @('set') }
            Reason = @(
                'This writes a property. Set-CimInstance needs the instance identified first, so'
                'the WMIC where-clause becomes a separate retrieval step and the write applies to'
                'whatever that retrieval returned.'
            )
            Suggestion = @(
                'Judgment call. Retrieve with Get-CimInstance {Class} -Filter "{Filter}", confirm'
                'the instance count, then pipe to Set-CimInstance -Property @{}.'
            )
        }

        @{
            Id     = 'WMIC207'
            Name   = 'Instance creation or deletion'
            Tier   = 'Semantic'
            Match  = @{ Verb = @('create', 'delete') }
            Reason = @(
                'This creates or removes an instance. The failure mode of a mistranslated'
                'where-clause is deleting the wrong instances, and it will not announce itself.'
            )
            Suggestion = @(
                'Judgment call. New-CimInstance or Remove-CimInstance, after confirming with'
                'Get-CimInstance -Filter "{Filter}" exactly which instances that filter selects.'
            )
        }

        @{
            Id     = 'WMIC208'
            Name   = 'Association traversal'
            Tier   = 'Semantic'
            Match  = @{ Verb = @('assoc') }
            Reason = @(
                'WMIC assoc walks WMI associations and flattens whatever it finds into text. There'
                'is no flat equivalent; the replacement returns objects of several classes and the'
                'caller has to decide which of them it wanted.'
            )
            Suggestion = @(
                'Judgment call. Get-CimAssociatedInstance, naming -ResultClassName explicitly'
                'rather than accepting everything the association returns.'
            )
        }

        @{
            Id     = 'WMIC209'
            Name   = 'Polling with /every: or /repeat:'
            Tier   = 'Semantic'
            Match  = @{ Switch = @('every', 'repeat') }
            Reason = @(
                'WMIC polls on its own. Nothing in PowerShell does this for you, so the loop, its'
                'interval and its exit condition all have to be written - and the exit condition'
                'is the part WMIC never had.'
            )
            Suggestion = @(
                'Judgment call. Write the loop explicitly with Start-Sleep and decide what ends'
                'it. Register-CimIndicationEvent is the better fit if the goal was reacting to a'
                'change.'
            )
        }

        @{
            Id     = 'WMIC210'
            Name   = 'WMIC path held in a variable'
            Tier   = 'Semantic'
            Match  = @{ Structure = @('Assignment') }
            Reason = @(
                'The path to wmic.exe is stored in a variable. This scanner does not resolve'
                'variables, so the call sites of this variable are NOT in these results - the'
                'count you are reading is an undercount until someone greps for this variable by'
                'hand.'
            )
            Suggestion = @(
                'Judgment call. Find the call sites of this variable manually. They are not in'
                'this report.'
            )
        }

        #--- Environmental: PowerShell may not exist at the call site -------------------------

        @{
            Id     = 'WMIC300'
            Name   = 'WMIC in a WinPE context'
            Tier   = 'Environmental'
            Match  = @{ Context = @('WinPE') }
            Reason = @(
                'This file runs under WinPE. A boot image only has PowerShell if the'
                'WinPE-PowerShell optional component was added to it, so the substitution may not'
                'be available at all - and the failure lands during deployment, where nobody is'
                'watching a console.'
            )
            Suggestion = @(
                'Environment first. Confirm WinPE-PowerShell and WinPE-WMI are in the boot image'
                'before migrating this, or keep the call and pin the image.'
            )
        }

        @{
            Id     = 'WMIC301'
            Name   = 'WMIC in a pre-install task sequence step'
            Tier   = 'Environmental'
            Match  = @{ Context = @('TaskSequenceWinPE') }
            Reason = @(
                'This step runs in the pre-install phase, which is WinPE. The same boot image'
                'question applies, and a task sequence failure here rolls back the whole'
                'deployment.'
            )
            Suggestion = @(
                'Environment first. Confirm the boot image carries PowerShell, or move the step'
                'into the full OS phase where it is guaranteed.'
            )
        }

        #--- Signals: no tier of their own, but they change what the report says --------------

        @{
            Id     = 'WMIC400'
            Name   = 'Invoked through the command interpreter'
            Match  = @{ Invocation = @('ComSpec') }
            Reason = @(
                'Reached through %COMSPEC% /c rather than called directly, so a search for lines'
                'beginning with wmic would have missed it.'
            )
            Suggestion = @(
                'No change to the tier. Noted because inventories built by grepping for a leading'
                'wmic undercount these.'
            )
        }

        @{
            Id     = 'WMIC401'
            Name   = 'Invoked by full path'
            Match  = @{ Invocation = @('Path') }
            Reason = @(
                'Called by its path under System32\wbem rather than by name. Same undercount'
                'problem as %COMSPEC%, and it also survives a PATH change that would otherwise'
                'have surfaced the breakage early.'
            )
            Suggestion = @(
                'No change to the tier. Noted because a bare wmic grep misses it.'
            )
        }

        @{
            Id     = 'WMIC402'
            Name   = 'Launched by a process launcher'
            Match  = @{ Invocation = @('ProcessLauncher') }
            Reason = @(
                'Started through Start-Process, WScript.Shell or subprocess rather than run'
                'inline, so exit code and output handling are the launcher API problem rather'
                'than the shell default.'
            )
            Suggestion = @(
                'No change to the tier. Check how the launcher reads the result - that is where'
                'the WMIC text layout is assumed.'
            )
        }

        @{
            Id     = 'WMIC403'
            Name   = 'Alias whose class is not guessable'
            Match  = @{ AliasNonObvious = $true }
            Reason = @(
                'The WMIC alias does not resemble the class it maps to, so the reader cannot get'
                'from the old command to the new one without a lookup.'
            )
            Suggestion = @(
                'No change to the tier. The lookup is already done: {Alias} is {Class}.'
            )
        }

        #--- Security: reported alongside the deprecation finding, not instead of it -----------

        @{
            Id     = 'WMIC900'
            Kind   = 'Security'
            Name   = 'Credentials on the command line'
            Tier   = 'Semantic'
            Match  = @{ Switch = @('password') }
            Reason = @(
                'A password is passed on the command line. It is visible to any local process'
                'listing, and in a checked-in batch file it is plain text in source control. This'
                'is worth fixing whether or not the WMIC call is ever migrated.'
            )
            Suggestion = @(
                'Independent of the migration. Take the credential off the command line - use the'
                'calling account, or Get-Credential feeding New-CimSession - and rotate the'
                'exposed password.'
            )
        }
    )
}
