function Get-WmicFileContext {
    <#
    .SYNOPSIS
        Decides whether a file runs somewhere PowerShell might not exist

    .DESCRIPTION
        Returns the execution contexts that apply to a whole file. Today that means one thing
        that matters: WinPE.

        This is what makes the Environmental tier possible, and it is the only tier that depends
        on where a file runs rather than what it contains. A boot image has PowerShell only if
        someone added the WinPE-PowerShell optional component to it, so the substitution this
        tool recommends everywhere else may simply not be available - and the way that failure
        surfaces is a task sequence dying at 2am with nobody watching the console.

        Detection is by three signals, any one of which is enough:

        - The file name. startnet.cmd and winpeshl.ini only exist in a boot image.
        - Commands that only exist in WinPE: wpeinit, wpeutil, drvload. A script calling one of
          these is telling you where it runs more reliably than its path does.
        - The X: drive, which is what WinPE calls its RAM disk and nothing else ever is.

        A path segment named winpe counts too, but on its own it is weak - people name folders
        after the thing the script deploys as often as after where it runs - so it is treated as
        a signal of equal standing rather than a stronger one, and any single hit is enough.

        Being wrong here is asymmetric, which is why the signals are generous. A false positive
        moves a finding from Mechanical to Environmental: it stops failing a build and gets read
        by a human, which costs a few minutes. A false negative fails a deployment.

    .PARAMETER Path
        [System.String] (Mandatory, No Pipeline Support)

        Full path to the file. Used for the name and path-segment signals.

    .PARAMETER Content
        [System.String] (Optional, No Pipeline Support)

        The file's text, for the content signals. Omit it and only the path signals apply.

    .PARAMETER FileType
        [System.String] (Optional, No Pipeline Support)

        The reader handling this file. A task sequence is always tagged TaskSequence; whether a
        given step is also WinPE is decided per step by Read-WmicTaskSequenceRegion, because one
        task sequence spans both phases.

    .OUTPUTS
        System.String[] - zero or more context names. Empty means an ordinary full-OS script.

    .EXAMPLE
        Get-WmicFileContext -Path 'C:\Boot\startnet.cmd' -Content $text -FileType Batch

        DESCRIPTION: Classifies a boot image startup script
        OUTPUT: WinPE
        USE CASE: Escalating every finding in that file to the Environmental tier

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter()]
        [string]$FileType
    )

    $contexts = @()

    $leaf = (Split-Path -Path $Path -Leaf).ToLowerInvariant()
    $winPeNames = @('startnet.cmd', 'winpeshl.ini')

    $isWinPe = $false

    if ($winPeNames -contains $leaf) {
        $isWinPe = $true
        Write-Verbose "WinPE context: file is named $leaf"
    }

    if (-not $isWinPe -and $Path -match '(?i)[\\/]winpe([\\/]|$)') {
        $isWinPe = $true
        Write-Verbose 'WinPE context: winpe path segment'
    }

    if (-not $isWinPe -and -not [string]::IsNullOrEmpty($Content)) {
        # wpeinit and friends do not exist outside a boot image, and X: is the WinPE RAM disk
        if ($Content -match '(?i)(?<![\w-])(wpeinit|wpeutil|drvload)(?![\w-])') {
            $isWinPe = $true
            Write-Verbose 'WinPE context: WinPE-only command present'
        }
        elseif ($Content -match '(?i)(?<![\w:])X:\\[Ww]indows') {
            $isWinPe = $true
            Write-Verbose 'WinPE context: X: RAM disk path present'
        }
    }

    if ($isWinPe) { $contexts += 'WinPE' }

    if ($FileType -eq 'TaskSequence') { $contexts += 'TaskSequence' }

    return $contexts
}
