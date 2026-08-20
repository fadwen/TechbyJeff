# Examples

A small fake deployment share to point the scanner at, so you can see what the
tiers look like before running it against anything real.

```powershell
Import-Module ..\WmicTriage.psd1
Invoke-WmicScan -Path .\DeploymentShare
```

Nothing here executes. These are input files, written the way the scripts in a
real estate are written — a collector carried forward from an XP rollout, a
vendor file nobody may edit, a migration somebody started and abandoned. They
are deliberately not good code.

## What is in it

```text
DeploymentShare/
├── Boot/
│   └── startnet.cmd                   WinPE startup - everything here is Environmental
├── Scripts/
│   ├── Get-AssetInventory.cmd         the classic: for /f parsing, a DMTF date, a pinned path
│   ├── Audit-InstalledSoftware.cmd    Win32_Product, and output redirected to a share
│   ├── Set-ServiceBaseline.cmd        set, call, and a boolean compared as text
│   ├── Get-BranchInventory.cmd        /node: sweep with a credential on the command line
│   └── Get-NetworkConfig.vbs          WScript.Shell.Exec, and a multi-valued property
├── TaskSequences/
│   └── Deploy-Windows11.xml           two steps, one in WinPE and one in the full OS
├── Migrated/
│   └── Get-AssetInventory.ps1         a migration somebody started and stopped halfway
└── Vendor/
    └── ThirdParty-Collect.cmd         replaced on every agent upgrade - the -Exclude case
```

## What you get

```text
Tier          RelativePath                        Line Command
----          ------------                        ---- -------
Environmental Boot\startnet.cmd                     11 wmic csproduct get identifyingnumber
Environmental Boot\startnet.cmd                     16 wmic computersystem get model
Environmental TaskSequences\Deploy-Windows11.xml    18 wmic csproduct get identifyingnumber
Environmental TaskSequences\Deploy-Windows11.xml    26 wmic diskdrive get size,model
Semantic      Migrated\Get-AssetInventory.ps1       37 wmic os get lastbootuptime /value
Semantic      Scripts\Audit-InstalledSoftware.cmd   10 wmic product get name,version,installdate ...
Semantic      Scripts\Get-AssetInventory.cmd        18 wmic.exe
Semantic      Scripts\Get-AssetInventory.cmd        30 wmic os get lastbootuptime /value
Semantic      Scripts\Get-BranchInventory.cmd       15 wmic /node:%NODES% /user:CONTOSO\svc_inven...
Semantic      Scripts\Get-BranchInventory.cmd       15 wmic /node:%NODES% /user:CONTOSO\svc_inven...
Semantic      Scripts\Get-BranchInventory.cmd       19 wmic /node:%NODES% logicaldisk where "driv...
Semantic      Scripts\Get-NetworkConfig.vbs         16 wmic nicconfig where IPEnabled=TRUE get IP...
Semantic      Scripts\Set-ServiceBaseline.cmd        8 wmic service where "name='spooler'" set st...
Semantic      Scripts\Set-ServiceBaseline.cmd        9 wmic service where "name='spooler'" call s...
Semantic      Scripts\Set-ServiceBaseline.cmd       12 wmic nicconfig where "IPEnabled=TRUE and D...
Semantic      Scripts\Set-ServiceBaseline.cmd       15 wmic path win32_process where "name='oldag...
Semantic      TaskSequences\Deploy-Windows11.xml    38 wmic product get name,version
Semantic      TaskSequences\Deploy-Windows11.xml    45 wmic os get installdate /value
Semantic      Vendor\ThirdParty-Collect.cmd          9 wmic os get installdate,lastbootuptime
Semantic      Vendor\ThirdParty-Collect.cmd         10 wmic nicconfig where "IPEnabled=TRUE" get ...
Wrapped       Migrated\Get-AssetInventory.ps1       41 wmic qfe list brief
Wrapped       Scripts\Audit-InstalledSoftware.cmd   13 wmic qfe get hotfixid,installedon
Wrapped       Scripts\Get-AssetInventory.cmd        24 wmic csproduct get vendor^,name /format:csv
Wrapped       Scripts\Get-AssetInventory.cmd        34 wmic logicaldisk where "drivetype=3" get d...
Mechanical    Scripts\Audit-InstalledSoftware.cmd   16 wmic startup get caption,command
Mechanical    Scripts\Get-AssetInventory.cmd        10 wmic csproduct get uuid
Mechanical    Scripts\Get-AssetInventory.cmd        21 wmic bios get serialnumber
Mechanical    Scripts\Get-NetworkConfig.vbs          5 wmic nic get macaddress
Mechanical    Scripts\Get-NetworkConfig.vbs         22 wmic nic where netenabled=true get name,ma...
Mechanical    Vendor\ThirdParty-Collect.cmd          8 wmic csproduct get uuid,identifyingnumber
```

