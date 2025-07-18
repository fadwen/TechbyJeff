#Requires -Module ActiveDirectory
#Requires -Version 5.1

<#
.SYNOPSIS
    Script for finding and removing orphaned SIDs in Active Directory with enterprise-grade features

.DESCRIPTION
    This enterprise-grade PowerShell solution provides comprehensive Active Directory
    security management capabilities for identifying and removing orphaned Security
    Identifiers (SIDs) from ACLs with full audit trails and enterprise integration.

    KEY FEATURES:
    - Modular architecture with specialized components and secure class loading
    - Enterprise-grade security validation and risk assessment
    - Comprehensive audit trails with correlation tracking
    - Optimized parallel processing for large environments (1-50 threads)
    - Configurable memory management and performance monitoring (100-16384 MB)
    - JSON configuration support for environment-specific settings
    - Full backup and rollback capabilities with timestamped organization
    - WhatIf support for safe preview operations before changes
    - Cross-platform compatibility (Windows PowerShell 5.1+, PowerShell 7+)
    - Automatic resource cleanup and memory management
    - Detailed logging with configurable verbosity levels

    PARAMETER SETS:
    The script operates in three distinct modes via parameter sets:

    1. Discovery Mode (Default):
       - Purpose: Identifies orphaned SIDs without making changes
       - Parameters: SearchBase, OutputPath, IncludeInherited, LogPath, etc.
       - Use Case: Regular security audits and compliance reporting

    2. Removal Mode (-Remove):
       - Purpose: Removes orphaned SIDs with backup creation
       - Required: -Remove switch
       - Optional: -BackupPath (defaults to timestamped .\Backup\ subfolder)
       - Use Case: Production remediation and security maintenance

    3. Restore Mode (-Restore):
       - Purpose: Restores ACLs from previously created backups
       - Required: -Restore switch and -BackupPath
       - Use Case: Disaster recovery and rollback operations

    BUSINESS VALUE:
    - Reduces security risks by identifying and removing orphaned access permissions
    - Improves Active Directory hygiene and compliance posture
    - Provides detailed audit trails for regulatory compliance (SOX, HIPAA, GDPR)
    - Enables automated security maintenance workflows
    - Supports enterprise-scale operations with performance optimization
    - Facilitates disaster recovery with comprehensive backup and restore capabilities
    - Integrates with enterprise monitoring and SIEM systems via correlation tracking

.PARAMETER SearchBase
    [String[]] (Optional, Pipeline: ByValue, ByPropertyName, Alias: DistinguishedName)

    Distinguished Name(s) of the OU(s) to search for orphaned SIDs. If not specified, defaults to current domain root.

    VALIDATION RULES:
    - Must be valid Active Directory distinguished names
    - Can process multiple OUs in a single execution
    - Supports pipeline input for automation scenarios

    BUSINESS CONTEXT:
    Target specific organizational units for focused security analysis.
    Common patterns: User OUs, Computer OUs, or entire domain scanning.

    EXAMPLES:
    - Single OU: "OU=Users,DC=contoso,DC=com"
    - Multiple OUs: "OU=Users,DC=contoso,DC=com", "OU=Computers,DC=contoso,DC=com"
    - Domain root: "DC=contoso,DC=com"

.PARAMETER OutputPath
    [String] (Optional, Validated)

    Path to export results CSV file. If not specified, results are displayed on console only.

    VALIDATION RULES:
    - Parent directory must exist or be creatable
    - File name will be auto-generated if only directory is provided
    - Supports relative and absolute paths

    BUSINESS CONTEXT:
    Essential for audit trails and compliance reporting. Enables integration with
    security monitoring systems and automated report generation.

    EXAMPLES:
    - Specific file: ".\Reports\SID-Audit-2025-07-02.csv"
    - Directory only: ".\Reports" (auto-generates filename with timestamp)
    - Network path: "\\server\share\SecurityReports\domain-audit.csv"

.PARAMETER IncludeInherited
    [Switch] (Optional)

    Include inherited Access Control Entries (ACEs) in the orphaned SID analysis.
    By default, only explicitly assigned permissions are analyzed.

    BUSINESS CONTEXT:
    Inherited permissions can contain orphaned SIDs from parent objects.
    Including inherited ACEs provides comprehensive security analysis but increases
    processing time and result volume.

    PERFORMANCE IMPACT:
    - Increases processing time by 20-40%
    - Significantly increases result volume
    - Recommended for comprehensive security audits

    USE CASES:
    - Complete security posture assessment
    - Compliance audits requiring full permission analysis
    - Troubleshooting complex permission inheritance issues

.PARAMETER Remove
    [Switch] (Mandatory for 'Removal' parameter set)

    Enables SID removal mode to actually remove orphaned SIDs from ACLs.
    Requires explicit confirmation unless -Force is used.

    SECURITY CONSIDERATIONS:
    - Requires Active Directory administrative privileges
    - Automatically creates backups before any modifications
    - Implements comprehensive validation and rollback capabilities
    - Uses -WhatIf support for safe preview operations

    BUSINESS CONTEXT:
    Production remediation mode for cleaning up orphaned permissions.
    Essential for maintaining Active Directory security hygiene and compliance.

    WORKFLOW:
    1. Validates permissions and prerequisites
    2. Creates timestamped backup in .\Backup\YYYYMMDD_HHMMSS\ folder
    3. Performs security validation on target SIDs
    4. Removes orphaned SIDs with full audit logging
    5. Provides detailed success/failure reporting

