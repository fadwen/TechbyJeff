function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$Level = "Information",

        [Parameter()]
        [string]$Component = 'General',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [hashtable]$Data = @{}
    )

    # Call the actual logging function with all parameters
    $params = @{
        Message = $Message
        Level = $Level
        Component = $Component
        CorrelationId = $CorrelationId
        Details = $Data
    }

    if ($LogPath) {
        $params.LogPath = $LogPath
    }

    Write-StructuredLogEntry @params
}
