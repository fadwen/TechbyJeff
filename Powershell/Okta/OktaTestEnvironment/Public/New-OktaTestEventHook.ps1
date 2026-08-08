function New-OktaTestEventHook {
    <#
    .SYNOPSIS
        Creates the seeded event hooks

    .DESCRIPTION
        An event hook is an outbound webhook: Okta POSTs to a URL when the events you subscribe
        to occur. A fresh org has none, so anything that audits outbound integrations has
        nothing to find until these exist.

        Two hooks, subscribed to events this lab actually generates. The lifecycle hook fires on
        create, suspend and delete - all of which the seeded users go through - and the group
        hook fires on membership changes, which the group rules produce on their own without
        anybody doing anything. So the hooks are not inert decoration; they correspond to
        traffic the environment really creates.

        The URL is under example.com rather than the lab domain, and that is not a
        preference. Okta VALIDATES the hook URL and rejects a hostname that does not resolve:
        https://hooks.oktalab.example.com/events fails with "Invalid URL provided", while
        https://example.com/... is accepted. Verified against a live tenant. example.com is
        IANA-reserved and does resolve, which makes it the only address that is both safe and
        acceptable to Okta.

        Nothing is listening at the other end, so deliveries will fail. That is fine and
        expected for a lab, and it is itself worth having: a hook whose deliveries fail is a
        state monitoring should notice.

    .PARAMETER HookName
        Restrict the operation to these CSV hook names

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalHooks, CreatedHooks, ExistingHooks, Hooks and Errors

    .EXAMPLE
        New-OktaTestEventHook -PassThru

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Okta creates these ACTIVE but unverified. Verification requires the endpoint to answer
        a challenge, which nothing here does, so they are created and left alone.

    .LINK
        New-OktaTestTrustedOrigin
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$HookName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaEventHooks.csv') -Encoding UTF8)
    if ($HookName) {
        $rows = @($rows | Where-Object { $HookName -contains $_.Name })
        $unknown = @($HookName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No event hook definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalHooks    = $rows.Count
        CreatedHooks  = 0
        ExistingHooks = 0
        Hooks         = @()
        Errors        = @()
    }

    $existingHooks = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/eventHooks' `
        -Query @{ limit = 200 } -Paginate)
    $hooks = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Okta event hook')) { continue }

        try {
            $existing = @($existingHooks | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $hook = $existing[0]
                $result.ExistingHooks++
                Write-Verbose "Reusing event hook $name"
            }
            else {
                $events = @($row.Events -split ';' | Where-Object { $_ })

                $hook = Invoke-OktaTestRequest -Method POST -Path '/api/v1/eventHooks' -Body @{
                    name    = $name
                    events  = @{ type = 'EVENT_TYPE'; items = $events }
                    channel = @{
                        type    = 'HTTP'
                        version = '1.0.0'
                        config  = @{ uri = $row.Uri }
                    }
                }
                $result.CreatedHooks++
                Write-Verbose "Created event hook $name"
            }

            $hooks.Add([PSCustomObject]@{
                Id     = $hook.id
                Key    = $row.Name
                Name   = $name
                Uri    = $row.Uri
                Status = $hook.status
                Events = @($row.Events -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create event hook '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Hooks = $hooks.ToArray()

    if ($PassThru) { return $result }
}
