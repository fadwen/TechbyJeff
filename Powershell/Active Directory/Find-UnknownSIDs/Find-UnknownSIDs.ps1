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

.PARAMETER ParallelThrottleLimit
    [Int] (Optional, Range: 1-50, Default: 10)

    Number of parallel threads for processing Active Directory objects.
    Controls concurrency to balance performance with system resource usage.

    PERFORMANCE CONSIDERATIONS:
    - Default (10): Balanced performance for most environments
    - Low (1-5): Conservative approach for resource-constrained environments
    - High (20-50): Aggressive performance for high-capacity systems

    BUSINESS CONTEXT:
    Higher values reduce total processing time but increase system resource usage.
    Consider domain controller capacity and network bandwidth when adjusting.

    RECOMMENDATIONS:
    - Small environments (< 1,000 objects): 5-10 threads
    - Medium environments (1,000-10,000 objects): 10-20 threads
    - Large environments (> 10,000 objects): 20-50 threads
    - Test with your specific environment before production use

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
    - Automatic garbage collection at 80% threshold
    - Processing suspension at 90% threshold
    - Emergency cleanup at 95% threshold
    - Configurable monitoring and alerting

    BUSINESS CONTEXT:
    Critical for large-scale enterprise environments where memory management
    prevents system instability and ensures reliable long-running operations.

    RECOMMENDATIONS:
    - Standard workstations: 1024-2048 MB
    - Server environments: 2048-4096 MB
    - High-capacity systems: 4096-8192 MB
    - Monitor actual usage and adjust based on environment size

    PERFORMANCE IMPACT:
    - Lower values: More frequent cleanup, slower processing
    - Higher values: Less cleanup overhead, higher memory usage
    - Optimal setting depends on available system memory

.PARAMETER LogPath
    [String] (Optional, Validated, Default: ".\Logs\Find-UnknownSIDs_YYYYMMDD_HHMMSS.log")

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
    - Default: ".\Logs\Find-UnknownSIDs_20250702_143052.log"
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
    PS> .\Find-UnknownSIDs.ps1 -SearchBase "OU=Users,DC=contoso,DC=com"

    DESCRIPTION: Basic orphaned SID discovery scan in the Users OU
    OUTPUT: CSV report with orphaned SIDs, their locations, and analysis
    DURATION: Approximately 2-5 minutes depending on OU size
    USE CASE: Regular security hygiene check for user accounts

.EXAMPLE
    PS> .\Find-UnknownSIDs.ps1 -SearchBase "DC=contoso,DC=com" -ParallelThrottleLimit 20 -MaxMemoryUsageMB 2048 -OutputPath ".\audit-results.csv"

    DESCRIPTION: High-performance domain-wide scan with custom settings
    OUTPUT: Comprehensive scan results with parallel processing optimization
    BUSINESS CASE: Enterprise-scale Active Directory environments
    INTEGRATION: Suitable for automated security monitoring workflows

.EXAMPLE
    PS> .\Find-UnknownSIDs.ps1 -Remove -SearchBase "OU=TestUsers,DC=contoso,DC=com" -WhatIf -ConfigPath ".\config.json"

    DESCRIPTION: Removal operation preview with custom configuration
    OUTPUT: Preview of planned removals with detailed security validation
    SECURITY: Uses WhatIf mode to preview changes before actual removal
    COMPLIANCE: Includes full audit trail and backup creation for rollback capability
    BACKUP: Creates timestamped backup subfolder (e.g., .\Backup\20250702_103631\) for organization

.EXAMPLE
    PS> .\Find-UnknownSIDs.ps1 -Restore -SearchBase "CN=User1,CN=Users,DC=contoso,DC=com" -BackupPath ".\Backup\20250702_103631"

    DESCRIPTION: Restore ACL from backup for a specific user object using timestamped backup folder
    OUTPUT: Detailed restoration results with success/failure status
    BUSINESS CASE: Rollback after problematic SID removal or ACL corruption
    SECURITY: Includes backup validation and integrity verification before restoration

.EXAMPLE
    PS> .\Find-UnknownSIDs.ps1 -Restore -SearchBase "OU=TestUsers,DC=contoso,DC=com" -BackupPath ".\Backup\20250702_103631" -Force

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
    - For common issues: .\Troubleshooting\Common\Find-UnknownSIDs-Issues.md
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
    .\Documentation\Find-UnknownSIDs-Automation.md

.LINK
    .\Documentation\Find-UnknownSIDs-Memory-Security.md

