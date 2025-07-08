function Get-StringHash {
    <#
    .SYNOPSIS
        Calculates hash of a string value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString,
        
        [Parameter()]
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256"
    )
    
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
        $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        $hashBytes = $hasher.ComputeHash($bytes)
        return [System.BitConverter]::ToString($hashBytes) -replace '-'
    } catch {
        Write-Error "Failed to compute hash: $($_.Exception.Message)"
        return $null
    } finally {
        if ($hasher) { $hasher.Dispose() }
    }
}
