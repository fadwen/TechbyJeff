function New-ADTestOUStructure {
    <#
    .SYNOPSIS
        Creates the standardized organizational unit (OU) structure for AD test data.

    .DESCRIPTION
        Creates a comprehensive OU structure including TestData parent OU and sub-OUs
        for Users (by department), Groups (by category), Devices (by type), and
        ServiceAccounts. Supports WhatIf for preview mode.

    .PARAMETER PassThru
        Returns a PSCustomObject with creation results and statistics

    .EXAMPLE
        PS> New-ADTestOUStructure
        Creates the complete OU structure

    .EXAMPLE
        PS> New-ADTestOUStructure -WhatIf
        Shows what would be created without making changes

    .EXAMPLE
        PS> $results = New-ADTestOUStructure -PassThru
        Creates the OU structure and returns results for further processing

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: $(Get-Date -Format 'yyyy-MM-dd')

    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestOUStructure - CorrelationId: $correlationId"

        # Test prerequisites
        if (-not (Test-ADTestPrerequisite)) {
            throw "Prerequisites not met. Please ensure Active Directory module is installed and you have appropriate permissions."
        }
    }

    process {
        try {
            Write-Host ""
            Write-Host "=========================================" -ForegroundColor Cyan
            Write-Host "   Active Directory TestData OU Structure Creation" -ForegroundColor Cyan
            Write-Host "=========================================" -ForegroundColor Cyan

            # Initialize results
            $results = @{
                Created = @()
                Skipped = @()
                Failed = @()
            }

            # Get domain information
            $domain = Get-ADTestDomain
            Write-Verbose "Detected domain: $($domain.DomainName) (DN: $($domain.DomainDN))"

            # Create main TestData OU
            Write-ADTestProgress -Message "Creating main TestData OU..." -Type Info
            $result = New-ADTestOU -Name "TestData" -Path $domain.DomainDN -Description "Root OU for all test data objects"
            switch ($result.Action) {
                'Created' { $results.Created += "TestData" }
                'Skipped' { $results.Skipped += "TestData" }
                'Failed' { $results.Failed += "TestData: $($result.Message)" }
            }

            $testDataOU = "OU=TestData,$($domain.DomainDN)"

            # Create Users OU
            $result = New-ADTestOU -Name "Users" -Path $testDataOU -Description "Test user accounts organized by department"
            switch ($result.Action) {
                'Created' { $results.Created += "Users" }
                'Skipped' { $results.Skipped += "Users" }
                'Failed' { $results.Failed += "Users: $($result.Message)" }
            }

            $usersOU = "OU=Users,$testDataOU"

            # Create Group category sub-OUs
            Write-ADTestProgress -Message "Creating Groups category sub-OUs..." -Type Info

            # Create Groups OU first
            $groupsOU = "OU=Groups,$testDataOU"
            $result = New-ADTestOU -Name "Groups" -Path $testDataOU -Description "Security groups organized by category"
            switch ($result.Action) {
                'Created' { $results.Created += "Groups" }
                'Skipped' { $results.Skipped += "Groups" }
                'Failed' { $results.Failed += "Groups: $($result.Message)" }
            }

            $groupCategories = @("Department", "Role", "Location", "Device", "Resource", "Administrative")
            foreach ($category in $groupCategories) {
                $result = New-ADTestOU -Name $category -Path $groupsOU -Description "$category-based security groups"
                switch ($result.Action) {
                    'Created' { $results.Created += "Groups\$category" }
                    'Skipped' { $results.Skipped += "Groups\$category" }
                    'Failed' { $results.Failed += "Groups\$category`: $($result.Message)" }
                }
            }

            # Create Device type sub-OUs
            Write-ADTestProgress -Message "Creating Device type sub-OUs..." -Type Info

            # Create Devices OU first
            $devicesOU = "OU=Devices,$testDataOU"
            $result = New-ADTestOU -Name "Devices" -Path $testDataOU -Description "Computer and device objects organized by type"
            switch ($result.Action) {
                'Created' { $results.Created += "Devices" }
                'Skipped' { $results.Skipped += "Devices" }
                'Failed' { $results.Failed += "Devices: $($result.Message)" }
            }

            $deviceTypes = @("Workstations", "Servers", "Printers", "Mobile")
            foreach ($deviceType in $deviceTypes) {
                $result = New-ADTestOU -Name $deviceType -Path $devicesOU -Description "$deviceType devices"
                switch ($result.Action) {
                    'Created' { $results.Created += "Devices\$deviceType" }
                    'Skipped' { $results.Skipped += "Devices\$deviceType" }
                    'Failed' { $results.Failed += "Devices\$deviceType`: $($result.Message)" }
                }
            }

            # Create ServiceAccounts OU
            $result = New-ADTestOU -Name "ServiceAccounts" -Path $testDataOU -Description "Service account objects for applications and services"
            switch ($result.Action) {
                'Created' { $results.Created += "ServiceAccounts" }
                'Skipped' { $results.Skipped += "ServiceAccounts" }
                'Failed' { $results.Failed += "ServiceAccounts: $($result.Message)" }
            }

            # Create department-based user OUs
            Write-ADTestProgress -Message "Analyzing departments from ADUsers.csv..." -Type Info
            $dataPath = Get-ADTestDataPath
            $csvPath = Join-Path $dataPath "ADUsers.csv"
            $departments = @()

            if (Test-Path $csvPath) {
                $departments = (Import-csv $csvPath | Select-Object -ExpandProperty Department | Sort-Object -Unique) | Where-Object {![string]::IsNullOrWhiteSpace($_)}
                Write-ADTestProgress -Message "Creating department sub-OUs..." -Type Info

                foreach ($dept in $departments) {
                    # Clean department name for OU creation
                    $cleanDept = $dept -replace '[^a-zA-Z0-9\s]', '' -replace '\s+', ' '
                    $cleanDept = $cleanDept.Trim()

                    if (![string]::IsNullOrWhiteSpace($cleanDept)) {
                        $result = New-ADTestOU -Name $cleanDept -Path $usersOU -Description "Users in the $dept department"
                        switch ($result.Action) {
                            'Created' { $results.Created += "Users\$cleanDept" }
                            'Skipped' { $results.Skipped += "Users\$cleanDept" }
                            'Failed' { $results.Failed += "Users\$cleanDept`: $($result.Message)" }
                        }
                    }
                }
            } else {
                Write-ADTestProgress -Message "ADUsers.csv not found - department OUs will be created during user creation" -Type Warning
            }

            # Display summary
            Write-Verbose "TestData OU Structure:"
            Write-Verbose "  TestData"
            Write-Verbose "    Users"

            foreach ($dept in $departments) {
                $cleanDept = $dept -replace '[^a-zA-Z0-9\s]', '' -replace '\s+', ' '
                $cleanDept = $cleanDept.Trim()
                if (![string]::IsNullOrWhiteSpace($cleanDept)) {
                    Write-Verbose "      $cleanDept"
                }
            }

            Write-Verbose "    Groups"
            foreach ($category in $groupCategories) {
                Write-Verbose "      $category"
            }

            Write-Verbose "    Devices"
            foreach ($deviceType in $deviceTypes) {
                Write-Verbose "      $deviceType"
            }

            Write-Verbose "    ServiceAccounts"

            # Display OU Creation Summary
            Write-ADTestProgress -Message "OU Creation Summary" -Type Info
            Write-ADTestProgress -Message "  OUs Created: $($results.Created.Count)" -Type Info
            Write-ADTestProgress -Message "  OUs Skipped: $($results.Skipped.Count)" -Type Warning
            if ($results.Failed.Count -gt 0) {
                Write-ADTestProgress -Message "  OUs Failed: $($results.Failed.Count)" -Type Error
            }

            if ($WhatIfPreference) {
                Write-ADTestProgress -Message "WHATIF: Organizational structure analysis complete!" -Type Warning
                Write-ADTestProgress -Message "Run without -WhatIf to create the actual OUs." -Type Warning
            } else {
                Write-ADTestProgress -Message "Organizational structure creation complete!" -Type Success
            }

            if ($PassThru) {
                return [PSCustomObject]$results
            }

        } catch {
            Write-Error "Failed to create organizational structure: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestOUStructure - CorrelationId: $correlationId"
    }
}