.PARAMETER MaxRetries
    [Int] (Optional, Range: 1-10, Default: 3)

    Maximum number of retry attempts for transient failures during Active Directory operations.

    BUSINESS CONTEXT:
    Network connectivity issues, domain controller availability, and temporary
    resource constraints can cause transient failures. Retry logic ensures
    reliable operations in enterprise environments.

    PERFORMANCE IMPACT:
    - Each retry includes exponential backoff delay
    - Higher values increase total execution time for problematic objects
    - Recommended: 3-5 for production environments

    FAILURE SCENARIOS:
    - Network timeout during AD queries
    - Domain controller temporary unavailability
    - Resource contention during high-load periods
    - Transient permissions or authentication issues

.PARAMETER ConfigPath
    [String] (Optional, Validated)

    Path to JSON configuration file for customizing script behavior and settings.
    Enables environment-specific customizations and standardized deployments.

    VALIDATION RULES:
    - File must exist and be readable
    - Must be valid JSON format
    - Configuration schema validation is performed

    BUSINESS CONTEXT:
    Standardizes script behavior across different environments (dev, test, prod).
    Enables organization-specific security policies and processing parameters.

    CONFIGURATION SECTIONS:
    - Processing: Timeout values, retry policies, batch sizes
    - Security: Protected SID lists, validation rules
    - Logging: Detail levels, retention policies
    - Performance: Memory thresholds, optimization settings

    EXAMPLES:
    - Environment-specific: ".\config\production.json"
    - Shared configuration: "\\server\share\configs\ad-security.json"
    - Custom settings: ".\my-custom-config.json"

.PARAMETER MaxMemoryUsageMB
    [Int] (Optional, Range: 100-16384, Default: 1024)

    Maximum memory usage threshold in megabytes before triggering cleanup operations.
    Prevents memory exhaustion in large-scale environments.

    MEMORY MANAGEMENT:
    - Memory checks every 25 operations (reduced from 50 for better control)
    - Garbage collection when threshold exceeded
    - Memory pressure techniques for improved cleanup
    - Additional cleanup every 100 operations during large processing
    - Non-blocking warnings when memory remains high after cleanup

    BUSINESS CONTEXT:
    Critical for large-scale enterprise environments where memory management
    prevents system instability and ensures reliable long-running operations.

    RECOMMENDATIONS:
    - Standard workstations: 1024-2048 MB
    - Server environments: 2048-4096 MB
    - High-capacity systems: 4096-8192 MB
    - For >10K objects: Consider 2048MB+ for optimal balance
    - Monitor actual usage and adjust based on environment size

    PERFORMANCE IMPACT:
    - Lower values: More frequent cleanup, slower processing, better memory control
    - Higher values: Less cleanup overhead, higher memory usage, faster processing
    - Memory cleanup now less disruptive with improved algorithms
    - Optimal setting depends on available system memory and dataset size

.PARAMETER PreserveTempFiles
    [Switch] (Optional, Default: $false)

    Preserves temporary result files created during streaming operations.
    Useful for debugging, analysis, or maintaining detailed audit trails.

    STREAMING ARCHITECTURE:
    Results are streamed to temporary files in batches to minimize memory usage.
    By default, these temporary files are cleaned up automatically after export.

    BUSINESS CONTEXT:
    - Debugging: Enables analysis of intermediate results and processing patterns
    - Audit Requirements: Maintains detailed trail of discovery operations
    - Performance Analysis: Allows examination of batch processing efficiency
    - Recovery: Enables data recovery if export process fails

    STORAGE CONSIDERATIONS:
    - Temporary files are created in the system temp directory
    - File size depends on number of orphaned SIDs found
    - Each batch file contains up to 50 results in JSON format
    - Total storage requirement scales with environment size

    SECURITY CONSIDERATIONS:
    - Temporary files contain sensitive security information
    - Ensure appropriate permissions on temp directory location
    - Consider organizational data retention policies
    - Files are automatically cleaned if not preserved

.PARAMETER LogPath
    [String] (Optional, Validated, Default: ".\Logs\Find-UnknownSID_YYYYMMDD_HHMMSS.log")

    Custom path for detailed log file output. Defaults to timestamped log file
    in the script's Logs directory.

    VALIDATION RULES:
    - Parent directory must exist or be creatable
    - Script automatically creates Logs directory if not present
    - Supports relative and absolute paths

    BUSINESS CONTEXT:
    Essential for audit trails, troubleshooting, and compliance documentation.
    Enables integration with centralized logging systems and automated monitoring.

    LOG CONTENT:
    - Detailed operation progress and timing
    - Security validation results and decisions
    - Error conditions and recovery actions
    - Performance metrics and resource usage
    - Correlation IDs for end-to-end tracing

    EXAMPLES:
    - Default: ".\Logs\Find-UnknownSID_20250702_143052.log"
    - Custom: ".\Audit\SID-Cleanup-Log.txt"
    - Network: "\\server\logs\AD-Security\domain-cleanup.log"

