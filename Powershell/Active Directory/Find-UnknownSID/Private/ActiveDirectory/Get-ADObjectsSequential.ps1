function Get-ADObjectsSequential {
    <#
    .SYNOPSIS
        Retrieves Active Directory objects from multiple search bases sequentially

    .DESCRIPTION
        Processes multiple AD search bases in sequence with comprehensive logging
        and error handling. Optimized for reliability over speed.

    .PARAMETER SearchBase
        Array of distinguished names to search

    .PARAMETER IncludeInherited
        Whether to include inherited permissions in security descriptors

    .EXAMPLE
        PS> Get-ADObjectsSequential -SearchBase @("OU=Users,DC=contoso,DC=com", "OU=Groups,DC=contoso,DC=com")

        DESCRIPTION: Sequentially processes multiple organizational units
        OUTPUT: Combined collection of AD objects from all search bases
        USE CASE: Reliable bulk processing when parallel processing isn't required

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For performance optimization: .\Troubleshooting\Performance\Sequential-Optimization.md
        - For bulk operation issues: .\Troubleshooting\Common\Bulk-Processing.md
    #>

    [CmdletBinding()]
    [OutputType('Microsoft.ActiveDirectory.Management.ADObject')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Starting sequential AD object retrieval from $($SearchBase.Count) search bases"

        # Log bulk operation start
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Attempt' -SecurityContext @{
            SearchBaseCount = $SearchBase.Count
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
        } -CorrelationId $CorrelationId

        $totalObjects = 0
        $successfulBases = 0
        $failedBases = 0
    }

    process {
        # Use pipeline for efficiency - no manual collection building
        $results = $SearchBase | Get-ADObjectFromSearchBase -IncludeInherited:$IncludeInherited

        # Count results for reporting
        $resultArray = @($results)
        $totalObjects = $resultArray.Count

        # Calculate success/failure rates
        $successfulBases = ($SearchBase | ForEach-Object {
            try {
                Get-ADObject -SearchBase $_ -Filter * -Properties nTSecurityDescriptor -ErrorAction Stop | Out-Null
                return $true
            }
            catch {
                return $false
            }
        } | Where-Object { $_ }).Count

        $failedBases = $SearchBase.Count - $successfulBases

        Write-Verbose "Sequential processing completed: $totalObjects objects from $successfulBases/$($SearchBase.Count) search bases"

        # Output results to pipeline
        $resultArray | Write-Output
    }

    end {
        # Log bulk operation completion
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Success' -SecurityContext @{
            SearchBaseCount = $SearchBase.Count
            SuccessfulBases = $successfulBases
            FailedBases = $failedBases
            ObjectsRetrieved = $totalObjects
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
            ResultSummary = "Retrieved $totalObjects objects from $successfulBases/$($SearchBase.Count) search bases"
        } -CorrelationId $CorrelationId
    }
}
