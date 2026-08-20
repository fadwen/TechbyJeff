@echo off
rem ---------------------------------------------------------------------------
rem WinPE startup. This runs off the boot image, before there is an OS on the
rem disk. Whether PowerShell exists here depends entirely on whether anyone
rem added WinPE-PowerShell to the image, and nobody remembers.
rem ---------------------------------------------------------------------------

wpeinit

rem Stamp the serial into the environment so the task sequence can name the machine
for /f "skip=1 tokens=*" %%A in ('wmic csproduct get identifyingnumber') do (
    if not "%%A"=="" set SERIAL=%%A
)

rem Straight to the console for the technician standing there
wmic computersystem get model

echo Serial: %SERIAL%
