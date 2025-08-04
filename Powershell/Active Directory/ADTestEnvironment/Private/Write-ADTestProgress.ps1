function Write-ADTestProgress {
    <#
    .SYNOPSIS
        Writes standardized progress messages for AD test operations
    
    .DESCRIPTION
        Provides consistent formatting for progress messages during test data operations
    
    .PARAMETER Message
        The progress message to display
    
    .PARAMETER Type
        Type of message (Info, Warning, Error, Success)
    
    .EXAMPLE
        Write-ADTestProgress -Message "Creating user accounts..." -Type Info

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Header')]
        [string]$Type = 'Info'
    )
    
    switch ($Type) {
        'Header' {
            Write-Host "`n=========================================" -ForegroundColor Cyan
            Write-Host "   $Message" -ForegroundColor Cyan
            Write-Host "=========================================" -ForegroundColor Cyan
        }
        'Info' {
            Write-Host $Message -ForegroundColor Green
        }
        'Warning' {
            Write-Host $Message -ForegroundColor Yellow
        }
        'Error' {
            Write-Host $Message -ForegroundColor Red
        }
        'Success' {
            Write-Host $Message -ForegroundColor Green
        }
    }
}
