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

    .PARAMETER CorrelationId
        Unique identifier for operation tracking and correlation

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
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        # Robust count calculation for test environment compatibility - store once to avoid pipeline issues
        $script:searchBaseCount = if ($SearchBase -is [array]) { $SearchBase.Count } else { 1 }
        Write-Verbose "Starting sequential AD object retrieval from $($script:searchBaseCount) search bases"

        # Log bulk operation start
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Attempt' -SecurityContext @{
            SearchBaseCount = $script:searchBaseCount
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
        } -CorrelationId $CorrelationId

        # Initialize tracking variables
        $script:totalObjects = 0
        $script:successfulBases = 0
        $script:failedBases = 0
    }

    process {
        # Process each search base sequentially and track results
        $allResults = @()
        
        foreach ($searchBase in $SearchBase) {
            try {
                Write-Verbose "Processing search base: $searchBase"
                $searchResults = Get-ADObjectFromSearchBase -SearchBase $searchBase -IncludeInherited:$IncludeInherited -CorrelationId $CorrelationId
                
                if ($searchResults) {
                    $allResults += $searchResults
                    $script:successfulBases++
                    Write-Verbose "Successfully retrieved $(@($searchResults).Count) objects from $searchBase"
                } else {
                    $script:successfulBases++  # No objects but no error
                    Write-Verbose "No objects found in $searchBase (not an error)"
                }
            }
            catch {
                $script:failedBases++
                Write-Warning "Failed to process search base $searchBase : $($_.Exception.Message)"
                
                # Log the failure but continue processing
                Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Failure' -SecurityContext @{
                    FailedSearchBase = $searchBase
                    ErrorMessage = $_.Exception.Message
                    ContinueProcessing = $true
                } -CorrelationId $CorrelationId
            }
        }

        $script:totalObjects = $allResults.Count
        
        # Use stored count to avoid pipeline parameter issues
        Write-Verbose "Sequential processing completed: $($script:totalObjects) objects from $($script:successfulBases)/$($script:searchBaseCount) search bases"

        # Output results to pipeline
        $allResults | Write-Output
    }

    end {
        # Use stored count to avoid pipeline parameter issues
        
        # Log bulk operation completion
        Write-ADOperationSecurityLog -OperationName 'Get-ADObjectsSequential' -Outcome 'Success' -SecurityContext @{
            SearchBaseCount = $script:searchBaseCount
            SuccessfulBases = $script:successfulBases
            FailedBases = $script:failedBases
            TotalObjectsRetrieved = $script:totalObjects
            IncludeInherited = $IncludeInherited.IsPresent
            ProcessingType = 'Sequential'
            ADAccessType = 'BulkRetrieval'
            ResultSummary = "Retrieved $($script:totalObjects) objects from $($script:successfulBases)/$($script:searchBaseCount) search bases"
        } -CorrelationId $CorrelationId
    }
}
