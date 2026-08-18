function Get-CaRetryDirective {
    <#
    .SYNOPSIS
        Decides whether a failed request should be retried, and after how long

    .DESCRIPTION
        The evaluate endpoint's reference documents no throttling limits, which is not the same
        as there being none - Graph throttles per-resource and the numbers are not always
        published. A matrix run is exactly the shape of traffic that finds an unpublished limit:
        dozens of POSTs to one endpoint as fast as they will go. So retry is built in from the
        start rather than added after the first run that fails halfway through.

        Reading the status code is done defensively because the exception shape depends on who
        made the call. Invoke-MgGraphRequest, Invoke-RestMethod and a caller's own handler all
        surface HTTP failures differently, and this module deliberately lets any of them be the
        transport. Every access is therefore attempted and allowed to fail, with a match on the
        message as the last resort - crude, but a retry that does not happen because a property
        was named differently is worse than one triggered by a string.

        Retrying is limited to the codes where it is meaningful: 429, which is a throttle and
        carries Retry-After, and 502, 503 and 504, which are transient. A 400 or a 403 is a
        request that will fail identically forever, and retrying it just spends the quota that
        the throttle is about to care about.

        Retry-After is honoured when the response carries it, because the server's number beats
        any backoff this module invents. Only when it is absent does the caller fall back to
        exponential backoff.

    .PARAMETER ErrorRecord
        The error record from the failed request.

    .OUTPUTS
        PSCustomObject with ShouldRetry, StatusCode and RetryAfterSecond. RetryAfterSecond is
        null when the response did not say.

    .EXAMPLE
        $directive = Get-CaRetryDirective -ErrorRecord $_
        if ($directive.ShouldRetry) { Start-Sleep -Seconds $directive.RetryAfterSecond }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 0.2.0
        Last Updated: 2026-08-17
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$ErrorRecord
    )

    $retryable = @(429, 502, 503, 504)
    $statusCode = $null
    $retryAfter = $null

    $exception = $null
    if ($null -ne $ErrorRecord) {
        $exception = Get-CaProperty -InputObject $ErrorRecord -Name 'Exception'
    }

    $response = Get-CaProperty -InputObject $exception -Name 'Response'

    foreach ($source in @($response, $exception)) {
        if ($null -ne $statusCode -or $null -eq $source) { continue }
        foreach ($name in @('StatusCode', 'Status', 'ResponseStatusCode')) {
            $candidate = Get-CaProperty -InputObject $source -Name $name
            if ($null -eq $candidate) { continue }
            try { $statusCode = [int]$candidate; break } catch { $statusCode = $null }
        }
    }

    # Retry-After, if the response carries one. Header collections differ enough between
    # HttpClient and the older stacks that each shape gets its own attempt.
    $headers = Get-CaProperty -InputObject $response -Name 'Headers'
    if ($null -ne $headers) {
        $retryAfterHeader = Get-CaProperty -InputObject $headers -Name 'RetryAfter'
        $delta = Get-CaProperty -InputObject $retryAfterHeader -Name 'Delta'
        $totalSeconds = Get-CaProperty -InputObject $delta -Name 'TotalSeconds'
        if ($null -ne $totalSeconds) {
            try { $retryAfter = [int][math]::Ceiling([double]$totalSeconds) } catch { $retryAfter = $null }
        }

        if ($null -eq $retryAfter) {
            $raw = $null
            try { $raw = $headers['Retry-After'] } catch { $raw = $null }
            if ($null -ne $raw) {
                $first = @($raw)[0]
                $parsed = 0
                if ([int]::TryParse([string]$first, [ref]$parsed)) { $retryAfter = $parsed }
            }
        }
    }

    $shouldRetry = $false
    if ($null -ne $statusCode) {
        $shouldRetry = $retryable -contains $statusCode
    } else {
        # No status code anywhere. Fall back to the message, which catches both a throttle
        # surfaced as text and the transient socket failures a long run runs into.
        $message = [string](Get-CaProperty -InputObject $exception -Name 'Message')
        $transient = '(?i)429|too many requests|throttl|503|service unavailable|' +
                     'timed out|connection reset'
        $shouldRetry = $message -match $transient
    }

    return [PSCustomObject]@{
        PSTypeName       = 'CaOutcome.RetryDirective'
        ShouldRetry      = $shouldRetry
        StatusCode       = $statusCode
        RetryAfterSecond = $retryAfter
    }
}
