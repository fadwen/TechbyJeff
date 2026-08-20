@echo off
rem ---------------------------------------------------------------------------
rem Service baseline for print-free servers. Changes state, so read it twice
rem before running it anywhere.
rem ---------------------------------------------------------------------------

rem Disable the spooler, then stop it now rather than at the next reboot
wmic service where "name='spooler'" set startmode=disabled
wmic service where "name='spooler'" call stopservice

rem Only report the adapters that are actually configured by DHCP
wmic nicconfig where "IPEnabled=TRUE and DHCPEnabled=TRUE" get description,IPAddress

rem Kill anything the vendor agent left behind
wmic path win32_process where "name='oldagent.exe'" call terminate
