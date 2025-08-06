function New-ADTestEnvironment {
    <#
    .SYNOPSIS
        Creates a complete Active Directory test environment with OUs, users, devices, and groups

    .DESCRIPTION
        This function orchestrates the creation of a comprehensive AD test environment by:
        1. Creating the OU structure
        2. Creating user accounts from CSV data
        3. Creating device objects from CSV data
        4. Creating service accounts from CSV data (with optional SecretStore password storage)
        5. Creating security groups and assigning memberships

        This is the main entry point for setting up the entire test environment.

    .PARAMETER Skip
        Specify which components to skip during creation. Valid values:
        - OUStructure: Skip creating the OU structure (useful if it already exists)
        - Users: Skip creating user accounts
        - Devices: Skip creating device objects
        - ServiceAccounts: Skip creating service accounts
        - Groups: Skip creating security groups

    .PARAMETER WhatIf
        Shows what would be created without making changes

    .PARAMETER ShowProgress
        Display detailed progress information during execution

    .PARAMETER PassThru
        Return the detailed results object. By default, only summary information is displayed.

    .PARAMETER UseSecretStore
        Use PowerShell SecretManagement/SecretStore modules to store service account passwords
        in a secure vault instead of exporting to a plain text file. Will install required modules if not present.

    .PARAMETER VaultName
        Name of the secret vault to use when UseSecretStore is specified. Defaults to "ADTestEnvironment"

    .PARAMETER VaultPassword
        Password for the secret vault when UseSecretStore is specified. If not provided,
        will use "ADTestEnvironmentPassword" as the default to avoid prompting.

    .PARAMETER GlobalVault
        Create SecretStore vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges. Only applies when UseSecretStore is specified.

    .EXAMPLE
        New-ADTestEnvironment
        Creates the complete test environment

    .EXAMPLE
        New-ADTestEnvironment -UseSecretStore
        Creates the complete test environment with service account passwords stored in SecretStore vault

    .EXAMPLE
        New-ADTestEnvironment -UseSecretStore -VaultName "ProdVault" -VaultPassword (ConvertTo-SecureString "VaultPass123!" -AsPlainText -Force)
        Creates the environment with passwords stored in a custom named vault

    .EXAMPLE
        New-ADTestEnvironment -UseSecretStore -GlobalVault
        Creates the environment with service account passwords in a global vault (requires admin privileges)

    .EXAMPLE
        New-ADTestEnvironment -WhatIf
        Shows what would be created without making changes

    .EXAMPLE
        New-ADTestEnvironment -Skip Devices,Groups
        Creates only OUs, users, and service accounts

    .EXAMPLE
        New-ADTestEnvironment -Skip ServiceAccounts
        Creates OUs, users, devices, and groups but skips service accounts

    .EXAMPLE
        New-ADTestEnvironment -Skip OUStructure,Users,Devices,ServiceAccounts,Groups -WhatIf
        Shows what would happen if all components were skipped (essentially a no-op)

    .OUTPUTS
        Hashtable containing summary of operations performed

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2025-08-05

        REQUIREMENTS:
        - Active Directory PowerShell module
        - Domain administrator privileges
        - CSV data files in Data folder

        SECRETSTORE FEATURES:
        - Use -UseSecretStore to store service account passwords in an encrypted vault
        - Automatically installs required SecretManagement/SecretStore modules if not present
        - Creates computer-level vault for shared access (when run as administrator)
        - Retrieve passwords later using Get-ADTestPasswordFromVault function


    .LINK
        New-ADTestOUStructure
        New-ADTestUser
        New-ADTestDevice
        New-ADTestServiceAccount
        New-ADTestSecurityGroups
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [ValidateSet('OUStructure', 'Users', 'Devices', 'ServiceAccounts', 'Groups')]
        [string[]]$Skip = @(),

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestEnvironment - CorrelationId: $correlationId"

        # Test prerequisites
        if (-not (Test-ADTestPrerequisite -CheckDataFiles)) {
            throw "Prerequisites not met for AD test environment creation"
        }
    }

    process {
        try {
            Write-ADTestProgress -Message "Active Directory Test Environment Creation" -Type Header

            $results = @{
                CorrelationId = $correlationId
                StartTime = Get-Date
                Operations = @{
                    OUStructure = @{ Attempted = $false; Success = $false; Results = $null }
                    Users = @{ Attempted = $false; Success = $false; Results = $null }
                    Devices = @{ Attempted = $false; Success = $false; Results = $null }
                    ServiceAccounts = @{ Attempted = $false; Success = $false; Results = $null }
                    Groups = @{ Attempted = $false; Success = $false; Results = $null }
                }
                Summary = @{
                    TotalOperations = 0
                    SuccessfulOperations = 0
                    FailedOperations = 0
                }
            }

            # Step 1: Create OU Structure
            Write-Verbose "Skip contains: $($Skip -join ', ')"
            if ('OUStructure' -notin $Skip) {
                Write-ADTestProgress -Message "Step 1: Creating OU Structure" -Type Info
                $results.Operations.OUStructure.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("OU Structure", "Create AD Test OU Structure")) {
                        $ouResults = New-ADTestOUStructure
                        $results.Operations.OUStructure.Success = $true
                        $results.Operations.OUStructure.Results = $ouResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Created $($ouResults.Created.Count) OUs"
                            if ($ouResults.Errors.Count -gt 0) {
                                Write-Verbose "$($ouResults.Errors.Count) errors encountered"
                            }
                        }
                    }
                } catch {
                    $results.Operations.OUStructure.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "OU Structure creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-ADTestProgress -Message "Step 1: Skipping OU Structure (as requested)" -Type Warning
            }

            # Step 2: Create Users
            if ('Users' -notin $Skip) {
                Write-ADTestProgress -Message "Step 2: Creating User Accounts" -Type Info
                $results.Operations.Users.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("User Accounts", "Create AD Test Users")) {
                        $userResults = New-ADTestUser
                        $results.Operations.Users.Success = $true
                        $results.Operations.Users.Results = $userResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($userResults.TotalUsers) users"
                            Write-Verbose "Created $($userResults.CreatedUsers) new users"
                        }
                    }
                } catch {
                    $results.Operations.Users.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "User creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-ADTestProgress -Message "Step 2: Skipping User Accounts (as requested)" -Type Warning
            }

            # Step 3: Create Devices
            if ('Devices' -notin $Skip) {
                Write-ADTestProgress -Message "Step 3: Creating Device Objects" -Type Info
                $results.Operations.Devices.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Device Objects", "Create AD Test Devices")) {
                        $deviceResults = New-ADTestDevice
                        $results.Operations.Devices.Success = $true
                        $results.Operations.Devices.Results = $deviceResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($deviceResults.TotalDevices) devices"
                            Write-Verbose "Created $($deviceResults.CreatedDevices) new devices"
                        }
                    }
                } catch {
                    $results.Operations.Devices.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Device creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-ADTestProgress -Message "Step 3: Skipping Device Objects (as requested)" -Type Warning
            }

            # Step 4: Create Service Accounts
            if ('ServiceAccounts' -notin $Skip) {
                Write-ADTestProgress -Message "Step 4: Creating Service Accounts" -Type Info
                $results.Operations.ServiceAccounts.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Service Accounts", "Create AD Test Service Accounts")) {
                        # Create service accounts (simplified - no SecretStore orchestration)
                        $serviceAccountResults = New-ADTestServiceAccount -PassThru
                        $results.Operations.ServiceAccounts.Success = $true
                        $results.Operations.ServiceAccounts.Results = $serviceAccountResults
                        $results.Summary.SuccessfulOperations++

                        # Handle SecretStore orchestration separately if requested
                        if ($UseSecretStore -and $serviceAccountResults.PasswordData.Count -gt 0) {
                            try {
                                $orchestrationParams = @{
                                    PasswordData = $serviceAccountResults.PasswordData
                                    VaultName = $VaultName
                                    GlobalVault = $GlobalVault
                                    CorrelationId = $correlationId
                                }

                                if ($VaultPassword) {
                                    $orchestrationParams.VaultPassword = $VaultPassword
                                }

                                $secretStoreResult = Invoke-ADTestSecretStoreOrchestration @orchestrationParams

                                # Add SecretStore results to service account results
                                $serviceAccountResults | Add-Member -NotePropertyName "SecretStoreResult" -NotePropertyValue $secretStoreResult -Force
                                $serviceAccountResults | Add-Member -NotePropertyName "UseSecretStore" -NotePropertyValue $true -Force
                                $serviceAccountResults | Add-Member -NotePropertyName "VaultName" -NotePropertyValue $VaultName -Force

                                if ($secretStoreResult.Errors.Count -gt 0) {
                                    Write-Warning "SecretStore orchestration completed with errors: $($secretStoreResult.Errors -join '; ')"
                                    # Fall back to file export
                                    $passwordFile = Export-PasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix "ServiceAccountPW"
                                    Write-Warning "Passwords exported to file as fallback: $passwordFile"
                                    $serviceAccountResults | Add-Member -NotePropertyName "PasswordFile" -NotePropertyValue $passwordFile -Force
                                }
                            }
                            catch {
                                Write-Warning "SecretStore orchestration failed: $($_.Exception.Message)"
                                # Fall back to file export
                                $passwordFile = Export-PasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix "ServiceAccountPW"
                                Write-Warning "Passwords exported to file as fallback: $passwordFile"
                                $serviceAccountResults | Add-Member -NotePropertyName "PasswordFile" -NotePropertyValue $passwordFile -Force
                            }
                        }
                        elseif ($serviceAccountResults.PasswordData.Count -gt 0) {
                            # Export to file when not using SecretStore
                            $passwordFile = Export-PasswordDocumentation -PasswordData $serviceAccountResults.PasswordData -FilePrefix "ServiceAccountPW"
                            $serviceAccountResults | Add-Member -NotePropertyName "PasswordFile" -NotePropertyValue $passwordFile -Force
                        }

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($serviceAccountResults.TotalAccounts) service accounts"
                            Write-Verbose "Created $($serviceAccountResults.CreatedAccounts) new service accounts"

                            if ($UseSecretStore -and $serviceAccountResults.SecretStoreResult) {
                                Write-Verbose "Stored $($serviceAccountResults.SecretStoreResult.TotalStored) passwords in vault: $VaultName"
                            }
                            elseif ($serviceAccountResults.PasswordFile) {
                                Write-Verbose "Password file created: $($serviceAccountResults.PasswordFile)"
                            }
                        }
                    }
                } catch {
                    $results.Operations.ServiceAccounts.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Service account creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-ADTestProgress -Message "Step 4: Skipping Service Accounts (as requested)" -Type Warning
            }

            # Step 5: Create Security Groups
            if ('Groups' -notin $Skip) {
                Write-ADTestProgress -Message "Step 5: Creating Security Groups" -Type Info
                $results.Operations.Groups.Attempted = $true
                $results.Summary.TotalOperations++

                try {
                    if ($PSCmdlet.ShouldProcess("Security Groups", "Create AD Test Security Groups")) {
                        $groupResults = New-ADTestSecurityGroups
                        $results.Operations.Groups.Success = $true
                        $results.Operations.Groups.Results = $groupResults
                        $results.Summary.SuccessfulOperations++

                        if ($ShowProgress) {
                            Write-Verbose "Processed $($groupResults.TotalGroups) groups"
                            Write-Verbose "Created $($groupResults.CreatedGroups) new groups"
                            Write-Verbose "Added $($groupResults.MembersAdded) group members"
                        }
                    }
                } catch {
                    $results.Operations.Groups.Results = $_.Exception.Message
                    $results.Summary.FailedOperations++
                    Write-Error "Security group creation failed: $($_.Exception.Message)"
                }
            } else {
                Write-ADTestProgress -Message "Step 5: Skipping Security Groups (as requested)" -Type Warning
            }

            # Final Summary
            $results.EndTime = Get-Date
            $results.Duration = $results.EndTime - $results.StartTime

            Write-ADTestProgress -Message "Environment Creation Summary" -Type Header
            Write-Host "Operations Completed: $($results.Summary.SuccessfulOperations)/$($results.Summary.TotalOperations)" -ForegroundColor Green
            Write-Host "Duration: $($results.Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

            if ($results.Summary.FailedOperations -gt 0) {
                Write-Warning "Failed Operations: $($results.Summary.FailedOperations)"
                Write-Warning "Check the results object for detailed error information."
            }

            Write-ADTestProgress -Message "Test environment creation complete!" -Type Success

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            Write-Error "Failed to create test environment: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestEnvironment - CorrelationId: $correlationId"
    }
}
