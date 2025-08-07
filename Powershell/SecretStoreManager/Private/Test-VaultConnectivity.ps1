# Vault Connectivity and Testing Functions
# Tests vault connectivity and provides diagnostic capabilities

function Test-VaultConnectivity {
    <#
    .SYNOPSIS
        Tests connectivity to a vault
        
    .DESCRIPTION
        Performs a connectivity test to verify that a vault is accessible
        and responsive. Measures response time and reports any access issues.
        
    .PARAMETER VaultName
        The name of the vault to test
        
    .EXAMPLE
        $result = Test-VaultConnectivity -VaultName 'MyVault'
        if ($result.IsAccessible) { Write-Information "Vault is accessible" -InformationAction Continue }
        
    .NOTES
        This function performs a minimal operation (listing secrets) to test connectivity
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )

    $result = @{
        VaultName = $VaultName
        IsAccessible = $false
        ResponseTime = $null
        Errors = @()
        Warnings = @()
    }

    try {
        $startTime = Get-Date
        
        # Try to list secrets (minimal operation to test connectivity)
        $secrets = Get-SecretInfo -Vault $VaultName -ErrorAction Stop
        
        $endTime = Get-Date
        $result.ResponseTime = ($endTime - $startTime).TotalMilliseconds
        $result.IsAccessible = $true
        
        Write-Verbose "Vault '$VaultName' is accessible. Found $($secrets.Count) secrets. Response time: $($result.ResponseTime)ms"
        
    }
    catch {
        $result.Errors += $_.Exception.Message
        Write-Warning "Vault '$VaultName' is not accessible: $($_.Exception.Message)"
    }

    return $result
}
