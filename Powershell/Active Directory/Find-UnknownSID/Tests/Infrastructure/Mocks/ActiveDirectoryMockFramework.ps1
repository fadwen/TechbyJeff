# Simple Mock Framework for Find-UnknownSID Tests
# This provides stub functions that can be used outside of Pester context

# Core logging functions
function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [string]$Level = "Information",
        
        [Parameter()]
        [string]$Component = "General",
        
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString(),
        
        [Parameter()]
        [hashtable]$Data = @{}
    )
    # Mock implementation - do nothing but accept parameters
    Write-Verbose "Mock: Write-StructuredLog - $Level - $Message"
}

function Write-StructuredLogEntry {
    [CmdletBinding()]
    param(
        [string]$Message = "",
        [string]$Level = "INFO",
        [string]$Component = "",
        [string]$CorrelationId = ""
    )
    Write-Verbose "Mock: Write-StructuredLogEntry - $Level [$Component]: $Message"
}

function Format-LogMessage {
    [CmdletBinding()]
    param(
        [string]$Message = "",
        [string]$Level = "INFO",
        [string]$Component = "",
        [string]$CorrelationId = "",
        [hashtable]$AdditionalData = @{}
    )
    # Mock implementation - return simple formatted string
    return "[$Level] $Component`: $Message"
}