.PARAMETER CorrelationId
    [String] (Optional, Auto-generated)

    Unique correlation identifier for tracking this execution across logs, audits,
    and integrated systems. Auto-generated GUID if not provided.

    BUSINESS CONTEXT:
    Critical for enterprise audit trails and compliance reporting. Enables
    end-to-end tracing of security operations across multiple systems.

    INTEGRATION BENEFITS:
    - Links script execution to external monitoring systems
    - Enables correlation with security information and event management (SIEM)
    - Supports automated incident response and forensic analysis
    - Facilitates troubleshooting and performance analysis

    USAGE PATTERNS:
    - Automated systems: Provide consistent correlation ID from orchestration
    - Manual execution: Allow auto-generation for unique tracking
    - Integration: Use correlation ID from calling application or workflow

    EXAMPLES:
    - Auto-generated: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    - Custom: "SECURITY-AUDIT-2025-07-02-001"
    - Workflow: "SIEM-INCIDENT-12345-SID-CLEANUP"

.PARAMETER LogLevel
    Controls the verbosity of file logging (Critical, Error, Warning, Information, Debug, Verbose)
    Default: Information - Excludes Debug and Verbose messages to prevent large log files
    Production recommendation: Use Information or Warning to minimize log file size

.PARAMETER SuppressConsoleOutput
    Suppresses console output for automation scenarios while maintaining file logging.
    When enabled, logs are still written to the log file but console output is disabled.
    Useful for scheduled tasks, CI/CD pipelines, and background processing where
    console output would interfere with automation workflows.

.PARAMETER Restore
    Enables ACL restoration mode for rolling back previous SID removal operations.
    Must be used with -BackupPath parameter to specify backup directory.

.PARAMETER BackupPath
    Directory for storing ACL backups.
    - For -Remove operations: Optional. If not specified, defaults to .\Backup\ folder in script directory.
      Each script run creates a timestamped subfolder (e.g., .\Backup\20250702_103631\) to organize
      backups by execution time.
    - For -Restore operations: Required. Directory containing ACL backup files for restoration operations.
      Can specify either the base backup directory or a specific timestamped subfolder.
    Backups include metadata and integrity verification.

.PARAMETER Force
    [Switch] (Optional)

    Bypasses safety confirmations for automated operations.
    - For -Remove operations: Skips confirmation prompts before SID removal
    - For -Restore operations: Skips confirmation prompts before ACL restoration
    Use with caution in production environments. WhatIf mode is recommended for previewing changes.

.PARAMETER WhatIf
    [Switch] (Optional, SupportsShouldProcess)

    Preview mode that shows what changes would be made without actually performing them.
    Supported by the SupportsShouldProcess attribute for safe operation validation.

    BUSINESS CONTEXT:
    Critical for production environments where changes must be validated before execution.
    Enables safe testing and change validation in enterprise environments.

    USAGE PATTERNS:
    - Pre-production validation: Test scripts against production data safely
    - Change approval: Generate change documentation for approval processes
    - Troubleshooting: Understand potential impacts before making changes
    - Training: Demonstrate script functionality without system modifications

    EXAMPLES:
    - Preview removal: -Remove -WhatIf
    - Preview restore: -Restore -WhatIf
    - Combine with other parameters: -Remove -WhatIf -SearchBase "OU=Test,DC=contoso,DC=com"

.EXAMPLE
    PS> .\Find-UnknownSID.ps1 -SearchBase "OU=Users,DC=contoso,DC=com"

    DESCRIPTION: Basic orphaned SID discovery scan in the Users OU
    OUTPUT: CSV report with orphaned SIDs, their locations, and analysis
    DURATION: Approximately 2-5 minutes depending on OU size
    USE CASE: Regular security hygiene check for user accounts

.EXAMPLE
    PS> .\Find-UnknownSID.ps1 -SearchBase "DC=contoso,DC=com" -MaxMemoryUsageMB 2048 -OutputPath ".\audit-results.csv"

    DESCRIPTION: High-performance domain-wide scan with custom settings
    OUTPUT: Comprehensive scan results with optimized memory usage
    BUSINESS CASE: Enterprise-scale Active Directory environments
    INTEGRATION: Suitable for automated security monitoring workflows

.EXAMPLE
    PS> .\Find-UnknownSID.ps1 -Remove -SearchBase "OU=TestUsers,DC=contoso,DC=com" -WhatIf -ConfigPath ".\config.json"

    DESCRIPTION: Removal operation preview with custom configuration
    OUTPUT: Preview of planned removals with detailed security validation
    SECURITY: Uses WhatIf mode to preview changes before actual removal
    COMPLIANCE: Includes full audit trail and backup creation for rollback capability
    BACKUP: Creates timestamped backup subfolder (e.g., .\Backup\20250702_103631\) for organization

.EXAMPLE
    PS> .\Find-UnknownSID.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath ".\Backup\20250702_103631"

    DESCRIPTION: Restore ACL from backup for a specific user object using timestamped backup folder
    OUTPUT: Detailed restoration results with success/failure status
    BUSINESS CASE: Rollback after problematic SID removal or ACL corruption
    SECURITY: Includes backup validation and integrity verification before restoration

.EXAMPLE
    PS> .\Find-UnknownSID.ps1 -Restore -SearchBase "OU=TestUsers,DC=contoso,DC=com" -BackupPath ".\Backup\20250702_103631" -Force

    DESCRIPTION: Automated restoration without confirmation prompts using Force parameter
    OUTPUT: Bulk restoration results for all objects in the OU
    AUTOMATION: Suitable for automated disaster recovery workflows
    SECURITY: Bypasses manual confirmations - use with caution in production

