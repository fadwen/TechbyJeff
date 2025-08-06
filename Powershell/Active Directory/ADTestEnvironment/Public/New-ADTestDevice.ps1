function New-ADTestDevice {
    <#
    .SYNOPSIS
        Creates Active Directory test device objects from CSV data

    .DESCRIPTION
        Creates computer objects in Active Directory based on data from ADDevices.csv.
        Devices are placed in appropriate type OUs (Workstations, Servers, etc.).

    .PARAMETER PassThru
        Returns a PSCustomObject with creation results and statistics

    .PARAMETER BatchSize
        Number of devices to process in each batch. Default is 10.
        Larger batches improve performance but may consume more resources.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent batch operations. Default is 5.
        Adjust based on your domain controller's capacity.

    .PARAMETER WhatIf
        Shows what would be created without making changes

    .EXAMPLE
        New-ADTestDevice
        Creates all devices from ADDevices.csv using default batch size

    .EXAMPLE
        New-ADTestDevice -BatchSize 20 -ThrottleLimit 3
        Creates devices in batches of 20 with maximum 3 concurrent batches

    .EXAMPLE
        $results = New-ADTestDevice -PassThru -BatchSize 15
        Creates all devices in batches of 15 and returns results for further processing

    .OUTPUTS
        PSCustomObject (when -PassThru is specified)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-02
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$PassThru,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$BatchSize = 17,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$ThrottleLimit = 6
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestDevice - CorrelationId: $correlationId"

        # Get data paths
        $dataPath = Get-ADTestDataPath
        $devicesCSV = Join-Path $dataPath "ADDevices.csv"

        # Verify prerequisites
        if (-not (Test-Path $devicesCSV)) {
            throw "ADDevices.csv not found at: $devicesCSV"
        }

        # Get domain information
        $domain = Get-ADTestDomain

        # Counters
        $script:DevicesCreated = 0
        $script:DevicesSkipped = 0
        $script:Errors = @()
        $script:ProcessingJobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()

        Write-Verbose "Batch processing configuration: BatchSize=$BatchSize, ThrottleLimit=$ThrottleLimit"
    }

    process {
        try {
            Write-ADTestProgress -Message "Creating Active Directory Test Devices" -Type Header
            Write-ADTestProgress -Message "Loading device data from CSV..." -Type Info

            # Import device data
            $devices = Import-Csv $devicesCSV
            Write-Verbose "Loaded $($devices.Count) devices from CSV"

            $totalDevices = $devices.Count
            Write-ADTestProgress -Message "Processing $totalDevices devices in batches of $BatchSize..." -Type Info

            # Group devices into batches
            $deviceBatches = @()
            for ($i = 0; $i -lt $totalDevices; $i += $BatchSize) {
                $batchEnd = [Math]::Min($i + $BatchSize - 1, $totalDevices - 1)
                $deviceBatches += ,@($devices[$i..$batchEnd])
            }

            Write-Verbose "Created $($deviceBatches.Count) batches for processing"

            # Process batches with throttling
            $batchNumber = 0
            $completedBatches = 0

            foreach ($batch in $deviceBatches) {
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
                            $script:DevicesCreated += $result.Created
                            $script:DevicesSkipped += $result.Skipped
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
                        $percentComplete = ($completedBatches / $deviceBatches.Count) * 100
                        Write-Progress -Activity "Creating Device Batches" -Status "Completed $completedBatches of $($deviceBatches.Count) batches" -PercentComplete $percentComplete
                    }
                }

                # Start new batch job
                $jobName = "DeviceBatch_$batchNumber"
                Write-Verbose "Starting batch $batchNumber with $($batch.Count) devices"

                $job = Start-Job -Name $jobName -ScriptBlock {
                    param($DeviceBatch, $Domain, $WhatIfPreference, $VerbosePreference)

                    # Import required modules in job
                    Import-Module ActiveDirectory -Verbose:$false

                    $batchResults = @{
                        Created = 0
                        Skipped = 0
                        Errors = @()
                    }

                    foreach ($device in $DeviceBatch) {
                        try {
                            # Skip if device already exists
                            $existingDevice = Get-ADComputer -Filter "Name -eq '$($device.DeviceName)'" -ErrorAction SilentlyContinue
                            if ($existingDevice) {
                                Write-Verbose "Device $($device.DeviceName) already exists, skipping"
                                $batchResults.Skipped++
                                continue
                            }

                            # Determine OU path based on device type
                            $ouPath = switch ($device.DeviceType) {
                                'Workstation' { "OU=Workstations,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Database Server' { "OU=Servers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Domain Controller' { "OU=Servers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Exchange Server' { "OU=Servers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'File Server' { "OU=Servers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Server' { "OU=Servers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Mobile Device' { "OU=Mobile,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Mobile' { "OU=Mobile,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Printer' { "OU=Printers,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Laptop' { "OU=Workstations,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                'Tablet' { "OU=Mobile,OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                                default { "OU=Devices,OU=TestData,$($Domain.DomainDN)" }
                            }

                            # Verify OU exists
                            try {
                                Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                            }
                            catch {
                                $batchResults.Errors += "OU not found for $($device.DeviceName): $ouPath"
                                $batchResults.Skipped++
                                continue
                            }

                            # Prepare device parameters
                            $deviceParams = @{
                                Name = $device.DeviceName
                                SamAccountName = "$($device.DeviceName)$"
                                Path = $ouPath
                                Enabled = [bool]::Parse($device.Enabled)
                                Description = $device.Description
                            }

                            # Create computer object
                            if ($PSCmdlet.ShouldProcess($device.DeviceName, "Create AD Computer Object")) {
                                Write-Verbose "Creating device: $($device.DeviceName) in $ouPath"
                                New-ADComputer @deviceParams

                                # Set additional attributes
                                $additionalAttributes = @{}

                                if (-not [string]::IsNullOrWhiteSpace($device.OperatingSystem)) {
                                    $additionalAttributes['OperatingSystem'] = $device.OperatingSystem
                                }

                                if (-not [string]::IsNullOrWhiteSpace($device.Office)) {
                                    $additionalAttributes['Location'] = $device.Office
                                }

                                # Store additional info in Description field if needed
                                if (-not [string]::IsNullOrWhiteSpace($device.SerialNumber) -or
                                    -not [string]::IsNullOrWhiteSpace($device.AssetTag) -or
                                    -not [string]::IsNullOrWhiteSpace($device.Manufacturer) -or
                                    -not [string]::IsNullOrWhiteSpace($device.Model)) {

                                    $additionalInfo = @()
                                    if (-not [string]::IsNullOrWhiteSpace($device.SerialNumber)) {
                                        $additionalInfo += "SN:$($device.SerialNumber)"
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($device.AssetTag)) {
                                        $additionalInfo += "Asset:$($device.AssetTag)"
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($device.Manufacturer)) {
                                        $additionalInfo += "Make:$($device.Manufacturer)"
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($device.Model)) {
                                        $additionalInfo += "Model:$($device.Model)"
                                    }

                                    # Append to existing description
                                    $enhancedDescription = "$($device.Description) | $($additionalInfo -join ' | ')"
                                    $additionalAttributes['Description'] = $enhancedDescription
                                }

                                if (-not [string]::IsNullOrWhiteSpace($device.Department)) {
                                    $additionalAttributes['Department'] = $device.Department
                                }

                                # Apply additional attributes if any
                                if ($additionalAttributes.Count -gt 0) {
                                    Set-ADComputer -Identity $device.DeviceName -Replace $additionalAttributes
                                    Write-Verbose "Set additional attributes for $($device.DeviceName)"
                                }

                                # Set managed by user if specified
                                if (-not [string]::IsNullOrWhiteSpace($device.AssignedUser)) {
                                    try {
                                        # Escape single quotes in the name for AD filter
                                        $escapedAssignedUser = $device.AssignedUser -replace "'", "''"
                                        $assignedUser = Get-ADUser -Filter "Name -eq '$escapedAssignedUser'" -ErrorAction SilentlyContinue
                                        if ($assignedUser) {
                                            Set-ADComputer -Identity $device.DeviceName -ManagedBy $assignedUser.DistinguishedName
                                            Write-Verbose "Set managed by for $($device.DeviceName): $($device.AssignedUser)"
                                        }
                                        else {
                                            $batchResults.Errors += "Assigned user not found for $($device.DeviceName): $($device.AssignedUser)"
                                        }
                                    }
                                    catch {
                                        $batchResults.Errors += "Managed by error for $($device.DeviceName): $($_.Exception.Message)"
                                    }
                                }

                                $batchResults.Created++
                            }
                            else {
                                Write-Verbose "Would create device: $($device.DeviceName) in $ouPath"
                                $batchResults.Created++
                            }
                        }
                        catch {
                            $batchResults.Errors += "Device creation error for $($device.DeviceName): $($_.Exception.Message)"
                        }
                    }

                    return $batchResults
                } -ArgumentList $batch, $domain, $WhatIfPreference, $VerbosePreference

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
                        $script:DevicesCreated += $result.Created
                        $script:DevicesSkipped += $result.Skipped
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
                    $percentComplete = ($completedBatches / $deviceBatches.Count) * 100
                    Write-Progress -Activity "Creating Device Batches" -Status "Completed $completedBatches of $($deviceBatches.Count) batches" -PercentComplete $percentComplete
                }
            }

            Write-Progress -Activity "Creating Device Batches" -Status "Complete" -PercentComplete 100 -Completed

            # Retry transient errors
            $transientErrors = @()
            $permanentErrors = @()
            $retriedDevices = @()

            # Identify transient connection errors
            foreach ($error in $script:Errors) {
                if ($error -like "*transient condition*" -or
                    $error -like "*connection to the directory*was unavailable*" -or
                    $error -like "*server is not operational*" -or
                    $error -like "*RPC server is unavailable*") {

                    # Extract device name from error message
                    if ($error -match "Device creation error for ([^:]+):") {
                        $deviceName = $matches[1]
                        $transientErrors += @{
                            DeviceName = $deviceName
                            OriginalError = $error
                        }
                    }
                } else {
                    $permanentErrors += $error
                }
            }

            # Retry transient errors if any found
            if ($transientErrors.Count -gt 0) {
                Write-ADTestProgress -Message "Retrying $($transientErrors.Count) devices with transient connection errors..." -Type Info

                foreach ($transientError in $transientErrors) {
                    $deviceName = $transientError.DeviceName
                    $device = $devices | Where-Object { $_.DeviceName -eq $deviceName }

                    if ($device) {
                        Write-Verbose "Retrying device creation for: $deviceName"

                        try {
                            # Add small delay to help with transient issues
                            Start-Sleep -Milliseconds 500

                            # Skip if device now exists (might have been created during retry delay)
                            $existingDevice = Get-ADComputer -Filter "Name -eq '$deviceName'" -ErrorAction SilentlyContinue
                            if ($existingDevice) {
                                Write-Verbose "Device $deviceName now exists, removing from error list"
                                $retriedDevices += $deviceName
                                $script:DevicesCreated++
                                continue
                            }

                            # Determine OU path based on device type
                            $ouPath = switch ($device.DeviceType) {
                                'Workstation' { "OU=Workstations,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Database Server' { "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Domain Controller' { "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Exchange Server' { "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'File Server' { "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Server' { "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Mobile Device' { "OU=Mobile,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Mobile' { "OU=Mobile,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Printer' { "OU=Printers,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Laptop' { "OU=Workstations,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                'Tablet' { "OU=Mobile,OU=Devices,OU=TestData,$($domain.DomainDN)" }
                                default { "OU=Devices,OU=TestData,$($domain.DomainDN)" }
                            }

                            # Prepare device parameters
                            $deviceParams = @{
                                Name = $device.DeviceName
                                SamAccountName = "$($device.DeviceName)$"
                                Path = $ouPath
                                Enabled = [bool]::Parse($device.Enabled)
                                Description = $device.Description
                            }

                            # Retry device creation
                            if ($PSCmdlet.ShouldProcess($device.DeviceName, 'Retry Create AD Computer Object')) {
                                Write-Verbose "Retrying creation of device: $deviceName in $ouPath"
                                New-ADComputer @deviceParams -ErrorAction Stop

                                # Set additional attributes if needed
                                $additionalAttributes = @{}

                                if (-not [string]::IsNullOrWhiteSpace($device.OperatingSystem)) {
                                    $additionalAttributes['OperatingSystem'] = $device.OperatingSystem
                                }

                                if (-not [string]::IsNullOrWhiteSpace($device.Office)) {
                                    $additionalAttributes['Location'] = $device.Office
                                }

                                if (-not [string]::IsNullOrWhiteSpace($device.Department)) {
                                    $additionalAttributes['Department'] = $device.Department
                                }

                                # Apply additional attributes if any
                                if ($additionalAttributes.Count -gt 0) {
                                    Set-ADComputer -Identity $device.DeviceName -Replace $additionalAttributes -ErrorAction SilentlyContinue
                                }

                                # Set managed by user if specified
                                if (-not [string]::IsNullOrWhiteSpace($device.AssignedUser)) {
                                    try {
                                        $escapedAssignedUser = $device.AssignedUser -replace "'", "''"
                                        $assignedUser = Get-ADUser -Filter "Name -eq '$escapedAssignedUser'" -ErrorAction SilentlyContinue
                                        if ($assignedUser) {
                                            Set-ADComputer -Identity $device.DeviceName -ManagedBy $assignedUser.DistinguishedName -ErrorAction SilentlyContinue
                                        }
                                    }
                                    catch {
                                        # Ignore managed by errors on retry
                                    }
                                }

                                $retriedDevices += $deviceName
                                $script:DevicesCreated++
                                Write-Verbose "Successfully retried device creation for: $deviceName"
                            }
                            else {
                                Write-Verbose "Would retry creating device: $deviceName in $ouPath"
                                $retriedDevices += $deviceName
                                $script:DevicesCreated++
                            }
                        }
                        catch {
                            Write-Verbose "Retry failed for device $deviceName : $($_.Exception.Message)"
                            # Keep original error but mark as retry failed
                            $permanentErrors += "Retry failed for $deviceName : $($_.Exception.Message) (Original: $($transientError.OriginalError))"
                        }
                    }
                }

                # Update error list - remove successfully retried devices
                $script:Errors = $permanentErrors

                if ($retriedDevices.Count -gt 0) {
                    Write-ADTestProgress -Message "Successfully retried $($retriedDevices.Count) devices with transient errors" -Type Success
                }
            }

            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalDevices = $totalDevices
                CreatedDevices = $script:DevicesCreated
                SkippedDevices = $script:DevicesSkipped
                BatchesProcessed = $deviceBatches.Count
                BatchSize = $BatchSize
                ThrottleLimit = $ThrottleLimit
                Errors = $script:Errors
            }

            # Display summary
            Write-ADTestProgress -Message "Device Creation Summary (Batch Mode)" -Type Success
            Write-Host "  Total Batches: $($results.BatchesProcessed)" -ForegroundColor Cyan
            Write-Host "  Batch Size: $($results.BatchSize)" -ForegroundColor Cyan
            Write-Host "  Devices Created: $($results.CreatedDevices)" -ForegroundColor Green
            Write-Host "  Devices Skipped: $($results.SkippedDevices)" -ForegroundColor Yellow

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
                Write-Verbose "Cleaning up $($script:ProcessingJobs.Count) background jobs due to error"
                foreach ($job in $script:ProcessingJobs) {
                    Stop-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -ErrorAction SilentlyContinue
                }
                $script:ProcessingJobs.Clear()
            }
            Write-Error "Failed to create devices: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        # Cleanup any remaining background jobs
        if ($script:ProcessingJobs.Count -gt 0) {
            Write-Verbose "Cleaning up $($script:ProcessingJobs.Count) remaining background jobs"
            foreach ($job in $script:ProcessingJobs) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -ErrorAction SilentlyContinue
            }
            $script:ProcessingJobs.Clear()
        }

        Write-Verbose "Completed New-ADTestDevice - CorrelationId: $correlationId"
    }
}
