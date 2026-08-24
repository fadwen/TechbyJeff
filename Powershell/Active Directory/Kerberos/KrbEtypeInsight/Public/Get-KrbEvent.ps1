#Requires -Version 7.6

function Get-KrbEvent {
    <#
    .SYNOPSIS
        Collects and decodes Kerberos authentication audit events from domain controllers or archived logs

    .DESCRIPTION
        Reads security audit events 4768 (TGT requested), 4769 (service ticket requested) and
        4771 (pre-authentication failed), and returns them in the single normalised schema the
        rest of the module consumes. Every encryption type, result code and pre-authentication
        type is decoded on the way out, so no caller has to know which of the two Kerberos
        numbering systems a given field belongs to.

        Collection sources:

        - The current domain's controllers, discovered automatically. This is the default and
          needs no parameters.
        - Named computers, for a subset of controllers or a read-only DC.
        - Archived .evtx files, which is both the way to assess a domain from a workstation
          and the way this module's own tests exercise the full decode path with no domain
          present.

        On event volume, which is the real constraint. A busy domain controller produces
        4769 events at a rate that makes "collect everything and filter later" untenable -
        tens of millions per week is ordinary. Three things follow from that, and this
        function is built around them:

        1. All filtering that CAN be pushed to the event log service IS. Event ID and time
           window go into the FilterHashtable, where they are evaluated by the log service on
           the remote controller before anything crosses the network. Filtering the same
           events with Where-Object after collection transfers every record and is slower by
           orders of magnitude.

        2. MaxEvents is applied per source, not per collection, and applies to the newest
           events. A representative sample from each controller is nearly always a better
           basis for an assessment than an exhaustive read of one.

        3. Controllers are read sequentially and the decode happens locally. For a large
           estate, the intended pattern is to archive the security log to .evtx on each
           controller - wevtutil exports in seconds because it never leaves the machine -
           and then run this function against the collected files. The Troubleshooting notes
           carry a worked example.

        Business value: this is the observational half of an encryption-type hardening
        assessment. Configuration alone cannot tell you what a service account has actually
        been presenting for the last thirty days, and that is the fact that decides whether
        hardening it is safe.

    .PARAMETER ComputerName
        [System.String[]] (Optional, No Pipeline Support)

        Domain controllers to read the security log from. When omitted, every controller in
        the current domain is discovered and read. Ignored when -Path is used.

    .PARAMETER Path
        [System.String[]] (Mandatory in the Path set, Pipeline: ByPropertyName)

        Archived .evtx files to read instead of a live log. Accepts wildcards and pipes
        directly from Get-ChildItem. This is the offline assessment path and the one the unit
        tests use.

    .PARAMETER EventId
        [System.Int32[]] (Optional, No Pipeline Support)

        Which audit events to collect. Defaults to 4768, 4769 and 4771.

        Narrowing this is the cheapest available optimisation. 4769 alone answers "what have
        services been presenting"; 4768 alone answers "what do clients advertise"; 4771 alone
        answers "what is already failing".

    .PARAMETER StartTime
        [System.DateTime] (Optional, No Pipeline Support)

        Earliest event to collect. Defaults to 30 days ago, which is chosen to be longer than
        the 30-day default computer account password cycle so that at least one full
        authentication cycle for every domain-joined machine falls inside the window.

        Assessments run over a window shorter than a month routinely miss the monthly batch
        job that is the thing hardening will break.

    .PARAMETER EndTime
        [System.DateTime] (Optional, No Pipeline Support)

        Latest event to collect. Defaults to the present.

    .PARAMETER MaxEvents
        [System.Int32] (Optional, No Pipeline Support)

        Maximum events to read from each source, newest first. Defaults to 50000.

        Set this to 0 for no limit only when reading an archived file. Applying no limit to a
        live controller's security log is a request to transfer the entire log.

    .PARAMETER Credential
        [System.Management.Automation.PSCredential] (Optional, No Pipeline Support)

        Credentials for reading remote security logs. Requires membership of Event Log
        Readers or equivalent on each controller. Ignored when -Path is used.

    .PARAMETER IncludeFailureOnly
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Return only events that represent a failure - every 4771, plus any 4768 or 4769
        carrying a non-zero result code.

        The intended use is after a hardening change: filtered to failures and grouped by
        StatusName, a collection shows immediately whether KDC_ERR_ETYPE_NOTSUPP has appeared
        where it was not before.

    .EXAMPLE
        PS> Get-KrbEvent -MaxEvents 5000

        DESCRIPTION: Collects the most recent 5000 Kerberos events from every controller in the domain
        OUTPUT: KrbEtypeInsight.Event objects with all encryption types decoded
        USE CASE: A first look at what a domain is actually issuing
        DURATION: Roughly 30 seconds per controller at this volume

    .EXAMPLE
        PS> Get-KrbEvent -EventId 4769 -StartTime (Get-Date).AddDays(-45) |
                Group-Object ServiceName |
                Where-Object { $_.Group.TicketEtype -contains 23 } |
                Sort-Object Count -Descending

        DESCRIPTION: Finds every service that has been issued at least one RC4 service ticket in 45 days
        OUTPUT: Service names ordered by request volume
        USE CASE: Building the work list for an RC4 removal project
        DURATION: 2 to 10 minutes depending on domain size

    .EXAMPLE
        PS> Get-ChildItem \\fileserver\krbaudit\*.evtx | Get-KrbEvent -MaxEvents 0

        DESCRIPTION: Processes archived security logs collected from every controller
        OUTPUT: The full decoded event set with no domain connectivity required
        USE CASE: Assessing a domain from an administrative workstation, or re-running an
                  assessment against a preserved snapshot after the estate has changed

    .EXAMPLE
        PS> Get-KrbEvent -IncludeFailureOnly -StartTime (Get-Date).AddHours(-4) |
                Group-Object StatusName | Sort-Object Count -Descending

        DESCRIPTION: Post-change verification over the four hours since a hardening rollout
        OUTPUT: Failure counts by KDC result code
        USE CASE: Deciding within a maintenance window whether to proceed or roll back.
                  KDC_ERR_ETYPE_NOTSUPP appearing here is the change breaking something.

    .INPUTS
        System.String. Accepts .evtx paths by property name, so Get-ChildItem pipes directly.

    .OUTPUTS
        KrbEtypeInsight.Event

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        Requires the Kerberos Authentication Service and Kerberos Service Ticket Operations
        audit subcategories to be enabled on the controllers. Without them the collection
        returns nothing and the assessment silently describes an empty domain - so this
        function warns rather than returning quietly when a source yields no events.

        Permissions: membership of Event Log Readers on each controller is sufficient for THIS
        function, and Domain Admin is not required. It is NOT sufficient for the module as a
        whole - Get-KrbDomainEtypeContext reads each controller's registry over PowerShell
        remoting and needs local administrator there. See the rights table in the README.

        Rights are not the only gate. Get-WinEvent -ComputerName uses the legacy Event Log RPC
        protocol, and the Remote Event Log Management firewall rules that permit it are off by
        default on a fresh Windows install. A controller with perfect rights still returns
        "The RPC server is unavailable" until they are enabled.

        TROUBLESHOOTING:
        - No events returned: .\Troubleshooting\Common\No-Events-Collected.md
        - Event volume and archiving: .\Troubleshooting\Performance\Event-Volume.md
        - Remote access denied: .\Troubleshooting\Security\Event-Log-Permissions.md

    .LINK
        https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4769

    .LINK
        KB5021131 - managing the Kerberos protocol changes for CVE-2022-37966
        https://support.microsoft.com/help/5021131
    #>
    [CmdletBinding(DefaultParameterSetName = 'LiveDomain')]
    [OutputType('KrbEtypeInsight.Event')]
    param(
        [Parameter(ParameterSetName = 'LiveDomain')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        # Get-KrbEtypeRisk models only these three events. Accepting adjacent Kerberos
        # audit IDs here made Get-KrbEvent appear to support them even though the risk
        # engine silently omitted them from its assessment.
        [ValidateSet(4768, 4769, 4771)]
        [int[]]$EventId = @(4768, 4769, 4771),

        [Parameter()]
        [datetime]$StartTime = (Get-Date).AddDays(-30),

        [Parameter()]
        [datetime]$EndTime = (Get-Date),

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxEvents = 50000,

        [Parameter(ParameterSetName = 'LiveDomain')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter()]
        [switch]$IncludeFailureOnly
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        if ($StartTime -ge $EndTime) {
            Write-Error "StartTime ($StartTime) must be earlier than EndTime ($EndTime)" -ErrorAction Stop
            return
        }

        $totalEmitted = 0
        $totalRead = 0
        $failuresSeen = 0
        $sourcesRead = 0
        $sourcesEmpty = [System.Collections.Generic.List[string]]::new()

        # Resolved once so the two collection paths share exactly one filter construction.
        # Time bounds are included here rather than applied afterwards because the log
        # service evaluates them before a single record crosses the network.
        $baseFilter = @{
            Id        = $EventId
            StartTime = $StartTime
            EndTime   = $EndTime
        }

        # Get-WinEvent treats -MaxEvents 0 as an error rather than as "unlimited", so the
        # unlimited case is expressed by omitting the parameter entirely.
        $readerArgs = @{ ErrorAction = 'Stop' }
        if ($MaxEvents -gt 0) { $readerArgs['MaxEvents'] = $MaxEvents }
    }

    process {
        # Build the source list for this invocation. In the Path set this runs once per
        # pipeline item, which is what makes Get-ChildItem | Get-KrbEvent stream.
        $sources = switch ($PSCmdlet.ParameterSetName) {

            'Path' {
                foreach ($item in $Path) {
                    $resolved = Resolve-Path -Path $item -ErrorAction SilentlyContinue
                    if (-not $resolved) {
                        Write-Error "Archived log not found: $item"
                        continue
                    }
                    foreach ($file in $resolved) {
                        [PSCustomObject]@{
                            Name   = Split-Path -Path $file.Path -Leaf
                            Filter = $baseFilter + @{ Path = $file.Path }
                            Remote = @{}
                        }
                    }
                }
            }

            'LiveDomain' {
                $targets = $ComputerName
                if (-not $targets) {
                    try {
                        $targets = @(Get-ADDomainController -Filter * -ErrorAction Stop |
                            Select-Object -ExpandProperty HostName)
                        Write-Verbose "Discovered $($targets.Count) domain controller(s)"
                    }
                    catch {
                        Write-Error ("Could not enumerate domain controllers. Supply -ComputerName " +
                            "explicitly, or use -Path against archived logs. Error: $($_.Exception.Message)") `
                            -ErrorAction Stop
                        return
                    }
                }

                foreach ($target in $targets) {
                    $remote = @{ ComputerName = $target }
                    if ($Credential) { $remote['Credential'] = $Credential }

                    [PSCustomObject]@{
                        Name   = $target
                        Filter = $baseFilter + @{ LogName = 'Security' }
                        Remote = $remote
                    }
                }
            }
        }

        foreach ($source in $sources) {
            $sourcesRead++
            Write-Verbose "Reading $($source.Name) - CorrelationId: $correlationId"
            Write-Progress -Activity 'Collecting Kerberos events' -Status $source.Name `
                -CurrentOperation "$totalEmitted events decoded so far"

            $emittedFromSource = 0

            # Splatting needs a variable, not a property expression - @($source.Remote) is an
            # array subexpression and would pass the hashtable as a single positional
            # argument rather than binding ComputerName and Credential.
            $remoteArgs = $source.Remote

            try {
                # -ErrorAction Stop turns "no events matched" into a catchable terminating
                # error, which is the only way to distinguish it from a genuine empty result
                # and report it as the audit-policy problem it usually is.
                $records = Get-WinEvent -FilterHashtable $source.Filter @readerArgs @remoteArgs
            }
            catch [System.Exception] {
                # Get-WinEvent raises the same exception type for "no matching events" as for
                # real faults, so the message is the only discriminator available.
                if ($_.Exception.Message -match 'No events were found') {
                    $sourcesEmpty.Add($source.Name)
                    Write-Verbose "No matching events on $($source.Name) in the requested window"
                    continue
                }

                $errorDetails = @{
                    Source        = $source.Name
                    CorrelationId = $correlationId
                    Function      = $MyInvocation.MyCommand.Name
                    ErrorMessage  = $_.Exception.Message
                    Line          = $_.InvocationInfo.ScriptLineNumber
                }
                Write-Verbose ("Collection failure detail: " + ($errorDetails | ConvertTo-Json -Compress))

                # One unreachable controller must not abandon the others. The assessment is
                # still valid over the controllers that answered, provided the report says
                # which ones did not - which is why this is a non-terminating error.
                #
                # "The RPC server is unavailable" gets named, because on a domain controller
                # it almost never means the machine is down. Get-WinEvent -ComputerName uses
                # the legacy Event Log RPC protocol, which needs the dynamic RPC range as well
                # as port 135, and the firewall rules that open it - the Remote Event Log
                # Management group - are DISABLED by default on a fresh Windows install.
                #
                # Measured: a healthy, replicating Server 2025 domain controller, reachable on
                # 135, 445, 5985, 389 and 88, answering WinRM perfectly, returned this error
                # for every single event log call. Its Security log held 6,703 records the
                # whole time. Without naming the cause this reads as "that DC is broken", and
                # an assessment run with -ErrorAction SilentlyContinue simply omits the
                # controller and reports a confident result over a fraction of the estate.
                $message = "Failed to read Kerberos events from $($source.Name): $($_.Exception.Message)"

                if ($_.Exception.Message -match 'RPC server is unavailable') {
                    $message += (' The host is usually reachable and this is usually the ' +
                        'firewall: Get-WinEvent uses Event Log RPC, whose rules are off by ' +
                        'default. Enable them on that controller with ' +
                        "Enable-NetFirewallRule -DisplayGroup 'Remote Event Log Management', " +
                        'or collect from an archived .evtx instead.')
                }

                Write-Error $message
                continue
            }

            # Read and emitted are counted separately. Conflating them made a source that
            # returned plenty of events but no FAILURES - which under -IncludeFailureOnly is
            # simply a healthy controller - report as empty, and the end block then advised
            # the operator to go and check whether Kerberos auditing was enabled. That advice
            # fired hardest during post-change verification, the one moment the module's
            # empty-collection warning most needs to mean what it says.
            $readFromSource = 0

            foreach ($record in $records) {
                $decoded = ConvertFrom-KrbEventRecord -Record $record -SourceName $source.Name
                if (-not $decoded) { continue }

                $readFromSource++
                if ($decoded.IsFailure) { $failuresSeen++ }

                if ($IncludeFailureOnly -and -not $decoded.IsFailure) { continue }

                $emittedFromSource++
                $totalEmitted++
                $decoded
            }

            $totalRead += $readFromSource

            # Only a source that produced no events AT ALL is evidence of an auditing or
            # retention problem.
            if ($readFromSource -eq 0) { $sourcesEmpty.Add($source.Name) }
            elseif ($emittedFromSource -eq 0) {
                Write-Verbose ("$($source.Name) returned $readFromSource event(s), none matching " +
                    'the requested filter')
            }
        }
    }

    end {
        Write-Progress -Activity 'Collecting Kerberos events' -Completed

        # An empty collection is the failure mode that most often goes unnoticed, because it
        # looks exactly like a clean domain. Saying so explicitly is the difference between
        # an assessment that found nothing and an assessment that measured nothing.
        if ($sourcesEmpty.Count -gt 0) {
            $names = $sourcesEmpty -join ', '
            Write-Warning ("No Kerberos events matched on: $names. Check that the " +
                "'Kerberos Authentication Service' and 'Kerberos Service Ticket Operations' " +
                "audit subcategories are enabled, and that the requested window " +
                "($StartTime to $EndTime) is inside the log's retention.")
        }

        # Gated on events READ, not on events emitted. A collection that read plenty and
        # emitted none because -IncludeFailureOnly filtered them all is a healthy domain, and
        # telling its operator that the assessment "will describe an empty domain rather than
        # a clean one" is precisely backwards - it IS a clean one, and that is the answer
        # they were looking for.
        if ($sourcesRead -gt 0 -and $totalRead -eq 0) {
            Write-Warning ("Read $sourcesRead source(s) and decoded no events. Any assessment " +
                'built on this collection will describe an empty domain rather than a clean one.')
        }

        if ($IncludeFailureOnly -and $totalRead -gt 0 -and $totalEmitted -eq 0) {
            # Worth stating positively. Silence here reads as a failed collection, when it is
            # the result a post-change verification hopes for.
            Write-Verbose ("Read $totalRead event(s) across $sourcesRead source(s) and none were " +
                'failures.')
        }

        # Success-only audit policy is the module's remaining blind spot, and it was found by
        # running this against a domain that had it. The two Kerberos subcategories can be set
        # to Success without Failure, which is not the default but is common - and in that
        # state the KDC logs no 4771 at all and no failed 4769. A post-change verification
        # then returns nothing and reads as "the change broke nothing", when in truth nothing
        # capable of recording breakage was ever switched on.
        #
        # Inferred from the collection rather than by reading audit policy, which would need
        # local administrator on every controller for a module that otherwise needs only
        # Event Log Reader. Asking for 4771 and receiving none while thousands of successes
        # came back is not proof, but it is the shape the misconfiguration makes.
        if ($EventId -contains 4771 -and $totalRead -gt 100 -and $failuresSeen -eq 0) {
            Write-Warning ("Collected $totalRead event(s) and not one failure, including zero " +
                '4771s. That is what a domain with the Kerberos audit subcategories set to ' +
                'Success without Failure looks like. Confirm with: auditpol /get /subcategory:' +
                '"Kerberos Authentication Service" - if Failure is not enabled, this collection ' +
                'cannot show breakage and must not be read as showing none.')
        }

        Write-Verbose ("Completed $($MyInvocation.MyCommand.Name) - $totalEmitted of $totalRead " +
            "event(s) from $sourcesRead source(s) - CorrelationId: $correlationId")
    }
}
