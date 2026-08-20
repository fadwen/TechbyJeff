@echo off
REM Legacy inventory helper. Was: wmic csproduct get uuid
wmic bios get serialnumber
wmic os get caption
%COMSPEC% /c wmic computersystem get model
C:\Windows\System32\wbem\wmic.exe qfe list brief
echo Replace wmic with PowerShell before the next image refresh
