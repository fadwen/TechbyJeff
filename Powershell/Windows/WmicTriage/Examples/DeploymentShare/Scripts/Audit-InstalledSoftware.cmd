@echo off
rem ---------------------------------------------------------------------------
rem Weekly software audit, called from a scheduled task at 02:00.
rem
rem Comment left by whoever wrote this: "takes forever, do not run during the
rem day". They were right, and the reason is on the first line below - querying
rem Win32_Product makes the installer verify every package on the machine.
rem ---------------------------------------------------------------------------

wmic product get name,version,installdate /format:csv > \\fs01\Inventory$\%COMPUTERNAME%-software.csv

rem Hotfixes are quick, and this one only wants the lines that look like a KB
wmic qfe get hotfixid,installedon | find "KB"

rem Startup entries, straight to the console
wmic startup get caption,command