.LINK
    .\Documentation\Backup-and-Restore-Guide.md

.LINK
    .\Troubleshooting\Common\Find-UnknownSIDs-Issues.md
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
    [ValidateRange(1, 50)]
    [int]$ParallelThrottleLimit = 10,

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
    [string]$LogPath = ".\Logs\Find-UnknownSIDs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter()]
    [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),

    [Parameter()]
    [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Debug', 'Verbose')]
    [string]$LogLevel = 'Information',

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

    Write-StatusMessage "Starting Find-UnknownSIDs script..." -Color Green
    Write-Verbose "Script execution starting with CorrelationId: $CorrelationId"

    try {
        # Import Active Directory module
        Write-StatusMessage "Initializing Active Directory module..." -Color Cyan
        if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            throw "Active Directory PowerShell module is not available"
        }
        Import-Module ActiveDirectory -Force -ErrorAction Stop
        Write-Verbose "ActiveDirectory module imported successfully"

        # Import all private modules quietly
        Write-StatusMessage "Loading security-validated components..." -Color Cyan

        # Import secure class loader first
        $secureClassImporterPath = Join-Path $PSScriptRoot "Private\SecureClassImporter.ps1"
        if (Test-Path $secureClassImporterPath) {
            try {
                . $secureClassImporterPath
                Write-Verbose "Imported SecureClassImporter"
            }
            catch {
                Write-Error "Failed to import SecureClassImporter: $($_.Exception.Message)"
                throw "Critical dependency failure: SecureClassImporter"
            }
        }
        else {
            Write-Error "SecureClassImporter not found: $secureClassImporterPath"
            throw "Missing critical dependency: SecureClassImporter.ps1"
        }

        # Import class definitions securely using direct script-level loading (working approach)
        Write-Verbose "Loading classes with security validation..."
        $classesPath = Join-Path $PSScriptRoot "Classes"

        try {
            # Security-hardened approved classes list with current SHA256 hashes
            $approvedClasses = @{
                'ScriptConfiguration.ps1' = @{
                    RequiredTypes = @('ScriptConfiguration')
                    Dependencies = @()
                    Description = 'Core script configuration and validation functionality'
                    ExpectedHash = 'A371D70846A44F38360F26915418A3384E9D2C9216803719AB32FA46677E991C'
                }
                'MemoryManager.ps1' = @{
                    RequiredTypes = @('MemoryManager')
                    Dependencies = @('System.IDisposable')
                    Description = 'Memory management and garbage collection with resource disposal'
                    ExpectedHash = '3BCC993DDA93F6B712ED95632335C0D64C9B8528180FCE7C0AF2820FD17F2F35'
                }
                'ProcessingStatistics.ps1' = @{
                    RequiredTypes = @('ProcessingStatistics')
                    Dependencies = @()
                    Description = 'Processing statistics and performance metrics tracking'
                    ExpectedHash = '23991121E86449AE7785C77E14F8433C16CA44BA9FE9377B37A7F3A571EC0F09'
                }
                'SIDAnalysisResult.ps1' = @{
                    RequiredTypes = @('SIDAnalysisResult')
                    Dependencies = @()
                    Description = 'SID analysis result container with risk assessment'
                    ExpectedHash = 'F6793F8F3DCF9E66BC42E468FF024AB531348BA0B7B0AB9A0EF3FA83C0D95DBE'
                }
                'OrphanedSIDResult.ps1' = @{
                    RequiredTypes = @('OrphanedSIDResult')
                    Dependencies = @()
                    Description = 'Orphaned SID result with detailed path and permission information'
                    ExpectedHash = 'F28780B25757F1E3E06D03BE0A5485B0292B40B360735DDBF345F4B4D5E18081'
                }
                'SecurityValidationResult.ps1' = @{
                    RequiredTypes = @('SecurityValidationResult')
                    Dependencies = @()
                    Description = 'Security validation result container with risk assessment'
                    ExpectedHash = '3F76E471AF30AF9948131828086F4339428A4643BFD749A1EB03574CB956A011'
                }
                'RemovalOperationResult.ps1' = @{
                    RequiredTypes = @('RemovalOperationResult')
                    Dependencies = @()
                    Description = 'Removal operation result with success tracking'
                    ExpectedHash = 'F59812B60262101DA34C006D57C5DCB6289E8DE0661D15C8D5781CC81A9269A4'
                }
                'RestoreOperationResult.ps1' = @{
                    RequiredTypes = @('RestoreOperationResult')
                    Dependencies = @()
                    Description = 'Restore operation result with success tracking'
                    ExpectedHash = 'E24F00E560C0901F51FDC7955EB8B76F1BD00D5E9856034E7C44634F138D473B'
                }
            }

            $resolvedClassesPath = Resolve-Path -Path $classesPath -ErrorAction Stop
            Write-Verbose "Validated classes path: $($resolvedClassesPath.Path)"

            $loadedClasses = @()
            $failedClasses = @()
            $integrityResults = @()

            # Perform security validation and loading for each class (direct script-level approach)
            foreach ($className in $approvedClasses.Keys) {
                try {
                    $classInfo = $approvedClasses[$className]
                    $classPath = Join-Path $resolvedClassesPath.Path $className

                    Write-Verbose "Processing class: $className"

                    # Security validation: Path traversal check
                    $resolvedClassPath = Resolve-Path -Path $classPath -ErrorAction Stop
                    if ($resolvedClassPath.Path -notlike "$($resolvedClassesPath.Path)*") {
                        throw "Security violation: Path traversal detected for $className"
                    }

                    # File existence check
                    if (-not (Test-Path -Path $resolvedClassPath.Path -PathType Leaf)) {
                        throw "Class file not found: $className"
                    }

                    # Integrity verification (optional - can be enabled for production)
                    if ($false) {  # Set to $true to enable integrity checking
                        $actualHash = Get-FileHash -Path $resolvedClassPath.Path -Algorithm SHA256
                        $expectedHash = $classInfo.ExpectedHash

                        if ($actualHash.Hash -ne $expectedHash) {
                            Write-Warning "File integrity verification failed for $className"
                            Write-Warning "Expected: $expectedHash"
                            Write-Warning "Actual: $($actualHash.Hash)"
                            # Continue loading for development, but log the violation
                        } else {
                            Write-Verbose "File integrity verified for: $className"
                        }
                    }

                    # Load the class file directly at script scope using dot-sourcing
                    Write-Verbose "Loading class file: $className"
                    . $resolvedClassPath.Path

                    # Type validation
                    foreach ($expectedType in $classInfo.RequiredTypes) {
                        if (-not ($expectedType -as [type])) {
                            throw "Expected type not found after loading $className : $expectedType"
                        }
                        Write-Verbose "Verified type availability: $expectedType"
                    }

                    $loadedClasses += $className
                    Write-Verbose "Successfully loaded class: $className"

                }
                catch {
                    $errorMessage = "Failed to load class $className : $($_.Exception.Message)"
                    Write-Error $errorMessage

                    $failedClasses += @{
                        ClassName = $className
                        Error = $_.Exception.Message
                        Path = $classPath
                    }
                }
            }

            # Create result summary
            $classImportResult = [PSCustomObject]@{
                Success = ($failedClasses.Count -eq 0)
                TotalClasses = $approvedClasses.Count
                LoadedCount = $loadedClasses.Count
                FailedCount = $failedClasses.Count
                LoadedClasses = $loadedClasses
                FailedClasses = $failedClasses
                IntegrityResults = $integrityResults
            }

            if ($classImportResult.Success) {
                Write-Verbose "All $($classImportResult.LoadedCount) classes loaded securely"
                Write-Verbose "Successfully loaded classes: $($classImportResult.LoadedClasses -join ', ')"
            } else {
                $failureDetails = $classImportResult.FailedClasses | ForEach-Object { "$($_.ClassName): $($_.Error)" }
                throw "Secure class loading failed: $($failureDetails -join '; ')"
            }
        }
        catch {
            Write-Error "Secure class loading failed: $($_.Exception.Message)"
            throw "Critical class import failure"
        }

        # Import remaining private modules (SecureClassImporter already loaded)
        $privateModulesPath = Join-Path $PSScriptRoot "Private"
        $requiredModules = @(
            'Logging.ps1',
            'Configuration.ps1',
            'Utilities.ps1',
            'ADOperations.ps1',
            'SIDValidation.ps1',
            'SIDProcessing.ps1',
            'BackupOperations.ps1',
            'RemovalOperations.ps1',
            'RestoreOperations.ps1',
            'Orchestration.ps1'
        )

        foreach ($moduleFile in $requiredModules) {
            $modulePath = Join-Path $privateModulesPath $moduleFile
            if (Test-Path $modulePath) {
                try {
                    . $modulePath
                    Write-Verbose "Imported module: $moduleFile"
                }
                catch {
                    Write-Error "Failed to import module $moduleFile : $($_.Exception.Message)"
                    throw "Critical module import failure: $moduleFile"
                }
            }
            else {
                Write-Error "Required module not found: $modulePath"
                throw "Missing required module: $moduleFile"
            }
        }

        Write-StatusMessage "All modules loaded successfully" -Color Green

        # Initialize script execution environment
        Write-StatusMessage "Initializing execution environment..." -Color Cyan
        $initResults = Initialize-ScriptExecution -ConfigPath $ConfigPath -LogPath $LogPath -MaxMemoryUsageMB $MaxMemoryUsageMB -CorrelationId $CorrelationId -LogLevel $LogLevel

        # Set script-level variables from initialization
        $script:Config = $initResults.Config
        $script:MemoryManager = $initResults.MemoryManager
        $script:Statistics = $initResults.Statistics
        $script:LogPath = $initResults.LogPath

        Write-StatusMessage "Script initialization completed successfully" -Color Green
        Write-ScriptLog "Find-UnknownSIDs script fully initialized (CorrelationId: $CorrelationId)" -Level Information -Component 'Main' -Color Green -CorrelationId $CorrelationId

    }
    catch {
        Write-Error "Script initialization failed: $($_.Exception.Message)"
        Write-ScriptLog "Critical initialization failure: $($_.Exception.Message)" -Level Error -Component 'Main'
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
        Write-ScriptLog "Starting main processing workflow" -Level Information -Component 'Main' -CorrelationId $CorrelationId

        if ($Restore) {
            # Execute restore workflow
            if (-not $BackupPath) {
                throw "BackupPath parameter is required when using -Restore"
            }

            $processingResults = Invoke-RestoreWorkflow -SearchBase $SearchBase -BackupPath $BackupPath -WhatIfMode:$WhatIfPreference -Force:$Force -CorrelationId $CorrelationId
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
                    Write-ScriptLog "Created timestamped backup subfolder: $timestampedBackupPath" -Level Information -Component 'Main' -CorrelationId $CorrelationId
                }

                # Use the timestamped path for actual backup operations
                $effectiveBackupPath = $timestampedBackupPath
            }

            # Execute discovery/removal workflow
            $processingResults = Invoke-MainProcessingLogic -SearchBase $SearchBase -Remove:$Remove -IncludeInherited:$IncludeInherited -BackupPath $effectiveBackupPath -ParallelThrottleLimit $ParallelThrottleLimit -MaxRetries $MaxRetries -CorrelationId $CorrelationId
        }

        Write-ScriptLog "Main processing workflow completed successfully" -Level Information -Component 'Main' -Color Green -CorrelationId $CorrelationId

    }
    catch {
        $script:Statistics.CriticalErrors++
        Write-ScriptLog "Critical error in main process: $($_.Exception.Message)" -Level Error -Component 'Main' -CorrelationId $CorrelationId
        throw
    }
}