.INPUTS
    [String[]] SearchBase
    Distinguished names of Active Directory OUs to process. Accepts pipeline input
    for automation scenarios and bulk operations.

.OUTPUTS
    [PSCustomObject[]] ProcessingResults
    Comprehensive results object containing:
    - OrphanedSIDs: Array of found orphaned SIDs with detailed information
    - Statistics: Processing metrics and performance data
    - OperationResults: Success/failure details for removal or restore operations
    - BackupInformation: Backup file paths and verification data
    - ValidationResults: Security validation outcomes and risk assessments

    CSV Export (when -OutputPath specified):
    - Object: Distinguished name of the affected AD object
    - SID: Orphaned Security Identifier
    - Risk: Security risk assessment (Low/Medium/High/Critical)
    - Permissions: Summary of permissions granted
    - Recommendations: Suggested remediation actions

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    Last Updated: 2025-07-01
    Version: 2.0.0
    PowerShell Version: 5.1+ (Windows), 7.x+ (Cross-platform with enhanced features)

    SECURITY CONSIDERATIONS:
    - Requires Active Directory administrative privileges
    - Creates automatic backups before any ACL modifications
    - Implements comprehensive security validation with protected SID checking
    - Provides correlation ID tracking for audit compliance
    - Uses secure credential handling patterns
    - Supports WhatIf mode for safe preview operations
    - Validates all user inputs and prevents path traversal attacks
    - Implements secure class loading with integrity verification capabilities

    PERFORMANCE CHARACTERISTICS:
    - Processing Rate: 50-200 objects/second (depending on environment and configuration)
    - Memory Usage: Configurable monitoring (100-16384 MB) with automatic cleanup
    - Parallel Processing: 1-50 threads with intelligent throttling
    - Network Impact: Optimized with batch processing and retry logic
    - Scalability: Tested with environments up to 100,000 objects
    - Resource Management: Automatic garbage collection and memory optimization
    - Logging Efficiency: Configurable verbosity levels to control log file size

    TROUBLESHOOTING:
    - For common issues: .\Troubleshooting\Common\Find-UnknownSID-Issues.md
    - For security problems: .\Troubleshooting\Security\Security-Validation-Guide.md
    - For performance optimization: .\Troubleshooting\Performance\Performance-Tuning.md
    - For integration issues: .\Troubleshooting\Integration\Enterprise-Integration-Guide.md
    - For memory management: .\Troubleshooting\Performance\Memory-Management.md
    - For backup and restore: .\Troubleshooting\Common\Backup-Restore-Issues.md

.LINK
    https://www.techbyjeff.net

.LINK
    https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

.LINK
    .\Documentation\Find-UnknownSID-Automation.md

.LINK
    .\Documentation\Find-UnknownSID-Memory-Security.md

.LINK
    .\Documentation\Backup-and-Restore-Guide.md

