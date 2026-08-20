@echo off
set WMICPATH=%SystemRoot%\System32\wbem\wmic.exe
"%WMICPATH%" os get caption
start "" wmic cpu get name
