#Requires -Version 5.1

# Fixture. This file is deliberately written the way legacy inventory scripts are written, so the
# scanner has something real to classify. Do not treat it as an example of anything.

# Legacy approach kept for reference: wmic os get caption
$serial = wmic bios get serialnumber
wmic os get caption | Select-String 'Windows'
wmic qfe list brief > hotfix.txt
$model = (wmic csproduct get name)
Start-Process -FilePath 'wmic.exe' -ArgumentList 'os get caption'
wmic computersystem get model

Write-Output $serial
Write-Output $model
