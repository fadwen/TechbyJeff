#Requires -RunAsAdministrator
<#
    Regenerates the output blocks flagged in "What the Intune Agent Counts as Installed".
    Run from an elevated Windows PowerShell 5.1 or PowerShell 7 prompt with IntuneScriptLab 0.30.0
    installed (or pass -ModulePath to a checkout). Everything it creates lives under
    C:\ProgramData\IslPost4 and HKLM:\SOFTWARE\(WOW6432Node\)IslPost4, and is removed at the end.

    Runs on x64 and on Windows on ARM: since 0.30.0 the harness picks the machine's own 64-bit host,
    and the base-requirement example asks for the architecture the machine is not, so it reads
    Not applicable on both.
#>
param([string]$ModulePath = 'IntuneScriptLab')

Import-Module $ModulePath -Force

# The architecture this machine is not, for the base-requirement example
$otherArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'x64' } else { 'arm64' }

$root = 'C:\ProgramData\IslPost4'
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
$app = New-Item -ItemType Directory -Path "$root\app" -Force
$fs = [System.IO.File]::Create("$root\app\data.bin"); $fs.SetLength(2621440); $fs.Dispose()
"IntuneScriptLab $((Get-Module IntuneScriptLab).Version), PowerShell $($PSVersionTable.PSVersion), $env:PROCESSOR_ARCHITECTURE"

"`n=== Opening: file DoesNotExist, absent then present"
Test-IntuneWin32Rule -Path $app.FullName -FileOrFolderName gone.txt -FileOperation DoesNotExist | Format-List Met, Reason
Test-IntuneWin32Rule -Path $app.FullName -FileOrFolderName data.bin -FileOperation DoesNotExist | Format-List Met, Reason

"`n=== Detection script with a Write-Error"
Set-Content -Path "$root\Detect-WithError.ps1" -Encoding ascii -Value @(
    '$v = Get-ItemPropertyValue -Path ''HKLM:\SOFTWARE\IslPost4\Missing'' -Name Version'
    'Write-Output "installed"'
    'exit 0'
)
Invoke-IntuneDetectionTest -Path "$root\Detect-WithError.ps1" -Context System |
    Format-List Detected, Reason, ExitCode, StdOut, RunAs

"`n=== Graph-shaped file rule"
$graphRule = @{
    '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemRule'
    ruleType             = 'detection'
    path                 = $app.FullName
    fileOrFolderName     = 'data.bin'
    check32BitOn64System = $false
    operationType        = 'sizeInMB'
    operator             = 'greaterThanOrEqual'
    comparisonValue      = '2'
}
Test-IntuneWin32Rule -Rule $graphRule | Format-List Met, Kind, Operation, Operator, Value, Actual, Reason

"`n=== Base requirement: an app for the architecture this machine is not ($otherArch)"
Test-IntuneWin32Requirement -Architecture $otherArch -MinimumMemoryMB 1024 | Format-List

"`n=== Whole app: the install command runs install.ps1 through powershell.exe"
# powershell.exe on the command line, or since 0.30.0 inside a .cmd or .bat the command line names,
# gets the 32-bit host warning.
$content = New-Item -ItemType Directory -Path "$root\content" -Force
Set-Content -Path "$content\install.ps1" -Encoding ascii -Value @(
    'New-Item -Path HKLM:\SOFTWARE\IslPost4 -Force | Out-Null'
    'Set-ItemProperty -Path HKLM:\SOFTWARE\IslPost4 -Name Version -Value 2.1'
    'exit 0'
)
Set-Content -Path "$root\Detect-App.ps1" -Encoding ascii -Value @(
    '$v = Get-ItemProperty -Path ''HKLM:\SOFTWARE\IslPost4'' -Name Version -ErrorAction SilentlyContinue'
    'if ($v -and [version]$v.Version -ge [version]''2.0'') { Write-Output "Version $($v.Version)"; exit 0 }'
    'exit 1'
)
$appSplat = @{
    DetectionPath  = "$root\Detect-App.ps1"
    ContentPath    = $content.FullName
    InstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1'
    Context        = 'System'
}
$result = Invoke-IntuneWin32AppTest @appSplat
$result | Format-List Status, Warnings, RunAs
"Value landed in WOW6432Node: $(Test-Path 'HKLM:\SOFTWARE\WOW6432Node\IslPost4')"

# Cleanup
Remove-Item 'HKLM:\SOFTWARE\WOW6432Node\IslPost4', 'HKLM:\SOFTWARE\IslPost4' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
"`nCleaned up."
