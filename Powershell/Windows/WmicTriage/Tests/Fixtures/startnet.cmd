@echo off
wpeinit
for /f "tokens=2 delims==" %%A in ('wmic csproduct get uuid /value') do set UUID=%%A
wmic bios get serialnumber
