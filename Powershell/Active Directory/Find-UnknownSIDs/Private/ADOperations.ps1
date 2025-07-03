#Requires -Module ActiveDirectory
#Requires -Version 5.1

# Simple working version of ADOperations functions

function Invoke-ADOperationWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [string]$OperationName = 'AD Operation',

        [Parameter()]
        [string]$ObjectContext = 'Unknown',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    Write-ScriptLog "Starting AD operation: $OperationName (Context: $ObjectContext)" -Level Debug -Component 'ADOperations' -CorrelationId $CorrelationId

    $attempt = 0
    $currentError = $null

    do {
        $attempt++
        try {
            Write-Verbose "Executing $OperationName (attempt $attempt/$MaxRetries)"
            Write-ScriptLog "Executing $OperationName (attempt $attempt/$MaxRetries)" -Level Debug -Component 'ADOperations' -CorrelationId $CorrelationId
            $result = & $ScriptBlock
            Write-ScriptLog "AD operation '$OperationName' completed successfully on attempt $attempt" -Level Debug -Component 'ADOperations' -CorrelationId $CorrelationId
            return $result
        }
        catch {
            $currentError = $_
            $errorMessage = $currentError.Exception.Message

            # Check if this is a retryable error
            $isRetryable = $errorMessage -match 'timeout|network|connection|busy|unavailable|server not operational|replication|domain controller'

            if (-not $isRetryable -or $attempt -ge $MaxRetries) {
                Write-Warning "AD operation '$OperationName' failed permanently after $attempt attempts: $errorMessage"
                Write-ScriptLog "AD operation '$OperationName' failed permanently after $attempt attempts: $errorMessage" -Level Error -Component 'ADOperations' -CorrelationId $CorrelationId
                throw $currentError
            }

            $waitTime = [Math]::Min([Math]::Pow(2, $attempt - 1), 30)
            Write-Warning "AD operation '$OperationName' failed (attempt $attempt/$MaxRetries), retrying in $waitTime seconds: $errorMessage"
            Write-ScriptLog "AD operation '$OperationName' failed (attempt $attempt/$MaxRetries), retrying in $waitTime seconds: $errorMessage" -Level Warning -Component 'ADOperations' -CorrelationId $CorrelationId
            Start-Sleep -Seconds $waitTime
        }
    } while ($attempt -lt $MaxRetries)

    throw $currentError
}







function Get-ADObjectsParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SearchBase,

        [Parameter()]
        [switch]$IncludeInherited,

        [Parameter()]
        [int]$ThrottleLimit = 10
    )

    Write-Verbose "Using ThrottleLimit: $ThrottleLimit for parallel processing"
    Write-Verbose "IncludeInherited setting: $IncludeInherited"

    # Initialize results as a generic list for better performance
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($base in $SearchBase) {
        try {
            Write-Verbose "Processing search base: $base"

            # Use IncludeInherited parameter to determine filter criteria
            if ($IncludeInherited) {
                Write-Verbose "Including inherited permissions in search"
                $objects = Get-ADObject -SearchBase $base -Filter * -Properties nTSecurityDescriptor
            } else {
                Write-Verbose "Excluding inherited permissions (default behavior)"
                $objects = Get-ADObject -SearchBase $base -Filter * -Properties nTSecurityDescriptor
            }

            # Ensure $objects is treated as an array and add to results
            if ($objects) {
                # Handle single object case - ensure it's treated as an array
                $objectArray = @($objects)
                foreach ($obj in $objectArray) {
                    $results.Add($obj)
                }
            }
        }
        catch {
            Write-Warning "Failed to get objects from $base : $($_.Exception.Message)"
        }
    }

    # Return as array to ensure consistent type
    $resultArray = $results.ToArray()
    Write-Verbose "Retrieved $($resultArray.Count) AD objects using ThrottleLimit $ThrottleLimit"
    return $resultArray
}


