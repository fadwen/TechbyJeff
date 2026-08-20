@echo off
wmic product get name,version
wmic os get lastbootuptime
wmic nicconfig where "IPEnabled=TRUE" get IPAddress,DefaultIPGateway
wmic /node:SRV01 /user:CONTOSO\svc_inv /password:PlainTextSecret os get caption
wmic path win32_process where "name='notepad.exe'" call terminate
wmic service where "name='spooler'" set startmode=disabled
wmic cpu get loadpercentage /every:5
