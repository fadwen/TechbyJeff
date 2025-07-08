#Requires -Version 5.1

function Get-ApprovedClassList {
    <#
    .SYNOPSIS
        Retrieves approved PowerShell class configuration with security metadata

    .DESCRIPTION
        Provides centralized management of approved class definitions, expected hashes,
        dependencies, and validation metadata. This module contains the authoritative
        list of classes that can be securely loaded by the class import system.

        Security Features:
        - Hardcoded approved class list (immune to external manipulation)
        - SHA256 integrity hashes for tamper detection
        - Dependency tracking for validation
        - Last verification timestamps for audit trails

    .PARAMETER ConfigurationVersion
        Specifies which version of the configuration to retrieve.
        Defaults to 'Current' for the most recent configuration.

    .PARAMETER CorrelationId
        Correlation ID for tracking and audit purposes. If not provided,
        a new GUID will be generated automatically.

    .EXAMPLE
        Get-ApprovedClassList

        DESCRIPTION: Retrieves the current approved class configuration
        OUTPUT: Hashtable with class definitions and security metadata
        USE CASE: Standard configuration retrieval for class loading operations

    .EXAMPLE
        $config = Get-ApprovedClassList -CorrelationId $correlationId
        Write-Output "Found $($config.Count) approved classes"

        DESCRIPTION: Retrieves configuration with correlation tracking
        OUTPUT: Configuration hashtable with audit correlation
        USE CASE: Enterprise environments requiring audit trail tracking

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable. Returns approved class configuration containing:
        - Class file names as keys
        - Configuration objects with RequiredTypes, Dependencies, Description, ExpectedHash, LastVerified

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        SECURITY CONSIDERATIONS:
        - Configuration is hardcoded to prevent external manipulation
        - Hash values are verified during integrity checking
        - All changes require code modification and deployment
        - Configuration is immutable at runtime for security

        TROUBLESHOOTING:
        - For configuration issues: .\Troubleshooting\Common\Configuration-Issues.md
        - For hash mismatches: .\Troubleshooting\Security\Integrity-Verification.md

        COMPLIANCE:
        - SOX: Supports change control requirements with immutable configuration
        - GDPR: No personal data processing in configuration management
        - Enterprise Security: Defense-in-depth with hardcoded security controls
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [ValidateSet('Current', 'Legacy', 'Development')]
        [string]$ConfigurationVersion = 'Current',

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    begin {
        Write-Verbose "Retrieving approved class configuration - Version: $ConfigurationVersion, CorrelationId: $CorrelationId"

        # Log configuration access
        if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
            Write-StructuredLog -Level Debug -Message "Accessing approved class configuration" -Component 'ClassConfiguration' -CorrelationId $CorrelationId
        }
    }

    process {
        try {
            # Approved class files with comprehensive metadata and integrity hashes
            # Generated and last verified: 2025-07-05 from Find-UnknownSID project class files
            $approvedClasses = @{
                'ScriptConfiguration.ps1' = @{
                    RequiredTypes = @('ScriptConfiguration')
                    Dependencies = @()
                    Description = 'Core script configuration and validation functionality'
                    ExpectedHash = 'A371D70846A44F38360F26915418A3384E9D2C9216803719AB32FA46677E991C'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 1
                }
                'MemoryManager.ps1' = @{
                    RequiredTypes = @('MemoryManager')
                    Dependencies = @('System.IDisposable')
                    Description = 'Memory management and garbage collection with resource disposal'
                    ExpectedHash = '6CEA50C8746F111AABE7397557FFABF805BF0BCF8997CECC3932E4FBC66744A4'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 2
                }
                'ProcessingStatistics.ps1' = @{
                    RequiredTypes = @('ProcessingStatistics')
                    Dependencies = @()
                    Description = 'Processing statistics and performance metrics tracking'
                    ExpectedHash = '23991121E86449AE7785C77E14F8433C16CA44BA9FE9377B37A7F3A571EC0F09'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 3
                }
                'OrphanedSIDResult.ps1' = @{
                    RequiredTypes = @('OrphanedSIDResult')
                    Dependencies = @()
                    Description = 'Results container for orphaned SID analysis operations'
                    ExpectedHash = 'F28780B25757F1E3E06D03BE0A5485B0292B40B360735DDBF345F4B4D5E18081'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 4
                }
                'SIDAnalysisResult.ps1' = @{
                    RequiredTypes = @('SIDAnalysisResult')
                    Dependencies = @()
                    Description = 'Results container for comprehensive SID analysis operations'
                    ExpectedHash = 'F6793F8F3DCF9E66BC42E468FF024AB531348BA0B7B0AB9A0EF3FA83C0D95DBE'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 5
                }
                'SecurityValidationResult.ps1' = @{
                    RequiredTypes = @('SecurityValidationResult')
                    Dependencies = @()
                    Description = 'Security validation results and compliance status tracking'
                    ExpectedHash = '3F76E471AF30AF9948131828086F4339428A4643BFD749A1EB03574CB956A011'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Enhanced'
                    LoadOrder = 6
                }
                'RemovalOperationResult.ps1' = @{
                    RequiredTypes = @('RemovalOperationResult')
                    Dependencies = @()
                    Description = 'Results container for SID removal operations with audit trail'
                    ExpectedHash = 'F59812B60262101DA34C006D57C5DCB6289E8DE0661D15C8D5781CC81A9269A4'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Enhanced'
                    LoadOrder = 7
                }
                'RestoreOperationResult.ps1' = @{
                    RequiredTypes = @('RestoreOperationResult')
                    Dependencies = @()
                    Description = 'Results container for restore operations with validation'
                    ExpectedHash = 'E24F00E560C0901F51FDC7955EB8B76F1BD00D5E9856034E7C44634F138D473B'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Enhanced'
                    LoadOrder = 8
                }
                'StreamingResultsManager.ps1' = @{
                    RequiredTypes = @('StreamingResultsManager')
                    Dependencies = @()
                    Description = 'Streaming results manager for large dataset processing with enhanced directory handling'
                    ExpectedHash = '4257B303E7BC4C34C566DB1B307907FB0392FE31AD3195A29FA0087EE7D55603'
                    LastVerified = '2025-07-05'
                    SecurityLevel = 'Standard'
                    LoadOrder = 9
                }
            }

            # Add metadata to configuration
            $configurationMetadata = @{
                Version = $ConfigurationVersion
                TotalClasses = $approvedClasses.Count
                GeneratedOn = '2025-07-05'
                LastUpdated = '2025-07-05'
                SecurityReview = '2025-07-02'
                CorrelationId = $CorrelationId
                ConfigurationHash = 'CONFIG-' + [System.Guid]::NewGuid().ToString().Substring(0, 8)
            }

            # Log successful configuration retrieval
            if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog -Level Debug -Message "Successfully retrieved approved class configuration" -Component 'ClassConfiguration' -CorrelationId $CorrelationId -Data @{
                    ClassCount = $approvedClasses.Count
                    Version = $ConfigurationVersion
                    ConfigurationHash = $configurationMetadata.ConfigurationHash
                }
            }

            Write-Verbose "Retrieved configuration for $($approvedClasses.Count) approved classes"

            # Return configuration with metadata
            return @{
                Classes = $approvedClasses
                Metadata = $configurationMetadata
            }
        }
        catch {
            $errorMessage = "Failed to retrieve approved class configuration: $($_.Exception.Message)"

            # Log error
            if (Get-Command Write-StructuredLog -ErrorAction SilentlyContinue) {
                Write-StructuredLog -Level Error -Message $errorMessage -Component 'ClassConfiguration' -CorrelationId $CorrelationId
            }

            Write-Error $errorMessage -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed approved class configuration retrieval - CorrelationId: $CorrelationId"
    }
}
