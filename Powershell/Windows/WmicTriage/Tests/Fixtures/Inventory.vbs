' Asset inventory helper
' Old approach: wmic os get caption
Set objShell = CreateObject("WScript.Shell")
Set objExec = objShell.Exec("wmic csproduct get uuid /value")
objShell.Run "wmic bios get serialnumber", 0, True
