function Invoke-CaEvaluateRequest {
    <#
    .SYNOPSIS
        Sends one evaluate request, retrying a throttle or a transient failure

    .DESCRIPTION
        The single point where this module talks to anything. Isolating it is what keeps the
        rest of the module a pure transform with no dependencies and no connection, and what
        makes the whole thing testable without a tenant: the request handler is a parameter, so
        a test supplies a scriptblock and never touches the network.

        The default handler calls Invoke-MgGraphRequest, checked for at run time rather than
        declared with #Requires. A #Requires -Modules line is enforced whenever the file is
        loaded, including when Pester dot-sources it, which would make this module untestable on
        any host without the Graph SDK installed - and this module has no need of the SDK at all
        unless somebody actually sends a request.

        Backoff is exponential with the server's Retry-After taking precedence when it sends
        one. The delay doubles per attempt, so the default five attempts at two seconds spans
        about half a minute before giving up, which is long enough to ride out a throttle and
        short enough that a genuinely broken run does not sit there for an hour.

    .PARAMETER Body
        The request body from ConvertTo-CaEvaluateBody.

    .PARAMETER Uri
        The evaluate endpoint.

    .PARAMETER RequestHandler
        A scriptblock taking the body and the URI and returning the raw response. Defaults to
        Invoke-MgGraphRequest.

    .PARAMETER MaxRetry
        How many times to retry before giving up.

    .PARAMETER InitialBackoffSecond
        The first backoff, doubling per attempt. Zero disables waiting, which is what the tests
        use.

    .OUTPUTS
        The raw response, in whatever shape the handler returned.

    .EXAMPLE
        Invoke-CaEvaluateRequest -Body $body -RequestHandler { param($b, $u) $canned }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Body,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Uri = 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate',

        [Parameter()]
        [scriptblock]$RequestHandler,

        [Parameter()]
        [ValidateRange(0, 20)]
        [int]$MaxRetry = 4,

        [Parameter()]
        [ValidateRange(0, 300)]
        [int]$InitialBackoffSecond = 2
    )

    if (-not $RequestHandler) {
        if (-not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
            throw ('Invoke-MgGraphRequest was not found. Install and import ' +
                'Microsoft.Graph.Authentication and run Connect-MgGraph, or pass your own ' +
                '-RequestHandler.')
        }

        $RequestHandler = {
            param($RequestBody, $RequestUri)
            Invoke-MgGraphRequest -Method POST -Uri $RequestUri -OutputType Json `
                -Body ($RequestBody | ConvertTo-Json -Depth 10)
        }
    }

    $attempt = 0
    $backoff = $InitialBackoffSecond

    while ($true) {
        try {
            return & $RequestHandler $Body $Uri
        } catch {
            $directive = Get-CaRetryDirective -ErrorRecord $_

            if (-not $directive.ShouldRetry -or $attempt -ge $MaxRetry) {
                throw
            }

            $attempt++
            $wait = $backoff
            if ($null -ne $directive.RetryAfterSecond) {
                # The server's number beats anything invented here
                $wait = $directive.RetryAfterSecond
            }

            $status = if ($null -ne $directive.StatusCode) { $directive.StatusCode } else { 'transient failure' }
            Write-Verbose "Attempt $attempt of $MaxRetry after $status; waiting $wait second(s)"

            if ($wait -gt 0) { Start-Sleep -Seconds $wait }
            $backoff = $backoff * 2
        }
    }
}
