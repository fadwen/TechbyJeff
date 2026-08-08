function New-OktaTestUser {
    <#
    .SYNOPSIS
        Creates the seeded Okta users from Data\OktaUsers.csv

    .DESCRIPTION
        Creates eight users, which is not an arbitrary number: an Okta trial org
        licenses ten active users and your own admin account is one of them, so eight is what
        fits with a slot left over for a colleague or a second admin.

        Because there are only eight, each one has to earn its place. They differ from each
        other along the axes that actually break scripts:

        - Three carry non-ASCII names (José Niño, Zoë Müller, Tomás Álvarez) while their
          logins stay ASCII, which is what a real directory looks like. Windows PowerShell
          writes CSV as ASCII unless told otherwise and silently replaces those characters
          with question marks, so without them that data loss is invisible.
        - Three lifecycle states: active, suspended and staged. A staged user has never signed
          in and has no established credentials, but it still counts against the tenant's
          active user licence and it is still evaluated by group rules. Both of those were
          verified against a real tenant, and both are the opposite of what people assume.
        - Two contractors with an end date, and six permanent staff without one, so empty
          optional attributes are represented rather than assumed away.
        - A manager chain three deep, so a script that resolves managers has something to
          resolve.

        The function is re-runnable. An existing login is updated rather than duplicated,
        which matters when a seed run fails partway and you want to fix the cause and run it
        again rather than tear down first.

    .PARAMETER UserCount
        How many users to create, taken from the top of the CSV. Lower it if the tenant is
        already holding users you want to keep.

    .PARAMETER AccountPassword
        Password for the seeded accounts, as a SecureString. Defaults to a known, shared, weak
        value. That is deliberate: these are lab accounts and being able to sign in as one is
        usually the point. Pass your own to override it.

        A password is always set, even on the staged user, because creating an Okta user
        without credentials makes Okta send a real activation email to the address on the
        profile.

    .PARAMETER SkipLifecycleStates
        Create every user active, ignoring the Suspended and Staged states in the CSV. Useful
        when you want eight uniformly usable accounts and not the awkward ones.

    .PARAMETER PassThru
        Return the detailed result object

    .OUTPUTS
        PSCustomObject with TotalUsers, CreatedUsers, UpdatedUsers, Users and Errors

    .EXAMPLE
        New-OktaTestUser
        Creates all eight users in their CSV-defined lifecycle states

    .EXAMPLE
        New-OktaTestUser -UserCount 4 -SkipLifecycleStates -PassThru
        Creates four uniformly active users, leaving six licence slots free

    .EXAMPLE
        $password = Read-Host 'Lab password' -AsSecureString
        New-OktaTestUser -AccountPassword $password

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07

        The custom attributes these users carry must exist first. Run
        New-OktaTestProfileAttribute, or let New-OktaTestEnvironment order it for you.

    .LINK
        New-OktaTestProfileAttribute
        New-OktaTestGroup
        Remove-OktaTestEnvironment
    #>

    # The justification has to be one string constant: PSScriptAnalyzer rejects a concatenation
    # in a suppression attribute, and the error it gives says nothing about which one.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Deliberately weak shared lab password; -AccountPassword overrides it.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$UserCount = 8,

        [Parameter()]
        [System.Security.SecureString]$AccountPassword,

        [Parameter()]
        [switch]$SkipLifecycleStates,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-OktaTestConnection

    if (-not $AccountPassword) {
        $AccountPassword = ConvertTo-SecureString -String 'Okta-Lab-Passw0rd!2026' -AsPlainText -Force
    }
    $plainPassword = ConvertFrom-OktaTestSecureString -SecureString $AccountPassword

    $csvPath = Join-Path -Path (Get-OktaTestDataPath) -ChildPath 'OktaUsers.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8 | Select-Object -First $UserCount)

    $result = [PSCustomObject]@{
        TotalUsers   = $rows.Count
        CreatedUsers = 0
        UpdatedUsers = 0
        Users        = @()
        Errors       = @()
    }

    # Manager is a display name and managerId a login, so the whole file has to be in hand
    # before the first user is built, not just the first $UserCount rows.
    $allRows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    $displayNameByLogin = @{}
    foreach ($row in $allRows) { $displayNameByLogin[$row.LoginPrefix] = $row.DisplayName }

    # Resolved once. A user's type can only be set at creation, so a row naming a type that
    # does not exist is worth failing loudly on rather than silently creating a default user.
    $userTypeIdByKey = @{}
    if (@($rows | Where-Object { $_.PSObject.Properties['OktaUserType'] -and $_.OktaUserType })) {
        foreach ($type in (Invoke-OktaTestRequest -Method GET -Path '/api/v1/meta/types/user')) {
            $userTypeIdByKey[$type.name] = $type.id
        }
    }

    $created = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $login = '{0}@{1}' -f $row.LoginPrefix, $connection.EmailDomain

        $userProfile = [ordered]@{
            login             = $login
            email             = $login
            firstName         = $row.FirstName
            lastName          = $row.LastName
            displayName       = $row.DisplayName
            nickName          = $row.NickName
            title             = $row.Title
            userType          = $row.UserType
            department        = $row.Department
            division          = $row.Division
            organization      = $row.Organization
            costCenter        = $row.CostCenter
            employeeNumber    = $row.EmployeeNumber
            mobilePhone       = $row.MobilePhone
            primaryPhone      = $row.PrimaryPhone
            streetAddress     = $row.StreetAddress
            city              = $row.City
            state             = $row.State
            zipCode           = $row.ZipCode
            countryCode       = $row.CountryCode
            preferredLanguage = $row.PreferredLanguage
            locale            = $row.Locale
            timezone          = $row.Timezone

            labSeedTag        = $connection.Prefix
            labBadgeId        = $row.LabBadgeId
            labClearanceLevel = $row.LabClearanceLevel
            labIsContractor   = [bool]::Parse($row.LabIsContractor)
            labCostCenterOwner = $row.LabCostCenterOwner
        }

        if ($row.MiddleName)      { $userProfile.middleName = $row.MiddleName }
        if ($row.HonorificPrefix) { $userProfile.honorificPrefix = $row.HonorificPrefix }

        if ($row.ManagerLoginPrefix) {
            $userProfile.managerId = '{0}@{1}' -f $row.ManagerLoginPrefix, $connection.EmailDomain
            $userProfile.manager   = $displayNameByLogin[$row.ManagerLoginPrefix]
        }

        # Compared against empty string rather than tested for truth. A risk score of zero is
        # a legitimate value and falsy in PowerShell, and dropping it silently is exactly the
        # bug this attribute exists to expose.
        if ($row.LabRiskScore -ne '') { $userProfile.labRiskScore = [int]$row.LabRiskScore }
        if ($row.LabContractEndDate)  { $userProfile.labContractEndDate = $row.LabContractEndDate }

        $entitlements = @($row.LabEntitlements -split ';' | Where-Object { $_ })
        if ($entitlements.Count -gt 0) { $userProfile.labEntitlements = $entitlements }

        # Attributes that live only on the Contractor type's schema. Sending them to a default
        # user is a 400, so they follow the type rather than being set unconditionally.
        if ($row.PSObject.Properties['OktaUserType'] -and $row.OktaUserType) {
            if ($row.LabAgencyName)    { $userProfile.labAgencyName = $row.LabAgencyName }
            if ($row.LabPurchaseOrder) { $userProfile.labPurchaseOrder = $row.LabPurchaseOrder }
        }

        $lifecycle = if ($SkipLifecycleStates) { 'Active' } else { $row.LifecycleState }

        if (-not $PSCmdlet.ShouldProcess($login, "Create Okta user ($lifecycle)")) { continue }

        try {
            $existing = $null
            try {
                $existing = Invoke-OktaTestRequest -Method GET `
                    -Path "/api/v1/users/$([uri]::EscapeDataString($login))"
            }
            catch {
                Write-Verbose "No existing user for $login; it will be created."
            }

            if ($existing) {
                # A partial profile update. Okta merges rather than replaces here, which is
                # what makes a re-run after a half-finished seed safe.
                $user = Invoke-OktaTestRequest -Method POST -Path "/api/v1/users/$($existing.id)" `
                    -Body @{ profile = $userProfile }
                $result.UpdatedUsers++
                Write-Verbose "Updated $login"
            }
            else {
                $activate = ($lifecycle -ne 'Staged')
                $body = @{
                    profile     = $userProfile
                    credentials = @{ password = @{ value = $plainPassword } }
                }

                if ($row.PSObject.Properties['OktaUserType'] -and $row.OktaUserType) {
                    $typeName = '{0}{1}' -f $connection.Prefix.ToLowerInvariant(), $row.OktaUserType
                    if (-not $userTypeIdByKey.ContainsKey($typeName)) {
                        throw ("User type '$typeName' does not exist. Run New-OktaTestUserType " +
                            'before creating users that belong to it.')
                    }
                    $body.type = @{ id = $userTypeIdByKey[$typeName] }
                }

                $user = Invoke-OktaTestRequest -Method POST -Path '/api/v1/users' `
                    -Query @{ activate = $activate.ToString().ToLowerInvariant() } -Body $body
                $result.CreatedUsers++
                Write-Verbose "Created $login ($lifecycle)"
            }

            if ($lifecycle -eq 'Suspended' -and $user.status -ne 'SUSPENDED') {
                $null = Invoke-OktaTestRequest -Method POST `
                    -Path "/api/v1/users/$($user.id)/lifecycle/suspend"
                $user.status = 'SUSPENDED'
            }

            $created.Add([PSCustomObject]@{
                Id          = $user.id
                Login       = $login
                DisplayName = $row.DisplayName
                Status      = $user.status
                Groups      = @($row.Groups -split ';' | Where-Object { $_ })
            })
        }
        catch {
            $message = "Failed to create $login`: $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Users = $created.ToArray()

    Write-Verbose ("Users: $($result.CreatedUsers) created, $($result.UpdatedUsers) updated, " +
        "$($result.Errors.Count) failed")

    if ($PassThru) { return $result }
}
