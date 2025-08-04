function New-ADTestEnvironment {
    <#
    .SYNOPSIS
        Creates a complete Active Directory test environment with OUs, users, devices, and groups

    .DESCRIPTION
        This function orchestrates the creation of a comprehensive AD test environment by:
        1. Creating the OU structure
        2. Creating user accounts from CSV data
        3. Creating device objects from CSV data  
        4. Creating security groups and assigning memberships
        
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

    .EXAMPLE
        New-ADTestEnvironment
        Creates the complete test environment

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
        Version: 1.0.0
        Last Updated: 2025-08-02
        
        REQUIREMENTS:
        - Active Directory PowerShell module
        - Domain administrator privileges
        - CSV data files in Data folder
        

    .LINK
        New-ADTestOUStructure
        New-ADTestUsers
        New-ADTestDevices
        New-ADTestServiceAccounts
        New-ADTestSecurityGroups
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [ValidateSet('OUStructure', 'Users', 'Devices', 'ServiceAccounts', 'Groups')]
        [string[]]$Skip = @(),
        [switch]$ShowProgress,
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestEnvironment - CorrelationId: $correlationId"
        
        # Test prerequisites
        if (-not (Test-ADTestPrerequisites -CheckDataFiles)) {
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
                        $userResults = New-ADTestUsers
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
                        $deviceResults = New-ADTestDevices
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
                        $serviceAccountResults = New-ADTestServiceAccounts
                        $results.Operations.ServiceAccounts.Success = $true
                        $results.Operations.ServiceAccounts.Results = $serviceAccountResults
                        $results.Summary.SuccessfulOperations++
                        
                        if ($ShowProgress) {
                            Write-Verbose "Processed $($serviceAccountResults.TotalServiceAccounts) service accounts"
                            Write-Verbose "Created $($serviceAccountResults.CreatedServiceAccounts) new service accounts"
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
