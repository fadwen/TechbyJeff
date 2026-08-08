function New-OktaTestTrustedOrigin {
    <#
    .SYNOPSIS
        Creates the seeded trusted origins

    .DESCRIPTION
        A trusted origin is an allowlist entry: a URL Okta will accept cross-origin calls from
        (CORS), or redirect a browser back to after sign-in or sign-out (REDIRECT). They are
        cheap, they are security-relevant, and a fresh org has none - so any script that audits
        them has nothing to find until these exist.

        The two seeded entries differ in scope on purpose. One carries both CORS and REDIRECT,
        the other only CORS. A report that assumes every origin does both, or that flattens the
        scope list to a single value, gets the second one wrong.

        The origins are under example.com, which is IANA-reserved. That matters more here than
        elsewhere: a trusted origin naming a domain somebody else controls is an actual
        security finding, not just untidy test data.

    .PARAMETER OriginName
        Restrict the operation to these CSV origin names

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalOrigins, CreatedOrigins, ExistingOrigins, Origins and Errors

    .EXAMPLE
        New-OktaTestTrustedOrigin -PassThru

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

    .LINK
        New-OktaTestEventHook
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$OriginName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaTrustedOrigins.csv') -Encoding UTF8)
    if ($OriginName) {
        $rows = @($rows | Where-Object { $OriginName -contains $_.Name })
        $unknown = @($OriginName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No trusted origin definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalOrigins    = $rows.Count
        CreatedOrigins  = 0
        ExistingOrigins = 0
        Origins         = @()
        Errors          = @()
    }

    $existingOrigins = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/trustedOrigins' `
        -Query @{ limit = 200 } -Paginate)
    $origins = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $name = '{0}-{1}' -f $connection.Prefix, $row.Name

        if (-not $PSCmdlet.ShouldProcess($name, 'Create Okta trusted origin')) { continue }

        try {
            $existing = @($existingOrigins | Where-Object { $_.name -eq $name })

            if ($existing.Count -gt 0) {
                $origin = $existing[0]
                $result.ExistingOrigins++
                Write-Verbose "Reusing trusted origin $name"
            }
            else {
                $scopes = @(
                    foreach ($scope in @($row.Scopes -split ';' | Where-Object { $_ })) {
                        @{ type = $scope }
                    }
                )

                $origin = Invoke-OktaTestRequest -Method POST -Path '/api/v1/trustedOrigins' -Body @{
                    name   = $name
                    origin = $row.Origin
                    scopes = $scopes
                }
                $result.CreatedOrigins++
                Write-Verbose "Created trusted origin $name"
            }

            $origins.Add([PSCustomObject]@{
                Id     = $origin.id
                Key    = $row.Name
                Name   = $name
                Origin = $row.Origin
                Scopes = @($row.Scopes -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create trusted origin '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Origins = $origins.ToArray()

    if ($PassThru) { return $result }
}
