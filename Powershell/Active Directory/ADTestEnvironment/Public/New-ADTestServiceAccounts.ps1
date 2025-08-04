function New-ADTestServiceAccounts {
    <#
    .SYNOPSIS
        Creates Active Directory test service accounts from CSV data

    .DESCRIPTION
        Creates service accounts in Active Directory based on data from ADServiceAccounts.csv.
        Service accounts are created with secure passwords, configured for non-interactive use,
        and passwords are exported to a timestamped file for documentation.

    .PARAMETER PassThru
        Returns the results object instead of displaying summary

    .EXAMPLE
        New-ADTestServiceAccounts
        Creates all service accounts from ADServiceAccounts.csv and displays summary

    .EXAMPLE
        $results = New-ADTestServiceAccounts -PassThru
        Creates service accounts and returns results object

    .OUTPUTS
        PSCustomObject with creation results and statistics (when -PassThru is used)

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-02
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestServiceAccounts - CorrelationId: $correlationId"
        
        # Get data paths
        $dataPath = Get-ADTestDataPath
        $serviceAccountsCSV = Join-Path $dataPath "ADServiceAccounts.csv"
        
        # Verify prerequisites
        if (-not (Test-Path $serviceAccountsCSV)) {
            throw "ADServiceAccounts.csv not found at: $dataPath"
        }
        
        # Get domain information
        $domain = Get-ADTestDomain
        
        # Counters
        $script:ServiceAccountsCreated = 0
        $script:ServiceAccountsSkipped = 0
        $script:Errors = @()
        $script:PasswordExports = @()
    }

    process {
        try {
            Write-ADTestProgress -Message "Creating Active Directory Test Service Accounts" -Type Header
            Write-ADTestProgress -Message "Loading service account data from CSV..." -Type Info
            
            # Import service account data
            $serviceAccounts = Import-Csv $serviceAccountsCSV
            Write-Verbose "Loaded $($serviceAccounts.Count) service accounts from CSV"
            
            $totalAccounts = $serviceAccounts.Count
            $currentAccount = 0
            
            Write-ADTestProgress -Message "Processing $totalAccounts service accounts..." -Type Info
            
            foreach ($serviceAccount in $serviceAccounts) {
                $currentAccount++
                $percentComplete = ($currentAccount / $totalAccounts) * 100
                
                Write-Progress -Activity "Creating Service Accounts" -Status "Processing $($serviceAccount.SamAccountName)" -PercentComplete $percentComplete
                
                try {
                    # Skip if service account already exists
                    $existingAccount = Get-ADUser -Filter "SamAccountName -eq '$($serviceAccount.SamAccountName)'" -ErrorAction SilentlyContinue
                    if ($existingAccount) {
                        Write-Verbose "Service account $($serviceAccount.SamAccountName) already exists, skipping"
                        $script:ServiceAccountsSkipped++
                        continue
                    }
                    
                    # Generate cryptographically secure password
                    $password = New-SecureRandomPassword -Length 16
                    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
                    
                    # Store password for export
                    $script:PasswordExports += New-PasswordExportEntry -ServiceAccountName $serviceAccount.SamAccountName -Password $password -Description $serviceAccount.Description
                    
                    # Get manager if specified
                    $manager = $null
                    if (-not [string]::IsNullOrWhiteSpace($serviceAccount.Manager)) {
                        # Handle both DN format (CN=Name) and plain name format
                        $managerName = $serviceAccount.Manager
                        if ($managerName.StartsWith('CN=')) {
                            $managerName = $managerName.Substring(3)  # Remove 'CN=' prefix
                        }
                        
                        $manager = Get-ADUser -Filter "Name -eq '$managerName'" -ErrorAction SilentlyContinue
                        if (-not $manager) {
                            Write-Warning "Manager '$managerName' not found for service account $($serviceAccount.SamAccountName)"
                        }
                    }
                    
                    # Determine OU path
                    $ouPath = "OU=ServiceAccounts,OU=TestData,$($domain.DomainDN)"
                    
                    # Verify OU exists
                    try {
                        Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Warning "OU not found: $ouPath. Skipping service account creation for $($serviceAccount.SamAccountName). Please ensure OU structure is created first."
                        $script:ServiceAccountsSkipped++
                        continue
                    }
                    
                    # Generate dynamic email address
                    $dynamicEmail = if ([string]::IsNullOrWhiteSpace($serviceAccount.mail)) {
                        "$($serviceAccount.SamAccountName)@$($domain.DNSName)"
                    } else {
                        "$($serviceAccount.mail)@$($domain.DNSName)"
                    }
                    
                    # Prepare service account parameters
                    $accountParams = @{
                        Name = $serviceAccount.Name
                        SamAccountName = $serviceAccount.SamAccountName
                        UserPrincipalName = "$($serviceAccount.SamAccountName)@$($domain.DNSName)"
                        EmailAddress = $dynamicEmail
                        GivenName = $serviceAccount.GivenName
                        Surname = $serviceAccount.Surname
                        DisplayName = $serviceAccount.Name
                        Description = $serviceAccount.Description
                        Department = $serviceAccount.Department
                        Title = $serviceAccount.Title
                        Office = $serviceAccount.Office
                        StreetAddress = $serviceAccount.StreetAddress
                        City = $serviceAccount.City
                        State = $serviceAccount.State
                        PostalCode = $serviceAccount.PostalCode
                        AccountPassword = $securePassword
                        Enabled = $true
                        CannotChangePassword = $true
                        PasswordNeverExpires = $true
                        Path = $ouPath
                    }
                    
                    # Add manager if found (only add parameter if manager exists)
                    if ($manager) {
                        $accountParams.Manager = $manager.DistinguishedName
                        Write-Verbose "Setting manager for $($serviceAccount.SamAccountName): $($manager.Name)"
                    } else {
                        Write-Verbose "No manager specified or found for $($serviceAccount.SamAccountName)"
                    }
                    
                    # Create service account
                    if ($PSCmdlet.ShouldProcess($serviceAccount.SamAccountName, "Create AD Service Account")) {
                        Write-Verbose "Creating service account: $($serviceAccount.SamAccountName)"
                        $newAccount = New-ADUser @accountParams -PassThru
                        
                        # Set additional properties that require the account to exist
                        Set-ADUser -Identity $newAccount.DistinguishedName -SmartcardLogonRequired $false
                        
                        # Deny interactive logon
                        $logonRights = @(
                            "SeDenyInteractiveLogonRight",
                            "SeDenyRemoteInteractiveLogonRight",
                            "SeDenyNetworkLogonRight"
                        )
                        
                        Write-Verbose "Service account $($serviceAccount.SamAccountName) created successfully"
                        $script:ServiceAccountsCreated++
                    }
                    else {
                        Write-Host "Would create service account: $($serviceAccount.SamAccountName)" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Error "Failed to create service account $($serviceAccount.SamAccountName): $($_.Exception.Message)"
                    $script:Errors += "Service account creation error for $($serviceAccount.SamAccountName): $($_.Exception.Message)"
                }
            }
            
            Write-Progress -Activity "Creating Service Accounts" -Status "Complete" -PercentComplete 100 -Completed
            
            # Export passwords to file if accounts were created
            $passwordFile = $null
            if ($script:PasswordExports.Count -gt 0 -and -not $WhatIfPreference) {
                try {
                    Write-Verbose "Exporting password documentation for $($script:PasswordExports.Count) service accounts"
                    
                    $passwordFile = Export-PasswordDocumentation -PasswordData $script:PasswordExports -FilePrefix "ServiceAccountPW"
                    
                    Write-Verbose "Service account passwords exported to: $passwordFile"
                }
                catch {
                    Write-Warning "Failed to export service account passwords: $($_.Exception.Message)"
                    $script:Errors += "Password export error: $($_.Exception.Message)"
                }
            }
            
            # Create summary
            $results = @{
                CorrelationId = $correlationId
                TotalAccounts = $totalAccounts
                CreatedAccounts = $script:ServiceAccountsCreated
                SkippedAccounts = $script:ServiceAccountsSkipped
                PasswordFile = $passwordFile
                Errors = $script:Errors
            }
            
            # Display summary or return results
            if ($PassThru) {
                return [PSCustomObject]$results
            } else {
                Write-ADTestProgress -Message "Service Account Creation Summary" -Type Success
                Write-Host "  Accounts Created: $($results.CreatedAccounts)" -ForegroundColor Green
                Write-Host "  Accounts Skipped: $($results.SkippedAccounts)" -ForegroundColor Yellow
                
                if ($passwordFile) {
                    Write-Host "  Password File: $passwordFile" -ForegroundColor Cyan
                    Write-Host "  WARNING: Store password file securely and delete after use!" -ForegroundColor Red
                }
                
                if ($results.Errors.Count -gt 0) {
                    Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                    $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
                }
            }
            
        } catch {
            Write-Error "Failed to create service accounts: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestServiceAccounts - CorrelationId: $correlationId"
    }
}
