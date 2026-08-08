function Get-OktaTestErrorDetail {
    <#
    .SYNOPSIS
        Extracts the useful part of a failed Okta API response

    .DESCRIPTION
        Okta puts the actionable text in the response body, under errorSummary and
        errorCauses, and PowerShell throws that body away in favour of a generic
        "The remote server returned an error" message. Worse, the two editions surface the
        body differently: PowerShell 7 populates $_.ErrorDetails.Message, Windows PowerShell
        often leaves it empty and only exposes the response stream.

        This reads whichever one is available and flattens errorCauses, which is the field
        that actually says which attribute was rejected and why.

    .PARAMETER ErrorRecord
        The ErrorRecord caught from Invoke-WebRequest

    .OUTPUTS
        String suitable for putting straight into an exception message

    .EXAMPLE
        catch { throw (Get-OktaTestErrorDetail -ErrorRecord $_) }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $rawBody = $null

    if ($ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $rawBody = $ErrorRecord.ErrorDetails.Message
    }
    elseif ($ErrorRecord.Exception.PSObject.Properties['Response'] -and $ErrorRecord.Exception.Response) {
        # Windows PowerShell only. GetResponseStream does not exist on the PowerShell 7
        # HttpResponseMessage, hence the method probe rather than a version check.
        $response = $ErrorRecord.Exception.Response
        if ($response.PSObject.Methods['GetResponseStream']) {
            $reader = $null
            try {
                $stream = $response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $rawBody = $reader.ReadToEnd()
            }
            catch {
                Write-Verbose "Could not read the error response stream: $($_.Exception.Message)"
            }
            finally {
                if ($reader) { $reader.Dispose() }
            }
        }
    }

    # Whatever is left when the body is absent or is not an Okta error document. A transport
    # failure is the common case: PowerShell 7 puts the inner exception's entire ToString,
    # stack trace included, into both ErrorDetails.Message and Exception.Message, so a refused
    # connection yields twenty lines of System.Net internals wrapped around one useful
    # sentence. Keep the sentence. The full record is still on $Error[0] for anyone who wants
    # it, and Okta always answers an API error with JSON, so nothing structured is lost here.
    $fallbackSource = if ([string]::IsNullOrWhiteSpace($rawBody)) {
        $ErrorRecord.Exception.Message
    }
    else {
        $rawBody
    }
    $fallback = (@($fallbackSource -split "`r?`n") |
        Where-Object { $_.Trim() } | Select-Object -First 1)
    $fallback = if ($fallback) { $fallback.Trim() } else { 'no further detail was returned' }

    if ([string]::IsNullOrWhiteSpace($rawBody)) { return $fallback }

    $parsed = $null
    try { $parsed = $rawBody | ConvertFrom-Json } catch { return $fallback }

    if (-not $parsed) { return $fallback }

    # The token endpoint uses the OAuth error shape, everything else uses Okta's own.
    if ($parsed.PSObject.Properties['error'] -and -not $parsed.PSObject.Properties['errorSummary']) {
        $oauthParts = @($parsed.error)
        if ($parsed.PSObject.Properties['error_description']) {
            $oauthParts += $parsed.error_description
        }
        return ($oauthParts -join ': ')
    }

    $parts = @()
    if ($parsed.PSObject.Properties['errorSummary']) { $parts += $parsed.errorSummary }
    if ($parsed.PSObject.Properties['errorCauses'] -and $parsed.errorCauses) {
        $parts += @($parsed.errorCauses | ForEach-Object { $_.errorSummary })
    }
    if ($parsed.PSObject.Properties['errorCode'] -and $parsed.errorCode) {
        $parts += "[$($parsed.errorCode)]"
    }

    $message = ($parts | Where-Object { $_ }) -join ' '
    if ([string]::IsNullOrWhiteSpace($message)) { return $fallback }

    return $message
}
