#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The collector, with Get-WinEvent and Get-ADDomainController mocked so the tests run with
    no domain, no security log access, and no dependence on what this machine happens to have
    logged.

    The behaviours worth pinning:

    - Filtering is pushed into the FilterHashtable, where the event log service evaluates it
      before a record crosses the network. Doing the same filtering afterwards with
      Where-Object is correct and unusably slow at the volumes a domain controller produces,
      and the difference is invisible in the output - which is exactly why it needs a test.

    - A collection that matched nothing warns loudly. This is the module's most dangerous
      quiet failure: an assessment run with the Kerberos audit subcategories disabled returns
      no events and produces a report that looks exactly like a clean domain.

    - One unreachable controller does not abandon the others. In a large estate at least one
      controller is always down, and a collection that aborts on the first failure never
      completes.
#>

# Script-level suppressions. A SuppressMessageAttribute on a param() block at the top of a
# script applies to the whole file.
#
# ConvertToSecureStringWithPlainText: these are throwaway literals used to construct a
# PSCredential that is never authenticated with - the tests assert only that the parameter is
# forwarded. There is no secret here to protect.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Throwaway literal for a credential that is never authenticated with.')]
param()

BeforeAll {
    $moduleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    # Every directory call below is mocked, but Pester cannot attach a mock to a command
    # that does not exist. On a host without RSAT the stub supplies the names; on a domain
    # controller the real cmdlets win, because the stub path is appended, not prepended.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-KrbTestStubPath.ps1')
    Import-Module (Join-Path $moduleRoot 'KrbEtypeInsight.psd1') -Force
}

AfterAll {
    Remove-Module KrbEtypeInsight -Force -ErrorAction SilentlyContinue
}

