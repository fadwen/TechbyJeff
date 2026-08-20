@{
    # WMIC alias to WMI class mapping.
    #
    # The point of this table is not completeness for its own sake. WMIC aliases hide the class
    # behind a friendly name, and roughly half of them are not guessable: nobody reads "qfe" and
    # thinks Win32_QuickFixEngineering, or "rdtoggle" and thinks Win32_TerminalServiceSetting. A
    # report that says "replace wmic qfe" leaves the reader exactly where they started. A report
    # that says "wmic qfe -> Get-CimInstance Win32_QuickFixEngineering" does the lookup for them.
    #
    # NonObvious marks the aliases whose class the reader will not already know. It drives whether
    # the finding's suggestion leads with the class name, and it is the flag to set when adding a
    # new alias whose mapping made you look it up.

    SchemaVersion = 1

    Aliases = @{
        # Obvious mappings - the alias is the class minus the Win32_ prefix, or close enough
        bios                 = @{ Class = 'Win32_BIOS' }
        computersystem       = @{ Class = 'Win32_ComputerSystem' }
        desktop              = @{ Class = 'Win32_Desktop' }
        desktopmonitor       = @{ Class = 'Win32_DesktopMonitor' }
        diskdrive            = @{ Class = 'Win32_DiskDrive' }
        environment          = @{ Class = 'Win32_Environment' }
        group                = @{ Class = 'Win32_Group' }
        logicaldisk          = @{ Class = 'Win32_LogicalDisk' }
        os                   = @{ Class = 'Win32_OperatingSystem' }
        printer              = @{ Class = 'Win32_Printer' }
        printjob             = @{ Class = 'Win32_PrintJob' }
        process              = @{ Class = 'Win32_Process' }
        product              = @{ Class = 'Win32_Product' }
        service              = @{ Class = 'Win32_Service' }
        share                = @{ Class = 'Win32_Share' }
        startup              = @{ Class = 'Win32_StartupCommand' }
        systemenclosure      = @{ Class = 'Win32_SystemEnclosure' }
        timezone             = @{ Class = 'Win32_TimeZone' }
        useraccount          = @{ Class = 'Win32_UserAccount' }
        volume               = @{ Class = 'Win32_Volume' }

        # Non-obvious mappings - the reader will not get these from the alias alone
        baseboard            = @{ Class = 'Win32_BaseBoard'; NonObvious = $true }
        bootconfig           = @{ Class = 'Win32_BootConfiguration'; NonObvious = $true }
        cdrom                = @{ Class = 'Win32_CDROMDrive'; NonObvious = $true }
        cpu                  = @{ Class = 'Win32_Processor'; NonObvious = $true }
        csproduct            = @{ Class = 'Win32_ComputerSystemProduct'; NonObvious = $true }
        datafile             = @{ Class = 'CIM_DataFile'; NonObvious = $true }
        dcomapp              = @{ Class = 'Win32_DCOMApplication'; NonObvious = $true }
        fsdir                = @{ Class = 'Win32_Directory'; NonObvious = $true }
        idecontroller        = @{ Class = 'Win32_IDEController'; NonObvious = $true }
        irq                  = @{ Class = 'Win32_IRQResource'; NonObvious = $true }
        job                  = @{ Class = 'Win32_ScheduledJob'; NonObvious = $true }
        loadorder            = @{ Class = 'Win32_LoadOrderGroup'; NonObvious = $true }
        logon                = @{ Class = 'Win32_LogonSession'; NonObvious = $true }
        memcache             = @{ Class = 'Win32_CacheMemory'; NonObvious = $true }
        memlogical           = @{ Class = 'Win32_LogicalMemoryConfiguration'; NonObvious = $true }
        memphysical          = @{ Class = 'Win32_PhysicalMemoryArray'; NonObvious = $true }
        memorychip           = @{ Class = 'Win32_PhysicalMemory'; NonObvious = $true }
        netclient            = @{ Class = 'Win32_NetworkClient'; NonObvious = $true }
        netlogin             = @{ Class = 'Win32_NetworkLoginProfile'; NonObvious = $true }
        netprotocol          = @{ Class = 'Win32_NetworkProtocol'; NonObvious = $true }
        netuse               = @{ Class = 'Win32_NetworkConnection'; NonObvious = $true }
        nic                  = @{ Class = 'Win32_NetworkAdapter'; NonObvious = $true }
        nicconfig            = @{ Class = 'Win32_NetworkAdapterConfiguration'; NonObvious = $true }
        nteventlog           = @{ Class = 'Win32_NTEventlogFile'; NonObvious = $true }
        ntdomain             = @{ Class = 'Win32_NTDomain'; NonObvious = $true }
        onboarddevice        = @{ Class = 'Win32_OnBoardDevice'; NonObvious = $true }
        pagefile             = @{ Class = 'Win32_PageFileUsage'; NonObvious = $true }
        pagefileset          = @{ Class = 'Win32_PageFileSetting'; NonObvious = $true }
        partition            = @{ Class = 'Win32_DiskPartition'; NonObvious = $true }
        portconnector        = @{ Class = 'Win32_PortConnector'; NonObvious = $true }
        qfe                  = @{ Class = 'Win32_QuickFixEngineering'; NonObvious = $true }
        rdtoggle             = @{ Class = 'Win32_TerminalServiceSetting'; NonObvious = $true }
        recoveros            = @{ Class = 'Win32_OSRecoveryConfiguration'; NonObvious = $true }
        scsicontroller       = @{ Class = 'Win32_SCSIController'; NonObvious = $true }
        sounddev             = @{ Class = 'Win32_SoundDevice'; NonObvious = $true }
        sysaccount           = @{ Class = 'Win32_SystemAccount'; NonObvious = $true }
        sysdriver            = @{ Class = 'Win32_SystemDriver'; NonObvious = $true }
        systemslot           = @{ Class = 'Win32_SystemSlot'; NonObvious = $true }
        tapedrive            = @{ Class = 'Win32_TapeDrive'; NonObvious = $true }
        usercontrol          = @{ Class = 'Win32_UserDesktop'; NonObvious = $true }
    }
}
