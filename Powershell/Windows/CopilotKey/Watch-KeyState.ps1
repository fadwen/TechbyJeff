#Requires -Version 5.1

<#
.SYNOPSIS
    Logs every key transition the system reports, after any remapping, for a short window.

.DESCRIPTION
    Polls GetAsyncKeyState for every virtual key about 200 times a second and writes a line
    for each down or up transition, with a timestamp and the key's name. Because it reads the
    key state the system exposes to applications, it shows the result of whatever sits between
    the keyboard and you: the Windows "Customize Copilot key" setting, PowerToys Keyboard
    Manager, or nothing at all.

    Written to answer one question for the Tech by Jeff post on PowerToys and the Copilot key:
    what does the Copilot key on a Surface Pro 11 send with Keyboard Manager switched off and
    the Windows setting on Right control? The answer was virtual-key 0x5D, Apps, on its own.

    Mouse buttons are ignored. Esc ends the capture early.

.PARAMETER Seconds
    How long to listen before giving up. Default 60.

.PARAMETER LogPath
    Optional file to append the same lines to, so you can read them after the window closes.

.EXAMPLE
    .\Watch-KeyState.ps1 -Seconds 90

    Then tap the key you are curious about, hold it with another key, and press Esc.

.EXAMPLE
    .\Watch-KeyState.ps1 -Seconds 240 -LogPath "$env:TEMP\keys.log"

    Same, with the lines kept in a file.

.NOTES
    Run it from the session you type in. GetAsyncKeyState reports the state for the calling
    session, so a script scheduled under another account sees nothing. It also sees keys you
    press in other windows while it runs, which is the point, so close anything you would
    rather not have logged.

    Blog post: https://techbyjeff.net/powertoys-tour-and-the-copilot-key/
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$Seconds = 60,

    [string]$LogPath
)

Add-Type -Namespace TechbyJeff -Name KeyState -MemberDefinition @'
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
'@
Add-Type -AssemblyName System.Windows.Forms

# Names for the log: the Keys enum covers most of the table; a few are spelled out so the
# modifier and Copilot-related codes read the way the post refers to them.
$names = @{}
foreach ($value in [enum]::GetValues([System.Windows.Forms.Keys])) {
    $code = [int]$value
    if ($code -gt 0 -and $code -lt 256 -and -not $names.ContainsKey($code)) { $names[$code] = $value.ToString() }
}
$names[0x5B] = 'LWin'
$names[0x5C] = 'RWin'
$names[0x5D] = 'Apps'
$names[0x86] = 'F23'
$names[0xA0] = 'LShiftKey'
$names[0xA1] = 'RShiftKey'
$names[0xA2] = 'LControlKey'
$names[0xA3] = 'RControlKey'
$names[0xA4] = 'LMenu'
$names[0xA5] = 'RMenu'

$mouseButtons = 0x01, 0x02, 0x04, 0x05, 0x06
$state = New-Object bool[] 256
$clock = [System.Diagnostics.Stopwatch]::StartNew()

function Write-Line {
    param([string]$Text)
    Write-Output $Text
    if ($LogPath) { Add-Content -Path $LogPath -Value $Text }
}

Write-Line "listening $Seconds s (Esc ends early)"

while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    for ($vk = 1; $vk -lt 256; $vk++) {
        if ($vk -in $mouseButtons) { continue }
        $down = ([TechbyJeff.KeyState]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
        if ($down -eq $state[$vk]) { continue }
        $state[$vk] = $down
        $name = if ($names.ContainsKey($vk)) { $names[$vk] } else { 'VK_{0:X2}' -f $vk }
        $edge = if ($down) { 'DOWN' } else { 'UP' }
        Write-Line ('{0,8:F3}s  {1,-5} 0x{2:X2} {3}' -f $clock.Elapsed.TotalSeconds, $edge, $vk, $name)
        if ($vk -eq 0x1B -and -not $down) {
            Write-Line 'ended by Esc'
            return
        }
    }
    Start-Sleep -Milliseconds 4
}

Write-Line 'ended by timeout'
