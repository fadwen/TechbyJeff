function Invoke-OktaTestRequest {
    <#
    .SYNOPSIS
        Single entry point for every Okta management API call this module makes

    .DESCRIPTION
        Wraps Invoke-WebRequest with the things the Okta API needs and PowerShell does not do
        by default:

        - UTF-8 on both sides. The seed data carries accented names on purpose, and Windows
          PowerShell will otherwise send them as question marks and decode responses as
          Latin-1. Request bodies are encoded to UTF-8 bytes and responses are decoded from
          the raw stream rather than trusting the charset negotiation.
        - Cursor pagination. Okta pages with a Link header, not a page number, so -Paginate
          follows rel="next" until a page comes back empty.
        - 429 handling. The Integrator Free Plan has a low per-minute ceiling and seeding an
          environment will hit it. Retries honour X-Rate-Limit-Reset when Okta sends it and
          fall back to exponential backoff when it does not.
        - Readable errors. Okta puts the useful part in errorCauses inside the response body,
          which PowerShell discards by default on both editions.

        Invoke-WebRequest is used rather than Invoke-RestMethod because the Link and
        X-Rate-Limit headers are only reachable through the response object, and Windows
        PowerShell's Invoke-RestMethod does not expose them at all.

    .PARAMETER Method
        HTTP method

    .PARAMETER Path
        Path below the org URL, beginning with a slash, for example /api/v1/users

    .PARAMETER Body
        Request body. A string is sent as-is, anything else is serialised to JSON.

    .PARAMETER Query
        Query string parameters. Values are URL-encoded.

    .PARAMETER Paginate
        Follow the Link rel="next" header and return every item across all pages

    .PARAMETER ContentType
        Overrides the request content type. Only the token endpoint needs this, because it
        takes form encoding rather than JSON.

    .PARAMETER Connection
        Connection hashtable to use instead of the module's active connection. Used by
        Connect-OktaTestEnvironment to validate credentials before storing them.

    .PARAMETER MaxRetry
        Attempts made against a rate limit or a server error before giving up

    .OUTPUTS
        The deserialised response body, or $null for a 204

    .EXAMPLE
        Invoke-OktaTestRequest -Method GET -Path '/api/v1/users' -Paginate

    .EXAMPLE
        Invoke-OktaTestRequest -Method POST -Path '/api/v1/groups' -Body @{
            profile = @{ name = 'OKTALAB-Dept-Engineering'; description = 'Engineering' }
        }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [string]$ContentType = 'application/json; charset=UTF-8',

        [Parameter()]
        [hashtable]$Connection,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetry = 5
    )

    if (-not $Connection) { $Connection = Get-OktaTestConnection }

    # Windows PowerShell defaults to TLS 1.0, which Okta refuses outright. Only ever add to
    # the enabled set: clearing it would change behaviour for everything else in the session.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }

    $uri = '{0}{1}' -f $Connection.OrgUrl.TrimEnd('/'), $Path
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            if ($null -eq $Query[$key] -or '' -eq $Query[$key]) { continue }
            '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$Query[$key])
        }
        if ($pairs) { $uri = '{0}?{1}' -f $uri, ($pairs -join '&') }
    }

    # The token endpoint is the one Okta endpoint that must not carry an Authorization
    # header: the client assertion in the body is the credential, and sending both makes Okta
    # reject the request. Callers signal that by passing a connection with no header.
    $headers = @{ 'Accept' = 'application/json' }
    if (-not [string]::IsNullOrWhiteSpace($Connection.AuthorizationHeader)) {
        $headers['Authorization'] = $Connection.AuthorizationHeader
    }

    $bodyBytes = $null
    if ($null -ne $Body) {
        $bodyText = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
    }

    # Invoke-WebRequest paints a progress bar per call on Windows PowerShell, which for a few
    # hundred calls costs more wall clock than the calls do.
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $collected = [System.Collections.Generic.List[object]]::new()
    $result = $null

    try {
        $nextUri = $uri

        while ($nextUri) {
            $attempt = 0
            $response = $null

            while ($true) {
                $attempt++
                try {
                    $requestArgs = @{
                        Uri             = $nextUri
                        Method          = $Method
                        Headers         = $headers
                        UseBasicParsing = $true
                        ErrorAction     = 'Stop'
                    }
                    if ($null -ne $bodyBytes) {
                        $requestArgs.Body        = $bodyBytes
                        $requestArgs.ContentType = $ContentType
                    }

                    Write-Verbose "Okta $Method $nextUri (attempt $attempt)"
                    $response = Invoke-WebRequest @requestArgs
                    break
                }
                catch {
                    $statusCode = 0
                    if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
                    }

                    $retryable = ($statusCode -eq 429 -or $statusCode -ge 500)
                    if (-not $retryable -or $attempt -ge $MaxRetry) {
                        # The message is built into its own variable rather than inline. A
                        # concatenation written directly inside New-Object's argument list
                        # binds as ONE array argument, so "message" + detail, $exception is
                        # joined into a single string and matched against Exception(string).
                        # The result is a message with the inner exception's whole stack trace
                        # stringified into it, and no InnerException set at all.
                        $statusText = if ($statusCode) { " with HTTP $statusCode" } else { '' }
                        $message = "Okta $Method $Path failed${statusText}: " +
                            (Get-OktaTestErrorDetail -ErrorRecord $_)

                        throw (New-Object System.Exception($message, $_.Exception))
                    }

                    # Okta answers a 429 with the epoch second the window resets. Prefer it
                    # over guessing, but cap it: a clock skew between here and Okta would
                    # otherwise park the run for an arbitrarily long time.
                    $waitSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
                    try {
                        $resetHeader = $_.Exception.Response.Headers['X-Rate-Limit-Reset']
                        if ($resetHeader) {
                            $resetEpoch = [long](@($resetHeader)[0])
                            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                            $fromHeader = $resetEpoch - $now + 1
                            if ($fromHeader -gt 0) { $waitSeconds = [Math]::Min(60, $fromHeader) }
                        }
                    }
                    catch {
                        Write-Verbose "No usable X-Rate-Limit-Reset header; backing off instead."
                    }

                    Write-Warning ("Okta returned HTTP $statusCode for $Method $Path. " +
                        "Retrying in $waitSeconds second(s) (attempt $attempt of $MaxRetry).")
                    Start-Sleep -Seconds $waitSeconds
                }
            }

            # Decode from the raw bytes rather than $response.Content. Okta does not send a
            # charset on application/json, and Windows PowerShell then decodes as Latin-1 and
            # turns every accented character in the directory into mojibake.
            $content = $null
            if ($response.RawContentStream -and $response.RawContentStream.Length -gt 0) {
                $content = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
            }
            elseif ($response.Content -is [byte[]]) {
                $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
            }
            else {
                $content = [string]$response.Content
            }

            $page = $null
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $page = $content | ConvertFrom-Json
            }

            if (-not $Paginate) {
                $result = $page
                break
            }

            $pageItems = @($page)
            if ($pageItems.Count -eq 0) { break }
            $collected.AddRange($pageItems)

            # Okta pages with an opaque cursor in a Link header. Windows PowerShell gives the
            # header back as one comma-joined string and PowerShell 7 as a collection, so
            # normalise before parsing. The self-comparison is the loop guard: Okta will
            # happily hand back a next link identical to the one just fetched.
            $currentUri = $nextUri
            $nextUri = $null
            $linkHeader = $response.Headers['Link']
            if ($linkHeader) {
                $linkText = (@($linkHeader) -join ', ')
                $match = [regex]::Match($linkText, '<(?<url>[^>]+)>\s*;\s*rel="next"')
                if ($match.Success -and $match.Groups['url'].Value -ne $currentUri) {
                    $nextUri = $match.Groups['url'].Value
                }
            }
        }
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    if ($Paginate) { return $collected.ToArray() }
    return $result
}
