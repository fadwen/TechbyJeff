' ---------------------------------------------------------------------------
' Network configuration collector, called from the logon script.
' Written in 2009. Still deployed, because it still works.
'
' Old approach, kept for reference: wmic nic get macaddress
' ---------------------------------------------------------------------------

Option Explicit

Dim objShell, objExec, strOutput

Set objShell = CreateObject("WScript.Shell")

' Captured and parsed. IPAddress and DefaultIPGateway both come back braced,
' because WMIC renders an array as {"a","b"} and this code splits on that.
Set objExec = objShell.Exec("wmic nicconfig where IPEnabled=TRUE get IPAddress,DefaultIPGateway /format:list")
strOutput = objExec.StdOut.ReadAll()

WScript.Echo strOutput

' Fire and forget - nothing reads this one
objShell.Run "wmic nic where netenabled=true get name,macaddress", 0, True