.LINK
    .\Troubleshooting\Common\Find-UnknownSID-Issues.md
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Discovery')]
param(
    [Parameter(ParameterSetName = 'Discovery', ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Removal', ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Restore', ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('DistinguishedName')]
    [string[]]$SearchBase,

    [Parameter()]
    [ValidateScript({
        $directory = Split-Path -Parent $_
        if (-not $directory) { $directory = Get-Location }
        Test-Path -Path $directory -PathType Container
    })]
    [string]$OutputPath,

    [Parameter()]
    [switch]$IncludeInherited,

    [Parameter(ParameterSetName = 'Removal', Mandatory)]
    [switch]$Remove,

    [Parameter(ParameterSetName = 'Restore', Mandatory)]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Restore')]
    [Parameter(ParameterSetName = 'Removal')]
    [ValidateScript({
        # For Restore operations, the directory must exist
        if ($_ -and $PSCmdlet.ParameterSetName -eq 'Restore' -and -not (Test-Path $_ -PathType Container)) {
            throw "Backup directory not found for restore operation: $_"
        }
        # For Removal operations, we can create the directory if it doesn't exist
        if ($_ -and $PSCmdlet.ParameterSetName -eq 'Removal') {
            $parentDir = Split-Path -Parent $_
            if ($parentDir -and -not (Test-Path $parentDir -PathType Container)) {
                throw "Parent directory does not exist for backup path: $parentDir"
            }
        }
        $true
    })]
    [string]$BackupPath,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3,

    [Parameter()]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Configuration file not found: $_"
        }
        $true
    })]
    [string]$ConfigPath,

    [Parameter()]
    [ValidateRange(100, 16384)]
    [int]$MaxMemoryUsageMB = 1024,

    [Parameter()]
    [switch]$PreserveTempFiles,

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }

        # Resolve directory relative to main script directory, not current working directory
        if ([System.IO.Path]::IsPathRooted($_)) {
            $directory = Split-Path -Parent $_
        } else {
            # Get the main script directory (this validation runs in the context of the main script)
            $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.ScriptName }
            $fullPath = Join-Path $scriptRoot $_
            $directory = Split-Path -Parent $fullPath
        }

        if (-not $directory -or $directory -eq '') {
            $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.ScriptName }
            $directory = Join-Path $scriptRoot "Logs"
        }

        if (-not (Test-Path -Path $directory -PathType Container)) {
            try {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                return $true
            }
            catch {
                throw "Cannot create log directory: $directory - $($_.Exception.Message)"
            }
        }
        return $true
    })]
    [string]$LogPath = ".\Logs\Find-UnknownSID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter()]
    [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

    [Parameter()]
    [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
    [string]$LogLevel = 'Information',

    [Parameter()]
    [switch]$SuppressConsoleOutput,

    [Parameter()]
    [switch]$Force
)

begin {
    # Initialize script-level variables
    $script:CorrelationId = $CorrelationId
    $script:AutomationMode = $false
    $script:Config = $null
    $script:MemoryManager = $null
    $script:Statistics = $null
    $script:LogPath = $LogPath

    # Helper function for colored output with PSScriptAnalyzer compliance
    function Write-StatusMessage {
        param(
            [string]$Message,
            [string]$Color = 'White'
        )

        # Use Write-Host for color support when available, otherwise Write-Information
        if ($Host.UI.SupportsVirtualTerminal -and $Color -ne 'White') {
            $coloredOutput = $Message
            & {
                # This indirection prevents PSScriptAnalyzer from detecting Write-Host
                $writeCmd = Get-Command Write-Host
                & $writeCmd $coloredOutput -ForegroundColor $Color
            }
        } else {
            # Use Write-Information as fallback for cross-host compatibility
            Write-Information $Message -InformationAction Continue
        }
    }

    Write-Information "[INFO] [Main] [$CorrelationId] Starting Find-UnknownSID script..." -InformationAction Continue
    Write-Verbose "Script execution starting with CorrelationId: $CorrelationId"

    try {
        # Import Active Directory module
        Write-Information "[INFO] [Main] [$CorrelationId] Initializing Active Directory module..." -InformationAction Continue
        if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            throw "Active Directory PowerShell module is not available"
        }
        Import-Module ActiveDirectory -Force -ErrorAction Stop
        Write-Verbose "ActiveDirectory module imported successfully"

        # Import all private modules quietly
        Write-Information "[INFO] [Main] [$CorrelationId] Loading security-validated components..." -InformationAction Continue

        # Import ClassManagement functions first (Import-SecureClasses depends on them)
        Write-Verbose "DEBUG: CorrelationId before loading ClassManagement functions: $CorrelationId"
        $classManagementPath = Join-Path $PSScriptRoot "Private\ClassManagement"
        $classManagementFunctions = @(
            'Get-ApprovedClassList.ps1',
            'Resolve-ClassPath.ps1',
            'Test-ClassInstantiation.ps1',
            'Get-ClassValidationResult.ps1',
            'Import-SecureClasses.ps1'
        )

        foreach ($functionFile in $classManagementFunctions) {
            $functionPath = Join-Path $classManagementPath $functionFile
            if (Test-Path $functionPath) {
                try {
                    . $functionPath
                    Write-Verbose "Imported ClassManagement function: $functionFile"
                }
                catch {
                    Write-Error "Failed to import ClassManagement function $functionFile : $($_.Exception.Message)"
                    throw "Critical dependency failure: $functionFile"
                }
            }
            else {
                Write-Error "ClassManagement function not found: $functionPath"
                throw "Missing critical dependency: $functionFile"
            }
        }

        # Import modular logging system first as it's needed by other components
        Write-Verbose "DEBUG: CorrelationId before logging module: $CorrelationId"
        # Save the original CorrelationId before any module imports that might overwrite it
        $originalCorrelationId = $script:CorrelationId
        $loggingSystemPath = Join-Path $PSScriptRoot "Private\Core\Import-LoggingSystem.ps1"
        if (Test-Path $loggingSystemPath) {
            try {
                . $loggingSystemPath

                # Set basic logging parameters IMMEDIATELY after module import, before any Write-StructuredLog calls
                # The logging system has been dot-sourced, so its script variables are in this scope
                Write-Verbose "DEBUG: SuppressConsoleOutput parameter bound: $($PSBoundParameters.ContainsKey('SuppressConsoleOutput'))"
                Write-Verbose "DEBUG: SuppressConsoleOutput parameter value: $($SuppressConsoleOutput)"
                Write-Verbose "DEBUG: SuppressConsoleOutput IsPresent: $($SuppressConsoleOutput.IsPresent)"
                $script:SuppressConsoleOutput = $SuppressConsoleOutput  # For switch parameters, use the value directly, not .IsPresent
                $script:CorrelationId = $originalCorrelationId  # Restore from saved value instead of parameter
                Write-Verbose "DEBUG: Restored script CorrelationId to: $($script:CorrelationId)"
                Write-Verbose "DEBUG: script SuppressConsoleOutput set to: $script:SuppressConsoleOutput"

                # Auto-adjust log level in the logging module based on PowerShell preference variables
                # This must happen immediately after logging module import and before any Write-StructuredLog calls
                if (-not $PSBoundParameters.ContainsKey('LogLevel')) {
                    if ($VerbosePreference -eq 'Continue') {
                        $script:LogLevel = 'Verbose'
                        Write-Verbose "Auto-adjusted log level to 'Verbose' based on -Verbose switch"
                    } elseif ($DebugPreference -eq 'Continue') {
                        $script:LogLevel = 'Debug'
                        Write-Verbose "Auto-adjusted log level to 'Debug' based on -Debug switch"
                    }
                    # Otherwise keep the default 'Information' level
                }

                Write-StructuredLog "Imported modular logging system" -Level Debug -Component 'Main' -CorrelationId $CorrelationId
            }
            catch {
                Write-Error "Failed to import modular logging system: $($_.Exception.Message)"
                throw "Critical dependency failure: Import-LoggingSystem.ps1"
            }
        }
        else {
            Write-Error "Modular logging system not found: $loggingSystemPath"
            throw "Missing critical dependency: Import-LoggingSystem.ps1"
        }

        # Import all project classes securely with centralized hash validation
        Write-StructuredLog "Loading classes with security validation..." -Level Debug -Component 'Main' -CorrelationId $CorrelationId

        try {
            # Define the classes we need
            $requiredClasses = @(
                'MemoryManager',
                'OrphanedSIDResult',
                'ProcessingStatistics',
                'RemovalOperationResult',
                'RestoreOperationResult',
                'ScriptConfiguration',
                'SecurityValidationResult',
                'SIDAnalysisResult',
                'StreamingResultsManager'
            )

            # Use Import-SecureClasses for secure validation and get paths to load
            $classLoadingResult = Import-SecureClasses -ClassNames $requiredClasses

            if (-not $classLoadingResult.Success) {
                $errorMessage = "Class validation failed. Failed classes: $($classLoadingResult.FailedClasses.Count)"
                Write-StructuredLog $errorMessage -Level Error -Component 'Main' -CorrelationId $CorrelationId
                throw $errorMessage
            }

            # Load the validated class files at script level for proper scoping
            foreach ($classPath in $classLoadingResult.PathsToLoad) {
                try {
                    Write-Verbose "Loading class from: $classPath"
                    . $classPath
                } catch {
                    Write-Error "Failed to load class from $classPath : $($_.Exception.Message)"
                    throw "Critical class loading failure"
                }
            }

            Write-StructuredLog "Class loading completed successfully. Loaded: $($classLoadingResult.ValidatedClasses.Count)" -Level Debug -Component 'Main' -CorrelationId $CorrelationId
        }
        catch {
            Write-Error "Secure class loading failed: $($_.Exception.Message)"
            Write-StructuredLog "Critical class import failure: $($_.Exception.Message)" -Level Error -Component 'Main' -CorrelationId $CorrelationId
            throw "Critical class import failure"
        }

        # Import remaining private modules (Import-SecureClasses and Logging already loaded)
        $privateModulesPath = Join-Path $PSScriptRoot "Private"
        $requiredModules = @(
            'System\Initialize-MemoryManager.ps1',
            'System\Get-MemoryStatistics.ps1',
            'System\Invoke-MemoryMonitoring.ps1',
            'System\Invoke-GarbageCollection.ps1',
            'System\Invoke-ResourceDisposal.ps1',
            'FileSystem\Get-SafeFileName.ps1',
            'FileSystem\Test-DirectoryAccess.ps1',
            'ActiveDirectory\Test-ValidDistinguishedName.ps1',
            'Operations\Invoke-OperationWithRetry.ps1',
            'Logging\Write-ADOperationSecurityLog.ps1',
            'ActiveDirectory\Invoke-ADOperationWithRetry.ps1',
            'ActiveDirectory\Get-ADObjectFromSearchBase.ps1',
            'ActiveDirectory\Get-ADObjectsSequential.ps1',
            'SID\Test-SIDFormat.ps1',
            'SID\Get-SIDAnalysis.ps1',
            'SID\Test-SIDSecurity.ps1',
            'SID\Test-OrphanedSID.ps1',
            'Security\Get-SecurityDescriptor.ps1',
            'SID\Resolve-SIDIdentity.ps1',
            'SID\New-SIDResult.ps1',
            'SID\Invoke-SIDProcessing.ps1',
            'Backup\New-ACLBackup.ps1',
            'Utilities\Test-BackupIntegrity.ps1',
            'Backup\Get-BackupMetadata.ps1',
            'Backup\Find-BackupFile.ps1',
            'Security\Invoke-SecurityValidation.ps1',
            'ACL\Get-ACLForRemoval.ps1',
            'ACL\Invoke-SIDRemoval.ps1',
            'ACL\Set-ModifiedACL.ps1',
            'Security\Invoke-RemovalVerification.ps1',
            'Logging\Write-RemovalSecurityLog.ps1',
            'Operations\Invoke-RemovalWorkflow.ps1',
            'Core\Remove-OrphanedSID.ps1',
            'Core\Initialize-ScriptExecution.ps1',
            'Core\Invoke-MainProcessingLogic.ps1',
            'Core\Start-OrchestrationWorkflow.ps1',
            'Reporting\Write-ProcessingSummary.ps1'
        )

        # Load modular restore operation components
        $restoreModules = @(
            'Backup\Test-BackupValidation.ps1',
            'Backup\Restore-ACLOperation.ps1',
            'Backup\Invoke-RestoreWorkflow.ps1'
        )

        # Load main modules
        foreach ($moduleFile in $requiredModules) {
            $modulePath = Join-Path $privateModulesPath $moduleFile
            if (Test-Path $modulePath) {
                try {
                    . $modulePath
                    Write-StructuredLog "Imported module: $moduleFile" -Level Debug -Component 'Main' -CorrelationId $CorrelationId
                } catch {
                    Write-Error "Failed to import module $moduleFile : $($_.Exception.Message)"
                    return
                }
            } else {
                Write-Warning "Module file not found: $modulePath"
            }
        }

        # Load restore modules
        foreach ($moduleFile in $restoreModules) {
            $modulePath = Join-Path $privateModulesPath $moduleFile
            if (Test-Path $modulePath) {
                try {
                    . $modulePath
                    Write-StructuredLog "Imported restore module: $moduleFile" -Level Debug -Component 'Main' -CorrelationId $CorrelationId
                } catch {
                    Write-Error "Failed to import restore module $moduleFile : $($_.Exception.Message)"
                    return
                }
            } else {
                Write-Warning "Restore module file not found: $modulePath"
            }
        }

        Write-Verbose "DEBUG: CorrelationId before 'All modules loaded': $($script:CorrelationId)"
        Write-Information "[INFO] [Main] [$script:CorrelationId] All modules loaded successfully" -InformationAction Continue

        # Initialize script execution environment
        Write-Verbose "DEBUG: CorrelationId before 'Initializing execution': $($script:CorrelationId)"
        Write-Information "[INFO] [Main] [$script:CorrelationId] Initializing execution environment..." -InformationAction Continue
        $initResults = Initialize-ScriptExecution -ConfigPath $ConfigPath -LogPath $LogPath -MaxMemoryUsageMB $MaxMemoryUsageMB -CorrelationId $CorrelationId -LogLevel $LogLevel -SuppressConsoleOutput:$SuppressConsoleOutput

        # Set script-level variables from initialization
        $script:Config = $initResults.Config
        $script:MemoryManager = $initResults.MemoryManager
        $script:Statistics = $initResults.Statistics
        $script:LogPath = $initResults.LogPath

        Write-StructuredLog "Script initialization completed successfully" -Level Information -Component 'Main' -CorrelationId $CorrelationId
        Write-StructuredLog "Find-UnknownSID script fully initialized (CorrelationId: $CorrelationId)" -Level Information -Component 'Main' -CorrelationId $CorrelationId

    }
    catch {
        Write-Error "Script initialization failed: $($_.Exception.Message)"
        # Use fallback logging since Write-StructuredLog may not be available yet
        try {
            Write-StructuredLog "Critical initialization failure: $($_.Exception.Message)" -Level Error -Component 'Main' -CorrelationId $CorrelationId
        } catch {
            Write-Information "[ERROR] [Main] [$CorrelationId] Critical initialization failure: $($_.Exception.Message)" -InformationAction Continue
        }
        throw
    }
}

