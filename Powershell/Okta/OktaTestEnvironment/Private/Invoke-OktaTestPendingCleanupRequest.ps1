function Invoke-OktaTestPendingCleanupRequest {
    <#
    .SYNOPSIS
        Makes a request that can fail purely because Okta has not finished deleting something

    .DESCRIPTION
        Okta deletes schema-bearing objects asynchronously. The DELETE returns success, the
        object disappears from every listing, and for some seconds afterwards the name is still
        reserved by a background clean-up job. Re-creating it in that window fails.

        This matters here more than it would elsewhere, because the module's normal workflow is
        exactly the thing that triggers it: tear down, then seed again. Both failures were
        reproduced against a live tenant immediately after a teardown, and both went away on
        their own:

        - Custom profile attributes come back as a 400 naming each attribute: "the deletion
          process for an attribute with the same variable name is incomplete. Wait until the
          data clean up process finishes and then try again."
        - A user type comes back as a bare 400 "The request body was not well-formed", which
          says nothing about the real cause and sends you looking for a malformed payload that
          is in fact perfectly valid. The identical body succeeds a few seconds later.

        So this retries on that specific pair of signatures and nothing else. A 400 that means
        what it says is still an immediate failure - retrying every 400 would turn a genuine
        bad request into a slow genuine bad request.

    .PARAMETER Method
        HTTP method

    .PARAMETER Path
        Path below the org URL

    .PARAMETER Body
        Request body

    .PARAMETER MaxWaitSeconds
        Total time to keep retrying before giving up

    .OUTPUTS
        The deserialised response body

    .EXAMPLE
        Invoke-OktaTestPendingCleanupRequest -Method POST -Path '/api/v1/meta/types/user' -Body $body

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('POST', 'PUT')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Body,

        [Parameter()]
        [ValidateRange(0, 300)]
        [int]$MaxWaitSeconds = 90
    )

    # Both signatures Okta uses for "still cleaning up". The second is deliberately broad
    # because Okta gives no better hint for a user type, and it is only ever consulted for an
    # HTTP 400 on a create.
    $pendingPattern = 'deletion process|clean up process|was not well-formed'

    $waited = 0
    $delay = 5

    while ($true) {
        try {
            return Invoke-OktaTestRequest -Method $Method -Path $Path -Body $Body
        }
        catch {
            $isPending = $_.Exception.Message -match 'HTTP 400' -and
                $_.Exception.Message -match $pendingPattern

            if (-not $isPending -or $waited -ge $MaxWaitSeconds) { throw }

            Write-Warning ("Okta has not finished deleting a previous object of this name. " +
                "Waiting $delay seconds and retrying ($waited of $MaxWaitSeconds elapsed).")
            Start-Sleep -Seconds $delay
            $waited += $delay
            $delay = [Math]::Min(20, $delay * 2)
        }
    }
}
