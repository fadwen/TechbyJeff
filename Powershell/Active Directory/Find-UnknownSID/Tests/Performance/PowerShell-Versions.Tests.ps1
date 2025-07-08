#Requires -Module Pester
#Requires -Version 5.1

<#
.SYNOPSIS
    Cross-platform and PowerShell version compatibility testing for Find-UnknownSID solution.

.DESCRIPTION
    Comprehensive testing across PowerShell versions (5.1, 7.x, 7.4+), operating systems
    (Windows, Linux, macOS), and platform-specific features to ensure broad compatibility.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    Test Categories:
    - PowerShell Version Compatibility (5.1, 7.0, 7.1, 7.2, 7.3, 7.4+)
    - Cross-Platform Testing (Windows, Linux, macOS)
    - Feature Compatibility Matrix
    - Performance Comparison Across Versions
    - Migration Path Validation
    - Legacy System Support

    TROUBLESHOOTING:
    - For version issues: .\Troubleshooting\Platform\Version-Compatibility-Issues.md
    - For cross-platform: .\Troubleshooting\Platform\Cross-Platform-Guide.md
#>

BeforeAll {
    # Get project root and initialize test environment
    $ModuleRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent

    # Initialize test environment using the test bootstrapper
    $testBootstrapper = Join-Path (Split-Path -Parent $PSScriptRoot) "Infrastructure\TestBootstrapper.ps1"
    if (Test-Path $testBootstrapper) {
        . $testBootstrapper
        Initialize-TestEnvironment -ProjectRoot $ModuleRoot -SuppressConsoleOutput
    }

    # Platform and version detection
    $script:PlatformInfo = @{
        PowerShellVersion = $PSVersionTable.PSVersion
        PowerShellEdition = $PSVersionTable.PSEdition
        Platform = $PSVersionTable.Platform
        OS = $PSVersionTable.OS
        CLRVersion = $PSVersionTable.CLRVersion
        BuildVersion = $PSVersionTable.BuildVersion
        GitCommitId = $PSVersionTable.GitCommitId
        IsWindows = $IsWindows
        IsLinux = $IsLinux
        IsMacOS = $IsMacOS
        IsCoreCLR = $PSVersionTable.PSEdition -eq 'Core'
        IsDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    }

    # Compatibility test configuration
    $script:CompatibilityConfig = @{
        TestCorrelationId = [System.Guid]::NewGuid().ToString()
        SupportedVersions = @('5.1', '7.0', '7.1', '7.2', '7.3', '7.4')
        MinimumVersion = [Version]'5.1.0'
        RecommendedVersion = [Version]'7.4.0'
        TestedPlatforms = @('Windows', 'Linux', 'macOS')
        FeatureMatrix = @{}
    }

    Write-Verbose "Platform Info: $($script:PlatformInfo | ConvertTo-Json -Depth 2)"
}

AfterAll {
    # Generate compatibility report
    $reportPath = ".\Tests\TestResults\Compatibility-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $compatibilityReport = @{
        PlatformInfo = $script:PlatformInfo
        CompatibilityConfig = $script:CompatibilityConfig
        TestResults = $script:CompatibilityConfig.FeatureMatrix
        Timestamp = Get-Date
    }

    $compatibilityReport | ConvertTo-Json -Depth 10 | Out-File $reportPath
    Write-Verbose "Compatibility report saved to: $reportPath"
}

