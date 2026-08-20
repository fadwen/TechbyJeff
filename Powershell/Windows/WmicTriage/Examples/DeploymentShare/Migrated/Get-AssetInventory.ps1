#Requires -Version 5.1

<#
    .SYNOPSIS
        Half-migrated version of Scripts\Get-AssetInventory.cmd

    .DESCRIPTION
        Somebody started porting the batch collector and stopped. The calls that
        were obviously mechanical are done. The two that were harder to reason
        about are still shelling out to WMIC - and, importantly, still parsing
        its text layout rather than reading properties.

        This is the state a migration is usually found in, and it is the state
        the scanner is most useful in: the remaining calls look like leftovers,
        but both of them are Wrapped, so swapping the command without changing
        the parsing around it would leave the script running and wrong.

        Deliberately not fixed. It is example input.

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.1.0
        Last Updated: 2026-08-19
#>

[CmdletBinding()]
param()

$inventory = [ordered]@{}

# Migrated. Real properties off a real object.
$inventory['Serial'] = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$inventory['Model'] = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

# Not migrated. Captured into a variable and split on '=', which only works
# because WMIC prints /value output as name=value text.
$bootLine = wmic os get lastbootuptime /value
$inventory['BootRaw'] = @($bootLine -split '=')[-1]

# Not migrated. Piped into a text filter that matches the WMIC table layout.
$hotfixes = wmic qfe list brief | Select-String -Pattern 'KB'
$inventory['HotfixCount'] = @($hotfixes).Count

[PSCustomObject]$inventory
