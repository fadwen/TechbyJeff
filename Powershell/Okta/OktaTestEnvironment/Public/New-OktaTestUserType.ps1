function New-OktaTestUserType {
    <#
    .SYNOPSIS
        Creates the second Okta user type and extends its schema

    .DESCRIPTION
        Every Okta org has a default user type, and almost every script written against Okta
        assumes it is the only one. A second type is the cheapest way to prove otherwise,
        because users on it have a DIFFERENT schema: an export that reads
        /api/v1/meta/schemas/user/default sees none of their custom attributes, and a report
        that groups by profile shape silently splits in two.

        Two attributes exist only on the Contractor type - labAgencyName and labPurchaseOrder -
        so a default-schema export genuinely cannot see them. That is the whole point of the
        type existing.

        Do not confuse this with the profile.userType STRING attribute, which the seeded users
        also carry. They are unrelated: the string is free text on the profile, this is a real
        object with its own schema and its own id. Okta named them almost identically, which is
        a trap worth knowing about before you write a report that mixes them up.

        A user type costs no licence. The users on it still do.

    .PARAMETER TypeName
        Restrict the operation to these CSV type names

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalTypes, CreatedTypes, ExistingTypes, Types and Errors

    .EXAMPLE
        New-OktaTestUserType -PassThru

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        Runs before New-OktaTestProfileAttribute and New-OktaTestUser, because a type has to
        exist before its schema can be extended or a user assigned to it.

    .LINK
        New-OktaTestProfileAttribute
        New-OktaTestUser
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$TypeName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $rows = @(Import-Csv -Path (Join-Path (Get-OktaTestDataPath) 'OktaUserTypes.csv') -Encoding UTF8)
    if ($TypeName) {
        $rows = @($rows | Where-Object { $TypeName -contains $_.Name })
        $unknown = @($TypeName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No user type definition for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalTypes    = $rows.Count
        CreatedTypes  = 0
        ExistingTypes = 0
        Types         = @()
        Errors        = @()
    }

    $existingTypes = @(Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/types/user')
    $types = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        # The API name must be a bare identifier, so the prefix is carried in the display name
        # and description instead. Teardown matches on the name having the prefix in it.
        $typeName = '{0}{1}' -f $connection.Prefix.ToLowerInvariant(), $row.Name
        $displayName = '{0}-{1}' -f $connection.Prefix, $row.DisplayName

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create Okta user type')) { continue }

        try {
            $existing = @($existingTypes | Where-Object { $_.name -eq $typeName })

            if ($existing.Count -gt 0) {
                $type = $existing[0]
                $result.ExistingTypes++
                Write-Verbose "Reusing user type $typeName"
            }
            else {
                # Retried, because Okta's deletion of a user type is asynchronous and a create
                # inside that window fails with a bare "request body was not well-formed" that
                # names nothing. The identical body succeeds seconds later.
                # 240 seconds, not the helper's default. Measured against a live tenant: an
                # attribute name frees up in seconds, but a user type name stayed reserved for
                # over 90, so the shorter default gives up while the create is still going to
                # start working. A seed run that waits three minutes beats one that fails.
                $type = Invoke-OktaTestPendingCleanupRequest -Method POST -MaxWaitSeconds 240 `
                    -Path '/api/v1/meta/types/user' -Body @{
                        name        = $typeName
                        displayName = $displayName
                        description = $row.Description
                    }
                $result.CreatedTypes++
                Write-Verbose "Created user type $typeName"
            }

            # Each type has its own schema, reachable only through the link on the type object.
            # There is no predictable path to build by hand, which is why this is captured here
            # and passed to New-OktaTestProfileAttribute rather than reconstructed later.
            $schemaPath = $null
            if ($type._links -and $type._links.schema -and $type._links.schema.href) {
                $schemaPath = ([uri]$type._links.schema.href).AbsolutePath
            }

            $types.Add([PSCustomObject]@{
                Id          = $type.id
                Key         = $row.Name
                Name        = $typeName
                DisplayName = $displayName
                SchemaPath  = $schemaPath
            })
        }
        catch {
            $message = "Failed to create user type '$typeName': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Types = $types.ToArray()

    if ($PassThru) { return $result }
}