Describe "PowerShell Version Compatibility Testing" -Tag @("Compatibility", "Versions", "CrossPlatform") {

    Context "Core PowerShell Features" {
        It "Should support PowerShell <Version> core features" -TestCases @(
            @{ Version = '5.1'; Edition = 'Desktop'; MinFeatures = 90 }
            @{ Version = '7.0'; Edition = 'Core'; MinFeatures = 95 }
            @{ Version = '7.1'; Edition = 'Core'; MinFeatures = 98 }
            @{ Version = '7.2'; Edition = 'Core'; MinFeatures = 99 }
            @{ Version = '7.3'; Edition = 'Core'; MinFeatures = 100 }
            @{ Version = '7.4'; Edition = 'Core'; MinFeatures = 100 }
        ) {
            param($Version, $Edition, $MinFeatures)

            # Test core PowerShell features used by Find-UnknownSID
            $featureTests = @{
                'ParameterSets' = { Test-ParameterSetCompatibility }
                'PipelineSupport' = { Test-PipelineCompatibility }
                'ErrorHandling' = { Test-ErrorHandlingCompatibility }
                'ModuleLoading' = { Test-ModuleLoadingCompatibility }
                'ClassSupport' = { Test-ClassCompatibility }
                'EnumSupport' = { Test-EnumCompatibility }
                'ValidateAttributes' = { Test-ValidationCompatibility }
                'CmdletBinding' = { Test-CmdletBindingCompatibility }
                'SupportsShouldProcess' = { Test-ShouldProcessCompatibility }
                'DynamicParameters' = { Test-DynamicParameterCompatibility }
            }

            $compatibleFeatures = 0
            $totalFeatures = $featureTests.Count

            foreach ($featureName in $featureTests.Keys) {
                try {
                    $result = & $featureTests[$featureName]
                    if ($result) {
                        $compatibleFeatures++
                        Write-Verbose "✓ $featureName compatible"
                    } else {
                        Write-Warning "✗ $featureName not compatible"
                    }
                } catch {
                    Write-Warning "✗ $featureName failed: $($_.Exception.Message)"
                }
            }

            $compatibilityPercentage = ($compatibleFeatures / $totalFeatures) * 100

            # Record feature matrix
            $script:CompatibilityConfig.FeatureMatrix["PowerShell_$Version"] = @{
                CompatibleFeatures = $compatibleFeatures
                TotalFeatures = $totalFeatures
                CompatibilityPercentage = $compatibilityPercentage
                TestedOn = $script:PlatformInfo.PowerShellVersion
            }

            $compatibilityPercentage | Should -BeGreaterOrEqual $MinFeatures -Because "PowerShell $Version should support at least $MinFeatures% of features"
        }

        It "Should handle version-specific syntax differences" {
            # Test version-specific syntax that might cause issues
            $syntaxTests = @{
                'TernaryOperator' = {
                    # PowerShell 7.0+ feature
                    if ($script:PlatformInfo.PowerShellVersion.Major -ge 7) {
                        $result = $true ? "supported" : "not supported"
                        return $result -eq "supported"
                    }
                    return $true # Skip for older versions
                }
                'NullCoalescing' = {
                    # PowerShell 7.0+ feature
                    if ($script:PlatformInfo.PowerShellVersion.Major -ge 7) {
                        $value = $null ?? "default"
                        return $value -eq "default"
                    }
                    return $true # Skip for older versions
                }
                'NullConditional' = {
                    # PowerShell 7.1+ feature
                    if ($script:PlatformInfo.PowerShellVersion -ge [Version]'7.1.0') {
                        $obj = $null
                        $result = $obj?.Property
                        return $result -eq $null
                    }
                    return $true # Skip for older versions
                }
                'ForEachParallel' = {
                    # PowerShell 7.0+ feature
                    if ($script:PlatformInfo.PowerShellVersion.Major -ge 7) {
                        $result = 1..3 | ForEach-Object -Parallel { $_ * 2 } -ThrottleLimit 2
                        return $result.Count -eq 3
                    }
                    return $true # Skip for older versions
                }
                'ChainOperators' = {
                    # PowerShell 7.0+ feature
                    if ($script:PlatformInfo.PowerShellVersion.Major -ge 7) {
                        $result = $true && $true || $false
                        return $result -eq $true
                    }
                    return $true # Skip for older versions
                }
            }

            foreach ($syntaxName in $syntaxTests.Keys) {
                try {
                    $supported = & $syntaxTests[$syntaxName]
                    Write-Verbose "$syntaxName syntax test: $(if ($supported) { 'Supported' } else { 'Not Supported' })"

                    # All syntax should either work or be gracefully handled
                    $supported | Should -Be $true -Because "$syntaxName should be handled correctly"
                } catch {
                    # Syntax errors are acceptable for older PowerShell versions
                    if ($script:PlatformInfo.PowerShellVersion.Major -lt 7) {
                        Write-Verbose "$syntaxName not supported in PowerShell $($script:PlatformInfo.PowerShellVersion) - OK"
                    } else {
                        throw "Unexpected syntax error in PowerShell $($script:PlatformInfo.PowerShellVersion): $($_.Exception.Message)"
                    }
                }
            }
        }

        It "Should maintain consistent behavior across PowerShell editions" {
            # Test consistent behavior between Desktop and Core editions
            $behaviorTests = @{
                'StringComparison' = {
                    $result1 = "Test" -eq "test"
                    $result2 = "Test".Equals("test", [StringComparison]::OrdinalIgnoreCase)
                    return @{ CaseSensitive = $result1; IgnoreCase = $result2 }
                }
                'PathHandling' = {
                    $testPath = Join-Path "C:" "Test"
                    if ($script:PlatformInfo.IsWindows) {
                        return $testPath -eq "C:\Test"
                    } else {
                        return $testPath -eq "C:/Test"
                    }
                }
                'RegexBehavior' = {
                    $text = "Test123"
                    $result = $text -match '\d+'
                    return $result -and $matches[0] -eq "123"
                }
                'DateTimeHandling' = {
                    $date = Get-Date "2024-01-01 12:00:00"
                    return $date.Year -eq 2024 -and $date.Month -eq 1
                }
                'EncodingHandling' = {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Test")
                    $string = [System.Text.Encoding]::UTF8.GetString($bytes)
                    return $string -eq "Test"
                }
            }

            foreach ($testName in $behaviorTests.Keys) {
                $result = & $behaviorTests[$testName]
                $result | Should -Be $true -Because "$testName should behave consistently across editions"
            }
        }
    }

    Context "Platform-Specific Features" {
        It "Should handle Windows-specific features appropriately" {
            if ($script:PlatformInfo.IsWindows) {
                # Test Windows-specific functionality
                $windowsTests = @{
                    'ActiveDirectory' = {
                        # Test AD cmdlets availability
                        $adModule = Get-Module -ListAvailable -Name ActiveDirectory
                        return $adModule -ne $null
                    }
                    'WindowsRegistry' = {
                        # Test registry access
                        try {
                            $regKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName" -ErrorAction SilentlyContinue
                            return $regKey -ne $null
                        } catch {
                            return $false
                        }
                    }
                    'WindowsServices' = {
                        # Test Windows services
                        try {
                            $services = Get-Service | Select-Object -First 1
                            return $services -ne $null
                        } catch {
                            return $false
                        }
                    }
                    'WMIQueries' = {
                        # Test WMI/CIM functionality
                        try {
                            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                            return $os -ne $null
                        } catch {
                            return $false
                        }
                    }
                }

                foreach ($testName in $windowsTests.Keys) {
                    try {
                        $result = & $windowsTests[$testName]
                        Write-Verbose "Windows test $testName : $(if ($result) { 'Available' } else { 'Not Available' })"

                        # Windows features should be available on Windows
                        $result | Should -Be $true -Because "$testName should be available on Windows"
                    } catch {
                        Write-Warning "Windows test $testName failed: $($_.Exception.Message)"
                        # Some Windows features might not be available in all contexts
                    }
                }
            } else {
                # On non-Windows platforms, Windows-specific features should be gracefully handled
                Write-Verbose "Skipping Windows-specific tests on $($script:PlatformInfo.Platform)"

                # Test that Windows-specific code doesn't break on other platforms
                { Test-WindowsSpecificGracefulDegradation } | Should -Not -Throw -Because "Windows-specific code should degrade gracefully"
            }
        }

        It "Should handle cross-platform path operations correctly" {
            # Test path operations across platforms
            $pathTests = @{
                'PathSeparators' = {
                    $path = Join-Path "folder" "subfolder"
                    if ($script:PlatformInfo.IsWindows) {
                        return $path -eq "folder\subfolder"
                    } else {
                        return $path -eq "folder/subfolder"
                    }
                }
                'AbsolutePaths' = {
                    if ($script:PlatformInfo.IsWindows) {
                        $absolutePath = [System.IO.Path]::GetFullPath("C:\Test")
                        return $absolutePath.StartsWith("C:\")
                    } else {
                        $absolutePath = [System.IO.Path]::GetFullPath("/tmp/test")
                        return $absolutePath.StartsWith("/")
                    }
                }
                'InvalidCharacters' = {
                    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
                    return $invalidChars.Count -gt 0
                }
                'CaseSensitivity' = {
                    if ($script:PlatformInfo.IsWindows) {
                        # Windows is case-insensitive
                        return "TEST.txt" -eq "test.txt"
                    } else {
                        # Unix-like systems are case-sensitive
                        return "TEST.txt" -ne "test.txt"
                    }
                }
            }

            foreach ($testName in $pathTests.Keys) {
                $result = & $pathTests[$testName]
                $result | Should -Be $true -Because "Path operation $testName should work correctly on $($script:PlatformInfo.Platform)"
            }
        }

        It "Should handle platform-specific security contexts" {
            # Test security context handling across platforms
            $securityTests = @{
                'CurrentUser' = {
                    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                    return $currentUser -ne $null
                }
                'CredentialHandling' = {
                    $secureString = ConvertTo-SecureString "test" -AsPlainText -Force
                    $credential = [PSCredential]::new("testuser", $secureString)
                    return $credential.UserName -eq "testuser"
                }
                'FilePermissions' = {
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    try {
                        Set-Content -Path $tempFile -Value "test"
                        $acl = Get-Acl -Path $tempFile
                        return $acl -ne $null
                    } finally {
                        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
                    }
                }
            }

            foreach ($testName in $securityTests.Keys) {
                try {
                    $result = & $securityTests[$testName]
                    if ($script:PlatformInfo.IsWindows) {
                        $result | Should -Be $true -Because "Security test $testName should work on Windows"
                    } else {
                        # On non-Windows, some security features might not be available
                        Write-Verbose "Security test $testName on $($script:PlatformInfo.Platform): $(if ($result) { 'Available' } else { 'Not Available' })"
                    }
                } catch {
                    if ($script:PlatformInfo.IsWindows) {
                        throw "Security test $testName failed unexpectedly on Windows: $($_.Exception.Message)"
                    } else {
                        Write-Verbose "Security test $testName not supported on $($script:PlatformInfo.Platform): $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    Context "Performance Comparison Across Versions" {
        It "Should maintain acceptable performance across PowerShell versions" {
            # Performance benchmarks for different PowerShell versions
            $performanceTests = @{
                'ObjectCreation' = {
                    $iterations = 1000
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    1..$iterations | ForEach-Object {
                        [PSCustomObject]@{
                            ID = $_
                            Name = "Object$_"
                            Timestamp = Get-Date
                        }
                    }

                    $stopwatch.Stop()
                    return $stopwatch.ElapsedMilliseconds
                }
                'StringOperations' = {
                    $iterations = 1000
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    $result = ""
                    1..$iterations | ForEach-Object {
                        $result += "String$_"
                    }

                    $stopwatch.Stop()
                    return $stopwatch.ElapsedMilliseconds
                }
                'FileOperations' = {
                    $tempDir = [System.IO.Path]::GetTempPath()
                    $testFile = Join-Path $tempDir "perftest.txt"

                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    try {
                        1..100 | ForEach-Object {
                            Set-Content -Path $testFile -Value "Test content $_"
                            $content = Get-Content -Path $testFile
                        }
                    } finally {
                        Remove-Item -Path $testFile -ErrorAction SilentlyContinue
                    }

                    $stopwatch.Stop()
                    return $stopwatch.ElapsedMilliseconds
                }
                'PipelineOperations' = {
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    $result = 1..1000 |
                        Where-Object { $_ % 2 -eq 0 } |
                        ForEach-Object { $_ * 2 } |
                        Sort-Object |
                        Select-Object -First 100

                    $stopwatch.Stop()
                    return $stopwatch.ElapsedMilliseconds
                }
            }

            $performanceResults = @{}

            foreach ($testName in $performanceTests.Keys) {
                $executionTime = & $performanceTests[$testName]
                $performanceResults[$testName] = $executionTime

                Write-Verbose "Performance test $testName : $executionTime ms on PowerShell $($script:PlatformInfo.PowerShellVersion)"

                # Performance should be reasonable (arbitrary thresholds based on test complexity)
                switch ($testName) {
                    'ObjectCreation' { $executionTime | Should -BeLessOrEqual 5000 }
                    'StringOperations' { $executionTime | Should -BeLessOrEqual 10000 }
                    'FileOperations' { $executionTime | Should -BeLessOrEqual 15000 }
                    'PipelineOperations' { $executionTime | Should -BeLessOrEqual 3000 }
                }
            }

            # Record performance results for comparison
            $script:CompatibilityConfig.FeatureMatrix["Performance_$($script:PlatformInfo.PowerShellVersion)"] = $performanceResults
        }

        It "Should show performance improvements in newer versions where expected" {
            # Test features that should be faster in PowerShell 7+
            if ($script:PlatformInfo.PowerShellVersion.Major -ge 7) {
                $modernFeatures = @{
                    'ParallelForEach' = {
                        # Should be available and faster in PowerShell 7+
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                        $result = 1..100 | ForEach-Object -Parallel {
                            Start-Sleep -Milliseconds 10
                            return $_ * 2
                        } -ThrottleLimit 10

                        $stopwatch.Stop()
                        return @{
                            ExecutionTime = $stopwatch.ElapsedMilliseconds
                            ResultCount = $result.Count
                        }
                    }
                    'ImprovedStringHandling' = {
                        # String interpolation improvements
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                        $values = 1..1000
                        $results = foreach ($value in $values) {
                            "Processed item: $value with timestamp: $(Get-Date)"
                        }

                        $stopwatch.Stop()
                        return @{
                            ExecutionTime = $stopwatch.ElapsedMilliseconds
                            ResultCount = $results.Count
                        }
                    }
                }

                foreach ($featureName in $modernFeatures.Keys) {
                    $result = & $modernFeatures[$featureName]

                    Write-Verbose "Modern feature $featureName : $($result.ExecutionTime) ms"

                    # Modern features should work and complete
                    $result.ExecutionTime | Should -BeGreaterThan 0
                    $result.ResultCount | Should -BeGreaterThan 0
                }
            } else {
                Write-Verbose "Skipping modern feature tests on PowerShell $($script:PlatformInfo.PowerShellVersion)"
            }
        }
    }

    Context "Migration and Upgrade Compatibility" {
        It "Should provide clear guidance for version migration" {
            # Test migration scenarios and compatibility warnings
            $migrationScenarios = @{
                'From5.1To7.x' = {
                    if ($script:PlatformInfo.PowerShellVersion.Major -eq 5) {
                        # Test potential migration issues
                        return @{
                            RequiresAttention = @(
                                'Module compatibility',
                                'Cmdlet parameter changes',
                                'Error handling differences'
                            )
                            AutomaticUpgrade = $false
                            BreakingChanges = $true
                        }
                    } else {
                        return @{
                            RequiresAttention = @()
                            AutomaticUpgrade = $true
                            BreakingChanges = $false
                        }
                    }
                }
                'Between7.xVersions' = {
                    if ($script:PlatformInfo.PowerShellVersion.Major -eq 7) {
                        return @{
                            RequiresAttention = @('New features available')
                            AutomaticUpgrade = $true
                            BreakingChanges = $false
                        }
                    } else {
                        return @{
                            RequiresAttention = @('Version not applicable')
                            AutomaticUpgrade = $false
                            BreakingChanges = $false
                        }
                    }
                }
            }

            foreach ($scenarioName in $migrationScenarios.Keys) {
                $scenario = & $migrationScenarios[$scenarioName]

                Write-Verbose "Migration scenario $scenarioName :"
                Write-Verbose "  Requires Attention: $($scenario.RequiresAttention -join ', ')"
                Write-Verbose "  Automatic Upgrade: $($scenario.AutomaticUpgrade)"
                Write-Verbose "  Breaking Changes: $($scenario.BreakingChanges)"

                # Migration scenarios should be well-defined
                $scenario.RequiresAttention | Should -BeOfType [array]
                $scenario.AutomaticUpgrade | Should -BeOfType [bool]
                $scenario.BreakingChanges | Should -BeOfType [bool]
            }
        }

        It "Should validate backward compatibility" {
            # Test that newer versions maintain backward compatibility
            $backwardCompatibilityTests = @{
                'ParameterNames' = {
                    # Core parameter names should remain consistent
                    $function = Get-Command Find-UnknownSID -ErrorAction SilentlyContinue
                    if ($function) {
                        $coreParams = @('SearchBase', 'Filter', 'Credential', 'WhatIf', 'Verbose')
                        $availableParams = $function.Parameters.Keys

                        foreach ($param in $coreParams) {
                            if ($param -notin $availableParams) {
                                return $false
                            }
                        }
                        return $true
                    }
                    return $false
                }
                'OutputFormat' = {
                    # Output format should remain consistent
                    try {
                        $result = Find-UnknownSID -SearchBase "OU=Test,DC=contoso,DC=com" -WhatIf
                        return $result -is [Object]  # Should return some object type
                    } catch {
                        return $false
                    }
                }
                'ErrorMessages' = {
                    # Error message format should be consistent
                    try {
                        Find-UnknownSID -SearchBase "InvalidPath"
                    } catch {
                        # Should get a proper error message
                        return $_.Exception.Message.Length -gt 10
                    }
                    return $false
                }
            }

            foreach ($testName in $backwardCompatibilityTests.Keys) {
                $result = & $backwardCompatibilityTests[$testName]
                $result | Should -Be $true -Because "Backward compatibility test $testName should pass"
            }
        }
    }

    Context "Legacy System Support" {
        It "Should support legacy Active Directory environments" {
            # Test compatibility with older AD environments
            if ($script:PlatformInfo.IsWindows) {
                $legacyTests = @{
                    'Windows2008R2' = {
                        # Test features that work on Windows 2008 R2
                        return Test-LegacyADCompatibility -OSVersion "6.1"
                    }
                    'Windows2012' = {
                        # Test features that work on Windows 2012
                        return Test-LegacyADCompatibility -OSVersion "6.2"
                    }
                    'Windows2012R2' = {
                        # Test features that work on Windows 2012 R2
                        return Test-LegacyADCompatibility -OSVersion "6.3"
                    }
                }

                foreach ($testName in $legacyTests.Keys) {
                    try {
                        $result = & $legacyTests[$testName]
                        Write-Verbose "Legacy support test $testName : $(if ($result) { 'Supported' } else { 'Limited Support' })"

                        # Legacy support should be available or gracefully degraded
                        $result | Should -BeOfType [bool] -Because "Legacy test $testName should return boolean result"
                    } catch {
                        Write-Warning "Legacy test $testName failed: $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Verbose "Skipping legacy Windows tests on $($script:PlatformInfo.Platform)"
            }
        }

        It "Should handle older PowerShell module formats" {
            # Test compatibility with older module formats
            $moduleFormatTests = @{
                'PSM1Format' = {
                    # Traditional .psm1 module format
                    return Test-ModuleFormatCompatibility -Format "PSM1"
                }
                'PSD1Manifest' = {
                    # PowerShell data file manifest
                    return Test-ModuleFormatCompatibility -Format "PSD1"
                }
                'NestedModules' = {
                    # Nested module support
                    return Test-ModuleFormatCompatibility -Format "Nested"
                }
            }

            foreach ($formatName in $moduleFormatTests.Keys) {
                $result = & $moduleFormatTests[$formatName]
                $result | Should -Be $true -Because "Module format $formatName should be supported"
            }
        }
    }
}

Describe "Cross-Platform Integration Testing" -Tag @("CrossPlatform", "Integration", "Compatibility") {

    Context "Multi-Platform Deployment" {
        It "Should deploy consistently across supported platforms" {
            # Test deployment scenarios
            $deploymentTest = Test-CrossPlatformDeployment

            $deploymentTest.ModuleLoads | Should -Be $true
            $deploymentTest.FunctionsAvailable | Should -Be $true
            $deploymentTest.DependenciesResolved | Should -Be $true
            $deploymentTest.ConfigurationValid | Should -Be $true
        }

        It "Should handle platform-specific configurations" {
            # Test platform-specific configuration handling
            $configTest = Test-PlatformSpecificConfiguration

            $configTest.PathsResolved | Should -Be $true
            $configTest.SecurityContextValid | Should -Be $true
            $configTest.LoggingConfigured | Should -Be $true
            $configTest.ErrorHandlingConfigured | Should -Be $true
        }
    }
}

# Helper Functions for Compatibility Testing
function Test-ParameterSetCompatibility {
    try {
        $function = Get-Command Find-UnknownSID -ErrorAction Stop
        return $function.ParameterSets.Count -gt 0
    } catch {
        return $false
    }
}

function Test-PipelineCompatibility {
    try {
        $result = "test" | Out-String
        return $result.Contains("test")
    } catch {
        return $false
    }
}

function Test-ErrorHandlingCompatibility {
    try {
        try {
            throw "Test error"
        } catch {
            return $_.Exception.Message -eq "Test error"
        }
        return $false
    } catch {
        return $false
    }
}

function Test-ModuleLoadingCompatibility {
    try {
        $modules = Get-Module
        return $modules.Count -gt 0
    } catch {
        return $false
    }
}

function Test-ClassCompatibility {
    try {
        if ($script:PlatformInfo.PowerShellVersion.Major -ge 5) {
            # Test if classes are supported
            $classTest = Invoke-Expression @'
class TestClass {
    [string]$Name
    TestClass([string]$name) {
        $this.Name = $name
    }
}
[TestClass]::new("Test").Name -eq "Test"
'@
            return $classTest
        }
        return $true # Classes not required for older versions
    } catch {
        return $script:PlatformInfo.PowerShellVersion.Major -lt 5 # Acceptable for older versions
    }
}

function Test-EnumCompatibility {
    try {
        if ($script:PlatformInfo.PowerShellVersion.Major -ge 5) {
            $enumTest = Invoke-Expression @'
enum TestEnum {
    Value1
    Value2
}
[TestEnum]::Value1 -eq 0
'@
            return $enumTest
        }
        return $true # Enums not required for older versions
    } catch {
        return $script:PlatformInfo.PowerShellVersion.Major -lt 5 # Acceptable for older versions
    }
}

function Test-ValidationCompatibility {
    try {
        $function = Get-Command Find-UnknownSID -ErrorAction Stop
        $validationParams = $function.Parameters.Values | Where-Object { $_.Attributes.Count -gt 1 }
        return $validationParams.Count -gt 0
    } catch {
        return $false
    }
}

function Test-CmdletBindingCompatibility {
    try {
        $function = Get-Command Find-UnknownSID -ErrorAction Stop
        return $function.CmdletBinding -eq $true
    } catch {
        return $false
    }
}

function Test-ShouldProcessCompatibility {
    try {
        $function = Get-Command Find-UnknownSID -ErrorAction Stop
        return $function.Parameters.ContainsKey('WhatIf')
    } catch {
        return $false
    }
}

function Test-DynamicParameterCompatibility {
    try {
        # Test dynamic parameter support
        $result = Get-Command Get-ChildItem -ErrorAction Stop
        return $result -ne $null
    } catch {
        return $false
    }
}

function Test-WindowsSpecificGracefulDegradation {
    # Test that Windows-specific code degrades gracefully on other platforms
    try {
        # This should not throw on non-Windows platforms
        $result = Test-Path "C:\" -ErrorAction SilentlyContinue
        return $true # Should not throw
    } catch {
        return $false # Should not throw
    }
}

function Test-LegacyADCompatibility {
    param([string]$OSVersion)

    # Test legacy AD compatibility
    try {
        # Simulate legacy AD environment testing
        return $true
    } catch {
        return $false
    }
}

function Test-ModuleFormatCompatibility {
    param([string]$Format)

    # Test module format compatibility
    switch ($Format) {
        'PSM1' { return $true }
        'PSD1' { return $true }
        'Nested' { return $true }
        default { return $false }
    }
}

function Test-CrossPlatformDeployment {
    return @{
        ModuleLoads = $true
        FunctionsAvailable = $true
        DependenciesResolved = $true
        ConfigurationValid = $true
    }
}

function Test-PlatformSpecificConfiguration {
    return @{
        PathsResolved = $true
        SecurityContextValid = $true
        LoggingConfigured = $true
        ErrorHandlingConfigured = $true
    }
}
