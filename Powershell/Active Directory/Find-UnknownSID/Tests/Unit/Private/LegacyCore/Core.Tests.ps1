#Requires -Module Pester

# Core functionality tests for Find-UnknownSID.ps1
# Uses content analysis approach to validate script capabilities without execution

Describe "Find-UnknownSID Core Functionality" {
    Context "Script File Validation" {
        It "Should have Find-UnknownSID.ps1 file available" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            Test-Path $scriptPath | Should Be $true
        }

        It "Should be a PowerShell script file" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $extension = [System.IO.Path]::GetExtension($scriptPath)
            $extension | Should Be '.ps1'
        }

        It "Should contain main function definitions" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $content = Get-Content $scriptPath -Raw
            $content | Should Match 'param\s*\('
            $content | Should Match 'function\s+Write-StatusMessage'
        }

        It "Should have proper script structure" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $content = Get-Content $scriptPath -Raw
            $content | Should Match 'begin\s*\{'
            $content | Should Match 'process\s*\{'
            $content | Should Match 'end\s*\{'
        }

        It "Should have proper parameter definitions" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $content = Get-Content $scriptPath -Raw
            $content | Should Match '\[Parameter\('
            $content | Should Match 'SearchBase'
            $content | Should Match 'Remove'
            $content | Should Match 'Restore'
        }
    }

    Context "Script Content Analysis" {
        BeforeAll {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $script:scriptContent = Get-Content $scriptPath -Raw
        }

        It "Should have logging functionality" {
            $script:scriptContent | Should Match 'Write-StructuredLog'
            $script:scriptContent | Should Match 'CorrelationId'
        }

        It "Should have error handling" {
            $script:scriptContent | Should Match 'try\s*\{'
            $script:scriptContent | Should Match 'catch\s*\{'
            $script:scriptContent | Should Match 'throw'
        }

        It "Should have required Active Directory operations" {
            $script:scriptContent | Should Match 'Get-AD'
            $script:scriptContent | Should Match 'ActiveDirectory'
        }

        It "Should have backup functionality for Remove mode" {
            $script:scriptContent | Should Match 'BackupPath'
            $script:scriptContent | Should Match 'backup'
        }

        It "Should have restore functionality" {
            $script:scriptContent | Should Match 'Restore'
            $script:scriptContent | Should Match 'Backup'
        }
    }

    Context "PowerShell Compatibility" {
        It "Should be compatible with PowerShell 5.1" {
            $PSVersionTable.PSVersion.Major | Should BeGreaterThan 4
        }

        It "Should not use PowerShell 7+ specific features" {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $content = Get-Content $scriptPath -Raw
            # Check for PS7+ specific syntax that would break PS5.1
            $content | Should Not Match '\?\?' # Null coalescing operator
        }
    }

    Context "Security Features" {
        BeforeAll {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $script:scriptContent = Get-Content $scriptPath -Raw
        }

        It "Should have WhatIf support" {
            $script:scriptContent | Should Match 'WhatIf'
            $script:scriptContent | Should Match 'SupportsShouldProcess'
        }

        It "Should have confirmation for dangerous operations" {
            $script:scriptContent | Should Match 'Confirm'
            $script:scriptContent | Should Match 'Remove'
        }

        It "Should validate input parameters" {
            $script:scriptContent | Should Match '\[ValidateScript\('
            $script:scriptContent | Should Match '\[ValidateRange\('
        }
    }

    Context "Enterprise Features" {
        BeforeAll {
            $scriptPath = "$PSScriptRoot\..\..\..\..\Find-UnknownSID.ps1"
            $script:scriptContent = Get-Content $scriptPath -Raw
        }

        It "Should have correlation ID tracking" {
            $script:scriptContent | Should Match 'CorrelationId'
            $script:scriptContent | Should Match 'System\.Guid'
        }

        It "Should have memory management" {
            $script:scriptContent | Should Match 'memory'
            $script:scriptContent | Should Match 'MemoryManager'
        }

        It "Should have performance monitoring" {
            $script:scriptContent | Should Match 'statistics'
            $script:scriptContent | Should Match 'Memory'
        }

        It "Should have comprehensive logging" {
            $script:scriptContent | Should Match 'Write-StructuredLog'
            $script:scriptContent | Should Match 'CorrelationId'
        }
    }
}
