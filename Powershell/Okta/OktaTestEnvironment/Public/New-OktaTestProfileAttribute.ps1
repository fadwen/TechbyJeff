function New-OktaTestProfileAttribute {
    <#
    .SYNOPSIS
        Adds the module's custom attributes to the Okta user schemas

    .DESCRIPTION
        Okta's base user profile is fixed. Anything beyond it lives in the custom section of a
        user type's schema, and it has to exist before a user can be created carrying it, so
        this runs early in the seed order and late in the teardown order.

        The attributes are chosen for type coverage rather than realism. A lab whose profile is
        nothing but strings will not tell you that your export flattens an array to
        "System.Object[]", that your CSV writer turns a boolean into "True" where the API wanted
        true, or that a risk score of zero is falsy in PowerShell and gets dropped by an
        `if ($value)` guard. Each of those has a corresponding attribute here.

        Attributes are grouped by user type, because each type has its OWN schema at its own
        path. Two of them - labAgencyName and labPurchaseOrder - exist only on the Contractor
        type, which means an export that reads the default schema genuinely cannot see them.
        That is the point of the second type existing.

        One attribute, labSeedTag, is infrastructure rather than test data: it is what
        Remove-OktaTestEnvironment uses to be certain a user was created by this module and not
        by you.

        The schema API replaces the properties it is given and leaves the rest alone, so this is
        safe to re-run. -Remove sets each property to null, which is how Okta deletes a custom
        attribute; there is no DELETE for these.

    .PARAMETER Attribute
        Restrict the operation to these attribute names. Defaults to everything in
        Data\OktaProfileAttributes.csv.

    .PARAMETER Remove
        Set the attributes to null, deleting them from the schema. Any user still carrying a
        value loses it, so this must run after the users are gone.

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with Applied, Removed, Skipped and Errors

    .EXAMPLE
        New-OktaTestProfileAttribute
        Adds every attribute defined in the CSV, to whichever schema each belongs to

    .EXAMPLE
        New-OktaTestProfileAttribute -Attribute labRiskScore, labEntitlements -PassThru
        Adds only the two attributes whose types tend to break exports

    .EXAMPLE
        New-OktaTestProfileAttribute -Remove -WhatIf
        Shows which attributes teardown would delete from the schemas

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2026-08-07

        Editing the default user type's schema affects every user in the tenant, including your
        own admin account. On a shared tenant, prefer a dedicated user type.

        Attributes on a non-default type need that type to exist, so run New-OktaTestUserType
        first, or let New-OktaTestEnvironment order it for you.

    .LINK
        New-OktaTestUserType
        New-OktaTestUser
        Remove-OktaTestEnvironment
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$Attribute,

        [Parameter()]
        [switch]$Remove,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    $definitionPath = Join-Path -Path (Get-OktaTestDataPath) -ChildPath 'OktaProfileAttributes.csv'
    $definitions = @(Import-Csv -Path $definitionPath -Encoding UTF8)

    if ($Attribute) {
        $definitions = @($definitions | Where-Object { $Attribute -contains $_.Name })
        $unknown = @($Attribute | Where-Object { $definitions.Name -notcontains $_ })
        if ($unknown) {
            throw "No definition in $definitionPath for: $($unknown -join ', ')"
        }
    }

    $result = [PSCustomObject]@{
        Applied = @()
        Removed = @()
        Skipped = @()
        Errors  = @()
    }

    # A user type's schema is INDEPENDENT, not an extension of the default one. So an attribute
    # with no UserType has to be written to every type's schema, not just the default - a
    # contractor whose type only carried the contractor-specific attributes would be rejected
    # for every shared attribute the seed tries to set on it, including labSeedTag, which
    # teardown depends on.
    #
    # Attributes naming a type go to that type alone. That is what makes them invisible to a
    # default-schema export, which is the point of having them.
    $shared = @($definitions | Where-Object {
        -not $_.PSObject.Properties['UserType'] -or -not $_.UserType
    })
    $namedTypes = @($definitions | Where-Object {
        $_.PSObject.Properties['UserType'] -and $_.UserType
    } | ForEach-Object { $_.UserType } | Sort-Object -Unique)

    # Every type defined by the module gets the shared set even if it has no attributes of its
    # own, so the list comes from the user type data rather than from what happens to be tagged.
    $typeKeys = @('')
    $typeFile = Join-Path (Get-OktaTestDataPath) 'OktaUserTypes.csv'
    if (Test-Path -Path $typeFile) {
        $typeKeys += @((Import-Csv -Path $typeFile -Encoding UTF8).Name)
    }
    $typeKeys = @($typeKeys + $namedTypes | Sort-Object -Unique)

    $byUserType = [ordered]@{}
    foreach ($typeKey in $typeKeys) {
        $forThisType = @($shared)
        if ($typeKey) {
            $forThisType += @($definitions | Where-Object {
                $_.PSObject.Properties['UserType'] -and $_.UserType -eq $typeKey
            })
        }
        if ($forThisType.Count -gt 0) { $byUserType[$typeKey] = $forThisType }
    }

    foreach ($userTypeKey in @($byUserType.Keys)) {
        $schemaPath = $null
        try {
            $schemaPath = Get-OktaTestSchemaPath -UserTypeKey $userTypeKey -Prefix $connection.Prefix
        }
        catch {
            # A missing type is only fatal when adding. During teardown it means the type has
            # already gone, which is the desired end state anyway.
            if ($Remove) {
                Write-Verbose "Skipping schema for '$userTypeKey': $($_.Exception.Message)"
                continue
            }
            $result.Errors += $_.Exception.Message
            Write-Error $_.Exception.Message
            continue
        }

        $properties = [ordered]@{}

        foreach ($definition in $byUserType[$userTypeKey]) {
            if ($Remove) {
                $properties[$definition.Name] = $null
                continue
            }

            $property = [ordered]@{
                title       = $definition.Title
                description = $definition.Description
                type        = $definition.Type
                required    = [bool]::Parse($definition.Required)
                scope       = if ($definition.Scope) { $definition.Scope } else { 'NONE' }
                master      = @{ type = if ($definition.Master) { $definition.Master } else { 'PROFILE_MASTER' } }
                permissions = @(@{
                    principal = 'SELF'
                    action    = if ($definition.SelfPermission) { $definition.SelfPermission } else { 'READ_ONLY' }
                })
            }

            # Only send the constraints that were actually specified. Sending minLength on a
            # boolean, or a null maxLength on a string, is a 400 rather than a no-op.
            if ($definition.MinLength) { $property.minLength = [int]$definition.MinLength }
            if ($definition.MaxLength) { $property.maxLength = [int]$definition.MaxLength }

            if ($definition.EnumValues) {
                $values = @($definition.EnumValues -split ';' | Where-Object { $_ })
                $property.enum = $values
                # oneOf is what puts readable labels on the values in the admin console. Okta
                # requires it to agree with enum exactly, so it is generated from the same list
                # rather than maintained beside it.
                $property.oneOf = @($values | ForEach-Object { @{ const = $_; title = $_ } })
            }

            if ($definition.Type -eq 'array') {
                $itemType = if ($definition.ItemType) { $definition.ItemType } else { 'string' }
                $property.items = @{ type = $itemType }
                $property.union = 'DISABLE'
            }

            $properties[$definition.Name] = $property
        }

        if ($properties.Count -eq 0) { continue }

        $typeLabel = if ($userTypeKey) { "$userTypeKey user schema" } else { 'default user schema' }
        $action = if ($Remove) { 'Remove custom profile attributes' } else { 'Add custom profile attributes' }
        $target = "$typeLabel ($($properties.Keys -join ', '))"

        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            $result.Skipped += @($properties.Keys)
            continue
        }

        $body = @{
            definitions = @{
                custom = @{
                    id         = '#custom'
                    type       = 'object'
                    properties = $properties
                    required   = @()
                }
            }
        }

        try {
            # Retried on the "deletion process is incomplete" 400. Okta reserves an attribute
            # name for some seconds after it is deleted, so a teardown immediately followed by
            # a re-seed - the module's normal workflow - hits this every time.
            $null = Invoke-OktaTestPendingCleanupRequest -Method POST -Path $schemaPath -Body $body

            if ($Remove) {
                $result.Removed += @($properties.Keys)
                Write-Verbose "Removed $($properties.Count) attributes from $schemaPath"
            }
            else {
                $result.Applied += @($properties.Keys)
                Write-Verbose "Applied $($properties.Count) attributes to $schemaPath"
            }
        }
        catch {
            $message = "Schema update failed for $typeLabel : $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    if ($PassThru) { return $result }
}
