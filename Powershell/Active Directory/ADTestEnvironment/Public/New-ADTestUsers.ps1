function New-ADTestUsers {
    <#
    .SYNOPSIS
        Creates Active Directory test user accounts from CSV data
    .DESCRIPTION
        Creates user accounts in Active Directory based on data from ADUsers.csv.
        Users are placed in appropriate department OUs and configured with
        photos, manager relationships, and other attributes.

    .PARAMETER WhatIf
        Shows what would be created without making changes

    .PARAMETER IncludePhotos
        Include user photos from Data/UserImages folder

    .PARAMETER BatchSize
        Number of users to process in each batch. Default is 15.
        Larger batches improve performance but may consume more resources.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent batch operations. Default is 4.
        Adjust based on your domain controller's capacity.

    .PARAMETER PassThru
        Returns a PSCustomObject with creation results and statistics

    .EXAMPLE
        New-ADTestUsers
        Creates all users from ADUsers.csv

    .EXAMPLE
        New-ADTestUsers -BatchSize 20 -ThrottleLimit 3
        Creates users in batches of 20 with maximum 3 concurrent batches

    .EXAMPLE
        New-ADTestUsers -WhatIf
        Shows what users would be created

    .EXAMPLE
        $results = New-ADTestUsers -PassThru -BatchSize 10
        Creates users in batches of 10 and returns results object

    .OUTPUTS
        PSCustomObject with creation results and statistics (when -PassThru is used)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-02
        
        REQUIREMENTS:
        - OU structure must exist (run New-ADTestOUStructure first)
        - ADUsers.csv must be present in Data folder
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [switch]$IncludePhotos,
        
        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$BatchSize = 15,
        
        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$ThrottleLimit = 4,
        
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestUsers - CorrelationId: $correlationId"
        
        # Get data paths
        $dataPath = Get-ADTestDataPath
        $usersCSV = Join-Path $dataPath "ADUsers.csv"
        $userImagesPath = Join-Path $dataPath "UserImages"
        
        # Verify prerequisites
        if (-not (Test-Path $usersCSV)) {
            throw "ADUsers.csv not found at: $usersCSV"
        }
        
        # Get domain information
        $domain = Get-ADTestDomain
        
        # Counters
        $script:UsersCreated = 0
        $script:UsersSkipped = 0
        $script:PhotosAdded = 0
        $script:ManagersSet = 0
        $script:Errors = @()
        $script:ProcessingJobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()
        
        Write-Verbose "Batch processing configuration: BatchSize=$BatchSize, ThrottleLimit=$ThrottleLimit"
    }

    process {
        try {
            Write-ADTestProgress -Message "Creating Active Directory Test Users" -Type Header
            Write-ADTestProgress -Message "Loading user data from CSV..." -Type Info
            
            # Import user data
            $users = Import-Csv $usersCSV
            Write-Verbose "Loaded $($users.Count) users from CSV"
            
            # Sort users to create managers before their reports (simplified approach)
            $sortedUsers = $users | Sort-Object {
                if ([string]::IsNullOrWhiteSpace($_.Manager)) { 0 } else { 1 }
            }
            
            $totalUsers = $sortedUsers.Count
            Write-ADTestProgress -Message "Processing $totalUsers users in batches of $BatchSize..." -Type Info
            
            # Group users into batches
            $userBatches = @()
            for ($i = 0; $i -lt $totalUsers; $i += $BatchSize) {
                $batchEnd = [Math]::Min($i + $BatchSize - 1, $totalUsers - 1)
                $userBatches += ,@($sortedUsers[$i..$batchEnd])
            }
            
            Write-Verbose "Created $($userBatches.Count) batches for processing"
            
            # Process batches with throttling
            $batchNumber = 0
            $completedBatches = 0
            
            foreach ($batch in $userBatches) {
                $batchNumber++
                
                # Wait for available slot if at throttle limit
                while ($script:ProcessingJobs.Count -ge $ThrottleLimit) {
                    Start-Sleep -Milliseconds 500
                    
                    # Check for completed jobs
                    $completedJobs = $script:ProcessingJobs | Where-Object { $_.State -eq 'Completed' }
                    if ($completedJobs) {
                        foreach ($job in $completedJobs) {
                            $result = Receive-Job -Job $job
                            Remove-Job -Job $job
                            
                            # Aggregate results
                            $script:UsersCreated += $result.Created
                            $script:UsersSkipped += $result.Skipped
                            $script:PhotosAdded += $result.PhotosAdded
                            $script:Errors += $result.Errors
                            
                            $completedBatches++
                        }
                        
                        # Remove completed jobs from tracking
                        $remainingJobs = $script:ProcessingJobs | Where-Object { $_.State -ne 'Completed' }
                        $script:ProcessingJobs.Clear()
                        foreach ($job in $remainingJobs) {
                            $script:ProcessingJobs.Add($job)
                        }
                        
                        # Update progress
                        $percentComplete = ($completedBatches / $userBatches.Count) * 80  # Reserve 20% for manager relationships
                        Write-Progress -Activity "Creating User Batches" -Status "Completed $completedBatches of $($userBatches.Count) batches" -PercentComplete $percentComplete
                    }
                }
                
                # Start new batch job
                $jobName = "UserBatch_$batchNumber"
                Write-Verbose "Starting batch $batchNumber with $($batch.Count) users"
                
                $job = Start-Job -Name $jobName -ScriptBlock {
                    param($UserBatch, $Domain, $IncludePhotos, $UserImagesPath, $WhatIfPreference, $VerbosePreference)
                    
                    # Import required modules in job
                    Import-Module ActiveDirectory -Verbose:$false
                    
                    $batchResults = @{
                        Created = 0
                        Skipped = 0
                        PhotosAdded = 0
                        Errors = @()
                    }
                    
                    foreach ($user in $UserBatch) {
                        try {
                            # Skip if user already exists
                            $existingUser = Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue
                            if ($existingUser) {
                                Write-Verbose "User $($user.SamAccountName) already exists, skipping"
                                $batchResults.Skipped++
                                continue
                            }
                            
                            # Determine OU path
                            $ouPath = "OU=$($user.Department),OU=Users,OU=TestData,$($Domain.DomainDN)"
                            
                            # Verify OU exists
                            try {
                                Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                            }
                            catch {
                                Write-Verbose "OU not found: $ouPath. Using default Users container."
                                $ouPath = "CN=Users,$($Domain.DomainDN)"
                            }
                            
                            # Generate domain-dependent fields dynamically
                            $dynamicEmail = if ([string]::IsNullOrWhiteSpace($user.mail)) {
                                "$($user.SamAccountName)@$($Domain.DNSName)"
                            } else {
                                "$($user.mail)@$($Domain.DNSName)"
                            }
                            
                            $dynamicUPN = if ([string]::IsNullOrWhiteSpace($user.UserPrincipalName)) {
                                $dynamicEmail
                            } else {
                                "$($user.UserPrincipalName)@$($Domain.DNSName)"
                            }
                            
                            # Prepare user parameters
                            $userParams = @{
                                Name = $user.Name
                                SamAccountName = $user.SamAccountName
                                UserPrincipalName = $dynamicUPN
                                GivenName = $user.GivenName
                                Surname = $user.Surname
                                DisplayName = $user.Name
                                EmailAddress = $dynamicEmail
                                Title = $user.Title
                                Department = $user.Department
                                OfficePhone = $user.OfficePhone
                                MobilePhone = $user.MobilePhone
                                Office = $user.Office
                                StreetAddress = $user.StreetAddress
                                City = $user.City
                                State = $user.State
                                PostalCode = $user.PostalCode
                                Description = $user.Description
                                EmployeeID = $user.EmployeeID
                                OtherAttributes = @{EmployeeType = $user.EmployeeType}
                                Path = $ouPath
                                Enabled = [bool]::Parse($user.Enabled)
                                PasswordNeverExpires = $true
                                CannotChangePassword = $false
                                AccountPassword = (ConvertTo-SecureString -String "Password123!" -AsPlainText -Force)
                            }
                            
                            # Create user
                            if (-not $WhatIfPreference) {
                                Write-Verbose "Creating user: $($user.Name) in $ouPath"
                                New-ADUser @userParams
                                $batchResults.Created++
                                
                                # Add photo if requested and available
                                if ($IncludePhotos) {
                                    $photoPath = Join-Path $UserImagesPath "$($user.Name).jpg"
                                    if (Test-Path $photoPath) {
                                        try {
                                            $photo = [System.IO.File]::ReadAllBytes($photoPath)
                                            Set-ADUser -Identity $user.SamAccountName -Replace @{thumbnailPhoto = $photo}
                                            Write-Verbose "Added photo for $($user.Name)"
                                            $batchResults.PhotosAdded++
                                        }
                                        catch {
                                            $batchResults.Errors += "Photo error for $($user.Name): $($_.Exception.Message)"
                                        }
                                    }
                                }
                            }
                            else {
                                Write-Verbose "Would create user: $($user.Name) in $ouPath"
                                $batchResults.Created++
                            }
                        }
                        catch {
                            $batchResults.Errors += "User creation error for $($user.Name): $($_.Exception.Message)"
                        }
                    }
                    
                    return $batchResults
                } -ArgumentList $batch, $domain, $IncludePhotos, $userImagesPath, $WhatIfPreference, $VerbosePreference
                
                $script:ProcessingJobs.Add($job)
            }
            
            # Wait for all remaining jobs to complete
            Write-Verbose "Waiting for all batch jobs to complete..."
            while ($script:ProcessingJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 500
                
                $completedJobs = $script:ProcessingJobs | Where-Object { $_.State -eq 'Completed' }
                if ($completedJobs) {
                    foreach ($job in $completedJobs) {
                        $result = Receive-Job -Job $job
                        Remove-Job -Job $job
                        
                        # Aggregate results
                        $script:UsersCreated += $result.Created
                        $script:UsersSkipped += $result.Skipped
                        $script:PhotosAdded += $result.PhotosAdded
                        $script:Errors += $result.Errors
                        
                        $completedBatches++
                    }
                    
                    # Remove completed jobs from tracking
                    $remainingJobs = $script:ProcessingJobs | Where-Object { $_.State -ne 'Completed' }
                    $script:ProcessingJobs.Clear()
                    foreach ($job in $remainingJobs) {
                        $script:ProcessingJobs.Add($job)
                    }
                    
                    # Update progress
                    $percentComplete = ($completedBatches / $userBatches.Count) * 80
                    Write-Progress -Activity "Creating User Batches" -Status "Completed $completedBatches of $($userBatches.Count) batches" -PercentComplete $percentComplete
                }
            }
            
            # Second pass: Set manager relationships using batch processing
            if (-not $WhatIfPreference) {
                Write-ADTestProgress -Message "Setting manager relationships..." -Type Info
                Write-Progress -Activity "Creating Users" -Status "Setting manager relationships" -PercentComplete 85
                
                # Filter users that need manager assignments
                $usersWithManagers = $sortedUsers | Where-Object { 
                    -not [string]::IsNullOrWhiteSpace($_.Manager) -and $_.Manager -ne "CN=" 
                }
                
                if ($usersWithManagers.Count -gt 0) {
                    Write-Verbose "Processing manager assignments for $($usersWithManagers.Count) users"
                    
                    # Group manager assignments into batches
                    $managerBatches = @()
                    $managerBatchSize = [Math]::Min($BatchSize, 20)  # Smaller batches for manager operations
                    
                    for ($i = 0; $i -lt $usersWithManagers.Count; $i += $managerBatchSize) {
                        $batchEnd = [Math]::Min($i + $managerBatchSize - 1, $usersWithManagers.Count - 1)
                        $managerBatches += ,@($usersWithManagers[$i..$batchEnd])
                    }
                    
                    Write-Verbose "Created $($managerBatches.Count) manager assignment batches of size $managerBatchSize"
                    
                    # Process manager batches with throttling
                    $script:ManagerJobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()
                    $managerBatchNumber = 0
                    $completedManagerBatches = 0
                    
                    foreach ($batch in $managerBatches) {
                        $managerBatchNumber++
                        
                        # Wait for available slot if at throttle limit
                        while ($script:ManagerJobs.Count -ge $ThrottleLimit) {
                            Start-Sleep -Milliseconds 300
                            
                            # Check for completed jobs
                            $completedJobs = $script:ManagerJobs | Where-Object { $_.State -eq 'Completed' }
                            if ($completedJobs) {
                                foreach ($job in $completedJobs) {
                                    $result = Receive-Job -Job $job
                                    Remove-Job -Job $job
                                    
                                    # Aggregate results
                                    $script:ManagersSet += $result.ManagersSet
                                    $script:Errors += $result.Errors
                                    
                                    $completedManagerBatches++
                                }
                                
                                # Remove completed jobs from tracking
                                $remainingJobs = $script:ManagerJobs | Where-Object { $_.State -ne 'Completed' }
                                $script:ManagerJobs.Clear()
                                foreach ($job in $remainingJobs) {
                                    $script:ManagerJobs.Add($job)
                                }
                                
                                # Update progress
                                $percentComplete = 85 + (($completedManagerBatches / $managerBatches.Count) * 10)
                                Write-Progress -Activity "Creating Users" -Status "Manager assignments: $completedManagerBatches of $($managerBatches.Count) batches" -PercentComplete $percentComplete
                            }
                        }
                        
                        # Start new manager batch job
                        $jobName = "ManagerBatch_$managerBatchNumber"
                        Write-Verbose "Starting manager batch $managerBatchNumber with $($batch.Count) assignments"
                        
                        $job = Start-Job -Name $jobName -ScriptBlock {
                            param($UserBatch, $VerbosePreference)
                            
                            # Import required modules in job
                            Import-Module ActiveDirectory -Verbose:$false
                            
                            $batchResults = @{
                                ManagersSet = 0
                                Errors = @()
                            }
                            
                            foreach ($user in $UserBatch) {
                                try {
                                    # Extract manager name from CN format
                                    $managerName = $user.Manager -replace "^CN=", ""
                                    # Escape single quotes in the name for AD filter
                                    $escapedManagerName = $managerName -replace "'", "''"
                                    $managerUser = Get-ADUser -Filter "Name -eq '$escapedManagerName'" -ErrorAction SilentlyContinue
                                    
                                    if ($managerUser) {
                                        Set-ADUser -Identity $user.SamAccountName -Manager $managerUser.DistinguishedName
                                        Write-Verbose "Set manager for $($user.Name): $managerName"
                                        $batchResults.ManagersSet++
                                    }
                                    else {
                                        $batchResults.Errors += "Manager not found for $($user.Name): $managerName"
                                    }
                                }
                                catch {
                                    $batchResults.Errors += "Manager assignment error for $($user.Name): $($_.Exception.Message)"
                                }
                            }
                            
                            return $batchResults
                        } -ArgumentList $batch, $VerbosePreference
                        
                        $script:ManagerJobs.Add($job)
                    }
                    
                    # Wait for all manager assignment jobs to complete
                    Write-Verbose "Waiting for all manager assignment jobs to complete..."
                    while ($script:ManagerJobs.Count -gt 0) {
                        Start-Sleep -Milliseconds 300
                        
                        $completedJobs = $script:ManagerJobs | Where-Object { $_.State -eq 'Completed' }
                        if ($completedJobs) {
                            foreach ($job in $completedJobs) {
                                $result = Receive-Job -Job $job
                                Remove-Job -Job $job
                                
                                # Aggregate results
                                $script:ManagersSet += $result.ManagersSet
                                $script:Errors += $result.Errors
                                
                                $completedManagerBatches++
                            }
                            
                            # Remove completed jobs from tracking
                            $remainingJobs = $script:ManagerJobs | Where-Object { $_.State -ne 'Completed' }
                            $script:ManagerJobs.Clear()
                            foreach ($job in $remainingJobs) {
                                $script:ManagerJobs.Add($job)
                            }
                            
                            # Update progress
                            $percentComplete = 85 + (($completedManagerBatches / $managerBatches.Count) * 10)
                            Write-Progress -Activity "Creating Users" -Status "Manager assignments: $completedManagerBatches of $($managerBatches.Count) batches" -PercentComplete $percentComplete
                        }
                    }
                    
                    Write-Verbose "Manager assignment processing completed"
                } else {
                    Write-Verbose "No users require manager assignments"
                }
            }
            
            Write-Progress -Activity "Creating Users" -Status "Complete" -PercentComplete 100 -Completed
            
            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalUsers = $totalUsers
                CreatedUsers = $script:UsersCreated
                SkippedUsers = $script:UsersSkipped
                BatchesProcessed = $userBatches.Count
                BatchSize = $BatchSize
                ThrottleLimit = $ThrottleLimit
                PhotosAdded = if ($IncludePhotos) { $script:PhotosAdded } else { 0 }
                ManagersSet = $script:ManagersSet
                Errors = $script:Errors
            }
            
            # Display summary
            Write-ADTestProgress -Message "User Creation Summary (Batch Mode)" -Type Success
            Write-Host "  User Creation Batches: $($results.BatchesProcessed)" -ForegroundColor Cyan
            Write-Host "  Batch Size: $($results.BatchSize)" -ForegroundColor Cyan
            Write-Host "  Users Created: $($results.CreatedUsers)" -ForegroundColor Green
            Write-Host "  Users Skipped: $($results.SkippedUsers)" -ForegroundColor Yellow
            if ($IncludePhotos) {
                Write-Host "  Photos Added: $($results.PhotosAdded)" -ForegroundColor Green
            }
            Write-Host "  Managers Set: $($results.ManagersSet)" -ForegroundColor Green
            
            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            
            if ($PassThru) {
                return [PSCustomObject]$results
            }
            
        } catch {
            # Cleanup any remaining jobs on error
            if ($script:ProcessingJobs.Count -gt 0) {
                Write-Verbose "Cleaning up $($script:ProcessingJobs.Count) user creation background jobs due to error"
                foreach ($job in $script:ProcessingJobs) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
                $script:ProcessingJobs.Clear()
            }
            
            # Cleanup manager assignment jobs if they exist
            if (Get-Variable -Name 'script:ManagerJobs' -ErrorAction SilentlyContinue -and $script:ManagerJobs.Count -gt 0) {
                Write-Verbose "Cleaning up $($script:ManagerJobs.Count) manager assignment background jobs due to error"
                foreach ($job in $script:ManagerJobs) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
                $script:ManagerJobs.Clear()
            }
            
            Write-Error "Failed to create users: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestUsers - CorrelationId: $correlationId"
    }
}
