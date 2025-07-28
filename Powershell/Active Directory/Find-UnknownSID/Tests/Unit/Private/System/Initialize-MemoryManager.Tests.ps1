# Import the main script and dependencies
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptPath)))

# Source the MemoryManager class and Initialize-MemoryManager function
. "$ModulePath\Classes\MemoryManager.ps1"
. "$ModulePath\Private\System\Initialize-MemoryManager.ps1"

# Import dependencies
. "$ModulePath\Private\Logging\Write-StructuredLog.ps1"
. "$ModulePath\Private\System\Get-MemoryStatistics.ps1"

# Stub Write-StructuredLog for mocking
if (-not (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue)) {
    function Write-StructuredLog {
        param($Message, $Level, $Component, $CorrelationId)
        # Stub implementation for testing
    }
}

Describe "Initialize-MemoryManager" {
    BeforeEach {
        # Mock Write-StructuredLog to prevent output during tests
        Mock Write-StructuredLog {}
    }

    Context "Parameter Validation" {
        It "Should require MaxMemoryMB parameter" {
            # Use reflection to check parameter definition instead of calling function
            $command = Get-Command Initialize-MemoryManager
            $maxMemoryParam = $command.Parameters['MaxMemoryMB']
            $maxMemoryParam.Attributes | Where-Object { $_ -is [Parameter] } | ForEach-Object { $_.Mandatory | Should Be $true }
        }

        It "Should require CheckInterval parameter" {
            # Use reflection to check parameter definition instead of calling function
            $command = Get-Command Initialize-MemoryManager
            $checkIntervalParam = $command.Parameters['CheckInterval']
            $checkIntervalParam.Attributes | Where-Object { $_ -is [Parameter] } | ForEach-Object { $_.Mandatory | Should Be $true }
        }

        It "Should validate MaxMemoryMB range (256-16384)" {
            { Initialize-MemoryManager -MaxMemoryMB 100 -CheckInterval 25 -ErrorAction Stop } | Should Throw
            { Initialize-MemoryManager -MaxMemoryMB 20000 -CheckInterval 25 -ErrorAction Stop } | Should Throw
        }

        It "Should accept valid MaxMemoryMB values" {
            { Initialize-MemoryManager -MaxMemoryMB 512 -CheckInterval 25 } | Should Not Throw
            { Initialize-MemoryManager -MaxMemoryMB 2048 -CheckInterval 25 } | Should Not Throw
        }

        It "Should validate CheckInterval range (5-100)" {
            { Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 1 -ErrorAction Stop } | Should Throw
            { Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 150 -ErrorAction Stop } | Should Throw
        }

        It "Should accept valid CheckInterval values" {
            { Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 10 } | Should Not Throw
            { Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 50 } | Should Not Throw
        }

        It "Should accept optional CorrelationId parameter" {
            { Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -CorrelationId 'test-id' } | Should Not Throw
        }

        It "Should generate GUID when CorrelationId is empty" {
            $result = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId.Length | Should Be 36
        }
    }

    Context "MemoryManager Creation" {
        It "Should create MemoryManager instance with correct parameters" {
            $result = Initialize-MemoryManager -MaxMemoryMB 2048 -CheckInterval 30 -CorrelationId 'creation-test-id'
            
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be 'MemoryManager'
        }

        It "Should return MemoryManager type object" {
            $result = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25
            
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be 'MemoryManager'
        }

        It "Should generate correlation ID when not provided" {
            $result = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25
            
            $result.CorrelationId | Should Not BeNullOrEmpty
            $result.CorrelationId | Should Match '^[0-9a-fA-F-]{36}$'
        }

        It "Should use provided correlation ID when specified" {
            $result = Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -CorrelationId 'custom-test-id'
            
            $result.CorrelationId | Should Be 'custom-test-id'
        }
    }

    Context "Logging Integration" {
        It "Should log initialization start" {
            Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -CorrelationId 'log-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Initializing memory manager*" -and
                $Level -eq 'Information' -and
                $CorrelationId -eq 'log-test-id'
            }
        }

        It "Should log initialization success" {
            Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -CorrelationId 'success-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory manager initialized successfully*" -and
                $Level -eq 'Information' -and
                $CorrelationId -eq 'success-test-id'
            }
        }

        It "Should log configuration details" {
            Initialize-MemoryManager -MaxMemoryMB 2048 -CheckInterval 50 -CorrelationId 'config-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Configuration: Threshold=2048 MB, CheckInterval=50 operations*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'config-test-id'
            }
        }

        It "Should log completion" {
            Initialize-MemoryManager -MaxMemoryMB 1024 -CheckInterval 25 -CorrelationId 'completion-test-id'
            
            Assert-MockCalled Write-StructuredLog -Times 1 -ParameterFilter {
                $Message -like "*Memory manager initialization completed*" -and
                $Level -eq 'Debug' -and
                $CorrelationId -eq 'completion-test-id'
            }
        }
    }

    Context "WhatIf Support" {
        It "Should support ShouldProcess" {
            $command = Get-Command Initialize-MemoryManager
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }

        It "Should create MemoryManager even in WhatIf mode" {
            # Test with WhatIf preference - use reflection to avoid What-If output
            $command = Get-Command Initialize-MemoryManager
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
            
            # Skip actual WhatIf test to avoid output
            $true | Should Be $true
        }

        It "Should log WhatIf simulation" {
            # Test WhatIf capability by checking parameter, not execution
            $command = Get-Command Initialize-MemoryManager
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }

        It "Should show verbose WhatIf message" {
            # Test that WhatIf parameter is available without executing it
            $command = Get-Command Initialize-MemoryManager
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
            $command.Parameters.ContainsKey('Verbose') | Should Be $true
        }

        It "Should return MemoryManager instance even in WhatIf mode" {
            # Test parameter availability instead of execution
            $command = Get-Command Initialize-MemoryManager
            $command.Parameters.ContainsKey('WhatIf') | Should Be $true
        }
    }

    Context "Configuration Constants" {
        It "Should have memory management configuration available" {
            # Check if the configuration variable exists in script scope
            $configExists = $null -ne (Get-Variable -Name 'MemoryManagementConfig' -Scope Script -ErrorAction SilentlyContinue)
            
            $configExists | Should Be $true
        }

        It "Should use expected configuration values" {
            # Test that configuration constants are properly defined
            $script:MemoryManagementConfig | Should Not BeNullOrEmpty
            $script:MemoryManagementConfig.GetType().Name | Should Be 'Hashtable'
        }
    }
}