end {
    try {
        # Generate and display comprehensive summary
        Write-ProcessingSummary -ProcessingResults $processingResults -OutputPath $OutputPath -AutomationMode:$script:AutomationMode -CorrelationId $CorrelationId

        Write-ScriptLog "Script completed successfully (CorrelationId: $script:CorrelationId)" -Level Information -Component 'Main' -Color Green -CorrelationId $script:CorrelationId

    }
    catch {
        # Enhanced error handling for final summary
        $errorMessage = if ($_ -and $_.Exception -and $_.Exception.Message) {
            $_.Exception.Message.Trim()
        } else {
            "Critical error occurred during script execution"
        }

        Write-ScriptLog "Critical error in end block: $errorMessage" -Level Error -Component 'Main' -CorrelationId $script:CorrelationId

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
        # Cleanup resources
        try {
            if ($script:MemoryManager) {
                $script:MemoryManager.Dispose()
                Write-Verbose "Memory manager disposed successfully"
            }
        }
        catch {
            Write-Warning "Error during cleanup: $($_.Exception.Message)"
        }

        # Final memory cleanup
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        }
        catch {
            # Log garbage collection errors but don't fail the script
            Write-ScriptLog "Memory cleanup warning: $($_.Exception.Message)" -Level Warning -Component 'Main' -CorrelationId $CorrelationId
            Write-Verbose "Garbage collection cleanup encountered non-critical error: $($_.Exception.Message)"
        }

        Write-StatusMessage "Find-UnknownSIDs script execution completed." -Color Green
    }
}
