@echo off
setlocal enabledelayedexpansion

rem ---------------------------------------------------------------------------
rem Asset inventory collector.
rem
rem Written for the XP rollout, carried through 7, 10 and 11 without anyone
rem revisiting it. Feeds \\fs01\Inventory$, which the CMDB imports overnight.
rem
rem Historical note: this used to call "wmic csproduct get uuid" as well, but
rem the UUID came back differently on the Dell fleet so it was dropped.
rem ---------------------------------------------------------------------------

set OUTFILE=%TEMP%\%COMPUTERNAME%.txt

rem Some estates have the path pinned because wmic was pulled off PATH by a
rem hardening baseline. The scanner reports this line and cannot follow it.
set WMICEXE=%SystemRoot%\System32\wbem\wmic.exe

rem Straight to the console - nothing reads it, it is here for the technician
wmic bios get serialnumber

rem Vendor and model, parsed by column out of the CSV
for /f "skip=2 tokens=1,2 delims=," %%A in ('wmic csproduct get vendor^,name /format:csv') do (
    set VENDOR=%%A
    set MODEL=%%B
)

rem Last boot, sliced to yyyymmdd out of the DMTF string
for /f "tokens=2 delims==" %%A in ('wmic os get lastbootuptime /value') do set BOOT=%%A
set BOOTDATE=!BOOT:~0,8!

rem Fixed disks only, appended to the file the CMDB collects
wmic logicaldisk where "drivetype=3" get deviceid,freespace,size >> %OUTFILE%

rem Called through the pinned path, so a search for a leading "wmic" misses it
"%WMICEXE%" computersystem get domain,totalphysicalmemory >> %OUTFILE%

echo %VENDOR%,%MODEL%,%BOOTDATE% >> %OUTFILE%
copy /y %OUTFILE% \\fs01\Inventory$\ >nul