9 files, 29 deprecation findings and 1 security finding — 6 Mechanical,
4 Wrapped, 15 Semantic, 4 Environmental. Two of the Mechanical hits sit in
comments, so they never fail a build.

Note that only 6 of 29 are the simple swap everyone assumes the whole job is.
That ratio is the point of the tool.

## Things worth looking at specifically

**The one that will bite.** `Scripts\Get-AssetInventory.cmd` line 24:

```batch
for /f "skip=2 tokens=1,2 delims=," %%A in ('wmic csproduct get vendor^,name /format:csv') do (
```

Swap the command for `Get-CimInstance` and this keeps running. It sets `VENDOR`
and `MODEL` from whatever the token positions now land on, nothing errors, and
the CSV that reaches the CMDB is wrong in a way nobody notices for a quarter.
The finding spans the whole block and records `skip=2 tokens=1,2 delims=,` —
that spec, not the command, is the thing being rewritten.

**Same block, different answer.** `Boot\startnet.cmd` line 11 is also a `for /f`
block, and it is reported as **Environmental** rather than Wrapped. The block
still has to be restructured, but whether the boot image has PowerShell at all
outranks that, and it has to be answered first.

**Where the scanner admits it is blind.** `Scripts\Get-AssetInventory.cmd`
line 18 stores the path:

```batch
set WMICEXE=%SystemRoot%\System32\wbem\wmic.exe
```

That line gets a Semantic finding saying the call sites are *not* in the report.
Line 37 uses `"%WMICEXE%"` and is genuinely missed. Variables are not resolved —
it is unsolvable in batch — so the finding says so where it will be read.

**A comment that outlived its code.** Line 10 is a `rem` describing a
`wmic csproduct` call that was removed years ago. It is reported, because it is
the example the next person copies, and it never fails a build because it does
not run.

**Two problems on one line.** `Scripts\Get-BranchInventory.cmd` line 15 appears
twice: once as a Semantic deprecation finding for `/node:`, once as a separate
security finding for the password. Neither can be closed by fixing the other.

**The half-done migration.** `Migrated\Get-AssetInventory.ps1` has its easy
calls already ported to `Get-CimInstance`. Both survivors are Wrapped — one
captured into a variable and split on `=`, one piped into `Select-String`. They
look like leftovers and they are the expensive part.

## Other things to try

Cut out the tree you are not allowed to edit:

```powershell
Invoke-WmicScan -Path .\DeploymentShare -Exclude '*\Vendor\*'
```

Look only at the work that will silently produce wrong answers:

```powershell
Invoke-WmicScan -Path .\DeploymentShare -Tier Wrapped |
    Format-List RelativePath, Line, Command, ForOptions, Reason
```

See the build verdict a CI step would read:

```powershell
Invoke-WmicScan -Path .\DeploymentShare -Summary
```

Write the two report formats:

```powershell
$findings = Invoke-WmicScan -Path .\DeploymentShare
$findings | Export-WmicScanReport -Path .\wmic.csv
$findings | Export-WmicScanReport -Path .\wmic.sarif -Format Sarif
```

Ask why something landed where it did:

```powershell
(Get-WmicRule -Id WMIC200).Reason
```
