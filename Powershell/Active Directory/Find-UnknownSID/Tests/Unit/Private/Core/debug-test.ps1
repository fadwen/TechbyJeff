# Debug test to check MemoryManager properties

# Set up the stubs
function global:Write-StructuredLog { param($Level, $Message, $Component, $Operation, $CorrelationId) }
function global:ScriptConfiguration { 
    param($ConfigPath)
    return @{
        Settings = @{
            MemoryThresholdMB = 100
            EnableAuditTrail = $true
            BatchSize = 100
            MaxRetryAttempts = 3
            RetryDelaySeconds = 5
            AuditTrailEnabled = $true
            SecurityValidationLevel = 'Standard'
        }
        IsValid = $true
        MemoryCheckInterval = 30
        ValidateConfiguration = { return $true }
    }
}

function global:Initialize-LoggingSystem { 
    param($CorrelationId, $LogLevel, [switch]$SuppressConsoleOutput) 
    return @{ 
        Success = $true 
        LoggingSystem = [PSCustomObject]@{ 
            Level = $LogLevel 
            IsInitialized = $true
            SuppressConsoleOutput = $SuppressConsoleOutput.IsPresent
            CorrelationId = $CorrelationId
        } 
    }
}

function global:Initialize-MemoryManager { 
    param($MaxMemoryMB, $CheckInterval, $CorrelationId)
    Write-Host "Creating MemoryManager with MaxMemoryMB: $MaxMemoryMB"
    $memMgr = [PSCustomObject]@{ 
        ThresholdMB = $MaxMemoryMB 
        IsInitialized = $true
        CheckInterval = $CheckInterval
        CurrentUsageMB = 0
    }
    Write-Host "MemoryManager Properties: $($memMgr.PSObject.Properties.Name -join ', ')"
    return @{ 
        Success = $true 
        MemoryManager = $memMgr
    }
}

# Load the actual function
. "c:\Users\Administrator\TechbyJeff\Powershell\Active Directory\Find-UnknownSID\Private\Core\Initialize-ScriptExecution.ps1"

# Test it
Write-Host "Testing Initialize-ScriptExecution..."
$result = Initialize-ScriptExecution -ConfigPath "test.json"
Write-Host "Result Success: $($result.Success)"
Write-Host "MemoryManager Type: $($result.MemoryManager.GetType().Name)"
Write-Host "MemoryManager Properties: $($result.MemoryManager.PSObject.Properties.Name -join ', ')"
Write-Host "Has IsInitialized: $($result.MemoryManager.PSObject.Properties.Name -contains 'IsInitialized')"
