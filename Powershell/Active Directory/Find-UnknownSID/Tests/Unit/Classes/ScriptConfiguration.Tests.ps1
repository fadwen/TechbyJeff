#Requires -Version 5.1
#Requires -Module Pester

# Import the class
$ModuleRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path
. "$ModuleRoot\Classes\ScriptConfiguration.ps1"

Describe 'ScriptConfiguration Class Tests' {
    Context 'Constructor Tests' {
        It 'Should create instance with default constructor' {
            $config = [ScriptConfiguration]::new()
            $config | Should Not BeNullOrEmpty
            $config.GetType().Name | Should Be 'ScriptConfiguration'
        }

        It 'Should initialize all default properties' {
            $config = [ScriptConfiguration]::new()
            
            # Verify array properties are initialized
            $config.WellKnownSIDPatterns | Should Not BeNullOrEmpty
            $config.ProtectedSIDs | Should Not BeNullOrEmpty  
            $config.CriticalObjectPatterns | Should Not BeNullOrEmpty
            
            # Verify numeric properties
            $config.BatchSize | Should Be 100
            $config.MemoryCheckInterval | Should Be 50
            $config.MaxLogFileSizeMB | Should Be 10
            
            # Verify boolean properties
            $config.EnableDetailedLogging | Should Be $false
            $config.EnableLogFileRotation | Should Be $true
            
            # Verify string properties
            $config.LogLevel | Should Be 'Information'
            $config.LogFilePath | Should BeNullOrEmpty
        }
    }

    Context 'Property Type Tests' {
        It 'Should have correct property types' {
            $config = [ScriptConfiguration]::new()
            
            $config.WellKnownSIDPatterns.GetType().Name | Should Be 'String[]'
            $config.ProtectedSIDs.GetType().Name | Should Be 'String[]'
            $config.CriticalObjectPatterns.GetType().Name | Should Be 'String[]'
            
            $config.BatchSize.GetType().Name | Should Be 'Int32'
            $config.MemoryCheckInterval.GetType().Name | Should Be 'Int32'
            $config.MaxLogFileSizeMB.GetType().Name | Should Be 'Int32'
            
            $config.EnableDetailedLogging.GetType().Name | Should Be 'Boolean'
            $config.EnableLogFileRotation.GetType().Name | Should Be 'Boolean'
            
            $config.LogLevel.GetType().Name | Should Be 'String'
        }

        It 'Should allow property modifications' {
            $config = [ScriptConfiguration]::new()
            
            $config.BatchSize = 200
            $config.BatchSize | Should Be 200
            
            $config.EnableDetailedLogging = $true
            $config.EnableDetailedLogging | Should Be $true
            
            $config.LogLevel = 'Debug'
            $config.LogLevel | Should Be 'Debug'
            
            $config.LogFilePath = 'C:\Logs\test.log'
            $config.LogFilePath | Should Be 'C:\Logs\test.log'
        }
    }

    Context 'InitializeDefaults Method Tests' {
        It 'Should have InitializeDefaults method' {
            $config = [ScriptConfiguration]::new()
            { $config.InitializeDefaults() } | Should Not Throw
        }

        It 'Should initialize WellKnownSIDPatterns with expected patterns' {
            $config = [ScriptConfiguration]::new()
            $config.InitializeDefaults()
            ($config.WellKnownSIDPatterns -contains '^S-1-1-0$') | Should Be $true
            ($config.WellKnownSIDPatterns -contains '^S-1-5-18$') | Should Be $true
            ($config.WellKnownSIDPatterns -contains '^S-1-5-32-') | Should Be $true
            $config.WellKnownSIDPatterns.Count | Should BeGreaterThan 5
        }

        It 'Should initialize ProtectedSIDs with expected SIDs' {
            $config = [ScriptConfiguration]::new()
            $config.InitializeDefaults()
            ($config.ProtectedSIDs -contains 'S-1-5-32-544') | Should Be $true
            ($config.ProtectedSIDs -contains 'S-1-5-18') | Should Be $true
            $config.ProtectedSIDs.Count | Should BeGreaterThan 3
        }

        It 'Should initialize CriticalObjectPatterns with expected patterns' {
            $config = [ScriptConfiguration]::new()
            $config.InitializeDefaults()
            ($config.CriticalObjectPatterns -contains '*CN=Domain Admins*') | Should Be $true
            ($config.CriticalObjectPatterns -contains '*CN=BUILTIN*') | Should Be $true
            $config.CriticalObjectPatterns.Count | Should BeGreaterThan 3
        }
    }

    Context 'ValidateConfiguration Method Tests' {
        It 'Should have ValidateConfiguration method' {
            $config = [ScriptConfiguration]::new()
            $result = $config.ValidateConfiguration()
            $result.GetType().Name | Should Be 'Boolean'
        }

        It 'Should return true for valid default configuration' {
            $config = [ScriptConfiguration]::new()
            $result = $config.ValidateConfiguration()
            $result | Should Be $true
        }

        It 'Should return false for invalid BatchSize' {
            $config = [ScriptConfiguration]::new()
            $config.BatchSize = 0
            $result = $config.ValidateConfiguration()
            $result | Should Be $false
        }

        It 'Should return false for invalid MemoryCheckInterval' {
            $config = [ScriptConfiguration]::new()
            $config.MemoryCheckInterval = 1001
            $result = $config.ValidateConfiguration()
            $result | Should Be $false
        }

        It 'Should return false for invalid LogLevel' {
            $config = [ScriptConfiguration]::new()
            $config.LogLevel = 'InvalidLevel'
            $result = $config.ValidateConfiguration()
            $result | Should Be $false
        }

        It 'Should return false for invalid SID pattern' {
            $config = [ScriptConfiguration]::new()
            $config.WellKnownSIDPatterns = @('[invalid-regex')
            $result = $config.ValidateConfiguration()
            $result | Should Be $false
        }

        It 'Should return false for invalid protected SID format' {
            $config = [ScriptConfiguration]::new()
            $config.ProtectedSIDs = @('invalid-sid-format')
            $result = $config.ValidateConfiguration()
            $result | Should Be $false
        }
    }

    Context 'LoadFromFile Static Method Tests' {
        It 'Should load configuration from valid file' {
            # Create a temporary config file
            $tempConfigFile = Join-Path $env:TEMP "test-config-$(Get-Random).json"
            $validConfig = @{
                WellKnownSIDPatterns = @('^S-1-1-0$', '^S-1-5-18$')
                ProtectedSIDs = @('S-1-5-32-544', 'S-1-5-18')
                BatchSize = 50
                MemoryCheckInterval = 25
                EnableDetailedLogging = $true
                LogLevel = 'Debug'
                LogFilePath = 'C:\Logs\test.log'
                EnableLogFileRotation = $false
                MaxLogFileSizeMB = 20
            }
            $validConfig | ConvertTo-Json | Out-File $tempConfigFile -Encoding UTF8
            
            try {
                $config = [ScriptConfiguration]::LoadFromFile($tempConfigFile)
                $config | Should Not BeNullOrEmpty
                $config.GetType().Name | Should Be 'ScriptConfiguration'
                $config.BatchSize | Should Be 50
                $config.LogLevel | Should Be 'Debug'
            } finally {
                Remove-Item $tempConfigFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should throw error for non-existent file' {
            { [ScriptConfiguration]::LoadFromFile('C:\NonExistent\config.json') } | Should Throw
        }

        It 'Should throw error for invalid JSON file' {
            $invalidConfigFile = Join-Path $env:TEMP "invalid-config-$(Get-Random).json"
            '{ invalid json }' | Out-File $invalidConfigFile -Encoding UTF8
            
            try {
                { [ScriptConfiguration]::LoadFromFile($invalidConfigFile) } | Should Throw
            } finally {
                Remove-Item $invalidConfigFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Integration Tests' {
        It 'Should maintain data consistency across operations' {
            $config = [ScriptConfiguration]::new()
            
            # Modify configuration
            $config.BatchSize = 250
            $config.LogLevel = 'Warning'
            $config.EnableDetailedLogging = $true
            
            # Validate modified configuration
            $result = $config.ValidateConfiguration()
            $result | Should Be $true
            
            # Verify changes persisted
            $config.BatchSize | Should Be 250
            $config.LogLevel | Should Be 'Warning'
            $config.EnableDetailedLogging | Should Be $true
        }

        It 'Should handle edge cases gracefully' {
            $config = [ScriptConfiguration]::new()
            
            # Test minimum valid values
            $config.BatchSize = 1
            $config.MemoryCheckInterval = 1
            $config.ValidateConfiguration() | Should Be $true
            
            # Test maximum valid values
            $config.BatchSize = 1000
            $config.MemoryCheckInterval = 1000
            $config.ValidateConfiguration() | Should Be $true
        }
    }
}
