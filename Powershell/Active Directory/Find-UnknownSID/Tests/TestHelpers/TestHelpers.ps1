#Requires -Module Pester

<#
.SYNOPSIS
# Load only essential private functions needed for testing (avoid recursive loading that can hang)
$PrivateRoot = Join-Path $ProjectRoot "Private"
if (Test-Path $PrivateRoot) {
    # Load only core functions needed for Operations tests to prevent hanging
    $essentialFunctions = @(
        "Operations\Invoke-OperationWithRetry.ps1",
        "Operations\Invoke-RemovalWorkflow.ps1",
        "Core\Test-ValidDistinguishedName.ps1",
        "Utilities\Write-StructuredLog.ps1"
    )
    
    foreach ($functionPath in $essentialFunctions) {
        $fullPath = Join-Path $PrivateRoot $functionPath
        if (Test-Path $fullPath) {
            try {
                Write-Verbose "Loading essential function: $functionPath"
                . $fullPath        } catch {
            $errorMessage = $_.Exception.Message
            Write-Warning "Failed to load essential function $fullPath`: $errorMessage"
        }
        }
    }
}se test helper utilities and bootstrapper for Find-UnknownSID test suite

.DESCRIPTION
    Provides comprehensive test utilities, mock data generation, environment initialization,
    and helper functions for the Find-UnknownSID enterprise PowerShell testing framework.
    Consolidates both test data generation and project bootstrapping for enterprise compliance.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    Version: 2.0.0 - Enterprise Consolidated Edition
    PowerShell Version: 5.1+
#>

#region Project Bootstrapping Functions

# Ensure all functions are available for testing by loading project dependencies
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Load ActiveDirectoryMockFramework first to provide stub functions
$mockFrameworkPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Infrastructure\Mocks\ActiveDirectoryMockFramework.ps1"
if (Test-Path $mockFrameworkPath) {
    . $mockFrameworkPath
    Write-Verbose "ActiveDirectoryMockFramework loaded"
}

# Load critical logging functions first to ensure dependencies are met
$loggingRoot = Join-Path $ProjectRoot "Private\Logging"
if (Test-Path $loggingRoot) {
    Get-ChildItem $loggingRoot -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        try {
            Write-Verbose "Loading logging function: $($_.Name)"
            . $_.FullName
        } catch {
            Write-Warning "Failed to load logging function $($_.FullName): $($_.Exception.Message)"
        }
    }
}

# Load all private functions (skip Logging since it's already loaded)
$PrivateRoot = Join-Path $ProjectRoot "Private"
if (Test-Path $PrivateRoot) {
    Get-ChildItem $PrivateRoot -Recurse -Filter "*.ps1" | Where-Object { $_.Directory.Name -ne 'Logging' } | ForEach-Object {
        try {
            Write-Verbose "Loading private function: $($_.Name)"
            . $_.FullName
        } catch {
            Write-Warning "Failed to load $($_.FullName): $($_.Exception.Message)"
        }
    }
}

# Load all classes first (order matters)
$ClassesRoot = Join-Path $ProjectRoot "Classes"
if (Test-Path $ClassesRoot) {
    Get-ChildItem $ClassesRoot -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        try {
            Write-Verbose "Loading class: $($_.Name)"
            . $_.FullName
        } catch {
            Write-Warning "Failed to load class $($_.FullName): $($_.Exception.Message)"
        }
    }
}

# Create mock Find-UnknownSID module for tests that require it
if (-not (Get-Module Find-UnknownSID -ErrorAction SilentlyContinue)) {
    $null = New-Module -Name "Find-UnknownSID" -ScriptBlock {
        # Placeholder module for testing - export all test functions
        function Test-ModuleLoaded { return $true }
        
        # Export common functions that tests expect to mock
        function Write-Verbose { param($Message) }
        function Write-Information { param($MessageData) }
        function Write-Warning { param($Message) }
        function Write-Host { param($Object) }
        function Test-Path { param($Path) return $true }
        function New-Item { param($Path, $ItemType) return @{ FullName = $Path } }
        function Out-File { param($FilePath, $InputObject) }
        function Get-ADUser { param($Identity) return @{ Name = 'MockUser'; SamAccountName = 'mockuser' } }
        function Get-ADGroup { param($Identity) return @{ Name = 'MockGroup'; SamAccountName = 'mockgroup' } }
        
        Export-ModuleMember -Function *
    }
    Write-Verbose "Mock Find-UnknownSID module created"
}


