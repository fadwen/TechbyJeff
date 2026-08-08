function New-OktaTestLinkedObject {
    <#
    .SYNOPSIS
        Creates the linked object definition and links seeded users with it

    .DESCRIPTION
        Linked objects are Okta's real relationship primitive: a named, directional, queryable
        association between two users. The seeded users also carry a `manager` profile string,
        and the difference between the two is the whole reason this exists.

        The profile string is just text. Nothing validates it, nothing indexes it, and nothing
        stops it naming somebody who left two years ago. A linked object is a genuine reference
        that Okta maintains on both sides, and it disappears when either user does.

        A reporting script that reads `manager` and calls it the org chart is wrong in a way
        that only shows up when the two disagree. This module deliberately makes them disagree:
        the mentoring links do not mirror the management chain, so a script that conflates them
        produces a visibly different answer than one that does not.

        The definition is org-wide and the links are per user. Removing the definition removes
        every link made with it, which is why teardown deletes it after the users are gone.

    .PARAMETER SkipLinks
        Create the definition but do not link any users

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with Definitions, LinksCreated and Errors

    .EXAMPLE
        New-OktaTestLinkedObject -PassThru

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Links are made between seeded users, so run New-OktaTestUser first.

    .LINK
        New-OktaTestUser
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$SkipLinks,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaLinkedObjects.csv') -Encoding UTF8)

    $result = [PSCustomObject]@{
        Definitions  = @()
        LinksCreated = 0
        Errors       = @()
    }

    $userIdByLogin = @{}
    if (-not $SkipLinks) {
        $seeded = @(Get-OktaTestSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)
        foreach ($user in $seeded) { $userIdByLogin[$user.profile.login] = $user.id }
    }

    $existing = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/schemas/user/linkedObjects')
    $definitions = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        if (-not $PSCmdlet.ShouldProcess($row.PrimaryName, 'Create Okta linked object definition')) { continue }

        try {
            $alreadyThere = @($existing | Where-Object { $_.primary.name -eq $row.PrimaryName })

            if ($alreadyThere.Count -eq 0) {
                $null = Invoke-OktaTestRequest -Method POST `
                    -Path '/api/v1/meta/schemas/user/linkedObjects' -Body @{
                        primary = @{
                            name        = $row.PrimaryName
                            title       = $row.PrimaryTitle
                            description = $row.PrimaryDescription
                            type        = 'USER'
                        }
                        associated = @{
                            name        = $row.AssociatedName
                            title       = $row.AssociatedTitle
                            description = $row.AssociatedDescription
                            type        = 'USER'
                        }
                    }
                Write-Verbose "Created linked object definition $($row.PrimaryName)"
            }
            else {
                Write-Verbose "Reusing linked object definition $($row.PrimaryName)"
            }

            $linked = @()

            if (-not $SkipLinks) {
                foreach ($pair in @($row.Links -split ';' | Where-Object { $_ })) {
                    $parts = $pair -split '>'
                    if ($parts.Count -ne 2) {
                        $result.Errors += "Malformed link '$pair'; expected primary>associated."
                        continue
                    }

                    $primaryLogin = '{0}@{1}' -f $parts[0].Trim(), $connection.EmailDomain
                    $associatedLogin = '{0}@{1}' -f $parts[1].Trim(), $connection.EmailDomain

                    if (-not $userIdByLogin.ContainsKey($primaryLogin) -or
                        -not $userIdByLogin.ContainsKey($associatedLogin)) {
                        $message = "Link '$pair' names a user that does not exist. Skipped."
                        $result.Errors += $message
                        Write-Warning $message
                        continue
                    }

                    # The call is made on the ASSOCIATED user and names the PRIMARY relationship,
                    # which reads backwards until you see it: you are setting "this user's
                    # mentor is X", not "X mentors this user". Getting it the wrong way round
                    # produces a link that exists and points the wrong way.
                    $null = Invoke-OktaTestRequest -Method PUT -Path (
                        "/api/v1/users/$($userIdByLogin[$associatedLogin])/linkedObjects/" +
                        "$($row.PrimaryName)/$($userIdByLogin[$primaryLogin])")

                    $linked += "$primaryLogin -> $associatedLogin"
                    $result.LinksCreated++
                }
            }

            $definitions.Add([PSCustomObject]@{
                Primary    = $row.PrimaryName
                Associated = $row.AssociatedName
                Links      = $linked
            })
        }
        catch {
            $message = "Failed to create linked object '$($row.PrimaryName)': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Definitions = $definitions.ToArray()

    if ($PassThru) { return $result }
}
