function New-OktaTestNetworkZone {
    <#
    .SYNOPSIS
        Creates the seeded network zones that policies condition on

    .DESCRIPTION
        A zone is a named set of IP ranges, and it is what turns "allow sign-in" into "allow
        sign-in from the office". Policies reference zones by id, so these have to exist before
        New-OktaTestPolicy runs.

        Two zones, because one is not enough to test with:

        - Corporate-Egress, a POLICY zone, referenced by the admin sign-on rule. This is the
          allow case.
        - Suspect-Range, a BLOCKLIST zone. Blocklist zones behave differently from policy zones
          in evaluation and in the admin console, and a report that treats every zone the same
          gets this wrong.

        The ranges are all IANA documentation blocks - 198.51.100.0/24, 203.0.113.0/24 and
        192.0.2.0/24. They are reserved precisely so they can appear in examples without
        belonging to anybody, which matters here because a lab zone containing somebody's real
        address range is a policy that could really lock somebody out.

    .PARAMETER ZoneName
        Restrict the operation to these CSV zone names

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalZones, CreatedZones, ExistingZones, Zones and Errors

    .EXAMPLE
        New-OktaTestNetworkZone -PassThru

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

    .LINK
        New-OktaTestPolicy
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$ZoneName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaNetworkZones.csv') -Encoding UTF8)
    if ($ZoneName) {
        $rows = @($rows | Where-Object { $ZoneName -contains $_.Name })
        $unknown = @($ZoneName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No network zone definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalZones    = $rows.Count
        CreatedZones  = 0
        ExistingZones = 0
        Zones         = @()
        Errors        = @()
    }

    $existingZones = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/zones' -Query @{ limit = 200 } -Paginate)
    $zones = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, "Create Okta network zone ($($row.Usage))")) { continue }

        try {
            $existing = @($existingZones | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $zone = $existing[0]
                $result.ExistingZones++
                Write-Verbose "Reusing network zone $name"
            }
            else {
                # A CIDR and a bare range are different gateway types, and Okta rejects the
                # wrong one, so the shape is inferred from the value rather than configured.
                $gateways = @(
                    foreach ($value in @($row.Gateways -split ';' | Where-Object { $_ })) {
                        @{ type = $(if ($value -like '*-*') { 'RANGE' } else { 'CIDR' }); value = $value }
                    }
                )

                $body = [ordered]@{
                    type     = $row.Type
                    name     = $name
                    status   = 'ACTIVE'
                    usage    = $row.Usage
                    gateways = $gateways
                }

                $zone = Invoke-OktaTestRequest -Method POST -Path '/api/v1/zones' -Body $body
                $result.CreatedZones++
                Write-Verbose "Created network zone $name"
            }

            $zones.Add([PSCustomObject]@{
                Id    = $zone.id
                Key   = $row.Name
                Name  = $name
                Usage = $row.Usage
            })
        }
        catch {
            $message = "Failed to create network zone '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Zones = $zones.ToArray()

    if ($PassThru) { return $result }
}
