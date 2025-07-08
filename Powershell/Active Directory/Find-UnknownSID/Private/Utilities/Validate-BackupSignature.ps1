function Validate-BackupSignature {
    <#
    .SYNOPSIS
        Validates backup signature for security
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Signature,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $validSignatures = @(
        "PSSecurityBackup_v2.1",
        "PSSecurityBackup_v2.0",
        "PowerShellSecurityBackup"
    )

    $result = [PSCustomObject]@{
        Valid = $validSignatures -contains $Signature
        SecurityRisk = $false
        CorrelationId = $CorrelationId
    }

    if (-not $result.Valid) {
        $result.SecurityRisk = $true
    }

    return $result
}