Describe 'Get-KrbEvent' -Tag 'Unit', 'Public', 'Collection' {

    Context 'Server-side filtering' {

        # These assertions go through Should-Invoke -ParameterFilter rather than capturing
        # the filter into a variable. A mock declared with -ModuleName runs inside the
        # module's scope, so a $script: variable in the mock body resolves against the
        # MODULE's script scope and not the test file's - the write lands somewhere the test
        # cannot see, and the assertion compares against $null. -ParameterFilter is evaluated
        # by Pester with the captured arguments in hand and sidesteps the scoping question
        # entirely.

        BeforeAll {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }

            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }
        }

        It 'pushes the event identifiers into the filter' {
            Get-KrbEvent -EventId 4769 -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter {
                    $FilterHashtable.Id.Count -eq 1 -and $FilterHashtable.Id[0] -eq 4769
                }
        }

        It 'pushes the time window into the filter rather than filtering afterwards' {
            # The difference between a filter the log service evaluates and a Where-Object
            # after the fact is invisible in the output and is orders of magnitude in
            # runtime, which is exactly why it needs an assertion rather than a comment.
            $start = (Get-Date).AddDays(-7)
            $end = Get-Date

            Get-KrbEvent -StartTime $start -EndTime $end -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter {
                    $FilterHashtable.StartTime -eq $start -and $FilterHashtable.EndTime -eq $end
                }
        }

        It 'reads the Security log for a live collection' {
            Get-KrbEvent -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter { $FilterHashtable.LogName -eq 'Security' }
        }

        It 'defaults to all three Kerberos audit events' {
            Get-KrbEvent -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter {
                    $FilterHashtable.Id.Count -eq 3 -and
                    $FilterHashtable.Id -contains 4768 -and
                    $FilterHashtable.Id -contains 4769 -and
                    $FilterHashtable.Id -contains 4771
                }
        }

        It 'defaults to a thirty day window' {
            # Shorter than a month and the monthly batch job - reliably the thing hardening
            # breaks - falls outside the collection entirely.
            Get-KrbEvent -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter {
                    $days = ($FilterHashtable.EndTime - $FilterHashtable.StartTime).TotalDays
                    [Math]::Round($days) -eq 30
                }
        }

        It 'applies MaxEvents when one is set' {
            Get-KrbEvent -MaxEvents 1234 -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter { $MaxEvents -eq 1234 }
        }

        It 'omits MaxEvents entirely when it is zero' {
            # Get-WinEvent treats -MaxEvents 0 as an error rather than as unlimited, so the
            # unlimited case has to be expressed by not passing the parameter at all.
            Get-KrbEvent -MaxEvents 0 -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter { -not $PSBoundParameters.ContainsKey('MaxEvents') }
        }

        It 'rejects an inverted time window' {
            {
                Get-KrbEvent -StartTime (Get-Date) -EndTime (Get-Date).AddDays(-1) -ErrorAction Stop
            } | Should-Throw
        }
    }

    Context 'Domain controller discovery' {

        It 'reads every controller when none is named' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(
                    [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
                    [PSCustomObject]@{ HostName = 'dc02.ad.techbyjeff.net' }
                    [PSCustomObject]@{ HostName = 'dc03.ad.techbyjeff.net' }
                )
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            Get-KrbEvent -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 3 -Exactly
        }

        It 'does not discover controllers when they are named explicitly' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { throw 'should not be called' }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            Get-KrbEvent -ComputerName 'dc01', 'dc02' -WarningAction SilentlyContinue | Out-Null

            Should-NotInvoke Get-ADDomainController -ModuleName KrbEtypeInsight
            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 2 -Exactly
        }

        It 'errors usefully when discovery fails and no controller was named' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController { throw 'no domain' }

            {
                Get-KrbEvent -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*-ComputerName*'
        }
    }

    Context 'Fault tolerance' {

        It 'continues past an unreachable controller' {
            # At least one controller in a large estate is always down. A collection that
            # aborts on the first failure never completes, and the assessment never happens.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                @(
                    [PSCustomObject]@{ HostName = 'dc-down.ad.techbyjeff.net' }
                    [PSCustomObject]@{ HostName = 'dc-up.ad.techbyjeff.net' }
                )
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                if ($ComputerName -eq 'dc-down.ad.techbyjeff.net') {
                    throw [System.Exception]::new('The RPC server is unavailable')
                }
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            Get-KrbEvent -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

            # Both were attempted; the first failure did not stop the second.
            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 2 -Exactly
        }

        It 'reports an unreachable controller as a non-terminating error' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc-down.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new('The RPC server is unavailable')
            }

            $errors = @()
            Get-KrbEvent -ErrorVariable errors -ErrorAction SilentlyContinue `
                -WarningAction SilentlyContinue | Out-Null

            # ErrorVariable collects the original exception as well as the function's own
            # message, and the original arrives first. The assertion is that the collection
            # names the controller SOMEWHERE - an operator reading a partial assessment needs
            # to know which controller did not contribute, and 'The RPC server is
            # unavailable' on its own does not tell them.
            @($errors).Count | Should-BeGreaterThan 0
            ($errors -join ' ') | Should-MatchString 'dc-down'
        }
    }

    Context 'Empty collections' {

        It 'warns when a source matched nothing' {
            # The module's most dangerous quiet failure. With the Kerberos audit
            # subcategories disabled the collection returns nothing, and a report built on it
            # describes an empty domain in language indistinguishable from a clean one.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            $captured = @(Get-KrbEvent 3>&1)
            $warnings = @($captured | Where-Object {
                $_ -is [System.Management.Automation.WarningRecord]
            })

            @($warnings).Count | Should-BeGreaterThan 0
            ($warnings -join ' ') | Should-MatchString 'audit subcategories'
        }

        It 'names the audit subcategories that have to be enabled' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            $captured = @(Get-KrbEvent 3>&1)
            $text = ($captured | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }) -join ' '

            $text | Should-MatchString 'Kerberos Authentication Service'
            $text | Should-MatchString 'Kerberos Service Ticket Operations'
        }
    }

    Context 'Archived log collection' {

        It 'errors on a path that does not exist' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) 'no-such-file-krbetype.evtx'

            {
                Get-KrbEvent -Path $missing -ErrorAction Stop
            } | Should-Throw -ExceptionMessage '*not found*'
        }

        It 'builds a Path filter rather than a LogName filter' {
            # Get-WinEvent rejects a FilterHashtable carrying both keys, so this is not a
            # cosmetic distinction - getting it wrong makes the entire archived-log path,
            # and with it every offline assessment, fail to run.
            $probe = Join-Path ([System.IO.Path]::GetTempPath()) "krbetype-probe-$([guid]::NewGuid()).evtx"
            Set-Content -Path $probe -Value 'placeholder'

            try {
                Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                    throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
                }

                Get-KrbEvent -Path $probe -WarningAction SilentlyContinue | Out-Null

                Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                    -ParameterFilter {
                        $FilterHashtable.ContainsKey('Path') -and
                        -not $FilterHashtable.ContainsKey('LogName')
                    }
            }
            finally {
                Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Credentials' {

        It 'passes credentials through to the remote log read' {
            # Never exercised before. An assessment run from a workstation against controllers
            # in another forest supplies -Credential for every call, and a parameter that is
            # silently dropped surfaces as an access-denied on the controller rather than as a
            # missing argument here.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            $credential = [PSCredential]::new('TECHBYJEFF\svc-audit',
                (ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force))

            Get-KrbEvent -Credential $credential -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter { $null -ne $Credential }
        }

        It 'does not pass a credential it was not given' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent {
                throw [System.Exception]::new(
                    'No events were found that match the specified selection criteria.')
            }

            Get-KrbEvent -WarningAction SilentlyContinue | Out-Null

            Should-Invoke Get-WinEvent -ModuleName KrbEtypeInsight -Times 1 -Exactly `
                -ParameterFilter { -not $PSBoundParameters.ContainsKey('Credential') }
        }
    }

    Context 'Inferring that failure auditing is disabled' {

        # The most dangerous state this module can be run against, and the reason this
        # inference exists at all. Both Kerberos audit subcategories can be set to Success
        # WITHOUT Failure. In that state the KDC logs no 4771 and no failed 4769, so a
        # post-change verification returns a large, healthy-looking collection and the
        # operator reads it as "the change broke nothing". Nothing capable of recording
        # breakage was ever switched on.
        #
        # This was not hypothetical. A live lab domain was found in exactly that state: a
        # service ticket request the KDC rejected with KDC_ERR_ETYPE_NOTSUPP produced no
        # event whatsoever until Failure auditing was enabled.
        #
        # The inference is deliberately conservative - asking for 4771 and receiving none
        # across a large sample is the shape the misconfiguration makes, not proof of it -
        # so the boundaries matter as much as the warning does. A false positive here trains
        # people to ignore the one warning that must not be ignored.

        BeforeAll {
            function New-FakeRecordSet {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                    'PSUseShouldProcessForStateChangingFunctions', '',
                    Justification = 'Test fixture builder; constructs objects, changes no state.')]
                param([int]$Count)

                1..$Count | ForEach-Object { [PSCustomObject]@{ RecordId = $_ } }
            }

            # Captures warnings without letting them reach the host. Get-KrbEvent emits this
            # one from its end block, so the whole pipeline has to be consumed first.
            function Get-WarningText {
                param([scriptblock]$Action)

                $captured = @(& $Action 3>&1)
                @($captured |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
                    ForEach-Object { $_.Message }) -join ' '
            }
        }

        It 'warns when a large collection contains no failure at all' {
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { New-FakeRecordSet -Count 150 }

            # -RemoveParameterType is required because the real -Record parameter is typed
            # [EventLogRecord], which has no public constructor - the mock could not be given
            # an argument that satisfies it otherwise.
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' `
                -MockWith { [PSCustomObject]@{ IsFailure = $false } }

            $warning = Get-WarningText { Get-KrbEvent | Out-Null }

            $warning | Should-MatchString 'not one failure'
            $warning | Should-MatchString 'auditpol'
            $warning | Should-MatchString 'must not be read as showing none'
        }

        It 'stays silent when at least one failure was recorded' {
            # One failure anywhere proves the subcategory is logging failures, which is the
            # entire question. The warning must not fire on a healthy domain that simply had
            # a bad password somewhere in the window.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { New-FakeRecordSet -Count 150 }
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' `
                -MockWith {
                    [PSCustomObject]@{ IsFailure = ($Record.RecordId -eq 1) }
                }

            $warning = Get-WarningText { Get-KrbEvent | Out-Null }

            $warning | Should-NotMatchString 'not one failure'
        }

        It 'stays silent when 4771 was never requested' {
            # Collecting only 4769 and seeing no failures says nothing about audit policy -
            # the events that would have proved it were not asked for.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { New-FakeRecordSet -Count 150 }
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' `
                -MockWith { [PSCustomObject]@{ IsFailure = $false } }

            $warning = Get-WarningText { Get-KrbEvent -EventId 4769 | Out-Null }

            $warning | Should-NotMatchString 'not one failure'
        }

        It 'stays silent on a sample too small to mean anything' {
            # A handful of events with no failures among them is ordinary. Warning here would
            # fire on every small or narrow collection and devalue the warning everywhere.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { New-FakeRecordSet -Count 20 }
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' `
                -MockWith { [PSCustomObject]@{ IsFailure = $false } }

            $warning = Get-WarningText { Get-KrbEvent | Out-Null }

            $warning | Should-NotMatchString 'not one failure'
        }

        It 'reports a source whose records all failed to decode as empty' {
            # Distinct from a source that returned nothing: here the log had records and none
            # of them survived decoding. It must still be reported as an empty source, since
            # an assessment built on it measured nothing either way.
            Mock -ModuleName KrbEtypeInsight Get-ADDomainController {
                [PSCustomObject]@{ HostName = 'dc01.ad.techbyjeff.net' }
            }
            Mock -ModuleName KrbEtypeInsight Get-WinEvent { New-FakeRecordSet -Count 10 }
            Mock -ModuleName KrbEtypeInsight ConvertFrom-KrbEventRecord `
                -RemoveParameterType 'Record' -MockWith { $null }

            $warning = Get-WarningText { Get-KrbEvent | Out-Null }

            $warning | Should-MatchString 'dc01.ad.techbyjeff.net'
        }
    }

    Context 'Parameter validation' {

        It 'rejects an event identifier that is not a Kerberos audit event' {
            { Get-KrbEvent -EventId 4624 -ErrorAction Stop } | Should-Throw
        }

        It 'rejects a Kerberos audit event the risk engine does not model' {
            # 4770 is a valid Kerberos audit event, but it is not one of the three event
            # schemas Get-KrbEtypeRisk correlates. It must not be accepted and then silently
            # discarded by the assessment pipeline.
            { Get-KrbEvent -EventId 4770 -ErrorAction Stop } | Should-Throw
        }

        It 'rejects a negative MaxEvents' {
            { Get-KrbEvent -MaxEvents -1 -ErrorAction Stop } | Should-Throw
        }
    }
}
