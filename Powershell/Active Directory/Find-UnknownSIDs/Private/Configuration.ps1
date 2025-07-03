#requires -version 5.1

<#
.SYNOPSIS
    Configuration management module for Find-UnknownSIDs script.

.DESCRIPTION
    This module provides comprehensive configuration management including:
    - Configuration validation functions
    - Parameter validation and security checks
    - JSON configuration file support
    - Runtime configuration loading and validation
    - Configuration troubleshooting and reporting

    The module ensures all configuration settings are validated for security,
    performance, and compatibility before use.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    TROUBLESHOOTING:
    - For configuration issues: .\Troubleshooting\Common\Configuration-Issues.md
    - For JSON format errors: .\Troubleshooting\Common\JSON-Configuration-Guide.md
    - For parameter validation: .\Troubleshooting\Common\Parameter-Validation-Guide.md

.LINK
    https://github.com/your-org/powershell-scripts/tree/main/Scripts/Active%20Directory/Find-UnknownSIDs

.COMPONENT
    Configuration Management

.FUNCTIONALITY
    Enterprise configuration validation and management
#>

#region Configuration Validation Functions

function Initialize-ScriptConfiguration {
    <#
    .SYNOPSIS
        Initializes script configuration from parameters or configuration file.

    .DESCRIPTION
        Creates and validates a ScriptConfiguration object either from command-line
        parameters or from a JSON configuration file. Provides comprehensive
        validation and error handling.

    .PARAMETER ConfigPath
        Optional path to JSON configuration file

    .PARAMETER BatchSize
        Override batch size from command line

    .PARAMETER LogLevel
        Override log level from command line

    .PARAMETER EnableDetailedLogging
        Override detailed logging setting from command line

    .OUTPUTS
        [ScriptConfiguration] Validated configuration object

    .EXAMPLE
        PS> $config = Initialize-ScriptConfiguration -ConfigPath "C:\Config\script.json"

        DESCRIPTION: Loads configuration from JSON file
        OUTPUT: Validated ScriptConfiguration object
        USE CASE: Enterprise configuration management

    .EXAMPLE
        PS> $config = Initialize-ScriptConfiguration -BatchSize 200 -LogLevel "Debug"

        DESCRIPTION: Creates configuration with parameter overrides
        OUTPUT: Configuration object with custom settings
        USE CASE: Development and testing with custom settings
    #>
    [CmdletBinding()]
    [OutputType([ScriptConfiguration])]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$BatchSize,

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
        [string]$LogLevel,

        [Parameter()]
        [switch]$EnableDetailedLogging,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog -Level "Information" -Message "Initializing script configuration" -Component 'Configuration' -CorrelationId $CorrelationId

        # Load configuration from file or create default
        if ($ConfigPath -and (Test-Path $ConfigPath)) {
            Write-StructuredLog -Level "Information" -Message "Loading configuration from file: $ConfigPath" -Component 'Configuration' -CorrelationId $CorrelationId
            $config = [ScriptConfiguration]::LoadFromFile($ConfigPath)
        }
        else {
            Write-StructuredLog -Level "Information" -Message "Creating default configuration" -Component 'Configuration' -CorrelationId $CorrelationId
            $config = [ScriptConfiguration]::new()
        }

        # Apply parameter overrides
        if ($PSBoundParameters.ContainsKey('BatchSize')) {
            Write-StructuredLog -Level "Debug" -Message "Overriding BatchSize: $BatchSize" -Component 'Configuration' -CorrelationId $CorrelationId
            $config.BatchSize = $BatchSize
        }

        if ($PSBoundParameters.ContainsKey('LogLevel')) {
            Write-StructuredLog -Level "Debug" -Message "Overriding LogLevel: $LogLevel" -Component 'Configuration' -CorrelationId $CorrelationId
            $config.LogLevel = $LogLevel
        }

        if ($PSBoundParameters.ContainsKey('EnableDetailedLogging')) {
            Write-StructuredLog -Level "Debug" -Message "Overriding EnableDetailedLogging: $EnableDetailedLogging" -Component 'Configuration' -CorrelationId $CorrelationId
            $config.EnableDetailedLogging = $EnableDetailedLogging.IsPresent
        }

        # Final validation
        if (-not $config.ValidateConfiguration()) {
            throw "Configuration validation failed after parameter overrides"
        }

        Write-StructuredLog -Level "Information" -Message "Configuration initialized successfully" -Component 'Configuration' -CorrelationId $CorrelationId
        return $config

    }
    catch {
        Write-StructuredLog -Level "Error" -Message "Failed to initialize configuration: $($_.Exception.Message)" -Component 'Configuration' -CorrelationId $CorrelationId
        throw
    }
}

