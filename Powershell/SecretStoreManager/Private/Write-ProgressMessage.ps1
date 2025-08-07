function Write-ProgressMessage {
    <#
    .SYNOPSIS
        Writes progress and status messages using appropriate PowerShell streams.

    .DESCRIPTION
        Provides a unified way to write progress, status, and informational messages
        using appropriate PowerShell output streams instead of Write-Host. Compatible
        with PowerShell 5.1+ and supports both interactive and automation scenarios.

    .PARAMETER Message
        The message to display.

    .PARAMETER Type
        The type of message to write. Valid values are:
        - Information: Uses Write-Information (PS 5.0+) or Write-Output
        - Progress: Uses Write-Verbose for detailed progress tracking
        - Warning: Uses Write-Warning
        - Error: Uses Write-Error
        - Success: Uses Write-Information with success context
        - Debug: Uses Write-Debug for diagnostic information

    .PARAMETER Category
        Optional category for the message (e.g., 'VaultCreation', 'SecretStorage').

    .PARAMETER CorrelationId
        Optional correlation ID for tracking related operations.

    .PARAMETER Quiet
        Suppresses all output except errors and warnings.

    .EXAMPLE
        Write-ProgressMessage -Message "Vault created successfully" -Type Success

        Writes a success message using the Information stream.

    .EXAMPLE
        Write-ProgressMessage -Message "Creating vault with SecretStore provider" -Type Progress -Category "VaultCreation"

        Writes a progress message with categorization.

    .NOTES
        Author: SecretStoreManager Team
        Version: 1.0.0
        Compatible: PowerShell 5.1+
        
        This function replaces Write-Host usage throughout the module to provide
        better stream handling and automation compatibility.
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Progress', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Type,

        [Parameter()]
        [string]$Category,

        [Parameter()]
        [string]$CorrelationId,

        [Parameter()]
        [switch]$Quiet
    )

    begin {
        # Don't output anything if Quiet is specified (except errors/warnings)
        if ($Quiet -and $Type -notin @('Error', 'Warning')) {
            return
        }

        # Build message with optional context
        $formattedMessage = $Message
        if ($Category) {
            $formattedMessage = "[$Category] $formattedMessage"
        }
        if ($CorrelationId) {
            $formattedMessage = "$formattedMessage (CorrelationId: $CorrelationId)"
        }
    }

    process {
        switch ($Type) {
            'Information' {
                # Use Write-Information if available (PS 5.0+), otherwise Write-Output
                if (Get-Command Write-Information -ErrorAction SilentlyContinue) {
                    Write-Information $formattedMessage -InformationAction Continue
                } else {
                    Write-Output $formattedMessage
                }
            }
            'Progress' {
                Write-Verbose $formattedMessage
            }
            'Warning' {
                Write-Warning $formattedMessage
            }
            'Error' {
                Write-Error $formattedMessage
            }
            'Success' {
                # Success messages go to Information stream
                if (Get-Command Write-Information -ErrorAction SilentlyContinue) {
                    Write-Information $formattedMessage -InformationAction Continue
                } else {
                    Write-Output $formattedMessage
                }
            }
            'Debug' {
                Write-Debug $formattedMessage
            }
        }
    }
}
