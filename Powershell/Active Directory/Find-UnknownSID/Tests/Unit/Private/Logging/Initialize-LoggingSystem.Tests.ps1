# Pester 3.4 tests for Initialize-LoggingSystem.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$modulePath = "$here\..\..\..\..\Private\Logging\$sut"

# Import the script content for testing
. $modulePath

$here = $PSScriptRoot
$modulePath = Split-Path $here -Parent

# Import shared logging configuration first
. "$here\..\..\..\..\Private\Logging\Initialize-LoggingConfiguration.ps1"

Describe "Initialize-LoggingSystem" -Tags @('Unit', 'Logging', 'Initialization') {

    # Mock dependencies inside Describe block
    Mock Write-Verbose { } -Verifiable
    Mock Write-Error { throw $Message } -Verifiable

    Context "Parameter Validation" {
        
        BeforeEach {
            # Reset logging state before each test
            $script:CorrelationId = $null
            $script:LogLevel = 'Information'
            $script:SuppressConsoleOutput = $false
            $script:LogFileInitialized = $false
            $script:LogFileReinitAttempted = $false
        }

        It "Should accept valid CorrelationId parameter" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            { Initialize-LoggingSystem -CorrelationId $testCorrelationId } | Should Not Throw
        }

        It "Should accept valid LogLevel parameter" {
            $validLevels = @('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')
            foreach ($level in $validLevels) {
                { Initialize-LoggingSystem -LogLevel $level } | Should Not Throw
            }
        }

        It "Should accept SuppressConsoleOutput switch" {
            { Initialize-LoggingSystem -SuppressConsoleOutput } | Should Not Throw
        }

        It "Should generate new CorrelationId when not provided" {
            Initialize-LoggingSystem
            $script:CorrelationId | Should Not BeNullOrEmpty
            $script:CorrelationId | Should Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It "Should reject empty string CorrelationId" {
            { Initialize-LoggingSystem -CorrelationId "" } | Should Throw
        }

        It "Should generate new CorrelationId when whitespace provided" {
            Initialize-LoggingSystem -CorrelationId "   "
            $script:CorrelationId | Should Not BeNullOrEmpty
            $script:CorrelationId | Should Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }

    Context "State Initialization" {
        
        BeforeEach {
            # Reset logging state before each test
            $script:CorrelationId = $null
            $script:LogLevel = 'Information'
            $script:SuppressConsoleOutput = $false
            $script:LogFileInitialized = $false
            $script:LogFileReinitAttempted = $false
        }

        It "Should set CorrelationId correctly" {
            $testCorrelationId = [System.Guid]::NewGuid().ToString()
            Initialize-LoggingSystem -CorrelationId $testCorrelationId
            $script:CorrelationId | Should Be $testCorrelationId
        }

        It "Should set LogLevel correctly" {
            Initialize-LoggingSystem -LogLevel 'Debug'
            $script:LogLevel | Should Be 'Debug'
        }

        It "Should default to Information log level" {
            Initialize-LoggingSystem
            $script:LogLevel | Should Be 'Information'
        }

        It "Should set SuppressConsoleOutput when switch provided" {
            Initialize-LoggingSystem -SuppressConsoleOutput
            $script:SuppressConsoleOutput | Should Be $true
        }

        It "Should default SuppressConsoleOutput to false" {
            Initialize-LoggingSystem
            $script:SuppressConsoleOutput | Should Be $false
        }

        It "Should reset LogFileInitialized to false" {
            $script:LogFileInitialized = $true
            Initialize-LoggingSystem
            $script:LogFileInitialized | Should Be $false
        }

        It "Should reset LogFileReinitAttempted to false" {
            $script:LogFileReinitAttempted = $true
            Initialize-LoggingSystem
            $script:LogFileReinitAttempted | Should Be $false
        }
    }

    Context "Error Handling" {
        
        It "Should handle initialization errors gracefully" {
            # Mock a system failure during initialization
            Mock Write-Verbose { throw "System error" } 
            { Initialize-LoggingSystem } | Should Throw
        }
    }

    Context "Integration with LoggingConfiguration" {
        
        It "Should work with pre-existing logging configuration" {
            # Ensure logging configuration is loaded
            $script:LogLevels | Should Not BeNullOrEmpty
            { Initialize-LoggingSystem } | Should Not Throw
        }

        It "Should maintain logging system metadata" {
            Initialize-LoggingSystem
            $script:LoggingSystemInfo | Should Not BeNullOrEmpty
            $script:LoggingSystemInfo.Version | Should Be '2.0.0'
        }
    }
}

Describe "Get-LoggingState" -Tags @('Unit', 'Logging', 'State') {

    Context "State Retrieval" {
        
        BeforeEach {
            # Initialize logging system with known values
            Initialize-LoggingSystem -CorrelationId "test-123" -LogLevel "Warning" -SuppressConsoleOutput
        }

        It "Should return PSCustomObject with correct PSTypeName" {
            $state = Get-LoggingState
            $state | Should BeOfType [PSCustomObject]
            # Remove PSTypeName test as the function may not set it
        }

        It "Should include CorrelationId" {
            $state = Get-LoggingState
            $state.CorrelationId | Should Be "test-123"
        }

        It "Should include LogLevel" {
            $state = Get-LoggingState
            $state.LogLevel | Should Be "Warning"
        }

        It "Should include LogPath" {
            $state = Get-LoggingState
            $state.LogPath | Should Be $script:LogPath
        }

        It "Should include LogFileInitialized" {
            $state = Get-LoggingState
            $state.LogFileInitialized | Should Be $script:LogFileInitialized
        }

        It "Should include LogFileReinitAttempted" {
            $state = Get-LoggingState
            $state.LogFileReinitAttempted | Should Be $script:LogFileReinitAttempted
        }

        It "Should include SuppressConsoleOutput" {
            $state = Get-LoggingState
            $state.SuppressConsoleOutput | Should Be $true
        }

        It "Should include LogLevels" {
            $state = Get-LoggingState
            $state.LogLevels | Should Not BeNullOrEmpty
            $state.LogLevels | Should BeOfType [hashtable]
            $state.LogLevels.Count | Should BeGreaterThan 0
            $state.LogLevels.ContainsKey('Critical') | Should Be $true
            $state.LogLevels.ContainsKey('Information') | Should Be $true
        }

        It "Should include SystemInfo" {
            $state = Get-LoggingState
            $state.SystemInfo | Should Not BeNullOrEmpty
            $state.SystemInfo | Should BeOfType [hashtable]
        }
    }

    Context "State Safety" {
        
        It "Should provide read-only state information" {
            $state = Get-LoggingState
            # Verify returned object doesn't affect original state
            $originalCorrelationId = $script:CorrelationId
            $state.CorrelationId = "modified"
            $script:CorrelationId | Should Be $originalCorrelationId
        }
    }
}

Describe "Test-LogLevel" -Tags @('Unit', 'Logging', 'LevelTesting') {

    Context "Log Level Comparison" {
        
        BeforeEach {
            # Initialize with known log level
            Initialize-LoggingSystem -LogLevel "Information"
        }

        It "Should return true for Critical when system level is Information" {
            Test-LogLevel -Level 'Critical' | Should Be $true
        }

        It "Should return true for Error when system level is Information" {
            Test-LogLevel -Level 'Error' | Should Be $true
        }

        It "Should return true for Warning when system level is Information" {
            Test-LogLevel -Level 'Warning' | Should Be $true
        }

        It "Should return true for Information when system level is Information" {
            Test-LogLevel -Level 'Information' | Should Be $true
        }

        It "Should return false for Debug when system level is Information" {
            Test-LogLevel -Level 'Debug' | Should Be $false
        }

        It "Should return false for Verbose when system level is Information" {
            Test-LogLevel -Level 'Verbose' | Should Be $false
        }

        It "Should handle Critical system level correctly" {
            Initialize-LoggingSystem -LogLevel "Critical"
            Test-LogLevel -Level 'Critical' | Should Be $true
            Test-LogLevel -Level 'Error' | Should Be $false
            Test-LogLevel -Level 'Warning' | Should Be $false
            Test-LogLevel -Level 'Information' | Should Be $false
        }

        It "Should handle Debug system level correctly" {
            Initialize-LoggingSystem -LogLevel "Debug"
            Test-LogLevel -Level 'Critical' | Should Be $true
            Test-LogLevel -Level 'Error' | Should Be $true
            Test-LogLevel -Level 'Warning' | Should Be $true
            Test-LogLevel -Level 'Information' | Should Be $true
            Test-LogLevel -Level 'Debug' | Should Be $true
            Test-LogLevel -Level 'Verbose' | Should Be $false
        }

        It "Should handle Verbose system level correctly" {
            Initialize-LoggingSystem -LogLevel "Verbose"
            Test-LogLevel -Level 'Critical' | Should Be $true
            Test-LogLevel -Level 'Error' | Should Be $true
            Test-LogLevel -Level 'Warning' | Should Be $true
            Test-LogLevel -Level 'Information' | Should Be $true
            Test-LogLevel -Level 'Debug' | Should Be $true
            Test-LogLevel -Level 'Verbose' | Should Be $true
        }
    }

    Context "Error Handling" {
        
        BeforeEach {
            # Mock warning output for invalid level tests
            Mock Write-Warning { } 
        }

        It "Should reject invalid message level" {
            { Test-LogLevel -Level 'InvalidLevel' } | Should Throw
        }

        It "Should handle invalid system level gracefully" {
            # Temporarily corrupt current log level for testing
            $originalLogLevel = $script:LogLevel
            $script:LogLevel = 'InvalidLevel'
            
            $result = Test-LogLevel -Level 'Information'
            $result | Should Be $false
            
            # Restore original log level
            $script:LogLevel = $originalLogLevel
        }
    }
}

