function Test-SecretStorePrerequisite {
    <#
    .SYNOPSIS
        Tests and installs PowerShell SecretManagement/SecretStore prerequisites

    .DESCRIPTION
        Checks for required PowerShell modules for SecretManagement and SecretStore.
        Automatically installs missing modules if not present.

    .PARAMETER InstallIfMissing
        Automatically install missing modules. Defaults to $true.

    .PARAMETER Scope
        Installation scope for modules. Defaults to 'CurrentUser'

    .PARAMETER MaxRetries
        Maximum number of retry attempts for module installation/import when "in use" errors occur. Defaults to 2.

    .PARAMETER RetryDelaySeconds
        Delay in seconds between retry attempts. Defaults to 2.

    .EXAMPLE
        Test-SecretStorePrerequisite
        Checks and installs missing SecretStore modules

    .EXAMPLE
        Test-SecretStorePrerequisite -InstallIfMissing:$false
        Only checks for modules without installing

    .EXAMPLE
        Test-SecretStorePrerequisite -MaxRetries 3 -RetryDelaySeconds 5
        Checks and installs modules with custom retry settings for handling "in use" errors

    .OUTPUTS
        PSCustomObject containing prerequisite check results

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-05
        
        Required Modules:
        - Microsoft.PowerShell.SecretManagement
        - Microsoft.PowerShell.SecretStore
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [bool]$InstallIfMissing = $true,
        
        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser',
        
        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 2,
        
        [Parameter()]
        [ValidateRange(1, 30)]
        [int]$RetryDelaySeconds = 2
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Test-SecretStorePrerequisite - CorrelationId: $correlationId"
        
        $requiredModules = @(
            'Microsoft.PowerShell.SecretManagement',
            'Microsoft.PowerShell.SecretStore'
        )
        
        $results = @{
            CorrelationId = $correlationId
            RequiredModules = @()
            AllModulesAvailable = $true
            ModulesInstalled = @()
            ModulesImported = @()
            Errors = @()
        }
    }

    process {
        try {
            Write-Verbose "Checking required modules: $($requiredModules -join ', ')"
            
            foreach ($moduleName in $requiredModules) {
                $moduleResult = @{
                    Name = $moduleName
                    Available = $false
                    Installed = $false
                    Imported = $false
                    Version = $null
                    Error = $null
                }
                
                try {
                    # Check if module is available
                    $availableModule = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
                    
                    if ($availableModule) {
                        $moduleResult.Available = $true
                        $moduleResult.Version = $availableModule.Version.ToString()
                        Write-Verbose "Module $moduleName is available (Version: $($moduleResult.Version))"
                    }
                    else {
                        Write-Verbose "Module $moduleName is not available"
                        $results.AllModulesAvailable = $false
                        
                        if ($InstallIfMissing) {
                            Write-Verbose "Installing module: $moduleName"
                            try {
                                # First attempt - normal installation
                                Install-Module -Name $moduleName -Force -Scope $Scope -AllowClobber -ErrorAction Stop
                                $results.ModulesInstalled += $moduleName
                                $moduleResult.Installed = $true
                                $moduleResult.Available = $true
                                
                                # Get version after installation
                                $installedModule = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
                                if ($installedModule) {
                                    $moduleResult.Version = $installedModule.Version.ToString()
                                }
                                
                                Write-Verbose "Successfully installed module: $moduleName (Version: $($moduleResult.Version))"
                            }
                            catch {
                                # Check if it's a "module in use" error
                                if ($_.Exception.Message -like "*currently in use*" -or $_.Exception.Message -like "*version*is currently in use*") {
                                    Write-Verbose "Module $moduleName is in use, attempting retry with force unload and wait"
                                    
                                    $retryAttempt = 0
                                    $retrySuccess = $false
                                    
                                    while ($retryAttempt -lt $MaxRetries -and -not $retrySuccess) {
                                        $retryAttempt++
                                        Write-Verbose "Retry attempt $retryAttempt of $MaxRetries for module: $moduleName"
                                        
                                        try {
                                            # Try to remove the module from memory
                                            Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
                                            
                                            # Wait for module to be released
                                            Write-Verbose "Waiting $RetryDelaySeconds seconds for module to be released..."
                                            Start-Sleep -Seconds $RetryDelaySeconds
                                            
                                            # Retry installation
                                            Install-Module -Name $moduleName -Force -Scope $Scope -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                                            $results.ModulesInstalled += $moduleName
                                            $moduleResult.Installed = $true
                                            $moduleResult.Available = $true
                                            $retrySuccess = $true
                                            
                                            # Get version after installation
                                            $installedModule = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
                                            if ($installedModule) {
                                                $moduleResult.Version = $installedModule.Version.ToString()
                                            }
                                            
                                            Write-Verbose "Successfully installed module on retry $retryAttempt : $moduleName (Version: $($moduleResult.Version))"
                                        }
                                        catch {
                                            Write-Verbose "Retry $retryAttempt failed for $moduleName : $($_.Exception.Message)"
                                            if ($retryAttempt -eq $MaxRetries) {
                                                # Final attempt failed, check if module is actually available now
                                                $retryCheck = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
                                                if ($retryCheck) {
                                                    Write-Verbose "Module $moduleName appears to be available despite installation error (Version: $($retryCheck.Version))"
                                                    $moduleResult.Available = $true
                                                    $moduleResult.Version = $retryCheck.Version.ToString()
                                                    $moduleResult.Error = "Installation completed with warnings after $retryAttempt retries: $($_.Exception.Message)"
                                                    $results.Errors += "Installation warning for '$moduleName': $($_.Exception.Message)"
                                                    $retrySuccess = $true
                                                }
                                                else {
                                                    $errorMsg = "Failed to install module '$moduleName' after $MaxRetries retries: $($_.Exception.Message)"
                                                    $moduleResult.Error = $errorMsg
                                                    $results.Errors += $errorMsg
                                                    Write-Error $errorMsg
                                                }
                                            }
                                        }
                                    }
                                }
                                else {
                                    $errorMsg = "Failed to install module '$moduleName': $($_.Exception.Message)"
                                    $moduleResult.Error = $errorMsg
                                    $results.Errors += $errorMsg
                                    Write-Error $errorMsg
                                    continue
                                }
                            }
                        }
                    }
                    
                    # Try to import the module if it's available
                    if ($moduleResult.Available) {
                        try {
                            Import-Module -Name $moduleName -Force -ErrorAction Stop
                            $moduleResult.Imported = $true
                            $results.ModulesImported += $moduleName
                            Write-Verbose "Successfully imported module: $moduleName"
                        }
                        catch {
                            # Check if it's a conflict issue and try alternative approach
                            if ($_.Exception.Message -like "*could not be loaded*" -or $_.Exception.Message -like "*in use*") {
                                Write-Verbose "Module import conflict detected for $moduleName, attempting alternative import"
                                
                                $importRetryAttempt = 0
                                $importSuccess = $false
                                
                                while ($importRetryAttempt -lt $MaxRetries -and -not $importSuccess) {
                                    $importRetryAttempt++
                                    Write-Verbose "Import retry attempt $importRetryAttempt of $MaxRetries for module: $moduleName"
                                    
                                    try {
                                        # Try removing and re-importing
                                        Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
                                        Start-Sleep -Seconds $RetryDelaySeconds
                                        Import-Module -Name $moduleName -Force -Global -ErrorAction Stop
                                        $moduleResult.Imported = $true
                                        $results.ModulesImported += $moduleName
                                        $importSuccess = $true
                                        Write-Verbose "Successfully imported module on retry $importRetryAttempt : $moduleName"
                                    }
                                    catch {
                                        Write-Verbose "Import retry $importRetryAttempt failed for $moduleName : $($_.Exception.Message)"
                                        if ($importRetryAttempt -eq $MaxRetries) {
                                            # Try to check if module functions are actually available
                                            if (Get-Command -Module $moduleName -ErrorAction SilentlyContinue) {
                                                Write-Verbose "Module $moduleName functions are available despite import error"
                                                $moduleResult.Imported = $true
                                                $results.ModulesImported += $moduleName
                                                $moduleResult.Error = "Import completed with warnings after $importRetryAttempt retries: $($_.Exception.Message)"
                                                $importSuccess = $true
                                            }
                                            else {
                                                $errorMsg = "Failed to import module '$moduleName' after $MaxRetries retries: $($_.Exception.Message)"
                                                $moduleResult.Error = $errorMsg
                                                $results.Errors += $errorMsg
                                                Write-Warning $errorMsg
                                            }
                                        }
                                    }
                                }
                            }
                            else {
                                $errorMsg = "Failed to import module '$moduleName': $($_.Exception.Message)"
                                $moduleResult.Error = $errorMsg
                                $results.Errors += $errorMsg
                                Write-Warning $errorMsg
                            }
                        }
                    }
                }
                catch {
                    $errorMsg = "Error processing module '$moduleName': $($_.Exception.Message)"
                    $moduleResult.Error = $errorMsg
                    $results.Errors += $errorMsg
                    Write-Error $errorMsg
                }
                
                $results.RequiredModules += [PSCustomObject]$moduleResult
            }
            
            # Final validation
            $availableCount = ($results.RequiredModules | Where-Object { $_.Available }).Count
            $importedCount = ($results.RequiredModules | Where-Object { $_.Imported }).Count
            
            Write-Verbose "Prerequisites check complete - Available: $availableCount/$($requiredModules.Count), Imported: $importedCount/$($requiredModules.Count)"
            
            if ($availableCount -eq $requiredModules.Count -and $importedCount -eq $requiredModules.Count) {
                Write-Verbose "All SecretStore prerequisites are satisfied"
            }
            else {
                Write-Warning "Some SecretStore prerequisites are not satisfied"
                $results.AllModulesAvailable = $false
            }
            
        }
        catch {
            $errorMsg = "Failed to check SecretStore prerequisites: $($_.Exception.Message)"
            $results.Errors += $errorMsg
            Write-Error $errorMsg -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Test-SecretStorePrerequisite - CorrelationId: $correlationId"
        return [PSCustomObject]$results
    }
}
