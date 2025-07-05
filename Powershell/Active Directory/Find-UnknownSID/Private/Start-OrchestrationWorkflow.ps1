#Requires -Version 5.1

<#
.SYNOPSIS
    High-level workflow coordination for Find-UnknownSID operations

.DESCRIPTION
    Provides lightweight orchestration and coordination between focused
    processing modules. Acts as the central coordinator that delegates
    to specialized functions while maintaining workflow integrity.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-04
    Version: 2.0.0

    TROUBLESHOOTING:
    - For orchestration issues: .\Troubleshooting\Common\Orchestration-Issues.md
    - For workflow coordination: .\Troubleshooting\Common\Workflow-Issues.md
#>


function Start-OrchestrationWorkflow {
    <#
    .SYNOPSIS
        Coordinates high-level workflow between processing modules

    .DESCRIPTION
        Acts as the central coordinator for Find-UnknownSID operations,
        delegating to specialized functions while maintaining workflow
        integrity and proper error handling.

        BUSINESS VALUE:
        - Provides consistent workflow execution across operations
        - Ensures proper initialization and cleanup sequences
        - Maintains audit trail continuity across modules
        - Enables centralized error handling and reporting
        - Supports enterprise workflow standards

        COORDINATION FEATURES:
        - Module dependency management and initialization
        - Workflow decision routing based on operation type
        - Centralized correlation ID propagation
        - Consistent error handling across all modules
        - Proper resource cleanup and finalization

    .PARAMETER OperationType
        [String] (Mandatory) Type of operation to coordinate.
        Valid values: 'Discovery', 'Removal', 'Restore'

    .PARAMETER Parameters
        [Hashtable] (Mandatory) Parameters to pass to the selected workflow.
        Must contain all required parameters for the specified operation type.

    .PARAMETER CorrelationId
        [String] (Optional) Correlation ID for tracking this workflow.
        Auto-generated if not provided for audit purposes.

    .OUTPUTS
        [Object] Results from the coordinated workflow operation.
        Type varies based on OperationType specified.

    .EXAMPLE
        PS> Start-OrchestrationWorkflow -OperationType 'Discovery' -Parameters @{SearchBase='OU=Users,DC=contoso,DC=com'}

        DESCRIPTION: Coordinate discovery workflow
        OUTPUT: Discovery results from main processing logic
        USE CASE: Standard orphaned SID discovery operation

    .EXAMPLE
        PS> Start-OrchestrationWorkflow -OperationType 'Restore' -Parameters @{SearchBase=@('CN=User1,CN=Users,DC=contoso,DC=com'); BackupPath='C:\Backups'}

        DESCRIPTION: Coordinate restore workflow
        OUTPUT: Restore operation results
        USE CASE: ACL restoration from backup files

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        TROUBLESHOOTING:
        - For orchestration issues: .\Troubleshooting\Common\Orchestration-Issues.md
        - For workflow coordination: .\Troubleshooting\Common\Workflow-Issues.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Discovery', 'Removal', 'Restore')]
        [string]$OperationType,

        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-StructuredLog "Starting orchestration workflow: $OperationType" -Level Information -Component 'Orchestration' -CorrelationId $CorrelationId

        # Load required modules for restore operations
        if ($OperationType -eq 'Restore') {
            if (-not (Get-Command Invoke-RestoreWorkflow -ErrorAction SilentlyContinue)) {
                . $PSScriptRoot\Restore\Invoke-RestoreWorkflow.ps1
            }
        }

        # Ensure CorrelationId is propagated to all operations
        if (-not $Parameters.ContainsKey('CorrelationId')) {
            $Parameters.CorrelationId = $CorrelationId
        }
    }

    process {
        try {
            switch ($OperationType) {
                'Discovery' {
                    Write-StructuredLog "Coordinating discovery workflow" -Level Debug -Component 'Orchestration' -CorrelationId $CorrelationId
                    return Invoke-MainProcessingLogic @Parameters
                }
                'Removal' {
                    Write-StructuredLog "Coordinating removal workflow" -Level Debug -Component 'Orchestration' -CorrelationId $CorrelationId
                    # Add Remove switch for removal operations
                    $Parameters.Remove = $true
                    return Invoke-MainProcessingLogic @Parameters
                }
                'Restore' {
                    Write-StructuredLog "Coordinating restore workflow" -Level Debug -Component 'Orchestration' -CorrelationId $CorrelationId

                    # Map parameters from main script format to restore workflow format
                    $restoreParams = @{}

                    # Map TargetObjectDN (individual object for restore)
                    if ($Parameters.ContainsKey('TargetObjectDN')) {
                        $restoreParams.TargetObjectDN = $Parameters.TargetObjectDN
                    }

                    # Map BackupPath
                    if ($Parameters.ContainsKey('BackupPath')) {
                        $restoreParams.BackupPath = $Parameters.BackupPath
                    }

                    # Map CorrelationId
                    if ($Parameters.ContainsKey('CorrelationId')) {
                        $restoreParams.CorrelationId = $Parameters.CorrelationId
                    }

                    # Map WhatIf parameter
                    if ($Parameters.ContainsKey('WhatIf') -and $Parameters.WhatIf) {
                        $restoreParams.WhatIf = $true
                    }

                    return Invoke-RestoreWorkflow @restoreParams
                }
                default {
                    throw "Unsupported operation type: $OperationType"
                }
            }
        }
        catch {
            Write-StructuredLog "Orchestration workflow failed for $OperationType : $($_.Exception.Message)" -Level Error -Component 'Orchestration' -CorrelationId $CorrelationId
            throw
        }
        finally {
            Write-StructuredLog "Orchestration workflow completed: $OperationType" -Level Information -Component 'Orchestration' -CorrelationId $CorrelationId
        }
    }
}
