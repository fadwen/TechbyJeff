function Get-ADTestDomain {
    <#
    .SYNOPSIS
        Gets the current AD domain information for test data operations
    
    .DESCRIPTION
        Automatically detects the current Active Directory domain and returns
        the domain DN and DNS name for use in test data creation operations
    
    .OUTPUTS
        Hashtable with DomainDN and DNSName properties
    
    .EXAMPLE
        $domain = Get-ADTestDomain
        Write-Host "Domain: $($domain.DNSName)"

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        # Try environment variable first
        $dnsDomain = $env:USERDNSDOMAIN
        if ([string]::IsNullOrEmpty($dnsDomain)) {
            # Get domain from AD module
            $currentDomain = Get-ADDomain -Current LocalComputer -ErrorAction SilentlyContinue
            if ($currentDomain) {
                $dnsDomain = $currentDomain.DNSRoot
            }
        }
        
        if ($dnsDomain) {
            $split = $dnsDomain.split(".")
            if ($split.Count -eq 3) {
                $domainDN = "DC=$($split[0]),DC=$($split[1]),DC=$($split[2])"
            } elseif ($split.Count -eq 2) {
                $domainDN = "DC=$($split[0]),DC=$($split[1])"
            } else {
                $domainDN = "DC=$($split[0])"
            }
            
            Write-Verbose "Detected domain: $dnsDomain (DN: $domainDN)" 
            
            return @{
                DNSName = $dnsDomain
                DomainDN = $domainDN
            }
        } else {
            throw "Could not detect domain"
        }
    } catch {
        throw "Failed to detect domain: $($_.Exception.Message). Please ensure this is run on a domain-joined machine with AD PowerShell module."
    }
}