function Initialize-TestEnvironmentBootstrap {
    <#
    .SYNOPSIS
        Initializes the complete test environment with project dependencies

    .DESCRIPTION
        Sets up the test environment with all required project functions, classes,
        and dependencies loaded. Creates global test environment context for
        enterprise testing scenarios.

    .PARAMETER ProjectRoot
        Root path of the Find-UnknownSID project

    .PARAMETER SuppressConsoleOutput
        Suppresses console output during initialization

    .PARAMETER CorrelationId
        Correlation ID for tracking test environment initialization
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),

        [Parameter()]
        [switch]$SuppressConsoleOutput,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    try {
        # Check critical functions
        $criticalFunctions = @(
            'Write-StructuredLogEntry',
            'Format-LogMessage',
            'Get-StringHash',
            'Test-BackupIntegrity',
            'Validate-BackupSignature'
        )

        $criticalFunctionStatus = @{}
        foreach ($func in $criticalFunctions) {
            $criticalFunctionStatus[$func] = (Get-Command $func -ErrorAction SilentlyContinue) -ne $null
        }

        # Set global test environment variables
        $global:TestEnvironment = [PSCustomObject]@{
            CorrelationId = $CorrelationId
            ProjectRoot = $ProjectRoot
            CriticalFunctionStatus = $criticalFunctionStatus
            LoadedAliases = @()
            InitializedAt = Get-Date
            Version = "2.0.0-Enterprise"
        }

        if (-not $SuppressConsoleOutput) {
            Write-Host "Enterprise test environment initialized with CorrelationId: $CorrelationId" -ForegroundColor Green
        }

        return $true
    } catch {
        Write-Error "Failed to initialize test environment: $($_.Exception.Message)"
        return $false
    }
}


function Get-TestEnvironmentStatus {
    <#
    .SYNOPSIS
        Gets the current test environment status

    .DESCRIPTION
        Returns information about the current test environment including
        loaded functions, correlation ID, and initialization status.
    #>
    [CmdletBinding()]
    param()

    if ($global:TestEnvironment) {
        return $global:TestEnvironment
    } else {
        return [PSCustomObject]@{
            CorrelationId = "Not initialized"
            CriticalFunctionStatus = @{}
            LoadedAliases = @()
            InitializedAt = $null
            Version = "Unknown"
        }
    }
}

# Initialize the test environment automatically when TestHelpers is loaded
Initialize-TestEnvironmentBootstrap -SuppressConsoleOutput

Write-Verbose "Enterprise test module loading complete"

#endregion Project Bootstrapping Functions

#region Test Data Generation Functions

function New-TestData {
    <#
    .SYNOPSIS
        Creates standardized test data for Find-UnknownSID tests

    .DESCRIPTION
        Generates consistent test data objects for use across all test scenarios.
        Supports various data types including SIDs, Distinguished Names, file paths,
        and configuration objects.

    .PARAMETER DataType
        Type of test data to generate

    .PARAMETER Count
        Number of test objects to generate (default: 1)

    .PARAMETER CorrelationId
        Correlation ID for tracking test data generation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SID', 'DistinguishedName', 'FilePath', 'Configuration', 'ADObject', 'SecurityDescriptor')]
        [string]$DataType,

        [Parameter()]
        [int]$Count = 1,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    switch ($DataType) {
        'SID' {
            $results = 1..$Count | ForEach-Object {
                $domainSID = "S-1-5-21-123456789-987654321-456789123"
                $rid = Get-Random -Minimum 1000 -Maximum 9999
                "$domainSID-$rid"
            }
        }

        'DistinguishedName' {
            $results = 1..$Count | ForEach-Object {
                "CN=TestUser$_,CN=Users,DC=testdomain,DC=local"
            }
        }

        'FilePath' {
            $results = 1..$Count | ForEach-Object {
                "C:\TestData\TestFile$_.xml"
            }
        }

        'Configuration' {
            $results = @{
                LogPath = "C:\Logs\Find-UnknownSID"
                MaxLogSizeMB = 10
                MemoryThresholdMB = 512
                EnableDetailedLogging = $true
                RetryCount = 3
                RetryDelaySeconds = 5
                CacheExpirationMinutes = 60
                ParallelProcessing = $true
                MaxConcurrentJobs = 10
                CorrelationId = $CorrelationId
            }
        }

        'ADObject' {
            $results = 1..$Count | ForEach-Object {
                @{
                    ObjectSid = New-TestData -DataType 'SID' -Count 1
                    Name = "TestUser$_"
                    SamAccountName = "testuser$_"
                    DistinguishedName = "CN=TestUser$_,CN=Users,DC=testdomain,DC=local"
                    ObjectClass = "user"
                    Enabled = $true
                    LastLogonDate = (Get-Date).AddDays(-7)
                    Created = (Get-Date).AddYears(-1)
                }
            }
        }

        'SecurityDescriptor' {
            $testSID = New-TestData -DataType 'SID' -Count 1
            $results = @{
                Owner = "TESTDOMAIN\Administrator"
                Group = "TESTDOMAIN\Domain Admins"
                Access = @(
                    @{
                        IdentityReference = "TESTDOMAIN\TestUser"
                        FileSystemRights = "FullControl"
                        AccessControlType = "Allow"
                        IsInherited = $false
                    },
                    @{
                        IdentityReference = $testSID
                        FileSystemRights = "ReadAndExecute"
                        AccessControlType = "Allow"
                        IsInherited = $false
                    }
                )
                Sddl = "O:BAG:BAD:(A;;FA;;;BA)(A;;0x1200a9;;;BU)"
            }
        }
    }

    return $results
}

