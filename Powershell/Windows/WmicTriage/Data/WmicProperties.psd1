@{
    # Property groups whose value changes shape between WMIC and Get-CimInstance.
    #
    # This is the table behind the Semantic tier, and it is the reason the tier exists. Swapping
    # the command is easy. What is not easy is that WMIC renders every value as text for a console,
    # while Get-CimInstance hands back a typed object - so any script that reached into the text
    # keeps running after the swap and quietly produces different values.
    #
    # Each group below is one such shape change, and each is a silent failure rather than a loud
    # one. Adding a property here is the cheapest way to make the scanner smarter; adding a whole
    # group means a new rule in WmicRules.psd1 that references it.

    SchemaVersion = 1

    Groups = @{

        # WMIC prints DMTF datetime: 20250314093000.000000-300. Get-CimInstance returns a
        # DateTime. Every substring index into the old format is wrong against the new one, and
        # the classic offender is a script that took the first 8 characters to get yyyymmdd.
        DateTime = @(
            'CreationDate'
            'FinishTime'
            'InstallDate'
            'LastAccessed'
            'LastBootUpTime'
            'LastModified'
            'LocalDateTime'
            'ReleaseDate'
            'StartTime'
            'TerminationDate'
            'TimeOfLastReset'
            'TimeStamp'
            'UntilTime'
        )

        # WMIC prints a DMTF interval: 00000001020304.000000:000. Get-CimInstance returns a
        # TimeSpan. Same failure as DateTime, different format, and the arithmetic that follows
        # is usually the point of the script.
        Interval = @(
            'ElapsedTime'
            'MaxPasswordAge'
            'MinPasswordAge'
            'PasswordAge'
            'SystemUpTime'
        )

        # WMIC prints an array as {"a","b"}. Get-CimInstance returns a real array. A script that
        # did a string comparison against the braced form now compares against System.String[],
        # and one that took the whole field as "the IP address" now silently takes the first
        # element only - or, worse, the object's type name.
        MultiValue = @(
            'BiosCharacteristics'
            'Capabilities'
            'CapabilityDescriptions'
            'DefaultIPGateway'
            'DNSDomainSuffixSearchOrder'
            'DNSServerSearchOrder'
            'GatewayCostMetric'
            'IPAddress'
            'IPSubnet'
            'IPXAddress'
            'IPXFrameType'
            'IPXNetworkNumber'
            'IPXVirtualNetNumber'
            'PowerManagementCapabilities'
            'Roles'
            'SystemStartupOptions'
        )

        # WMIC prints TRUE and FALSE. Get-CimInstance returns [bool], which stringifies to True
        # and False. A batch comparison against "TRUE" therefore stops matching, and because a
        # failed comparison is not an error, the else branch just starts running instead.
        Boolean = @(
            'AcceptPause'
            'AcceptStop'
            'AutoReboot'
            'Bootable'
            'BootPartition'
            'Compressed'
            'DesktopInteract'
            'DHCPEnabled'
            'Encrypted'
            'Hidden'
            'IPEnabled'
            'PartOfDomain'
            'PrimaryPartition'
            'Readable'
            'Started'
            'System'
            'Writeable'
        )
    }
}
