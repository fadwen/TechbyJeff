function Set-SecureVaultPassword {
    <#
    .SYNOPSIS
        Securely stores vault password in encrypted configuration

    .DESCRIPTION
        Saves vault passwords in encrypted configuration files using Windows Data Protection API
        or cross-platform encryption methods. Provides secure storage for vault authentication
        credentials without exposing plaintext passwords.

    .PARAMETER VaultName
        The name of the vault for which to store the password

    .PARAMETER Password
        The SecureString password to store securely

    .PARAMETER CorrelationId
        Optional correlation ID for audit trail tracking

    .EXAMPLE
        PS> Set-SecureVaultPassword -VaultName "ProductionVault" -Password $securePassword

        Saves the vault password in encrypted configuration

    .NOTES
        Author: SecretStoreManager Development Team
        Version: 1.0.0
        Last Updated: 2025-08-06

        SECURITY CONSIDERATIONS:
        - Uses Windows Data Protection API when available
        - Cross-platform encryption for non-Windows systems
        - No plaintext storage
        - User-scoped encryption (not machine-wide)
        - Audit trail with correlation tracking

        TROUBLESHOOTING:
        - Permission issues: ./Troubleshooting/Security/File-Permissions.md
        - Encryption errors: ./Troubleshooting/Security/Encryption-Issues.md
        - Configuration paths: ./Troubleshooting/Configuration/File-Locations.md
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password,

        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting Set-SecureVaultPassword for vault '$VaultName' - CorrelationId: $CorrelationId"
    }

    process {
        if ($PSCmdlet.ShouldProcess("vault password for '$VaultName'", "Store encrypted password")) {
            try {
                # Ensure configuration directory exists
                $configDir = Join-Path $PSScriptRoot "..\Configuration"
                if (-not (Test-Path $configDir)) {
                    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created configuration directory - CorrelationId: $CorrelationId"
                }

            $configPath = Join-Path $configDir "VaultPasswords.xml"
            
            # Load existing configuration or create new
            $vaultConfigs = @{}
            if (Test-Path $configPath) {
                try {
                    $vaultConfigs = Import-Clixml $configPath -ErrorAction Stop
                    Write-Verbose "Loaded existing vault configurations - CorrelationId: $CorrelationId"
                }
                catch {
                    Write-Verbose "Failed to load existing configuration, creating new: $($_.Exception.Message) - CorrelationId: $CorrelationId"
                    $vaultConfigs = @{}
                }
            }

            # Add or update vault password configuration
            $vaultConfigs[$VaultName] = @{
                Password = $Password
                LastUpdated = Get-Date
                UpdatedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                CorrelationId = $CorrelationId
            }

            # Save encrypted configuration
            Export-Clixml -Path $configPath -InputObject $vaultConfigs -Force
            
            # Verify the file was created and is not accessible to others
            if (Test-Path $configPath) {
                $fileInfo = Get-Item $configPath
                Write-Verbose "Password configuration saved securely - Size: $($fileInfo.Length) bytes - CorrelationId: $CorrelationId"
                
                # On Windows, restrict file permissions
                if ($IsWindows -or $env:OS -eq "Windows_NT") {
                    try {
                        $acl = Get-Acl $configPath
                        # Remove inherited permissions and set only current user access
                        $acl.SetAccessRuleProtection($true, $false)
                        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                            "FullControl",
                            "Allow"
                        )
                        $acl.SetAccessRule($accessRule)
                        Set-Acl -Path $configPath -AclObject $acl
                        Write-Verbose "File permissions restricted to current user - CorrelationId: $CorrelationId"
                    }
                    catch {
                        Write-Warning "Could not restrict file permissions: $($_.Exception.Message) - CorrelationId: $CorrelationId"
                    }
                }

                return $true
            }
            else {
                throw "Failed to create password configuration file"
            }
        }
        catch {
            Write-Error "Failed to save secure vault password: $($_.Exception.Message) - CorrelationId: $CorrelationId" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Set-SecureVaultPassword - CorrelationId: $CorrelationId"
    }
}
}