#endregion Test Data Generation Functions

#region Test Helper Functions

function New-MockCredential {
    <#
    .SYNOPSIS
        Creates mock PSCredential objects for testing

    .DESCRIPTION
        Generates PSCredential objects with test usernames and passwords
        for use in credential-related tests.

    .PARAMETER Username
        Username for the credential (default: testuser)

    .PARAMETER Password
        Password for the credential (default: TestPassword123!)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Username = 'testuser',

        [Parameter()]
        [string]$Password = 'TestPassword123!'
    )

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    return [System.Management.Automation.PSCredential]::new($Username, $securePassword)
}


function Assert-SecurityLogged {
    <#
    .SYNOPSIS
        Asserts that security events were properly logged

    .DESCRIPTION
        Verifies that Write-SecurityLog was called with appropriate parameters
        for security event validation in tests.

    .PARAMETER EventType
        Expected security event type

    .PARAMETER Outcome
        Expected outcome (Success, Failure, Attempt)

    .PARAMETER ThreatLevel
        Expected threat level (None, Low, Medium, High, Critical)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Authentication', 'Authorization', 'DataAccess', 'DataValidation', 'ConfigurationChange', 'SecurityViolation')]
        [string]$EventType,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failure', 'Attempt')]
        [string]$Outcome,

        [Parameter()]
        [ValidateSet('None', 'Low', 'Medium', 'High', 'Critical')]
        [string]$ThreatLevel
    )

    $filterScript = {
        $SecurityEventType -eq $EventType -and $Outcome -eq $Outcome
    }

    if ($ThreatLevel) {
        $filterScript = {
            $SecurityEventType -eq $EventType -and
            $Outcome -eq $Outcome -and
            $SecurityContext.ThreatLevel -eq $ThreatLevel
        }
    }

    Assert-MockCalled Write-SecurityLog -ParameterFilter $filterScript -Scope It
}


function Assert-CorrelationTracked {
    <#
    .SYNOPSIS
        Asserts that correlation ID tracking is properly implemented

    .DESCRIPTION
        Verifies that functions properly accept, use, and return correlation IDs
        for enterprise audit trail requirements.

    .PARAMETER Result
        The result object to validate

    .PARAMETER ExpectedCorrelationId
        The expected correlation ID value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [Parameter(Mandatory)]
        [string]$ExpectedCorrelationId
    )

    $Result | Should -Not -BeNullOrEmpty -Because "Result object should not be null"
    $Result.CorrelationId | Should -Be $ExpectedCorrelationId -Because "Correlation ID should be preserved throughout operation"
}


function Assert-PerformanceWithinSLA {
    <#
    .SYNOPSIS
        Asserts that operation performance meets SLA requirements

    .DESCRIPTION
        Validates that operations complete within acceptable time limits
        and resource usage constraints.

    .PARAMETER Duration
        The measured duration of the operation

    .PARAMETER MaxSeconds
        Maximum acceptable duration in seconds

    .PARAMETER MemoryBefore
        Memory usage before operation (optional)

    .PARAMETER MemoryAfter
        Memory usage after operation (optional)

    .PARAMETER MaxMemoryIncreaseMB
        Maximum acceptable memory increase in MB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [TimeSpan]$Duration,

        [Parameter(Mandatory)]
        [double]$MaxSeconds,

        [Parameter()]
        [long]$MemoryBefore,

        [Parameter()]
        [long]$MemoryAfter,

        [Parameter()]
        [int]$MaxMemoryIncreaseMB = 10
    )

    $Duration.TotalSeconds | Should -BeLessThan $MaxSeconds -Because "Operation should complete within SLA time limit"

    if ($MemoryBefore -and $MemoryAfter) {
        $memoryIncreaseMB = ($MemoryAfter - $MemoryBefore) / 1MB
        $memoryIncreaseMB | Should -BeLessThan $MaxMemoryIncreaseMB -Because "Memory usage should remain within acceptable limits"
    }
}


