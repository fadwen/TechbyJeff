@echo off
rem ---------------------------------------------------------------------------
rem Vendor-supplied collector. Shipped with the agent and replaced wholesale on
rem every upgrade, so editing it is pointless - which makes it the obvious thing
rem to put behind -Exclude when you scan this share.
rem ---------------------------------------------------------------------------

wmic csproduct get uuid,identifyingnumber
wmic os get installdate,lastbootuptime
wmic nicconfig where "IPEnabled=TRUE" get IPAddress
