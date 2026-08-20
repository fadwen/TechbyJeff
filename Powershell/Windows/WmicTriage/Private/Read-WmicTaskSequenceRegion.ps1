function Read-WmicTaskSequenceRegion {
    <#
    .SYNOPSIS
        Reads an MDT or Configuration Manager task sequence and reports the step a WMIC call sits in

    .DESCRIPTION
        Parses the XML rather than grepping it, so a finding can name the task sequence step
        instead of a line number.

        That is the entire justification for a separate reader here. A line number in an exported
        task sequence is close to useless - nobody edits the XML, and the number will not survive
        the next export - whereas the step name is what the console shows and what somebody can
        actually go and open. The command also lives in a specific place, a CommandLine variable
        or an action element, so parsing removes the false positives a regex would collect from
        descriptions and condition text.

        The phase matters as much as the step. A step running in WinPE may have no PowerShell at
        all, so those findings are marked TaskSequenceWinPE and escalate to Environmental. Phase
        is read from the step's runIn attribute where the export carries one, and otherwise from
        the names of the groups the step sits in, which is weaker but is all a hand-built
        sequence gives you.

        Line numbers are recovered by finding the command text back in the raw file, because
        XmlDocument does not keep them. An approximate line beats no line: it makes the finding
        clickable in an editor without pretending to a precision the format does not have.

        A file that is not valid XML falls through to the line reader. A .xml extension is not a
        promise, and half the deployment shares in the world have a truncated export in them.

    .PARAMETER Content
        [System.String] (Mandatory, No Pipeline Support)

        The full text of the XML file.

    .OUTPUTS
        Region hashtables whose Detail carries StepName, GroupPath, RunIn and Context.

    .EXAMPLE
        $regions = Read-WmicTaskSequenceRegion -Content (Get-Content .\Deploy-W11.xml -Raw)

        DESCRIPTION: Finds WMIC calls in an exported task sequence
        OUTPUT: One region per step containing a WMIC command, named by step
        USE CASE: Reporting to whoever owns the sequence in which step to open

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

    $document = $null
    try {
        $document = [xml]$Content
    }
    catch {
        Write-Verbose "XML did not parse, falling back to the line reader: $($_.Exception.Message)"
        Read-WmicScriptRegion -Content $Content -FileType 'TaskSequence'
        return
    }

    if ($null -eq $document.DocumentElement) { return }

    $lines = $Content -split "`r?`n"
    $wmicPattern = '(?i)(?<![\w.])wmic(\.exe)?(?![\w])'

    foreach ($element in $document.SelectNodes('//*')) {
        $values = [System.Collections.Generic.List[object]]::new()

        foreach ($attribute in $element.Attributes) {
            if ($attribute.Value -match $wmicPattern) {
                $values.Add(@{ Text = $attribute.Value; Source = "@$($attribute.Name)" })
            }
        }

        # Direct text children only. Taking InnerText would re-report every ancestor of the
        # command, one finding per level of the tree.
        foreach ($child in $element.ChildNodes) {
            if ($child.NodeType -ne [System.Xml.XmlNodeType]::Text -and
                $child.NodeType -ne [System.Xml.XmlNodeType]::CDATA) {
                continue
            }
            if ($child.Value -match $wmicPattern) {
                $values.Add(@{ Text = $child.Value; Source = $element.LocalName })
            }
        }

        if ($values.Count -eq 0) { continue }

        # Walk to the enclosing step, collecting the groups on the way. The nearest ancestor with
        # a name attribute is usually the variable element itself, which is why this looks for a
        # step specifically rather than taking the first name it finds.
        $stepName = $null
        $runIn = $null
        $groups = [System.Collections.Generic.List[string]]::new()
        $node = $element

        while ($null -ne $node -and $node.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            if ($node.LocalName -match '(?i)^step$') {
                if (-not $stepName) {
                    $stepName = $node.GetAttribute('name')
                    $runIn = $node.GetAttribute('runIn')
                }
            }
            elseif ($node.LocalName -match '(?i)^group$') {
                $groupName = $node.GetAttribute('name')
                if ($groupName) { $groups.Insert(0, $groupName) }
            }
            $node = $node.ParentNode
        }

        $groupPath = ($groups -join ' / ')

        $context = @()
        if ($runIn -and $runIn -match '(?i)winpe') {
            $context += 'TaskSequenceWinPE'
        }
        elseif (-not $runIn -and $groupPath -match '(?i)(preinstall|winpe|boot\s*image)') {
            $context += 'TaskSequenceWinPE'
        }

        foreach ($value in $values) {
            $line = Find-WmicTextLine -Line $lines -Needle $value.Text

            [PSCustomObject]@{
                Kind      = 'Code'
                Structure = 'TaskSequenceStep'
                Text      = $value.Text
                Snippet   = $value.Text
                StartLine = $line
                EndLine   = $line
                Lines     = @(@{ Number = $line; Text = $value.Text })
                Detail    = @{
                    StepName  = $stepName
                    GroupPath = $groupPath
                    RunIn     = $runIn
                    Source    = $value.Source
                    Context   = $context
                }
            }
        }
    }
}