# Memory management functions
function Get-MemoryStatistics {
    [CmdletBinding()]
    param(
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    return [PSCustomObject]@{
        TotalMemoryMB = 1024
        UsedMemoryMB = 512
        AvailableMemoryMB = 512
        ProcessMemoryMB = 128
        CorrelationId = $CorrelationId
    }
}

function Initialize-MemoryManager {
    [CmdletBinding()]
    param(
        [int]$MaxMemoryMB = 1024,
        [int]$CheckInterval = 30
    )
    return $true
}

function Invoke-GarbageCollection {
    [CmdletBinding()]
    param(
        [int]$Generation = 0,
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    return [PSCustomObject]@{
        MemoryBefore = 512
        MemoryAfter = 256
        TimingMs = 100
        Generation = $Generation
    }
}

function Invoke-MemoryMonitoring {
    [CmdletBinding()]
    param(
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    return [PSCustomObject]@{
        Status = 'Normal'
        MemoryUsage = 50
        WarningThreshold = 75
        CriticalThreshold = 90
    }
}

function Write-StatusMessage {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )
    Write-Host "$Message" -ForegroundColor Green
}

function Invoke-ResourceDisposal {
    [CmdletBinding()]
    param(
        [object[]]$Objects,
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )
    return $true
}

# Reporting functions
function Write-ProcessingSummary {
    [CmdletBinding()]
    param(
        [hashtable]$Statistics,
        [string]$OutputFormat = "Console",
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )
    Write-Output "Processing summary generated"
}

# Active Directory functions (removed duplicate definition)

function New-ACLBackup {
    [CmdletBinding()]
    param(
        [string]$ObjectDN,
        [string]$BackupPath,
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )
    return "backup-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
}

function Test-ADPermission {
    [CmdletBinding()]
    param(
        [string]$ObjectDN,
        [string]$Permission = "ReadProperty",
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )
    return $true
}

function Get-PerformanceStatistics {
    [CmdletBinding()]
    param(
        [string]$CorrelationId = [guid]::NewGuid().ToString()
    )

    return [PSCustomObject]@{
        ProcessingTime = 1000
        ThroughputPerSecond = 10
        MemoryPeakMB = 256
        ErrorRate = 0.05
    }
}

Write-Verbose "Simple mock framework loaded successfully"

# Additional Mock Functions for Missing Dependencies (removed duplicate definition)

function Invoke-RestoreWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [Parameter(Mandatory)]
        [string]$ObjectDN,
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    return [PSCustomObject]@{
        PSTypeName = 'RestoreOperationResult'
        Success = $true
        ObjectDN = $ObjectDN
        BackupPath = $BackupPath
        CorrelationId = $CorrelationId
    }
}


# Add missing class types for test compatibility
if (-not ('RemovalOperationResult' -as [Type])) {
    Add-Type -TypeDefinition @"
        public class RemovalOperationResult {
            public string ObjectDN { get; set; }
            public string SID { get; set; }
            public bool Success { get; set; }
            public string Message { get; set; }
            public System.DateTime Timestamp { get; set; }
            public string CorrelationId { get; set; }
            public RemovalOperationResult() {
                Timestamp = System.DateTime.Now;
                Success = false;
            }
        }
"@
}

# Mock [System.GC] static methods
function Invoke-GarbageCollection {
    param(
        [Parameter()]
        [int]$Generation = -1,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    # Simulate garbage collection
    $beforeMemory = [System.GC]::GetTotalMemory($false)
    [System.GC]::Collect()
    if ($Force) {
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
    }
    $afterMemory = [System.GC]::GetTotalMemory($false)

    return [PSCustomObject]@{
        BeforeMemory = $beforeMemory
        AfterMemory = $afterMemory
        MemoryFreed = $beforeMemory - $afterMemory
        Generation = $Generation
        Force = $Force.IsPresent
        CorrelationId = $CorrelationId
        Timestamp = Get-Date
    }
}

# Global variable to track mock calls
$Global:MockCallHistory = @{}

# Global variable to control mock error behavior  
$Global:MockShouldThrow = $null

# Function to set mock error behavior
function Set-MockErrorBehavior {
    param([string]$ErrorMessage)
    $Global:MockShouldThrow = $ErrorMessage
}

# Mock missing AD operation functions with call tracking
function Invoke-ADOperationWithRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    # Track the call
    $functionName = 'Invoke-ADOperationWithRetry'
    if (-not $Global:MockCallHistory.ContainsKey($functionName)) {
        $Global:MockCallHistory[$functionName] = 0
    }
    $Global:MockCallHistory[$functionName]++

    # For Get-Acl operations, return a mock ACL
    if ($ScriptBlock.ToString() -match 'Get-Acl') {
        # Check for error scenarios first
        if ($Global:MockShouldThrow -eq "Access denied") {
            $Global:MockShouldThrow = $null  # Reset after use
            throw "Access denied"
        }
        
        $mockAccess = @(
            [PSCustomObject]@{
                IdentityReference = [PSCustomObject]@{ Value = "S-1-5-21-1234567890-1234567890-1234567890-1001" }
                AccessControlType = "Allow"
                ActiveDirectoryRights = "ReadProperty"
                InheritanceType = "All"
                ObjectType = [System.Guid]::Empty
                InheritedObjectType = [System.Guid]::Empty
            }
        )
        
        $mockAcl = [PSCustomObject]@{
            Path = "AD:\CN=TestObject,DC=domain,DC=com"
            Owner = "DOMAIN\Administrator"
            Group = "DOMAIN\Domain Admins"
            Access = $mockAccess
            PSTypeName = 'System.Security.AccessControl.DirectorySecurity'
        }
        
        # Add RemoveAccessRuleSpecific method for SID removal operations
        $mockAcl | Add-Member -MemberType ScriptMethod -Name "RemoveAccessRuleSpecific" -Value {
            param($ace)
            # Mock implementation - remove the ACE from Access array
            $this.Access = @($this.Access | Where-Object { $_.IdentityReference.Value -ne $ace.IdentityReference.Value })
        }
        
        return $mockAcl
    }

    # For Set-Acl operations, check for error scenarios
    if ($ScriptBlock.ToString() -match 'Set-Acl') {
        # Add some processing time to simulate real ACL operations
        Start-Sleep -Milliseconds 50
        
        # Check if this should simulate an error
        $pathMatch = if ($ScriptBlock.ToString() -match 'AD:\\(.+?)["\'']') { $matches[1] } else { "" }
        
        # Simulate Access denied for C:\Restricted
        if ($pathMatch -match "C:\\Restricted") {
            throw "Access denied"
        }
        
        # Simulate specific error message for certain test cases
        if ($Global:MockShouldThrow -eq "Access denied") {
            $Global:MockShouldThrow = $null  # Reset after use
            throw "Access denied"
        }
        
        if ($Global:MockShouldThrow -eq "Specific error message") {
            $Global:MockShouldThrow = $null  # Reset after use
            throw "Specific error message"
        }
        
        # Simulate successful execution - Set-Acl doesn't return anything on success
        return
    }

    # For other operations, execute the script block
    try {
        return & $ScriptBlock
    } catch {
        Write-Warning "Mock Invoke-ADOperationWithRetry: $($_.Exception.Message)"
        throw
    }
}

# Function to get mock call count
function Get-MockCallCount {
    param([string]$FunctionName)
    if ($Global:MockCallHistory.ContainsKey($FunctionName)) {
        return $Global:MockCallHistory[$FunctionName]
    } else {
        return 0
    }
}

# Function to reset mock call history
function Reset-MockCallHistory {
    $Global:MockCallHistory = @{}
    $Global:MockShouldThrow = $null
}

# Mock Active Directory utility functions
function Test-ObjectDN {
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDN
    )
    
    # Track the call
    $functionName = 'Test-ObjectDN'
    if (-not $Global:MockCallHistory.ContainsKey($functionName)) {
        $Global:MockCallHistory[$functionName] = 0
    }
    $Global:MockCallHistory[$functionName]++
    
    # Mock implementation - return false for specific test cases
    if ($ObjectDN -match "NonExistent") { return $false }
    if ($ObjectDN -match "C:\\Restricted") { return $true }  # This path exists but will fail later with access denied
    if ($ObjectDN -match "\.\." -and $ObjectDN -match "System32") { return $true }  # Path traversal - let it through so the function can detect it
    
    # Default to true for valid-looking DN patterns
    return $true
}

# Mock backup function
function New-ACLBackup {
    param(
        [Parameter(Mandatory)]
        [string]$ObjectDN,
        
        [Parameter(Mandatory)]
        [PSObject]$ACL,
        
        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    # Track the call
    $functionName = 'New-ACLBackup'
    if (-not $Global:MockCallHistory.ContainsKey($functionName)) {
        $Global:MockCallHistory[$functionName] = 0
    }
    $Global:MockCallHistory[$functionName]++
    
    # Mock successful backup creation
    return @{
        Success = $true
        BackupPath = "C:\Backup\test_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
        Timestamp = Get-Date
        CorrelationId = $CorrelationId
    }
}

