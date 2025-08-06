function New-ADTestSecurityGroups {
    <#
    .SYNOPSIS
        Creates Active Directory test security groups from CSV data

    .DESCRIPTION
        Creates security groups in Active Directory based on data from ADSecurityGroups.csv
        and automatically assigns users and devices as members based on criteria.

    .PARAMETER SkipMemberAssignment
        Creates groups but skips automatic member assignment

    .PARAMETER BatchSize
        Number of group member assignments to process in each batch

    .PARAMETER ThrottleLimit
        Maximum number of concurrent background jobs for member assignment

    .PARAMETER PassThru
        Returns a PSCustomObject with creation results and statistics


    .EXAMPLE
        New-ADTestSecurityGroups
        Creates all groups from ADSecurityGroups.csv with automatic membership

    .EXAMPLE
        New-ADTestSecurityGroups -BatchSize 15 -ThrottleLimit 8
        Creates groups with larger batches and more concurrent jobs for faster processing

    .EXAMPLE
        $results = New-ADTestSecurityGroups -PassThru
        Creates all groups and returns results for further processing

    .EXAMPLE
        New-ADTestSecurityGroups -SkipMemberAssignment
        Creates groups only without automatic member assignment for faster processings

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
        [switch]$SkipMemberAssignment,

        [ValidateRange(1, 50)]
        [int]$BatchSize = 15,

        [ValidateRange(1, 20)]
        [int]$ThrottleLimit = 5,

        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestSecurityGroups - CorrelationId: $correlationId"

        # Get data paths
        $dataPath = Get-ADTestDataPath
        $groupsCSV = Join-Path $dataPath "ADSecurityGroups.csv"

        # Verify prerequisites
        if (-not (Test-Path $groupsCSV)) {
            throw "ADSecurityGroups.csv not found at: $groupsCSV"
        }

        # Get domain information
        $domain = Get-ADTestDomain

        # Counters
        $script:GroupsCreated = 0
        $script:GroupsSkipped = 0
        $script:MembersAdded = 0
        $script:Errors = @()

        # Job tracking for batch processing
        $script:MembershipJobs = [System.Collections.Generic.List[object]]::new()
        $script:JobResults = [System.Collections.Generic.List[object]]::new()
    }

    process {
        try {
            Write-ADTestProgress -Message "Creating Active Directory Test Security Groups" -Type Header
            Write-ADTestProgress -Message "Loading security group data from CSV..." -Type Info

            # Import group data
            $groups = Import-Csv $groupsCSV
            Write-Verbose "Loaded $($groups.Count) groups from CSV"

            $totalGroups = $groups.Count
            $currentGroup = 0

            Write-ADTestProgress -Message "Processing $totalGroups security groups..." -Type Info

            foreach ($group in $groups) {
                $currentGroup++
                $percentComplete = ($currentGroup / $totalGroups) * 80  # Reserve 20% for member assignment

                Write-Progress -Activity "Creating Security Groups" -Status "Processing $($group.GroupName)" -PercentComplete $percentComplete

                try {
                    # Skip if group already exists
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$($group.GroupName)'" -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Write-Verbose "Group $($group.GroupName) already exists, skipping"
                        $script:GroupsSkipped++
                        continue
                    }

                    # Determine OU path based on category
                    $ouPath = switch ($group.Category) {
                        'Administrative' { "OU=Administrative,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Access Control' { "OU=Resource,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Departmental' { "OU=Department,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Device Access' { "OU=Device,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Application Access' { "OU=Resource,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Employment Type' { "OU=Role,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Geographic' { "OU=Location,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Management Level' { "OU=Role,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Organizational' { "OU=Role,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Physical Access' { "OU=Resource,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        'Resource Access' { "OU=Resource,OU=Groups,OU=TestData,$($domain.DomainDN)" }
                        default { "OU=Groups,OU=TestData,$($domain.DomainDN)" }
                    }

                    # Verify OU exists, skip group creation if not found
                    try {
                        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Warning "OU not found: $ouPath. Skipping group creation for $($group.GroupName). Please ensure OU structure is created first."
                        $script:GroupsSkipped++
                        continue
                    }                    # Map group scope
                    $groupScope = switch ($group.GroupScope) {
                        'DomainLocal' { 'DomainLocal' }
                        'Global' { 'Global' }
                        'Universal' { 'Universal' }
                        default { 'Global' }
                    }

                    # Prepare group parameters
                    $groupParams = @{
                        Name = $group.GroupName
                        SamAccountName = $group.GroupName
                        GroupCategory = 'Security'
                        GroupScope = $groupScope
                        Path = $ouPath
                        Description = $group.Description
                    }

                    # Create security group
                    if ($PSCmdlet.ShouldProcess($group.GroupName, "Create AD Security Group")) {
                        Write-Verbose "Creating security group: $($group.GroupName) in $ouPath"
                        New-ADGroup @groupParams
                        $script:GroupsCreated++
                    }
                    else {
                        Write-Host "Would create security group: $($group.GroupName) in $ouPath" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Error "Failed to create group $($group.GroupName): $($_.Exception.Message)"
                    $script:Errors += "Group creation error for $($group.GroupName): $($_.Exception.Message)"
                }
            }

            # Second pass: Assign members based on criteria using batch processing
            if (-not $SkipMemberAssignment -and -not $WhatIfPreference) {
                Write-ADTestProgress -Message "Preparing group membership assignments..." -Type Info
                Write-Progress -Activity "Creating Security Groups" -Status "Preparing member assignments" -PercentComplete 85

                # Collect groups that need member assignment
                $groupsForMembership = $groups | Where-Object { [bool]::Parse($_.AutoAssignment) -eq $true }
                $totalMembershipGroups = $groupsForMembership.Count

                if ($totalMembershipGroups -gt 0) {
                    Write-ADTestProgress -Message "Processing membership for $totalMembershipGroups groups..." -Type Info

                    # Process groups in batches
                    $batchCount = [Math]::Ceiling($totalMembershipGroups / $BatchSize)

                    for ($batchIndex = 0; $batchIndex -lt $batchCount; $batchIndex++) {
                        $startIndex = $batchIndex * $BatchSize
                        $endIndex = [Math]::Min(($startIndex + $BatchSize - 1), ($totalMembershipGroups - 1))
                        $currentBatch = $groupsForMembership[$startIndex..$endIndex]

                        Write-Progress -Activity "Creating Security Groups" -Status "Processing membership batch $($batchIndex + 1) of $batchCount" -PercentComplete (85 + (($batchIndex / $batchCount) * 15))
                        Write-Verbose "Processing membership batch $($batchIndex + 1)/$batchCount with $($currentBatch.Count) groups"

                        # Wait for job slots to become available
                        while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
                            Start-Sleep -Milliseconds 100

                            # Collect completed jobs
                            $completedJobs = Get-Job -State Completed
                            foreach ($job in $completedJobs) {
                                try {
                                    $jobResult = Receive-Job $job
                                    $script:JobResults.Add($jobResult)
                                    Remove-Job $job
                                }
                                catch {
                                    Write-Warning "Error receiving job result: $($_.Exception.Message)"
                                    $script:Errors += "Job processing error: $($_.Exception.Message)"
                                    Remove-Job $job -Force
                                }
                            }
                        }

                        # Start job for current batch
                        $job = Start-Job -ScriptBlock {
                            param($GroupBatch, $DomainDN)

                            # Import Active Directory module in the job
                            Import-Module ActiveDirectory -ErrorAction SilentlyContinue -Verbose:$false

                            $results = @{
                                BatchIndex = $using:batchIndex
                                GroupsProcessed = 0
                                MembersAdded = 0
                                Errors = @()
                            }

                            foreach ($group in $GroupBatch) {
                                try {
                                    # Get the AD group
                                    $adGroup = Get-ADGroup -Filter "Name -eq '$($group.GroupName)'" -ErrorAction SilentlyContinue
                                    if (-not $adGroup) {
                                        $results.Errors += "Group not found: $($group.GroupName)"
                                        continue
                                    }

                                    # Collect members based on group name patterns
                                    $membersToAdd = @()

                                    switch -Regex ($group.GroupName) {
                                        # Employee groups based on employment type
                                        '^All Employees$' {
                                            $allUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $allUsers | Where-Object { $_.EmployeeType -in @('Full-time', 'Part-time') }
                                        }
                                        '^All Contractors$' {
                                            $contractorUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $contractorUsers | Where-Object { $_.EmployeeType -eq 'Contractor' }
                                        }
                                        '^All Interns$' {
                                            $internUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $internUsers | Where-Object { $_.EmployeeType -eq 'Intern' }
                                        }
                                        '^Full Time Employees$' {
                                            $fullTimeUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $fullTimeUsers | Where-Object { $_.EmployeeType -eq 'Full-time' }
                                        }
                                        '^Contract Workers$' {
                                            $contractUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $contractUsers | Where-Object { $_.EmployeeType -eq 'Contractor' }
                                        }
                                        '^Intern Employees$' {
                                            $internUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $internUsers | Where-Object { $_.EmployeeType -eq 'Intern' }
                                        }

                                        # Department-based groups
                                        '^(Executives|Executive.*)$' {
                                            $execUsers = Get-ADUser -Filter "Department -eq 'Executive'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $execUsers
                                        }
                                        '^(Operations|Operation.*)$' {
                                            $opsUsers = Get-ADUser -Filter "Department -eq 'Operations'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $opsUsers
                                        }
                                        '^(Engineering|Engineering.*)$' {
                                            $engUsers = Get-ADUser -Filter "Department -eq 'Engineering' -or Department -eq 'Engineering Operations'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $engUsers
                                        }
                                        '^(Sales|Sales.*)$' {
                                            $salesUsers = Get-ADUser -Filter "Department -eq 'Sales' -or Department -eq 'Sales Engagement Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $salesUsers
                                        }
                                        '^(Marketing|Marketing.*)$' {
                                            $marketingUsers = Get-ADUser -Filter "Department -eq 'Marketing'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $marketingUsers
                                        }
                                        '^(Accounting|Finance)$' {
                                            $financeUsers = Get-ADUser -Filter "Department -eq 'Accounting' -or Department -eq 'Finance'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $financeUsers
                                        }
                                        '^Human Resources$' {
                                            $hrUsers = Get-ADUser -Filter "Department -eq 'Human Resources'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $hrUsers
                                        }
                                        '^Project Management$' {
                                            $pmUsers = Get-ADUser -Filter "Department -eq 'Project Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $pmUsers
                                        }
                                        '^Strategy Consulting$' {
                                            $stratUsers = Get-ADUser -Filter "Department -eq 'Strategy Consulting'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $stratUsers
                                        }
                                        '^Content Management$' {
                                            $contentUsers = Get-ADUser -Filter "Department -eq 'Content Management Consulting'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $contentUsers
                                        }
                                        '^CRM Strategy$' {
                                            $crmUsers = Get-ADUser -Filter "Department -eq 'CRM Strategy'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $crmUsers
                                        }
                                        '^Senior Management$' {
                                            $seniorMgmt = Get-ADUser -Filter "Department -eq 'Senior Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $seniorMgmt
                                        }
                                        '^Creative$' {
                                            $creativeUsers = Get-ADUser -Filter "Department -eq 'Creative'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $creativeUsers
                                        }
                                        '^CVP of IT$' {
                                            $cvpITUsers = Get-ADUser -Filter "Department -eq 'CVP of IT'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $cvpITUsers
                                        }

                                        # Management level groups
                                        '^Directors$' {
                                            $directors = Get-ADUser -Filter "Title -like '*Director*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $directors
                                        }
                                        '^Managers$' {
                                            $managers = Get-ADUser -Filter "Title -like '*Manager*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $managers
                                        }
                                        '^VPs and Above$' {
                                            $vps = Get-ADUser -Filter "Title -like '*VP*' -or Title -like '*SVP*' -or Title -like '*CVP*' -or Title -like '*CEO*' -or Title -like '*COO*' -or Title -like '*CFO*' -or Title -like '*CTO*' -or Title -like '*President*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $vps
                                        }
                                        '^C-Level$' {
                                            $clevel = Get-ADUser -Filter "Title -like '*CEO*' -or Title -like '*COO*' -or Title -like '*CFO*' -or Title -like '*CTO*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $clevel
                                        }
                                        '^Sales Management$' {
                                            $salesMgmt = Get-ADUser -Filter "(Department -eq 'Sales' -or Department -eq 'Sales Engagement Management') -and (Title -like '*Manager*' -or Title -like '*Director*' -or Title -like '*VP*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $salesMgmt
                                        }
                                        '^Sales Engagement Management$' {
                                            $salesEngagement = Get-ADUser -Filter "Department -eq 'Sales Engagement Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $salesEngagement
                                        }

                                        # Location-based groups - handle all office patterns
                                        'Office$|^Seattle.*Office$' {
                                            if ($group.GroupName -eq 'Seattle Main Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Seattle - Main'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Seattle Engineering Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Seattle - Engineering'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Seattle Finance Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Seattle - Finance'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Atlanta Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Atlanta - Southeast'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Boston Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Boston - Northeast'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Chicago Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Chicago - Central'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Houston Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Houston - Sales'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'London Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'London - International'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Los Angeles Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Los Angeles - West'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'New York Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -like '*New York*'" -ErrorAction SilentlyContinue
                                            }
                                            elseif ($group.GroupName -eq 'Richmond Office') {
                                                $locationUsers = Get-ADUser -Filter "Office -eq 'Richmond - East'" -ErrorAction SilentlyContinue
                                            }
                                            else {
                                                $locationName = ($group.GroupName -replace ' Office$', '')
                                                $locationUsers = Get-ADUser -Filter "Office -like '*$locationName*'" -ErrorAction SilentlyContinue
                                            }
                                            $membersToAdd += $locationUsers
                                        }
                                        '^Remote Workers$' {
                                            $remoteUsers = Get-ADUser -Filter "Office -like '*Remote*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $remoteUsers
                                        }

                                        # Technology access groups
                                        '^VPN Users$' {
                                            $vpnUsers = Get-ADUser -Filter "Office -like '*Remote*' -or Department -eq 'Sales' -or Department -eq 'Sales Engagement Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $vpnUsers
                                        }
                                        '^WiFi Users$' {
                                            $wifiUsers = Get-ADUser -Filter "Enabled -eq 'True'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $wifiUsers
                                        }
                                        '^Remote Desktop Users$' {
                                            $rdpUsers = Get-ADUser -Filter "Office -like '*Remote*' -or Department -eq 'Operations' -or Title -like '*IT*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $rdpUsers
                                        }

                                        # Device-based groups
                                        '^Workstation Users$' {
                                            $workstationUsers = Get-ADUser -Filter "Enabled -eq 'True'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $workstationUsers | Where-Object { $_.Office -notlike '*Remote*' -and $_.Department -notin @('Sales', 'Sales Engagement Management') }
                                        }

                                        # Application access groups - basic access for all employees
                                        '^Email Users$|^Calendar Users$|^Internet Access Basic$|^Conference Room Booking$|^File Share Users$' {
                                            $basicUsers = Get-ADUser -Filter "Enabled -eq 'True'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $basicUsers
                                        }
                                        '^Internet Access Full$' {
                                            $fullAccessUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $fullAccessUsers | Where-Object { $_.EmployeeType -ne 'Intern' }
                                        }
                                        '^Expense System Access$' {
                                            $expenseUsers = Get-ADUser -Filter "Enabled -eq 'True'" -Properties EmployeeType -ErrorAction SilentlyContinue
                                            $membersToAdd += $expenseUsers | Where-Object { $_.EmployeeType -ne 'Intern' }
                                        }

                                        # Department computing groups
                                        '^Engineering Computing$' {
                                            $engComputing = Get-ADUser -Filter "Department -eq 'Engineering' -or Department -eq 'Engineering Operations'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $engComputing
                                        }
                                        '^Executive Computing$' {
                                            $execComputing = Get-ADUser -Filter "Department -eq 'Executive'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $execComputing
                                        }
                                        '^Sales Computing$' {
                                            $salesComputing = Get-ADUser -Filter "Department -eq 'Sales' -or Department -eq 'Sales Engagement Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $salesComputing
                                        }

                                        # Specific access groups based on department and role
                                        '^Development Tools$|^Engineering File Access$' {
                                            $devUsers = Get-ADUser -Filter "Department -eq 'Engineering' -or Department -eq 'Engineering Operations'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $devUsers
                                        }
                                        '^Design Tools$' {
                                            $designUsers = Get-ADUser -Filter "Department -eq 'Marketing' -or Department -eq 'Creative'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $designUsers
                                        }
                                        '^Executive File Access$|^Executive Floor Access$' {
                                            $execAccess = Get-ADUser -Filter "Department -eq 'Executive' -or Department -eq 'Senior Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $execAccess
                                        }
                                        '^Finance File Access$|^Financial Applications$|^Payroll System Access$' {
                                            $financeAccess = Get-ADUser -Filter "Department -eq 'Accounting' -or Department -eq 'Human Resources'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $financeAccess
                                        }
                                        '^HR Applications$|^HR File Access$' {
                                            $hrAccess = Get-ADUser -Filter "Department -eq 'Human Resources'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $hrAccess
                                        }
                                        '^Project File Access$|^Project Management Tools$' {
                                            $projectAccess = Get-ADUser -Filter "Department -eq 'Project Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $projectAccess
                                        }
                                        '^CRM System Access$' {
                                            $crmAccess = Get-ADUser -Filter "Department -eq 'Sales' -or Department -eq 'Sales Engagement Management' -or Department -eq 'Marketing' -or Department -eq 'CRM Strategy'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $crmAccess
                                        }
                                        '^Database Access Read$|^Business Intelligence$' {
                                            $dbRead = Get-ADUser -Filter "Title -like '*Analyst*' -or Title -like '*Manager*' -or Title -like '*Director*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $dbRead
                                        }
                                        '^Database Access Write$' {
                                            $dbWrite = Get-ADUser -Filter "(Department -eq 'Engineering' -or Department -eq 'Engineering Operations') -and (Title -like '*Engineer*' -or Title -like '*Developer*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $dbWrite
                                        }
                                        '^Color Printer Access$' {
                                            $colorPrint = Get-ADUser -Filter "Department -eq 'Marketing' -or Department -eq 'Executive' -or Department -eq 'Senior Management'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $colorPrint
                                        }

                                        # Printer access by location
                                        '^Printer Access Engineering$' {
                                            $printEng = Get-ADUser -Filter "Office -eq 'Seattle - Engineering'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $printEng
                                        }
                                        '^Printer Access Finance$' {
                                            $printFin = Get-ADUser -Filter "Office -eq 'Seattle - Finance'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $printFin
                                        }
                                        '^Printer Access Main$' {
                                            $printMain = Get-ADUser -Filter "Office -eq 'Seattle - Main'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $printMain
                                        }

                                        # Administrative groups
                                        '^After Hours Access$' {
                                            $afterHoursAccess = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Manager*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $afterHoursAccess
                                        }
                                        '^Backup System Access$' {
                                            $backupAccess = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Administrator*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $backupAccess
                                        }
                                        '^Monitoring System Access$' {
                                            $monitoringAccess = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $monitoringAccess
                                        }
                                        '^Security Event Review$' {
                                            $securityAccess = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $securityAccess
                                        }
                                        '^Server Room Access$' {
                                            $serverRoomAccess = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Manager*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $serverRoomAccess
                                        }
                                        '^Software Installation$' {
                                            $softwareInstall = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $softwareInstall
                                        }
                                        '^Payroll System Access$' {
                                            $payrollAccess = Get-ADUser -Filter "Department -eq 'Human Resources' -or (Department -eq 'Accounting' -and Title -like '*Manager*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $payrollAccess
                                        }
                                        '^Database Access Write$' {
                                            $dbWrite = Get-ADUser -Filter "(Department -eq 'Engineering' -or Department -eq 'Engineering Operations') -and (Title -like '*Engineer*' -or Title -like '*Developer*')" -ErrorAction SilentlyContinue
                                            $membersToAdd += $dbWrite
                                        }
                                        '^Compliance Reporting$' {
                                            $complianceAccess = Get-ADUser -Filter "Department -eq 'Accounting' -or Department -eq 'Human Resources'" -ErrorAction SilentlyContinue
                                            $membersToAdd += $complianceAccess
                                        }
                                        # Mobile device and laptop users based on device assignments
                                        '^Mobile Device Users$' {
                                            # Get all mobile devices and find their owners via ManagedBy property
                                            $mobileDevices = Get-ADComputer -Filter "Name -like '*Mobile*'" -Properties ManagedBy -ErrorAction SilentlyContinue
                                            $mobileUserDNs = $mobileDevices | Where-Object { $_.ManagedBy } | Select-Object -ExpandProperty ManagedBy -Unique
                                            $membersToAdd += $mobileUserDNs | ForEach-Object { Get-ADUser -Identity $_ -ErrorAction SilentlyContinue } | Where-Object { $_ }
                                        }
                                        '^Laptop Users$' {
                                            # Get all laptop devices and find their owners via ManagedBy property
                                            $laptopDevices = Get-ADComputer -Filter "Name -like '*Laptop*'" -Properties ManagedBy -ErrorAction SilentlyContinue
                                            $laptopUserDNs = $laptopDevices | Where-Object { $_.ManagedBy } | Select-Object -ExpandProperty ManagedBy -Unique
                                            $membersToAdd += $laptopUserDNs | ForEach-Object { Get-ADUser -Identity $_ -ErrorAction SilentlyContinue } | Where-Object { $_ }
                                        }
                                        # Test administrative groups - assign to IT staff for testing
                                        '^Test Domain Admins$' {
                                            $testDomainAdmins = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testDomainAdmins | Select-Object -First 3
                                        }
                                        '^Test Enterprise Admins$' {
                                            $testEnterpriseAdmins = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testEnterpriseAdmins | Select-Object -First 2
                                        }
                                        '^Test Schema Admins$' {
                                            $testSchemaAdmins = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testSchemaAdmins | Select-Object -First 1
                                        }
                                        '^Test Backup Operators$' {
                                            $testBackupOps = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Technician*')" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testBackupOps | Select-Object -First 4
                                        }
                                        '^Test Server Operators$' {
                                            $testServerOps = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Administrator*')" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testServerOps | Select-Object -First 5
                                        }
                                        '^Test Account Operators$' {
                                            $testAccountOps = Get-ADUser -Filter "Department -eq 'Operations' -and Title -like '*IT*'" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testAccountOps | Select-Object -First 3
                                        }
                                        '^Test Print Operators$' {
                                            $testPrintOps = Get-ADUser -Filter "Department -eq 'Operations' -and (Title -like '*IT*' -or Title -like '*Support*')" -Properties Title, Department -ErrorAction SilentlyContinue
                                            $membersToAdd += $testPrintOps | Select-Object -First 2
                                        }

                                        default {
                                            # No specific membership logic - group will remain empty
                                            # This is intentional for groups that require manual assignment
                                        }
                                    }

                                    # Add members to group using batch Add-ADGroupMember
                                    if ($membersToAdd.Count -gt 0) {
                                        try {
                                            # Use batch member addition for efficiency
                                            $memberDNs = $membersToAdd | ForEach-Object { $_.DistinguishedName }
                                            Add-ADGroupMember -Identity $adGroup.DistinguishedName -Members $memberDNs -ErrorAction Stop
                                            $results.MembersAdded += $membersToAdd.Count
                                        }
                                        catch {
                                            # If batch fails, try individual additions
                                            $batchError = $_.Exception.Message
                                            $results.Errors += "Batch add failed for $($group.GroupName), trying individual adds: $batchError"

                                            foreach ($member in $membersToAdd) {
                                                try {
                                                    Add-ADGroupMember -Identity $adGroup.DistinguishedName -Members $member.DistinguishedName -ErrorAction Stop
                                                    $results.MembersAdded++
                                                }
                                                catch {
                                                    if ($_.Exception.Message -notlike "*already a member*") {
                                                        $results.Errors += "Failed to add $($member.Name) to $($group.GroupName): $($_.Exception.Message)"
                                                    }
                                                    # If already a member, just count it as added (no error)
                                                    elseif ($_.Exception.Message -like "*already a member*") {
                                                        $results.MembersAdded++
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    $results.GroupsProcessed++
                                }
                                catch {
                                    $results.Errors += "Error processing group $($group.GroupName): $($_.Exception.Message)"
                                }
                            }

                            return $results
                        } -ArgumentList $currentBatch, $domain.DomainDN

                        $script:MembershipJobs.Add($job)
                    }

                    # Wait for all jobs to complete and collect results
                    Write-ADTestProgress -Message "Waiting for membership assignment jobs to complete..." -Type Info

                    do {
                        Start-Sleep -Milliseconds 500
                        $runningJobs = Get-Job -State Running

                        # Collect completed jobs
                        $completedJobs = Get-Job -State Completed
                        foreach ($job in $completedJobs) {
                            try {
                                $jobResult = Receive-Job $job
                                $script:JobResults.Add($jobResult)
                                Remove-Job $job
                            }
                            catch {
                                Write-Warning "Error receiving job result: $($_.Exception.Message)"
                                $script:Errors += "Job processing error: $($_.Exception.Message)"
                                Remove-Job $job -Force
                            }
                        }

                        $remainingJobs = (Get-Job -State Running).Count
                        if ($remainingJobs -gt 0) {
                            Write-Progress -Activity "Creating Security Groups" -Status "Waiting for $remainingJobs membership jobs to complete" -PercentComplete 95
                        }

                    } while ($runningJobs.Count -gt 0)

                    # Process any failed jobs
                    $failedJobs = Get-Job -State Failed
                    foreach ($job in $failedJobs) {
                        $script:Errors += "Job failed: $($job.Name)"
                        Remove-Job $job -Force
                    }

                    # Aggregate results
                    foreach ($result in $script:JobResults) {
                        $script:MembersAdded += $result.MembersAdded
                        if ($result.Errors -and $result.Errors.Count -gt 0) {
                            foreach ($error in $result.Errors) {
                                if (-not [string]::IsNullOrWhiteSpace($error)) {
                                    $script:Errors += $error
                                }
                            }
                        }
                    }

                    Write-ADTestProgress -Message "Membership assignment completed" -Type Success
                }
            }

            Write-Progress -Activity "Creating Security Groups" -Status "Complete" -PercentComplete 100 -Completed

            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalGroups = $totalGroups
                CreatedGroups = $script:GroupsCreated
                SkippedGroups = $script:GroupsSkipped
                MembersAdded = if ($SkipMemberAssignment) { 0 } else { $script:MembersAdded }
                Errors = $script:Errors
            }

            # Display summary
            Write-ADTestProgress -Message "Security Group Creation Summary" -Type Success
            Write-Host "  Groups Created: $($results.CreatedGroups)" -ForegroundColor Green
            Write-Host "  Groups Skipped: $($results.SkippedGroups)" -ForegroundColor Yellow
            if (-not $SkipMemberAssignment) {
                Write-Host "  Members Added: $($results.MembersAdded)" -ForegroundColor Green
            }

            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            Write-Error "Failed to create security groups: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestSecurityGroups - CorrelationId: $correlationId"
    }
}