function Export-ConfigurationTemplate {
    <#
    .SYNOPSIS
        Exports a template JSON configuration file for customization.

    .DESCRIPTION
        Creates a complete JSON configuration template with all available
        settings, comments, and examples for enterprise customization.

    .PARAMETER Path
        Path where the template file should be created

    .PARAMETER IncludeComments
        Include detailed comments in the JSON template

    .OUTPUTS
        [void] Creates JSON template file

    .EXAMPLE
        PS> Export-ConfigurationTemplate -Path "C:\Config\template.json" -IncludeComments

        DESCRIPTION: Creates comprehensive configuration template
        OUTPUT: JSON file with all configuration options
        USE CASE: Setting up enterprise configuration standards
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeComments,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        if ($PSCmdlet.ShouldProcess($Path, "Create Configuration Template")) {
            Write-StructuredLog -Level "Information" -Message "Creating configuration template: $Path" -Component 'Configuration' -CorrelationId $CorrelationId

            $template = [ordered]@{
                '$schema' = 'https://json-schema.org/draft/2020-12/schema'
                'title' = 'Find-UnknownSIDs Configuration'
                'description' = 'Configuration file for Find-UnknownSIDs PowerShell script'
                'BatchSize' = 100
                'MemoryCheckInterval' = 25
                'EnableDetailedLogging' = $false
                'LogLevel' = 'Information'
                'LogFilePath' = 'C:\Logs\Find-UnknownSIDs.log'
                'EnableLogFileRotation' = $true
                'MaxLogFileSizeMB' = 10
                'WellKnownSIDPatterns' = @(
                    '^S-1-1-0$',
                    '^S-1-5-11$',
                    '^S-1-5-32-',
                    '^S-1-3-[0-4]$',
                    '^S-1-5-18$',
                    '^S-1-5-19$',
                    '^S-1-5-20$'
                )
                'ProtectedSIDs' = @(
                    'S-1-5-32-544',
                    'S-1-5-32-545',
                    'S-1-5-18',
                    'S-1-5-19',
                    'S-1-5-20'
                )
                'CriticalObjectPatterns' = @(
                    '*CN=Domain Admins*',
                    '*CN=Enterprise Admins*',
                    '*CN=Schema Admins*',
                    '*CN=BUILTIN*'
                )
            }

            if ($IncludeComments) {
                $template['_comments'] = @{
                    'BatchSize' = 'Number of objects to process in each batch (1-1000)'
                    'MemoryCheckInterval' = 'Check memory usage every N operations (1-100)'
                    'LogLevel' = 'Logging level: Critical, Error, Warning, Information, Debug, Verbose'
                    'WellKnownSIDPatterns' = 'Regex patterns for well-known SIDs to exclude from processing'
                    'ProtectedSIDs' = 'SIDs that should never be removed for security'
                    'CriticalObjectPatterns' = 'AD object patterns to protect from modification'
                }
            }

            $templateJson = $template | ConvertTo-Json -Depth 10
            $templateJson | Out-File -FilePath $Path -Encoding UTF8

            Write-StructuredLog -Level "Information" -Message "Configuration template created successfully" -Component 'Configuration' -CorrelationId $CorrelationId
        }
    }
    catch {
        Write-StructuredLog -Level "Error" -Message "Failed to create configuration template: $($_.Exception.Message)" -Component 'Configuration' -CorrelationId $CorrelationId
        throw
    }
}

