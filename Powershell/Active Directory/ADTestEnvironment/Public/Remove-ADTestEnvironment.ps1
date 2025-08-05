function Remove-ADTestEnvironment {
    <#
    .SYNOPSIS
        Safely removes all AD test data created by the ADTestEnvironment module

    .DESCRIPTION
        Performs a complete cleanup of test data including users, devices, security groups,
        and optionally OUs. Includes safety checks and progress reporting.

    .PARAMETER RemoveOUs
        Also removes the test OU structure (WARNING: This is destructive)

    .PARAMETER VaultName
        Name of the SecretStore vault to remove. Defaults to "ADTestEnvironment"

    .PARAMETER Force
        Bypasses confirmation prompts (use with caution)

    .PARAMETER ResetSecretStore
        Also reset the global SecretStore configuration to defaults.
        WARNING: This will affect ALL SecretStore vaults on the system.
        Use with caution if you have other vaults configured.

    .PARAMETER GlobalVault
        Create/remove vault at AllUsers scope instead of CurrentUser scope.
        Requires administrative privileges.

    .PARAMETER PassThru
        Returns detailed results object (default: summary only)

    .PARAMETER WhatIf
        Shows what would be removed without making changes

    .EXAMPLE
        Remove-ADTestEnvironment -WhatIf
        Shows what would be removed without making changes

    .EXAMPLE
        Remove-ADTestEnvironment -RemoveOUs -Force
        Removes all test data including OUs and SecretStore vault without confirmation

    .EXAMPLE
        Remove-ADTestEnvironment -VaultName "CustomVault"
        Removes test data and a custom named vault

    .EXAMPLE
        Remove-ADTestEnvironment -ResetSecretStore -Force
        Removes test data, vault, AND resets SecretStore configuration without prompts

    .EXAMPLE
        Remove-ADTestEnvironment -GlobalVault -Force
        Removes test data and a global vault (requires admin privileges)

    .OUTPUTS
        Hashtable with removal results and statistics

    .NOTES
        Author: Jeffrey Stuhr
        Version: 2.0.0
        Last Updated: 2025-08-05
        
        WARNING: This function is destructive. Always test with -WhatIf first.
        
        SECRETSTORE CLEANUP:
        - Automatically removes SecretStore vaults created during environment setup
        - All stored passwords/secrets will be permanently deleted
        - Vault removal is a management operation that doesn't require the vault password
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$RemoveOUs,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = "ADTestEnvironment",
        
        [switch]$Force,
        [switch]$PassThru,
        
        [Parameter()]
        [switch]$ResetSecretStore,
        
        [Parameter()]
        [switch]$GlobalVault
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Remove-ADTestEnvironment - CorrelationId: $correlationId"
        
        # Get domain information
        $domain = Get-ADTestDomain
        
        # Safety check - confirm this is a test environment
        $manuallyConfirmed = $false
        if (-not $Force) {
            Write-Warning "This will permanently delete all test data from Active Directory."
            Write-Warning "Domain: $($domain.DNSName)"
            if ($RemoveOUs) {
                Write-Warning "OU REMOVAL ENABLED: This will also delete the entire test OU structure!"
            }
            
            $confirmation = Read-Host "Type 'CONFIRM' to proceed with deletion"
            if ($confirmation -ne 'CONFIRM') {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                return @{ Cancelled = $true }
            }
            $manuallyConfirmed = $true
        }
        
        # Counters
        $script:UsersRemoved = 0
        $script:DevicesRemoved = 0
        $script:GroupsRemoved = 0
        $script:OUsRemoved = 0
        $script:VaultsRemoved = 0
        $script:SecretsRemoved = 0
        $script:Errors = @()
    }

    process {
        try {
            Write-ADTestProgress -Message "Removing Active Directory Test Environment" -Type Header
            
            # Step 1: Remove Test Users
            Write-ADTestProgress -Message "Removing test users..." -Type Info
            try {
                # Remove all users from TestData OU structure (excluding built-in accounts)
                $testUsers = Get-ADUser -Filter "*" -SearchBase "OU=TestData,$($domain.DomainDN)" -ErrorAction SilentlyContinue
                
                foreach ($user in $testUsers) {
                    if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess($user.Name, "Remove AD User")) {
                        try {
                            Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed user: $($user.Name)"
                            $script:UsersRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove user $($user.Name): $($_.Exception.Message)"
                            $script:Errors += "User removal error: $($user.Name)"
                        }
                    }
                    else {
                        Write-Host "Would remove user: $($user.Name)" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test users found (TestData OU may not exist)"
                } else {
                    Write-Warning "Error searching for test users: $($_.Exception.Message)"
                }
                $script:Errors += "User search error: $($_.Exception.Message)"
            }
            
            # Step 2: Remove Test Devices
            Write-ADTestProgress -Message "Removing test devices..." -Type Info
            try {
                # Remove all devices from TestData OU structure
                $testDevices = Get-ADComputer -Filter "*" -SearchBase "OU=TestData,$($domain.DomainDN)" -ErrorAction SilentlyContinue
                
                foreach ($device in $testDevices) {
                    if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess($device.Name, "Remove AD Computer")) {
                        try {
                            Remove-ADComputer -Identity $device.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed device: $($device.Name)"
                            $script:DevicesRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove device $($device.Name): $($_.Exception.Message)"
                            $script:Errors += "Device removal error: $($device.Name)"
                        }
                    }
                    else {
                        Write-Host "Would remove device: $($device.Name)" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test devices found (TestData OU may not exist)"
                } else {
                    Write-Warning "Error searching for test devices: $($_.Exception.Message)"
                }
                $script:Errors += "Device search error: $($_.Exception.Message)"
            }
            
            # Step 3: Remove Test Service Accounts
            Write-ADTestProgress -Message "Removing test service accounts..." -Type Info
            try {
                # Remove all service accounts from ServiceAccounts OU
                $testServiceAccounts = Get-ADUser -Filter "*" -SearchBase "OU=ServiceAccounts,OU=TestData,$($domain.DomainDN)" -ErrorAction SilentlyContinue
                
                foreach ($serviceAccount in $testServiceAccounts) {
                    if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess($serviceAccount.Name, "Remove AD Service Account")) {
                        try {
                            Remove-ADUser -Identity $serviceAccount.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed service account: $($serviceAccount.Name)"
                            $script:UsersRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove service account $($serviceAccount.Name): $($_.Exception.Message)"
                            $script:Errors += "Service account removal error: $($serviceAccount.Name)"
                        }
                    }
                    else {
                        Write-Host "Would remove service account: $($serviceAccount.Name)" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test service accounts found (ServiceAccounts OU may not exist)"
                } else {
                    Write-Warning "Error searching for test service accounts: $($_.Exception.Message)"
                }
                $script:Errors += "Service account search error: $($_.Exception.Message)"
            }
            
            # Step 4: Remove Test Security Groups
            Write-ADTestProgress -Message "Removing test security groups..." -Type Info
            try {
                # Get groups from the Groups OU structure  
                $testGroups = Get-ADGroup -Filter "*" -SearchBase "OU=Groups,OU=TestData,$($domain.DomainDN)" -ErrorAction SilentlyContinue
                
                foreach ($group in $testGroups) {
                    if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess($group.Name, "Remove AD Group")) {
                        try {
                            Remove-ADGroup -Identity $group.DistinguishedName -Confirm:$false
                            Write-Verbose "Removed group: $($group.Name)"
                            $script:GroupsRemoved++
                        }
                        catch {
                            Write-Warning "Failed to remove group $($group.Name): $($_.Exception.Message)"
                            $script:Errors += "Group removal error: $($group.Name)"
                        }
                    }
                    else {
                        Write-Host "Would remove group: $($group.Name)" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                if ($_.Exception.Message -like "*Directory object not found*") {
                    Write-Verbose "No test groups found (Groups OU may not exist)"
                } else {
                    Write-Warning "Error searching for test groups: $($_.Exception.Message)"
                }
                $script:Errors += "Group search error: $($_.Exception.Message)"
            }
            
            # Step 5: Remove OUs (if requested)
            if ($RemoveOUs) {
                Write-ADTestProgress -Message "Removing test OU structure..." -Type Info
                
                if ($RemoveOUs) {
                    try {
                        # Remove OUs in reverse hierarchical order
                        $ouRemovalOrder = @(
                            "OU=Administrative,OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Resource,OU=Groups,OU=TestData,$($domain.DomainDN)", 
                            "OU=Device,OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Location,OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Role,OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Department,OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Groups,OU=TestData,$($domain.DomainDN)",
                            "OU=Workstations,OU=Devices,OU=TestData,$($domain.DomainDN)",
                            "OU=Servers,OU=Devices,OU=TestData,$($domain.DomainDN)",
                            "OU=Printers,OU=Devices,OU=TestData,$($domain.DomainDN)",
                            "OU=Mobile,OU=Devices,OU=TestData,$($domain.DomainDN)",
                            "OU=Devices,OU=TestData,$($domain.DomainDN)",
                            "OU=ServiceAccounts,OU=TestData,$($domain.DomainDN)"
                        )
                        
                        # Add department/user OUs (dynamically discovered)
                        try {
                            $userOUs = Get-ADOrganizationalUnit -Filter "*" -SearchBase "OU=Users,OU=TestData,$($domain.DomainDN)" -ErrorAction SilentlyContinue
                            foreach ($userOU in $userOUs) {
                                if ($userOU.DistinguishedName -ne "OU=Users,OU=TestData,$($domain.DomainDN)") {
                                    $ouRemovalOrder = @($userOU.DistinguishedName) + $ouRemovalOrder
                                }
                            }
                        }
                        catch {
                            Write-Verbose "No user department OUs found or error accessing them"
                        }
                        
                        # Add the main structure OUs
                        $ouRemovalOrder += @(
                            "OU=Users,OU=TestData,$($domain.DomainDN)",
                            "OU=TestData,$($domain.DomainDN)"
                        )
                        
                        foreach ($ouPath in $ouRemovalOrder) {
                            if ($Force -or $manuallyConfirmed -or $PSCmdlet.ShouldProcess($ouPath, "Remove AD Organizational Unit")) {
                                try {
                                    # Check if OU exists before trying to remove
                                    $ou = Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction SilentlyContinue
                                    if ($ou) {
                                        # Enable deletion by removing protection
                                        Set-ADOrganizationalUnit -Identity $ouPath -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue
                                        Remove-ADOrganizationalUnit -Identity $ouPath -Recursive -Confirm:$false
                                        Write-Verbose "Removed OU: $ouPath"
                                        $script:OUsRemoved++
                                    }
                                }
                                catch {
                                    # Only warn for actual failures, not missing OUs
                                    if ($_.Exception.Message -notmatch "Directory object not found") {
                                        Write-Warning "Failed to remove OU $ouPath : $($_.Exception.Message)"
                                        $script:Errors += "OU removal error: $ouPath"
                                    }
                                    else {
                                        Write-Verbose "OU not found (already removed): $ouPath"
                                    }
                                }
                            }
                            else {
                                Write-Host "Would remove OU: $ouPath" -ForegroundColor Yellow
                            }
                        }
                    }
                    catch {
                        # Only warn for actual failures, not missing search bases
                        if ($_.Exception.Message -notmatch "Directory object not found") {
                            Write-Warning "Error during OU removal: $($_.Exception.Message)"
                            $script:Errors += "OU removal process error: $($_.Exception.Message)"
                        }
                        else {
                            Write-Verbose "OU structure not found (already clean): $($_.Exception.Message)"
                        }
                    }
                }
            }
            
            # Remove SecretStore vault if it exists
            try {
                Write-ADTestProgress -Message "Checking for SecretStore vault removal..." -Type Info
                
                if ($Force -or $PSCmdlet.ShouldProcess("SecretStore Vault: $VaultName", "Remove Secret Vault")) {
                    $vaultResult = Remove-ADTestSecretVault -VaultName $VaultName -Force:$Force -ResetSecretStore:$ResetSecretStore -GlobalVault:$GlobalVault
                    
                    if ($vaultResult.VaultRemoved) {
                        $script:VaultsRemoved++
                        $script:SecretsRemoved += $vaultResult.SecretsRemoved
                        Write-Host "  Removed SecretStore vault: $VaultName" -ForegroundColor Green
                        Write-Host "  Removed $($vaultResult.SecretsRemoved) stored secrets" -ForegroundColor Green
                        
                        if ($vaultResult.SecretStoreReset) {
                            Write-Host "  Reset SecretStore configuration to defaults" -ForegroundColor Green
                        }
                    }
                    elseif ($vaultResult.VaultExists -eq $false) {
                        Write-Host "  SecretStore vault '$VaultName' was not found" -ForegroundColor Yellow
                    }
                    
                    if ($vaultResult.Errors.Count -gt 0) {
                        $vaultResult.Errors | ForEach-Object { 
                            Write-Warning "Vault removal error: $_"
                            $script:Errors += "Vault removal: $_"
                        }
                    }
                }
                else {
                    Write-Host "Would remove SecretStore vault: $VaultName" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Warning "Error during vault removal: $($_.Exception.Message)"
                $script:Errors += "Vault removal process error: $($_.Exception.Message)"
            }
            
            # Create summary
            $results = @{
                CorrelationId = $correlationId
                UsersRemoved = $script:UsersRemoved
                DevicesRemoved = $script:DevicesRemoved
                GroupsRemoved = $script:GroupsRemoved
                OUsRemoved = $script:OUsRemoved
                VaultsRemoved = $script:VaultsRemoved
                SecretsRemoved = $script:SecretsRemoved
                OUsRequested = $RemoveOUs
                Errors = $script:Errors
                TotalRemoved = $script:UsersRemoved + $script:DevicesRemoved + $script:GroupsRemoved + $script:OUsRemoved + $script:VaultsRemoved
            }
            
            # Display summary
            Write-ADTestProgress -Message "Test Environment Removal Summary" -Type Success
            Write-Host "  Users Removed: $($results.UsersRemoved)" -ForegroundColor Green
            Write-Host "  Devices Removed: $($results.DevicesRemoved)" -ForegroundColor Green
            Write-Host "  Groups Removed: $($results.GroupsRemoved)" -ForegroundColor Green
            if ($RemoveOUs) {
                Write-Host "  OUs Removed: $($results.OUsRemoved)" -ForegroundColor Green
            }
            if ($results.VaultsRemoved -gt 0) {
                Write-Host "  SecretStore Vaults Removed: $($results.VaultsRemoved)" -ForegroundColor Green
            }
            if ($results.SecretsRemoved -gt 0) {
                Write-Host "  Secrets Removed: $($results.SecretsRemoved)" -ForegroundColor Green
            }
            Write-Host "  Total Objects Removed: $($results.TotalRemoved)" -ForegroundColor Cyan
            
            if ($results.Errors.Count -gt 0) {
                Write-Host "  Errors: $($results.Errors.Count)" -ForegroundColor Red
                $results.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            else {
                Write-Host "  No errors encountered!" -ForegroundColor Green
            }
            
            # Return detailed results for programmatic access only
            if ($PassThru) {
                return [PSCustomObject]$results
            }
            # Store results in verbose output for troubleshooting
            Write-Verbose "Detailed results: $($results | ConvertTo-Json -Depth 3)"
            
        } catch {
            Write-Error "Failed to remove test environment: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Remove-ADTestEnvironment - CorrelationId: $correlationId"
    }
}
