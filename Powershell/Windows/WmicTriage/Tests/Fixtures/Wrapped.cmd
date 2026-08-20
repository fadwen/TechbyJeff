@echo off
for /f "tokens=2 delims==" %%A in ('wmic os get caption /value') do set OSNAME=%%A

for /f "skip=1 tokens=1,2" %%A in ('wmic logicaldisk get deviceid, freespace') do (
    echo %%A has %%B free
    wmic bios get serialnumber
)

wmic qfe list brief /format:csv > %TEMP%\hotfix.csv
wmic service get name,startmode | find "auto"
wmic nic get name /output:C:\Temp\nic.txt
wmic process where "workingsetsize > 100000000" get name