function Test-ConfigurationCompliance {
    <#
    .SYNOPSIS
        Tests configuration against enterprise compliance standards.

    .DESCRIPTION
        Validates configuration settings against enterprise security and
        operational standards, providing compliance reporting.

    .PARAMETER Configuration
        ScriptConfiguration object to test

    .PARAMETER ComplianceProfile
        Compliance profile to validate against

    .OUTPUTS
        [hashtable] Compliance test results

    .EXAMPLE
        PS> $results = Test-ConfigurationCompliance -Configuration $config -ComplianceProfile "Enterprise"

        DESCRIPTION: Tests configuration against enterprise standards
        OUTPUT: Hashtable with compliance results
        USE CASE: Ensuring configuration meets organizational requirements
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptConfiguration]$Configuration,

        [Parameter()]
        [ValidateSet('Basic', 'Enterprise', 'HighSecurity')]
        [string]$ComplianceProfile = 'Basic',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        Write-StructuredLog -Level "Information" -Message "Starting configuration compliance test with profile: $ComplianceProfile" -Component 'Configuration' -CorrelationId $CorrelationId

        # Validate configuration object
        if (-not $Configuration) {
            throw "Configuration parameter is required for compliance testing"
        }

        $complianceResults = @{
            Profile = $ComplianceProfile
            TestTime = Get-Date
            OverallCompliant = $false
            PassedTests = @()
            FailedTests = @()
            Warnings = @()
            Score = 0
            MaxScore = 0
        }

        # Define compliance tests based on profile
        $tests = switch ($ComplianceProfile) {
            'Basic' {
                @{
                    'BatchSizeReasonable' = { $Configuration.BatchSize -le 500 }
                    'LoggingEnabled' = { -not [string]::IsNullOrEmpty($Configuration.LogLevel) }
                    'ProtectedSIDsPresent' = { $Configuration.ProtectedSIDs.Count -gt 0 }
                }
            }
            'Enterprise' {
                @{
                    'BatchSizeOptimal' = { $Configuration.BatchSize -le 200 }
                    'MemoryCheckFrequent' = { $Configuration.MemoryCheckInterval -le 25 }
                    'LogRotationEnabled' = { $Configuration.EnableLogFileRotation }
                    'LogSizeControlled' = { $Configuration.MaxLogFileSizeMB -le 50 }
                    'DetailedLoggingDisabled' = { -not $Configuration.EnableDetailedLogging }
                    'MinimalProtectedSIDs' = { $Configuration.ProtectedSIDs.Count -ge 5 }
                    'CriticalPatternsPresent' = { $Configuration.CriticalObjectPatterns.Count -ge 3 }
                }
            }
            'HighSecurity' {
                @{
                    'SmallBatchSize' = { $Configuration.BatchSize -le 100 }
                    'FrequentMemoryCheck' = { $Configuration.MemoryCheckInterval -le 10 }
                    'InformationLogging' = { $Configuration.LogLevel -in @('Information', 'Warning', 'Error', 'Critical') }
                    'LogFileSpecified' = { -not [string]::IsNullOrEmpty($Configuration.LogFilePath) }
                    'ComprehensiveProtection' = { $Configuration.ProtectedSIDs.Count -ge 6 }
                    'ExtensiveCriticalPatterns' = { $Configuration.CriticalObjectPatterns.Count -ge 4 }
                    'SecureDefaults' = { $Configuration.WellKnownSIDPatterns.Count -ge 10 }
                }
            }
        }

        # Execute compliance tests
        foreach ($testName in $tests.Keys) {
            $complianceResults.MaxScore++
            try {
                $testResult = & $tests[$testName]
                if ($testResult) {
                    $complianceResults.PassedTests += $testName
                    $complianceResults.Score++
                    Write-StructuredLog -Level "Debug" -Message "Compliance test passed: $testName" -Component 'Configuration' -CorrelationId $CorrelationId
                }
                else {
                    $complianceResults.FailedTests += $testName
                    Write-StructuredLog -Level "Warning" -Message "Compliance test failed: $testName" -Component 'Configuration' -CorrelationId $CorrelationId
                }
            }
            catch {
                $complianceResults.FailedTests += $testName
                Write-StructuredLog -Level "Error" -Message "Compliance test error for $testName : $($_.Exception.Message)" -Component 'Configuration' -CorrelationId $CorrelationId
            }
        }

        # Calculate overall compliance
        $complianceResults.OverallCompliant = $complianceResults.FailedTests.Count -eq 0

        Write-StructuredLog -Level "Information" -Message "Configuration compliance test completed. Score: $($complianceResults.Score)/$($complianceResults.MaxScore)" -Component 'Configuration' -CorrelationId $CorrelationId

        return $complianceResults

    }
    catch {
        Write-StructuredLog -Level "Error" -Message "Configuration compliance test failed: $($_.Exception.Message)" -Component 'Configuration' -CorrelationId $CorrelationId
        throw
    }
}

#endregion

#region Module Exports

# Note: Functions are automatically available when file is dot-sourced
# Export-ModuleMember is only used in actual .psm1 module files

#endregion
