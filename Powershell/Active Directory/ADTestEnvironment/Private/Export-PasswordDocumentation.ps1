function Export-PasswordDocumentation {
    <#
    .SYNOPSIS
        Exports password documentation to a timestamped file for service accounts

    .DESCRIPTION
        Creates a secure password documentation file with timestamped filename containing 
        service account names and their generated passwords. This is used for secure 
        password distribution and documentation purposes.

    .PARAMETER PasswordData
        Array of objects containing password information to export.
        Each object should have: ServiceAccountName, Password, CreatedDate

    .PARAMETER OutputDirectory
        Directory where the password file should be created. Defaults to current location.

    .PARAMETER FilePrefix
        Prefix for the password file name. Defaults to "ServiceAccountPW"

    .PARAMETER IncludeWarnings
        Include security warnings in the exported file

    .EXAMPLE
        $passwordData = @(
            @{ ServiceAccountName = 'svc-app1'; Password = 'SecurePass123!'; CreatedDate = Get-Date }
            @{ ServiceAccountName = 'svc-db1'; Password = 'AnotherPass456@'; CreatedDate = Get-Date }
        )
        Export-PasswordDocumentation -PasswordData $passwordData

        Exports passwords to a timestamped file in the current directory

    .EXAMPLE
        Export-PasswordDocumentation -PasswordData $passwordExports -OutputDirectory "C:\SecureLocation" -FilePrefix "Prod-ServiceAccounts"

        Exports passwords to a custom location with custom filename prefix

    .OUTPUTS
        String containing the full path to the created password file

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
        
        SECURITY CONSIDERATIONS:
        - Password files should be stored securely and deleted after distribution
        - File permissions should be restricted to authorized personnel only
        - Consider using encrypted storage or secure file transfer methods
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [array]$PasswordData,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = (Get-Location).Path,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$FilePrefix = "ServiceAccountPW",
        
        [Parameter()]
        [switch]$IncludeWarnings = $true
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Export-PasswordDocumentation - CorrelationId: $correlationId"
        
        # Validate output directory
        if (-not (Test-Path $OutputDirectory)) {
            try {
                New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
                Write-Verbose "Created output directory: $OutputDirectory"
            }
            catch {
                throw "Failed to create output directory '$OutputDirectory': $($_.Exception.Message)"
            }
        }
    }

    process {
        try {
            # Create timestamped filename
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $fileName = "$FilePrefix-$timestamp.txt"
            $filePath = Join-Path $OutputDirectory $fileName
            
            Write-Verbose "Creating password documentation file: $filePath"
            
            # Build export content
            $exportContent = @()
            
            # Add header with metadata
            $exportContent += "# $FilePrefix Password Documentation"
            $exportContent += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $exportContent += "# Total Accounts: $($PasswordData.Count)"
            $exportContent += "# Correlation ID: $correlationId"
            
            if ($IncludeWarnings) {
                $exportContent += ""
                $exportContent += "# =========================================="
                $exportContent += "# SECURITY WARNING"
                $exportContent += "# =========================================="
                $exportContent += "# This file contains sensitive password information"
                $exportContent += "# - Store securely with restricted access permissions"
                $exportContent += "# - Delete after passwords are distributed/changed"
                $exportContent += "# - Do not transmit via unsecured channels"
                $exportContent += "# - Log access and distribution for audit purposes"
                $exportContent += "# =========================================="
            }
            
            $exportContent += ""
            $exportContent += "# Password Information"
            $exportContent += "# Format: Account | Password | Created Date"
            $exportContent += ""
            
            # Process each password entry
            foreach ($entry in $PasswordData) {
                # Validate required properties
                if (-not $entry.ServiceAccountName) {
                    Write-Warning "Skipping entry with missing ServiceAccountName"
                    continue
                }
                if (-not $entry.Password) {
                    Write-Warning "Skipping entry with missing Password for account: $($entry.ServiceAccountName)"
                    continue
                }
                
                # Set default created date if not provided
                $createdDate = if ($entry.CreatedDate) { 
                    $entry.CreatedDate 
                } else { 
                    Get-Date 
                }
                
                # Add account information
                $exportContent += "Account: $($entry.ServiceAccountName)"
                $exportContent += "Password: $($entry.Password)"
                $exportContent += "Created: $($createdDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                
                # Add additional properties if available
                if ($entry.Description) {
                    $exportContent += "Description: $($entry.Description)"
                }
                if ($entry.Department) {
                    $exportContent += "Department: $($entry.Department)"
                }
                if ($entry.ExpirationDate) {
                    $exportContent += "Expires: $($entry.ExpirationDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                }
                
                $exportContent += ""  # Blank line between entries
            }
            
            # Write content to file
            try {
                $exportContent | Out-File -FilePath $filePath -Encoding UTF8 -ErrorAction Stop
                Write-Verbose "Password documentation written to: $filePath"
                
                # Set restrictive file permissions (Windows)
                if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
                    try {
                        # Remove inheritance and set restricted permissions
                        $acl = Get-Acl $filePath
                        $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, don't copy existing
                        
                        # Add only current user and administrators
                        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                        $adminGroup = "BUILTIN\Administrators"
                        
                        $accessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")
                        $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($adminGroup, "FullControl", "Allow")
                        
                        $acl.RemoveAccessRuleAll((New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")))
                        $acl.RemoveAccessRuleAll((New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "ReadAndExecute", "Allow")))
                        
                        $acl.SetAccessRule($accessRule1)
                        $acl.SetAccessRule($accessRule2)
                        
                        Set-Acl -Path $filePath -AclObject $acl
                        Write-Verbose "Restrictive file permissions applied to: $filePath"
                    }
                    catch {
                        Write-Warning "Failed to set restrictive permissions on password file: $($_.Exception.Message)"
                    }
                }
                
                # Return the file path
                return $filePath
                
            }
            catch {
                throw "Failed to write password documentation file '$filePath': $($_.Exception.Message)"
            }
            
        }
        catch {
            Write-Error "Failed to export password documentation: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Export-PasswordDocumentation - CorrelationId: $correlationId"
    }
}

function New-PasswordExportEntry {
    <#
    .SYNOPSIS
        Creates a standardized password export entry object

    .DESCRIPTION
        Helper function to create a consistent password export entry object
        that can be used with Export-PasswordDocumentation.

    .PARAMETER ServiceAccountName
        Name of the service account

    .PARAMETER Password
        Generated password for the account

    .PARAMETER CreatedDate
        Date when the account/password was created. Defaults to current date.

    .PARAMETER Description
        Optional description for the service account

    .PARAMETER Department
        Optional department information

    .PARAMETER ExpirationDate
        Optional password expiration date

    .EXAMPLE
        $entry = New-PasswordExportEntry -ServiceAccountName "svc-app1" -Password "SecurePass123!"
        Creates a basic password export entry

    .EXAMPLE
        $entry = New-PasswordExportEntry -ServiceAccountName "svc-db1" -Password "DatabasePass456@" -Description "Database service account" -Department "IT"
        Creates a detailed password export entry

    .OUTPUTS
        PSCustomObject containing standardized password export entry

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,
        
        [Parameter()]
        [DateTime]$CreatedDate = (Get-Date),
        
        [Parameter()]
        [string]$Description,
        
        [Parameter()]
        [string]$Department,
        
        [Parameter()]
        [DateTime]$ExpirationDate
    )

    $entry = [PSCustomObject]@{
        ServiceAccountName = $ServiceAccountName
        Password = $Password
        CreatedDate = $CreatedDate
    }
    
    # Add optional properties if provided
    if ($Description) {
        $entry | Add-Member -NotePropertyName 'Description' -NotePropertyValue $Description
    }
    if ($Department) {
        $entry | Add-Member -NotePropertyName 'Department' -NotePropertyValue $Department
    }
    if ($ExpirationDate) {
        $entry | Add-Member -NotePropertyName 'ExpirationDate' -NotePropertyValue $ExpirationDate
    }
    
    return $entry
}