function New-TestEnvironment {
    <#
    .SYNOPSIS
        Sets up isolated test environment

    .DESCRIPTION
        Creates temporary directories, configuration files, and other
        resources needed for integration testing.

    .PARAMETER TempPath
        Base path for temporary test files

    .PARAMETER CorrelationId
        Correlation ID for test environment tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TempPath = $TestDrive,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $testEnv = @{
        BasePath = $TempPath
        LogPath = Join-Path $TempPath 'Logs'
        BackupPath = Join-Path $TempPath 'Backups'
        OutputPath = Join-Path $TempPath 'Output'
        ConfigPath = Join-Path $TempPath 'Config'
        CorrelationId = $CorrelationId
        CreatedAt = Get-Date
    }

    # Create directory structure
    foreach ($path in @($testEnv.LogPath, $testEnv.BackupPath, $testEnv.OutputPath, $testEnv.ConfigPath)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    # Create test configuration file
    $testConfig = New-TestData -DataType 'Configuration' -CorrelationId $CorrelationId
    $testConfig.LogPath = $testEnv.LogPath
    $configFile = Join-Path $testEnv.ConfigPath 'test-config.json'
    $testConfig | ConvertTo-Json | Out-File $configFile

    $testEnv.ConfigFile = $configFile

    return $testEnv
}


function Remove-TestEnvironment {
    <#
    .SYNOPSIS
        Cleans up test environment resources

    .DESCRIPTION
        Removes temporary files and directories created during testing.

    .PARAMETER Environment
        Test environment object from New-TestEnvironment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Environment
    )

    if (Test-Path $Environment.BasePath) {
        try {
            Remove-Item $Environment.BasePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore cleanup errors in tests
            Write-Verbose "Test cleanup warning: $($_.Exception.Message)"
        }
    }
}


function Measure-TestPerformance {
    <#
    .SYNOPSIS
        Measures test performance with detailed metrics

    .DESCRIPTION
        Provides comprehensive performance measurement including execution time,
        memory usage, and resource utilization for test validation.

    .PARAMETER ScriptBlock
        The code to measure

    .PARAMETER Name
        Name of the operation being measured
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        [Parameter()]
        [string]$Name = 'Operation'
    )

    $memoryBefore = [System.GC]::GetTotalMemory($false)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $result = & $ScriptBlock
    }
    finally {
        $stopwatch.Stop()
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        $memoryAfter = [System.GC]::GetTotalMemory($false)
    }

    return @{
        Result = $result
        Duration = $stopwatch.Elapsed
        MemoryBefore = $memoryBefore
        MemoryAfter = $memoryAfter
        MemoryUsedMB = ($memoryAfter - $memoryBefore) / 1MB
        Name = $Name
    }
}


function Import-TestModule {
    <#
    .SYNOPSIS
        Imports Find-UnknownSID modules for testing

    .DESCRIPTION
        Safely imports the main module and private functions with
        proper error handling and dependency management.

    .PARAMETER ModulePath
        Path to the main module file

    .PARAMETER PrivatePath
        Path to private functions directory
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ModulePath,

        [Parameter()]
        [string]$PrivatePath
    )

    if ($ModulePath -and (Test-Path $ModulePath)) {
        try {
            Import-Module $ModulePath -Force -Global
        }
        catch {
            Write-Warning "Failed to import main module: $($_.Exception.Message)"
        }
    }

    if ($PrivatePath -and (Test-Path $PrivatePath)) {
        # Load only essential functions to prevent hanging
        $essentialFunctions = @(
            "Operations\Invoke-OperationWithRetry.ps1",
            "Operations\Invoke-RemovalWorkflow.ps1",
            "Core\Test-ValidDistinguishedName.ps1",
            "Utilities\Write-StructuredLog.ps1"
        )
        
        foreach ($functionPath in $essentialFunctions) {
            $fullPath = Join-Path $PrivatePath $functionPath
            if (Test-Path $fullPath) {
                try {
                    . $fullPath
                } catch {
                    $errorMessage = $_.Exception.Message
                    Write-Warning "Failed to import $functionPath`: $errorMessage"
                }
            }
        }
    }
}


# Test helper functions are available when dot-sourced
# No explicit exports needed for dot-sourced files

#endregion Test Helper Functions

Write-Verbose "TestHelpers.ps1 v2.0.0 Enterprise Edition loaded successfully"
