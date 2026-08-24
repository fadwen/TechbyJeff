#Requires -Version 7.6

function New-KrbHtmlReport {
    <#
    .SYNOPSIS
        Renders risk objects as a single self-contained HTML document

    .DESCRIPTION
        Builds the HTML assessment report. Every element is inline - stylesheet, layout and
        colours - so the file works when emailed, copied to a share, or opened on an isolated
        machine, which is where security reports are usually read.

        All interpolated values pass through HTML encoding. The names in this report come
        from the event log, and an event log field is written by whoever made the request:
        a service principal name is chosen by the client and may contain markup. Rendering it
        verbatim would turn the assessment into a stored cross-site scripting delivery
        mechanism aimed at its own reader.

        A StringBuilder is used rather than string concatenation because the output grows to
        several hundred KB on a real domain, and the report body is assembled from thousands
        of fragments - which is the case where concatenation's quadratic behaviour actually
        shows up rather than being a micro-optimisation.

    .PARAMETER Risk
        [System.Object[]] (Mandatory, No Pipeline Support)

        Risk objects to render.

    .PARAMETER Title
        [System.String] (Mandatory, No Pipeline Support)

        Document heading.

    .PARAMETER DomainContext
        [System.Object] (Optional, No Pipeline Support)

        Domain baseline to render in the header section.

    .PARAMETER CorrelationId
        [System.String] (Optional, No Pipeline Support)

        Correlation identifier recorded in the report footer for audit traceability.

    .EXAMPLE
        PS> New-KrbHtmlReport -Risk $risks -Title 'RC4 readiness'

        DESCRIPTION: Renders the report body
        OUTPUT: A complete HTML document as a single string
        USE CASE: Called by Export-KrbEtypeReport

    .OUTPUTS
        System.String

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - Report rendering: .\Troubleshooting\Common\Report-Output.md
    #>
    # Returns a string and touches nothing. The file write it feeds is performed by
    # Export-KrbEtypeReport, which does declare SupportsShouldProcess - that is where the
    # state change happens and where -WhatIf belongs. The attribute's Justification must be a
    # single unwrappable string literal, so it carries only a summary.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns a string; the caller owns the file write. See comment above.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$Risk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [object]$DomainContext,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId
    )

    # Local encoder. Applied to every value that reaches the document, without exception -
    # a per-call decision about whether a particular field is "safe" is a decision that will
    # eventually be made wrongly.
    $enc = { param($value) [System.Net.WebUtility]::HtmlEncode([string]$value) }

    $order = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Info = 4; None = 5 }
    $sorted = @($Risk | Sort-Object `
        @{ Expression = { $order["$($_.RiskLevel)"] } },
        @{ Expression = { $_.RiskScore }; Descending = $true },
        PrincipalName)

    $counts = @{ Critical = 0; High = 0; Medium = 0; Low = 0; Info = 0; None = 0 }
    foreach ($item in $sorted) {
        $key = "$($item.RiskLevel)"
        if ($counts.ContainsKey($key)) { $counts[$key]++ }
    }

    $breaking = @($sorted | Where-Object { $_.WillBreakOnHardening })
    $affectedClients = @($sorted.ClientsWithoutAesSupport | Where-Object { $_ } | Sort-Object -Unique)

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>$(& $enc $Title)</title>")
    [void]$sb.AppendLine(@'
<style>
:root { color-scheme: light dark;
  --bg:#ffffff; --fg:#1a1a1a; --muted:#5c5c5c; --line:#d8d8d8; --panel:#f6f6f7;
  --crit:#b3261e; --high:#b25000; --med:#8a6d00; --low:#2a6f9e; --info:#4a7c59; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#16181c; --fg:#e6e6e6; --muted:#a0a0a0; --line:#33363d; --panel:#1e2127;
    --crit:#ff6b5e; --high:#ff9f45; --med:#e0c04a; --low:#6db3e0; --info:#7fc490; } }
* { box-sizing:border-box; }
body { margin:0; padding:2rem 1.25rem 4rem; background:var(--bg); color:var(--fg);
  font:15px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; }
main { max-width:1180px; margin:0 auto; }
h1 { font-size:1.6rem; margin:0 0 .35rem; }
h2 { font-size:1.15rem; margin:2.25rem 0 .75rem; padding-bottom:.35rem; border-bottom:1px solid var(--line); }
h3 { font-size:1rem; margin:0 0 .4rem; }
.sub { color:var(--muted); font-size:.87rem; margin:0 0 1.5rem; }
.tiles { display:flex; flex-wrap:wrap; gap:.75rem; margin:1rem 0 1.5rem; }
.tile { flex:1 1 130px; background:var(--panel); border:1px solid var(--line);
  border-radius:8px; padding:.8rem .9rem; }
.tile .n { font-size:1.7rem; font-weight:650; line-height:1.1; }
.tile .l { font-size:.76rem; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); }
.scroll { overflow-x:auto; border:1px solid var(--line); border-radius:8px; }
table { border-collapse:collapse; width:100%; font-size:.87rem; }
th,td { text-align:left; padding:.5rem .65rem; border-bottom:1px solid var(--line); vertical-align:top; }
th { background:var(--panel); font-weight:600; white-space:nowrap; position:sticky; top:0; }
tr:last-child td { border-bottom:none; }
code,.mono { font-family:ui-monospace,Consolas,Menlo,monospace; font-size:.85em; }
.badge { display:inline-block; padding:.1rem .45rem; border-radius:4px; font-size:.74rem;
  font-weight:650; text-transform:uppercase; letter-spacing:.03em; border:1px solid currentColor; }
.Critical{color:var(--crit)} .High{color:var(--high)} .Medium{color:var(--med)}
.Low{color:var(--low)} .Info{color:var(--info)} .None{color:var(--muted)}
details { background:var(--panel); border:1px solid var(--line); border-radius:8px;
  padding:.7rem .9rem; margin:.6rem 0; }
summary { cursor:pointer; font-weight:600; }
.finding { border-left:3px solid var(--line); padding:.15rem 0 .15rem .8rem; margin:.85rem 0; }
.finding.Critical{border-left-color:var(--crit)} .finding.High{border-left-color:var(--high)}
.finding.Medium{border-left-color:var(--med)} .finding.Low{border-left-color:var(--low)}
.finding.Info{border-left-color:var(--info)}
.finding p { margin:.35rem 0; }
.action { color:var(--fg); font-weight:600; }
.note { color:var(--muted); font-size:.83rem; }
.chips span { display:inline-block; background:var(--panel); border:1px solid var(--line);
  border-radius:4px; padding:.05rem .4rem; margin:.12rem .2rem .12rem 0; font-size:.8rem; }
footer { margin-top:3rem; padding-top:1rem; border-top:1px solid var(--line);
  color:var(--muted); font-size:.8rem; }
</style></head><body><main>
'@)

    [void]$sb.AppendLine("<h1>$(& $enc $Title)</h1>")
    [void]$sb.AppendLine("<p class=""sub"">Generated $(& $enc (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))" +
        " &middot; $($sorted.Count) principal(s) assessed</p>")

    # ---- Summary tiles ---------------------------------------------------------------
    [void]$sb.AppendLine('<div class="tiles">')
    foreach ($level in 'Critical', 'High', 'Medium', 'Low', 'Info') {
        [void]$sb.AppendLine("<div class=""tile""><div class=""n $level"">$($counts[$level])</div>" +
            "<div class=""l"">$level</div></div>")
    }
    [void]$sb.AppendLine("<div class=""tile""><div class=""n"">$($breaking.Count)</div>" +
        '<div class="l">Will break</div></div>')
    [void]$sb.AppendLine("<div class=""tile""><div class=""n"">$($affectedClients.Count)</div>" +
        '<div class="l">Legacy clients</div></div>')
    [void]$sb.AppendLine('</div>')

    # ---- Baseline --------------------------------------------------------------------
    if ($DomainContext) {
        [void]$sb.AppendLine('<h2>Assessment baseline</h2>')
        [void]$sb.AppendLine('<div class="scroll"><table><tbody>')

        $baselineRows = [ordered]@{
            'Domain'                  = $DomainContext.DomainName
            'Domain functional level' = $DomainContext.DomainMode
            'Forest functional level' = $DomainContext.ForestMode
            'AES key derivation supported' = $DomainContext.SupportsAesKeyDerivation
            'Domain default encryption types' = ("$($DomainContext.DomainDefaultDecoded.EffectiveHex) " +
                "($($DomainContext.DomainDefaultDecoded.CipherNames -join ', '))")
            'Default source'          = $DomainContext.DomainDefaultSource
            'Controllers disagree'    = $DomainContext.ControllersDisagreeOnDefault
            'krbtgt encryption types' = $DomainContext.KrbtgtEncryptionTypes.EffectiveHex
            'krbtgt password age'     = "$($DomainContext.KrbtgtPasswordAgeDays) day(s)"
            'Domain controllers'      = @($DomainContext.DomainControllers).Count
            'Trusts without AES'      = @($DomainContext.TrustsWithRc4Only).Count
        }

        foreach ($name in $baselineRows.Keys) {
            [void]$sb.AppendLine("<tr><th style=""width:16rem"">$(& $enc $name)</th>" +
                "<td>$(& $enc $baselineRows[$name])</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table></div>')

        # DomainDefaultSource of WindowsDefault means the baseline was assumed rather than
        # read. Saying so at the top is the difference between a reader trusting the report
        # and a reader being misled by it.
        if ($DomainContext.DomainDefaultSource -ne 'Registry') {
            [void]$sb.AppendLine('<p class="note">The domain default encryption types could not be ' +
                'read from the domain controllers, so the documented Windows default of 0x27 was ' +
                'assumed. Findings about accounts whose msDS-SupportedEncryptionTypes attribute is ' +
                'unset rest on that assumption.</p>')
        }
    }

    # ---- Priority table --------------------------------------------------------------
    [void]$sb.AppendLine('<h2>Prioritised findings</h2>')
    [void]$sb.AppendLine('<div class="scroll"><table><thead><tr>' +
        '<th>Principal</th><th>Level</th><th>Score</th><th>Role</th>' +
        '<th>Requests</th><th>Clients</th><th>Legacy clients</th>' +
        '<th>Observed etypes</th><th>Codes</th></tr></thead><tbody>')

    foreach ($item in $sorted) {
        $level = "$($item.RiskLevel)"
        [void]$sb.AppendLine('<tr>' +
            "<td class=""mono"">$(& $enc $item.PrincipalName)</td>" +
            "<td><span class=""badge $level"">$(& $enc $level)</span></td>" +
            "<td>$($item.RiskScore)</td>" +
            "<td>$(& $enc (@($item.Roles) -join ', '))</td>" +
            "<td>$($item.RequestCount)</td>" +
            "<td>$($item.ClientCount)</td>" +
            "<td>$(@($item.ClientsWithoutAesSupport).Count)</td>" +
            "<td class=""mono"">$(& $enc (@($item.ObservedTicketEtypeNames) -join ', '))</td>" +
            "<td class=""mono"">$(& $enc (@($item.FindingCodes) -join ' '))</td>" +
            '</tr>')
    }
    [void]$sb.AppendLine('</tbody></table></div>')

    # ---- Detail ----------------------------------------------------------------------
    [void]$sb.AppendLine('<h2>Detail and evidence</h2>')

    foreach ($item in $sorted) {
        $level = "$($item.RiskLevel)"
        [void]$sb.AppendLine('<details><summary>' +
            "<span class=""badge $level"">$(& $enc $level)</span> " +
            "<span class=""mono"">$(& $enc $item.PrincipalName)</span> " +
            "&mdash; score $($item.RiskScore), $($item.RequestCount) request(s)" +
            '</summary>')

        foreach ($finding in @($item.Findings)) {
            $sev = "$($finding.Severity)"
            [void]$sb.AppendLine("<div class=""finding $sev"">")
            [void]$sb.AppendLine("<h3><span class=""mono"">$(& $enc $finding.Code)</span> " +
                "$(& $enc $finding.Title)</h3>")
            [void]$sb.AppendLine("<p>$(& $enc $finding.Detail)</p>")

            if ($finding.RecommendedAction) {
                [void]$sb.AppendLine("<p class=""action"">Action: $(& $enc $finding.RecommendedAction)</p>")
            }

            if ($finding.Evidence -and $finding.Evidence.Keys.Count -gt 0) {
                [void]$sb.AppendLine('<p class="note">Evidence:</p><div class="chips">')
                foreach ($evidenceKey in ($finding.Evidence.Keys | Sort-Object)) {
                    $raw = $finding.Evidence[$evidenceKey]
                    $rendered = if ($raw -is [array]) { $raw -join ', ' } else { "$raw" }

                    # Evidence arrays can be long - a client list on a widely used service
                    # runs to hundreds. Truncating keeps the report readable; the JSON
                    # format exists for the complete set, and the note says so.
                    if ($rendered.Length -gt 400) {
                        $rendered = $rendered.Substring(0, 400) + ' ... (truncated, see JSON export)'
                    }
                    [void]$sb.AppendLine("<span><strong>$(& $enc $evidenceKey):</strong> " +
                        "$(& $enc $rendered)</span>")
                }
                [void]$sb.AppendLine('</div>')
            }
            [void]$sb.AppendLine('</div>')
        }

        if (@($item.ConfidenceNotes).Count -gt 0) {
            [void]$sb.AppendLine('<p class="note"><strong>Confidence:</strong></p><ul class="note">')
            foreach ($note in @($item.ConfidenceNotes)) {
                [void]$sb.AppendLine("<li>$(& $enc $note)</li>")
            }
            [void]$sb.AppendLine('</ul>')
        }

        [void]$sb.AppendLine('</details>')
    }

    [void]$sb.AppendLine('<footer>')
    [void]$sb.AppendLine('Produced by KrbEtypeInsight. This report names accounts, service principal ' +
        'names and client addresses - handle it as an internal document.')
    if ($CorrelationId) {
        [void]$sb.AppendLine("<br>Correlation ID: <span class=""mono"">$(& $enc $CorrelationId)</span>")
    }
    [void]$sb.AppendLine('</footer></main></body></html>')

    return $sb.ToString()
}
