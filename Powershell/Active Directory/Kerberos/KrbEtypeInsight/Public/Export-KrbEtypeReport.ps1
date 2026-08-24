#Requires -Version 7.6

function Export-KrbEtypeReport {
    <#
    .SYNOPSIS
        Writes a Kerberos encryption type risk assessment to HTML, CSV or JSON

    .DESCRIPTION
        Renders the output of Get-KrbEtypeRisk into a form that can be circulated, attached
        to a change record, or diffed against a previous run.

        Three formats, for three different readers:

        - Html produces a single self-contained file with a summary, a prioritised table and
          the evidence behind every finding. No external stylesheet, script or font is
          referenced, so it survives being emailed, dropped on a file share, or opened on a
          machine with no internet access - which is the machine most people open a security
          report on. It is the format to send to an application owner.

        - Csv produces one row per finding rather than one row per principal, because a
          principal with four findings needs four rows to be filtered and pivoted usefully in
          a spreadsheet. Evidence is flattened to text.

        - Json preserves the object graph including all evidence, and is the format to keep
          for comparison against the next run. This is what makes "KRB002 is down from 40
          accounts to 3" answerable.

        Content is HTML-encoded on the way in. Every principal name, service name and client
        address in this report originated in the event log, written there by whoever made the
        request - a service principal name is chosen by the client and can contain markup. An
        assessment report that renders its input verbatim is a stored cross-site scripting
        vector aimed at the person reading it, which is a poor way to end a security review.

    .PARAMETER Risk
        [System.Object[]] (Mandatory, Pipeline: ByValue)

        Risk objects from Get-KrbEtypeRisk.

    .PARAMETER Path
        [System.String] (Mandatory, No Pipeline Support)

        Destination file. The parent directory must exist.

    .PARAMETER Format
        [System.String] (Optional, No Pipeline Support)

        Html, Csv or Json. Defaults to Html.

    .PARAMETER Title
        [System.String] (Optional, No Pipeline Support)

        Report heading. Defaults to a generic title with the current date.

    .PARAMETER DomainContext
        [System.Object] (Optional, No Pipeline Support)

        Domain baseline from Get-KrbDomainEtypeContext. When supplied, the HTML report opens
        with the functional level, domain default and controller agreement that the findings
        were judged against - without which a reader cannot tell whether the baseline was
        measured or assumed.

    .PARAMETER PassThru
        [System.Management.Automation.SwitchParameter] (Optional, No Pipeline Support)

        Return the written file as a FileInfo object.

    .EXAMPLE
        PS> Get-KrbEvent | Get-KrbEtypeRisk | Export-KrbEtypeReport -Path .\krb-risk.html

        DESCRIPTION: Produces the standard assessment report
        OUTPUT: A self-contained HTML file
        USE CASE: The artefact to attach to a change request

    .EXAMPLE
        PS> $context = Get-KrbDomainEtypeContext
        PS> Get-KrbEvent | Get-KrbEtypeRisk -DomainContext $context |
                Export-KrbEtypeReport -Path .\krb-risk.html -DomainContext $context `
                    -Title 'RC4 removal readiness - Phase 1'

        DESCRIPTION: A report that states the baseline it was judged against
        OUTPUT: HTML including the domain functional level and per-controller policy
        USE CASE: A report that will be read by someone who was not in the room

    .EXAMPLE
        PS> Get-KrbEvent | Get-KrbEtypeRisk | Export-KrbEtypeReport -Path .\krb-risk.json -Format Json

        DESCRIPTION: Preserves the full object graph for comparison
        OUTPUT: JSON with all evidence retained
        USE CASE: Establishing the baseline for a quarterly trend

    .INPUTS
        KrbEtypeInsight.Risk

    .OUTPUTS
        None by default. System.IO.FileInfo when -PassThru is specified.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        The report names accounts, service principal names and client addresses. Handle it as
        an internal document.

        TROUBLESHOOTING:
        - Report rendering: .\Troubleshooting\Common\Report-Output.md
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object[]]$Risk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Html', 'Csv', 'Json')]
        [string]$Format = 'Html',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [object]$DomainContext,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        if (-not $Title) {
            $Title = "Kerberos Encryption Type Risk Assessment - $(Get-Date -Format 'yyyy-MM-dd')"
        }

        # Resolve-Path fails on a path that does not exist yet, which is every output file, so
        # the parent is resolved instead and the leaf appended. This also normalises a
        # relative path against the caller's location rather than the process working
        # directory, which are not the same thing in PowerShell.
        $parent = Split-Path -Path $Path -Parent
        if (-not $parent) { $parent = '.' }

        $resolvedParent = Resolve-Path -Path $parent -ErrorAction SilentlyContinue
        if (-not $resolvedParent) {
            Write-Error "Output directory does not exist: $parent" -ErrorAction Stop
            return
        }

        $outputPath = Join-Path -Path $resolvedParent.Path -ChildPath (Split-Path -Path $Path -Leaf)

        $collected = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $Risk) {
            if ($item) { $collected.Add($item) }
        }
    }

    end {
        if ($collected.Count -eq 0) {
            Write-Warning ('No risk objects were supplied, so no report was written. An empty ' +
                'assessment means nothing was measured, not that nothing is at risk.')
            return
        }

        if (-not $PSCmdlet.ShouldProcess($outputPath, "Write $Format assessment report")) {
            return
        }

        Write-Verbose "Writing $($collected.Count) risk object(s) as $Format to $outputPath"

        try {
            switch ($Format) {

                'Json' {
                    # Depth 8 reaches through Risk to Findings to Evidence and into the
                    # nested arrays inside Evidence. The default of 2 truncates at Findings
                    # and produces a file whose evidence is the string
                    # 'System.Collections.Hashtable'.
                    $collected | ConvertTo-Json -Depth 8 |
                        Set-Content -Path $outputPath -Encoding utf8 -ErrorAction Stop
                }

                'Csv' {
                    # One row per finding. A principal with four findings is four rows, which
                    # is what makes the file pivotable; one row per principal forces the
                    # findings into a single joined cell and defeats the purpose of using a
                    # spreadsheet.
                    $rows = foreach ($item in $collected) {
                        foreach ($finding in @($item.Findings)) {
                            [PSCustomObject]@{
                                PrincipalName    = $item.PrincipalName
                                Roles            = @($item.Roles) -join ';'
                                RiskLevel        = $item.RiskLevel
                                RiskScore        = $item.RiskScore
                                WillBreak        = $item.WillBreakOnHardening
                                FindingCode      = $finding.Code
                                Severity         = $finding.Severity
                                FindingTitle     = $finding.Title
                                FindingDetail    = $finding.Detail
                                RecommendedAction = $finding.RecommendedAction
                                RequestCount     = $item.RequestCount
                                FailureCount     = $item.FailureCount
                                ClientCount      = $item.ClientCount
                                ClientsWithoutAes = @($item.ClientsWithoutAesSupport) -join ';'
                                ObservedEtypes   = @($item.ObservedTicketEtypeNames) -join ';'
                                AvailableKeys    = @($item.AvailableKeys) -join ';'
                                ConfiguredEtypes = if ($item.ConfiguredEncryptionTypes) {
                                    $item.ConfiguredEncryptionTypes.EffectiveHex
                                } else { $null }
                                FirstSeen        = $item.FirstSeen
                                LastSeen         = $item.LastSeen
                                SchemaVersion2   = $item.EventSchemaVersion2
                            }
                        }
                    }

                    $rows | Export-Csv -Path $outputPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
                }

                'Html' {
                    $html = New-KrbHtmlReport -Risk $collected.ToArray() -Title $Title `
                        -DomainContext $DomainContext -CorrelationId $correlationId
                    $html | Set-Content -Path $outputPath -Encoding utf8 -ErrorAction Stop
                }
            }
        }
        catch {
            $errorDetails = @{
                CorrelationId = $correlationId
                Function      = $MyInvocation.MyCommand.Name
                OutputPath    = $outputPath
                Format        = $Format
                ErrorMessage  = $_.Exception.Message
                Line          = $_.InvocationInfo.ScriptLineNumber
            }
            Write-Verbose ('Report write failure detail: ' + ($errorDetails | ConvertTo-Json -Compress))
            Write-Error "Failed to write report to '$outputPath': $($_.Exception.Message)" -ErrorAction Stop
            return
        }

        Write-Verbose "Completed $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        if ($PassThru) { Get-Item -Path $outputPath }
    }
}
