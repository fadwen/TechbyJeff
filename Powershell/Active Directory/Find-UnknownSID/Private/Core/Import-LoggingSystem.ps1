#Requires -Version 5.1

<#
.SYNOPSIS
    Master logging module loader for Find-UnknownSID modular logging system

.DESCRIPTION
    Loads all logging system components in the correct dependency order.
    This module replaces the monolithic Logging.ps1 and provides a single
    entry point for importing the complete modular logging system.

    Module Loading Order:
    1. Initialize-LoggingConfiguration.ps1 - Shared state and configuration
    2. Initialize-LogDirectory.ps1 - File system operations
    3. Initialize-LoggingSystem.ps1 - Core logging initialization
    4. Format-LogMessage.ps1 - Message formatting utilities
    5. Protect-LogMessage.ps1 - Security and sanitization
    6. Write-StructuredLogEntry.ps1 - Core log writing
    7. Write-SecurityStructuredLogEntry.ps1 - Security-specific structured logging
    8. Write-SecurityLogEvent.ps1 - Security event logging
    9. Get-LogFileSummary.ps1 - Log analysis
    10. Export-DiagnosticData.ps1 - Diagnostic data export

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    IMPORTANT: This module must be dot-sourced to ensure script variables
    are available in the calling scope, just like the original Logging.ps1

    TROUBLESHOOTING:
    - For module loading issues: .\Troubleshooting\Common\Module-Loading.md
    - For dependency problems: .\Troubleshooting\Common\Dependency-Resolution.md

.EXAMPLE
    PS> . .\Private\Import-LoggingSystem.ps1

    Loads the complete modular logging system (dot-sourcing preserves variable scope)
#>

# Module loading configuration
$LoggingModuleInfo = @{
    Version = '2.0.0'
    LoadStartTime = Get-Date
    ModulesPath = $null
    LoadedModules = @()
    LoadErrors = @()
}

