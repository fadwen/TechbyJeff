function Read-WmicScriptRegion {
    <#
    .SYNOPSIS
        Splits a line-oriented script into regions, tracking comment state

    .DESCRIPTION
        The reader for VBScript, JScript and Python, and the fallback for a PowerShell file that
        will not parse. It works a line at a time, tracking whether it is inside a block comment,
        and reads the comment markers and capture patterns for the language out of the module's
        language profile.

        This reader is deliberately less clever than the other two. There is no tree to consult
        and no block structure worth reconstructing, so capture detection here is a regex against
        the line - .Exec in VBScript, check_output in Python - and it will be wrong occasionally.
        That is an honest limit rather than a hidden one: these languages are a minority of any
        estate that still runs WMIC, and building three more parsers to serve them would trade
        the batch coverage that actually matters for coverage that mostly is not there.

        A comment marker only opens a comment at the start of a line, after whitespace. Testing
        anywhere on the line would classify every Python dictionary and every VBScript string
        containing an apostrophe as a comment, which would move real findings into the tier that
        does not fail a build.

    .PARAMETER Content
        [System.String] (Mandatory, No Pipeline Support)

        The full text of the file.

    .PARAMETER FileType
        [System.String] (Mandatory, No Pipeline Support)

        Which language profile to read comment and capture patterns from.

    .OUTPUTS
        Region hashtables carrying Kind, Structure, Text, Snippet, StartLine, EndLine, Lines and
        Detail.

    .EXAMPLE
        $regions = Read-WmicScriptRegion -Content $text -FileType VBScript

        DESCRIPTION: Splits a VBScript inventory script into regions
        OUTPUT: One region per line, comments marked as such
        USE CASE: Scanning the logon scripts nobody has opened since 2011

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
        [string]$Content,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileType
    )

    $profileEntry = $script:LanguageProfile[$FileType]
    if ($null -eq $profileEntry) {
        Write-Verbose "No language profile for $FileType; treating every line as code"
        $profileEntry = @{ LineComment = @(); BlockCommentStart = $null; BlockCommentEnd = $null; Capture = @{} }
    }

    $lines = $Content -split "`r?`n"
    $inBlockComment = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $text = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $kind = 'Code'
        $trimmed = $text.TrimStart()

        if ($inBlockComment) {
            $kind = 'Comment'
            if ($profileEntry.BlockCommentEnd -and $text.Contains($profileEntry.BlockCommentEnd)) {
                $inBlockComment = $false
            }
        }
        elseif ($profileEntry.BlockCommentStart -and $trimmed.StartsWith($profileEntry.BlockCommentStart)) {
            $kind = 'Comment'
            if (-not $text.Contains($profileEntry.BlockCommentEnd)) { $inBlockComment = $true }
        }
        else {
            foreach ($marker in $profileEntry.LineComment) {
                # Only at the start of the line: an apostrophe mid-line is a string in every one
                # of these languages far more often than it is a comment
                if ($trimmed.StartsWith($marker, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $kind = 'Comment'
                    break
                }
            }
        }

        if ($text -notmatch '(?i)wmic') { continue }

        $capture = @()
        foreach ($captureName in $profileEntry.Capture.Keys) {
            if ($text -match $profileEntry.Capture[$captureName]) { $capture += $captureName }
        }

        [PSCustomObject]@{
            Kind      = $kind
            Structure = 'Line'
            Text      = $text
            Snippet   = $text
            StartLine = $i + 1
            EndLine   = $i + 1
            Lines     = @(@{ Number = $i + 1; Text = $text })
            Detail    = @{ Capture = $capture }
        }
    }
}
