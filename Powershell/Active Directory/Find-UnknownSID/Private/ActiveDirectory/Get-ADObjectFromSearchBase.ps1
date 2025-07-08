function Get-ADObjectFromSearchBase {
    <#
    .SYNOPSIS
        Retrieves Active Directory objects from a single search base

    .DESCRIPTION
        Performs AD object retrieval from a specified search base with proper
        error handling and security descriptor inclusion. Designed for pipeline efficiency.

    .PARAMETER SearchBase
        The distinguished name of the search base

    .PARAMETER IncludeInherited
        Whether to include inherited permissions in security descriptors

    .PARAMETER Properties
        Additional properties to retrieve (nTSecurityDescriptor always included)

    .EXAMPLE
        PS> Get-ADObjectFromSearchBase -SearchBase "OU=Users,DC=contoso,DC=com"

        DESCRIPTION: Retrieves all AD objects from the Users OU
        OUTPUT: Collection of AD objects with security descriptors
        USE CASE: Scanning specific organizational units for security analysis

    .EXAMPLE
        PS> @("OU=Users,DC=contoso,DC=com", "OU=Groups,DC=contoso,DC=com") | Get-ADObjectFromSearchBase

        DESCRIPTION: Pipeline processing of multiple search bases
        OUTPUT: Combined collection from all search bases
        USE CASE: Bulk processing of multiple organizational units

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For search base issues: .\Troubleshooting\Common\SearchBase-Problems.md
        - For permission issues: .\Troubleshooting\Security\Permission-Errors.md
    #>

    [CmdletBinding()]
    [OutputType('Microsoft.ActiveDirectory.Management.ADObject')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string[]]$Properties = @('nTSecurityDescriptor'),

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    process {
        try {
            Write-Verbose "Retrieving AD objects from search base: $SearchBase"

            # Ensure nTSecurityDescriptor is always included
            $allProperties = @($Properties) + @('nTSecurityDescriptor') | Sort-Object -Unique

            # Execute AD query
            $objects = Get-ADObject -SearchBase $SearchBase -Filter * -Properties $allProperties -ErrorAction Stop

            # Output to pipeline for efficiency
            if ($objects) {
                foreach ($obj in @($objects)) {
                    Write-Output $obj
                }
            }

            Write-Verbose "Retrieved $(@($objects).Count) objects from search base: $SearchBase"
        }
        catch {
            Write-Warning "Failed to retrieve objects from search base '$SearchBase': $($_.Exception.Message)"

            # Don't throw - let pipeline continue with other search bases
            # Log error for troubleshooting
            Write-Verbose "Search base error details: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        }
    }
}