try {
    # Determine the base path for logging modules
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        $scriptPath = $PSCommandPath
    }

    # Since this script is now in Private\Core\, we need to go up one level to get to Private\
    $coreFolder = Split-Path -Parent $scriptPath
    $moduleBasePath = Split-Path -Parent $coreFolder
    $LoggingModuleInfo.ModulesPath = $moduleBasePath

    Write-Verbose "Loading modular logging system from: $moduleBasePath"

    # Define module loading order with dependencies
    $moduleLoadOrder = @(
        @{
            Name = 'Initialize-LoggingConfiguration'
            Path = 'Logging\Initialize-LoggingConfiguration.ps1'
            Description = 'Shared logging state and configuration'
            Required = $true
        },
        @{
            Name = 'Initialize-LogDirectory'
            Path = 'FileSystem\Initialize-LogDirectory.ps1'
            Description = 'Log directory and path management'
            Required = $true
        },
        @{
            Name = 'Initialize-LoggingSystem'
            Path = 'Logging\Initialize-LoggingSystem.ps1'
            Description = 'Core logging system initialization'
            Required = $true
        },
        @{
            Name = 'Format-LogMessage'
            Path = 'Logging\Format-LogMessage.ps1'
            Description = 'Log message formatting utilities'
            Required = $true
        },
        @{
            Name = 'Protect-LogMessage'
            Path = 'Logging\Protect-LogMessage.ps1'
            Description = 'Log message sanitization and security'
            Required = $true
        },
        @{
            Name = 'Write-StructuredLogEntry'
            Path = 'Logging\Write-StructuredLogEntry.ps1'
            Description = 'Core structured log writing'
            Required = $true
        },
        @{
            Name = 'Write-StructuredLog'
            Path = 'Logging\Write-StructuredLog.ps1'
            Description = 'Wrapper for Write-StructuredLogEntry with backwards compatibility'
            Required = $true
        },
        @{
            Name = 'Write-SecurityStructuredLogEntry'
            Path = 'Logging\Write-SecurityStructuredLogEntry.ps1'
            Description = 'Security-specific structured logging (bypasses log level filtering)'
            Required = $true   # Required for compliance-grade security logging
        },
        @{
            Name = 'Write-SecurityLog'
            Path = 'Logging\Write-SecurityLog.ps1'
            Description = 'Legacy security audit logging'
            Required = $true   # Required for AD operation security logging
        },
        @{
            Name = 'Write-SecurityLogEvent'
            Path = 'Logging\Write-SecurityLogEvent.ps1'
            Description = 'Enhanced security event logging'
            Required = $false  # Optional for basic logging
        },
        @{
            Name = 'Write-ADOperationSecurityLog'
            Path = 'Logging\Write-ADOperationSecurityLog.ps1'
            Description = 'AD operation security audit logging'
            Required = $true   # Required for AD operation security logging
        },
        @{
            Name = 'Get-LogFileSummary'
            Path = 'Reporting\Get-LogFileSummary.ps1'
            Description = 'Log file analysis and summary'
            Required = $false  # Optional for basic logging
        },
        @{
            Name = 'Export-DiagnosticData'
            Path = 'Reporting\Export-DiagnosticData.ps1'
            Description = 'Diagnostic data export'
            Required = $false  # Optional for basic logging
        }
    )

    # Load each module in dependency order
    foreach ($module in $moduleLoadOrder) {
        $modulePath = Join-Path $moduleBasePath $module.Path

        Write-Verbose "Loading module: $($module.Name) from $modulePath"

        if (Test-Path $modulePath) {
            try {
                # Dot-source the module to preserve variable scope
                . $modulePath

                $LoggingModuleInfo.LoadedModules += @{
                    Name = $module.Name
                    Path = $modulePath
                    LoadedAt = Get-Date
                    Success = $true
                    Description = $module.Description
                }

                Write-Verbose "Successfully loaded: $($module.Name)"
            }
            catch {
                $errorInfo = @{
                    Name = $module.Name
                    Path = $modulePath
                    LoadedAt = Get-Date
                    Success = $false
                    Error = $_.Exception.Message
                    Required = $module.Required
                    Description = $module.Description
                }

                $LoggingModuleInfo.LoadErrors += $errorInfo

                if ($module.Required) {
                    Write-Error "Failed to load required logging module '$($module.Name)': $($_.Exception.Message)"
                    throw "Critical logging module failure: $($module.Name)"
                }
                else {
                    Write-Warning "Failed to load optional logging module '$($module.Name)': $($_.Exception.Message)"
                }
            }
        }
        else {
            $errorInfo = @{
                Name = $module.Name
                Path = $modulePath
                LoadedAt = Get-Date
                Success = $false
                Error = "Module file not found"
                Required = $module.Required
                Description = $module.Description
            }

            $LoggingModuleInfo.LoadErrors += $errorInfo

            if ($module.Required) {
                Write-Error "Required logging module not found: $modulePath"
                throw "Missing critical logging module: $($module.Name)"
            }
            else {
                Write-Warning "Optional logging module not found: $modulePath"
            }
        }
    }

    # Module loading completed
    $LoggingModuleInfo.LoadCompletedAt = Get-Date
    $LoggingModuleInfo.LoadDurationMs = ($LoggingModuleInfo.LoadCompletedAt - $LoggingModuleInfo.LoadStartTime).TotalMilliseconds

    $loadedCount = ($LoggingModuleInfo.LoadedModules | Where-Object { $_.Success }).Count
    $totalCount = $moduleLoadOrder.Count
    $errorCount = $LoggingModuleInfo.LoadErrors.Count

    Write-Verbose "Modular logging system loaded: $loadedCount/$totalCount modules successful, $errorCount errors"

    # Create summary for troubleshooting
    if ($LoggingModuleInfo.LoadErrors.Count -gt 0) {
        Write-Verbose "Module loading errors:"
        foreach ($error in $LoggingModuleInfo.LoadErrors) {
            Write-Verbose "  - $($error.Name): $($error.Error)"
        }
    }

    # Validate critical functions are available
    $criticalFunctions = @('Initialize-LoggingSystem', 'Write-StructuredLogEntry', 'Initialize-LogDirectory')
    $missingFunctions = @()

    foreach ($func in $criticalFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            $missingFunctions += $func
        }
    }

    if ($missingFunctions.Count -gt 0) {
        throw "Critical logging functions not available after module loading: $($missingFunctions -join ', ')"
    }

    # Set up aliases for backward compatibility if needed
    # These maintain compatibility with the original monolithic Logging.ps1
    # Use New-Alias with -Force to avoid WhatIf impact
    if (Get-Command Write-StructuredLogEntry -ErrorAction SilentlyContinue) {
        if (Get-Alias -Name 'Write-StructuredLog' -ErrorAction SilentlyContinue) {
            Remove-Item -Path "alias:Write-StructuredLog" -Force -ErrorAction SilentlyContinue
        }
        # REMOVED: Alias that was conflicting with Write-StructuredLog function
        # New-Alias -Name 'Write-StructuredLog' -Value 'Write-StructuredLogEntry' -Scope Script -Force -WhatIf:$false
    }

    # DISABLED: Problematic alias that overrides Write-SecurityLog function
    # This alias causes Write-SecurityLog calls to redirect to Write-SecurityLogEvent
    # which uses Debug level for Success outcomes, causing entries to be filtered out
    # if (Get-Command Write-SecurityLogEvent -ErrorAction SilentlyContinue) {
    #     if (Get-Alias -Name 'Write-SecurityLog' -ErrorAction SilentlyContinue) {
    #         Remove-Item -Path "alias:Write-SecurityLog" -Force -ErrorAction SilentlyContinue
    #     }
    #     New-Alias -Name 'Write-SecurityLog' -Value 'Write-SecurityLogEvent' -Scope Script -Force -WhatIf:$false
    # }

    if (Get-Command Initialize-LoggingSystem -ErrorAction SilentlyContinue) {
        if (Get-Alias -Name 'Initialize-ScriptLogging' -ErrorAction SilentlyContinue) {
            Remove-Item -Path "alias:Initialize-ScriptLogging" -Force -ErrorAction SilentlyContinue
        }
        New-Alias -Name 'Initialize-ScriptLogging' -Value 'Initialize-LoggingSystem' -Scope Script -Force -WhatIf:$false
    }

    Write-Verbose "Modular logging system initialization completed successfully"
}
catch {
    Write-Error "Failed to load modular logging system: $($_.Exception.Message)"

    # Provide fallback logging if possible
    if (-not (Get-Command Write-StructuredLogEntry -ErrorAction SilentlyContinue)) {
        function Write-StructuredLogEntry {
            param(
                [string]$Message,
                [string]$Level = 'Information',
                [string]$Component = 'Fallback',
                [string]$CorrelationId = 'unknown'
            )
            Write-Host "[$Level] $Component - $Message (CorrelationId: $CorrelationId)" -ForegroundColor Yellow
        }
        Write-Warning "Using fallback logging function due to module loading failure"
    }

    throw
}

# Export module loading information for diagnostics
function Get-LoggingModuleInfo {
    <#
    .SYNOPSIS
        Gets information about the loaded logging modules

    .DESCRIPTION
        Returns diagnostic information about the modular logging system
        including loaded modules, errors, and performance metrics.

    .OUTPUTS
        PSCustomObject containing module loading information
    #>

    return [PSCustomObject]$LoggingModuleInfo
}
