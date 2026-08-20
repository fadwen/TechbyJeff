@echo off
rem ---------------------------------------------------------------------------
rem Sweeps the branch office servers from the admin jump box.
rem
rem The credential is on the command line because the scheduled task that calls
rem this runs as SYSTEM and "could not use stored credentials". This is the kind
rem of thing the scanner raises separately from the migration, because it is
rem worth fixing whether or not the WMIC call ever moves.
rem
rem The password below is fictional and exists only to demonstrate that rule.
rem ---------------------------------------------------------------------------

set NODES=SRV-BR01,SRV-BR02,SRV-BR03

wmic /node:%NODES% /user:CONTOSO\svc_inventory /password:ExampleOnlyNotARealPassword ^
  os get caption,lastbootuptime

rem Same sweep, output captured for the report
wmic /node:%NODES% logicaldisk where "drivetype=3" get deviceid,freespace /format:csv > branch-disks.csv
