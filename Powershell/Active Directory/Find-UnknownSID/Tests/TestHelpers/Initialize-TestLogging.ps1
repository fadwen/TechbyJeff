<#
.SYNOPSIS
    Initializes the logging system for test scenarios

.DESCRIPTION
    Sets up the logging system with test-safe defaults to support
    unit testing of functions that depend on the logging infrastructure.

.NOTES
    This script should be called at the beginning of test files
    that test functions with logging dependencies.
#>
[CmdletBinding()]
param()

# Import required logging functions
$loggingRoot = Join-Path $PSScriptRoot "..\..\Private\Logging"
$loggingFiles = @(
    "Format-LogMessage.ps1",
    "Write-StructuredLogEntry.ps1", 
    "Write-StructuredLog.ps1",
    "Initialize-LoggingSystem.ps1"
)

foreach ($file in $loggingFiles) {
    $filePath = Join-Path $loggingRoot $file
    if (Test-Path $filePath) {
        . $filePath
    } else {
        Write-Warning "Could not find logging file: $filePath"
    }
}

# Initialize logging system with test defaults
try {
    # Create a temporary log path for testing
    $tempLogPath = Join-Path $env:TEMP "TestLogging"
    if (-not (Test-Path $tempLogPath)) {
        New-Item -Path $tempLogPath -ItemType Directory -Force | Out-Null
    }
    
    # Use unique log file for each test run/job to avoid conflicts
    $processId = $PID
    $randomId = Get-Random
    $testLogFile = Join-Path $tempLogPath "test-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$processId-$randomId.log"
    
    # Initialize script-scoped variables that the logging system expects
    $script:CorrelationId = [System.Guid]::NewGuid().ToString()
    $script:LogLevel = 'Debug'
    $script:LogPath = $testLogFile
    $script:SuppressConsoleOutput = $true
    $script:LogFileInitialized = $false
    $script:LogFileReinitAttempted = $false
    
    # Initialize log levels hierarchy
    $script:LogLevels = @{
        'Critical' = 0
        'Error' = 1
        'Warning' = 2
        'Information' = 3
        'Debug' = 4
        'Verbose' = 5
    }
    
    # Initialize the logging system (only needs LogLevel and SuppressConsoleOutput)
    if (Get-Command Initialize-LoggingSystem -ErrorAction SilentlyContinue) {
        Initialize-LoggingSystem -LogLevel "Debug" -SuppressConsoleOutput
    }
    
    Write-Verbose "Test logging initialized to: $testLogFile"
} catch {
    Write-Warning "Failed to initialize test logging system: $($_.Exception.Message)"
}