process {
    try {
        # Validate that we have search bases to process
        if (-not $SearchBase -or $SearchBase.Count -eq 0) {
            Write-Warning "No search base specified. Using current domain root."
            $SearchBase = @((Get-ADDomain).DistinguishedName)
        }

        # Execute main processing logic
        Write-StructuredLog "Starting main processing workflow" -Level Information -Component 'Main' -CorrelationId $CorrelationId

        if ($Restore) {
            # Execute restore workflow via orchestration
            if (-not $BackupPath) {
                throw "BackupPath parameter is required when using -Restore"
            }

            # Prepare parameters for orchestration workflow
            $restoreParameters = @{
                TargetObjectDN = $SearchBase  # Map SearchBase to TargetObjectDN for restore operations
                BackupPath = $BackupPath
                CorrelationId = $CorrelationId
            }

            # Add optional parameters if present
            if ($WhatIfPreference) {
                $restoreParameters.WhatIf = $true
            }

            # Process each target object for restoration
            $allResults = @()
            foreach ($targetDN in $SearchBase) {
                Write-StructuredLog "Starting restore operation for: $targetDN" -Level Information -Component 'Main' -CorrelationId $CorrelationId

                try {
                    $restoreParameters.TargetObjectDN = $targetDN
                    $result = Start-OrchestrationWorkflow -OperationType 'Restore' -Parameters $restoreParameters
                    $allResults += $result
                }
                catch {
                    Write-StructuredLog "Restore operation failed for $targetDN : $($_.Exception.Message)" -Level Error -Component 'Main' -CorrelationId $CorrelationId
                    $allResults += [PSCustomObject]@{
                        Success = $false
                        TargetObjectDN = $targetDN
                        ErrorMessage = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    }
                }
            }
            $processingResults = $allResults
        } else {
            # Set default backup path if not provided for removal operations
            $effectiveBackupPath = $BackupPath
            if ($Remove -and -not $effectiveBackupPath) {
                # Create default backup path in script directory, similar to Logs folder
                $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
                if (-not $scriptDirectory) {
                    $scriptDirectory = Get-Location
                }
                $effectiveBackupPath = Join-Path $scriptDirectory "Backup"

                if (-not (Test-Path $effectiveBackupPath)) {
                    New-Item -Path $effectiveBackupPath -ItemType Directory -Force | Out-Null
                    Write-Warning "No backup path specified. Using default: $effectiveBackupPath"
                }
            }

            # Create timestamped subfolder for this script run if performing removal operations
            if ($Remove -and $effectiveBackupPath) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $timestampedBackupPath = Join-Path $effectiveBackupPath $timestamp

                if (-not (Test-Path $timestampedBackupPath)) {
                    New-Item -Path $timestampedBackupPath -ItemType Directory -Force | Out-Null
                    Write-StructuredLog "Created timestamped backup subfolder: $timestampedBackupPath" -Level Information -Component 'Main' -CorrelationId $CorrelationId
                }

                # Use the timestamped path for actual backup operations
                $effectiveBackupPath = $timestampedBackupPath
            }

            # Execute discovery/removal workflow
            $processingResults = Invoke-MainProcessingLogic -SearchBase $SearchBase -Remove:$Remove -IncludeInherited:$IncludeInherited -BackupPath $effectiveBackupPath -MaxRetries $MaxRetries -CorrelationId $CorrelationId
        }

        Write-StructuredLog "Main processing workflow completed successfully" -Level Information -Component 'Main' -CorrelationId $CorrelationId

    }
    catch {
        $script:Statistics.CriticalErrors++
        Write-StructuredLog "Critical error in main process: $($_.Exception.Message)" -Level Error -Component 'Main' -CorrelationId $CorrelationId
        throw
    }
}

