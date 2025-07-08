function Format-LogMessage {
    <#
    .SYNOPSIS
        Formats log messages according to specified style and requirements
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose', 'INFO')]
        [string]$Level,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'General',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

        [Parameter()]
        [ValidateSet('JSON', 'PlainText', 'CSV', 'XML')]
        [string]$Format = 'JSON',

        [Parameter()]
        [hashtable]$AdditionalData = @{}
    )

    # Normalize INFO to Information
    if ($Level -eq 'INFO') {
        $Level = 'Information'
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"
    
    $logData = [PSCustomObject]@{
        Timestamp = $timestamp
        Level = $Level
        Component = $Component
        CorrelationId = $CorrelationId
        Message = $Message
    }

    # Add additional data
    if ($AdditionalData.Count -gt 0) {
        foreach ($key in $AdditionalData.Keys) {
            $logData | Add-Member -MemberType NoteProperty -Name $key -Value $AdditionalData[$key] -Force
        }
    }

    switch ($Format) {
        'JSON' {
            return $logData | ConvertTo-Json -Compress
        }
        'PlainText' {
            return "[$timestamp] [$Level] [$Component] [$CorrelationId] $Message"
        }
        'CSV' {
            return "$timestamp,$Level,$Component,$CorrelationId,`"$Message`""
        }
        'XML' {
            return $logData | ConvertTo-Xml -NoTypeInformation -As String
        }
        default {
            return $logData | ConvertTo-Json -Compress
        }
    }
}