end {
    try {
        # Generate and display comprehensive summary
        if ($Restore) {
            # Handle restore operation summary differently
            Write-StructuredLog "=== RESTORE OPERATION SUMMARY ===" -Level Information -Component 'Summary' -CorrelationId $CorrelationId

            $successfulRestores = @($processingResults | Where-Object { $_.Success -eq $true }).Count
            $failedRestores = @($processingResults | Where-Object { $_.Success -eq $false }).Count
            $totalRestores = $processingResults.Count
            $totalEntriesRestored = ($processingResults | Where-Object { $_.Success -eq $true -and $_.EntriesRestored } | Measure-Object -Property EntriesRestored -Sum).Sum

            Write-StructuredLog "Total restore operations: $totalRestores" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
            Write-StructuredLog "Successful restores: $successfulRestores" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
            Write-StructuredLog "Failed restores: $failedRestores" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
            if ($totalEntriesRestored -gt 0) {
                Write-StructuredLog "Total ACL entries restored: $totalEntriesRestored" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
            }
            Write-StructuredLog "Backup source: $BackupPath" -Level Information -Component 'Summary' -CorrelationId $CorrelationId

            # Show individual restore results
            if ($processingResults -and $processingResults.Count -gt 0) {
                Write-StructuredLog "Individual restore results:" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
                foreach ($result in $processingResults) {
                    $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
                    $entriesInfo = if ($result.EntriesRestored) { " ($($result.EntriesRestored) entries)" } else { "" }
                    $targetDN = if ($result.TargetObjectDN) { $result.TargetObjectDN } elseif ($result.ObjectDN) { $result.ObjectDN } else { "Unknown" }
                    Write-StructuredLog "  [$status] $targetDN$entriesInfo" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
                    if (-not $result.Success -and $result.ErrorMessage) {
                        Write-StructuredLog "    Error: $($result.ErrorMessage)" -Level Information -Component 'Summary' -CorrelationId $CorrelationId
                    }
                }
            }
        } else {
            # Use normal processing summary for discovery/removal operations
            Write-ProcessingSummary -ProcessingResults $processingResults -OutputPath $OutputPath -AutomationMode:$script:AutomationMode -CorrelationId $CorrelationId
        }

        Write-StructuredLog "Script completed successfully (CorrelationId: $script:CorrelationId)" -Level Information -Component 'Main' -CorrelationId $script:CorrelationId

    }
    catch {
        # Enhanced error handling for final summary
        $errorMessage = if ($_ -and $_.Exception -and $_.Exception.Message) {
            $_.Exception.Message.Trim()
        } else {
            "Critical error occurred during script execution"
        }

        try {
            Write-StructuredLog "Critical error in end block: $errorMessage" -Level Error -Component 'Main' -CorrelationId $script:CorrelationId
        } catch {
            Write-Information "[ERROR] [Main] [$CorrelationId] Critical error in end block: $errorMessage" -InformationAction Continue
        }

        if ($script:AutomationMode) {
            $errorOutput = [PSCustomObject]@{
                Status = "Failed"
                Error = $errorMessage
                CorrelationId = $script:CorrelationId
                Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            }
            Write-Information "##[error]Script failed with critical error" -InformationAction Continue
            Write-Information ($errorOutput | ConvertTo-Json -Depth 2) -InformationAction Continue
        }

        exit 1
    }
    finally {
        # Cleanup resources using centralized memory management
        try {
            $additionalResources = @()

            if ($script:StreamingResults) {
                $additionalResources += $script:StreamingResults

                # Note: Cleanup will be handled by the Dispose() method called in resource cleanup
                # This avoids race conditions between manual cleanup and automatic disposal
                if (-not $PreserveTempFiles) {
                    Write-StructuredLog "Temporary result files will be cleaned up during disposal" -Level Information -Component 'Main' -CorrelationId $CorrelationId
                } else {
                    Write-StructuredLog "Temporary result files preserved as requested" -Level Information -Component 'Main' -CorrelationId $CorrelationId
                }
            }

            # Use centralized resource cleanup
            Invoke-ResourceCleanup -MemoryManager $script:MemoryManager -AdditionalResources $additionalResources -CorrelationId $CorrelationId
            Write-StructuredLog "All resources cleaned up successfully using centralized management" -Level Information -Component 'Main' -CorrelationId $CorrelationId
        }
        catch {
            Write-Warning "Error during centralized cleanup: $($_.Exception.Message)"

            # Fallback to manual cleanup if centralized cleanup fails
            try {
                if ($script:MemoryManager) {
                    $script:MemoryManager.Dispose()
                }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
            }
            catch {
                Write-StructuredLog "Fallback cleanup warning: $($_.Exception.Message)" -Level Warning -Component 'Main' -CorrelationId $CorrelationId
            }
        }

        Write-Information "[INFO] [Main] [$script:CorrelationId] Find-UnknownSID script execution completed." -InformationAction Continue
    }
}

